class_name TrackNode
extends Node3D
## Builds the visible track (striped road on solid walls down to the ground),
## its collision and the animated drawbridge leaves.

const LAYER_ROAD := 1
const LAYER_WALL := 2
const LAYER_GROUND := 4
const LAYER_CAR := 8
const EDGE_BAND := 0.35
const STEEP_SLOPE := 0.33
const DECK_THICKNESS := 0.8

var path: TrackPath
var time := 0.0
var _leaves: Array = []



func build(p: TrackPath) -> TrackNode:
	path = p
	name = "Track"
	_build_static()
	_build_bridges()
	return self


func _road_color(i: int) -> Color:
	if path.piece_of[i] == 0 and path.s_arr[i] < 3.0:
		return Palette.START_LINE
	if path.steep[i] == 1:
		return Palette.ROAD_STEEP
	return Palette.ROAD_DARK if path.piece_of[i] % 2 == 0 else Palette.ROAD_LIGHT


func _wall(kit: MeshKit, faces: PackedVector3Array, a: Vector3, b: Vector3) -> void:
	var ag := Vector3(a.x, 0.0, a.z)
	var bg := Vector3(b.x, 0.0, b.z)
	var band := minf(EDGE_BAND, minf(a.y, b.y) * 0.5)
	var a2 := a - Vector3(0, band, 0)
	var b2 := b - Vector3(0, band, 0)
	kit.quad(a, b, b2, a2, Palette.WALL_EDGE)
	kit.quad(a2, b2, bg, ag, Palette.WALL)
	faces.append_array([a, b, bg, a, bg, ag])


func _build_static() -> void:
	var kit := MeshKit.new()
	var road_faces := PackedVector3Array()
	var wall_faces := PackedVector3Array()
	for i in path.n:
		_emit_segment(kit, road_faces, wall_faces, i)

	var mi := kit.build_instance()
	mi.name = "TrackMesh"
	add_child(mi)

	add_child(_static_body("RoadBody", road_faces, LAYER_ROAD))
	add_child(_static_body("WallBody", wall_faces, LAYER_WALL))


## Road quad + side walls (+ end caps at gaps) from sample i to i+1.
## Road quad + side walls (+ end caps at gaps) from sample i to i+1.
## Deck samples (overhead loop part, sections above an underpass) get a slab
## with thickness instead of walls down to the ground.
func _emit_segment(kit: MeshKit, road_faces: PackedVector3Array, wall_faces: PackedVector3Array, i: int) -> void:
	var j := (i + 1) % path.n
	var li := path.center[i] - path.right[i] * path.half_width[i]
	var ri := path.center[i] + path.right[i] * path.half_width[i]
	var lj := path.center[j] - path.right[j] * path.half_width[j]
	var rj := path.center[j] + path.right[j] * path.half_width[j]
	if path.road[i] == 1:
		kit.quad(li, lj, rj, ri, _road_color(i))
		road_faces.append_array([li, lj, rj, li, rj, ri])
		if path.deck[i] == 1:
			_slab(kit, wall_faces, li, lj, ri, rj, path.up[i], path.up[j])
			if path.deck[j] == 0 and path.road[j] == 1:
				_cap(kit, wall_faces, lj, rj)      # wall starts again: close it
		else:
			_wall(kit, wall_faces, li, lj)
			_wall(kit, wall_faces, ri, rj)
			if path.road[j] == 0 or path.deck[j] == 1:
				_cap(kit, wall_faces, lj, rj)
	elif path.road[j] == 1:
		_cap(kit, wall_faces, lj, rj)


func _slab(kit: MeshKit, faces: PackedVector3Array, li: Vector3, lj: Vector3, ri: Vector3, rj: Vector3, ui: Vector3, uj: Vector3) -> void:
	var lbi := li - ui * DECK_THICKNESS
	var lbj := lj - uj * DECK_THICKNESS
	var rbi := ri - ui * DECK_THICKNESS
	var rbj := rj - uj * DECK_THICKNESS
	kit.quad(li, lj, lbj, lbi, Palette.WALL_EDGE)
	kit.quad(ri, rj, rbj, rbi, Palette.WALL_EDGE)
	kit.quad(lbi, lbj, rbj, rbi, Palette.WALL.darkened(0.3))
	faces.append_array([li, lj, lbj, li, lbj, lbi, ri, rj, rbj, ri, rbj, rbi, lbi, lbj, rbj, lbi, rbj, rbi])


func _cap(kit: MeshKit, faces: PackedVector3Array, l: Vector3, r: Vector3) -> void:
	var lg := Vector3(l.x, 0.0, l.z)
	var rg := Vector3(r.x, 0.0, r.z)
	kit.quad(l, r, rg, lg, Palette.WALL)
	faces.append_array([l, r, rg, l, rg, lg])


func _static_body(body_name: String, faces: PackedVector3Array, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	return body


func _build_bridges() -> void:
	for p in path.pieces:
		if not p["bridge"]:
			continue
		var length: float = p["length"]
		var s0: float = float(p["s0"]) + length * TrackPath.BRIDGE_U0
		var s1: float = float(p["s0"]) + length * TrackPath.BRIDGE_U1
		var leaf_len := (s1 - s0) * 0.5
		var f0 := path.frame_at_s(s0)
		var f1 := path.frame_at_s(s1)
		f1.basis = f1.basis * Basis(Vector3.UP, PI)
		for hinge in [f0, f1]:
			_leaves.append({"body": _make_leaf(leaf_len), "hinge": hinge})
	_update_leaves()


func _make_leaf(leaf_len: float) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.sync_to_physics = true
	body.collision_layer = LAYER_ROAD
	body.collision_mask = 0
	var size := Vector3(TrackPath.ROAD_WIDTH, 0.6, leaf_len - 0.15)
	var c := Vector3(0, -0.3, -size.z * 0.5)
	var kit := MeshKit.new()
	kit.box(c, size, Palette.WALL)
	# striped top so it reads as road
	var stripes := 6
	for k in stripes:
		var z0 := -size.z * k / stripes
		var z1 := -size.z * (k + 1) / stripes
		var col := Palette.ROAD_DARK if k % 2 == 0 else Palette.ROAD_LIGHT
		kit.quad(Vector3(-size.x * 0.5, 0.01, z0), Vector3(-size.x * 0.5, 0.01, z1),
			Vector3(size.x * 0.5, 0.01, z1), Vector3(size.x * 0.5, 0.01, z0), col)
	body.add_child(kit.build_instance())
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = c
	body.add_child(cs)
	add_child(body)
	return body


func _update_leaves() -> void:
	var ang := TrackPath.bridge_angle(time)
	for leaf in _leaves:
		var hinge: Transform3D = leaf["hinge"]
		var body: AnimatableBody3D = leaf["body"]
		body.transform = Transform3D(hinge.basis * Basis(Vector3.RIGHT, ang), hinge.origin)


func _physics_process(delta: float) -> void:
	time += delta
	if not _leaves.is_empty():
		_update_leaves()
