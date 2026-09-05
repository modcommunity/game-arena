class_name ArenaNetBridge
extends Node

## Joins [ArenaGame] to a [DotNetManager]. The netcode seam, and the only file in
## game-arena that names both.
##
## [b]Every other join in this project is a few lines because the addons refuse to
## know about each other; this one is a file because the ordering is the hard part.[/b]
## dot-net drives simulation per entity, and this game's tick order is a whole-game
## property — everybody moves, then every shot is resolved against the world as it is
## afterwards, then the match clock runs. Those two facts have to be reconciled
## somewhere, and this is where.
##
## [codeblock]
## # server
## bridge.attach(game, net)
## bridge.add_player(peer_id, session_id, "Ada")
## bridge.server_tick(tick)                      # instead of game.tick()
##
## # client
## bridge.attach(game, net)
## bridge.apply_join(join_bytes)                 # from the server
## socket.send(bridge.encode_input(tick, move, fire))
## bridge.receive_snapshot(payload)
## bridge.client_tick(tick, move, fire)
## [/codeblock]

const CHANNEL := "arena.net"

## Bytes [method DotNetManager.encode_ack] produces, and the prefix of every input
## packet. Fixed width, so the command that follows starts at a known offset.
const ACK_BYTES := 4

## Announced a player. Server side: these bytes go to every client.
signal player_announced(payload: PackedByteArray)

var game: ArenaGame = null
var net: DotNetManager = null

## player id -> ArenaPlayerNet, for the ones this process knows about.
var _behaviours: Dictionary = {}

## peer id -> player id.
var _players_by_peer: Dictionary = {}

var _game_ticked_for: int = -1
var _tick: int = 0


## Binds a game and a manager to each other.
func attach(p_game: ArenaGame, p_net: DotNetManager) -> DotResult:
	if p_game == null or p_net == null:
		return DotResult.fail(DotError.CODE_INVALID, "A bridge needs both halves.")

	if p_game.is_authority != p_net.is_server:
		# A game that thinks it is authoritative behind a client manager would
		# resolve its own hits; a server whose game is not authoritative would
		# resolve nobody's. Both are silent, and both are unplayable.
		return DotResult.fail(
			DotError.CODE_STATE,
			"The game and the manager disagree about who is authoritative.",
			"game.is_authority=%s, net.is_server=%s"
				% [p_game.is_authority, p_net.is_server]
		)

	game = p_game
	net = p_net
	return DotResult.success(self)


# --- Membership ------------------------------------------------------------

## Adds a player and makes them a replicated entity. Server side.
##
## [param session_id] is the id everything downstream uses — the scoreboard key, the
## combat entity id, the damage attribution and the loadout key. [b]It is not the peer
## id.[/b] A peer id is reassigned the moment someone reconnects, and everything keyed
## by one would be handed to the next player to join.
func add_player(peer_id: int, session_id: int, display_name: String) -> DotResult:
	if net == null or not net.is_server:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only the server adds players.")

	var added := game.add_player(session_id, display_name)

	if not added.ok:
		return added

	# Before registering, not after: the manager only builds snapshots for peers it
	# knows about and only holds an input buffer for those, so an entity registered
	# to an unknown peer is an entity nothing is ever sent about and nothing can be
	# driven by. It is silent — the server simulates it perfectly and alone.
	net.add_peer(peer_id)

	var identity := _build_identity(added.value as ArenaPlayer, peer_id)
	var registered := net.registry.register(identity, 0, net.clock.tick, net.config)

	if not registered.ok:
		net.remove_peer(peer_id)
		game.remove_player(session_id)
		return registered

	_players_by_peer[peer_id] = session_id
	player_announced.emit(join_payload(session_id))

	return DotResult.success(identity)


## Mirrors a player the server has announced. Client side.
func mirror_player(
	net_id: int,
	peer_id: int,
	session_id: int,
	display_name: String
) -> DotResult:
	if net == null or net.is_server:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only a client mirrors.")

	if _behaviours.has(session_id):
		return DotResult.success(_behaviours[session_id])

	var added := game.add_player(session_id, display_name)

	if not added.ok:
		return added

	var identity := _build_identity(added.value as ArenaPlayer, peer_id)
	var registered := net.registry.register(identity, net_id, net.clock.tick, net.config)

	if not registered.ok:
		game.remove_player(session_id)
		return registered

	_players_by_peer[peer_id] = session_id
	return DotResult.success(identity)


## Builds the identity and behaviour that make an [ArenaPlayer] replicate.
##
## The behaviour is added before the identity on purpose: [DotNetIdentity] collects
## its behaviours in [code]_ready[/code], by walking the entity's subtree, and a
## behaviour added afterwards would never be found — the entity would register with
## nothing to replicate and simply never move on any other machine.
func _build_identity(player: ArenaPlayer, peer_id: int) -> DotNetIdentity:
	var behaviour := ArenaPlayerNet.new()
	behaviour.name = "Net"
	behaviour.player = player
	behaviour.bridge = self
	player.add_child(behaviour)

	var identity := DotNetIdentity.new()
	identity.name = "Identity"
	identity.owner_peer_id = peer_id
	# SHARED, not SERVER: the server stays authoritative and corrects, and the owning
	# client predicts. `DotNetIdentity.is_predicted()` is false for any other
	# authority, so SERVER would mean a client that sees its own movement a full
	# round trip late — noticeable at 80 ms and unplayable at 150.
	identity.authority = DotNetIdentity.Authority.SHARED
	player.add_child(identity)

	_behaviours[player.player_id] = behaviour
	return identity


## Drops a peer's player from the game and from replication.
func remove_peer(peer_id: int) -> void:
	if not _players_by_peer.has(peer_id):
		return

	var session_id := int(_players_by_peer[peer_id])
	_players_by_peer.erase(peer_id)
	_behaviours.erase(session_id)

	if net != null:
		if net.is_server:
			# Releases the peer's entities, its input buffer and its acknowledgement
			# record in one place, so nothing is left keyed by a peer id that the
			# next player to connect will be given.
			net.remove_peer(peer_id)
		else:
			for identity in net.registry.take_owned_by(peer_id):
				net.registry.unregister(identity.net_id)

	game.remove_player(session_id)


func behaviour_for(session_id: int) -> ArenaPlayerNet:
	return _behaviours.get(session_id)


func session_for_peer(peer_id: int) -> int:
	return int(_players_by_peer.get(peer_id, 0))


# --- The tick --------------------------------------------------------------

## One authoritative tick. Server side, and it replaces [method ArenaGame.tick].
##
## [method DotNetManager.server_tick] hands each peer's input to the entities it owns,
## simulates, records history for lag compensation and sends snapshots — in that
## order, and the game tick has to happen between the first two. It does, from
## [method ArenaPlayerNet._net_simulate], through [method ensure_game_ticked].
##
## The call afterwards is not redundant. A server with no players registered runs no
## behaviours at all, and the match clock still has to advance — otherwise an empty
## server's warmup never ends and the first player to join arrives into a match that
## has been frozen since it booted.
func server_tick(tick: int) -> void:
	_tick = tick
	_game_ticked_for = -1

	if net != null:
		net.server_tick(tick)

	ensure_game_ticked(tick)


## Runs the whole game for a tick, at most once.
##
## Called from every replicated player's [code]_net_simulate[/code]; the first one
## through does the work.
func ensure_game_ticked(tick: int) -> void:
	if _game_ticked_for == tick or game == null:
		return

	_game_ticked_for = tick
	game.tick(_commands())


## The command table [method ArenaGame.tick] takes, built from what each peer sent.
func _commands() -> Dictionary:
	var out: Dictionary = {}

	for session_id in _behaviours:
		var behaviour: ArenaPlayerNet = _behaviours[session_id]
		out[int(session_id)] = [behaviour.last_move, behaviour.last_fire]

	return out


## One client tick: record the local command, predict, reconcile.
##
## The command is recorded into the behaviour and into the manager's input history
## before predicting, because reconciliation replays that history — an input the
## buffer never saw is a tick the replay cannot reproduce, and the correction is then
## measured against a state the server never computed.
func client_tick(tick: int, move: DotFpsCommand, fire: DotCombatCommand) -> void:
	_tick = tick

	if net == null or net.is_server:
		return

	var command := ArenaNetCommand.new()
	command.tick = tick
	command.delta = net.clock.tick_duration()
	command.move = move
	command.fire = fire

	net.local_inputs().push(command)

	for identity in net.registry.predicted():
		for behaviour in identity.behaviours:
			if behaviour.has_method("_net_apply_input"):
				behaviour.call("_net_apply_input", command, tick)
			behaviour._net_simulate(tick, net.clock.tick_duration())


## Applies a snapshot. Client side.
##
## [b]Reconciliation is [DotNetManager]'s, not this file's.[/b]
## [method DotNetManager.receive_snapshot] already routes a predicted entity's state to
## [method DotNetPredictor.reconcile] rather than applying it — applying it directly would
## undo everything predicted since — and acknowledges the inputs that state covers.
##
## This used to do a second pass on top of that, reconciling against
## [method DotNetBehaviour.snapshot_values] which by then held values that had [i]already[/i]
## been rewound and replayed. The inputs were therefore replayed twice, and one correction
## became two. Nothing failed: the client still converged, because the second replay
## started from the first one's answer.
##
## What it cost was visible only in the number that exists to measure it.
## [method DotNetPredictor.correction_rate] read [b]0.500[/b] with the extra pass and
## [b]0.032[/b] without — and a correction rate near a half is precisely the reading that
## class documents as "the two simulations disagree, and no smoothing will fix that". It
## was found in dot-2d-hungry, whose bridge was written from this one and inherited it.
func receive_snapshot(payload: PackedByteArray) -> DotResult:
	if net == null or net.is_server:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only a client receives these.")

	return net.receive_snapshot(payload)


# --- The client-to-server channel ------------------------------------------

## An input packet, with the snapshot acknowledgement in front of it.
##
## [b]dot-net does not send either of these for you.[/b] It owns no client-to-server
## channel — inventing one would need a second socket or make every payload ambiguous
## with a message — so the four bytes of acknowledgement ride inside the input packet
## a host already sends every tick. Wiring it is what makes a property lost to a
## dropped packet get re-sent instead of sitting at a stale value until it happens to
## change again; a game that skips it still works, and a player's health is then
## whatever the last packet that arrived said.
##
## The acknowledgement goes first because it is fixed width. A bit-packed command is
## not, so a reader that had to skip it would need to decode it to know where it ends.
func encode_input(tick: int, move: DotFpsCommand, fire: DotCombatCommand) -> PackedByteArray:
	var command := ArenaNetCommand.new()
	command.tick = tick
	command.delta = net.clock.tick_duration()
	command.move = move
	command.fire = fire

	var writer := DotNetWriter.new()
	command.write(writer)

	var out := net.encode_ack()
	out.append_array(writer.to_bytes())
	return out


## Takes one of those packets. Server side.
##
## The acknowledgement is applied even when the command is refused: they are
## independent claims, and a duplicate or late input says nothing about which
## snapshots arrived.
func receive_input(peer_id: int, payload: PackedByteArray) -> DotResult:
	if net == null or not net.is_server:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only the server takes input.")

	if payload.size() <= ACK_BYTES:
		return DotResult.fail(DotError.CODE_PARSE, "Input packet is too short.")

	net.receive_ack_payload(peer_id, payload.slice(0, ACK_BYTES))

	var command := ArenaNetCommand.new()
	command.read(DotNetReader.new(payload.slice(ACK_BYTES)))

	return net.input_buffer_for(peer_id).push(command)


# --- Joins -----------------------------------------------------------------

## Everything a client needs to mirror one player.
##
## A message rather than a spawn: [DotNetSpawner] builds entities from a prefab table,
## and an [ArenaPlayer] is built by [method ArenaGame.add_player] so that the netted
## and the headless deployments get the same player rather than two that drift.
func join_payload(session_id: int) -> PackedByteArray:
	var behaviour: ArenaPlayerNet = _behaviours.get(session_id)

	if behaviour == null or behaviour.identity == null:
		return PackedByteArray()

	var writer := DotNetWriter.new()
	writer.write_varint(behaviour.identity.net_id)
	writer.write_varint(behaviour.identity.owner_peer_id)
	writer.write_varint(session_id)
	writer.write_string(behaviour.player.display_name, 64)
	return writer.to_bytes()


## Mirrors whatever a [method join_payload] described. Client side.
func apply_join(payload: PackedByteArray) -> DotResult:
	var reader := DotNetReader.new(payload)
	var net_id := reader.read_varint()
	var peer_id := reader.read_varint()
	var session_id := reader.read_varint()
	var display_name := reader.read_string(64)

	if not reader.ok():
		return DotResult.fail(DotError.CODE_PARSE, "Truncated join.")

	return mirror_player(net_id, peer_id, session_id, display_name)


func describe() -> Dictionary:
	return {
		"players": _behaviours.size(),
		"peers": _players_by_peer.size(),
		"tick": _tick,
		"ticked_for": _game_ticked_for,
	}
