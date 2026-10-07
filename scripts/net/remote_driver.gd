class_name RemoteDriver
extends RefCounted
## Drives the local copy of the online opponent's car. The copy is a full
## PlayerCar (mass, suspension, tyres) that runs on the opponent's pedal and
## steering values between packets; soft spring forces pull it toward the
## received state, extrapolated to the current race time. Far off (or a crane
## teleport): set hard. Its damage comes from the network only.

## Wire range of the steering angle (NetCodec "steer" = angle / this).
const STEER_WIRE_DEG := 45.0
## Extrapolate at most this far past the last packet (s).
const MAX_EXTRAPOLATE := 0.4
## Position error that is corrected by a hard set instead of forces (m).
const SNAP_DIST := 3.0
## Spring / damper toward the target (1/s^2, 1/s): critically damped, w = 4.
const KP := 16.0
const KD := 8.0
## Rotation: angular velocity toward target, error closed at this rate (1/s).
const KR := 6.0
const ANG_BLEND := 10.0

var car: PlayerCar
## Latest state (NetCodec.decode_state) and the position error after the
## last update (debug).
var state := {}
var error := 0.0


func _init(c: PlayerCar) -> void:
	car = c
	car.remote = true


## The local car's state for the wire.
static func capture(c: PlayerCar, race_s: float, race_state: String) -> Dictionary:
	return {
		"t": race_s, "pos": c.global_position, "rot": c.global_basis.get_rotation_quaternion(),
		"vel": c.linear_velocity, "angvel": c.angular_velocity,
		"steer": c.steer_angle / deg_to_rad(STEER_WIRE_DEG),
		"throttle": c.input.get("throttle", 0.0), "brake": c.input.get("brake", 0.0),
		"boosting": c.boosting, "reverse": c.reverse, "held": c.freeze,
		"airborne": c.grounded == 0 and not c.freeze, "state": race_state,
		"boost": c.boost_units, "crack": c.damage.crack, "holes": c.damage.holes,
	}


## Time from state s to race time t that is bridged by extrapolation.
static func lead(s: Dictionary, t: float) -> float:
	return clampf(t - float(s["t"]), 0.0, MAX_EXTRAPOLATE)


## The pose of state s extrapolated to race time t (a parabola in the air).
static func target(s: Dictionary, t: float) -> Transform3D:
	var e := lead(s, t)
	var rot: Quaternion = s["rot"]
	var w: Vector3 = s["angvel"]
	if w.length() > 1e-4:
		rot = Quaternion(w.normalized(), w.length() * e) * rot
	var pos: Vector3 = s["pos"] + s["vel"] * e
	if s.get("airborne", false):
		pos += Vector3.DOWN * 9.81 * 0.5 * e * e
	return Transform3D(Basis(rot.normalized()), pos)


## The velocity of state s extrapolated to race time t.
static func target_velocity(s: Dictionary, t: float) -> Vector3:
	var v: Vector3 = s["vel"]
	if s.get("airborne", false):
		v += Vector3.DOWN * 9.81 * lead(s, t)
	return v


## Called every physics tick before the car's own physics. Returns true when
## the car was set hard (teleport) this tick.
func update(s: Dictionary, race_s: float, dt: float) -> bool:
	if s.is_empty():
		return false
	state = s
	car.input = {
		"steer": clampf(float(s["steer"]) * STEER_WIRE_DEG / car.tuning.max_steer_deg, -1.0, 1.0),
		"throttle": s["throttle"], "brake": s["brake"], "boost": s["boosting"], "direct": true,
	}
	car.boost_units = s["boost"]
	car.damage.crack = s["crack"]
	car.damage.holes = s["holes"]
	if s["held"]:
		return false     # the race places held cars (crane)
	var xf := target(s, race_s)
	var err := xf.origin - car.global_position
	error = err.length()
	if car.freeze or error > SNAP_DIST:
		car.teleport(xf)
		car.linear_velocity = target_velocity(s, race_s)
		car.angular_velocity = s["angvel"]
		return true
	var dv := target_velocity(s, race_s) - car.linear_velocity
	car.apply_central_force(car.mass * (err * KP + dv * KD))
	var dq := xf.basis.get_rotation_quaternion() * car.global_basis.get_rotation_quaternion().inverse()
	if dq.w < 0.0:
		dq = -dq
	var corr := Vector3.ZERO
	if dq.get_angle() > 1e-4:
		corr = dq.get_axis().normalized() * dq.get_angle() * KR
	car.angular_velocity = car.angular_velocity.lerp(s["angvel"] + corr, clampf(dt * ANG_BLEND, 0.0, 1.0))
	return false
