extends SceneTree
## Headless logic tests. Run:
##   godot --headless --xr-mode off --path . --script res://tests/run_tests.gd

var _passed := 0
var _failed := 0
var _current := ""


func _init() -> void:
	var tests := [
		"test_cockpit_half_pitch", "test_cockpit_half_roll", "test_cockpit_extremes",
		"test_recenter", "test_tracks_closed", "test_track_heights", "test_track_mesh",
		"test_lap_tracker", "test_recovery", "test_bridge", "test_damage", "test_league",
		"test_league_roundtrip", "test_input_norm", "test_ai_profile",
		"test_custom1_layout", "test_loop_geometry", "test_tilt_rule", "test_tumble_view", "test_shifted_loop_view", "test_crane_chains",
		"test_league_track_features", "test_no_unintended_crossings", "test_legacy_save_ids", "test_translations",
		"test_net_golden", "test_net_roundtrip",
	]
	for t in tests:
		_current = t
		call(t)
	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL [%s] %s" % [_current, what])


func near(a: float, b: float, eps := 1e-3) -> bool:
	return absf(a - b) <= eps


# --- cockpit / VR view ----------------------------------------------------------------

func test_cockpit_half_pitch() -> void:
	var yaw := 0.7
	var car := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(20.0))
	var b := CockpitMath.view_basis(car, 0.5)
	check(near(rad_to_deg(CockpitMath.pitch_of(b)), 10.0, 0.05), "pitch 20 -> 10 (got %f)" % rad_to_deg(CockpitMath.pitch_of(b)))
	check(near(CockpitMath.yaw_of(b), yaw, 1e-3), "yaw preserved")


func test_cockpit_half_roll() -> void:
	var car := Basis(Vector3.UP, -1.2) * Basis(Vector3.FORWARD, deg_to_rad(30.0))
	var b := CockpitMath.view_basis(car, 0.5)
	check(near(absf(rad_to_deg(CockpitMath.roll_of(b))), 15.0, 0.05), "roll 30 -> 15 (got %f)" % rad_to_deg(CockpitMath.roll_of(b)))


func test_cockpit_extremes() -> void:
	var car := Basis(Vector3.UP, 0.3) * Basis(Vector3.RIGHT, 0.4) * Basis(Vector3.FORWARD, 0.2)
	var b0 := CockpitMath.view_basis(car, 0.0)
	check(near(CockpitMath.pitch_of(b0), 0.0) and near(CockpitMath.roll_of(b0), 0.0), "tilt 0 is level")
	var b1 := CockpitMath.view_basis(car, 1.0)
	check(b1.is_equal_approx(car.orthonormalized()), "tilt 1 follows car")
	# nose straight up must not produce NaN
	var vertical := Basis(Vector3.RIGHT, PI * 0.5)
	var bv := CockpitMath.view_basis(vertical, 0.5)
	check(not is_nan(bv.x.x), "vertical car no NaN")
	var xf := Transform3D(car, Vector3(5, 6, 7))
	var bt := CockpitMath.base_transform(xf, Vector3(0, 1, 0.3), 0.5)
	check(bt.origin.is_equal_approx(xf * Vector3(0, 1, 0.3)), "eye point at seat")


func test_recenter() -> void:
	var base := Transform3D(CockpitMath.view_basis(Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, 0.2), 0.5), Vector3(10, 5, -3))
	var head := Transform3D(Basis(Vector3.UP, 0.9) * Basis(Vector3.RIGHT, -0.15), Vector3(0.2, 1.1, 0.4))
	var off := CockpitMath.recenter_offset(head)
	var origin := CockpitMath.origin_transform(base, off)
	var cam := origin * head
	check(cam.origin.is_equal_approx(base.origin), "head at eye point after recenter")
	check(near(CockpitMath.yaw_of(cam.basis), CockpitMath.yaw_of(base.basis), 1e-3), "head yaw matches base yaw")
	# moving the head 10 cm to the left moves the camera 10 cm along base -X
	var head2 := Transform3D(head.basis, head.origin + Basis(Vector3.UP, 0.9) * Vector3(-0.1, 0, 0))
	var cam2 := origin * head2
	check(near((cam2.origin - cam.origin).dot(base.basis.x.normalized()), -0.1, 1e-3), "6DOF relative to base")


# --- tracks ---------------------------------------------------------------------------

func test_tracks_closed() -> void:
	check(TrackLibrary.ORDER.size() == 8, "8 tracks")
	for id in TrackLibrary.ORDER:
		var p := TrackPath.new(TrackLibrary.get_def(id))
		check(p.closure_error < 0.5, "%s closed (err %.3f)" % [id, p.closure_error])
		check(p.heading_error < 0.01, "%s heading closed" % id)
		check(p.total_length > 700.0, "%s length %.0f" % [id, p.total_length])
		check(p.n > 600, "%s samples" % id)


func test_track_heights() -> void:
	for id in TrackLibrary.ORDER:
		var p := TrackPath.new(TrackLibrary.get_def(id))
		var ok := true
		var min_h := INF
		for i in p.n:
			var j := (i + 1) % p.n
			min_h = minf(min_h, p.center[i].y - TrackPath.HALF_WIDTH * absf(p.right[i].y))
			# steps only where the road is a (black) pit wall
			if p.road[i] == 1 and p.road[j] == 1 and p.steep[i] == 0 and absf(p.center[j].y - p.center[i].y) > 1.0:
				ok = false
		check(ok, "%s no height steps on road" % id)
		check(min_h > 0.5, "%s road above ground (min %.2f)" % [id, min_h])
		check(p.center[0].distance_to(p.center[p.n - 1]) < 2.0, "%s seam continuous" % id)


func test_track_mesh() -> void:
	var p := TrackPath.new(TrackLibrary.get_def("bridge_run"))
	var node := TrackNode.new().build(p)
	var mi: MeshInstance3D = node.get_node("TrackMesh")
	var arr := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	check(verts.size() > 1000 and verts.size() % 3 == 0, "mesh triangles")
	check(node.get_node("RoadBody") != null and node.get_node("WallBody") != null, "collision bodies")
	var leaves := 0
	for c in node.get_children():
		if c is AnimatableBody3D:
			leaves += 1
	check(leaves == 2, "drawbridge has 2 leaves")
	node.free()


func test_lap_tracker() -> void:
	var lt := LapTracker.new(6, 0)
	var laps := 0
	for piece in [1, 2, 3, 4, 5, 0]:
		if lt.update(piece):
			laps += 1
	check(laps == 1 and lt.laps_done == 1, "one lap")
	var lt2 := LapTracker.new(10, 0)
	lt2.update(1)
	lt2.update(6)        # shortcut, ignored
	lt2.update(0)
	check(lt2.laps_done == 0, "shortcut not counted")
	var lt3 := LapTracker.new(10, 0)
	for piece in [1, 2, 4, 5, 6, 7, 9, 0]:  # skipping single short pieces is ok
		lt3.update(piece)
	check(lt3.laps_done == 1, "skip one piece ok")


func test_recovery() -> void:
	for id in TrackLibrary.ORDER:
		var p := TrackPath.new(TrackLibrary.get_def(id))
		var ok := true
		for pi_ in p.pieces.size():
			var s: float = float(p.pieces[pi_]["s0"]) + float(p.pieces[pi_]["length"]) * 0.5
			var rs := p.recovery_s(s)
			if not p.is_crane_allowed(p.piece_at_s(rs)):
				ok = false
			if p.road[p.index_at_s(rs)] != 1:
				ok = false
		check(ok, "%s crane positions valid" % id)


func test_bridge() -> void:
	check(near(TrackPath.bridge_angle(0.0), 0.0), "bridge closed at t=0")
	var max_a := 0.0
	for k in 200:
		max_a = maxf(max_a, TrackPath.bridge_angle(k * 0.1))
	check(near(max_a, TrackPath.BRIDGE_MAX_ANGLE, 1e-3), "bridge opens fully")
	var p := TrackPath.new(TrackLibrary.get_def("bridge_run"))
	var bp: Dictionary = {}
	for pc in p.pieces:
		if pc["bridge"]:
			bp = pc
	check(not bp.is_empty(), "draw bridge piece exists")
	var s_mid: float = float(bp["s0"]) + float(bp["length"]) * 0.5 - 0.5
	check(near(p.surface_height(s_mid, 0.0), float(bp["h1"]), 0.05), "closed bridge is flat")
	var t_open := TrackPath.BRIDGE_PERIOD * 0.7
	check(p.surface_height(s_mid, t_open) == -INF, "open bridge has a gap in the middle")
	var s_leaf: float = float(bp["s0"]) + float(bp["length"]) * 0.3
	check(p.surface_height(s_leaf, t_open) > float(bp["h1"]) + 1.0, "raised leaf is a ramp")


# --- damage / league / input -------------------------------------------------------------

func test_damage() -> void:
	var d := DamageModel.new(0)
	d.hit(0.05)
	check(near(d.crack, 0.05), "crack grows")
	d.hit(0.2)
	check(d.holes == 1, "heavy hit makes a hole")
	var before := d.crack
	d.hit(0.05)
	check(near(d.crack - before, 0.05 * (1.0 + DamageModel.HOLE_FACTOR)), "holes amplify damage")
	d.hit(5.0)
	check(d.is_wrecked and near(d.crack, 1.0), "wrecked at 1")


func test_league() -> void:
	var l := League.new_game()
	check(l.player_division() == 4, "start in div 4")
	check(l.schedule.size() == 4, "4 races per season")
	for i in 4:
		l.record_player_race({"won": true, "player_fastest": true})
	check(l.season_finished(), "season done")
	check(l.points[League.PLAYER] == 12, "12 points")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var rep := l.finish_season(rng)
	check(l.player_division() == 3, "promoted to div 3: " + rep)
	check(l.season == 2 and l.race_index == 0, "new season")
	var all := []
	for d in l.divisions:
		all.append_array(d)
	check(all.size() == 12 and League.PLAYER in all, "12 drivers")
	# losing everything relegates (from div 3)
	for i in 4:
		l.record_player_race({"won": false, "player_fastest": false})
	l.finish_season(rng)
	check(l.player_division() == 4, "relegated back to div 4")


func test_league_roundtrip() -> void:
	var l := League.new_game()
	l.record_player_race({"won": true, "player_fastest": false, "holes": 2})
	var json := JSON.stringify(l.to_dict())
	var l2 := League.from_dict(JSON.parse_string(json))
	check(l2.race_index == 1 and l2.points[League.PLAYER] == 2 and l2.holes == 2, "save/load league")
	check(l2.next_race()["track"] == l.next_race()["track"], "schedule preserved")


func test_input_norm() -> void:
	check(near(InputMath.pedal_norm(0.0, -1.0, 1.0), 0.5), "pedal half")
	check(near(InputMath.pedal_norm(-1.0, -1.0, 1.0), 0.0), "pedal rest")
	check(near(InputMath.pedal_norm(1.0, 1.0, -1.0), 0.0), "inverted pedal rest")
	check(near(InputMath.pedal_norm(-1.0, 1.0, -1.0), 1.0), "inverted pedal full")
	check(near(InputMath.pedal_norm(0.0, 0.0, -1.0), 0.0) and near(InputMath.pedal_norm(0.5, 0.0, -1.0), 0.0), "combined axis: other side ignored")
	check(near(InputMath.axis_norm(-0.8, -0.8, 0.8), -1.0), "steer left")
	check(near(InputMath.axis_norm(0.8, 0.8, -0.8), -1.0), "inverted steer left")
	check(near(InputMath.axis_norm(0.0, -0.8, 0.8), 0.0), "steer centre")


func test_ai_profile() -> void:
	for id in TrackLibrary.ORDER:
		var p := TrackPath.new(TrackLibrary.get_def(id))
		var v := AiProfile.compute(p)
		var ok := v.size() == p.n
		var vmin := INF
		for x in v:
			vmin = minf(vmin, x)
		check(ok and vmin >= 12.0, "%s ai profile (min %.1f)" % [id, vmin])
		for g in p.gaps():
			var js := AiProfile.jump_speed(p, g[0], g[1])
			check(js < AiProfile.VMAX, "%s gap jumpable at %.1f m/s" % [id, js])


# --- custom track, loops, underpass ------------------------------------------------------

func test_custom1_layout() -> void:
	var p := TrackPath.new(TrackLibrary.get_def("loop_and_jump"))
	check(p.closure_error < 0.5 and p.heading_error < 0.01, "loop_and_jump closed (err %.2f)" % p.closure_error)
	var decks := 0
	var lowest_under := INF
	for i in p.n:
		if p.deck[i] == 1 and p.loop_mask[i] == 0:
			decks += 1
	check(decks > 10, "underpass deck detected (%d samples)" % decks)
	# the low branch passes under the deck with enough clearance
	var ok := true
	for i in p.n:
		if p.deck[i] == 1 and p.loop_mask[i] == 0:
			for j in p.n:
				var d := Vector2(p.center[j].x - p.center[i].x, p.center[j].z - p.center[i].z).length()
				if d < 3.0 and absf(p.delta_s(p.s_arr[i], p.s_arr[j])) > 40.0:
					lowest_under = minf(lowest_under, p.center[i].y - p.center[j].y)
	check(lowest_under > 7.0 and lowest_under < INF, "underpass clearance %.1f m" % lowest_under)
	var crane_ok := true
	for pi_ in p.pieces.size():
		var s: float = float(p.pieces[pi_]["s0"]) + float(p.pieces[pi_]["length"]) * 0.5
		if p.deck[p.index_at_s(p.recovery_s(s))] == 1:
			crane_ok = false
	check(crane_ok, "crane never drops onto a deck")
	var v := AiProfile.floors(p)
	var loop_floor := 0.0
	for i in p.n:
		if p.loop_mask[i] == 1:
			loop_floor = maxf(loop_floor, v[i])
	check(loop_floor > 10.0, "AI has a loop speed floor (%.1f)" % loop_floor)


func test_loop_geometry() -> void:
	var p := TrackPath.new(TrackLibrary.get_def("loop_and_jump"))
	var lp: Dictionary = {}
	for pc in p.pieces:
		if pc["type"] == "O":
			lp = pc
			break
	check(not lp.is_empty(), "loop piece present")
	var i0: int = lp["i0"]
	var i1: int = lp["i1"]
	var top := -INF
	var overhead := 0
	for i in range(i0, i1):
		top = maxf(top, p.center[i].y)
		if p.up[i].y < -0.9:
			overhead += 1
	check(near(top - float(lp["h0"]), 2.0 * TrackPath.LOOP_RADIUS, 0.3), "loop height 2R (%.2f)" % (top - float(lp["h0"])))
	check(overhead > 5, "road is upside down at the top")
	var mid := (i0 + i1) / 2
	check(p.deck[mid] == 1, "overhead part is a deck")
	check(p.deck[i0 + 2] == 0, "rising part keeps the wall to the ground")
	# s_of/nearest stay consistent in the loop (3D)
	var probe := p.center[mid] + p.up[mid] * 0.7
	check(p.nearest(probe, mid - 3, 10) == mid, "nearest works upside down")
	check(p.height_above(probe, mid) > 0.5, "height above surface upside down")


## Runs the car through a sequence of orientations and returns the largest
## amount (deg) by which the view turned faster than 1.5x the car per step.
func _view_overspeed(cars: Array) -> float:
	var worst := 0.0
	for k in range(1, cars.size()):
		var v0 := Quaternion(CockpitMath.view_basis(cars[k - 1], 0.5))
		var v1 := Quaternion(CockpitMath.view_basis(cars[k], 0.5))
		var dc := Quaternion(cars[k - 1]).angle_to(Quaternion(cars[k]))
		worst = maxf(worst, rad_to_deg(v0.angle_to(v1) - 1.5 * dc))
	return worst


## Lag of the view behind the car as a signed angle about the given car axis
## (checks that it is a pure rotation about that axis).
func _lag_about(car: Basis, view: Basis, axis: Vector3, what: String, min_dot := 0.999) -> float:
	var rel := Quaternion(car.inverse() * view)
	if rel.get_angle() < deg_to_rad(0.5):
		return 0.0
	var ax := rel.get_axis().normalized()
	check(absf(ax.dot(axis)) > min_dot, "%s: view only turns about the car axis %s (axis %s)" % [what, axis, ax])
	return rad_to_deg(rel.get_angle()) * signf(ax.dot(axis))


func test_tilt_rule() -> void:
	# rounded triangle
	var max_kink := 0.0
	var h := deg_to_rad(0.5)
	for k in range(-720, 720):
		var a := float(k) * h
		var s0 := (CockpitMath.smooth_triangle(a) - CockpitMath.smooth_triangle(a - h)) / h
		var s1 := (CockpitMath.smooth_triangle(a + h) - CockpitMath.smooth_triangle(a)) / h
		max_kink = maxf(max_kink, absf(s1 - s0))
	check(max_kink < 0.06, "smooth triangle: slope changes gradually (max step %.3f)" % max_kink)
	check(near(rad_to_deg(CockpitMath.smooth_triangle(PI * 0.5)), 80.0, 1e-3), "smooth triangle: peak 80 (lag 40 at share 0.5)")
	check(near(CockpitMath.smooth_triangle(deg_to_rad(30.0)), deg_to_rad(30.0), 1e-4), "smooth triangle: straight away from the corner")
	# pure pitch through a full circle (like a loop) and pure roll (roll-over),
	# at any heading: lag 0 -> 40 -> 0 -> 40 -> 0, only about the car's own axis
	for yaw in [0.0, 0.4, -2.5]:
		var entry := Basis(Vector3.UP, yaw)
		for mode in ["pitch", "roll"]:
			var axis := Vector3.RIGHT if mode == "pitch" else Vector3.FORWARD
			var cars := []
			for k in 361:
				var car := entry * Basis(axis, deg_to_rad(float(k)))
				cars.append(car)
				var view := CockpitMath.view_basis(car, 0.5)
				var lag := _lag_about(car, view, Vector3.RIGHT if mode == "pitch" else Vector3.BACK, "%s %d" % [mode, k])
				var expect := {0: 0.0, 30: 15.0, 90: 40.0, 180: 0.0, 270: 40.0, 330: 15.0}
				if expect.has(k):
					check(near(absf(lag), expect[k], 0.05), "%s %d deg: lag %.1f (got %.2f)" % [mode, k, expect[k], lag])
				if k == 180:
					check(view.is_equal_approx(car), "%s: upside down the view is with the car" % mode)
			check(_view_overspeed(cars) < 0.1, "%s: no jumps (%.2f)" % [mode, _view_overspeed(cars)])
	# upright car on a ramp / banked curve: heading kept, tilt halved
	var tilted := Basis(Vector3.UP, 0.3) * Basis(Vector3.RIGHT, 0.6) * Basis(Vector3.BACK, 0.4)
	var tv := CockpitMath.view_basis(tilted, 0.5)
	check(near(CockpitMath.tilt_of(tv), CockpitMath.tilt_of(tilted) * 0.5, 1e-3), "small tilt: view follows half")
	# combined pitch + roll shifts the heading slightly: small on every track
	for id in TrackLibrary.TRACKS:
		var p := TrackPath.new(TrackLibrary.get_def(id))
		var worst := 0.0
		for i in p.n:
			if p.loop_mask[i] == 0:
				var car := Basis(p.right[i], p.up[i], -p.forward[i]).orthonormalized()
				var v := CockpitMath.view_basis(car, 0.5)
				worst = maxf(worst, absf(angle_difference(CockpitMath.yaw_of(v), CockpitMath.yaw_of(car))))
		check(rad_to_deg(worst) < 2.5, "%s: view heading within 2.5 deg of the car (max %.2f)" % [id, rad_to_deg(worst)])


func test_tumble_view() -> void:
	# a car tumbling freely about mixed axes (fell off the road): the view is
	# defined for every attitude, never NaN, and never jumps
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for run in 5:
		var car := Basis(Vector3.UP, rng.randf() * TAU)
		var w := Vector3(rng.randf_range(-6, 6), rng.randf_range(-6, 6), rng.randf_range(-6, 6))
		var cars := []
		for k in 600:
			car = (Basis(w.normalized(), w.length() / 240.0) * car).orthonormalized()
			cars.append(car)
			var view := CockpitMath.view_basis(car, 0.5)
			if is_nan(view.x.x) or is_nan(view.y.y):
				check(false, "tumble %d: NaN at step %d" % [run, k])
				break
			# view tilt = car tilt - lag
			var lag := CockpitMath.tilt_lag(CockpitMath.tilt_of(car), 0.5)
			if not near(CockpitMath.tilt_of(view), CockpitMath.tilt_of(car) - lag, 1e-3):
				check(false, "tumble %d step %d: view tilt %.2f vs %.2f" % [run, k, CockpitMath.tilt_of(view), CockpitMath.tilt_of(car) - lag])
				break
		check(_view_overspeed(cars) < 0.5, "tumble %d: no jumps (%.2f deg/step)" % [run, _view_overspeed(cars)])
	# exactly upright / upside down
	check(CockpitMath.view_basis(Basis(), 0.5).is_equal_approx(Basis()), "upright: view = car")
	var flipped := Basis(Vector3.FORWARD, PI)
	check(CockpitMath.view_basis(flipped, 0.5).is_equal_approx(flipped), "upside down: view = car")


func test_shifted_loop_view() -> void:
	# real loops are shifted sideways: through the whole loop the view only
	# pitches relative to the car (no roll), lag -40 (nose up) -> 0 (top) ->
	# +40 (nose down), and it does not jump at entry or exit
	var p := TrackPath.new(TrackLibrary.get_def("loop_and_jump"))
	var loops := 0
	for pc in p.pieces:
		if pc["type"] != "O":
			continue
		loops += 1
		var i0: int = pc["i0"]
		var i1: int = pc["i1"]
		var cars := []
		var best := {"up": [INF, 0.0], "top": [INF, 0.0], "down": [INF, 0.0]}
		var max_lag := 0.0
		for i in range(i0 - 20, i1 + 20):
			var car := Basis(p.right[i], p.up[i], -p.forward[i]).orthonormalized()
			cars.append(car)
			# the lag turns about the horizontal tilt axis; the shifted loop's
			# surface banks up to ~10 deg sideways, so that axis is up to ~20 deg
			# off the car's cross axis (the view levels part of that real roll)
			var view := CockpitMath.view_basis(car, 0.5)
			var lag := _lag_about(car, view, Vector3.RIGHT, "loop %d sample %d" % [loops, i], 0.94)
			var rel := (car.inverse() * view).get_euler(EULER_ORDER_YXZ)
			check(absf(rad_to_deg(rel.z)) < 9.0, "loop %d sample %d: view roll relative to the car below 9 deg (%.1f)" % [loops, i, rad_to_deg(rel.z)])
			max_lag = maxf(max_lag, absf(lag))
			var nose := (-car.z).y   # +1 nose up, -1 nose down
			for key in best:
				var target: float = {"up": 1.0, "top": 0.0, "down": -1.0}[key]
				var d := absf(nose - target) + (0.0 if key != "top" or car.y.y < 0.0 else 9.0)
				if d < best[key][0]:
					best[key] = [d, lag]
		check(max_lag < 40.3, "loop %d: lag within 40 deg (max %.1f)" % [loops, max_lag])
		check(near(best["up"][1], -40.0, 1.0), "loop %d: nose up -> view 40 below nose (got %.1f)" % [loops, best["up"][1]])
		check(near(best["top"][1], 0.0, 1.5), "loop %d: upside down -> view along driving direction (got %.1f)" % [loops, best["top"][1]])
		check(near(best["down"][1], 40.0, 1.0), "loop %d: nose down -> view 40 above nose (got %.1f)" % [loops, best["down"][1]])
		check(_view_overspeed(cars) < 0.1, "loop %d: no jumps (%.2f)" % [loops, _view_overspeed(cars)])
	check(loops == 2, "two loops checked")


func test_crane_chains() -> void:
	var crane := Crane.new()
	var xf := Transform3D(Basis(Vector3.UP, 0.7), Vector3(10, 5, -20))
	crane.hold(xf)
	var hook := xf * Vector3(0, Crane.HOOK_HEIGHT, 0)
	# held: taut and straight from the hook to the car corners
	for c in crane._chains.size():
		var pts: PackedVector3Array = crane._chains[c]["pts"]
		check(pts[0].is_equal_approx(hook), "chain %d starts at the hook" % c)
		check(pts[pts.size() - 1].is_equal_approx(xf * (Crane.CORNERS[c] as Vector3)), "chain %d ends at the car corner" % c)
	# released (hook kept in place here): the chains swing down and settle
	crane._free = true
	var max_stretch := 0.0
	var swing_late := 0.0
	for step in 1200:   # 10 s at 120 Hz
		var before: Vector3 = crane._chains[0]["pts"][crane._chains[0]["pts"].size() - 1]
		crane._simulate(1.0 / 120.0)
		var after: Vector3 = crane._chains[0]["pts"][crane._chains[0]["pts"].size() - 1]
		if step > 1080:
			swing_late = maxf(swing_late, before.distance_to(after) * 120.0)
	for c in crane._chains.size():
		var ch: Dictionary = crane._chains[c]
		var pts: PackedVector3Array = ch["pts"]
		var seg: float = ch["seg"]
		for i in pts.size() - 1:
			max_stretch = maxf(max_stretch, absf(pts[i].distance_to(pts[i + 1]) - seg) / seg)
		var end := pts[pts.size() - 1]
		check(not is_nan(end.x), "chain %d: no NaN" % c)
		var length := seg * (pts.size() - 1)
		check(Vector2(end.x - hook.x, end.z - hook.z).length() < 0.15 * length, "chain %d hangs below the hook (offset %.2f)" % [c, Vector2(end.x - hook.x, end.z - hook.z).length()])
		check(end.y < hook.y - 0.9 * length, "chain %d hangs straight down" % c)
	check(max_stretch < 0.03, "chain links keep their length (max stretch %.1f %%)" % (max_stretch * 100.0))
	check(swing_late < 0.3, "swinging dies down (end speed %.2f m/s after 9 s)" % swing_late)
	crane.free()


func test_league_track_features() -> void:
	# the rebuilt tracks carry the original features
	var expect := {"first_flight": 2, "camel_back": 1, "mega_ramp": 2, "stone_hopper": 5, "the_tower": 1, "bridge_run": 2}
	for id in expect:
		var p := TrackPath.new(TrackLibrary.get_def(id))
		check(p.pits.size() >= expect[id], "%s has pits (%d)" % [id, p.pits.size()])
	var max_bank := 0.0
	for id in TrackLibrary.ORDER:
		var p := TrackPath.new(TrackLibrary.get_def(id))
		for i in p.n:
			max_bank = maxf(max_bank, rad_to_deg(asin(clampf(absf(p.right[i].y), 0.0, 1.0))))
	check(max_bank > 34.0, "steep banking (max %.1f deg)" % max_bank)
	var sj := TrackPath.new(TrackLibrary.get_def("ski_flyer"))
	var top := 0.0
	for i in sj.n:
		top = maxf(top, sj.center[i].y)
	check(top > 40.0, "ski jump tower (%.0f m)" % top)


func test_no_unintended_crossings() -> void:
	# two parts of a track may only overlap in plan view as an underpass
	# (at least 7 m apart vertically)
	for id in TrackLibrary.ORDER + TrackLibrary.CUSTOM:
		var p := TrackPath.new(TrackLibrary.get_def(id))
		var worst := INF
		for i in range(0, p.n, 3):
			for j in range(i + 3, p.n, 3):
				if absf(p.delta_s(p.s_arr[i], p.s_arr[j])) < 40.0:
					continue
				var d := Vector2(p.center[j].x - p.center[i].x, p.center[j].z - p.center[i].z).length()
				if d < p.half_width[i] + p.half_width[j]:
					worst = minf(worst, absf(p.center[i].y - p.center[j].y))
		check(worst >= 7.0, "%s: no crossing at road level (closest %.1f m)" % [id, worst])


func test_legacy_save_ids() -> void:
	var d := League.new_game().to_dict()
	d["schedule"] = [{"track": "little_ramp", "opponent": 9}, {"track": "hump_back", "opponent": 10}]
	var l := League.from_dict(d)
	check(l.schedule[0]["track"] == "first_flight" and l.schedule[1]["track"] == "camel_back", "old save track ids are translated")


func test_translations() -> void:
	# every UI text passed to Lang.t() has a German entry
	var re := RegEx.create_from_string("Lang\\.t\\(\"((?:[^\"\\\\]|\\\\.)*)\"\\)")
	var missing := []
	var count := 0
	for dir in ["res://scripts/ui", "res://scripts/race", "res://scripts/hud", "res://scripts/league", "res://scripts/autoload"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var text := FileAccess.get_file_as_string(dir.path_join(f))
			for m in re.search_all(text):
				var key := m.get_string(1).c_unescape()
				count += 1
				if not Lang.DE.has(key):
					missing.append(key)
	check(count > 60, "UI texts found (%d)" % count)
	check(missing.is_empty(), "German translation for every UI text, missing: %s" % [missing])
	Lang.current = "de"
	check(Lang.t("PRACTICE") == "ÜBUNGSFAHRT", "German lookup")
	Lang.current = "en"
	check(Lang.t("PRACTICE") == "PRACTICE", "English default")


# --- online protocol -----------------------------------------------------------------

func _golden(name: String) -> String:
	return FileAccess.get_file_as_string("res://server/testdata/%s.hex" % name).strip_edges()


func test_net_golden() -> void:
	# the same messages as server/protocol_test.go: byte-identical encoding
	var st := {
		"t": 12.345, "pos": Vector3(123.456, -7.89, 1000.001), "rot": Quaternion(0.1, -0.9, 0.3, 0.3),
		"vel": Vector3(12.344, -3.21, 45.678), "angvel": Vector3(0.1234, -2.3456, 11.0),
		"steer": -0.3, "throttle": 0.8, "brake": 0.12, "boosting": true, "reverse": false,
		"held": true, "state": "racing", "boost": 7, "crack": 0.4, "holes": 2,
	}
	var pkt := NetCodec.packet(NetCodec.STATE, 65535, 2, 0xDEADBEEF, NetCodec.encode_state(st))
	check(pkt.hex_encode() == _golden("state"), "state packet matches Go: %s" % pkt.hex_encode())
	pkt = NetCodec.packet(NetCodec.HELLO, 1, 0, 0, NetCodec.encode_hello("Jöhn", Color8(255, 128, 0)))
	check(pkt.hex_encode() == _golden("hello"), "hello packet matches Go: %s" % pkt.hex_encode())
	pkt = NetCodec.packet(NetCodec.EVENT, 7, 0, 42, NetCodec.encode_event(1, NetCodec.EV_JOIN,
		NetCodec.ev_join(NetCodec.JOIN_CREATE, "abcd", "camel_back", true)))
	check(pkt.hex_encode() == _golden("join"), "join packet matches Go: %s" % pkt.hex_encode())
	# decode a server message encoded by Go
	var h := NetCodec.parse(_golden("match").hex_decode())
	check(h.get("type", 0) == NetCodec.EVENT and h["seq"] == 9 and h["ack"] == 4 and h["token"] == 42, "match header")
	var e := NetCodec.decode_event(h["body"])
	check(e.get("kind", 0) == NetCodec.EV_MATCH and e["id"] == 3 and e["slot"] == 1, "match event")
	check(e.get("track", "") == "camel_back" and e.get("opp_name", "") == "Max" and e.get("super", true) == false, "match fields")
	check((e["opp_color"] as Color).is_equal_approx(Color8(34, 102, 221)), "match colour")


func test_net_roundtrip() -> void:
	var rot := Quaternion(Vector3(0.3, 1.0, -0.2).normalized(), 2.5)
	var st := {
		"t": 61.5, "pos": Vector3(-812.25, 33.1, 2.0), "rot": rot,
		"vel": Vector3(-41.0, 3.33, 0.07), "angvel": Vector3(-1.5, 0.25, 9.9),
		"steer": 1.0, "throttle": 0.0, "brake": 1.0, "boosting": false, "reverse": true,
		"held": false, "airborne": true, "state": "wrecked", "boost": 0, "crack": 1.0, "holes": 8,
	}
	var data := NetCodec.encode_state(st)
	check(data.size() == NetCodec.STATE_SIZE, "state is %d bytes" % data.size())
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var d := NetCodec.decode_state(b)
	check(near(d["t"], 61.5) and (d["pos"] as Vector3).is_equal_approx(st["pos"]), "time and position")
	check(((d["vel"] - st["vel"]) as Vector3).length() < 0.01 and ((d["angvel"] - st["angvel"]) as Vector3).length() < 0.002, "velocities")
	var dq: Quaternion = d["rot"]
	check(absf(dq.dot(rot)) > 0.99999, "rotation (dot %f)" % absf(dq.dot(rot)))
	check(d["reverse"] and d["airborne"] and not d["boosting"] and not d["held"] and d["state"] == "wrecked" and d["holes"] == 8, "flags")
	check(near(d["steer"], 1.0) and near(d["brake"], 1.0) and near(d["crack"], 1.0), "inputs")
	check(NetCodec.seq_newer(2, 65534) and not NetCodec.seq_newer(65534, 2) and not NetCodec.seq_newer(5, 5), "sequence wrap-around")
	check(NetCodec.parse(PackedByteArray([1, 2, 3])).is_empty(), "short packet rejected")
