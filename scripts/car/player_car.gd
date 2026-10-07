class_name PlayerCar
extends RigidBody3D
## Player car: RigidBody3D with raycast spring suspension on 4 wheels,
## simple slip-based tyre forces, rear-wheel drive, brakes, boost and damage.
## Car forward is -Z.

signal landed(strength: float)
signal impacted(strength: float)

const WHEELS := CarModel.WHEEL_POS
const WHEEL_R := CarModel.WHEEL_R
const MASK_ENV := TrackNode.LAYER_ROAD | TrackNode.LAYER_WALL | TrackNode.LAYER_GROUND
const LANDING_COOLDOWN := 0.25
## Bottom of the tyre hitboxes above the wheel centre (m).
const WHEEL_BOX_LIFT := 0.15
## Traction control/ABS: share of the friction circle kept for the side
## force (1 = all of it; slightly less keeps some braking while sliding).
const TC_LATERAL_RESERVE := 0.9
const MAX_SANE_SPEED := 120.0   # m/s
const MAX_SPIN := 12.0          # rad/s

static var debug := OS.get_cmdline_user_args().has("--debug")

## Debug output only for the car with verbose = true (the player's).
var verbose := false
var tuning: CarTuning
var damage: DamageModel
var input := {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "boost": false}
var controls_enabled := true
var boost_units := 0
var boosting := false
var reverse := false
var steer_angle := 0.0
var speed := 0.0
var grounded := 0
var on_ground_plane := false
var airtime := 0.0
## Fell off the road: no flight alignment, the car tumbles as it comes.
var off_road := false
var _wheel_boxes: Array[CollisionShape3D] = []
var engine_load := 0.0

var wheel_comp := PackedFloat32Array([0, 0, 0, 0])
var wheel_contact := [false, false, false, false]
## Wheel rotation angle (rad) and angular velocity (rad/s) per wheel.
## On the ground the wheel rolls without slip on its real radius
## (omega = v / r); in the air it keeps spinning, slowed by bearing friction,
## the driven rear wheels spun up by the engine.
var wheel_spin := PackedFloat32Array([0, 0, 0, 0])
var wheel_omega := PackedFloat32Array([0, 0, 0, 0])
## Distance rolled by the left front wheel (debug check: equals distance driven).
var rolled_distance := 0.0

var _boost_timer := 0.0
var _prev_vel := Vector3.ZERO
var _expected_dv := Vector3.ZERO
var _landing_cd := PackedFloat32Array([0, 0, 0, 0])
var _skip_impact := 2
var _impact_suppress := 0.0
var touchdown_normal := Vector3.UP


func setup(t: CarTuning, holes: int) -> void:
	tuning = t
	mass = t.mass
	damage = DamageModel.new(holes)
	damage.hole_threshold = t.hole_threshold
	collision_layer = TrackNode.LAYER_CAR
	collision_mask = MASK_ENV | TrackNode.LAYER_CAR
	continuous_cd = true
	can_sleep = false
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.3, -0.28)   # ~0.5 m above the road: low buggy
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.5
	var pm := PhysicsMaterial.new()
	pm.friction = 0.5
	pm.bounce = 0.05
	physics_material_override = pm

	var chassis := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 0.5, 4.5)
	chassis.shape = box
	chassis.position = Vector3(0, 0.05, -0.2)
	add_child(chassis)
	var cage := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(1.0, 0.75, 1.3)
	cage.shape = cbox
	cage.position = Vector3(0, 0.85, 0.9)
	add_child(cage)
	var eng := CollisionShape3D.new()
	var ebox := BoxShape3D.new()
	ebox.size = Vector3(0.6, 0.4, 1.2)
	eng.shape = ebox
	eng.position = Vector3(0, 0.4, -0.95)
	add_child(eng)
	# wheels: upper part of each tyre (from WHEEL_BOX_LIFT above the wheel
	# centre to its top), so cars and walls hit the tyres. The boxes move with
	# the suspension (_place_wheel_box), so they stay r + lift above the road
	# under their wheel; the road itself is touched only by the rays.
	for w in 4:
		var r: float = WHEEL_R[w]
		var wheel := CollisionShape3D.new()
		var wbox := BoxShape3D.new()
		wbox.size = Vector3(CarModel.WHEEL_W[w], r - WHEEL_BOX_LIFT, r * 1.8)
		wheel.shape = wbox
		add_child(wheel)
		_wheel_boxes.append(wheel)
		_place_wheel_box(w, t.suspension_rest - (CarModel.RIDE_HEIGHT - r))


## Wheel hitbox w for the wheel centre (rest - comp) below its mount. Only
## moved when the wheel travelled > 2 cm (a moved shape rebuilds the body).
func _place_wheel_box(w: int, comp: float) -> void:
	var r: float = WHEEL_R[w]
	var p: Vector3 = WHEELS[w]
	var y := -(tuning.suspension_rest - comp) + (r + WHEEL_BOX_LIFT) * 0.5
	var box: CollisionShape3D = _wheel_boxes[w]
	if absf(box.position.y - y) > 0.02 or box.position.x != p.x:
		box.position = Vector3(p.x, y, p.z)


func teleport(xform: Transform3D) -> void:
	global_transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_vel = Vector3.ZERO
	_expected_dv = Vector3.ZERO
	_skip_impact = 3
	off_road = false
	for w in 4:
		wheel_comp[w] = 0.0
		wheel_contact[w] = false
	reset_physics_interpolation()


func hold(on: bool) -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = on
	_skip_impact = 3
	if not on:
		# dropped from rest: a held (kinematic) car that was moved picks up
		# the implied velocity of the move, which must not carry over
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO


func is_wrecked() -> bool:
	return damage.is_wrecked


func _physics_process(dt: float) -> void:
	if freeze:
		_prev_vel = Vector3.ZERO
		return
	var st := global_transform
	var b := st.basis
	var up := b.y.normalized()
	var fwd := -b.z.normalized()
	var com := st * center_of_mass
	# guard against solver blow-ups (deep penetration into near-vertical faces)
	if linear_velocity.length() > MAX_SANE_SPEED:
		linear_velocity = linear_velocity.limit_length(MAX_SANE_SPEED * 0.5)
	if angular_velocity.length() > MAX_SPIN:
		angular_velocity = angular_velocity.limit_length(MAX_SPIN)
	speed = linear_velocity.dot(fwd)

	_check_impact()

	var ctl := input if controls_enabled and not damage.is_wrecked else {"steer": 0.0, "throttle": 0.0, "brake": 0.4, "boost": false}
	var throttle: float = ctl["throttle"]
	var brk: float = ctl["brake"]

	# steering, less lock at speed
	if ctl.get("direct", false):
		# steering wheel: 1:1 linear, wheel end stop = road-wheel end stop
		steer_angle = float(ctl["steer"]) * deg_to_rad(tuning.max_steer_deg)
	else:
		# keyboard / autopilot: smoothed, less lock at speed
		var lock := deg_to_rad(lerpf(tuning.max_steer_deg, tuning.high_speed_steer_deg,
				clampf(absf(speed) / tuning.steer_falloff_speed, 0.0, 1.0)))
		steer_angle = move_toward(steer_angle, float(ctl["steer"]) * lock, deg_to_rad(240.0) * dt)

	# reverse gear: brake while (almost) stopped
	if brk > 0.2 and throttle < 0.1 and speed < 0.8:
		reverse = true
	elif throttle > 0.1 or speed > 2.0:
		reverse = false

	# boost
	boosting = false
	if ctl["boost"] and boost_units > 0 and grounded >= 2 and throttle > 0.1 and not reverse:
		boosting = true
		_boost_timer += dt
		if _boost_timer >= tuning.boost_unit_time:
			_boost_timer -= tuning.boost_unit_time
			boost_units -= 1

	var drive := 0.0
	if reverse:
		drive = -tuning.reverse_force * brk * maxf(0.0, 1.0 - pow(maxf(-speed, 0.0) / tuning.reverse_top_speed, 2.0))
		brk = 0.0
	else:
		var vtop := tuning.boost_top_speed if boosting else tuning.top_speed
		var factor := tuning.boost_factor if boosting else 1.0
		var ratio := clampf(maxf(speed, 0.0) / vtop, 0.0, 1.0)
		drive = tuning.engine_force * factor * throttle * (1.0 - ratio * ratio)
	engine_load = throttle

	var space := get_world_3d().direct_space_state
	var total := Vector3.ZERO
	var max_load := tuning.mass * 9.81 * 1.6
	var new_grounded := 0
	on_ground_plane = false
	var rear_contacts := 0
	var hits := []
	for w in 4:
		var mount: Vector3 = st * WHEELS[w]
		var ray_len: float = tuning.suspension_rest + float(WHEEL_R[w])
		var q := PhysicsRayQueryParameters3D.create(mount, mount - up * ray_len, MASK_ENV, [get_rid()])
		var hit := space.intersect_ray(q)
		hits.append(hit)
		if not hit.is_empty() and w >= 2:
			rear_contacts += 1

	for w in 4:
		_landing_cd[w] = maxf(0.0, _landing_cd[w] - dt)
		var hit: Dictionary = hits[w]
		var mount: Vector3 = st * WHEELS[w]
		var ray_len: float = tuning.suspension_rest + float(WHEEL_R[w])
		if hit.is_empty():
			wheel_comp[w] = 0.0
			wheel_contact[w] = false
			_place_wheel_box(w, 0.0)
			var om := wheel_omega[w] * maxf(0.0, 1.0 - 0.4 * dt)
			if w >= 2:
				om += (throttle * tuning.engine_force * 0.0004 - brk * 60.0 * signf(om)) * dt
			wheel_omega[w] = om
			wheel_spin[w] += om * dt
			continue
		new_grounded += 1
		var collider = hit["collider"]
		if collider is CollisionObject3D and (collider as CollisionObject3D).collision_layer == TrackNode.LAYER_GROUND:
			on_ground_plane = true
		var p: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		var comp := ray_len - mount.distance_to(p)
		var pv := linear_velocity + angular_velocity.cross(p - com)
		var approach := -pv.dot(normal)
		var comp_vel := approach if not wheel_contact[w] else (comp - wheel_comp[w]) / dt
		if not wheel_contact[w] and approach > 2.5 and _landing_cd[w] <= 0.0 and grounded > 0:
			_landing_cd[w] = LANDING_COOLDOWN
			landed.emit(approach * 0.5)
		if grounded == 0 and new_grounded == 1:
			touchdown_normal = normal
		wheel_comp[w] = comp
		wheel_contact[w] = true
		_place_wheel_box(w, comp)

		var damp := tuning.damping if comp_vel > 0.0 else tuning.damping_rebound
		var fs := tuning.spring * comp + damp * comp_vel
		var stop_start := tuning.suspension_rest * 0.85
		if comp > stop_start:
			fs += tuning.bump_stop * (comp - stop_start) * (1.0 if comp_vel > 0.0 else tuning.bump_stop_return)
		fs = maxf(fs, 0.0)
		var f_susp := up * fs

		# tyre forces in the contact plane
		var wheel_fwd := fwd
		if w < 2:
			wheel_fwd = fwd.rotated(up, -steer_angle)
		var wf := (wheel_fwd - normal * wheel_fwd.dot(normal)).normalized()
		var wr := wf.cross(normal).normalized()
		var v_long := pv.dot(wf)
		var v_lat := pv.dot(wr)
		var load := minf(fs, max_load)
		# side force from the slip angle (not the sideways speed), so the
		# tyre does not get stiffer the faster the car goes
		var c_alpha := tuning.cornering_stiffness_front if w < 2 else tuning.cornering_stiffness_rear
		var f_lat := -atan2(v_lat, maxf(absf(v_long), tuning.slip_min_speed)) * c_alpha
		var limit := tuning.grip * load
		var f_long := -v_long * 25.0
		if w >= 2 and rear_contacts > 0:
			f_long += drive / rear_contacts
		if brk > 0.0:
			f_long -= clampf(v_long * 2.0, -1.0, 1.0) * tuning.brake_force * brk * 0.25
		if tuning.traction_control and limit > 0.0:
			var lat_share := minf(absf(f_lat) / limit, 1.0)
			var avail := limit * sqrt(1.0 - TC_LATERAL_RESERVE * lat_share * lat_share)
			f_long = clampf(f_long, -avail, avail)
		var f := Vector2(f_long, f_lat)
		if f.length() > limit:
			f = f * (limit / f.length())
		var f_tyre := wf * f.x + wr * f.y
		var force := f_susp + f_tyre
		apply_force(force, p - global_position)
		total += force
		wheel_omega[w] = v_long / float(WHEEL_R[w])
		wheel_spin[w] += wheel_omega[w] * dt
		if w == 0:
			rolled_distance += absf(wheel_omega[w]) * float(WHEEL_R[w]) * dt

	# anti-roll bars
	for axle in [[0, 1], [2, 3]]:
		var l: int = axle[0]
		var r: int = axle[1]
		if wheel_contact[l] and wheel_contact[r]:
			var diff := (wheel_comp[l] - wheel_comp[r]) * tuning.anti_roll
			apply_force(up * diff, st * WHEELS[l] - global_position)
			apply_force(-up * diff, st * WHEELS[r] - global_position)

	if grounded == 0 and new_grounded > 0 and airtime > 0.2:
		_touchdown()
	grounded = new_grounded
	if grounded == 0:
		airtime += dt
		if not off_road:
			_align_to_flight(b, dt)
	else:
		airtime = 0.0

	var drag_f := -linear_velocity * linear_velocity.length() * tuning.drag
	apply_central_force(drag_f)
	total += drag_f

	_expected_dv = (total / mass + Vector3.DOWN * 9.81 * gravity_scale) * dt
	_prev_vel = linear_velocity


## In the air the car turns into its flight direction (tangent of the
## parabola): nose along the velocity vector, no roll. Very slow falls (e.g.
## sliding off the edge) only get levelled.
func _align_to_flight(b: Basis, dt: float) -> void:
	if airtime < tuning.air_align_delay:
		return
	var v := linear_velocity
	var dir := v.normalized()
	if v.length() < tuning.air_align_min_speed:
		dir = Vector3(-b.z.x, 0.0, -b.z.z).normalized()
		if dir.length() < 0.1:
			return
	# limit pitch so a near-vertical fall does not flip the car on its nose
	var max_pitch := deg_to_rad(tuning.air_align_max_pitch)
	var flat := Vector2(dir.x, dir.z).length()
	var pitch := clampf(atan2(dir.y, flat), -max_pitch, max_pitch)
	var heading := Vector3(dir.x, 0.0, dir.z).normalized() if flat > 0.05 else Vector3(-b.z.x, 0.0, -b.z.z).normalized()
	var target := Basis.looking_at(heading, Vector3.UP) * Basis(Vector3.RIGHT, pitch)
	var q := (target * b.orthonormalized().inverse()).get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	var angle := q.get_angle()
	var desired := Vector3.ZERO
	if angle > 1e-4:
		desired = q.get_axis().normalized() * angle * tuning.air_align_rate
	# feed-forward: the parabola turns at w = v x g / |v|^2 (removes the lag)
	if v.length() >= tuning.air_align_min_speed:
		desired += v.cross(Vector3.DOWN * 9.81 * gravity_scale) / v.length_squared()
	angular_velocity = angular_velocity.lerp(desired, clampf(dt * tuning.air_align_blend, 0.0, 1.0))
	if debug and verbose and Engine.get_physics_frames() % 15 == 0:
		print("[Air] t=%.2fs flight angle %+.1f deg, car pitch %+.1f deg, error %.1f deg" % [airtime, rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length())), rad_to_deg(asin(clampf(-b.z.y, -1.0, 1.0))), rad_to_deg(angle)])


## Velocity change not explained by our own forces and gravity = collision.
## One damage evaluation per landing, from the speed into the road surface.
func _touchdown() -> void:
	var v_n := -linear_velocity.dot(touchdown_normal)
	landed.emit(v_n)
	_impact_suppress = 0.35
	if v_n > tuning.landing_damage_speed:
		_damage(minf((v_n - tuning.landing_damage_speed) * tuning.landing_damage_factor, tuning.max_hit_damage), "landing v_n=%.1f air=%.2fs" % [v_n, airtime])


func _check_impact() -> void:
	_impact_suppress = maxf(0.0, _impact_suppress - get_physics_process_delta_time())
	if _skip_impact > 0:
		_skip_impact -= 1
		return
	if _impact_suppress > 0.0:
		return
	var unexplained := (linear_velocity - _prev_vel) - _expected_dv
	var m := unexplained.length()
	if m > MAX_SANE_SPEED:
		return    # solver glitch, not a real crash (velocity is clamped below)
	if m > tuning.impact_threshold:
		impacted.emit(m)
		_damage(minf((m - tuning.impact_threshold) * tuning.impact_damage_factor, tuning.max_hit_damage), "impact dv=%.1f" % m)


func _damage(amount: float, why := "") -> void:
	var eff := damage.hit(amount)
	if debug and verbose:
		print("[Car] damage %.3f (%s) speed=%.1f crack=%.3f holes=%d pos=%s" % [eff, why, speed, damage.crack, damage.holes, global_position])
