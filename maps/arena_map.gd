class_name ArenaMap
extends RefCounted

## A level as a list of boxes, and the three things that list becomes.
##
## [b]This is the idea the whole project is arranged around.[/b] A dev-textured arena
## is a floor and some boxes. Those boxes have to exist in three places:
##
## - as [MeshInstance3D]s, so a player can see them,
## - as [StaticBody3D]s, so Godot's physics can collide with them,
## - as analytic [AABB]s, so [DotFpsFlatBody] and [DotTraceFlat] can — on a headless
##   server and in a test, where there is no physics space and no renderer.
##
## Building them independently means three descriptions that drift, and the drift is
## invisible: the server's idea of a wall moves a metre and shots start passing through
## something clients can see. So the boxes are declared once, here, and everything else
## is generated from them.
##
## The same reason a game like this ships with dev textures in the first place. A
## grey-box level whose geometry is its gameplay is a level you can reason about.

const CHANNEL := "arena.map"

## Solid boxes, in world space.
var boxes: Array[AABB] = []

## Ground plane height. Boxes sit on it.
var floor_y: float = 0.0

## Half-extent of the playable area on X and Z. Walls are generated at the edges.
var extent: float = 24.0

## Wall height.
var wall_height: float = 8.0

## Where players appear. Fed into [DotMatch]'s spawn points.
var spawns: Array[Transform3D] = []

var display_name: String = "dm_box"


## The shipped arena: a square room, a raised centre, four pillars, two ledges.
##
## Symmetric on purpose. A symmetric map makes every spawn point score identically for
## the spawn selector, which is exactly the tie its name-based tie-break exists for —
## so the map that ships is also the map that exercises it.
static func dm_box() -> ArenaMap:
	var map := ArenaMap.new()
	map.display_name = "dm_box"
	map.extent = 24.0
	map.wall_height = 8.0

	# The raised middle. Two steps up, so stair stepping is exercised by walking at it.
	map.add_box(AABB(Vector3(-6.0, 0.0, -6.0), Vector3(12.0, 1.0, 12.0)))
	map.add_box(AABB(Vector3(-7.0, 0.0, -7.0), Vector3(14.0, 0.5, 14.0)))

	# Four pillars, off the diagonals so they break sightlines rather than framing them.
	for corner in [Vector2(-12.0, -4.0), Vector2(12.0, 4.0), Vector2(-4.0, 12.0), Vector2(4.0, -12.0)]:
		map.add_box(AABB(
			Vector3(corner.x - 1.5, 0.0, corner.y - 1.5), Vector3(3.0, 5.0, 3.0)
		))

	# Two ledges along opposite walls, reachable from the pillars.
	map.add_box(AABB(Vector3(-map.extent, 3.0, -18.0), Vector3(6.0, 0.6, 36.0)))
	map.add_box(AABB(Vector3(map.extent - 6.0, 3.0, -18.0), Vector3(6.0, 0.6, 36.0)))

	map.add_perimeter()

	# Eight spawns around the outside, facing the middle. Enough that a full server is
	# not spawning two people on one point, and far enough apart that the
	# furthest-from-danger rule has something to choose between.
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var at := Vector3(cos(angle) * 18.0, 0.1, sin(angle) * 18.0)
		map.spawns.append(
			Transform3D(Basis.looking_at(-at.normalized(), Vector3.UP), at)
		)

	return map


func add_box(box: AABB) -> ArenaMap:
	boxes.append(box.abs())
	return self


## Adds the four outer walls.
##
## Solid boxes rather than planes, because everything downstream understands a box and
## only some of it understands a plane — and a map that is boxes all the way down is a
## map whose three representations cannot disagree.
func add_perimeter(thickness: float = 2.0) -> ArenaMap:
	var span := extent * 2.0 + thickness * 2.0

	add_box(AABB(
		Vector3(-extent - thickness, floor_y, -extent - thickness),
		Vector3(thickness, wall_height, span)
	))
	add_box(AABB(
		Vector3(extent, floor_y, -extent - thickness),
		Vector3(thickness, wall_height, span)
	))
	add_box(AABB(
		Vector3(-extent - thickness, floor_y, -extent - thickness),
		Vector3(span, wall_height, thickness)
	))
	add_box(AABB(
		Vector3(-extent - thickness, floor_y, extent),
		Vector3(span, wall_height, thickness)
	))

	return self


# --- The three representations ---------------------------------------------

## The movement backend for a headless server or a test.
func to_fps_body() -> DotFpsFlatBody:
	var body := DotFpsFlatBody.with_floor(floor_y)

	for box in boxes:
		body.add_box(box)

	return body


## The shot-tracing backend for a headless server or a test.
func to_trace() -> DotTraceFlat:
	var trace := DotTraceFlat.with_floor(floor_y)

	for box in boxes:
		trace.add_box(box)

	return trace


## The visible and collidable level, for a client or a listen server.
##
## Returns a [Node3D] holding one [StaticBody3D] per box plus a floor. Built rather
## than loaded from a scene so that the geometry cannot drift from
## [method to_fps_body] and [method to_trace] — which is the whole point of the class.
func to_scene() -> Node3D:
	var root := Node3D.new()
	root.name = "Level"

	var material := dev_material()

	root.add_child(_make_box(
		AABB(
			Vector3(-extent - 2.0, floor_y - 1.0, -extent - 2.0),
			Vector3(extent * 2.0 + 4.0, 1.0, extent * 2.0 + 4.0)
		),
		material,
		"Floor"
	))

	for index in range(boxes.size()):
		root.add_child(_make_box(boxes[index], material, "Box%02d" % index))

	return root


static func _make_box(box: AABB, material: Material, node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = box.position + box.size * 0.5

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh.mesh = box_mesh
	mesh.material_override = material
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	body.add_child(shape)

	return body


# --- Dev texture -----------------------------------------------------------

## A grid texture, generated rather than shipped.
##
## No art assets anywhere in this repository. A generated grid is what a dev-textured
## game wants anyway: it makes distance and scale readable, which is the entire
## function a dev texture performs.
static func dev_texture(
	size: int = 128,
	line_every: int = 32,
	base: Color = Color(0.32, 0.34, 0.38),
	line: Color = Color(0.20, 0.21, 0.24)
) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	image.fill(base)

	for x in range(size):
		for y in range(size):
			if x % line_every == 0 or y % line_every == 0:
				image.set_pixel(x, y, line)
			elif (x % line_every == 1) or (y % line_every == 1):
				image.set_pixel(x, y, line.lerp(base, 0.5))

	return ImageTexture.create_from_image(image)


## A material that tiles the grid by world size rather than by UV.
##
## Triplanar, because a [BoxMesh] UV-maps every face to the same 0..1 square: without
## it a two-metre box and a forty-metre wall show the same number of grid squares, and
## the texture stops telling you anything about scale — which is the only job it has.
static func dev_material(tint: Color = Color.WHITE) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = dev_texture()
	material.albedo_color = tint
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.5, 0.5, 0.5)
	material.roughness = 0.9
	material.metallic = 0.0
	return material


func describe() -> Dictionary:
	return {
		"name": display_name,
		"boxes": boxes.size(),
		"spawns": spawns.size(),
		"extent": extent,
	}
