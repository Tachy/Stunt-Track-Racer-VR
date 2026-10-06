class_name CockpitMath
## Pure math for the VR viewpoint.
##
## The base view follows the car's heading (yaw) completely. Pitch and roll
## are followed only by a share (tilt_follow, 0.5 by default), with a folding
## rule so loops and roll-overs never make the view jump:
##   |angle| <= 90 deg : view = share * angle
##   |angle| >  90 deg : view = share * (180 - |angle|)  (back to level when upside down)
## With share 0.5 the view stays within +-45 deg of straight ahead in pitch and
## roll. The HMD pose (6DOF) is then applied relative to that base pose.


static func _wrap(a: float) -> float:
	return wrapf(a, -PI, PI)


## Car orientation as (pitch, yaw, roll) in YXZ order. Of the two equivalent
## decompositions the one whose yaw is closest to prev_yaw is chosen, so the
## heading stays continuous when the nose passes vertical (loops).
static func car_euler(car_basis: Basis, prev_yaw: float) -> Vector3:
	var e := car_basis.orthonormalized().get_euler(EULER_ORDER_YXZ)
	var alt := Vector3(_wrap(PI - e.x), _wrap(e.y + PI), _wrap(e.z + PI))
	if absf(angle_difference(prev_yaw, alt.y)) < absf(angle_difference(prev_yaw, e.y)):
		return alt
	return e


## The folding rule for one angle.
static func fold(angle: float, share: float) -> float:
	var a := _wrap(angle)
	if absf(a) <= PI * 0.5:
		return a * share
	return signf(a) * (PI - absf(a)) * share


static func view_basis(car_basis: Basis, tilt_follow: float, prev_yaw := 0.0) -> Basis:
	var e := car_euler(car_basis, prev_yaw)
	var share := clampf(tilt_follow, 0.0, 1.0)
	return Basis.from_euler(Vector3(fold(e.x, share), e.y, fold(e.z, share)), EULER_ORDER_YXZ)


## Car orientation inside a loop, relative to the loop's entry heading, as
## (pitch, yaw, roll) with R = Rx(pitch) * Ry(yaw) * Rz(roll). Pitch runs
## through the full circle; yaw and roll stay small (sideways shift and twist
## of the loop), so unlike car_euler there is no gimbal lock at vertical.
static func loop_euler(car_basis: Basis, entry_yaw: float) -> Vector3:
	var local := Basis(Vector3.UP, -entry_yaw) * car_basis.orthonormalized()
	return local.get_euler(EULER_ORDER_XYZ)


## View inside a loop: the view stays with the cockpit and only pitches
## relative to the car, never rolls. The offset from the driving direction
## is a triangle over the loop angle (share 0.5):
##   nose 0 -> 90 deg up    : offset 0 -> -45 (view below the nose)
##   90 -> 180 (upside down): offset -45 -> 0 (view along the driving direction)
##   180 -> 270 (nose down) : offset 0 -> +45 (view above the nose)
##   270 -> 360 (exit)      : offset +45 -> 0
## At entry and exit this equals view_basis (no jump).
static func loop_view_basis(car_basis: Basis, tilt_follow: float, entry_yaw: float) -> Basis:
	var e := loop_euler(car_basis, entry_yaw)
	var share := clampf(tilt_follow, 0.0, 1.0)
	var offset := -(1.0 - share) * fold(e.x, 1.0)
	# pitch about the car's own cross axis (it is turned by the loop's sideways shift)
	return Basis(Vector3.UP, entry_yaw) * Basis(Vector3.RIGHT, e.x) * Basis(Vector3.UP, e.y) 		* Basis(Vector3.RIGHT, offset) * Basis(Vector3.BACK, fold(e.z, share))


## Heading inside a loop, used as prev_yaw for the next frame.
static func loop_view_yaw(car_basis: Basis, entry_yaw: float) -> float:
	return entry_yaw + loop_euler(car_basis, entry_yaw).y


## Heading used as prev_yaw for the next frame.
static func view_yaw(car_basis: Basis, prev_yaw := 0.0) -> float:
	return car_euler(car_basis, prev_yaw).y


## Kept for callers/tests: base view basis (same as view_basis).
static func base_basis(car_basis: Basis, tilt_follow: float, prev_yaw := 0.0) -> Basis:
	return view_basis(car_basis, tilt_follow, prev_yaw)


## Yaw-only basis for a vehicle basis (Godot: -Z is forward).
static func level_yaw(car_basis: Basis, prev_yaw := 0.0) -> float:
	return view_yaw(car_basis, prev_yaw)


## Eye point = car transform applied to the seat offset, oriented by the base view.
static func base_transform(car_xform: Transform3D, seat_offset: Vector3, tilt_follow: float, prev_yaw := 0.0) -> Transform3D:
	return Transform3D(view_basis(car_xform.basis, tilt_follow, prev_yaw), car_xform * seat_offset)


## Recenter offset from the HMD pose relative to the XR origin. Only yaw and
## position are taken so the horizon never tilts after recentering.
static func recenter_offset(head_local: Transform3D) -> Transform3D:
	var f := -head_local.basis.z
	var yaw := atan2(-f.x, -f.z) if Vector2(f.x, f.z).length() > 1e-4 else 0.0
	return Transform3D(Basis(Vector3.UP, yaw), head_local.origin)


## Transform to assign to XROrigin3D so the head sits at the base pose when the
## HMD is at the recenter pose.
static func origin_transform(base: Transform3D, recenter: Transform3D) -> Transform3D:
	return base * recenter.affine_inverse()


static func pitch_of(b: Basis) -> float:
	return asin(clampf((-b.z).y, -1.0, 1.0))


static func roll_of(b: Basis) -> float:
	return asin(clampf(b.x.y, -1.0, 1.0))
