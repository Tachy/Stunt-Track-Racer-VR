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
		"test_net_golden", "test_net_roundtrip", "test_title_music", "test_doppler_source", "test_doppler_listener", "test_sound_travel_time", "test_tunnel_track", "test_tunnel_mesh_and_ground", "test_editor_basics", "test_editor_closing", "test_editor_crossings", "test_editor_heights", "test_editor_crossing_heights", "test_custom_track_delete", "test_track_share", "test_editor_deep_tunnel", "test_road_stripes", "test_league_pits_vertical",
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
			# steps only at the vertical walls of pits and ski jumps
			if p.road[i] == 1 and p.road[j] == 1 and p.steep[i] == 0 and p.step[i] == 0 and absf(p.center[j].y - p.center[i].y) > 1.0:
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
	pkt = NetCodec.packet(NetCodec.EVENT, 12, 5, 42, NetCodec.encode_event(2, NetCodec.EV_OFFER,
		NetCodec.ev_offer("big_dipper", true)))
	check(pkt.hex_encode() == _golden("offer"), "offer packet matches Go: %s" % pkt.hex_encode())
	pkt = NetCodec.packet(NetCodec.EVENT, 13, 5, 42, NetCodec.encode_event(3, NetCodec.EV_TAKE, NetCodec.ev_take(513)))
	check(pkt.hex_encode() == _golden("take"), "take packet matches Go: %s" % pkt.hex_encode())
	var part := PackedByteArray([0x78, 0x9c, 0x01, 0xff])
	pkt = NetCodec.packet(NetCodec.EVENT, 14, 5, 42, NetCodec.encode_event(4, NetCodec.EV_TRACK, NetCodec.ev_track(1, 3, part)))
	check(pkt.hex_encode() == _golden("track"), "track packet matches Go: %s" % pkt.hex_encode())
	h = NetCodec.parse(_golden("track").hex_decode())
	e = NetCodec.decode_event(h["body"])
	check(e.get("kind", 0) == NetCodec.EV_TRACK and e["part"] == 1 and e["parts"] == 3 and e["data"] == part, "track event")
	h = NetCodec.parse(_golden("lobby").hex_decode())
	e = NetCodec.decode_event(h["body"])
	var offers: Array = e.get("offers", [])
	check(e.get("kind", 0) == NetCodec.EV_LOBBY and e["id"] == 5 and e["online"] == 300 and offers.size() == 2, "lobby event")
	if offers.size() == 2:
		check(offers[0]["id"] == 513 and offers[0]["name"] == "Max" and offers[0]["track"] == "camel_back" and not offers[0]["super"], "lobby offer 1")
		check(offers[1]["id"] == 7 and offers[1]["name"] == "Jöhn" and offers[1]["track"] == "big_dipper" and offers[1]["super"], "lobby offer 2")
		check((offers[1]["color"] as Color).is_equal_approx(Color8(255, 128, 0)), "lobby colour")


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
	check(NetCodec.parse_address("1.2.3.4") == ["1.2.3.4", 27015], "address without port")
	check(NetCodec.parse_address(" racer.example.org:4000 ") == ["racer.example.org", 4000], "address with port")
	check(NetCodec.parse_address("1.2.3.4:abc") == ["1.2.3.4", 27015], "bad port -> default")
	check(NetCodec.parse_address("udp://host/") == ["host", 27015], "scheme and slash stripped")
	check(NetCodec.parse_address("")[0] == "", "empty address")


# --- title music ---------------------------------------------------------------------

func test_title_music() -> void:
	var bars := TitleMusic.song()
	check(bars.size() == 34, "34 bars (%d)" % bars.size())
	var ok := true
	for b in bars:
		var eighths := 0
		for tok in String(b["melody"]).split(" ", false):
			eighths += int(tok.split(":")[1])
		if eighths != 0 and eighths != 8:
			ok = false
			printerr("bar %s melody has %d eighths" % [b["chord"], eighths])
		TitleMusic.chord(b["chord"])   # parses
	check(ok, "every melody bar fills 4/4")
	check(TitleMusic.midi("A4") == 69 and TitleMusic.midi("C#5") == 73 and TitleMusic.midi("Bb4") == 70, "note names")
	check(TitleMusic.chord("Bbm") == [10, [0, 3, 7]] and TitleMusic.chord("C7") == [0, [0, 4, 7, 10]], "chord names")
	var s := TitleMusic.render(8, 10)
	check(s.size() == 2 * TitleMusic.bar_samples(), "two bars rendered")
	var peak := 0.0
	var finite := true
	for x in s:
		peak = maxf(peak, absf(x))
		finite = finite and is_finite(x)
	check(finite and peak > 0.2 and peak <= 0.951, "audible, finite, not clipping (peak %.2f)" % peak)


# --- sound propagation (Doppler, travel time) ----------------------------------------

## Emits a 1000 Hz tone for `secs`; source and listener move with constant
## velocity. Returns the heard frequency over the last second.
func _heard_freq(src0: Vector3, src_v: Vector3, lis0: Vector3, lis_v: Vector3, secs := 3.0) -> float:
	var rate := 16000.0
	var sp := SoundPropagation.new(rate)
	var heard := PackedFloat32Array()
	var n := 0
	var block := 256
	while n < int(secs * rate):
		var emitted := PackedFloat32Array()
		emitted.resize(block)
		for i in block:
			emitted[i] = sin(TAU * 1000.0 * (n + i) / rate)
		n += block
		var t := n / rate
		heard.append_array(sp.process(emitted, src0 + src_v * t, lis0 + lis_v * t))
	# frequency from interpolated rising zero crossings in the last second
	var first := -1.0
	var last := -1.0
	var count := 0
	for i in range(heard.size() - int(rate), heard.size()):
		if heard[i - 1] < 0.0 and heard[i] >= 0.0:
			var x := (i - 1) + heard[i - 1] / (heard[i - 1] - heard[i])
			if first < 0.0:
				first = x
			last = x
			count += 1
	return (count - 1) / ((last - first) / rate)


func test_doppler_source() -> void:
	var c := SoundPropagation.SPEED_OF_SOUND
	# source approaches at 0.1 c: f / (1 - 0.1) = 1111.1 Hz (not 1100)
	var f := _heard_freq(Vector3(0, 0, 400), Vector3(0, 0, -0.1 * c), Vector3.ZERO, Vector3.ZERO)
	check(near(f, 1000.0 / 0.9, 1.0), "approaching source: %.1f Hz, want 1111.1" % f)
	# source recedes at 0.1 c: f / 1.1 = 909.1 Hz
	f = _heard_freq(Vector3(0, 0, 20), Vector3(0, 0, 0.1 * c), Vector3.ZERO, Vector3.ZERO)
	check(near(f, 1000.0 / 1.1, 1.0), "receding source: %.1f Hz, want 909.1" % f)


func test_doppler_listener() -> void:
	var c := SoundPropagation.SPEED_OF_SOUND
	# listener approaches at 0.1 c: f (1 + 0.1) = 1100 Hz (not 1111)
	var f := _heard_freq(Vector3(0, 0, 400), Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, 0.1 * c))
	check(near(f, 1100.0, 1.0), "approaching listener: %.1f Hz, want 1100" % f)
	# moving side by side at the same speed: no shift
	f = _heard_freq(Vector3(30, 0, 0), Vector3(0, 0, -40), Vector3.ZERO, Vector3(0, 0, -40))
	check(near(f, 1000.0, 1.0), "same velocity: %.1f Hz, want 1000" % f)


func test_sound_travel_time() -> void:
	var rate := 16000.0
	var sp := SoundPropagation.new(rate)
	var heard := PackedFloat32Array()
	for k in 100:
		var b := PackedFloat32Array()
		b.resize(320)
		if k == 0:
			b[0] = 1.0   # a click at t = 0
		heard.append_array(sp.process(b, Vector3(343.0, 0, 0), Vector3.ZERO))
	var at := -1
	for i in heard.size():
		if heard[i] > 0.5:
			at = i
			break
	check(at >= 0 and absi(at - 16000) <= 1, "click from 343 m heard after 1 s (sample %d)" % at)
	check(near(sp.delay(), 1.0, 1e-4), "delay 1 s (%.4f)" % sp.delay())


# --- tunnels -------------------------------------------------------------------------

func test_tunnel_track() -> void:
	var p := TrackPath.new(TrackLibrary.get_def("grand_tour"))
	check(p.closure_error < 0.5 and p.heading_error < 0.01, "grand_tour closed (err %.3f)" % p.closure_error)
	check(p.total_length > 3500.0, "grand_tour is long (%.0f m)" % p.total_length)
	var covered := 0
	var cut := 0
	var roof_ok := true
	for i in p.n:
		covered += p.tunnel[i]
		cut += p.cut[i]
		if p.tunnel[i] == 1:
			var c := p.tunnel_corners(i)
			if maxf(c[2].y, c[3].y) + TrackPath.TUNNEL_ROOF > 0.0:
				roof_ok = false
	check(covered > 300, "covered tunnel (%d m)" % covered)
	check(cut > 20 and cut < 200, "open cuts at both ends (%d m)" % cut)
	check(roof_ok, "tunnel roof below the ground everywhere")
	var holes := p.ground_holes()
	check(holes.size() == 2, "two openings in the ground (%d)" % holes.size())
	# the start straight runs over the tunnel, not into it
	var over := false
	for i in p.n:
		if p.tunnel[i] == 0:
			continue
		for j in range(0, p.n, 2):
			if p.tunnel[j] == 0 and p.road[j] == 1 and Vector2(p.center[j].x - p.center[i].x, p.center[j].z - p.center[i].z).length() < 6.0 and p.center[j].y > 5.0:
				over = true
				break
		if over:
			break
	check(over, "a road crosses over the tunnel")
	var crane_ok := true
	for pi_ in p.pieces.size():
		var rs := p.recovery_s(float(p.pieces[pi_]["s0"]) + float(p.pieces[pi_]["length"]) * 0.5)
		var k := p.index_at_s(rs)
		if not p.is_crane_allowed(p.piece_at_s(rs)) or p.road[k] != 1 or p.tunnel[k] == 1 or p.cut[k] == 1:
			crane_ok = false
	check(crane_ok, "crane never sets down in a tunnel or cut")


func test_tunnel_mesh_and_ground() -> void:
	var p := TrackPath.new(TrackLibrary.get_def("grand_tour"))
	var node := TrackNode.new().build(p)
	check(node.has_node("TunnelMesh") and node.has_node("TunnelLamps"), "tunnel mesh and lamps")
	var lights := 0
	for c in node.get_children():
		if c is OmniLight3D:
			lights += 1
	check(lights > 10, "tunnel lights (%d)" % lights)
	node.free()
	# ground: open over the cut, closed over the covered tunnel
	var tris := PackedVector3Array()
	GroundMesh.area(Rect2(-4000, -4000, 8000, 8000), p.ground_holes(), tris)
	var in_cut := -1
	var in_tunnel := -1
	for i in p.n:
		if p.cut[i] == 1 and p.center[i].y < -3.0 and in_cut < 0:
			in_cut = i
		if p.tunnel[i] == 1 and p.tunnel_depth[i] > 50.0 and in_tunnel < 0:
			in_tunnel = i
	check(not _ground_covers(tris, p.center[in_cut]), "no ground over the open cut")
	check(_ground_covers(tris, p.center[in_tunnel]), "ground over the covered tunnel")
	var area := 0.0
	for t in range(0, tris.size(), 3):
		area += 0.5 * absf((tris[t + 1] - tris[t]).cross(tris[t + 2] - tris[t]).y)
	var hole_area := 0.0
	for h in p.ground_holes():
		hole_area += absf(_poly_area(h))
	check(absf(area + hole_area - 8000.0 * 8000.0) < 50.0, "ground + holes = whole square (diff %.1f m2)" % (area + hole_area - 64e6))


func _ground_covers(tris: PackedVector3Array, pos: Vector3) -> bool:
	var q := Vector2(pos.x, pos.z)
	for t in range(0, tris.size(), 3):
		if Geometry2D.point_is_inside_triangle(q, Vector2(tris[t].x, tris[t].z), Vector2(tris[t + 1].x, tris[t + 1].z), Vector2(tris[t + 2].x, tris[t + 2].z)):
			return true
	return false


func _poly_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var j := (i + 1) % poly.size()
		a += poly[i].x * poly[j].y - poly[j].x * poly[i].y
	return a * 0.5


# --- track editor ---------------------------------------------------------------------

func _closes(m: TrackEditorModel) -> bool:
	var p := TrackPath.new(m.to_def("t"))
	return p.closure_error < 0.5 and p.heading_error < 0.01


## Two flat wide curves in a row (the ends of the 30 deg curves of all radii
## lie only metres apart): the radius of the latest curve is kept; zoomed in
## (smaller head start) another radius can be picked.
func _check_curve_chain() -> void:
	var m := TrackEditorModel.new()
	m.set_start(Vector2(0, 0))
	m.place_first(Vector2(0, -200))
	m.place(m.group_for(TrackEditorModel.curve("R", 30, 100)))
	var e: Array = m.end_pose()
	var ends := {}
	for r in TrackEditorModel.RADII:
		var pose := e
		for p in m.group_for(TrackEditorModel.curve("R", 30, r)):   # with its run-out
			pose = TrackEditorModel.advance(pose[0], pose[1], p)
		ends[r] = pose[0]
	for k in 8:
		var c := m.candidate(ends[100] + Vector2.from_angle(TAU * k / 8.0) * 4.0)
		check(c.size() == 1 and c[0]["t"] == "R" and c[0]["a"] == 30 and c[0]["r"] == 100, "second R30 r100 near its end (%s)" % [c])
	var c := m.candidate(ends[75], 1.5)
	check(c[-1]["a"] == 30 and c[-1]["r"] == 75, "zoomed in: another radius (%s)" % [c])
	c = m.candidate(ends[75])
	check(c.size() == 1 and c[0]["r"] == 100, "zoomed out: the radius is kept (%s)" % [c])


func test_editor_basics() -> void:
	var m := TrackEditorModel.new()
	m.set_start(Vector2(0, 0))
	var f := m.first_straight_for(Vector2(3, -52))
	check(f[0] == Vector2(0, -1) and near(f[1], 50.0), "first straight: axis direction, 5 m grid (%s)" % [f])
	m.place_first(Vector2(3, -52))
	# straight ahead
	var c := m.candidate(Vector2(1, -130))
	check(c.size() == 1 and c[0]["t"] == "S" and near(c[0]["l"], 80.0), "straight on to the mouse (%s)" % [c])
	# off to the right: a right curve
	c = m.candidate(Vector2(80, -60))
	check(c.size() == 1 and c[0]["t"] == "R", "curve towards the mouse (%s)" % [c])
	m.place(c)
	# a left curve now needs a run-out for the change of banking
	var e: Array = m.end_pose()
	var d: Vector2 = e[1]
	c = m.candidate(e[0] + d * 120.0 + d.rotated(-PI * 0.5) * 120.0)
	check(c.size() == 2 and c[0].get("auto", false) and c[0]["t"] == "S" and c[1]["t"] == "L", "run-out before a counter curve (%s)" % [c])
	check(near(c[0]["l"], TrackEditorModel.snap(TrackEditorModel.TRANSITION_FULL * absf(c[1]["bank"] - m.last_piece()["bank"]) / 72.0)), "run-out length from the change of banking")
	m.place(c)
	var n := m.pieces.size()
	m.undo()
	check(m.pieces.size() == n - 2, "Esc removes the curve with its run-out")
	m.redo()
	check(m.pieces.size() == n, "redo puts it back")
	_check_curve_chain()
	# loops get a run-up after a curve
	var lg := m.loop_group(1)
	check(lg.size() == 2 and lg[0]["l"] == TrackEditorModel.LOOP_RUNWAY and lg[1]["t"] == "O", "loop with run-up")


func test_editor_closing() -> void:
	# square: three right turns, the solver adds the last one
	var m := TrackEditorModel.new()
	m.set_start(Vector2(0, 0))
	m.place_first(Vector2(0, -100))
	m.place([TrackEditorModel.curve("R", 90, 55)])
	m.place([TrackEditorModel.straight(100)])
	m.place([TrackEditorModel.curve("R", 90, 55)])
	m.place([TrackEditorModel.straight(100)])
	m.place([TrackEditorModel.curve("R", 90, 55)])
	var g := m.closing_group()
	check(not g.is_empty(), "closing pieces found")
	m.place(g, true)
	check(m.closed and _closes(m), "square closes exactly")
	# irregular: odd angles and an S-bend, closed by the solver
	var m2 := TrackEditorModel.new()
	m2.set_start(Vector2(10, 20))
	m2.place_first(Vector2(150, 22))
	for p in [TrackEditorModel.curve("L", 60, 75), TrackEditorModel.straight(85), TrackEditorModel.curve("R", 30, 40),
			TrackEditorModel.curve("L", 120, 55), TrackEditorModel.straight(40), TrackEditorModel.curve("L", 45, 100)]:
		m2.place(m2.group_for(p))
	var g2 := m2.closing_group()
	check(not g2.is_empty(), "irregular layout: closing pieces found")
	m2.place(g2, true)
	check(_closes(m2), "irregular layout closes exactly")
	var bad := false
	for p in m2.pieces:
		if p["t"] == "S" and float(p["l"]) < 0.0:
			bad = true
	check(not bad, "no negative straights")
	# save / load
	var j: Dictionary = JSON.parse_string(JSON.stringify(m2.to_dict("x")))
	var m3 := TrackEditorModel.from_dict(j)
	check(m3.closed and m3.pieces.size() == m2.pieces.size() and _closes(m3), "save/load round trip")


func test_editor_crossings() -> void:
	# figure eight crosses itself once
	var m := TrackEditorModel.new()
	m.set_start(Vector2(0, 0))
	m.place_first(Vector2(0, -200))
	for p in [TrackEditorModel.curve("L", 90, 55), TrackEditorModel.curve("L", 90, 55), TrackEditorModel.curve("L", 90, 55),
			TrackEditorModel.straight(220)]:
		m.place(m.group_for(p))
	check(m.crossings().size() >= 1, "crossing found (%d)" % m.crossings().size())


func _editor_oval() -> TrackEditorModel:
	var m := TrackEditorModel.new()
	m.set_start(Vector2(0, 0))
	m.place_first(Vector2(0, -250))
	for p in [TrackEditorModel.curve("R", 90, 55), TrackEditorModel.straight(60), TrackEditorModel.curve("R", 90, 55),
			TrackEditorModel.straight(250), TrackEditorModel.curve("R", 90, 55)]:
		m.place(m.group_for(p))
	m.place(m.closing_group(), true)
	return m


func test_editor_heights() -> void:
	var m := _editor_oval()
	var n := m.pieces.size()
	var length := m.profile_length()
	check(m.points().size() == 2, "at first only the start and the end point")
	check(near(m.points()[1][0], length) and near(m.points()[1][1], m.base), "end point at the start height")
	var p := TrackPath.new(m.to_def("t"))
	check(near(p.profile_length, length), "profile length (%.1f / %.1f)" % [p.profile_length, length])
	check(absf(p.center[p.n / 2].y - m.base) < 0.01, "flat at the start height")
	# free points: the spline passes through them, not flat there
	var i := m.add_point(length * 0.3, 15.0)
	check(i == 1, "new point index")
	check(m.add_point(length * 0.3 + 1.0, 3.0) == -1, "no point right next to another")
	m.add_point(length * 0.6, 10.0)
	p = TrackPath.new(m.to_def("t"))
	var k := p.index_at_s(length * 0.3)
	check(absf(p.center[k].y - 15.0) < 0.3, "spline through the point (%.2f)" % p.center[k].y)
	var k2 := p.index_at_s(length * 0.6)
	check(absf(p.center[k2 + 10].y - p.center[k2 - 10].y) > 0.2, "not flat at a point between a high and a low one")
	check(absf(p.center[p.n - 1].y - p.center[0].y) < 0.3, "no step at the start line")
	# moving, the start drags the end along, delete, corner, undo
	m.move_point(1, length * 0.35, 20.0)
	check(near(m.points()[1][0], roundf(length * 0.35)) and near(m.points()[1][1], 20.0), "point moved")
	m.move_point(0, 99.0, 12.0)
	check(near(m.base, 12.0) and near(m.points()[-1][1], 12.0) and near(m.points()[0][0], 0.0), "start and end move together")
	m.move_point(m.points().size() - 1, 0.0, 4.0)
	check(near(m.base, 4.0), "end point moves the start")
	check(m.toggle_corner(2) and m.points()[2][2], "corner point")
	check(not m.delete_point(0) and not m.delete_point(m.points().size() - 1), "start and end stay")
	check(m.delete_point(1) and m.points().size() == 3, "point deleted")
	for u in 5:
		m.undo_height()
	check(m.points().size() == 4 and near(m.base, TrackEditorModel.DEFAULT_BASE), "undo")
	# old files: piece end heights become points
	var old := m.to_dict("o")
	old.erase("heights")
	old["pieces"][2]["h"] = 14.0
	var m_old := TrackEditorModel.from_dict(old)
	check(m_old.heights.size() == 1 and near(m_old.heights[0][1], 14.0) and not m_old.pieces[2].has("h"), "old heights converted")
	# slope limit: a point asked too high stops where the curve is 100 % steep
	m = _editor_oval()
	i = m.add_point(30.0, 60.0)
	p = TrackPath.new(m.to_def("t"))
	var steepest := 0.0
	for j in p.n - 1:
		if p.loop_mask[j] == 0 and p.loop_mask[j + 1] == 0:
			steepest = maxf(steepest, absf(p.center[j + 1].y - p.center[j].y) / maxf(p.px[j + 1] - p.px[j], 0.01))
	check(m.points()[i][1] > m.base + 5.0 and m.points()[i][1] < 40.0, "point stopped by the slope limit (%.1f)" % m.points()[i][1])
	check(steepest <= TrackEditorModel.MAX_SLOPE + 0.05, "spline at most 100 %% steep (%.3f)" % steepest)
	m.move_point(i, 30.0, 60.0)
	check(m.points()[i][1] < 40.0, "dragging up stops too")
	# walls: a point pulled hard under its neighbour snaps there
	m = _editor_oval()
	m.move_point(0, 0.0, 9.0)
	var count := 0
	var ia := m.add_point(100.0, 11.0)
	var ib := m.add_point(120.0, 11.0)
	m.move_point(ib, 101.0, 6.0)
	var pts := m.points()
	check(near(pts[ib][0], 100.0) and near(pts[ib][1], 6.0) and pts[ib][3] == 1, "pulled under its neighbour: a wall down")
	var ic := m.add_point(114.0, 6.0)
	var id := m.add_point(130.0, 30.0)
	check(m.points()[id][1] < 30.0, "a normal point stays within the slope")
	m.move_point(id, 115.0, 10.0)
	check(HeightSpline.is_wall(m.points(), ic), "pulled over its neighbour: a wall up")
	p = TrackPath.new(m.to_def("t"))
	var walls := 0
	for j in p.n:
		walls += p.step[j]
	check(walls == 2 and p.pits.size() == 1, "wall down + wall up = pit (%d walls, %d pits)" % [walls, p.pits.size()])
	var pit: Array = p.pits[0]
	check(near(p.px[pit[1]] - p.px[pit[0]], 15.0, 1.5), "pit 14 m wide (%.1f)" % (p.px[pit[1]] - p.px[pit[0]]))
	check(near(p.center[pit[0]].y - p.center[(pit[0] + 1) % p.n].y, 5.0, 0.3), "wall 5 m down")
	check(m.problems(p).filter(func(o): return o["kind"] == "steep").is_empty(), "walls are not reported as steep")
	var node := TrackNode.new().build(p)
	node.free()
	# the wall point moves only up and down; the top point takes the wall along
	m.move_point(ib, 101.0, 7.0)
	check(near(m.points()[ib][0], 100.0) and near(m.points()[ib][1], 7.0), "wall point: only height")
	m.move_point(ia, 104.0, 11.0)
	check(near(m.points()[ia][0], 104.0) and near(m.points()[ib][0], 104.0), "the wall moves with its top")
	# pulled away to the right: a spline point again
	m.move_point(ib, 112.0, 7.0)
	check(m.points()[ib][3] == 0 and not HeightSpline.is_wall(m.points(), ia), "pulled off: a spline point again")
	m.undo_height()
	check(HeightSpline.is_wall(m.points(), ia), "undo: the wall is back")
	var back := TrackEditorModel.from_dict(JSON.parse_string(JSON.stringify(m.to_dict("x"))))
	check(HeightSpline.is_wall(back.points(), ia) and HeightSpline.is_wall(back.points(), ic), "walls saved")
	check(m.delete_point(ib) and not HeightSpline.is_wall(m.points(), ia), "deleting a wall point removes the wall")
	# a lower wall point near the ground snaps onto it (the top does not)
	m = _editor_oval()
	m.move_point(0, 0.0, 9.0)
	ia = m.add_point(100.0, 11.0)
	ib = m.add_point(110.0, 11.0)
	m.move_point(ib, 101.0, 3.5)
	check(near(m.points()[ib][1], 0.0), "lower wall point 3.5 m up snaps to the ground")
	m.move_point(ib, 100.0, -4.0)
	check(near(m.points()[ib][1], 0.0), "4 m below snaps up to the ground")
	m.move_point(ib, 100.0, 6.0)
	check(near(m.points()[ib][1], 6.0), "6 m up stays")
	m.move_point(ib, 100.0, 0.0)
	m.move_point(ia, 100.0, 4.0)
	check(near(m.points()[ia][1], 4.0), "the top of a wall does not snap")
	# a wall at a fractional x (older files) can still be moved up and down
	m = _editor_oval()
	m.move_point(0, 0.0, 9.0)
	m.heights = [[150.169602069447, 20.5, false, 0], [150.169602069447, 10.0, false, 1]]
	m.move_point(2, 151.0, 12.0)
	check(near(m.points()[2][1], 12.0) and HeightSpline.is_wall(m.points(), 1), "wall point at a fractional x moves")
	# a pit down to the ground in a banked curve: a gap too (no road, no
	# cut), vertical walls
	m = _editor_oval()
	m.move_point(0, 0.0, 9.0)
	m.add_point(270.0, 9.0)
	ib = m.add_point(280.0, 9.0)
	m.move_point(ib, 271.0, 1.0)
	m.add_point(285.0, 0.0)
	id = m.add_point(295.0, 9.0)
	m.move_point(id, 286.0, 9.0)
	p = TrackPath.new(m.to_def("t"))
	var cuts := 0
	var ground := 0
	walls = 0
	for j in p.n:
		if p.px[j] > 268.0 and p.px[j] < 290.0:
			cuts += p.cut[j]
			walls += p.step[j]
			ground += p.ground_floor[j]
	check(cuts == 0 and walls == 2 and ground >= 10, "ground pit in a curve: a gap with walls (%d cuts, %d walls, %d ground)" % [cuts, walls, ground])
	node = TrackNode.new().build(p)
	node.free()
	# pulled off a wall with a point close beside it: it stays a wall point
	m = _editor_oval()
	ia = m.add_point(100.0, 11.0)
	ib = m.add_point(110.0, 11.0)
	m.move_point(ib, 101.0, 4.0)
	m.add_point(102.0, 4.0)
	count = m.points().size()
	m.move_point(ib, 110.0, 4.0)
	check(m.points().size() == count, "pulling a wall point off next to a close point keeps every point")
	# dragging never removes a point: random drags around the walls
	m = TrackEditorModel.from_dict(back.to_dict("x"))
	count = m.points().size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lost := 0
	for t in 400:
		var kk := rng.randi_range(1, count - 2)
		var q: Array = m.points()[kk]
		m.move_point(kk, float(q[0]) + rng.randf_range(-12.0, 12.0), float(q[1]) + rng.randf_range(-8.0, 8.0), false, 8.0)
		if m.points().size() != count:
			lost += 1
			count = m.points().size()
	check(lost == 0, "no point lost while dragging (%d)" % lost)
	# a single wall down: ski jump; a pit floor on the ground is the ground
	m = _editor_oval()
	m.move_point(0, 0.0, 4.0)
	ia = m.add_point(100.0, 5.0)
	ib = m.add_point(110.0, 5.0)
	m.move_point(ib, 100.0, 0.0)
	ic = m.add_point(116.0, 0.0)
	id = m.add_point(130.0, 4.0)
	m.move_point(id, 117.0, 5.0)
	m.add_point(500.0, 9.0)
	var ie := m.add_point(520.0, 9.0)
	m.move_point(ie, 500.0, 5.0)
	p = TrackPath.new(m.to_def("t"))
	var gf := 0
	for j in p.n:
		gf += p.ground_floor[j]
	check(p.pits.size() == 1 and p.ramps.size() == 1, "pit and ski jump (%d, %d)" % [p.pits.size(), p.ramps.size()])
	check(gf >= 10, "pit floor on the ground (%d samples)" % gf)
	node = TrackNode.new().build(p)
	node.free()


func test_editor_deep_tunnel() -> void:
	# long oval, the back straight 100 m below the ground
	var m := TrackEditorModel.new()
	m.set_start(Vector2(0, 0))
	m.place_first(Vector2(0, -400))
	for q in [TrackEditorModel.curve("R", 90, 100), TrackEditorModel.straight(100), TrackEditorModel.curve("R", 90, 100),
			TrackEditorModel.straight(800), TrackEditorModel.curve("R", 90, 100)]:
		m.place(m.group_for(q))
	m.place(m.closing_group(), true)
	check(m.closed, "deep oval closes")
	var k := 0
	for i in m.pieces.size():
		if m.pieces[i]["t"] == "S" and float(m.pieces[i]["l"]) >= 800.0:
			k = i
	var x := m.piece_x(k) + 400.0
	var i := m.add_point(x, -130.0)
	check(near(m.points()[i][1], -100.0), "clamped to -100 m")
	var p := TrackPath.new(m.to_def("t"))
	var low := INF
	var tunnel := 0
	for j in p.n:
		low = minf(low, p.center[j].y)
		tunnel += p.tunnel[j]
	check(near(low, -100.0, 0.5), "road down to -100 m (%.1f)" % low)
	check(tunnel > 300, "long covered tunnel (%d m)" % tunnel)
	check(m.problems(p).filter(func(o): return o["kind"] == "steep").is_empty(), "the way down is not too steep")
	var node := TrackNode.new().build(p)
	check(node.has_node("TunnelMesh"), "deep tunnel mesh")
	node.free()


func test_league_pits_vertical() -> void:
	for id in ["camel_back", "stone_hopper", "the_tower"]:
		var p := TrackPath.new(TrackLibrary.get_def(id))
		var walls := 0
		var steep := 0
		for i in p.n:
			walls += p.step[i]
			if p.pit_mask[i] == 1:
				steep += p.steep[i]
		check(walls >= 2 * p.pits.size() and steep == 0, "%s: pit walls vertical (%d walls, %d steep)" % [id, walls, steep])
		for pt in p.pits:
			var lip: int = pt[0]
			check(p.center[lip].y - p.center[(lip + 1) % p.n].y > 3.0, "%s: drop right after the lip" % id)


func test_road_stripes() -> void:
	for id in ["camel_back", "grand_tour", "stone_hopper"]:
		var p := TrackPath.new(TrackLibrary.get_def(id))
		var node := TrackNode.new().build(p)
		var ok_border := true
		var longest := 0.0
		var run := 0.0
		for i in p.n:
			var j := (i + 1) % p.n
			if p.piece_of[i] != p.piece_of[j] and node._stripe[i] == node._stripe[j]:
				ok_border = false
			run += p.delta_s(p.s_arr[i], p.s_arr[j])
			if node._stripe[i] != node._stripe[j]:
				longest = maxf(longest, run)
				run = 0.0
		check(ok_border, "%s: colour changes at every piece border (also at the start)" % id)
		check(longest <= TrackNode.STRIPE_MAX + 1.5, "%s: stripes at most %d m (%.1f)" % [id, TrackNode.STRIPE_MAX, longest])
		node.free()


func test_custom_track_delete() -> void:
	var id := TrackLibrary.CUSTOM_PREFIX + "zz_test_delete"
	DirAccess.make_dir_recursive_absolute(TrackLibrary.CUSTOM_DIR)
	var f := FileAccess.open(TrackLibrary.custom_path(id), FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	check(TrackLibrary.delete_custom(id), "custom track deleted")
	check(not FileAccess.file_exists(TrackLibrary.custom_path(id)), "file gone")
	check(not TrackLibrary.delete_custom(id), "nothing left to delete")
	check(not TrackLibrary.delete_custom("camel_back"), "built-in tracks cannot be deleted")


## A shared editor track: kept in memory for the race, never saved.
func test_track_share() -> void:
	var src := TrackLibrary.CUSTOM_PREFIX + "zz_test_share"
	var def := TrackLibrary.get_def("camel_back")
	def.erase("id")
	DirAccess.make_dir_recursive_absolute(TrackLibrary.CUSTOM_DIR)
	var f := FileAccess.open(TrackLibrary.custom_path(src), FileAccess.WRITE)
	f.store_string(JSON.stringify({"name": "ZZ Share", "closed": true, "pieces": [], "def": def}))
	f.close()
	var files := DirAccess.get_files_at(TrackLibrary.CUSTOM_DIR).size()
	var id := TrackLibrary.install_shared(TrackLibrary.share_data(src))
	TrackLibrary.delete_custom(src)
	check(id == TrackLibrary.SHARED_ID, "shared track kept as %s" % id)
	check(TrackLibrary.display_name(id) == "ZZ Share" and TrackLibrary.division_of(id) == 1, "shared name")
	var d := TrackLibrary.get_def(id)
	check(d.get("id") == id and d.get("pieces") == JSON.parse_string(JSON.stringify(def["pieces"])), "shared def")
	check(TrackPath.new(d).total_length > 100.0, "shared track drivable")
	check(DirAccess.get_files_at(TrackLibrary.CUSTOM_DIR).size() == files - 1, "nothing saved")
	check(TrackLibrary.install_shared(PackedByteArray([1, 2, 3])) == "", "garbage refused")
	check(TrackLibrary.install_shared(JSON.stringify({"name": "x"}).to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE)) == "", "no def refused")
	TrackLibrary.clear_shared()
	check(TrackLibrary.get_def(id).get("pieces") == null, "cleared")


func test_editor_crossing_heights() -> void:
	# figure eight: the third straight crosses the start straight
	var m := TrackEditorModel.new()
	m.set_start(Vector2(0, 0))
	m.place_first(Vector2(0, -150))
	for p in [TrackEditorModel.curve("L", 90, 55), TrackEditorModel.straight(100), TrackEditorModel.curve("L", 90, 55),
			TrackEditorModel.straight(50), TrackEditorModel.curve("L", 90, 55), TrackEditorModel.straight(300),
			TrackEditorModel.curve("R", 90, 55), TrackEditorModel.straight(100), TrackEditorModel.curve("R", 90, 55),
			TrackEditorModel.straight(150)]:
		m.place(m.group_for(p))
	var g := m.closing_group()
	check(not g.is_empty(), "figure closes")
	m.place(g, true)
	var p := TrackPath.new(m.to_def("t"))
	var crossings := m.problems(p).filter(func(o): return o["kind"] == "crossing")
	check(crossings.size() >= 1, "flat crossing reported (%d)" % crossings.size())
	# lift the branch that crosses the start straight (the straight after the
	# third left curve and its neighbours), back down before the start
	var k := 0
	var lefts := 0
	while lefts < 3:
		if m.pieces[k]["t"] == "L":
			lefts += 1
		k += 1
	m.add_point(m.piece_x(k - 2), 22.0)
	m.add_point(m.piece_x(k + 2), 22.0)
	p = TrackPath.new(m.to_def("t"))
	crossings = m.problems(p).filter(func(o): return o["kind"] == "crossing")
	check(crossings.is_empty(), "no crossing problem once 16 m apart (%d)" % crossings.size())
