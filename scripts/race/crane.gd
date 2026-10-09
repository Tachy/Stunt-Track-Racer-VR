class_name Crane
extends Node3D
## The crane that sets the car onto the track at the start and after falling
## off. It stands beside the road, its jib across it at a fixed height that
## follows the road height there. The car starts on the ground beside the
## road below the trolley; the winch pulls the chain in (in a fixed time: the
## higher the road, the faster), then the trolley carries the car sideways
## over the road, where it hangs until the drop.
##
## The car on its chains is a physical pendulum swinging across the road: a
## chain from the trolley to the hook (CHAIN_LEN once pulled in), four slings
## from the hook to the car. Mass and roll inertia of the car, the trolley's
## acceleration, the changing chain length, air drag on the car's side and
## friction in the chain links drive and damp the swing. (The period depends
## on the chain length and the mass distribution, not on the mass itself; the
## mass decides how much the air drag damps.) At the drop the car keeps the
## swing's velocity.
##
## After the drop the chains are simulated (Verlet particles with fixed link
## spacing and gravity) and swing free from the trolley. They are drawn as real
## interlocking oval links, every second one turned by 90 degrees.
##
## The crane's frame is the car's pose over the road (target): x across the
## road, y up, -z along it.

const HOOK_HEIGHT := 2.8          # hook above the car origin
const CHAIN_LEN := 2.5            # chain from the trolley to the hook, pulled in
const PIVOT := HOOK_HEIGHT + CHAIN_LEN   # trolley above the car origin, pulled in
const CORNERS := [Vector3(-0.32, -0.15, -2.0), Vector3(0.32, -0.15, -2.0), Vector3(-0.46, 1.32, 1.4), Vector3(0.46, 1.32, 1.4)]

## The car as a pendulum body: centre of mass (PlayerCar.center_of_mass), a
## box of this width and height for its roll inertia, its side area for drag.
const CAR_COM := Vector3(0, -0.3, -0.28)
const CAR_ROLL_BOX := Vector2(2.2, 1.2)
const SIDE_AREA := 4.5            # m2
const DRAG_CD := 1.1
const AIR_DENSITY := 1.2          # kg/m3
const LINK_FRICTION := 0.005      # m: friction torque in the links = this x chain tension

## Sequence: on the ground, pull the chain in, carry over the road (trolley,
## without jerk; it sets off TROLLEY_LEAD before the chain is all in), let the chain out
## (only where the road lies lower than the ground spot or a banked road's
## upper edge). Winch and trolley both move without jerk.
const GROUND_GAP := 3.0           # car origin this far beside the road edge
const EDGE_CLEAR := 1.0           # wheels this high over the edge of a cut
const WAIT_TIME := 0.6            # on the ground before the lift (chains tighten)
const LIFT_TIME := 2.0
const TROLLEY_LEAD := 2.0         # chain (m) still to pull in when the trolley sets off
const CAR_HALF_WIDTH := 1.1       # dropped early only with the car all over the road
## Trolley run over the road (minimum jerk). The swing it leaves depends on
## this time against the pendulum's period (~4.8 s): 4 s leaves 35-70 deg,
## 7.5 s 4-11 deg (up to ~1 m sideways), 9.5 s (two periods) almost none.
const TROLLEY_TIME := 7.5
const TOWER_OUT := 4.0            # tower beyond the ground spot
const JIB_OVER := 4.0             # jib reaches this far beyond the target
const COUNTER_JIB := 7.0
## After the drop the trolley runs back off the road, over the ground spot.
const RETURN_DELAY := 1.0
const RETURN_TIME := 6.0

## Chain links: length, width and wire thickness (m); two links per particle.
const LINK_LEN := 0.13
const LINK_W := 0.07
const LINK_WIRE := 0.018
const PARTICLE_STEP := 0.2
const MAX_CHAIN := 40.0           # longest main chain drawn (m)
const ITERATIONS := 12
const DAMPING := 0.995            # per physics step: air drag / friction in the links

var _mode := "idle"               # idle, lift (simulated), hang (shown at a given car pose), free
var _target := Transform3D()      # car pose over the road (= the crane's frame, world)
var _car_xf := Transform3D()      # car pose now (world)
var _pivot := Vector3.ZERO        # trolley pivot now (world)
var _jib_y := PIVOT               # trolley pivot height (crane frame), fixed
var _t := 0.0                     # time since the sequence started
## Motion plan per axis (trolley x, chain length): [{t0, dur, a, b, kind}].
var _plan_x: Array = []
var _plan_c: Array = []
var _total := 0.0
var _lagged := false              # the car has hung back behind the trolley
var _swung := false               # ... and swung through below it since
var _side := 1.0                  # side of the ground spot (crane x)
var _road := Vector2(-INF, INF)   # the road (crane x) where the car may land
var _home_x := 0.0                # trolley x over the ground spot
var _plan_back: Array = []        # the trolley's way back after the drop
var _t_free := 0.0                # time since the drop
var _pos := Vector2.ZERO          # trolley x (crane frame), chain length
var _vel := Vector2.ZERO
# pendulum: angle of the car from hanging straight down (towards +x), rate
var _phi := 0.0
var _omega := 0.0
var _mass := 900.0
var _inertia := 1.0               # about the pivot
var _com_dist := 1.0              # pivot -> centre of mass
var _x_range := Vector2.ZERO      # crane x the trolley travels (min, max)

var _top: Node3D                  # jib
var _trolley: Node3D
var _mast: MeshInstance3D
var _hook: MeshInstance3D
var _chains: Array = []           # [main chain, 4 slings]: {n, end, pts, prev, seg}
var _links: MultiMeshInstance3D
static var _link_mesh: ArrayMesh


func _init() -> void:
	name = "Crane"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_top = Node3D.new()
	add_child(_top)
	_trolley = Node3D.new()
	_top.add_child(_trolley)
	var kit := MeshKit.new()
	kit.box(Vector3(0, 0.25, 0), Vector3(1.0, 0.5, 1.4), Palette.CRANE.darkened(0.2))
	for x in [-0.4, 0.4]:
		kit.cylinder(Vector3(x, 0.55, 0), Vector3(0, 0, 1), 0.12, 1.2, 10, Palette.CHAIN)
	_trolley.add_child(kit.build_instance())
	kit = MeshKit.new()
	kit.box(Vector3.ZERO, Vector3(0.45, 0.4, 0.3), Palette.CRANE)
	_hook = kit.build_instance()
	_hook.top_level = true
	add_child(_hook)

	_links = MultiMeshInstance3D.new()
	_links.top_level = true   # instance transforms are in world space
	_links.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = link_mesh()
	var total := int(ceil(MAX_CHAIN / PARTICLE_STEP)) * 2
	_chains.append({"n": 2, "end": Vector3(0, HOOK_HEIGHT, 0), "pts": PackedVector3Array(), "prev": PackedVector3Array(), "seg": 0.0})
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


## Puts the crane up for a car that starts at ground (world pose, beside the
## road) and is dropped at target (over the road): tower beside the ground
## spot, jib across the road at the height the road there asks for. travel:
## how high (crane y) the car must be carried over the road (a banked road's
## upper edge). Does not move the car.
func setup(target: Transform3D, ground: Transform3D, travel := 0.0) -> void:
	_target = target
	if is_inside_tree():
		global_transform = target
	var g := target.affine_inverse() * ground.origin
	var side := signf(g.x) if absf(g.x) > 0.01 else 1.0
	# the trolley as high above the highest of road, its upper edge and the
	# ground spot as the pulled-in chain needs
	_jib_y = maxf(g.y + EDGE_CLEAR if g.y > 0.0 else 0.0, travel) + PIVOT
	var hanging := _jib_y - HOOK_HEIGHT       # chain length with the car at y = 0
	var start := Vector2(g.x, _jib_y - g.y - HOOK_HEIGHT)
	_side = side
	_home_x = g.x
	_plan_x.clear()
	_plan_c.clear()
	_total = 0.0
	var pull := start.y - CHAIN_LEN
	_plan(_plan_c, start.y, CHAIN_LEN, WAIT_TIME, LIFT_TIME)
	var t_x := WAIT_TIME
	if pull > TROLLEY_LEAD:
		t_x += LIFT_TIME * _smooth_at(1.0 - TROLLEY_LEAD / pull)
	_plan(_plan_x, g.x, 0.0, t_x, TROLLEY_TIME)
	_plan(_plan_c, CHAIN_LEN, hanging, t_x + TROLLEY_TIME, LIFT_TIME)
	_total = maxf(_total, WAIT_TIME)
	_lagged = false
	_swung = false
	_x_range = Vector2(minf(g.x, 0.0), maxf(g.x, 0.0))
	_build_structure(g, side)
	_pos = start
	_vel = Vector2.ZERO
	visible = true


## A move of one axis from a to b, starting at t0 (none if there is no way to go).
func _plan(axis: Array, a: float, b: float, t0: float, dur: float) -> void:
	if absf(b - a) < 0.05:
		return
	axis.append({"t0": t0, "dur": dur, "a": a, "b": b})
	_total = maxf(_total, t0 + dur)


## Minimum jerk move (winch and trolley alike): share of the way at time
## share u - long, gentle phases of speeding up and slowing down.
static func _smooth(u: float) -> float:
	return u * u * u * (10.0 - 15.0 * u + 6.0 * u * u)


## Time share at which a minimum jerk move has done share f of its way.
static func _smooth_at(f: float) -> float:
	var lo := 0.0
	var hi := 1.0
	for _it in 40:
		var mid := (lo + hi) * 0.5
		if _smooth(mid) < f:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## Mast from the ground up to the jib, jib across the road with the counter
## jib and its weight.
func _build_structure(g: Vector3, side: float) -> void:
	for c in _top.get_children():
		if c != _trolley:
			c.queue_free()
	if _mast:
		_mast.queue_free()
	var tx := g.x + side * TOWER_OUT
	var ground_y := g.y - CarModel.RIDE_HEIGHT
	var col := Palette.CRANE
	var dark := Palette.CRANE.darkened(0.3)
	var kit := MeshKit.new()
	_lattice(kit, Vector3(tx, ground_y, 0), _jib_y + 0.8 - ground_y, 1.6, col, dark)
	kit.box(Vector3(tx, ground_y + 0.15, 0), Vector3(3.0, 0.3, 3.0), dark)
	_mast = kit.build_instance()
	add_child(_mast)
	_top.position = Vector3(0, _jib_y, 0)
	kit = MeshKit.new()
	var x0 := tx + side * COUNTER_JIB
	var x1 := -side * JIB_OVER
	var mid := (x0 + x1) * 0.5
	var y := 1.2
	kit.box(Vector3(mid, y, 0), Vector3(absf(x0 - x1), 0.8, 0.8), col)
	var steps := int(absf(x0 - x1) / 2.0)
	for k in steps:
		var xa := lerpf(x0, x1, float(k) / steps)
		var xb := lerpf(x0, x1, float(k + 1) / steps)
		kit.bar(Vector3(xa, y - 0.4, -0.4), Vector3(xb, y + 0.4, -0.4), 0.08, dark)
		kit.bar(Vector3(xa, y - 0.4, 0.4), Vector3(xb, y + 0.4, 0.4), 0.08, dark)
	kit.box(Vector3(x0 - side * 1.0, y - 0.6, 0), Vector3(2.0, 1.6, 1.6), Palette.CRANE.darkened(0.45))
	_top.add_child(kit.build_instance())


## A square lattice mast of width w from base up by height h.
static func _lattice(kit: MeshKit, base: Vector3, h: float, w: float, col: Color, dark: Color) -> void:
	var r := w * 0.5
	var corners := [Vector3(-r, 0, -r), Vector3(r, 0, -r), Vector3(r, 0, r), Vector3(-r, 0, r)]
	for c in corners:
		kit.bar(base + c, base + c + Vector3(0, h, 0), 0.14, col)
	var levels := maxi(1, int(h / 2.0))
	for k in levels:
		var y0 := h * k / levels
		var y1 := h * (k + 1) / levels
		for e in 4:
			var a: Vector3 = corners[e]
			var b: Vector3 = corners[(e + 1) % 4]
			kit.bar(base + a + Vector3(0, y0, 0), base + b + Vector3(0, y1, 0), 0.06, dark)


## Car at ground (world pose beside the road), to be set down at target: the
## lift starts. mass: the car's (kg). road: the road's extent across (crane x,
## from the target) - an early drop needs the car over it.
func start(target: Transform3D, ground: Transform3D, mass: float, road := Vector2(-INF, INF), travel := 0.0) -> void:
	setup(target, ground, travel)
	_road = road
	_mode = "lift"
	_t = 0.0
	_phi = 0.0
	_omega = 0.0
	_mass = mass
	_update_body()
	_update_car()
	_pin_chains()
	_draw_links()


## Distance to the centre of mass and inertia about the trolley for the
## chain length now.
func _update_body() -> void:
	_com_dist = _pos.y + HOOK_HEIGHT - CAR_COM.y
	var i_com := _mass * (CAR_ROLL_BOX.x * CAR_ROLL_BOX.x + CAR_ROLL_BOX.y * CAR_ROLL_BOX.y) / 12.0
	_inertia = i_com + _mass * _com_dist * _com_dist


## The sequence takes this long (s) until the car hangs over the road.
func duration() -> float:
	return _total


## The crane is done: the car hangs over the road (still swinging).
func arrived() -> bool:
	return _mode == "lift" and _t >= _total


## The car may be dropped: it has swung through below the trolley once
## (trolley maybe still running, the car still moving sideways) and hangs
## over the road, or the crane is done.
func droppable() -> bool:
	if _mode != "lift":
		return false
	if _t >= _total:
		return true
	var cx := (_target.affine_inverse() * _car_xf.origin).x
	return _swung and cx > _road.x + CAR_HALF_WIDTH and cx < _road.y - CAR_HALF_WIDTH


func lifting() -> bool:
	return _mode == "lift"


## Where the car hangs at rest over the road (world).
func drop_pose() -> Transform3D:
	return _target


## Where the car is now (world).
func car_xform() -> Transform3D:
	return _car_xf


## Velocity of the car's centre of mass (com: car-local) and its angular
## velocity, both world: what it keeps when dropped.
func car_velocity(com: Vector3) -> Array:
	var axis := _target.basis.z.normalized()
	var w := axis * _omega
	var down := (_car_xf.origin - _pivot).normalized()
	var v := _target.basis * Vector3(_vel.x, 0.0, 0.0) + down * _vel.y
	return [v + w.cross(_car_xf * com - _pivot), w]


## One physics step of the sequence and the swing.
func step(dt: float) -> void:
	if _mode != "lift":
		return
	_t += dt
	var i0 := _inertia
	var acc := _eval(_t)
	_update_body()
	if _t > WAIT_TIME:
		# physical pendulum on the trolley, chain length changing:
		# d(I w)/dt = -m d (g sin phi + ax cos phi) + drag + friction
		var torque := -_mass * _com_dist * (9.81 * sin(_phi) + acc.x * cos(_phi))
		# air drag on the side of the car: its speed across the road
		var vx := _vel.x + _com_dist * _omega * cos(_phi) + _vel.y * sin(_phi)
		var drag := -0.5 * AIR_DENSITY * DRAG_CD * SIDE_AREA * vx * absf(vx)
		torque += drag * _com_dist * cos(_phi)
		_omega = (i0 * _omega + torque * dt) / _inertia
		# friction in the links: stops a slow swing instead of reversing it
		var dw := LINK_FRICTION * _mass * 9.81 / _inertia * dt
		_omega = 0.0 if absf(_omega) <= dw else _omega - signf(_omega) * dw
		_phi += _omega * dt
	_update_car()
	# the trolley pulls away: the car hangs back (towards where it came
	# from), then swings through below the trolley (the rest position)
	if _phi * _side > deg_to_rad(0.5):
		_lagged = true
	elif _lagged and _phi * _side <= 0.0:
		_swung = true


## Trolley x and chain length (and their rates, kept in _pos/_vel) at time t;
## returns their accelerations.
func _eval(t: float) -> Vector2:
	var x := _eval_axis(_plan_x, t, _pos.x)
	var c := _eval_axis(_plan_c, t, _pos.y)
	_pos = Vector2(x[0], c[0])
	_vel = Vector2(x[1], c[1])
	return Vector2(x[2], c[2])


## [position, rate, acceleration] of one axis at t (keep: where it rests
## before its first move).
static func _eval_axis(axis: Array, t: float, keep: float) -> Array:
	if axis.is_empty():
		return [keep, 0.0, 0.0]
	var seg: Dictionary = axis[0]
	if t < float(seg["t0"]):
		return [float(seg["a"]), 0.0, 0.0]
	for sg in axis:
		if t >= float(sg["t0"]):
			seg = sg
	var a: float = seg["a"]
	var d: float = float(seg["b"]) - a
	var dur: float = seg["dur"]
	var u := (t - float(seg["t0"])) / dur
	if u >= 1.0:
		return [a + d, 0.0, 0.0]
	# minimum jerk: no sudden change of acceleration
	return [a + d * _smooth(u),
		d / dur * 30.0 * u * u * (1.0 - u) * (1.0 - u),
		d / (dur * dur) * 60.0 * u * (1.0 - u) * (1.0 - 2.0 * u)]


func _place_pivot() -> void:
	_trolley.position = Vector3(_pos.x, 0.0, 0.0)
	_pivot = _target * Vector3(_pos.x, _jib_y, 0.0)


## The car hangs from the trolley at the swing angle.
func _update_car() -> void:
	_place_pivot()
	var rot := Basis(_target.basis.z.normalized(), _phi)
	var basis := rot * _target.basis
	_car_xf = Transform3D(basis, _pivot - basis * Vector3(0, _pos.y + HOOK_HEIGHT, 0))
	_place_hook()


func _place_hook() -> void:
	var hook := _hook_pos()
	var up := (_pivot - hook).normalized()
	var fwd := _target.basis.z.normalized()
	var x := up.cross(fwd).normalized()
	_hook.global_transform = Transform3D(Basis(x, up, x.cross(up)), hook + up * 0.15)


## Shows the crane holding a car at car_xform (online: the other player's
## car, whose crane runs on its own machine): the trolley above the hook,
## the chain as long as it takes.
func hang(car_xform: Transform3D) -> void:
	_mode = "hang"
	_car_xf = car_xform
	var inv := _target.affine_inverse()
	var hook := inv * _hook_pos()
	var up := inv.basis * car_xform.basis.y.normalized()
	var c := (_jib_y - hook.y) / maxf(up.y, 0.2)
	_pos = Vector2(hook.x + up.x * c, c)
	_place_pivot()
	_place_hook()
	_pin_chains()


## Whether a car at pos (world) can hang from this crane as it stands.
func covers(pos: Vector3) -> bool:
	if not visible:
		return false
	var p := _target.affine_inverse() * pos
	return absf(p.z) < 2.0 and p.x > _x_range.x - 3.0 and p.x < _x_range.y + 3.0


## Car dropped: the chains swing free from the trolley.
func release() -> void:
	_mode = "free"
	_t_free = 0.0
	_plan_back.clear()
	if absf(_pos.x - _home_x) > 0.05:
		_plan_back.append({"t0": RETURN_DELAY, "dur": RETURN_TIME, "a": _pos.x, "b": _home_x})


func _hook_pos() -> Vector3:
	return _car_xf * Vector3(0, HOOK_HEIGHT, 0)


## Taut chains: trolley -> hook, hook -> car corners, at rest.
func _pin_chains() -> void:
	var hook := _hook_pos()
	_chains[0]["n"] = clampi(int(ceil(_pivot.distance_to(hook) / PARTICLE_STEP)), 2, int(ceil(MAX_CHAIN / PARTICLE_STEP)))
	for k in _chains.size():
		var ch: Dictionary = _chains[k]
		var n: int = ch["n"]
		var a := _pivot if k == 0 else hook
		var end := hook if k == 0 else _car_xf * (ch["end"] as Vector3)
		var pts := PackedVector3Array()
		pts.resize(n + 1)
		for i in n + 1:
			pts[i] = a.lerp(end, float(i) / n)
		ch["pts"] = pts
		ch["prev"] = pts.duplicate()
		ch["seg"] = a.distance_to(end) / n


func _physics_process(dt: float) -> void:
	if not visible:
		return
	if _mode == "free":
		# the trolley runs back off the road, the chains swing along
		_t_free += dt
		_pos.x = _eval_axis(_plan_back, _t_free, _pos.x)[0]
		_place_pivot()
		_simulate(dt)
		var main: PackedVector3Array = _chains[0]["pts"]
		var hook := main[main.size() - 1]
		var up := (main[main.size() - 2] - hook).normalized()
		var fwd := _target.basis.z.normalized()
		var x := up.cross(fwd).normalized()
		if x.length() > 0.5:
			_hook.global_transform = Transform3D(Basis(x, up, x.cross(up)), hook + up * 0.15)
	elif _mode == "lift":
		_pin_chains()
	_draw_links()


## Verlet step: gravity and damping, then the link lengths. The main chain
## hangs from the trolley, the slings from the main chain's end (the hook).
func _simulate(dt: float) -> void:
	var g := Vector3.DOWN * 9.81 * dt * dt
	for k in _chains.size():
		var ch: Dictionary = _chains[k]
		var main: PackedVector3Array = _chains[0]["pts"]
		var anchor := _pivot if k == 0 else main[main.size() - 1]
		var pts: PackedVector3Array = ch["pts"]
		var prev: PackedVector3Array = ch["prev"]
		var seg: float = ch["seg"]
		var n := pts.size()
		for i in range(1, n):
			var p := pts[i]
			pts[i] = p + (p - prev[i]) * DAMPING + g
			prev[i] = p
		prev[0] = pts[0]
		pts[0] = anchor
		for _it in ITERATIONS:
			pts[0] = anchor
			for i in n - 1:
				var d := pts[i + 1] - pts[i]
				var l := d.length()
				if l < 1e-6:
					continue
				var corr := d * ((l - seg) / l)
				if i == 0:
					pts[1] -= corr          # the anchor does not give way
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
	mm.visible_instance_count = k
