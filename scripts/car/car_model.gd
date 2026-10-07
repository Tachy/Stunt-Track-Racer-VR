class_name CarModel
extends Node3D
## Low-poly stunt car in the style of the original: the cockpit sits far back,
## in front of the driver a long nose with an exposed V-engine and big
## free-standing front wheels on visible double-wishbone suspension with
## coil-over springs that compress and extend with the physics.
## Origin = suspension mount height, forward = -Z.

## Wheel mount points (FL, FR, RL, RR) and radii - shared with PlayerCar.
const WHEEL_POS := [Vector3(-1.1, 0.0, -1.75), Vector3(1.1, 0.0, -1.75),
		Vector3(-1.1, 0.0, 1.15), Vector3(1.1, 0.0, 1.15)]
const WHEEL_R := [0.42, 0.42, 0.48, 0.48]
const WHEEL_W := [0.30, 0.30, 0.44, 0.44]
const WHEEL_RADIUS := 0.42
## Tyre spikes (visual only): edge of the square base, height above the
## tyre, spacing around the tyre and across its width.
## Visual roundness of tyre and rim (the physics wheel is an exact circle:
## a ray of length WHEEL_R).
const TYRE_SEGMENTS := 48
const RIM_SEGMENTS := 32
const SPIKE_SIZE := 0.05
const SPIKE_HEIGHT := 0.035
const SPIKE_PITCH := 0.15
const SPIKE_ROW_PITCH := 0.14
## Mount height above the road at rest (rest length - static sag + radius).
const RIDE_HEIGHT := 0.80

const SEAT_EYE := Vector3(0.0, 0.96, 0.9)
const HEADER_Y := 1.32
const HEADER_Z := 0.36
const HEADER_HALF := 0.46
## Rake of the front cage frame (the "windscreen" frame) from the vertical.
const SCREEN_RAKE_DEG := 20.0
## Height of the front cage feet on the cockpit sides.
const PILLAR_FOOT_Y := 0.4

const FRAME_X := 0.32
## Upper mount of the front coil-overs, out on an outrigger from the tower.
const FRONT_SPRING_TOP_X := 0.62
const METAL := Color("#555a60")
const CHROME := Color("#c8c8c8")
const HEADS := Color("#8a8f96")
const EXHAUST := Color("#b89a78")

var wheel_pivots: Array[Node3D] = []
var wheel_spinners: Array[Node3D] = []
var steering_pivot: Node3D
var steering_rot: Node3D
var dashboard_anchor: Node3D

var _links: Array = []          # per wheel: {upper, lower, spring, damper}
var _shown_comp := PackedFloat32Array([0, 0, 0, 0])
var _crack_mi: MeshInstance3D
var _holes_mi: MeshInstance3D
var _crack_points: PackedVector2Array
var _last_crack := -1.0
var _last_holes := -1
var _rest := 0.5
var _outlets: Array = []         # [position, direction] of the 8 exhaust pipes
var _flames: Array[Node3D] = []
var _flame_on := false
static var _flame_mesh: ArrayMesh
static var _flame_material: StandardMaterial3D
static var _unit_bar: ArrayMesh
static var _unit_coil: ArrayMesh
static var _unit_rod: ArrayMesh


func build(body_color: Color, cockpit: bool) -> CarModel:
	var kit := MeshKit.new()
	_build_chassis(kit, body_color)
	_build_engine(kit)
	_build_cabin(kit, body_color, cockpit)
	var body := kit.build_instance()
	body.name = "Body"
	add_child(body)

	_build_wheels()
	_build_flames()
	if cockpit:
		_build_steering_wheel()
		dashboard_anchor = Node3D.new()
		dashboard_anchor.name = "DashboardAnchor"
		dashboard_anchor.position = Vector3(0, 0.63, 0.27)
		dashboard_anchor.rotation = Vector3(deg_to_rad(-30.0), 0, 0)
		add_child(dashboard_anchor)
		_build_crack_holder()
	update_wheels(PackedFloat32Array([0.13, 0.13, 0.13, 0.13]), 0.0, PackedFloat32Array([0, 0, 0, 0]), _rest, 0.0)
	return self


# --- static geometry -------------------------------------------------------------

func _build_chassis(kit: MeshKit, body_color: Color) -> void:
	# ladder frame
	for sx in [-1.0, 1.0]:
		kit.box(Vector3(FRAME_X * sx, -0.22, -0.25), Vector3(0.1, 0.14, 4.2), METAL.darkened(0.3))
	for z in [-2.1, -1.75, -0.3, 1.15, 1.75]:
		kit.box(Vector3(0, -0.22, z), Vector3(FRAME_X * 2.0, 0.1, 0.1), METAL.darkened(0.3))
	# radiator and low front spoiler
	kit.box(Vector3(0, 0.08, -2.12), Vector3(0.7, 0.5, 0.1), Palette.BLACK)
	for k in 5:
		kit.box(Vector3(0, -0.1 + k * 0.09, -2.18), Vector3(0.72, 0.025, 0.02), CHROME)
	kit.box(Vector3(0, -0.3, -2.25), Vector3(1.5, 0.08, 0.3), body_color)
	# small front body panel under the engine (keeps the nose readable)
	kit.box(Vector3(0, -0.12, -1.0), Vector3(0.9, 0.1, 2.2), body_color.darkened(0.25))
	# suspension towers
	for z in [-1.75, 1.15]:
		for sx in [-1.0, 1.0]:
			kit.box(Vector3(0.36 * sx, 0.02, z), Vector3(0.1, 0.5, 0.12), METAL)
	# front: outriggers from the tower tops carry the upper spring mounts
	for sx in [-1.0, 1.0]:
		var z := float(WHEEL_POS[0].z) + 0.08
		kit.bar(Vector3(0.36 * sx, 0.25, z), Vector3((FRONT_SPRING_TOP_X + 0.03) * sx, 0.31, z), 0.055, METAL)
		kit.bar(Vector3(0.36 * sx, 0.12, z), Vector3((FRONT_SPRING_TOP_X - 0.05) * sx, 0.29, z), 0.035, METAL)   # brace


func _build_engine(kit: MeshKit) -> void:
	var z0 := -0.95
	# block
	kit.box(Vector3(0, -0.02, z0), Vector3(0.5, 0.36, 1.05), METAL)
	# V cylinder heads
	for sx in [-1.0, 1.0]:
		var head := Basis(Vector3.FORWARD, deg_to_rad(30.0) * sx)
		var head_c := Vector3(0.2 * sx, 0.24, z0)
		kit.box(head_c, Vector3(0.2, 0.26, 1.0), HEADS, head)
		# exhaust: four short open stubs per side (eight in all), standing on
		# the sloped top of each head, leaning 60 deg back from its normal
		var n := head.y                                  # top face normal: up and out
		var on_face: Vector3 = head_c + n * 0.13 - head.x * sx * 0.04
		var lean := deg_to_rad(60.0)   # from the face normal toward the back (+Z)
		var dir := (n * cos(lean) + Vector3.BACK * sin(lean)).normalized()
		for k in 4:
			var base: Vector3 = on_face + Vector3(0, 0, -0.38 + k * 0.25)
			# the slanted pipe reaches deep enough into the head that its
			# whole rim is buried: no gap where it meets the sloped face
			var visible := 0.11
			var sink := 0.03 * tan(lean) + 0.015
			kit.cylinder(base + dir * ((visible - sink) * 0.5), dir, 0.03, visible + sink, 10, EXHAUST, Palette.BLACK)
			_outlets.append([base + dir * visible, dir])
	# supercharger + scoop
	kit.box(Vector3(0, 0.42, z0), Vector3(0.28, 0.16, 0.6), CHROME)
	kit.box(Vector3(0, 0.55, z0 - 0.08), Vector3(0.3, 0.1, 0.3), Palette.BLACK)
	kit.box(Vector3(0, 0.56, z0 - 0.235), Vector3(0.26, 0.06, 0.02), Palette.ROCK_DARK)
	# belt drive at the front
	kit.cylinder(Vector3(0, 0.3, z0 - 0.56), Vector3.BACK, 0.11, 0.06, 10, Palette.BLACK)
	kit.cylinder(Vector3(0, -0.05, z0 - 0.56), Vector3.BACK, 0.09, 0.06, 10, Palette.BLACK)


func _build_cabin(kit: MeshKit, body_color: Color, cockpit: bool) -> void:
	var dark := Palette.INTERIOR
	# tub
	kit.box(Vector3(0, -0.14, 0.95), Vector3(1.04, 0.08, 1.5), dark)
	# the front cage feet stand this far ahead of the header (raked frame)
	var foot_z := HEADER_Z - (HEADER_Y - PILLAR_FOOT_Y) * tan(deg_to_rad(SCREEN_RAKE_DEG))
	for sx in [-1.0, 1.0]:
		kit.box(Vector3(0.52 * sx, 0.12, 0.98), Vector3(0.08, 0.56, 1.46), body_color)
		# a slim rail carries the raked front frame forward, braced down to
		# the chassis frame (keeps the view onto the front wheels free)
		kit.box(Vector3(0.52 * sx, PILLAR_FOOT_Y - 0.04, (foot_z - 0.05 + 0.25) * 0.5), Vector3(0.08, 0.1, 0.25 - foot_z + 0.05), body_color)
		kit.bar(Vector3(0.52 * sx, PILLAR_FOOT_Y - 0.06, foot_z + 0.04), Vector3(FRAME_X * sx, -0.16, 0.1), 0.05, METAL)
	kit.box(Vector3(0, 0.16, 1.72), Vector3(1.12, 0.64, 0.08), body_color)
	# firewall / scuttle with dashboard cowl
	kit.box(Vector3(0, 0.14, 0.24), Vector3(1.12, 0.54, 0.08), body_color)
	kit.box(Vector3(0, 0.43, 0.33), Vector3(1.12, 0.06, 0.2), dark)
	# fuel tank behind the seat
	kit.box(Vector3(0, 0.62, 1.9), Vector3(0.9, 0.36, 0.26), body_color.darkened(0.15))
	# seat
	kit.box(Vector3(0, -0.02, 0.98), Vector3(0.5, 0.16, 0.5), dark.lightened(0.12))
	kit.box(Vector3(0, 0.36, 1.26), Vector3(0.5, 0.66, 0.1), dark.lightened(0.12), Basis(Vector3.RIGHT, deg_to_rad(-12.0)))
	# roll cage
	var t := 0.065
	for sx in [-1.0, 1.0]:
		kit.bar(Vector3(0.52 * sx, PILLAR_FOOT_Y, foot_z), Vector3(HEADER_HALF * sx, HEADER_Y, HEADER_Z), t, Palette.CAGE)
		kit.bar(Vector3(HEADER_HALF * sx, HEADER_Y, HEADER_Z), Vector3(HEADER_HALF * sx, HEADER_Y, 1.4), t, Palette.CAGE)
		kit.bar(Vector3(HEADER_HALF * sx, HEADER_Y, 1.4), Vector3(0.52 * sx, 0.42, 1.68), t, Palette.CAGE)
	kit.box(Vector3(0, HEADER_Y, HEADER_Z), Vector3(HEADER_HALF * 2.0 + t, 0.11, 0.05), Palette.CAGE)
	kit.bar(Vector3(-HEADER_HALF, HEADER_Y, 1.4), Vector3(HEADER_HALF, HEADER_Y, 1.4), t, Palette.CAGE)
	kit.bar(Vector3(-HEADER_HALF, HEADER_Y, 1.4), Vector3(0.4, 0.45, 1.68), t * 0.8, Palette.CAGE)
	if not cockpit:
		kit.box(Vector3(0, 0.96, 1.0), Vector3(0.3, 0.3, 0.32), Palette.WHITE)
		kit.box(Vector3(0, 0.96, 0.85), Vector3(0.26, 0.1, 0.04), Palette.BLACK)


# --- boost flames ---------------------------------------------------------------------

## A flame cone along +Y: yellow core inside an orange-red mantle.
static func _flame() -> ArrayMesh:
	if _flame_mesh == null:
		var k := MeshKit.new()
		k.peak(Vector3.ZERO, 0.055, 0.42, 6, Color(1.0, 0.35, 0.05, 0.75))
		k.peak(Vector3(0, 0.01, 0), 0.03, 0.26, 6, Color(1.0, 0.9, 0.35, 0.95))
		_flame_mesh = k.build()
		_flame_material = StandardMaterial3D.new()
		_flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flame_material.vertex_color_use_as_albedo = true
		_flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flame_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flame_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _flame_mesh


func _build_flames() -> void:
	var mesh := _flame()
	for o in _outlets:
		var pos: Vector3 = o[0]
		var dir: Vector3 = o[1]
		var f := Node3D.new()
		f.position = pos
		var x := dir.cross(Vector3.FORWARD).normalized()
		f.basis = Basis(x, dir, x.cross(dir))   # +Y along the pipe
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _flame_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.add_child(mi)
		f.visible = false
		add_child(f)
		_flames.append(f)


## Flames out of all eight pipes while boosting, flickering every frame.
func set_boost(on: bool) -> void:
	if not on and not _flame_on:
		return
	_flame_on = on
	for f in _flames:
		f.visible = on
		if on:
			var w := randf_range(0.8, 1.15)
			f.scale = Vector3(w, randf_range(0.55, 1.35), w)


# --- wheels & suspension ------------------------------------------------------------

static func _bar_mesh() -> ArrayMesh:
	if _unit_bar == null:
		var k := MeshKit.new()
		k.box(Vector3(0, 0, -0.5), Vector3(1, 1, 1), METAL.lightened(0.15))
		_unit_bar = k.build()
	return _unit_bar


## Coil spring of unit length along -Z (scaling along Z compresses the
## coils): a round wire helix between two spring seats.
static func _coil_mesh() -> ArrayMesh:
	if _unit_coil == null:
		var k := MeshKit.new()
		var turns := 8
		var seg := 18
		var r := 0.058
		var pts := PackedVector3Array()
		for i in turns * seg + 1:
			var a := TAU * i / seg
			pts.append(Vector3(cos(a) * r, sin(a) * r, -0.03 - 0.94 * float(i) / (turns * seg)))
		k.tube(pts, 0.009, 6, Palette.YELLOW)
		for z in [-0.015, -0.985]:
			k.cylinder(Vector3(0, 0, z), Vector3.BACK, r + 0.018, 0.03, 14, METAL.lightened(0.25))
		_unit_coil = k.build()
	return _unit_coil


## Round rod of unit length and diameter along -Z (damper).
static func _rod_mesh() -> ArrayMesh:
	if _unit_rod == null:
		var k := MeshKit.new()
		k.cylinder(Vector3(0, 0, -0.5), Vector3.BACK, 0.5, 1.0, 10, CHROME)
		_unit_rod = k.build()
	return _unit_rod


func _link(mesh: ArrayMesh, thickness: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_meta("t", thickness)
	add_child(mi)
	return mi


static func _place(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length := d.length()
	if length < 1e-4:
		return
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
	var t: float = mi.get_meta("t", 1.0)
	mi.transform = Transform3D(Basis.looking_at(d / length, up) * Basis.from_scale(Vector3(t, t, length)), a)


func _build_wheels() -> void:
	for w in 4:
		var pos: Vector3 = WHEEL_POS[w]
		var r: float = WHEEL_R[w]
		var width: float = WHEEL_W[w]
		var pivot := Node3D.new()
		pivot.position = Vector3(pos.x, -0.37, pos.z)
		add_child(pivot)
		var spinner := Node3D.new()
		pivot.add_child(spinner)
		var kit := MeshKit.new()
		kit.cylinder(Vector3.ZERO, Vector3.RIGHT, r, width, TYRE_SEGMENTS, Palette.TYRE, Palette.TYRE.lightened(0.1))
		# rim and hub
		var side := signf(pos.x)
		kit.cylinder(Vector3(side * (width * 0.5 + 0.005), 0, 0), Vector3.RIGHT, r * 0.6, 0.02, RIM_SEGMENTS, Palette.HUB)
		kit.cylinder(Vector3(side * (width * 0.5 + 0.02), 0, 0), Vector3.RIGHT, r * 0.18, 0.04, 6, Palette.HUB.darkened(0.3))
		# spikes: radial boxes in staggered rows (visual only - the wheel's
		# physics radius is the bare tyre, the spikes have no hitbox)
		var rows := maxi(2, int(round(width / SPIKE_ROW_PITCH)))
		var per_row := int(round(TAU * r / SPIKE_PITCH))
		var base := r * cos(PI / TYRE_SEGMENTS) - 0.005   # just inside the tyre's flats
		var top := r + SPIKE_HEIGHT
		for j in rows:
			var x := (float(j) - (rows - 1) * 0.5) * width / rows
			for k in per_row:
				var a := TAU * (float(k) + 0.5 * (j % 2)) / per_row
				var mid := (base + top) * 0.5
				kit.box(Vector3(x, cos(a) * mid, sin(a) * mid), Vector3(SPIKE_SIZE, top - base, SPIKE_SIZE),
					Palette.TYRE.lightened(0.25), Basis(Vector3.RIGHT, a))
		spinner.add_child(kit.build_instance())
		wheel_pivots.append(pivot)
		wheel_spinners.append(spinner)
		_links.append({
			"upper": _link(_bar_mesh(), 0.045),
			"lower": _link(_bar_mesh(), 0.055),
			"spring": _link(_coil_mesh(), 1.0),
			"damper": _link(_rod_mesh(), 0.024),
		})


## comp = suspension compression per wheel (m), rest = rest length.
## dt > 0 smooths extension so wheels drop visibly instead of snapping.
func update_wheels(comp: PackedFloat32Array, steer: float, spin: PackedFloat32Array, rest: float, dt := 0.0) -> void:
	_rest = rest
	for w in 4:
		var target := comp[w]
		if dt > 0.0 and target < _shown_comp[w]:
			_shown_comp[w] = maxf(target, _shown_comp[w] - 3.5 * dt)
		else:
			_shown_comp[w] = target
		var y := -(rest - _shown_comp[w])
		var pos: Vector3 = WHEEL_POS[w]
		var pivot := wheel_pivots[w]
		pivot.position = Vector3(pos.x, y, pos.z)
		pivot.rotation.y = -steer if w < 2 else 0.0
		wheel_spinners[w].rotation.x = -fposmod(spin[w], TAU)

		# double wishbone: inner pivots fixed on the frame, outer ends follow the hub
		var sx := signf(pos.x)
		var hub_x := absf(pos.x) - float(WHEEL_W[w]) * 0.5 - 0.06
		var lk: Dictionary = _links[w]
		var lower_in := Vector3(FRAME_X * sx, -0.3, pos.z)
		var lower_out := Vector3(hub_x * sx, y - 0.12, pos.z)
		var upper_in := Vector3(0.36 * sx, 0.0, pos.z)
		var upper_out := Vector3(hub_x * sx, y + 0.14, pos.z)
		_place(lk["lower"], lower_in, lower_out)
		_place(lk["upper"], upper_in, upper_out)
		# coil-over from the tower top to the lower arm; at the front from the
		# end of an outrigger on the tower, so it stands more upright
		var top := Vector3(0.4 * sx, 0.28, pos.z + 0.08)
		if w < 2:
			top = Vector3(FRONT_SPRING_TOP_X * sx, 0.3, pos.z + 0.08)
		var bottom := lower_in.lerp(lower_out, 0.75) + Vector3(0, 0.05, 0.08)
		_place(lk["spring"], top, bottom)
		_place(lk["damper"], top, bottom)


func _build_steering_wheel() -> void:
	steering_pivot = Node3D.new()
	steering_pivot.name = "SteeringWheel"
	steering_pivot.position = Vector3(0, 0.56, 0.58)
	steering_pivot.rotation = Vector3(deg_to_rad(-35.0), 0, 0)
	add_child(steering_pivot)
	steering_rot = Node3D.new()
	steering_pivot.add_child(steering_rot)
	var kit := MeshKit.new()
	# round rim: one closed tube, three spokes into a round hub
	var r := 0.15
	var rim := PackedVector3Array()
	for i in 48:
		var a := TAU * i / 48
		rim.append(Vector3(cos(a) * r, sin(a) * r, 0))
	kit.tube(rim, 0.016, 8, Palette.TYRE, true)
	# top-centre marker: a yellow sleeve over the rim
	var mark := PackedVector3Array()
	for i in 7:
		var a := PI * 0.5 + deg_to_rad(-9.0 + 3.0 * i)
		mark.append(Vector3(cos(a) * r, sin(a) * r, 0))
	kit.tube(mark, 0.0185, 8, Palette.YELLOW)
	for a in [0.0, PI, PI * 1.5]:
		var d := Vector3(cos(a), sin(a), 0)
		kit.tube(PackedVector3Array([d * 0.03 + Vector3(0, 0, -0.015), d * (r - 0.01)]), 0.01, 6, Palette.HUB)
	kit.cylinder(Vector3(0, 0, -0.02), Vector3.BACK, 0.04, 0.05, 16, Palette.HUB, Palette.HUB.darkened(0.2))
	steering_rot.add_child(kit.build_instance())
	var col := MeshKit.new()
	col.bar(Vector3(0, 0, -0.05), Vector3(0, 0, -0.3), 0.04, Palette.HUB.darkened(0.4))
	steering_pivot.add_child(col.build_instance())


# --- damage: crack along the cage header, holes ----------------------------------------

func _build_crack_holder() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_crack_points = PackedVector2Array()
	var steps := 40
	for i in steps + 1:
		var x := -HEADER_HALF + 2.0 * HEADER_HALF * i / steps
		var y := HEADER_Y - 0.01 + rng.randf_range(-0.03, 0.03)
		_crack_points.append(Vector2(x, y))
	_crack_mi = MeshInstance3D.new()
	_crack_mi.name = "Crack"
	_crack_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crack_mi)
	_holes_mi = MeshInstance3D.new()
	_holes_mi.name = "Holes"
	_holes_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_holes_mi)
	set_damage(0.0, 0)


## Crack grows left to right along the cage header, as in the original.
func set_damage(crack: float, holes: int) -> void:
	if _crack_mi == null:
		return
	if absf(crack - _last_crack) > 0.002:
		_last_crack = crack
		var kit := MeshKit.new()
		var z := HEADER_Z + 0.03
		var count := int(round(crack * (_crack_points.size() - 1)))
		for i in count:
			var p0 := _crack_points[i]
			var p1 := _crack_points[i + 1]
			var w := 0.009
			kit.quad(Vector3(p0.x, p0.y - w, z), Vector3(p1.x, p1.y - w, z),
				Vector3(p1.x, p1.y + w, z), Vector3(p0.x, p0.y + w, z), Palette.BLACK)
			if i % 7 == 3:
				kit.tri(Vector3(p0.x, p0.y, z), Vector3(p0.x + 0.02, p0.y + 0.04, z), Vector3(p0.x + 0.03, p0.y + 0.035, z), Palette.BLACK)
		_crack_mi.mesh = kit.build()
	if holes != _last_holes:
		_last_holes = holes
		var hk := MeshKit.new()
		for h in holes:
			var x := -0.38 + 0.11 * h
			var c := Vector3(x, HEADER_Y + 0.035, HEADER_Z + 0.031)
			for k in 6:
				var a0 := TAU * k / 6.0
				var a1 := TAU * (k + 1) / 6.0
				hk.tri(c, c + Vector3(cos(a0), sin(a0), 0) * 0.02, c + Vector3(cos(a1), sin(a1), 0) * 0.02, Palette.BLACK)
		_holes_mi.mesh = hk.build()


func set_steering_wheel_deg(deg: float) -> void:
	if steering_rot:
		steering_rot.rotation.z = -deg_to_rad(deg)
