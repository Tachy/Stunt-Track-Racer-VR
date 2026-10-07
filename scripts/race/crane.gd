class_name Crane
extends Node3D
## The crane that holds the car on chains at the start and after falling off.
##
## The four chains are simulated (Verlet particles with fixed link spacing and
## gravity): taut while the car hangs on them, after the drop they swing free
## from the hook and are dragged up as the crane lifts away. They are drawn as
## real interlocking oval links, every second one turned by 90 degrees.

const HOOK_HEIGHT := 2.8
const CORNERS := [Vector3(-0.32, -0.15, -2.0), Vector3(0.32, -0.15, -2.0), Vector3(-0.46, 1.32, 1.4), Vector3(0.46, 1.32, 1.4)]

## Chain links: length, width and wire thickness (m); two links per particle.
const LINK_LEN := 0.13
const LINK_W := 0.07
const LINK_WIRE := 0.018
const PARTICLE_STEP := 0.2
const ITERATIONS := 12
const DAMPING := 0.995    # per physics step: air drag / friction in the links

var _rig: Node3D
var _tween: Tween
var _chains: Array = []   # per chain: {pts, prev, end (local), seg}
var _free := false
var _xf := Transform3D()   # where the crane holds the car (world)
var _links: MultiMeshInstance3D
static var _link_mesh: ArrayMesh


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
	_rig.add_child(kit.build_instance())

	_links = MultiMeshInstance3D.new()
	_links.top_level = true   # instance transforms are in world space
	_links.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = link_mesh()
	var total := 0
	for c in CORNERS:
		var n := maxi(2, int(ceil((c as Vector3).distance_to(Vector3(0, HOOK_HEIGHT, 0)) / PARTICLE_STEP)))
		_chains.append({"n": n, "end": c, "pts": PackedVector3Array(), "prev": PackedVector3Array(), "seg": 0.0})
		total += n * 2
	mm.instance_count = total
	_links.multimesh = mm
	add_child(_links)
	visible = false


## One oval chain link along its local Z axis.
static func link_mesh() -> ArrayMesh:
	if _link_mesh == null:
		var k := MeshKit.new()
		var hl := LINK_LEN * 0.5 - LINK_WIRE * 0.5
		var hw := LINK_W * 0.5 - LINK_WIRE * 0.5
		var r := hw * 0.6   # corner chamfer: an oval, not a rectangle
		var ring := [Vector3(-hw, 0, -hl + r), Vector3(-hw, 0, hl - r), Vector3(-hw + r, 0, hl),
			Vector3(hw - r, 0, hl), Vector3(hw, 0, hl - r), Vector3(hw, 0, -hl + r),
			Vector3(hw - r, 0, -hl), Vector3(-hw + r, 0, -hl)]
		for i in ring.size():
			k.bar(ring[i], ring[(i + 1) % ring.size()], LINK_WIRE, Palette.CHAIN.lightened(0.15))
		_link_mesh = k.build()
	return _link_mesh


## Show the crane holding a car whose transform is car_xform.
func hold(car_xform: Transform3D) -> void:
	if _tween:
		_tween.kill()
	visible = true
	_rig.position = Vector3.ZERO
	_xf = car_xform
	if is_inside_tree():
		global_transform = car_xform
	_free = false
	_pin_chains()
	_draw_links()


func follow(car_xform: Transform3D) -> void:
	_xf = car_xform
	global_transform = car_xform
	if not _free:
		_pin_chains()


## Car dropped: the chains swing free and the crane lifts away.
func release() -> void:
	if _tween:
		_tween.kill()
	_free = true
	_tween = create_tween()
	_tween.tween_property(_rig, "position:y", 30.0, 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func(): visible = false)


func _hook() -> Vector3:
	return _xf * (_rig.position + Vector3(0, HOOK_HEIGHT, 0))


## Taut chains from the hook straight to the car corners, at rest.
func _pin_chains() -> void:
	var hook := _hook()
	for ch in _chains:
		var n: int = ch["n"]
		var end: Vector3 = _xf * (ch["end"] as Vector3)
		var pts := PackedVector3Array()
		pts.resize(n + 1)
		for i in n + 1:
			pts[i] = hook.lerp(end, float(i) / n)
		ch["pts"] = pts
		ch["prev"] = pts.duplicate()
		ch["seg"] = hook.distance_to(end) / n


func _physics_process(dt: float) -> void:
	if not visible:
		return
	if _free:
		_simulate(dt)
	_draw_links()


## Verlet step: gravity and damping, then the link lengths (first particle
## hangs on the hook, the rest is free).
func _simulate(dt: float) -> void:
	var hook := _hook()
	var g := Vector3.DOWN * 9.81 * dt * dt
	for ch in _chains:
		var pts: PackedVector3Array = ch["pts"]
		var prev: PackedVector3Array = ch["prev"]
		var seg: float = ch["seg"]
		var n := pts.size()
		for i in range(1, n):
			var p := pts[i]
			pts[i] = p + (p - prev[i]) * DAMPING + g
			prev[i] = p
		prev[0] = pts[0]
		pts[0] = hook
		for _it in ITERATIONS:
			pts[0] = hook
			for i in n - 1:
				var d := pts[i + 1] - pts[i]
				var l := d.length()
				if l < 1e-6:
					continue
				var corr := d * ((l - seg) / l)
				if i == 0:
					pts[1] -= corr          # the hook does not give way
				else:
					pts[i] += corr * 0.5
					pts[i + 1] -= corr * 0.5
		ch["pts"] = pts
		ch["prev"] = prev


## Two interlocking links per segment, alternately turned by 90 degrees.
func _draw_links() -> void:
	var mm := _links.multimesh
	var k := 0
	for ch in _chains:
		var pts: PackedVector3Array = ch["pts"]
		if pts.is_empty():
			continue
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var dir := b - a
			if dir.length() < 1e-5:
				dir = Vector3.DOWN
			var z := dir.normalized()
			var helper := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
			var x := helper.cross(z).normalized()
			var y := z.cross(x)
			var basis := Basis(x, y, z)
			for h in 2:
				var twist := basis if (k % 2 == 0) else Basis(y, -x, z)
				mm.set_instance_transform(k, Transform3D(twist, a.lerp(b, 0.25 + 0.5 * h)))
				k += 1
