class_name CockpitMath
## Pure math for the VR viewpoint.
##
## The view sits in the cockpit and depends only on the car's attitude in
## space, never on the track (loops, flips and roll-overs are all the same):
## let tilt be the angle between the car's roof (up axis) and world up. The
## view is the car's orientation turned back towards level about the
## horizontal tilt axis by (1 - share) * smooth_triangle(tilt):
##   tilt   0 deg (upright)     : view = car
##   tilt  30 deg (e.g. ramp)   : view tilted 15 deg (share 0.5)
##   tilt  90 deg (nose up/side): view tilted 50 deg (lags the car by 40)
##   tilt 180 deg (upside down) : view = car again (upside down with it)
## For pure pitch or pure roll the heading is kept exactly; with both combined
## it shifts slightly (<= 2 deg on all tracks). No state is needed, so the view
## can never get stuck facing backwards. The HMD pose (6DOF) is then applied
## relative to that base pose.


## Half width of the rounded corner of the tilt triangle.
const TILT_CORNER := deg_to_rad(20.0)


## Triangle 0 -> 90 deg (at 90) -> 0 (at 180), odd, with its corners at
## +-90 deg replaced by a parabola that meets the straight parts tangentially
## (C1), so the view's turn rate changes smoothly. Peak 90 - TILT_CORNER / 2.
static func smooth_triangle(angle: float) -> float:
	var a := wrapf(angle, -PI, PI)
	var x := absf(a) - PI * 0.5   # distance from the corner
	var d := absf(x)
	if d < TILT_CORNER:
		d = (x * x / TILT_CORNER + TILT_CORNER) * 0.5
	return signf(a) * (PI * 0.5 - d)


## How far the view lags behind the car for a given tilt (0..PI).
static func tilt_lag(tilt: float, tilt_follow: float) -> float:
	return (1.0 - clampf(tilt_follow, 0.0, 1.0)) * smooth_triangle(tilt)


static func view_basis(car_basis: Basis, tilt_follow: float) -> Basis:
	var b := car_basis.orthonormalized()
	var axis := b.y.cross(Vector3.UP)   # turning about it brings the roof up
	var s := axis.length()
	if s < 1e-6:
		return b    # upright or exactly upside down: lag is zero
	var tilt := atan2(s, b.y.y)
	return Basis(axis / s, tilt_lag(tilt, tilt_follow)) * b


## Eye point = car transform applied to the seat offset, oriented by the base view.
static func base_transform(car_xform: Transform3D, seat_offset: Vector3, tilt_follow: float) -> Transform3D:
	return Transform3D(view_basis(car_xform.basis, tilt_follow), car_xform * seat_offset)


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


## Angle between a basis' up axis and world up (0 upright, PI upside down).
static func tilt_of(b: Basis) -> float:
	var u := b.orthonormalized().y
	return atan2(u.cross(Vector3.UP).length(), u.y)


static func pitch_of(b: Basis) -> float:
	return asin(clampf((-b.z).y, -1.0, 1.0))


static func roll_of(b: Basis) -> float:
	return asin(clampf(b.x.y, -1.0, 1.0))


static func yaw_of(b: Basis) -> float:
	var f := -b.z
	return atan2(-f.x, -f.z)
