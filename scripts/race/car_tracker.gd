class_name CarTracker
extends RefCounted
## Follows one physically simulated car along the track: position on the
## centre line, continuous progress (for gaps/positions), lap counting with
## piece order, lap times and off-track / upside-down detection.
## Used identically for the player and the opponent.

const OFF_TRACK_TIME := 0.7
const FLIP_TIME := 2.5

var path: TrackPath
var car: PlayerCar
var idx := 0
var s := 0.0
var progress := 0.0
var laps: LapTracker
var lap_start := 0.0
var best_lap := -1.0
var last_lap := -1.0
var off_timer := 0.0
var flip_timer := 0.0
var stuck_timer := 0.0
var hang_timer := 0.0
var left_s := -1.0          # where the car left the road (-1: still on it)
const STUCK_TIME := 2.5
const HANG_TIME := 2.0     # no wheel on the ground and not moving: wedged


func _init(p: TrackPath, c: PlayerCar, start_s: float) -> void:
	path = p
	car = c
	s = p.wrap_s(start_s)
	progress = start_s
	idx = p.index_at_s(start_s)
	laps = LapTracker.new(p.pieces.size(), 0)


func laps_done() -> int:
	return laps.laps_done


func lateral() -> float:
	return path.lateral(car.global_position, idx)


func update_position() -> void:
	var pos := car.global_position
	idx = path.nearest(pos, idx, 40)
	var ns := path.s_of(pos, idx)
	var d := path.delta_s(s, ns)
	if absf(d) < 60.0:
		progress += d
		s = ns


## Returns true when a lap was completed (pieces passed in order).
func update_laps(race_time: float) -> bool:
	var pos := car.global_position
	var near_road := absf(lateral()) < path.half_width[idx] + 1.0 and path.height_above(pos, idx) > -1.0
	if not near_road or not laps.update(path.piece_of[idx]):
		return false
	last_lap = race_time - lap_start
	lap_start = race_time
	if best_lap < 0.0 or last_lap < best_lap:
		best_lap = last_lap
	return true


## Returns true when the car has fallen off (or lies on its roof) long enough
## to call the crane.
func check_off(dt: float) -> bool:
	var pos := car.global_position
	# below the surface along its normal (also correct upside down in loops)
	var below := path.height_above(pos, idx) < -1.2 and path.loop_mask[idx] == 0
	if path.loop_mask[idx] == 1 and absf(lateral()) > path.half_width[idx] + 2.0:
		below = true
	# over the edge in the air: from here on it falls freely
	if below or car.on_ground_plane or car.grounded == 0 and absf(lateral()) > path.half_width[idx] + 1.0:
		if not car.off_road and left_s < 0.0:
			left_s = s
		car.off_road = true
	if car.on_ground_plane or below:
		off_timer += dt
	else:
		off_timer = 0.0
	if car.global_transform.basis.y.y < 0.25 and car.linear_velocity.length() < 4.0:
		flip_timer += dt
	else:
		flip_timer = 0.0
	# landed in a pit and can't get out
	if path.pit_mask.size() == path.n and path.pit_mask[idx] == 1 and absf(car.speed) < 2.0:
		stuck_timer += dt
	else:
		stuck_timer = 0.0
	# wedged somewhere with no wheel on the ground and not moving
	if car.grounded == 0 and car.linear_velocity.length() < 1.0:
		hang_timer += dt
	else:
		hang_timer = 0.0
	if off_timer > OFF_TRACK_TIME or flip_timer > FLIP_TIME or stuck_timer > STUCK_TIME or hang_timer > HANG_TIME:
		off_timer = 0.0
		flip_timer = 0.0
		stuck_timer = 0.0
		hang_timer = 0.0
		return true
	return false


## Where the car came off the road (or is now, if it never left it: on its
## roof, stuck, wedged).
func off_s() -> float:
	return left_s if left_s >= 0.0 else s


## The crane put the car back at rs.
func move_to(rs: float) -> void:
	left_s = -1.0
	progress += path.delta_s(s, rs)
	s = rs
	idx = path.index_at_s(rs)
	off_timer = 0.0
	flip_timer = 0.0
	stuck_timer = 0.0
	hang_timer = 0.0
