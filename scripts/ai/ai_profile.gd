class_name AiProfile
## Target speed per track sample for the path-following opponent
## (the original used a hand-made speed table per piece; we derive it from
## the geometry: curve radius, crests, braking distances and jump speeds).

const VMAX := 62.0
const VMAX_SUPER := 70.0
const LAT_ACCEL := 10.0
## deg/s of road twist the driver accepts (banking in/out of curves)
const MAX_ROLL_RATE := 30.0
const BRAKE := 9.0
const G := 9.81
const SPAN := 6
## Acceleration assumed when planning the run-up to a jump (m/s^2).
const ACCEL_PLAN := 3.0
## Loop entry speed cap relative to loop_speed().
const LOOP_CAP := 1.04


static func compute(path: TrackPath, super_league := false) -> PackedFloat32Array:
	var n := path.n
	var vmax := VMAX_SUPER if super_league else VMAX
	var v := PackedFloat32Array()
	v.resize(n)
	for i in n:
		if _near_loop(path, i):
			# floors() give the minimum; cap just above it: faster only
			# crushes the suspension into the bump stop (> 8 g) and the
			# chassis scrapes through the loop
			v[i] = minf(vmax, loop_speed(_loop_radius(path, i)) * LOOP_CAP)
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

	# jumps: not faster than they still land safe at the take-off (more
	# speed below an uphill run-up, what the climb eats)
	for g in jumps(path):
		var i0: int = g[0]
		var top := plan_jump(path, i0, g[1], vmax).y
		for step in 25:
			var k := (i0 - step + n) % n
			var climb := path.center[i0].y - path.center[k].y
			v[k] = minf(v[k], sqrt(maxf(top * top + 2.0 * G * climb, 1.0)))

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
	var js := jumps(path)
	var air := PackedByteArray()
	air.resize(n)
	for g in js:
		var k: int = (int(g[0]) + 1) % n
		while k != int(g[1]):
			air[k] = 1
			k = (k + 1) % n
	for g in js:
		var i0: int = g[0]
		var i1: int = g[1]
		var req := plan_jump(path, i0, i1, vmax).x
		# hold the speed over the last metres, before that build it up with a
		# realistic acceleration so the driver starts early enough; a run-up
		# uphill needs that much more speed below (what the climb eats - the
		# engine hardly gains anything on a ramp)
		var k := i0
		var v := req
		for step in 600:
			if step > 0:
				var up := path.center[(k + 1) % n].y - path.center[k].y
				var gain := 2.0 * ACCEL_PLAN * TrackPath.STEP if step >= 25 and up < 0.1 * TrackPath.STEP else 0.0
				v = sqrt(maxf(0.0, v * v + 2.0 * G * up - gain))
				if step >= 25 and v < 15.0 or air[k] == 1:
					break
			f[k] = maxf(f[k], minf(v, vmax))
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
		var req := minf(loop_speed(r), vmax)
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


## Entry speed for a loop of radius r: enough to keep pressing on the road
## at the top (v_top^2 = 1.6 g r), plus 12 % margin.
static func loop_speed(r: float) -> float:
	return sqrt(5.6 * G * r) * 1.12


static func _loop_radius(path: TrackPath, i: int) -> float:
	for k in range(-SPAN - 1, SPAN + 2):
		var p: Dictionary = path.pieces[path.piece_of[(i + k + path.n) % path.n]]
		if p["type"] == "O":
			return float(p["radius"])
	return TrackPath.LOOP_RADIUS


static func _near_loop(path: TrackPath, i: int) -> bool:
	for k in range(-SPAN - 1, SPAN + 2):
		if path.loop_mask[(i + k + path.n) % path.n] == 1:
			return true
	return false


## Every take-off the driver plans for, [take-off, landing] sample pairs:
## the gaps, pits and ski jumps and the black walls down (one per take-off,
## its farthest landing; none inside another one's flight, e.g. off a tower
## that is flown over).
static func jumps(path: TrackPath) -> Array:
	var land := {}
	var walls := []
	for w in path.wall_jumps():
		if path.center[(int(w[0]) + 1) % path.n].y < path.center[w[0]].y:
			walls.append(w)    # (a wall up on its own is no take-off)
	for g in path.gaps() + walls:
		var i0: int = g[0]
		var i1: int = g[1]
		if not land.has(i0) or path._fwd_dist(i0, i1) > path._fwd_dist(i0, land[i0]):
			land[i0] = i1
	var out := []
	for i0 in land:
		var inside := false
		for j0 in land:
			if j0 != i0 and path._fwd_dist(j0, i0) > 0 and path._fwd_dist(j0, i0) < path._fwd_dist(j0, land[j0]):
				inside = true
		if not inside:
			out.append([i0, land[i0]])
	return out


## Touchdown at most this fast into the road (damage from 9.5 m/s, but
## mild: 12 m/s cost 6 %; what wrecks is coming down short).
const LAND_SAFE := 12.0
## Metres beyond the landing sample the car must come down (its length).
const LAND_MARGIN := 3
## A wall's or hole's far edge this little above the flight is rolled over.
const EDGE_TOL := 0.5
const JUMP_V_MIN := 8.0
## The driver hits its speed only so well: a take-off speed counts as safe
## when everything from -6 % to +6 % around it lands safe.
const JUMP_TOLERANCE := 0.06


## Take-off speed for the jump from sample i0 that lands safely beyond
## landing sample i1: the classic estimate (clear the gap plus 12 %) when
## that lands safe, else the slowest safe speed from ballistic flights
## against the road ahead, else the softest landing. Returns (that speed,
## the fastest one up to which it still lands safe - too fast can overshoot
## the landing too).
static func plan_jump(path: TrackPath, i0: int, i1: int, vmax: float) -> Vector2:
	var classic := minf(jump_speed(path, i0, i1) * 1.12, vmax)
	if _safe(path, i0, i1, classic, vmax):
		return Vector2(classic, _top(path, i0, i1, classic, vmax))
	var v := JUMP_V_MIN
	while v <= vmax:
		if _safe(path, i0, i1, v, vmax):
			return Vector2(v, _top(path, i0, i1, v, vmax))
		v += 0.5
	# none: the softest landing (the worst within +-2 %)
	var best := vmax
	var soft := INF
	v = vmax
	while v >= JUMP_V_MIN:
		var hit := maxf(touchdown_speed(path, i0, i1, v), maxf(touchdown_speed(path, i0, i1, v * 0.98), touchdown_speed(path, i0, i1, v * 1.02)))
		if hit < soft:
			soft = hit
			best = v
		v -= 0.25
	return Vector2(best, best * 1.02)


## Fastest take-off speed from v on up to which every speed lands safe.
static func _top(path: TrackPath, i0: int, i1: int, v: float, vmax: float) -> float:
	var top := v * (1.0 + JUMP_TOLERANCE)
	while top + 0.5 <= vmax and touchdown_speed(path, i0, i1, top + 0.5) <= LAND_SAFE:
		top += 0.5
	return top


## Whether all take-off speeds within the tolerance around v land safe.
static func _safe(path: TrackPath, i0: int, i1: int, v: float, vmax: float) -> bool:
	if v * (1.0 + JUMP_TOLERANCE) > vmax + 0.5:
		return false
	for k in 5:
		var vk := v * (1.0 - JUMP_TOLERANCE + JUMP_TOLERANCE * 0.5 * k)
		if touchdown_speed(path, i0, i1, vk) > LAND_SAFE:
			return false
	return true


## Speed (m/s) into the road at the touchdown when taking off at sample i0
## with speed v along the road; INF when the car comes down before landing
## sample i1 (short, onto a tower), against a wall or a hole's far edge,
## or beyond the next wall or hole (flown over the next jump too).
static func touchdown_speed(path: TrackPath, i0: int, i1: int, v: float) -> float:
	var n := path.n
	var back := path.center[(i0 - 4 + n) % n]
	var p0 := path.center[i0]
	var theta := atan2(p0.y - back.y, maxf(Vector2(p0.x - back.x, p0.z - back.z).length(), 0.1))
	var vx := v * cos(theta)
	var vy := v * sin(theta)
	var reach := path._fwd_dist(i0, i1)
	var x := 0.0
	var k := i0
	var beyond := false     # a wall or a hole after the landing passed
	for step in 800:
		var k2 := (k + 1) % n
		var a := path.center[k]
		var b := path.center[k2]
		x += Vector2(b.x - a.x, b.z - a.z).length()
		var over_hole := path.road[k] == 0
		var face := path.step[k] == 1 or path.wall_steep(k)
		var past := path._fwd_dist(i0, k2) >= reach + LAND_MARGIN
		if past and path._fwd_dist(i0, k) > reach and (over_hole or face):
			beyond = true
		k = k2
		if path.road[k2] == 0:
			continue      # over a hole (whoever falls in hits its far edge)
		var t := x / vx
		var y := p0.y + vy * t - 0.5 * G * t * t
		if y <= b.y:
			var edge := over_hole or face
			if beyond or path.ground_floor[k2] == 1 or (edge and y < b.y - EDGE_TOL) 					or not (past or edge and path._fwd_dist(i0, k2) >= reach):
				return INF
			var c := path.center[(k2 + 1) % n]
			var tan := Vector2(Vector2(c.x - b.x, c.z - b.z).length(), c.y - b.y).normalized()
			var nrm := Vector2(-tan.y, tan.x)
			return maxf(0.0, -(vx * nrm.x + (vy - G * t) * nrm.y))
	return INF


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
