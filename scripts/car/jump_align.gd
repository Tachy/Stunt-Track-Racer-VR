class_name JumpAlign
extends RefCounted
## Jump assist (a button of its own, keyboard E): in the last ZONE metres
## before a take-off, held down, it takes over the steering - first the
## front wheels point the way the road goes (the car turns onto it), then,
## within ALIGNED_DEG, the wheel is held straight as long as it is pressed.
## Only the steering angle: the tyres do the rest (standing very much at an
## angle, the car may break away). No autoloads (tested headless).

const ZONE := 50.0
const ALIGNED_DEG := 1.0

## "": not acting, "align": turning onto the road, "straight": held straight.
var mode := ""
var _takeoffs := PackedFloat64Array()
var _length := 0.0


func _init(path: TrackPath) -> void:
	_length = path.total_length
	for j in path.crane_jumps():
		_takeoffs.append(path.s_arr[int(j[0])])


## Whether s is in the last ZONE metres before a take-off.
func in_zone(s: float) -> bool:
	for t in _takeoffs:
		var ahead := fposmod(t - s, _length)
		if ahead > 0.0 and ahead <= ZONE:
			return true
	return false


## Signed angle (rad) from the car's heading to the road's, seen from above
## (positive: the road goes off to the left).
static func heading_error(car_fwd: Vector3, road_fwd: Vector3) -> float:
	var a := Vector2(car_fwd.x, car_fwd.z)
	var b := Vector2(road_fwd.x, road_fwd.z)
	if a.length_squared() < 1e-8 or b.length_squared() < 1e-8:
		return 0.0
	return -a.angle_to(b)     # (Vector2 angles turn the other way round than the plan seen from above)


## The drive input with the assist applied: held in the zone, its steering
## replaced (as direct steering: the road-wheel angle itself). max_steer:
## the car's full lock (rad).
func apply(drive: Dictionary, held: bool, s: float, car_fwd: Vector3, road_fwd: Vector3, max_steer: float) -> Dictionary:
	if not held or not in_zone(s):
		mode = ""
		return drive
	var out := drive.duplicate()
	out["direct"] = true
	var err := heading_error(car_fwd, road_fwd)
	if mode != "straight" and absf(err) < deg_to_rad(ALIGNED_DEG):
		mode = "straight"
	if mode == "straight":
		out["steer"] = 0.0
		return out
	mode = "align"
	# the front wheels the way the road goes (positive steer: to the right)
	out["steer"] = clampf(-err / max_steer, -1.0, 1.0)
	return out
