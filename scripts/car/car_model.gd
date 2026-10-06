class_name CarModel
extends Node3D
## Low-poly stunt car in the style of the original: the cockpit sits far back,
## in front of the driver a long nose with an exposed V-engine and big
## free-standing front wheels on visible double-wishbone suspension with
## coil-over springs that compress and extend with the physics.
## Origin = suspension mount height, forward = -Z.

## Wheel mount points (FL, FR, RL, RR) and radii - shared with PlayerCar.
const WHEEL_POS := [Vector3(-0.98, 0.0, -1.75), Vector3(0.98, 0.0, -1.75),
		Vector3(-0.98, 0.0, 1.15), Vector3(0.98, 0.0, 1.15)]
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

const FRAME_X := 0.32
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
static var _unit_bar: ArrayMesh
static var _unit_coil: ArrayMesh


func build(body_color: Color, cockpit: bool) -> CarModel:
	var kit := MeshKit.new()
	_build_chassis(kit, body_color)
	_build_engine(kit)
	_build_cabin(kit, body_color, cockpit)
	var body := kit.build_instance()
	body.name = "Body"
	add_child(body)

	_build_wheels()
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


func _build_engine(kit: MeshKit) -> void:
	var z0 := -0.95
	# block
	kit.box(Vector3(0, -0.02, z0), Vector3(0.5, 0.36, 1.05), METAL)
	# V cylinder heads
	for sx in [-1.0, 1.0]:
		kit.box(Vector3(0.2 * sx, 0.24, z0), Vector3(0.2, 0.26, 1.0), HEADS, Basis(Vector3.FORWARD, deg_to_rad(30.0) * sx))
		# exhaust headers: four pipes per side sweeping out and back
		for k in 4:
			var z := z0 - 0.38 + k * 0.25
			var a := Vector3(0.33 * sx, 0.24, z)
			var b := Vector3(0.58 * sx, 0.08, z + 0.05)
			kit.bar(a, b, 0.05, EXHAUST)
			kit.bar(b, Vector3(0.62 * sx, -0.04, 0.15), 0.05, EXHAUST)
		kit.bar(Vector3(0.62 * sx, -0.04, 0.15), Vector3(0.66 * sx, -0.08, 1.9), 0.09, EXHAUST.darkened(0.2))
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
	for sx in [-1.0, 1.0]:
		kit.box(Vector3(0.52 * sx, 0.12, 0.98), Vector3(0.08, 0.56, 1.46), body_color)
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
		kit.bar(Vector3(0.52 * sx, 0.4, 0.26), Vector3(HEADER_HALF * sx, HEADER_Y, HEADER_Z), t, Palette.CAGE)
		kit.bar(Vector3(HEADER_HALF * sx, HEADER_Y, HEADER_Z), Vector3(HEADER_HALF * sx, HEADER_Y, 1.4), t, Palette.CAGE)
		kit.bar(Vector3(HEADER_HALF * sx, HEADER_Y, 1.4), Vector3(0.52 * sx, 0.42, 1.68), t, Palette.CAGE)
	kit.box(Vector3(0, HEADER_Y, HEADER_Z), Vector3(HEADER_HALF * 2.0 + t, 0.11, 0.05), Palette.CAGE)
	kit.bar(Vector3(-HEADER_HALF, HEADER_Y, 1.4), Vector3(HEADER_HALF, HEADER_Y, 1.4), t, Palette.CAGE)
	kit.bar(Vector3(-HEADER_HALF, HEADER_Y, 1.4), Vector3(0.4, 0.45, 1.68), t * 0.8, Palette.CAGE)
	if not cockpit:
		kit.box(Vector3(0, 0.96, 1.0), Vector3(0.3, 0.3, 0.32), Palette.WHITE)
		kit.box(Vector3(0, 0.96, 0.85), Vector3(0.26, 0.1, 0.04), Palette.BLACK)


# --- wheels & suspension ------------------------------------------------------------

static func _bar_mesh() -> ArrayMesh:
	if _unit_bar == null:
		var k := MeshKit.new()
		k.box(Vector3(0, 0, -0.5), Vector3(1, 1, 1), METAL.lightened(0.15))
		_unit_bar = k.build()
	return _unit_bar


## Coil spring of unit length along -Z (scaling along Z compresses the coils).
static func _coil_mesh() -> ArrayMesh:
	if _unit_coil == null:
		var k := MeshKit.new()
		var turns := 7
		var seg := 8
		var r := 0.075
		var prev := Vector3(r, 0, 0)
		for i in turns * seg:
			var a := TAU * (i + 1) / seg
			var p := Vector3(cos(a) * r, sin(a) * r, -float(i + 1) / (turns * seg))
			k.box((prev + p) * 0.5, Vector3(0.025, 0.025, 0.06), Palette.YELLOW, Basis.looking_at((p - prev).normalized(), Vector3.UP))
			prev = p
		_unit_coil = k.build()
	return _unit_coil


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
			"damper": _link(_bar_mesh(), 0.03),
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
		# coil-over from the tower top to the lower arm
		var top := Vector3(0.4 * sx, 0.28, pos.z + 0.08)
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
	var r := 0.15
	var seg := 14
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		kit.bar(Vector3(cos(a0) * r, sin(a0) * r, 0), Vector3(cos(a1) * r, sin(a1) * r, 0), 0.03, Palette.TYRE)
	kit.bar(Vector3(-r, 0, 0), Vector3(r, 0, 0), 0.025, Palette.HUB)
	kit.bar(Vector3(0, 0, 0), Vector3(0, -r, 0), 0.025, Palette.HUB)
	kit.box(Vector3(0, r, 0.005), Vector3(0.03, 0.035, 0.04), Palette.YELLOW)
	kit.box(Vector3(0, 0, -0.04), Vector3(0.06, 0.06, 0.08), Palette.HUB)
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
