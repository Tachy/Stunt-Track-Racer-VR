class_name TrackNode
extends Node3D
## Builds the visible track (striped road on solid walls down to the ground),
## its collision, the animated drawbridge leaves and tunnels: where the road
## dips below the ground an open cut with retaining walls, a portal and a
## rectangular tube (walls like the ramps, ceiling striped like the road)
## that turns and banks with the road, lit by lamps along the ceiling.

const LAYER_ROAD := 1
const LAYER_WALL := 2
const LAYER_GROUND := 4
const LAYER_CAR := 8
const EDGE_BAND := 0.35
const STEEP_SLOPE := 0.33
const DECK_THICKNESS := 0.8
## Render layer of everything the tunnel lamps light (tunnel inside, cars):
## the lamps would otherwise shine through the ground onto the world above.
const TUNNEL_LIGHT_LAYER := 2
## Inside the tunnel colours are darker (daylight only through the portals).
const TUNNEL_DIM := 0.45
const LAMP_SPACING := 12          # samples (m) between ceiling lamps
const LIGHT_SPACING := 24         # samples (m) between real lights
const LAMP_COLOR := Color(1.0, 0.92, 0.72)

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
	# white band below the road edge; a wall lower than the band is white
	# right down to the ground (per end, so it never steps)
	var a2 := a - Vector3(0, minf(EDGE_BAND, maxf(a.y, 0.0)), 0)
	var b2 := b - Vector3(0, minf(EDGE_BAND, maxf(b.y, 0.0)), 0)
	kit.quad(a, b, b2, a2, Palette.WALL_EDGE)
	kit.quad(a2, b2, bg, ag, Palette.WALL)
	faces.append_array([a, b, bg, a, bg, ag])


func _build_static() -> void:
	var kit := MeshKit.new()
	var tkit := MeshKit.new()
	var road_faces := PackedVector3Array()
	var wall_faces := PackedVector3Array()
	for i in path.n:
		if _is_tunnel_segment(i) or _is_cut_segment(i):
			_emit_tunnel_segment(tkit, road_faces, wall_faces, i)
		else:
			_emit_segment(kit, road_faces, wall_faces, i)

	var mi := kit.build_instance()
	mi.name = "TrackMesh"
	add_child(mi)
	if not tkit.is_empty():
		var tmi := tkit.build_instance()
		tmi.name = "TunnelMesh"
		tmi.layers = 1 | TUNNEL_LIGHT_LAYER
		add_child(tmi)
		_build_tunnel_lamps()

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


# --- tunnels ----------------------------------------------------------------------

func _is_tunnel_segment(i: int) -> bool:
	return path.tunnel[i] == 1 and path.tunnel[(i + 1) % path.n] == 1


## Open cut, or the step between cut and tunnel: retaining walls up to the
## ground, no roof.
func _is_cut_segment(i: int) -> bool:
	var j := (i + 1) % path.n
	return not _is_tunnel_segment(i) and (path.cut[i] == 1 or path.cut[j] == 1 or path.tunnel[i] == 1 or path.tunnel[j] == 1)


func _emit_tunnel_segment(kit: MeshKit, road_faces: PackedVector3Array, wall_faces: PackedVector3Array, i: int) -> void:
	var j := (i + 1) % path.n
	var ci := path.tunnel_corners(i)
	var cj := path.tunnel_corners(j)
	var inside := _is_tunnel_segment(i)
	var dim := TUNNEL_DIM if inside else 0.0
	# road plus the white edge strips out to the walls
	var li := path.center[i] - path.right[i] * path.half_width[i]
	var ri := path.center[i] + path.right[i] * path.half_width[i]
	var lj := path.center[j] - path.right[j] * path.half_width[j]
	var rj := path.center[j] + path.right[j] * path.half_width[j]
	var col := _road_color(i).darkened(dim)
	kit.quad(li, lj, rj, ri, col)
	kit.quad(ci[0], cj[0], lj, li, Palette.WALL_EDGE.darkened(dim))
	kit.quad(ri, rj, cj[1], ci[1], Palette.WALL_EDGE.darkened(dim))
	road_faces.append_array([li, lj, rj, li, rj, ri, ci[0], cj[0], lj, ci[0], lj, li, ri, rj, cj[1], ri, cj[1], ci[1]])
	if inside:
		var wall := Palette.WALL.darkened(TUNNEL_DIM)
		kit.quad(ci[0], cj[0], cj[2], ci[2], wall)
		kit.quad(ci[1], cj[1], cj[3], ci[3], wall)
		kit.quad(ci[2], cj[2], cj[3], ci[3], _road_color(i).darkened(TUNNEL_DIM))   # ceiling
		# roof top (under the ground, unseen): casts the tunnel's shadow
		var lift_i: Vector3 = path.tunnel_up(i) * TrackPath.TUNNEL_ROOF
		var lift_j: Vector3 = path.tunnel_up(j) * TrackPath.TUNNEL_ROOF
		kit.quad(ci[2] + lift_i, cj[2] + lift_j, cj[3] + lift_j, ci[3] + lift_i, Palette.WALL)
		wall_faces.append_array([ci[0], cj[0], cj[2], ci[0], cj[2], ci[2],
			ci[1], cj[1], cj[3], ci[1], cj[3], ci[3],
			ci[2], cj[2], cj[3], ci[2], cj[3], ci[3]])
		return
	# open cut: retaining walls from the road edge up (or down) to the ground
	_to_ground(kit, wall_faces, ci[0], cj[0])
	_to_ground(kit, wall_faces, ci[1], cj[1])
	# portal over the tunnel mouth
	if path.tunnel[i] == 1:
		_portal(kit, wall_faces, ci)
	if path.tunnel[j] == 1:
		_portal(kit, wall_faces, cj)


## Wall from a road edge a-b to the ground: down from a road above the
## ground (like the ramps), up as a retaining wall from a road below it.
## Where the edge crosses ground level the piece is split there.
func _to_ground(kit: MeshKit, faces: PackedVector3Array, a: Vector3, b: Vector3) -> void:
	if (a.y > 0.0 and b.y < 0.0) or (a.y < 0.0 and b.y > 0.0):
		var m := a.lerp(b, a.y / (a.y - b.y))
		m.y = 0.0
		_to_ground(kit, faces, a, m)
		_to_ground(kit, faces, m, b)
		return
	if a.y >= 0.0 and b.y >= 0.0:
		_wall(kit, faces, a, b)
		return
	# retaining wall: white band along the top edge at ground level, as high
	# as the ramps' band (a wall lower than that is white all over)
	var ag := Vector3(a.x, 0.0, a.z)
	var bg := Vector3(b.x, 0.0, b.z)
	var a2 := Vector3(a.x, -minf(EDGE_BAND, -a.y), a.z)
	var b2 := Vector3(b.x, -minf(EDGE_BAND, -b.y), b.z)
	kit.quad(a, b, b2, a2, Palette.WALL)
	kit.quad(a2, b2, bg, ag, Palette.WALL_EDGE)
	faces.append_array([a, b, bg, a, bg, ag])


## Portal face above the tunnel mouth at a cross-section c, from the roof
## line up to the ground. Its white edge runs along the top at exactly the
## height of the cut walls' white band, and its sides reach out to the cut
## walls (straight above the road edges), so a banked portal has no gap.
func _portal(kit: MeshKit, faces: PackedVector3Array, c: Array) -> void:
	var bl0: Vector3 = c[0]
	var br0: Vector3 = c[1]
	var tl: Vector3 = c[2]
	var tr: Vector3 = c[3]
	var gl := Vector3(bl0.x, 0.0, bl0.z)
	var gr := Vector3(br0.x, 0.0, br0.z)
	var el := Vector3(bl0.x, -EDGE_BAND, bl0.z)
	var er := Vector3(br0.x, -EDGE_BAND, br0.z)
	kit.quad(tl, tr, er, el, Palette.WALL)
	kit.quad(el, er, gr, gl, Palette.WALL_EDGE)
	# corners between the tunnel wall, the cut wall and the face
	kit.tri(bl0, tl, el, Palette.WALL)
	kit.tri(br0, er, tr, Palette.WALL)
	faces.append_array([tl, tr, gr, tl, gr, gl, bl0, tl, gl, br0, gr, tr])


## Lamp strips under the ceiling (always bright) and, every LIGHT_SPACING,
## a shadowless light that also lights the cars passing below.
func _build_tunnel_lamps() -> void:
	var kit := MeshKit.new()
	for i in path.n:
		if path.tunnel[i] == 0 or path.tunnel_depth[i] < 3.0:
			continue
		var tu := path.tunnel_up(i)
		var b := Basis(path.right[i], tu, path.right[i].cross(tu)).orthonormalized()
		var top: Vector3 = path.center[i] + tu * (TrackPath.TUNNEL_HEIGHT - 0.06)
		if i % LAMP_SPACING == 0:
			kit.box(top, Vector3(0.5, 0.1, 1.8), LAMP_COLOR, b)
		if i % LIGHT_SPACING == LAMP_SPACING / 2 and path.tunnel_depth[i] > 4.0:
			var light := OmniLight3D.new()
			light.position = path.center[i] + tu * (TrackPath.TUNNEL_HEIGHT - 0.8)
			light.light_color = LAMP_COLOR
			light.light_energy = 1.6
			light.omni_range = 11.0
			light.omni_attenuation = 1.2
			light.shadow_enabled = false
			light.light_cull_mask = TUNNEL_LIGHT_LAYER
			add_child(light)
	var mi := kit.build_instance()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "TunnelLamps"
	add_child(mi)


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
