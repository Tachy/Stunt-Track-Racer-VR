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
## The road colour changes at every piece border and, inside a piece, at
## least every STRIPE_MAX metres (the piece is cut into equal stripes).
const STRIPE_MAX := 30.0

var path: TrackPath
var time := 0.0
var _leaves: Array = []
var _stripe := PackedByteArray()      # per sample: 0 = dark, 1 = light



func build(p: TrackPath) -> TrackNode:
	path = p
	name = "Track"
	_stripes()
	_build_static()
	_build_bridges()
	return self


## Alternating stripes along the lap. An even number in all, so the colour
## also changes where the lap ends at the start (the longest piece gets one
## stripe more if needed).
func _stripes() -> void:
	var counts := []
	var total := 0
	var longest := 0
	for k in path.pieces.size():
		var length: float = path.pieces[k]["length"]
		counts.append(maxi(1, ceili(length / STRIPE_MAX - 0.01)))
		total += counts[k]
		if length > float(path.pieces[longest]["length"]):
			longest = k
	if total % 2 == 1:
		counts[longest] += 1
	_stripe.resize(path.n)
	var first := 0
	for k in path.pieces.size():
		var pc: Dictionary = path.pieces[k]
		for i in range(pc["i0"], pc["i1"]):
			var u := (path.s_arr[i] - float(pc["s0"])) / float(pc["length"])
			_stripe[i] = (first + mini(int(u * counts[k]), counts[k] - 1)) % 2
		first += counts[k]


func _road_color(i: int) -> Color:
	if path.piece_of[i] == 0 and path.s_arr[i] < 3.0:
		return Palette.START_LINE
	return Palette.ROAD_DARK if _stripe[i] == 0 else Palette.ROAD_LIGHT


func _wall(kit: MeshKit, faces: PackedVector3Array, a: Vector3, b: Vector3) -> void:
	var ag := Vector3(a.x, 0.0, a.z)
	var bg := Vector3(b.x, 0.0, b.z)
	kit.quad(a, b, bg, ag, Palette.WALL)
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


## Road quad with the white edge strips (as wide as in the tunnels) + side
## walls (+ end caps at gaps) from sample i to i+1.
## Deck samples (overhead loop part, sections above an underpass) get a slab
## with thickness instead of walls down to the ground.
func _emit_segment(kit: MeshKit, road_faces: PackedVector3Array, wall_faces: PackedVector3Array, i: int) -> void:
	var j := (i + 1) % path.n
	var ri_ := path.center[i] + path.right[i] * path.half_width[i]
	var li_ := path.center[i] - path.right[i] * path.half_width[i]
	var rj_ := path.center[j] + path.right[j] * path.half_width[j]
	var lj_ := path.center[j] - path.right[j] * path.half_width[j]
	# outer edges of the strips: walls, slabs and caps start there
	var li := path.center[i] - path.right[i] * path.tunnel_half_width(i)
	var ri := path.center[i] + path.right[i] * path.tunnel_half_width(i)
	var lj := path.center[j] - path.right[j] * path.tunnel_half_width(j)
	var rj := path.center[j] + path.right[j] * path.tunnel_half_width(j)
	if path.ground_floor[i] == 1 and path.ground_floor[j] == 1:
		return     # pit floor on the ground: the ground is the road
	if path.road[i] == 1 and path.step[i] == 1 and path.deck[i] == 0:
		_emit_step(kit, road_faces, wall_faces, [li, li_, ri_, ri], [lj, lj_, rj_, rj], i)
		return
	if path.road[i] == 1:
		kit.quad(li_, lj_, rj_, ri_, _road_color(i))
		kit.quad(li, lj, lj_, li_, Palette.WALL_EDGE)
		kit.quad(ri_, rj_, rj, ri, Palette.WALL_EDGE)
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


## Vertical wall of a pit or ski jump between samples i and j = i+1 (black,
## as in the original): the lower road runs on under the higher end, the
## wall stands at that end. A pit floor on the ground gets no road.
## a, b: cross-sections [outer left, road left, road right, outer right].
func _emit_step(kit: MeshKit, road_faces: PackedVector3Array, wall_faces: PackedVector3Array, a: Array, b: Array, i: int) -> void:
	var dh: float = b[0].y - a[0].y
	var low_a := a
	var low_b := b
	var high: Array
	var low: Array
	if dh < 0.0:      # down: the wall at i, the road at j's height from i on
		low_a = a.map(func(v): return v + Vector3(0, dh, 0))
		high = a
		low = low_a
	else:             # up: the road at i's height up to j, the wall at j
		low_b = b.map(func(v): return v - Vector3(0, dh, 0))
		high = b
		low = low_b
	var floor_i := (i + 1) % path.n if dh < 0.0 else i
	if path.ground_floor[floor_i] == 0:
		kit.quad(low_a[1], low_b[1], low_b[2], low_a[2], _road_color(i))
		kit.quad(low_a[0], low_b[0], low_b[1], low_a[1], Palette.WALL_EDGE)
		kit.quad(low_a[2], low_b[2], low_b[3], low_a[3], Palette.WALL_EDGE)
		road_faces.append_array([low_a[0], low_b[0], low_b[3], low_a[0], low_b[3], low_a[3]])
		_wall(kit, wall_faces, low_a[0], low_b[0])
		_wall(kit, wall_faces, low_a[3], low_b[3])
	if path.ground_floor[floor_i] == 1:
		# a gap down to the ground: the wall reaches the ground all across
		low = high.map(func(v): return Vector3(v.x, 0.0, v.z))
	kit.quad(high[0], high[3], low[3], low[0], Palette.JUMP_WALL)
	wall_faces.append_array([high[0], high[3], low[3], high[0], low[3], low[0]])


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
	kit.quad(ci[0], cj[0], lj, li, Palette.WALL_EDGE)   # pure white, also inside
	kit.quad(ri, rj, cj[1], ci[1], Palette.WALL_EDGE)   # pure white, also inside
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
	# open cut: the tunnel walls go on, tilted with the banking as in the
	# tunnel, and end where they reach the ground; a road edge above the
	# ground gets a wall down to it instead
	var ui := path.tunnel_up(i)
	var uj := path.tunnel_up(j)
	_cut_wall(kit, wall_faces, ci[0], cj[0], ui, uj)
	_cut_wall(kit, wall_faces, ci[1], cj[1], ui, uj)
	# portal over the tunnel mouth
	if path.tunnel[i] == 1:
		_portal(kit, wall_faces, ci, ui)
	if path.tunnel[j] == 1:
		_portal(kit, wall_faces, cj, uj)


## Wall of an open cut from the road edge a-b along the tunnel's up vectors
## ua / ub up to the ground (TrackPath.to_ground), with a white band along
## its top; a road edge above the ground: a wall down to it. Where the edge
## crosses ground level the piece is split there.
func _cut_wall(kit: MeshKit, faces: PackedVector3Array, a: Vector3, b: Vector3, ua: Vector3, ub: Vector3) -> void:
	if (a.y > 0.0 and b.y < 0.0) or (a.y < 0.0 and b.y > 0.0):
		var t := a.y / (a.y - b.y)
		var m := a.lerp(b, t)
		m.y = 0.0
		var um := ua.lerp(ub, t).normalized()
		_cut_wall(kit, faces, a, m, ua, um)
		_cut_wall(kit, faces, m, b, um, ub)
		return
	if a.y >= 0.0 and b.y >= 0.0:
		_wall(kit, faces, a, b)
		return
	var ga := TrackPath.to_ground(a, ua)
	var gb := TrackPath.to_ground(b, ub)
	# white band as high as the ramps' band (a lower wall is white all over)
	var ea := ga - ua * (minf(EDGE_BAND, -a.y) / ua.y)
	var eb := gb - ub * (minf(EDGE_BAND, -b.y) / ub.y)
	kit.quad(a, b, eb, ea, Palette.WALL)
	kit.quad(ea, eb, gb, ga, Palette.WALL_EDGE)
	faces.append_array([a, b, gb, a, gb, ga])


## Portal face above the tunnel mouth at a cross-section c (tilted with the
## tunnel, up vector u): from the roof line up to the ground, its sides on
## the lines of the cut walls, a white band along the top.
func _portal(kit: MeshKit, faces: PackedVector3Array, c: Array, u: Vector3) -> void:
	var tl: Vector3 = c[2]
	var tr: Vector3 = c[3]
	var gl := TrackPath.to_ground(tl, u)
	var gr := TrackPath.to_ground(tr, u)
	var el := gl - u * (minf(EDGE_BAND, -tl.y) / u.y)
	var er := gr - u * (minf(EDGE_BAND, -tr.y) / u.y)
	kit.quad(tl, tr, er, el, Palette.WALL)
	kit.quad(el, er, gr, gl, Palette.WALL_EDGE)
	faces.append_array([tl, tr, gr, tl, gr, gl])


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
	kit.quad(li, lj, lbj, lbi, Palette.WALL)
	kit.quad(ri, rj, rbj, rbi, Palette.WALL)
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
