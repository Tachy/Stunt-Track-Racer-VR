class_name AiProfile
## Target speed per track sample for the path-following opponent
## (the original used a hand-made speed table per piece; we derive it from
## the geometry: curve radius, crests, braking distances and jump speeds).

const VMAX := 62.0
const VMAX_SUPER := 70.0
const LAT_ACCEL := 9.0
## deg/s of road twist the driver accepts (banking in/out of curves)
const MAX_ROLL_RATE := 30.0
const BRAKE := 9.0
const G := 9.81
const SPAN := 6
## Acceleration assumed when planning the run-up to a jump (m/s^2).
const ACCEL_PLAN := 3.0


static func compute(path: TrackPath, super_league := false) -> PackedFloat32Array:
	var n := path.n
	var vmax := VMAX_SUPER if super_league else VMAX
	var v := PackedFloat32Array()
	v.resize(n)
	for i in n:
		if _near_loop(path, i):
			v[i] = vmax       # loops are handled by floors()
			continue
		var a := path.forward[(i - SPAN + n) % n]
		var b := path.forward[(i + SPAN) % n]
		var fa := Vector2(a.x, a.z).normalized()
		var fb := Vector2(b.x, b.z).normalized()
		var ang := absf(fa.angle_to(fb))
		var limit := vmax
		if ang > 0.001:
			var radius := (2.0 * SPAN * TrackPath.STEP) / ang
			var bank := absf(path.right[i].y)
			limit = minf(limit, sqrt((LAT_ACCEL + G * bank) * radius))
		# crests: allow some air, but not absurd launches
		var h0 := path.center[(i - SPAN + n) % n].y
		var h1 := path.center[i].y
		var h2 := path.center[(i + SPAN) % n].y
		var kv := (h2 - 2.0 * h1 + h0) / float(SPAN * SPAN)
		# twisting road (banking in/out): keep the roll rate moderate
		var j := (i + 1) % n
		var twist := absf(rad_to_deg(asin(clampf(path.right[j].y, -1.0, 1.0)) - asin(clampf(path.right[i].y, -1.0, 1.0)))) / TrackPath.STEP
		if twist > 0.05:
			limit = minf(limit, MAX_ROLL_RATE / twist)
		if kv < -1e-4 and path.road[i] == 1:
			limit = minf(limit, sqrt(G / -kv) * 1.0)   # no air on crests (no steering in the air)
		v[i] = maxf(limit, 12.0)

	# braking distances (two passes around the loop)
	for _pass in 2:
		for k in n:
			var i := n - 1 - k
			var j := (i + 1) % n
			v[i] = minf(v[i], sqrt(v[j] * v[j] + 2.0 * BRAKE * TrackPath.STEP))

	return v


## Minimum speeds that must not be scaled down by driver skill:
## jump approaches and the drawbridge.
static func floors(path: TrackPath, super_league := false) -> PackedFloat32Array:
	var n := path.n
	var vmax := VMAX_SUPER if super_league else VMAX
	var f := PackedFloat32Array()
	f.resize(n)
	for g in path.gaps():
		var i0: int = g[0]
		var i1: int = g[1]
		var req := minf(jump_speed(path, i0, i1) * 1.12, vmax)
		# hold the speed over the last metres, before that build it up with a
		# realistic acceleration so the driver starts early enough
		var k := i0
		var v := req
		for step in 600:
			var hold := step < 25
			if not hold:
				v = sqrt(maxf(0.0, v * v - 2.0 * ACCEL_PLAN * TrackPath.STEP))
				if v < 15.0:
					break
			f[k] = maxf(f[k], v)
			k = (k - 1 + n) % n
		k = (i0 + 1) % n
		while k != i1:
			f[k] = maxf(f[k], req)
			k = (k + 1) % n
	# loops: enough speed to stay on the road at the top (v_top^2 > g*R)
	for p in path.pieces:
		if p["type"] != "O":
			continue
		var r: float = p["radius"]
		var v_top := sqrt(1.6 * G * r)
		var req := minf(sqrt(v_top * v_top + 4.0 * G * r) * 1.12, vmax)
		var k: int = p["i0"]
		var vv := req
		for step in 600:
			if step >= 20:
				vv = sqrt(maxf(0.0, vv * vv - 2.0 * ACCEL_PLAN * TrackPath.STEP))
				if vv < 15.0:
					break
			f[k] = maxf(f[k], vv)
			k = (k - 1 + n) % n
		for i in range(p["i0"], p["i1"]):
			f[i] = maxf(f[i], v_top)
	for i in n:
		if path.bridge_zone[i] == 1:
			for step in 60:
				var k := (i - step + n) % n
				f[k] = maxf(f[k], 30.0)
	return f


static func _near_loop(path: TrackPath, i: int) -> bool:
	for k in range(-SPAN - 1, SPAN + 2):
		if path.loop_mask[(i + k + path.n) % path.n] == 1:
			return true
	return false


## Minimal take-off speed to clear a gap from sample i0 to landing sample i1.
static func jump_speed(path: TrackPath, i0: int, i1: int) -> float:
	var back := path.center[(i0 - 4 + path.n) % path.n]
	var p0 := path.center[i0]
	var run := Vector2(p0.x - back.x, p0.z - back.z).length()
	var theta := atan2(p0.y - back.y, maxf(run, 0.1))
	var p1 := path.center[i1]
	var dist := Vector2(p1.x - p0.x, p1.z - p0.z).length() + 3.0
	var dh := (p1.y - p0.y) + 0.4
	var denom := 2.0 * cos(theta) * cos(theta) * (dist * tan(theta) - dh)
	if denom <= 0.0:
		return VMAX_SUPER
	return sqrt(G * dist * dist / denom)
