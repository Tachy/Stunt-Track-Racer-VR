class_name Crane
extends Node3D
## The crane that holds the car on chains at the start and after falling off.

const HOOK_HEIGHT := 2.8
const CORNERS := [Vector3(-0.32, -0.15, -2.0), Vector3(0.32, -0.15, -2.0), Vector3(-0.46, 1.32, 1.4), Vector3(0.46, 1.32, 1.4)]

var _rig: Node3D
var _tween: Tween


func _init() -> void:
	name = "Crane"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rig = Node3D.new()
	add_child(_rig)
	var kit := MeshKit.new()
	var top := 26.0
	# jib: horizontal lattice beam reaching over the car
	kit.box(Vector3(0, top, 6.0), Vector3(0.8, 0.8, 22.0), Palette.CRANE)
	for k in 11:
		var z := -4.0 + k * 2.0
		kit.bar(Vector3(-0.4, top - 0.4, z), Vector3(0.4, top + 0.4, z + 2.0), 0.08, Palette.CRANE.darkened(0.3))
	# trolley + cable
	kit.box(Vector3(0, top - 0.7, 0), Vector3(1.0, 0.6, 1.2), Palette.CRANE.darkened(0.2))
	kit.bar(Vector3(0, top - 1.0, 0), Vector3(0, HOOK_HEIGHT + 0.3, 0), 0.06, Palette.CHAIN)
	# hook block
	kit.box(Vector3(0, HOOK_HEIGHT + 0.15, 0), Vector3(0.45, 0.4, 0.3), Palette.CRANE)
	# chains to the four corners
	for c in CORNERS:
		_chain(kit, Vector3(0, HOOK_HEIGHT, 0), c)
	_rig.add_child(kit.build_instance())
	visible = false


func _chain(kit: MeshKit, a: Vector3, b: Vector3) -> void:
	var links := 8
	for i in links:
		var p0 := a.lerp(b, float(i) / links)
		var p1 := a.lerp(b, float(i + 1) / links)
		kit.bar(p0, p1.lerp(p0, 0.2), 0.05 if i % 2 == 0 else 0.035, Palette.CHAIN)


## Show the crane holding a car whose transform is car_xform.
func hold(car_xform: Transform3D) -> void:
	if _tween:
		_tween.kill()
	visible = true
	_rig.position = Vector3.ZERO
	global_transform = car_xform


func follow(car_xform: Transform3D) -> void:
	global_transform = car_xform


## Car dropped: chains go slack and the crane lifts away.
func release() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_rig, "position:y", 30.0, 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func(): visible = false)
