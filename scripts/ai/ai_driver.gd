class_name AiDriver
extends RefCounted
## Computer driver for a physically simulated car. It produces exactly the
## same controls as the player's wheel and pedals (steer, throttle, brake,
## boost, 1:1 direct steering) - the car physics are identical.
##
## Steering: pure pursuit on the centre line plus a lateral lane offset.
## Speed: per-sample target speed (AiProfile) scaled by skill, never below
## the jump floors. Personality flags from the original game:
## push (rubs against you), obstruct (blocks you), edge (drives near the edge).

const WHEELBASE := 2.9
## Lateral centre distance of two cars side by side (car width ~2.4 m).
const SIDE_GAP := 3.0       # car width 2.64 m + margin
const MAX_LAT := 3.4

var car: PlayerCar
var tracker: CarTracker
var path: TrackPath
var profile: PackedFloat32Array
var floors: PackedFloat32Array
var skill := 0.9
var flags: Array = []
var finished := false
var race_time := 0.0          # set by the race; no pushing right after the start

var lat := 0.0
var lat_target := 0.0

const LANE_GAIN := 0.018      # rad per metre off the lane
const LANE_DAMP := 0.035      # rad per (m/s) of sideways drift
const COMMIT_AHEAD := 70      # samples: before loops/jumps keep to the centre
const COMMIT_SIDE_LAT := 2.0  # m: side by side in a loop/jump, each on its half
const LOOP_LOOK := 5.0        # m: pure pursuit look-ahead inside a loop


func _init(t: CarTracker, prof: PackedFloat32Array, flo: PackedFloat32Array, driver_skill: float, driver_flags: Array) -> void:
	tracker = t
	car = t.car
	path = t.path
	profile = prof
	floors = flo
	skill = driver_skill
	flags = driver_flags
	lat = t.lateral()
	lat_target = lat


## other: tracker of the rival car (or null).
func compute(dt: float, other: CarTracker) -> Dictionary:
	var v := car.speed
	var s := tracker.s
	var look_i := path.index_at_s(s + maxf(v, 0.0) * 0.35)
	var target := profile[look_i] * skill

	var gap := 0.0
	var other_lat := 0.0
	if other:
		gap = tracker.progress - other.progress
		other_lat = other.lateral()
		if gap > 150.0:
			target *= 0.93            # mild rubber band, as in the original
		elif gap < -150.0:
			target *= 1.03
		# don't plough into a car right in front
		if gap < 0.0 and gap > -9.0 and absf(lat - other_lat) < SIDE_GAP:
			var cap := other.car.speed + (2.0 if "push" in flags else -1.0)
			target = minf(target, maxf(cap, 5.0))
	if finished:
		target *= 0.7
	target = maxf(target, floors[look_i])

	_choose_lane(gap, other_lat, other != null)
	if _committed(look_i):
		# loops/jumps: straight down the middle - unless the rival is close,
		# then each car keeps to its own half (no lane changes, no contact)
		lat_target = 0.0
		if other and absf(gap) < 20.0:
			var side := signf(lat - other_lat)
			if side == 0.0:
				side = 1.0 if gap >= 0.0 else -1.0
			lat_target = side * COMMIT_SIDE_LAT
	lat = move_toward(lat, lat_target, (2.2 if absf(gap) > 6.0 or other == null else 1.0) * dt)

	# pure pursuit steering towards a point ahead on the chosen lane
	var look := 10.0 + 0.3 * maxf(v, 0.0)
	if path.loop_mask[tracker.idx] == 1:
		look = LOOP_LOOK   # 20 m would be a quarter of the loop: target above/behind the car
	var ts := s + look
	var tp := path.center_at_s(ts) + path.right_flat[path.index_at_s(ts)] * lat
	var local := car.global_transform.affine_inverse() * tp
	var alpha := atan2(local.x, -local.z)
	var wheel_angle := atan(2.0 * WHEELBASE * sin(alpha) / look)
	# pure pursuit cuts corners: pull back towards the chosen lane, and damp
	# the drift across the road
	var lat_now := tracker.lateral()
	# sideways drift from the velocity (not from differencing lateral(), which
	# jumps whenever the nearest sample changes, e.g. in the shifted loops),
	# minus the sideways run of the path itself
	var rf := path.right_flat[tracker.idx]
	var pf := path.forward[tracker.idx]
	var vel := car.linear_velocity
	var lat_rate := vel.dot(rf) - vel.dot(pf) * pf.dot(rf)
	wheel_angle += LANE_GAIN * (lat - lat_now) - LANE_DAMP * lat_rate
	var steer := clampf(wheel_angle / deg_to_rad(car.tuning.max_steer_deg), -1.0, 1.0)

	var err := target - v
	var throttle := clampf(0.4 + err * 0.3, 0.0, 1.0) if err > -0.5 else 0.0
	var brk := clampf((-err - 1.0) * 0.25, 0.0, 1.0)
	return {"steer": steer, "throttle": throttle, "brake": brk,
		"boost": err > 5.0 and car.boost_units > 0, "direct": true}


func _choose_lane(gap: float, other_lat: float, has_other: bool) -> void:
	lat_target = -3.0 if "edge" in flags else 0.0
	if not has_other:
		return
	var side := signf(lat - other_lat)
	if side == 0.0:
		side = 1.0
	if gap < 0.0 and gap > -25.0 and "push" in flags and race_time > 8.0:
		lat_target = other_lat + side * SIDE_GAP           # come alongside, up to contact
	elif gap > 6.0 and gap < 30.0 and "obstruct" in flags:
		lat_target = other_lat                            # block the car behind
	elif gap < 0.0 and gap > -14.0 and absf(lat - other_lat) < SIDE_GAP:
		lat_target = other_lat - 3.4 if other_lat > 0.0 else other_lat + 3.4  # overtake
	if absf(gap) < 6.0 and side * (lat_target - other_lat) < SIDE_GAP:
		lat_target = other_lat + side * SIDE_GAP          # alongside: keep room
	var max_lat := minf(MAX_LAT, path.half_width[tracker.idx] - 1.5)
	lat_target = clampf(lat_target, -max_lat, max_lat)


## True when a loop or a jump lies just ahead: no lane changes there.
func _committed(i: int) -> bool:
	for k in range(0, COMMIT_AHEAD, 5):
		var j := (i + k) % path.n
		if path.loop_mask[j] == 1 or floors[j] > 0.0 and path.road[j] == 0:
			return true
	for g in path.gaps():
		var d := (int(g[0]) - i + path.n) % path.n
		if d < COMMIT_AHEAD:
			return true
	return false
