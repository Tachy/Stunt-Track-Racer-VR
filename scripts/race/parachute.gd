class_name Parachute
extends Node3D
## The player's parachute in the race: a ParachuteSim on the car's hook (as
## high over the car as the crane's), drawn as a classic round canopy of red
## and white gores with its lines - four slings from the car's corners to
## the hook (as the crane's), the main line, the lines to the rim. Cut away
## after the touchdown it drifts down on its own and is gone.

const GORES := 16
const RIM_LINES := 8
const LINE_W := 0.04
const CUT_LIFE := 3.0            # s the cut canopy is still seen
const RISER := 0.3               # share of the line that is the main line

var sim: ParachuteSim
var _car: PlayerCar
var _canopy: MeshInstance3D
var _lines: MultiMeshInstance3D
var _cut_time := 0.0
static var _dome: ArrayMesh
static var _rod: ArrayMesh


func _init(car: PlayerCar) -> void:
	name = "Parachute"
	_car = car
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_canopy = MeshInstance3D.new()
	_canopy.mesh = dome_mesh()
	add_child(_canopy)
	_lines = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = rod_mesh()
	mm.instance_count = Crane.CORNERS.size() + 1 + RIM_LINES
	_lines.multimesh = mm
	add_child(_lines)
	visible = false


## The canopy: rim of radius 1 at y = 0, crown at y = 1; gores red and white.
static func dome_mesh() -> ArrayMesh:
	if _dome == null:
		var k := MeshKit.new()
		var rings := 5
		for g in GORES:
			var col := Palette.RED if g % 2 == 0 else Palette.WHITE
			var a0 := TAU * g / GORES
			var a1 := TAU * (g + 1) / GORES
			for r in rings:
				var p0 := PI * 0.5 * r / rings
				var p1 := PI * 0.5 * (r + 1) / rings
				var v00 := Vector3(cos(p0) * cos(a0), sin(p0), cos(p0) * sin(a0))
				var v01 := Vector3(cos(p0) * cos(a1), sin(p0), cos(p0) * sin(a1))
				var v10 := Vector3(cos(p1) * cos(a0), sin(p1), cos(p1) * sin(a0))
				var v11 := Vector3(cos(p1) * cos(a1), sin(p1), cos(p1) * sin(a1))
				k.tri(v00, v10, v11, col)
				k.tri(v00, v11, v01, col)
		_dome = k.build()
	return _dome


## A line: a rod of unit length along +Z and unit thickness (scaled per line).
static func rod_mesh() -> ArrayMesh:
	if _rod == null:
		var k := MeshKit.new()
		k.box(Vector3(0, 0, 0.5), Vector3.ONE, Palette.WHITE.darkened(0.15))
		_rod = k.build()
	return _rod


## The hook over the car (car frame), where the lines meet.
static func hook_local() -> Vector3:
	return Vector3(0, Crane.HOOK_HEIGHT, 0)


func active() -> bool:
	return sim != null and not sim.cut


## Fires it: the packet leaves the hook.
func fire() -> void:
	var hook := _car.global_transform * hook_local()
	sim = ParachuteSim.new(hook, _hook_velocity(hook))
	_car.chute_attached = true
	_cut_time = 0.0
	visible = true


## Cuts the lines: no more pull, the canopy drifts away.
func cut() -> void:
	if active():
		sim.cut = true
		_cut_time = 0.0
	_car.chute_attached = false


func _hook_velocity(hook: Vector3) -> Vector3:
	return _car.linear_velocity + _car.angular_velocity.cross(hook - _car.global_transform * _car.center_of_mass)


## One physics step: the line's pull on the car (called by the race before
## the car's own step).
func step(dt: float) -> void:
	if sim == null:
		return
	var hook := _car.global_transform * hook_local()
	var f := sim.step(dt, hook, _hook_velocity(hook))
	if not sim.cut:
		_car.external_force(f, hook)
		return
	_cut_time += dt
	if _cut_time > CUT_LIFE:
		sim = null
		visible = false


func _process(_dt: float) -> void:
	if sim == null:
		return
	var xf := _car.global_transform
	var hook := xf * hook_local()
	var axis := (sim.pos - hook).normalized() if not sim.cut else -sim.vel.normalized()
	if axis.length_squared() < 0.5:
		axis = Vector3.UP
	var r := lerpf(0.4, ParachuteSim.DIAMETER * 0.5, sim.opening())
	var basis := Basis.looking_at(axis, Vector3.UP if absf(axis.y) < 0.99 else Vector3.FORWARD)
	# the canopy's y axis along the line, out from the car
	var b := Basis(basis.x, axis, basis.x.cross(axis)).orthonormalized().scaled(Vector3(r, r * 0.6, r))
	_canopy.global_transform = Transform3D(b, sim.pos)
	var mm := _lines.multimesh
	if sim.cut:
		mm.visible_instance_count = 0
		return
	mm.visible_instance_count = -1
	var k := 0
	for c in Crane.CORNERS:
		mm.set_instance_transform(k, _line_xf(xf * (c as Vector3), hook))
		k += 1
	var joint := hook.lerp(sim.pos, RISER)
	mm.set_instance_transform(k, _line_xf(hook, joint))
	k += 1
	for i in RIM_LINES:
		var a := TAU * (i + 0.5) / RIM_LINES
		var rim := sim.pos + b * Vector3(cos(a), 0.0, sin(a))
		mm.set_instance_transform(k, _line_xf(joint, rim))
		k += 1


## A rod from a to b.
static func _line_xf(a: Vector3, b: Vector3) -> Transform3D:
	var d := b - a
	var l := maxf(d.length(), 0.01)
	var z := d / l
	var up := Vector3.UP if absf(z.y) < 0.99 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	return Transform3D(Basis(x * LINE_W, y * LINE_W, z * l), a)
