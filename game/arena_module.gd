class_name ArenaModule
extends DotModule

## Binds an [ArenaGame] to a [DotServer].
##
## [b]This is the only file in the project that names dot-server, and it is the only
## place the family's own documentation says such a bridge belongs.[/b] dot-match does
## not import dot-server, dot-combat does not, and dot-loadout does not — so a game
## that wants a dedicated server writes about forty lines, and they are these.
##
## Loaded the way any module is:
##
## [codeblock]
## server.modules.load_module("res://game/arena_module.gd")
## [/codeblock]
##
## The game itself is found through [DotRegistry] rather than being handed in, which is
## what makes loading by path rather than by instance work at all.

const CHANNEL := "arena.module"

var game: ArenaGame = null

## dot-server session id -> whether we have put them in the match.
var _joined: Dictionary = {}


func _module_name() -> String:
	return "arena"


func _module_version() -> String:
	return "0.1.0"


func _module_description() -> String:
	return "Deathmatch: match flow, combat, loadouts and spawning."


func _module_author() -> String:
	return "dot"


func _module_load() -> DotResult:
	game = DotRegistry.get_node_service(ArenaGame.SERVICE) as ArenaGame

	if game == null:
		# Refusing to load is right: a module that loaded and then did nothing would
		# leave a server that accepts players into a match that does not exist, and
		# the symptom is players who connect and never spawn.
		return DotResult.fail(
			DotError.CODE_STATE,
			"No ArenaGame is registered. Create one and call setup() before loading "
			+ "this module."
		)

	hook_post("client_spawn", _on_client_spawn)

	add_command(
		"arena_status", _cmd_status, "Show the match state", DotAdminFlags.GENERIC
	)
	add_command(
		"arena_score", _cmd_score, "Show the scoreboard", ""
	)
	add_command(
		"arena_restart", _cmd_restart, "Restart the match", DotAdminFlags.CHANGEMAP
	)

	add_cvar("arena_scorelimit", str(game.score_limit), "Kills to win the match")

	server.client_disconnected.connect(_on_client_disconnected)
	game.player_killed.connect(_on_player_killed)

	log_info("arena loaded", {"map": game.map.display_name})
	return DotResult.success(null)


func _module_unload() -> void:
	if server != null and server.client_disconnected.is_connected(_on_client_disconnected):
		server.client_disconnected.disconnect(_on_client_disconnected)

	if game != null and is_instance_valid(game):
		if game.player_killed.is_connected(_on_player_killed):
			game.player_killed.disconnect(_on_player_killed)

		# Every player this module put in the match comes back out. A module that
		# unloaded and left them there would leave the game holding bodies whose
		# sessions no longer exist, and the next kill would credit a ghost.
		for userid in _joined.keys():
			game.remove_player(int(userid))

	_joined.clear()


# --- Sessions --------------------------------------------------------------

## A client finished the signon and is in the world.
##
## [b]`client_spawn`, not `client_connected`.[/b] A connected client has a socket and
## nothing else — no identity, no content, no confirmation it can load the map. Adding
## them to the match there produces a body for someone who may still fail to join.
func _on_client_spawn(event: DotEvent) -> void:
	var session := server.session_of(event.get_int("peer_id"))

	if session == null:
		return

	_add(session)


func _add(session: DotClientSession) -> void:
	if _joined.has(session.userid):
		return

	# The session id, not the peer id. A peer id is reassigned the moment someone
	# reconnects, and everything downstream of this -- the scoreboard, the combat
	# entity, the damage attribution -- would then be handed to the next player to
	# join. dot-server's userid is stable for the life of the session.
	var added := game.add_player(session.userid, session.display_name)

	if not added.ok:
		log_warn("could not add a player to the match", {
			"userid": session.userid, "error": str(added.error)
		})
		return

	_joined[session.userid] = true

	log_info("player joined the match", {
		"userid": session.userid, "name": session.display_name
	})


func _on_client_disconnected(session: DotClientSession, _reason: String) -> void:
	if not _joined.has(session.userid):
		return

	game.remove_player(session.userid)
	_joined.erase(session.userid)


func _on_player_killed(entry: DotKillFeed.Entry) -> void:
	# The kill feed as chat is a placeholder for a real one, and it is deliberately
	# not nothing: a dedicated server with no HUD still has to be able to show an
	# operator what is happening in the match it is running.
	if server.chat == null:
		return

	server.broadcast_message(str(entry))


# --- Commands --------------------------------------------------------------

func _cmd_status(ctx: DotCmdContext) -> void:
	for line in game.describe_lines():
		ctx.reply(line)


func _cmd_score(ctx: DotCmdContext) -> void:
	for line in game.match_node.scoreboard.describe_lines():
		ctx.reply(line)


func _cmd_restart(ctx: DotCmdContext) -> void:
	game.start(game.current_tick())
	ctx.reply("Match restarted.")
