extends SceneTree
## Headless logic tests. Run:
##   godot --headless --xr-mode off --path . --script res://tests/run_tests.gd

var _passed := 0
var _failed := 0
var _current := ""


func _init() -> void:
	var tests := [
		"test_cockpit_half_pitch", "test_cockpit_half_roll", "test_cockpit_extremes",
		"test_recenter", "test_examples_install", "test_tracks_closed", "test_track_heights", "test_track_mesh",
		"test_lap_tracker", "test_recovery", "test_bridge", "test_fallen_on_bridge", "test_damage", "test_league",
		"test_league_roundtrip", "test_input_norm", "test_ai_profile",
		"test_custom1_layout", "test_loop_geometry", "test_tilt_rule", "test_tumble_view", "test_shifted_loop_view", "test_crane_chains",
		"test_no_unintended_crossings", "test_legacy_save_ids", "test_translations",
		"test_net_golden", "test_net_roundtrip", "test_title_music", "test_doppler_source", "test_doppler_listener", "test_sound_travel_time", "test_tunnel_track", "test_tunnel_mesh_and_ground", "test_editor_basics", "test_editor_closing", "test_editor_crossings", "test_editor_cut", "test_editor_move", "test_editor_move_start", "test_editor_nudge", "test_editor_reverse", "test_track_waves", "test_editor_move_points", "test_height_ribbon", "test_editor_view_dome", "test_wall_on_sample", "test_wall_mesh_upright", "test_official_in_editor", "test_loop_radius", "test_editor_heights", "test_editor_crossing_heights", "test_custom_track_delete", "test_track_share", "test_editor_deep_tunnel", "test_road_stripes", "test_steep_road_black", "test_crane_before_black_walls", "test_jump_align", "test_parachute", "test_road_on_ground", "test_bank_hold", "test_crane_motor_sound", "test_engine_start_stop", "test_wind_noise", "test_speed_signs", "test_tyre_squeal", "test_wall_point_roles", "test_league_pits_vertical",
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

## The league tracks and the shipped example tracks.
func _track_ids() -> Array:
	return TrackLibrary.ORDER + TrackLibrary.EXAMPLES.map(func(e): return TrackLibrary.EXAMPLE_PREFIX + e)


## The example tracks: shipped, copied once into the own tracks (never over
## an own file of the same name, a deleted one does not come back).
func test_examples_install() -> void:
	var dir := "user://test_examples"
	var marker := dir.path_join("installed.txt")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for ex in TrackLibrary.EXAMPLES:
		var d := TrackLibrary.load_example(ex)
		check(d.get("def") is Dictionary and not d.has("official"), "example %s shipped as an own track" % ex)
		check(not TrackLibrary.is_official(ex), "example %s is no official track" % ex)
	# an own file of the same name stays
	var own := FileAccess.open(dir.path_join("grand_tour.json"), FileAccess.WRITE)
	own.store_string("{\"name\": \"mine\"}")
	own.close()
	var copied := TrackLibrary.install_examples(dir, marker)
	check(copied == ["loop_and_jump"], "copied the missing example only (%s)" % [copied])
	check(FileAccess.get_file_as_string(dir.path_join("grand_tour.json")).contains("mine"), "own file not overwritten")
	check(FileAccess.get_file_as_string(dir.path_join("loop_and_jump.json")) == FileAccess.get_file_as_string(TrackLibrary.example_path("loop_and_jump")), "example copied as it is")
	DirAccess.remove_absolute(dir.path_join("loop_and_jump.json"))
	check(TrackLibrary.install_examples(dir, marker).is_empty(), "a deleted example does not come back")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


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
		for i in p.n:
			var j := (i + 1) % p.n
			# steps only at the vertical walls of pits and ski jumps
			if p.road[i] == 1 and p.road[j] == 1 and p.steep[i] == 0 and p.step[i] == 0 and absf(p.center[j].y - p.center[i].y) > 1.0:
				ok = false
		check(ok, "%s no height steps on road" % id)
		check(p.center[0].distance_to(p.center[p.n - 1]) < 2.0, "%s seam continuous" % id)


func test_track_mesh() -> void:
	var p := TrackPath.new(TrackLibrary.get_def("example/grand_tour"))     # has a drawbridge
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


## The crane sets the car down where it left the road, back to at least
## JUMP_RUNUP before a jump and before a tunnel; never on a loop, a gap, a
## drawbridge, a deck, a "no crane" piece or under another road. Curves and
## open cuts are fine. (Checked here against the track data, not with the
## crane's own rule.)
func test_recovery() -> void:
	var curves := 0
	var cuts := 0
	for id in _track_ids():
		var p := TrackPath.new(TrackLibrary.get_def(id))
		var jumps := p.crane_jumps()
		var bad := ""
		var runup := true
		var exact := true
		var behind := true
		var s := 0.0
		while s < p.total_length:
			var rs := p.recovery_s(s)
			var k := p.index_at_s(rs)
			var why := _no_crane_reason(p, k)
			if why != "" and bad == "":
				bad = "%s at s=%.0f (from %.0f)" % [why, rs, s]
			runup = runup and _jump_clear(p, jumps, rs, 0.5)
			if _no_crane_reason(p, p.index_at_s(s)) == "" and _jump_clear(p, jumps, s, 0.0):
				exact = exact and is_equal_approx(rs, p.wrap_s(s))
				var pc: Dictionary = p.pieces[p.piece_of[k]]
				if pc["type"] != "S":
					curves += 1
				if p.cut[k] == 1:
					cuts += 1
			elif p.delta_s(rs, s) <= 0.0:
				behind = false
			s += 7.0
		check(bad == "", "%s: crane sets down on plain road only %s" % [id, bad])
		check(runup, "%s: crane sets down %d m before a jump at least" % [id, TrackPath.JUMP_RUNUP])
		check(exact, "%s: crane sets down where the car left the road" % id)
		check(behind, "%s: crane goes back, not on" % id)
	check(curves > 0, "crane sets down in curves (%d spots)" % curves)
	check(cuts > 0, "crane sets down in open cuts (%d spots)" % cuts)

## Why the crane must not set a car down at sample i ("" = it may).
func _no_crane_reason(p: TrackPath, i: int) -> String:
	var pc: Dictionary = p.pieces[p.piece_of[i]]
	if p.road[i] != 1:
		return "no road"
	if p.tunnel[i] == 1:
		return "tunnel"
	if p.loop_mask[i] == 1:
		return "loop"
	if p.deck[i] == 1:
		return "deck"
	if pc["bridge"] or p.bridge_zone[i] == 1:
		return "drawbridge"
	if (p.pit_mask.size() == p.n and p.pit_mask[i] == 1) or (p.step.size() == p.n and p.step[i] == 1):
		return "pit"
	for j in p.n:
		if p.center[j].y > p.center[i].y + 2.0 and absf(p.delta_s(p.s_arr[i], p.s_arr[j])) > 30.0:
			var d := Vector2(p.center[j].x - p.center[i].x, p.center[j].z - p.center[i].z).length()
			if d < p.half_width[i] + p.half_width[j] + 2.0:
				return "under a road"
	return ""


## No jump within JUMP_RUNUP (less tolerance, m) ahead of s, and s not on one.
func _jump_clear(p: TrackPath, jumps: Array, s: float, tolerance: float) -> bool:
	var k := p.index_at_s(s)
	for jp in jumps:
		var ahead := fposmod(p.s_arr[jp[0]] - s, p.total_length)
		if ahead < TrackPath.JUMP_RUNUP - tolerance or p._fwd_dist(jp[0], k) <= p._fwd_dist(jp[0], jp[1]):
			return false
	return true


## A car on a drawbridge has not fallen off (its engine must not stall
## there); through the open bridge, beside or below the road it has.
func test_fallen_on_bridge() -> void:
	var p := TrackPath.new(TrackLibrary.get_def("example/loop_and_jump"))
	var i := -1
	for k in p.n:
		if p.bridge_zone[k] == 1:
			i = k
			break
	check(i >= 0, "bridge zone found")
	var h := p.road_height(i)
	check(not p.fallen(i, 0.0, h + 0.5), "on the bridge leaves: not fallen")
	check(p.fallen(i, 0.0, h - 8.0), "through the open bridge: fallen")
	var j := 0
	while p.road[j] != 1 or p.ground_floor[j] == 1 or (p.pit_mask.size() == p.n and p.pit_mask[j] == 1):
		j += 1
	var hj := p.road_height(j)
	check(not p.fallen(j, 0.0, hj + 0.5), "on the road: not fallen")
	check(not p.fallen(j, p.half_width[j] + 2.0, hj + 0.5), "beside the road, as high: not fallen")
	check(p.fallen(j, p.half_width[j] + 2.0, hj - 5.0), "beside and below the road: fallen")


func test_bridge() -> void:
	check(near(TrackPath.bridge_angle(0.0), 0.0), "bridge closed at t=0")
	var max_a := 0.0
	for k in 200:
		max_a = maxf(max_a, TrackPath.bridge_angle(k * 0.1))
	check(near(max_a, TrackPath.BRIDGE_MAX_ANGLE, 1e-3), "bridge opens fully")
	var p := TrackPath.new(TrackLibrary.get_def("example/grand_tour"))     # has a drawbridge
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
		for g in AiProfile.jumps(p):
			var js := AiProfile.plan_jump(p, g[0], g[1], AiProfile.VMAX).x
			check(js < AiProfile.VMAX and AiProfile.touchdown_speed(p, g[0], g[1], js) < INF, "%s jump %d planned at %.1f m/s" % [id, g[0], js])


# --- custom track, loops, underpass ------------------------------------------------------

func test_custom1_layout() -> void:
	var p := TrackPath.new(TrackLibrary.get_def("example/loop_and_jump"))
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
	var p := TrackPath.new(TrackLibrary.get_def("example/loop_and_jump"))
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
	# below 2 deg the axis means nothing (a shifted loop's exit still banks
	# 1-2 deg; the roll is checked on its own)
	if rel.get_angle() < deg_to_rad(2.0):
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
	# +40 (nose down), and it does not jump at entry or exit (before and
	# after the loop only where the road itself is not banked: a curve's
	# banking may begin right after it)
	var p := TrackPath.new(TrackLibrary.get_def("example/loop_and_jump"))
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
			if (i < i0 or i >= i1) and absf(p.right[i].y) > 0.02:
				continue
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
	root.add_child(crane)
	var basis := Basis(Vector3.UP, 0.7)
	var target := Transform3D(basis, Vector3(10, 9, -20))
	var ground := Transform3D(basis, target * Vector3(7.0, 0, 0))
	ground.origin.y = CarModel.RIDE_HEIGHT
	crane.start(target, ground, 900.0)
	check(crane.car_xform().origin.is_equal_approx(ground.origin), "crane: the car starts on the ground")
	# lift + trolley: then the car hangs over the road, swinging a little
	var dt := 1.0 / 120.0
	var t := 0.0
	var max_phi := 0.0
	var t_drop := -1.0
	while not crane.arrived() and t < 30.0:
		crane.step(dt)
		t += dt
		max_phi = maxf(max_phi, absf(crane._phi))
		if t_drop < 0.0 and crane.droppable():
			t_drop = t
	var t_x: float = crane._plan_x[0]["t0"]
	var chain_then: float = Crane._eval_axis(crane._plan_c, t_x, 0.0)[0]
	check(near(chain_then, Crane.CHAIN_LEN + Crane.TROLLEY_LEAD, 0.01), "crane: the trolley sets off %.1f m before the chain is all in" % (chain_then - Crane.CHAIN_LEN))
	check(t_drop > 0.0 and t_drop < t - 0.5, "crane: droppable once the car swings over the road (%.1f s, done %.1f s)" % [t_drop, t])
	check(crane.arrived() and near(t, crane.duration(), 0.02), "crane: over the road after %.1f s" % t)
	var narrow := Crane.new()
	root.add_child(narrow)
	narrow.start(target, ground, 900.0, Vector2(-1.0, 1.0))   # no room for the car anywhere
	var t_narrow := -1.0
	var tn := 0.0
	while tn < 30.0 and t_narrow < 0.0:
		narrow.step(dt)
		tn += dt
		if narrow.droppable():
			t_narrow = tn
	check(near(t_narrow, narrow.duration(), 0.02), "crane: an early drop only over the road (%.1f s, done %.1f s)" % [t_narrow, narrow.duration()])
	narrow.free()
	var off := crane.car_xform().origin - target.origin
	check(off.length() < 2.0, "crane: the car hangs near its drop pose (%.2f m)" % off.length())
	check(max_phi > deg_to_rad(2.0) and max_phi < deg_to_rad(25.0), "crane: the car swings (max %.1f deg)" % rad_to_deg(max_phi))
	# taut chains: trolley -> hook -> car corners
	crane._pin_chains()
	var xf := crane.car_xform()
	var hook := xf * Vector3(0, Crane.HOOK_HEIGHT, 0)
	var main: PackedVector3Array = crane._chains[0]["pts"]
	check(main[0].is_equal_approx(crane._pivot) and main[main.size() - 1].is_equal_approx(hook), "main chain from the trolley to the hook")
	check(near(crane._pivot.distance_to(hook), Crane.CHAIN_LEN, 1e-3), "main chain %.1f m long" % Crane.CHAIN_LEN)
	for c in Crane.CORNERS.size():
		var pts: PackedVector3Array = crane._chains[c + 1]["pts"]
		check(pts[0].is_equal_approx(hook) and pts[pts.size() - 1].is_equal_approx(xf * (Crane.CORNERS[c] as Vector3)), "sling %d from the hook to the car corner" % c)
	# the swing: a physical pendulum, period 2 pi sqrt(I / (m g d))
	var crossings: Array = []
	var prev := crane._phi
	for k in 120 * 30:
		crane.step(dt)
		if signf(crane._phi) != signf(prev) and prev != 0.0:
			crossings.append(k * dt)
		prev = crane._phi
	var expect := TAU * sqrt(crane._inertia / (900.0 * 9.81 * crane._com_dist))
	var period := 2.0 * (float(crossings[-1]) - float(crossings[0])) / (crossings.size() - 1) if crossings.size() > 2 else 0.0
	check(near(period, expect, expect * 0.03), "crane: swing period %.2f s (pendulum %.2f s)" % [period, expect])
	var v: Array = crane.car_velocity(Crane.CAR_COM)
	check((v[1] as Vector3).length() > 0.0 and absf((v[1] as Vector3).normalized().dot(target.basis.z)) > 0.99, "crane: dropped car keeps the swing (roll rate)")
	# released: the chains swing down from the trolley and settle
	crane.release()
	var pivot := crane._pivot
	var max_stretch := 0.0
	var swing_late := 0.0
	for k in 1200:   # 10 s at 120 Hz
		var before: Vector3 = main[main.size() - 1]
		crane._simulate(dt)
		main = crane._chains[0]["pts"]
		if k > 1080:
			swing_late = maxf(swing_late, before.distance_to(main[main.size() - 1]) * 120.0)
	var total := 0.0
	for c in crane._chains.size():
		var ch: Dictionary = crane._chains[c]
		var pts: PackedVector3Array = ch["pts"]
		var seg: float = ch["seg"]
		total += seg * (pts.size() - 1)
		for i in pts.size() - 1:
			max_stretch = maxf(max_stretch, absf(pts[i].distance_to(pts[i + 1]) - seg) / seg)
		var end := pts[pts.size() - 1]
		check(not is_nan(end.x), "chain %d: no NaN" % c)
		check(Vector2(end.x - pivot.x, end.z - pivot.z).length() < 0.15 * total, "chain %d hangs below the trolley" % c)
	check(max_stretch < 0.03, "chain links keep their length (max stretch %.1f %%)" % (max_stretch * 100.0))
	check(swing_late < 0.3, "swinging dies down (end speed %.2f m/s after 9 s)" % swing_late)
	# then the trolley runs back off the road, over the ground spot
	for k in int((Crane.RETURN_DELAY + Crane.RETURN_TIME + 0.5) / dt):
		crane._physics_process(dt)
	check(near(crane._pos.x, 7.0, 0.01), "crane: trolley back over the ground spot (x %.2f)" % crane._pos.x)
	var main_end: Vector3 = crane._chains[0]["pts"][crane._chains[0]["pts"].size() - 1]
	check(not is_nan(main_end.x) and Vector2(main_end.x - crane._pivot.x, main_end.z - crane._pivot.z).length() < Crane.CHAIN_LEN, "crane: the chain came along")
	# banked road: carried over the upper edge, then let down onto the drop pose
	crane.start(target, ground, 900.0, Vector2(-INF, INF), 2.0)
	var top := -INF
	t = 0.0
	while not crane.arrived() and t < 30.0:
		crane.step(dt)
		t += dt
		if absf((target.affine_inverse() * crane.car_xform().origin).x) < 3.0:
			top = maxf(top, (target.affine_inverse() * crane.car_xform().origin).y)
	check(top > 1.9, "crane: carried over the upper edge (%.2f m over the drop pose)" % top)
	check(near((target.affine_inverse() * crane.car_xform().origin).y, 0.0, 0.3), "crane: then let down to its drop pose")
	# winch: starts and stops gently (no jump in speed or acceleration)
	var lift: Dictionary = crane._plan_c[0]
	var v0: Array = Crane._eval_axis(crane._plan_c, float(lift["t0"]) + 0.01, 0.0)
	check(absf(v0[1]) < 0.05 and absf(v0[2]) < 1.0, "crane: the winch starts gently (v %.3f, a %.2f)" % [v0[1], v0[2]])
	crane.free()


func test_no_unintended_crossings() -> void:
	# two parts of a track may only overlap in plan view as an underpass
	# (at least 7 m apart vertically)
	for id in _track_ids():
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
	for dir in ["res://scripts/ui", "res://scripts/race", "res://scripts/hud", "res://scripts/league", "res://scripts/autoload", "res://scripts/editor"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var text := FileAccess.get_file_as_string(dir.path_join(f))
			for m in re.search_all(text):
				var key := m.get_string(1).c_unescape()
				count += 1
				if not Lang.DE.has(key):
					missing.append(key)
	# the editor help is a table (Lang.t() at runtime)
	for key in EditorHelp.texts():
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
	check(e.get("track", "") == "camel_back" and e.get("opp_name", "") == "Max" and e.get("super", true) == false and e.get("pitch_assist", false) == true, "match fields")
	check((e["opp_color"] as Color).is_equal_approx(Color8(34, 102, 221)), "match colour")
	pkt = NetCodec.packet(NetCodec.EVENT, 12, 5, 42, NetCodec.encode_event(2, NetCodec.EV_OFFER,
		NetCodec.ev_offer("big_dipper", true, false)))
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
		"held": false, "airborne": true, "chute": true, "state": "wrecked", "boost": 0, "crack": 1.0, "holes": 8,
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
	check(d["chute"], "parachute flag (bit 7, next to the race state)")
	st["chute"] = false
	b.data_array = NetCodec.encode_state(st)
	check(not NetCodec.decode_state(b)["chute"], "no parachute")
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
	var p := TrackPath.new(TrackLibrary.get_def("example/grand_tour"))
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
		if p.road[k] != 1 or p.tunnel[k] == 1:
			crane_ok = false
	check(crane_ok, "crane never sets down in a tunnel")


func test_tunnel_mesh_and_ground() -> void:
	var p := TrackPath.new(TrackLibrary.get_def("example/grand_tour"))
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


## Marked pieces deleted in the middle of a closed lap; the gap drawn anew
## and closed onto its anchor.
func test_editor_cut() -> void:
	var m := _editor_oval()
	var n := m.pieces.size()
	check(m.piece_at(Vector2(2, -100)) == 0 and m.piece_at(Vector2(200, 200)) == -1, "piece under the mouse")
	check(not m.cut(0, n - 1), "not the whole lap")
	# a click marks one piece (with its run-out), not all the closing pieces
	check(m.pieces[6].get("g") == m.pieces[7].get("g") and m.group_range(6) == Vector2i(6, 6) and m.group_range(7) == Vector2i(7, 7),
		"the closing pieces one by one")
	var mr := TrackEditorModel.new()
	mr.set_start(Vector2.ZERO)
	mr.place_first(Vector2(0, -100))
	mr.place(mr.group_for(TrackEditorModel.curve("R", 90, 55)))
	mr.place(mr.group_for(TrackEditorModel.curve("L", 90, 55)))
	check(mr.pieces[2].get("auto", false) and mr.group_range(3) == Vector2i(2, 3) and mr.group_range(2) == Vector2i(2, 3),
		"a curve with its run-out")
	m.add_point(m.piece_x(2) * 0.5, 10.0)                # before the gap
	m.add_point(m.piece_x(5) + 20.0, 14.0)               # after it
	var after_x := float(m.heights[1][0]) - m.piece_x(4)
	var e: Array = [m.start, m.start_dir]
	for k in 3:
		e = TrackEditorModel.advance(e[0], e[1], m.pieces[k])
	check(m.cut(3, 3), "cut out the second curve")
	check(not m.closed and m.has_gap() and m.pieces.size() == 3 and m.tail.size() == n - 4, "head and tail")
	check(m.end_pose()[0].distance_to(e[0]) < 0.01, "the head ends at the gap")
	check(m.heights.size() == 1, "profile points: the head's stay")
	# Esc right after the cut: the lap as before
	m.undo()
	check(m.closed and not m.has_gap() and m.pieces.size() == n and m.heights.size() == 2, "Esc undoes the cut")
	# a longer cut (straight and curve), closed onto the anchor by other pieces
	m.cut(2, 3)
	m.place(m.group_for(TrackEditorModel.straight(20)))
	check(m.near_target(m.tail_pos) and not m.near_target(m.start), "closing is offered at the anchor")
	var g := m.closing_group()
	check(not g.is_empty(), "closing pieces onto the anchor")
	m.place(g, true)
	check(m.closed and not m.has_gap() and _closes(m), "the gap closes exactly")
	var tail_start := m.pieces.size() - (n - 4)
	check(m.heights.size() == 2 and near(float(m.heights[1][0]), m.piece_x(tail_start) + after_x),
		"profile points after the gap move along (%s)" % [m.heights])
	# with the start straight: the head is empty, the start stays
	m = _editor_oval()
	check(m.cut(0, 1) and m.pieces.is_empty() and m.start_dir != Vector2.ZERO, "cut at the start")
	m.place(m.closing_group(), true)
	check(m.closed and _closes(m), "closed from the start onto the anchor")
	# up to the end: closed onto the start as usual
	m = _editor_oval()
	n = m.pieces.size()
	check(m.cut(n - 2, n - 1) and not m.has_gap(), "cut at the end")
	m.place(m.closing_group(), true)
	check(m.closed and _closes(m), "closed onto the start")
	# saved with a gap
	m = _editor_oval()
	m.cut(2, 3)
	var m2 := TrackEditorModel.from_dict(JSON.parse_string(JSON.stringify(m.to_dict("x"))))
	check(m2.has_gap() and not m2.closed and m2.tail.size() == m.tail.size(), "save/load with a gap")
	m2.place(m2.closing_group(), true)
	check(m2.closed and _closes(m2), "a loaded gap closes")


## A marked stretch dragged in the plan: the gaps before and after it are
## filled, the straights next to it solved anew; profile points go along.
func test_editor_move() -> void:
	var m := _editor_oval()
	var n := m.pieces.size()
	var curve: Dictionary = m.pieces[3]          # the second curve: east -> south
	var p3: Vector2 = m.poses()[3][0]
	m.add_point(m.piece_x(3) + 20.0, 12.0)
	m.add_point(m.piece_x(1) + 10.0, 8.0)        # on the first curve: stays
	var x_first := float(m.heights[0][0])
	var into := float(m.heights[1][0]) - m.piece_x(3)     # (points are put on whole metres)
	# sideways too little for an S-bend of catalogue curves: no move
	check(m.moved(3, 3, Vector2(2, 0)).is_empty() and not m.move_block(3, 3, Vector2(2, 0)), "too small a shift cannot be filled")
	check(m.pieces.size() == n and m.heights.size() == 2, "nothing changed")
	# further on along the straight before it: an S-bend down the long one after it
	check(m.move_block(3, 3, Vector2(60, 0)), "moved")
	check(_closes(m), "the moved lap closes")
	var k := -1
	for i in m.pieces.size():
		if is_same(m.pieces[i], curve):
			k = i
	check(k >= 0 and m.poses()[k][0].distance_to(p3 + Vector2(60, 0)) < 0.05, "the stretch is where it was dragged to")
	check(m.heights.size() == 2 and near(float(m.heights[0][0]), x_first), "the point before stays")
	check(near(float(m.heights[1][0]), m.piece_x(k) + into) and near(float(m.heights[1][1]), 12.0),
		"the point on the stretch goes along (%s)" % [m.heights])
	check(m.pieces[k - 1]["t"] == "S" and near(float(m.pieces[k - 1]["l"]), 120.0), "the straight before is longer")
	# Esc: back
	m.undo()
	check(m.closed and m.pieces.size() == n and m.poses()[3][0].distance_to(p3) < 0.01 and near(float(m.heights[1][0]), m.piece_x(3) + into), "Esc undoes the move")
	# with the start straight: the start line goes along
	var r := m.moved(0, 3, Vector2(0, -40))
	check(not r.is_empty() and (r["start"] as Vector2).distance_to(m.start + Vector2(0, -40)) < 0.05, "the start moves with its straight")
	check(m.move_block(0, 3, Vector2(0, -40)) and _closes(m), "moved with the start")
	# a point on a straight replaced by the gap stays at its place on the new
	# one; the start straight before the stretch: the start stays
	m = _editor_oval()
	m.add_point(m.piece_x(4) + 200.0, 9.0)       # 50 m before the end of the long straight
	var to_end := m.piece_x(5) - float(m.heights[0][0])
	check(m.move_block(1, 3, Vector2(0, 40)) and _closes(m), "moved down")
	check(m.start.distance_to(Vector2.ZERO) < 0.01 and near(float(m.pieces[0]["l"]), 210.0), "the start straight is shorter, the start stays")
	var after: Dictionary = m.pieces[4]
	check(after["t"] == "S" and near(float(after["l"]), 210.0), "the straight after it is shorter (%s)" % [after])
	check(m.heights.size() == 1 and near(float(m.heights[0][0]), m.piece_x(5) - to_end), "its point keeps its distance to the end")


## Cursor keys: the marked pieces one grid step on, or to the nearest step
## further on that fits.
func test_editor_nudge() -> void:
	var m := _editor_oval()
	var r := m.nudge(1, 3, Vector2(0, 1))
	check(not r.is_empty() and r["offset"] == Vector2(0, TrackEditorModel.GRID) and _closes(m), "one step down")
	check(r["block"] == Vector2i(1, 3), "the moved pieces (%s)" % [r["block"]])
	m = _editor_oval()
	var p3: Vector2 = m.poses()[3][0]
	r = m.nudge(3, 3, Vector2(1, 0))
	var off: Vector2 = r.get("offset", Vector2.ZERO)
	check(not r.is_empty() and off.x > TrackEditorModel.GRID and is_zero_approx(fmod(off.x, TrackEditorModel.GRID)) and off.y == 0.0,
		"too small a step: on to the next one that fits (%s)" % off)
	var bk: Vector2i = r["block"]
	check(_closes(m) and m.poses()[bk.x][0].distance_to(p3 + off) < 0.05, "moved there")
	# sideways off the start with nothing ahead to bend in: no step fits
	m = _editor_oval()
	var n := m.pieces.size()
	check(m.nudge(0, 3, Vector2(-1, 0)).is_empty() and m.pieces.size() == n and m.start == Vector2.ZERO, "nothing fits: unchanged")


## The direction of a closed lap reversed: the pieces backwards and
## mirrored, the start line where it is, the heights at the same places.
func test_editor_reverse() -> void:
	var m := TrackEditorModel.new()
	m.set_start(Vector2(0, 0))
	m.place_first(Vector2(0, -150))
	m.place(m.loop_group(1))
	for p in [TrackEditorModel.straight(80), TrackEditorModel.curve("R", 90, 55), TrackEditorModel.straight(60),
			TrackEditorModel.curve("L", 45, 75), TrackEditorModel.curve("R", 135, 55), TrackEditorModel.straight(200), TrackEditorModel.curve("R", 90, 55)]:
		m.place(m.group_for(p))
	m.place(m.closing_group(), true)
	check(m.closed and _closes(m), "a lap with a loop and run-outs")
	m.heights = [[100.0, 12.0, true, 0], [300.0, 20.0, false, 0], [300.0, 4.0, false, 1], [420.0, 9.0, false, 0]]
	m._tidy_heights()
	var before := m.to_dict("x")
	var pts0 := m.points()
	var length := m.profile_length()
	var n := m.pieces.size()
	var first: Dictionary = m.pieces[0].duplicate()
	var last: Dictionary = m.pieces[n - 1].duplicate()
	check(m.reverse(), "reversed")
	check(_closes(m), "the reversed lap closes")
	check(m.start == Vector2.ZERO and m.start_dir.distance_to(Vector2(0, 1)) < 1e-6, "the start line stays, the direction turns")
	check(m.pieces[n - 1]["t"] == first["t"] and m.pieces[0].get("l", 0.0) == last.get("l", 0.0), "the pieces backwards")
	var mirrored := true
	for k in n:
		var a: Dictionary = m.pieces[k]
		var b: Dictionary = before["pieces"][n - 1 - k]
		if TrackEditorModel.is_curve(b):
			mirrored = mirrored and a["t"] != b["t"] and near(float(a["bank"]), -float(b["bank"]))
		else:
			mirrored = mirrored and a["t"] == b["t"]
	check(mirrored, "curves turn the other way and bank the other way")
	var pts := m.points()
	var same := true
	for x in [50.0, 100.0, 250.0, 299.0, 301.0, 420.0, 600.0]:
		same = same and near(HeightSpline.height(pts, length - x), HeightSpline.height(pts0, x), 0.01)
	check(same, "the same heights at the same places")
	check(pts.size() == pts0.size() and HeightSpline.is_wall(pts, pts.size() - 4), "the wall stays a wall (%s)" % [pts])
	var same_lap := func() -> bool:
		var ok: bool = JSON.stringify(m.pieces) == JSON.stringify(before["pieces"]) and m.start_dir.is_equal_approx(Vector2(0, -1)) and m.heights.size() == before["heights"].size()
		for i in mini(m.heights.size(), before["heights"].size()):
			var a: Array = m.heights[i]
			var b: Array = before["heights"][i]
			ok = ok and near(float(a[0]), float(b[0])) and near(float(a[1]), float(b[1])) and a[2] == b[2] and int(a[3]) == int(b[3])
		return ok
	m.reverse()
	check(same_lap.call(), "reversed twice: the lap as before")
	m.reverse()
	m.undo()
	check(same_lap.call(), "Esc undoes the reversing")
	check(not TrackEditorModel.new().reverse(), "not an open lap")
	# a curve and its run-out are marked together the other way round too
	var mr := TrackEditorModel.new()
	mr.set_start(Vector2.ZERO)
	mr.place_first(Vector2(0, -100))
	mr.place(mr.group_for(TrackEditorModel.curve("R", 90, 55)))
	mr.place(mr.group_for(TrackEditorModel.curve("L", 90, 55)))
	mr.pieces.reverse()        # (as reverse() orders them)
	check(mr.pieces[1].get("auto", false) and mr.group_range(0) == Vector2i(0, 1) and mr.group_range(1) == Vector2i(0, 1)
		and mr.group_range(2) == Vector2i(2, 2), "run-out after its curve")


## Waves: one edge of the road lifted (or lowered) at a point, fading out
## as a cosine over 20 m each way; they go along with the pieces.
func test_track_waves() -> void:
	var m := _editor_oval()
	var flat := TrackPath.new(m.to_def("t"))
	check(m.add_wave(100.0, 1) == 0 and m.waves[0] == [100.0, 1, TrackEditorModel.WAVE_HEIGHT], "wave added")
	check(m.undo_height() and m.waves.is_empty(), "Esc takes it back")
	m.add_wave(100.0, 1)
	var p := TrackPath.new(m.to_def("t"))
	check(p.n == flat.n and p.closure_error < 0.5, "the lap as before")
	var edges := func(path: TrackPath, x: float) -> Array:
		var i := path._index_at_x(x)
		return [path.center[i] - path.right[i] * path.half_width[i], path.center[i] + path.right[i] * path.half_width[i]]
	for c in [[100.0, 1.0], [110.0, 0.5], [90.0, 0.5], [125.0, 0.0], [75.0, 0.0]]:
		var e0: Array = edges.call(flat, c[0])
		var e1: Array = edges.call(p, c[0])
		check(near(e1[1].y - e0[1].y, c[1], 0.02) and near(e1[0].y - e0[0].y, 0.0, 0.02),
			"right edge up %.1f m at %d m, left edge stays (%.3f / %.3f)" % [c[1], c[0], e1[1].y - e0[1].y, e1[0].y - e0[0].y])
		check(Vector2(e1[1].x, e1[1].z).distance_to(Vector2(e0[1].x, e0[1].z)) < 0.02, "the edge stays above its place at %d m" % c[0])
	var i100 := p._index_at_x(100.0)
	check(near(p.road_height(i100, p.half_width[i100] * (p.right[i100].dot(p.right_flat[i100]))), (edges.call(p, 100.0) as Array)[1].y, 0.02),
		"the road surface follows the edge")
	# a hollow; never 0 (over 0: the other way)
	check(m.set_wave(0, 100.0, -1.0) == 0, "hollow")
	var e2: Array = edges.call(TrackPath.new(m.to_def("t")), 100.0)
	check(near(e2[1].y - (edges.call(flat, 100.0) as Array)[1].y, -1.0, 0.02), "the right edge goes down")
	m.set_wave(0, 100.0, -0.5)
	m.set_wave(0, 100.0, 0.0)
	check(near(float(m.waves[0][2]), 0.5), "over 0 to the other side (%s)" % [m.waves[0]])
	m.set_wave(0, 100.0, 1.0)
	# saved and loaded
	var back := TrackEditorModel.from_dict(JSON.parse_string(JSON.stringify(m.to_dict("x"))))
	check(back.waves == m.waves and typeof(back.waves[0][1]) == TYPE_INT, "save / load (%s)" % [back.waves])
	check(m.to_def("x")["waves"] == m.waves, "in the track definition")
	# along with a moved stretch: on the straight after it, its distance to the end
	m = _editor_oval()
	m.add_wave(m.piece_x(4) + 100.0, -1)
	m.add_wave(m.piece_x(2) + 30.0, 1)          # on the moved stretch
	var into := float(m.waves[0][0]) - m.piece_x(2)
	m.move_block(1, 3, Vector2(0, 40))
	check(m.waves.size() == 2 and near(float(m.waves[0][0]), m.piece_x(2) + into), "a wave on the stretch goes along")
	check(near(float(m.waves[1][0]), m.piece_x(4) + 60.0, 0.5) and int(m.waves[1][1]) == -1, "a wave on the straight after it keeps its distance to the end (%s)" % [m.waves])
	# the start line moved, the lap reversed
	m = _editor_oval()
	m.add_wave(150.0, 1)
	m.move_start(0, 100.0)
	check(near(float(m.waves[0][0]), 50.0), "the start line moved: the wave stays where it is")
	var length := m.profile_length()
	m.reverse()
	check(near(float(m.waves[0][0]), length - 50.0) and int(m.waves[0][1]) == -1, "reversed: mirrored, on the other edge")
	# a cut: the waves in the gap go, Esc brings them back
	m = _editor_oval()
	m.add_wave(m.piece_x(3) + 20.0, 1)
	m.add_wave(m.piece_x(5) + 20.0, 1)
	m.cut(3, 3)
	check(m.waves.is_empty() and m._cut["waves"].size() == 1, "the wave in the gap goes, the one after it waits with the tail")
	m.undo()
	check(m.waves.size() == 2, "Esc after the cut: back")


## The start line dragged along the lap: only onto straights, which it
## splits; the straights it split before are one again; the height profile
## keeps its shape.
func test_editor_move_start() -> void:
	var m := _editor_oval()
	var n := m.pieces.size()
	var length := m.total_length()
	m.add_point(150.0, 14.0)
	m.add_point(400.0, 3.0)
	var old_pts := m.points()
	var lp := m.profile_length()
	var h100 := HeightSpline.height(old_pts, 100.0)
	check(m.start_spot(Vector2(0, -100)) == [0, 100.0], "spot on the start straight")
	check(m.start_spot(Vector2(0, -3)) == [0, 0.0], "near its start: its start")
	check(m.start_spot(Vector2(0, -245)) == [0, 240.0], "near its end: the last 10 m stay")
	check(m.start_spot(Vector2(300, 300)).is_empty(), "not beside the road")
	var c: Array = m.poses()[1]
	check(m.start_spot((c[0] as Vector2) + Vector2(20, -20)).is_empty() or m.start_spot((c[0] as Vector2) + Vector2(20, -20))[0] != 1, "not on a curve")
	check(not m.move_start(1, 0.0), "not onto a curve")
	check(m.move_start(0, 100.0), "moved")
	check(m.start.distance_to(Vector2(0, -100)) < 0.01 and m.start_dir.distance_to(Vector2(0, -1)) < 0.01, "start pose")
	check(_closes(m) and near(m.total_length(), length, 0.05), "the same lap")
	check(m.pieces[0]["t"] == "S" and near(float(m.pieces[0]["l"]), 150.0), "the straight split at the line")
	check(near(m.base, h100), "start height = the height there before")
	check(near(HeightSpline.height(m.points(), 50.0), 14.0) and near(HeightSpline.height(m.points(), 300.0), 3.0), "points stay on the road")
	check(near(HeightSpline.height(m.points(), lp - 100.0), old_pts[0][1]), "the old start is a point at the old start height")
	# back: the two halves are one straight again
	var back := m.start_spot(Vector2(0, 0))
	check(m.move_start(back[0], back[1]), "moved back")
	check(m.pieces.size() == n and m.start.distance_to(Vector2.ZERO) < 0.01 and near(float(m.pieces[0]["l"]), 250.0), "joined again (%d pieces)" % m.pieces.size())
	check(_closes(m), "still closed")
	check(m.heights.size() == 3 and near(float(m.heights[0][0]), 100.0) and near(float(m.heights[0][1]), h100) 		and near(m.base, float(old_pts[0][1])), "the old start point is the start again, the line before a point (%s)" % [m.heights])
	m.undo()
	check(m.start.distance_to(Vector2(0, -100)) < 0.01 and m.heights.size() == 3, "Esc undoes the start move")


## Several profile points moved together: distances and heights to each
## other stay; not past the next point, a wall's other point goes along.
func test_editor_move_points() -> void:
	var m := _editor_oval()
	m.heights = [[100.0, 8.0, false, 0], [130.0, 12.0, false, 0], [160.0, 10.0, false, 0], [300.0, 10.0, false, 0]]
	m._tidy_heights()
	var got := m.move_points([1, 2, 3], 20.0, 2.0)
	check(got == Vector2(20, 2), "moved by the offset (%s)" % got)
	var pts := m.points()
	check(near(pts[1][0], 120.0) and near(pts[2][0], 150.0) and near(pts[3][0], 180.0), "distances stay")
	check(near(pts[1][1], 10.0) and near(pts[2][1], 14.0) and near(pts[3][1], 12.0), "heights to each other stay")
	check(near(pts[4][0], 300.0) and near(pts[4][1], 10.0), "the point not moved stays")
	check(m.undo_height() and near(m.points()[1][0], 100.0), "Esc: one step back")
	# not past the next point
	got = m.move_points([1, 2, 3], 500.0, 0.0)
	pts = m.points()
	check(got.x > 0.0 and float(pts[3][0]) <= 300.0 - TrackEditorModel.MIN_POINT_GAP + 0.01, "stops before the next point (%s)" % [pts])
	check(near(float(pts[2][0]) - float(pts[1][0]), 30.0) and near(float(pts[3][0]) - float(pts[2][0]), 30.0), "distances stay at the stop")
	m.undo_height()
	# far up: no slope limit, only the height range
	got = m.move_points([2, 3], 0.0, 45.0)
	pts = m.points()
	check(got.y == 45.0, "as steep as it gets (%s)" % got)
	got = m.move_points([2, 3], 0.0, 500.0)
	check(got.y == TrackEditorModel.MAX_HEIGHT - 57.0, "up to MAX_HEIGHT (%s)" % got)
	check(near(float(m.points()[3][1]) - float(m.points()[2][1]), -2.0), "heights to each other stay at the top")
	# a wall: its other point goes along
	m = _editor_oval()
	m.heights = [[200.0, 15.0, false, 0], [200.0, 5.0, false, 1], [260.0, 5.0, false, 0]]
	m._tidy_heights()
	check(HeightSpline.is_wall(m.points(), 1), "a wall")
	m.move_points([1], 10.0, 0.0)
	pts = m.points()
	check(near(pts[1][0], 210.0) and near(pts[2][0], 210.0) and HeightSpline.is_wall(pts, 1), "the wall moves as a whole (%s)" % [pts])
	check(m.move_points([0, pts.size() - 1], 10.0, 0.0) == Vector2.ZERO, "start and end are not moved")
	# several marked points deleted at once (one undo step); a wall's other point stays as a plain one
	m = _editor_oval()
	m.heights = [[100.0, 8.0, false, 0], [130.0, 12.0, false, 0], [200.0, 15.0, false, 0], [200.0, 5.0, false, 1], [300.0, 9.0, false, 0]]
	m._tidy_heights()
	check(m.delete_points([1, 3, 0, 7]) and m.heights.size() == 3, "two marked points gone, start / end / out of range ignored (%s)" % [m.heights])
	pts = m.points()
	check(near(pts[1][0], 130.0) and near(pts[2][0], 200.0) and int(pts[2][3]) == 0 and not HeightSpline.is_wall(pts, 1),
		"the wall's other point is a plain point now")
	check(m.undo_height() and m.heights.size() == 5, "one Esc brings both back")
	check(not m.delete_points([0]), "nothing to delete: false")


## The height surface of the 3D height editor: profile x <-> plan, mouse
## rays onto it, clicks on the road.
func test_height_ribbon() -> void:
	var m := _editor_oval()
	var path := TrackPath.new(m.to_def("t"))
	var rb := HeightRibbon.new(path)
	check(near(rb.length, m.profile_length()), "ribbon length = profile length")
	var i := path.n / 3
	check(rb.plan_at(path.px[i]).distance_to(Vector2(path.center[i].x, path.center[i].z)) < 0.05, "plan_at follows the centre line")
	check(rb.plan_at(0.0).distance_to(rb.plan_at(rb.length)) < 0.05, "the lap closes")
	check(rb.plan_at(100.0).distance_to(Vector2(0, -100)) < 0.05, "start straight heads -z")
	check(rb.tangent_at(100.0).distance_to(Vector2(0, -1)) < 0.01, "tangent along the lap")
	# a ray across both long sides of the oval: the hint picks the side
	var from := Vector3(-60, 20, -100)
	var dir := Vector3(1, -0.05, 0).normalized()
	var near_side: Vector2 = rb.hit(from, dir, 110.0)
	check(near(near_side.x, 100.0, 0.05) and near(near_side.y, 17.0, 0.05), "ray hits the near side (%s)" % near_side)
	var far_x := 250.0 + 55.0 * PI * 0.5 + 60.0 + 55.0 * PI * 0.5 + 150.0
	var far_side: Vector2 = rb.hit(from, dir, far_x - 20.0)
	check(near(far_side.x, far_x, 0.1) and near(far_side.y, 20.0 - 230.0 * 0.05, 0.1), "hint on the far side: the far side (%s)" % far_side)
	# on a curve: the point the ray aims at comes back
	var x_c := 250.0 + 40.0
	var target := rb.point_at(x_c, 12.0)
	var eye := target + Vector3(30, 25, -40)
	var on_curve: Vector2 = rb.hit(eye, (target - eye).normalized(), x_c + 5.0)
	check(near(on_curve.x, x_c, 0.05) and near(on_curve.y, 12.0, 0.05), "ray onto a curve (%s)" % on_curve)
	# nothing within the window: the vertical plane at the hint
	var off: Variant = rb.hit(Vector3(-60, 20, -100), Vector3(1, 0, 0), 150.0, 10.0)
	check(off != null and near(off.x, 100.0, 0.05) and near(off.y, 20.0, 0.05), "outside the window: the plane at the hint (%s)" % [off])
	check(near(rb.lap_distance(5.0, rb.length - 5.0), 10.0), "distance across the start")
	# wall snap: WALL_SNAP near, 10 pixels' worth far away
	check(near(HeightRibbon.wall_snap(10.0, 60.0, 1000.0), TrackEditorModel.WALL_SNAP), "wall snap near")
	check(near(HeightRibbon.wall_snap(1000.0, 60.0, 1000.0), 10.0 * 2.0 * 1000.0 * tan(deg_to_rad(30.0)) / 1000.0), "wall snap far")


## VR screen sphere: the head moved inside it (6DOF) - the mouse ray runs
## from the eye through the pointer's spot on the sphere, and a world point
## on that ray comes back to the same screen point.
func test_editor_view_dome() -> void:
	var dome := Node3D.new()
	var cam := Camera3D.new()
	dome.transform = Transform3D(Basis(Vector3.UP, 0.7) * Basis(Vector3.RIGHT, -0.4), Vector3(5, 20, -3))
	cam.position = dome.position + Vector3(0.3, -0.1, 0.2)     # leaning aside
	var v := EditorView.new(cam, dome, 2.0, 0.05, Vector2(3200, 2200))
	for pos in [Vector2(1600, 1100), Vector2(900, 1500), Vector2(2800, 300)]:
		var r := v.ray(pos)
		var from: Vector3 = r[0]
		var dir: Vector3 = r[1]
		var through := (v.sphere_point(pos) - from).cross(dir).length()
		var back: Variant = v.to_screen(from + dir * 150.0)
		check(through < 1e-4 and back != null and (back as Vector2).distance_to(pos) < 0.05,
			"dome ray at %s: through the pointer (%.5f), back to %s" % [pos, through, back])
	check(v.to_screen(cam.position - dome.transform.basis.z * -50.0) == null, "behind: no screen point")
	dome.free()
	cam.free()


## A wall right on a sample (whole metres on a 400 m start straight: there
## 400 * (57 / 400) is 56.99999999999999, not 57 - TrackPath.sample_x) and
## one between samples: the step is built on the segment the height jumps
## on, not as a steep slope next to it.
func test_wall_on_sample() -> void:
	for wx in [57.0, 57.5, 120.0, 230.0]:
		for down in [true, false]:
			var m := TrackEditorModel.new()
			m.set_start(Vector2(0, 0))
			m.place_first(Vector2(0, -400))
			for pc in [TrackEditorModel.curve("R", 90, 55), TrackEditorModel.straight(60), TrackEditorModel.curve("R", 90, 55),
					TrackEditorModel.straight(400), TrackEditorModel.curve("R", 90, 55)]:
				m.place(m.group_for(pc))
			m.place(m.closing_group(), true)
			var hi := 12.5
			var lo := 6.0
			m.heights = [[wx - 30.0, hi if down else lo, false, 0], [wx, hi if down else lo, false, 0],
				[wx, lo if down else hi, false, 1], [wx + 40.0, lo if down else hi, false, 0]]
			m._tidy_heights()
			var p := TrackPath.new(m.to_def("t"))
			var steps := []
			for i in p.n:
				if p.step[i] == 1:
					steps.append(i)
			var ok := steps.size() == 1
			if ok:
				var i: int = steps[0]
				ok = absf(p.center[(i + 1) % p.n].y - p.center[i].y) > 5.0
			check(ok, "wall at x %.1f (%s): one step on the jump (%s)" % [wx, "down" if down else "up", steps])
			check(m.problems(p).filter(func(o): return o["kind"] == "steep").is_empty(), "wall at x %.1f (%s): not reported steep" % [wx, "down" if down else "up"])


## A wall down whose foot is above the ground, on it, below it (a cut) and
## one deep in a tunnel, on a whole metre (a sample) and between samples:
## every triangle of the built track that spans the drop stands upright (the
## tunnel / cut pieces drew it as a slope), and right at the wall's place
## the mesh reaches both its points - the road runs up to the wall at the
## top's height (it ended a sample early) and on from the foot's (it ran on
## at the next sample's height: a ledge).
func test_wall_mesh_upright() -> void:
	for wall in [[13.0, 6.0], [13.0, 0.0], [13.0, -3.0], [-12.0, -25.0]]:
		for wx in [56.0, 56.5]:
			var top: float = wall[0]
			var foot: float = wall[1]
			var m := TrackEditorModel.new()
			m.set_start(Vector2(0, 0))
			m.place_first(Vector2(0, -400))
			for pc in [TrackEditorModel.curve("R", 90, 55), TrackEditorModel.straight(60), TrackEditorModel.curve("R", 90, 55),
					TrackEditorModel.straight(400), TrackEditorModel.curve("R", 90, 55)]:
				m.place(m.group_for(pc))
			m.place(m.closing_group(), true)
			m.heights = [[20.0, top, false, 0], [wx, top, false, 0], [wx, foot, false, 1], [110.0, foot + 2.0, false, 0]]
			m._tidy_heights()
			var p := TrackPath.new(m.to_def("t"))
			var node := TrackNode.new().build(p)
			var slanted := 0
			var at_top := false
			var at_foot := false
			for c in node.get_children():
				if not (c is MeshInstance3D) or (c as MeshInstance3D).mesh == null:
					continue
				var mesh := (c as MeshInstance3D).mesh
				for sf in mesh.get_surface_count():
					var v: PackedVector3Array = mesh.surface_get_arrays(sf)[Mesh.ARRAY_VERTEX]
					for t in range(0, v.size(), 3):
						var lo := minf(v[t].y, minf(v[t + 1].y, v[t + 2].y))
						var hi := maxf(v[t].y, maxf(v[t + 1].y, v[t + 2].y))
						var a0 := minf(-v[t].z, minf(-v[t + 1].z, -v[t + 2].z))     # along the start straight
						var a1 := maxf(-v[t].z, maxf(-v[t + 1].z, -v[t + 2].z))
						var nrm := (v[t + 1] - v[t]).cross(v[t + 2] - v[t])
						# spanning the drop and not upright (walls and side walls are)
						var spans: bool = lo < foot + 2.0 and hi > top - 2.0 and a1 > wx - 5.0 and a0 < wx + 5.0
						if spans and nrm.length() > 1e-6 and absf(nrm.normalized().y) > 0.05:
							slanted += 1
						for q in [v[t], v[t + 1], v[t + 2]]:
							if absf(-q.z - wx) < 0.02 and absf(q.x) < TrackPath.HALF_WIDTH:
								at_top = at_top or absf(q.y - top) < 0.05
								at_foot = at_foot or absf(q.y - foot) < 0.05
			var lip := p._lip_at_x(wx)
			var kind := "tunnel" if p.tunnel[lip] == 1 else ("cut" if p.cut[(lip + 1) % p.n] == 1 else "open")
			var what := "wall at %.1f, %.0f -> %.0f m (%s)" % [wx, top, foot, kind]
			check(slanted == 0, "%s: drop built upright (%d slanted triangles)" % [what, slanted])
			check(at_top and at_foot, "%s: the road meets the wall at the top (%s) and the foot (%s)" % [what, at_top, at_foot])
			node.free()


## An official track in the editor: its theme and boost values stay, and a
## league track gets no division of its own (the league table gives it);
## old crane marks and gap pieces are dropped.
func test_official_in_editor() -> void:
	check(TrackLibrary.TRACKS.size() == TrackLibrary.ORDER.size(), "all official tracks loaded (the league)")
	var raw := TrackLibrary.load_official("camel_back")
	raw["pieces"][2]["no_crane"] = true      # old flags
	raw["pieces"][3]["gap"] = true
	var m := TrackEditorModel.from_dict(raw)
	check(m.official == "camel_back" and not m.pieces[2].has("no_crane") and not m.pieces[3].has("gap"), "old crane mark and gap dropped")
	var def := m.to_def("Camel Back")
	check(int(def.get("theme", -1)) == 1 and int(def.get("boost", 0)) == 40 and not def.has("division"), "official: theme / boost kept, no division (%s)" % [def])


## Loop radius: set per loop in the editor (clamped, snapped, undo), carried
## into the definition; the built loop is 2 r high.
func test_loop_radius() -> void:
	var m := TrackEditorModel.new()
	m.set_start(Vector2(0, 0))
	m.place_first(Vector2(0, -100))
	m.place(m.loop_group(1))
	var k := -1
	for i in m.pieces.size():
		if m.pieces[i].get("t", "S") == "O":
			k = i
	check(k >= 0 and near(TrackEditorModel.loop_radius(m.pieces[k]), TrackPath.LOOP_RADIUS), "new loop has the default radius")
	check(not m.set_loop_radius(0, 15.0), "only a loop has a loop radius")
	check(m.set_loop_radius(k, 16.2) and near(m.pieces[k]["r"], 16.0), "radius snapped to %.1f m (%s)" % [TrackEditorModel.LOOP_R_STEP, m.pieces[k].get("r")])
	check(near(TrackEditorModel.piece_length(m.pieces[k]), TAU * 16.0), "loop length 2 pi r")
	check(m.set_loop_radius(k, 99.0) and near(m.pieces[k]["r"], TrackEditorModel.LOOP_R_MAX), "clamped to the largest radius")
	check(not m.set_loop_radius(k, 99.0), "no change: false")
	check(m.undo_height() and near(m.pieces[k]["r"], 16.0), "undo")
	check(m.set_loop_radius(k, TrackPath.LOOP_RADIUS) and not m.pieces[k].has("r"), "default radius not stored")
	# the definition: TrackPath builds the loop with it
	var def: Dictionary = TrackLibrary.get_def("example/loop_and_jump").duplicate(true)
	var lk := -1
	for i in (def["pieces"] as Array).size():
		if def["pieces"][i].get("t", "S") == "O":
			lk = i
			break
	def["pieces"][lk]["r"] = 17.0
	var p := TrackPath.new(def)
	var lp: Dictionary = p.pieces[lk]
	var top := -INF
	for i in range(int(lp["i0"]), int(lp["i1"])):
		top = maxf(top, p.center[i].y)
	check(near(top - float(lp["h0"]), 34.0, 0.3), "loop of radius 17 is 34 m high (%.2f)" % (top - float(lp["h0"])))
	check(p.closure_error < 0.5, "the lap stays closed (err %.2f)" % p.closure_error)


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
	# no slope limit: a point goes as high as asked
	m = _editor_oval()
	i = m.add_point(30.0, 60.0)
	check(near(m.points()[i][1], 60.0), "no slope limit when added (%.1f)" % m.points()[i][1])
	m.move_point(i, 30.0, 45.0)
	check(near(m.points()[i][1], 45.0), "nor when dragged")
	# a kink next to a kink, even where the curve gets steep (Mega Ramp)
	m = _editor_oval()
	m.move_point(0, 0.0, 12.0)
	m.heights = [[682.0, 12.0, true, 0], [734.0, 25.0, false, 0], [751.0, 13.0, false, 0], [793.0, 24.0, false, 0]]
	m._tidy_heights()
	check(m.toggle_corner(2) and m.toggle_corner(3) and m.points()[2][2] and m.points()[3][2], "kinks next to kinks")
	# walls: a point pulled hard under its neighbour snaps there
	m = _editor_oval()
	m.move_point(0, 0.0, 9.0)
	var count := 0
	var ia := m.add_point(100.0, 11.0)
	var ib := m.add_point(120.0, 11.0)
	m.move_point(ib, 102.0, 6.0)
	var pts := m.points()
	check(near(pts[ib][0], 102.0) and pts[ib][3] == 0, "68 deg to its neighbour: still a slope")
	m.move_point(ib, 100.5, 6.0)
	pts = m.points()
	check(near(pts[ib][0], 100.0) and near(pts[ib][1], 6.0) and pts[ib][3] == 1, "84 deg under its neighbour: a wall down")
	var ic := m.add_point(114.0, 6.0)
	var id := m.add_point(130.0, 30.0)
	check(near(m.points()[id][1], 30.0), "a point as steep as asked")
	m.move_point(id, 114.5, 10.0)
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
	m.move_point(ib, 101.0, 2.0)
	check(near(m.points()[ib][1], 0.0), "lower wall point 2 m up snaps to the ground")
	m.move_point(ib, 100.0, 3.5)
	check(near(m.points()[ib][1], TrackEditorModel.GROUND_SNAP), "3.5 m up: to 5 m (half of the snap is the border)")
	m.move_point(ib, 100.0, -2.0)
	check(near(m.points()[ib][1], 0.0), "2 m below snaps up to the ground")
	m.move_point(ib, 100.0, -4.0)
	check(near(m.points()[ib][1], -TrackEditorModel.GROUND_SNAP), "4 m below: to 5 m below")
	m.move_point(ib, 100.0, 6.0)
	check(near(m.points()[ib][1], 6.0), "6 m up stays")
	# the cursor keys step out of the snap to its other border
	m.move_point(ib, 100.0, 0.0)
	m.move_point(ib, 100.0, 0.5, true, TrackEditorModel.WALL_SNAP, true)
	check(near(m.points()[ib][1], TrackEditorModel.GROUND_SNAP), "key up from the ground: to 5 m")
	m.move_point(ib, 100.0, 4.5, true, TrackEditorModel.WALL_SNAP, true)
	check(near(m.points()[ib][1], 0.0), "key down from 5 m: to the ground")
	m.move_point(ib, 100.0, -0.5, true, TrackEditorModel.WALL_SNAP, true)
	check(near(m.points()[ib][1], -TrackEditorModel.GROUND_SNAP), "key down from the ground: to 5 m below")
	# ... and a wall point off its wall: right beside it, and no snap back
	m.move_point(ib, 100.0, 4.0)
	var wx := float(m.points()[ib][0])
	m.move_point(ib, wx + 1.0, float(m.points()[ib][1]), true, TrackEditorModel.WALL_SNAP, true)
	check(m.points()[ib][3] == 0 and near(m.points()[ib][0], wx + TrackEditorModel.MIN_POINT_GAP), "key off the wall: 2 m beside it (%s)" % [m.points()[ib]])
	m.move_point(ib, float(m.points()[ib][0]) - 1.0, float(m.points()[ib][1]), true, TrackEditorModel.WALL_SNAP, true)
	check(m.points()[ib][3] == 0, "a key step back does not snap it into the wall again")
	m.move_point(ib, 100.0, 0.0)
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
	m.move_point(id, 116.5, 5.0)      # 84 deg over its neighbour: a wall up
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
	for id in ["camel_back", "example/grand_tour", "stone_hopper"]:
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


## Road steeper than 70 deg is drawn black like a real wall.
func test_steep_road_black() -> void:
	var m := _editor_oval()
	m.heights = [[100.0, 6.0, true, 0], [104.0, 20.0, true, 0], [140.0, 20.0, false, 0]]    # 74 deg up
	m._tidy_heights()
	var p := TrackPath.new(m.to_def("t"))
	var node := TrackNode.new().build(p)
	var black := 0
	for i in range(p._index_at_x(100.0), p._index_at_x(104.0)):
		if node._road_color(i) == Palette.JUMP_WALL:
			black += 1
	check(black >= 3, "the 74 deg ramp is black (%d samples)" % black)
	check(node._road_color(p._index_at_x(120.0)) != Palette.JUMP_WALL and node._road_color(p._index_at_x(300.0)) != Palette.JUMP_WALL,
		"the flat road is not")
	node.free()
	# 63 deg: still road coloured
	m.heights = [[100.0, 6.0, true, 0], [107.0, 20.0, true, 0], [140.0, 20.0, false, 0]]
	m._tidy_heights()
	p = TrackPath.new(m.to_def("t"))
	node = TrackNode.new().build(p)
	black = 0
	for i in p.n:
		if node._road_color(i) == Palette.JUMP_WALL:
			black += 1
	check(black == 0, "63 deg: road (%d black)" % black)
	node.free()


## The upper point of a wall takes the lower (yellow) one along; the lower
## one only goes up and down, or off the wall - also when the upper one was
## the snapped one (a wall up).
func test_wall_point_roles() -> void:
	var m := _editor_oval()
	m.move_point(0, 0.0, 9.0)
	m.add_point(100.0, 6.0)
	var up := m.add_point(130.0, 30.0)
	m.move_point(up, 100.0, 20.0)
	var pts := m.points()
	check(HeightSpline.is_wall(pts, 1) and near(pts[1][1], 6.0) and near(pts[2][1], 20.0), "a wall up (%s)" % [pts])
	m.move_point(2, 110.0, 22.0)
	pts = m.points()
	check(near(pts[1][0], 110.0) and near(pts[2][0], 110.0) and near(pts[2][1], 22.0), "the upper point takes the yellow one along")
	m.move_point(1, 113.0, 8.0)
	pts = m.points()
	check(near(pts[1][0], 110.0) and near(pts[2][0], 110.0) and near(pts[1][1], 8.0), "the yellow point: only up and down")
	m.move_point(1, 110.0, 40.0)
	check(near(m.points()[1][1], 21.0), "at least 1 m below the upper one")
	m.move_point(2, 110.0, 5.0)
	check(near(m.points()[2][1], 22.0), "the upper one at least 1 m above the yellow one")
	m.move_point(1, 100.0, 8.0)
	pts = m.points()
	check(near(pts[1][0], 100.0) and near(pts[2][0], 110.0) and near(pts[2][1], 22.0) and int(pts[1][3]) == 0 and int(pts[2][3]) == 0
		and not HeightSpline.is_wall(pts, 1), "the yellow one pulled off: the upper one stays, no wall (%s)" % [pts])
	# a low wall: the ground snap does not lift the yellow point over the top
	m = _editor_oval()
	m.move_point(0, 0.0, 9.0)
	m.add_point(100.0, 4.0)
	var lw := m.add_point(110.0, 4.0)
	m.move_point(lw, 100.0, 0.0)
	m.move_point(lw, 100.0, 3.0)
	check(near(m.points()[lw][1], 0.0), "under a 4 m top: the yellow point stays on the ground (%s)" % [m.points()[lw]])


## A hole between a black drop and a black rise (steeper than 70 deg): one
## jump - the crane puts the car down JUMP_RUNUP before the drop (the
## take-off), never in the hole or on a wall, however wide the hole is.
func test_crane_before_black_walls() -> void:
	for wide in [false, true]:
		var x_up := 540.0 if wide else 340.0
		var m := _editor_oval()
		m.move_point(0, 0.0, 20.0)
		m.heights = [[300.0, 20.0, true, 0], [304.0, 5.0, true, 0], [x_up, 5.0, true, 0], [x_up + 4.0, 20.0, true, 0]]
		m._tidy_heights()
		var p := TrackPath.new(m.to_def("t"))
		var walls := p.wall_jumps()
		check(walls.size() == 1, "drop and rise: one jump (%s)" % [walls])
		var s_drop := p.s_arr[p._index_at_x(300.0)]
		var ok := true
		for x in [290.0, 302.0, 320.0, x_up - 10.0, x_up + 2.0]:
			var rs := p.recovery_s(p.s_arr[p._index_at_x(x)])
			ok = ok and fposmod(s_drop - rs, p.total_length) >= TrackPath.JUMP_RUNUP - 0.5 and not p.wall_steep(p.index_at_s(rs))
		check(ok, "off before / in the %s hole: put down 200 m before the drop" % ("wide" if wide else "narrow"))
		var after := p.s_arr[p._index_at_x(x_up + 60.0)]
		check(near(p.recovery_s(after), after, 0.5), "after the rise: right there")


## Jump assist: only in the last 50 m before a take-off; the front wheels the
## way the road goes, then (within 1 deg) straight as long as it is held.
func test_jump_align() -> void:
	var m := _editor_oval()
	m.move_point(0, 0.0, 20.0)
	m.heights = [[300.0, 20.0, true, 0], [304.0, 5.0, true, 0], [340.0, 5.0, true, 0], [344.0, 20.0, true, 0]]
	m._tidy_heights()
	var p := TrackPath.new(m.to_def("t"))
	var ja := JumpAlign.new(p)
	var s_off := p.s_arr[p._index_at_x(300.0)]
	check(ja.in_zone(s_off - 30.0) and not ja.in_zone(s_off - 60.0) and not ja.in_zone(s_off + 5.0), "zone: the last 50 m before the take-off")
	var road := Vector3(0, 0, -1)
	var car_fwd := road.rotated(Vector3.UP, deg_to_rad(-20.0))      # turned 20 deg to the right
	var lock := deg_to_rad(32.0)
	var drive := {"steer": 0.7, "throttle": 1.0, "brake": 0.0, "boost": false, "direct": false}
	check(ja.apply(drive, true, s_off - 60.0, car_fwd, road, lock)["steer"] == 0.7 and ja.mode == "", "outside the zone: no effect")
	check(ja.apply(drive, false, s_off - 30.0, car_fwd, road, lock)["steer"] == 0.7, "not held: no effect")
	var out := ja.apply(drive, true, s_off - 30.0, car_fwd, road, lock)
	check(ja.mode == "align" and near(out["steer"], -20.0 / 32.0, 0.01) and out["direct"] and out["throttle"] == 1.0,
		"turned right: wheels 20 deg to the left, the road's way (%.3f)" % out["steer"])
	out = ja.apply(drive, true, s_off - 25.0, road.rotated(Vector3.UP, deg_to_rad(0.5)), road, lock)
	check(ja.mode == "straight" and out["steer"] == 0.0, "within 1 deg: straight")
	out = ja.apply(drive, true, s_off - 20.0, car_fwd, road, lock)
	check(ja.mode == "straight" and out["steer"] == 0.0, "held: stays straight")
	ja.apply(drive, false, s_off - 15.0, car_fwd, road, lock)
	out = ja.apply(drive, true, s_off - 10.0, car_fwd, road, lock)
	check(ja.mode == "align", "pressed again: aligns again")


## Parachute: a 900 kg car (a point mass here) fired off at 25 m/s; the
## canopy needs its 50 m through the air, then the car sinks at about
## 6.4 m/s; a slack line pulls nothing, a cut one neither.
func test_parachute() -> void:
	var m := 900.0
	var dt := 1.0 / 120.0
	var car_pos := Vector3(0, 200, 0)
	var car_vel := Vector3(0, 0, -25.0)
	var ps := ParachuteSim.new(car_pos, car_vel)
	check(ps.step(dt, car_pos, car_vel) == Vector3.ZERO, "fired: the line is slack")
	var pull_at_10 := -1.0
	var max_pull := 0.0
	var t := 0.0
	var stable := true
	while t < 30.0:
		var f := ps.step(dt, car_pos, car_vel)
		car_vel += (f / m + Vector3.DOWN * 9.81) * dt
		car_pos += car_vel * dt
		t += dt
		max_pull = maxf(max_pull, f.length())
		if pull_at_10 < 0.0 and ps.dist >= 10.0:
			pull_at_10 = f.length()
		stable = stable and is_finite(car_vel.length()) and car_vel.length() < 200.0
	check(stable, "the simulation stays stable")
	check(pull_at_10 < 0.2 * m * 9.81, "after 10 m hardly any pull (%.0f N)" % pull_at_10)
	check(ps.opening() == 1.0, "fully open after 50 m")
	check(near(-car_vel.y, ParachuteSim.terminal_speed(m), 0.3) and -car_vel.y < 7.0,
		"sinks at %.2f m/s (%.2f expected), below the landing damage" % [-car_vel.y, ParachuteSim.terminal_speed(m)])
	check(Vector2(car_vel.x, car_vel.z).length() < 1.0, "the forward speed is gone (%.2f)" % Vector2(car_vel.x, car_vel.z).length())
	check(max_pull < 8.0 * m * 9.81, "opening shock below 8 g (%.1f g)" % (max_pull / (m * 9.81)))
	ps.cut = true
	check(ps.step(dt, car_pos, car_vel) == Vector3.ZERO, "cut: no pull")
	# when the AI fires it: a drop that would land too hard (9.5 m/s)
	check(not ParachuteSim.needed(3.0, 0.0, 9.5), "AI: 3 m drop - no parachute")
	check(ParachuteSim.needed(20.0, 0.0, 9.5), "AI: 20 m drop - parachute")
	check(ParachuteSim.needed(2.0, -10.0, 9.5), "AI: already falling fast - parachute")
	check(ParachuteSim.needed(4.0, 6.0, 9.5), "AI: still flying up, then 4 m down - parachute")


## Road down on the ground: the ground is left open under it (no flicker);
## between two wall feet on the ground (a pit, also a wide one) the ground
## is the floor and no road is drawn.
func test_road_on_ground() -> void:
	# a wall down to the ground and, 150 m on, a wall up from the ground
	var m := _editor_oval()
	m.move_point(0, 0.0, 20.0)
	m.heights = [[100.0, 20.0, false, 0], [100.0, 0.0, false, 1], [250.0, 0.0, false, -1], [250.0, 20.0, false, 0]]
	m._tidy_heights()
	var p := TrackPath.new(m.to_def("t"))
	var i := p._index_at_x(170.0)
	check(p.ground_floor[i] == 1, "between two wall feet on the ground (150 m apart): the ground")
	# the far wall going up from 2 m: road on the ground, the ground open under it
	m.heights = [[100.0, 20.0, false, 0], [100.0, 0.0, false, 1], [200.0, 0.0, true, 0], [250.0, 2.0, false, -1], [250.0, 20.0, false, 0]]
	m._tidy_heights()
	p = TrackPath.new(m.to_def("t"))
	i = p._index_at_x(150.0)
	check(p.ground_floor[i] == 0 and p.ground_road[i] == 1 and p.cut[i] == 0, "road on the ground: drawn, the ground open")
	var c := Vector2(p.center[i].x, p.center[i].z)
	var inside := false
	for h in p.ground_holes():
		inside = inside or Geometry2D.is_point_in_polygon(c, h)
	check(inside, "a hole in the ground under it")
	check(p.ground_road[p._index_at_x(300.0)] == 0, "road up high: no hole")


## Banking held on into a straight: full up to the point, then the usual
## run-out; on the straight before a curve the same the other way; it goes
## along when the lap is reversed.
func test_bank_hold() -> void:
	var m := _editor_oval()
	var bank_at := func(path: TrackPath, x: float) -> float:
		return rad_to_deg(asin(clampf(-path.right[path._index_at_x(x)].y, -1.0, 1.0)))
	var x4 := m.piece_x(4)          # the long straight after the second curve (banked 30 deg)
	var before: float = bank_at.call(TrackPath.new(m.to_def("t")), x4 + 25.0)
	check(m.add_hold(x4 + 30.0) == [4, "out"] and near(float(m.pieces[4]["bank_out"]), 30.0), "hold point after the curve")
	var p := TrackPath.new(m.to_def("t"))
	check(absf(absf(bank_at.call(p, x4 + 25.0)) - 30.0) < 0.5 and absf(before) < 20.0,
		"full banking up to the point (%.1f, was %.1f)" % [bank_at.call(p, x4 + 25.0), before])
	check(absf(absf(bank_at.call(p, x4 + 50.0)) - 15.0) < 2.0, "half way down 20 m after it (%.1f)" % bank_at.call(p, x4 + 50.0))
	check(absf(bank_at.call(p, x4 + 75.0)) < 0.5, "flat 40 m after it")
	check(m.add_hold(x4 + 240.0) == [4, "in"] and near(float(m.pieces[4]["bank_in"]), 10.0), "near the curve after it: before that one")
	p = TrackPath.new(m.to_def("t"))
	check(absf(absf(bank_at.call(p, x4 + 242.0)) - 30.0) < 0.5, "full banking from the point on, before the curve")
	m.move_hold(4, "out", x4 + 60.0)
	check(near(float(m.pieces[4]["bank_out"]), 60.0) and near(m.hold_x(4, "out"), x4 + 60.0), "moved")
	check(m.hold_marks().size() == 2, "two points shown")
	check(m.delete_hold(4, "in") and not m.pieces[4].has("bank_in") and m.undo_height() and m.pieces[4].has("bank_in"), "deleted, Esc: back")
	# reversed: the hold after the curve is one before it now
	var n := m.pieces.size()
	m.reverse()
	var r: Dictionary = m.pieces[n - 1 - 4]
	check(near(float(r.get("bank_in", -1.0)), 60.0) and near(float(r.get("bank_out", -1.0)), 10.0), "reversed: out and in swapped (%s)" % [r])
	check(_closes(m), "the reversed lap closes")


## Crane drives: silent while standing, heard while the chain or the trolley
## runs; the tone climbs with the speed without a limit (Shepard-Risset).
func test_crane_motor_sound() -> void:
	var rms := func(x: PackedFloat32Array) -> float:
		var e := 0.0
		for v in x:
			e += v * v
		return sqrt(e / maxf(x.size(), 1))
	var m := CraneMotorSynth.new()
	check(rms.call(m.generate(1600)) < 1e-6, "standing: silent")
	m.hoist = 1.0
	m.generate(1600)
	var slow := m.generate(1600)
	m.hoist = 20.0
	m.generate(1600)
	var fast := m.generate(1600)
	check(rms.call(slow) > 0.02 and rms.call(fast) > rms.call(slow), "chain running: heard, louder when faster (%.3f, %.3f)" % [rms.call(slow), rms.call(fast)])
	check(CraneMotorSynth.pitch_of(CraneMotorSynth.HOIST, 200.0) > CraneMotorSynth.pitch_of(CraneMotorSynth.HOIST, 20.0) + 3.0,
		"the tone climbs on without a limit")
	# Shepard stack: the loudness of the partials is the same whatever the pitch
	var sum_at := func(p: float) -> float:
		var e := 0.0
		for k in range(-10, 10):
			e += CraneMotorSynth.bell(p - k)
		return e
	check(absf(sum_at.call(0.1) - sum_at.call(0.6)) < 1e-4 and absf(sum_at.call(3.3) - sum_at.call(0.3)) < 1e-4, "endless glissando: even loudness")
	m.hoist = 0.0
	m.trolley = 1.5
	m.generate(1600)
	check(rms.call(m.generate(1600)) > 0.02, "trolley running: heard")
	m.muted = true
	m.generate(1600)
	check(rms.call(m.generate(1600)) < 1e-6, "muted: silent")
	m.free()


## The engine sound: off until started, the starter turns it over, then it
## runs; stopped it dies away.
func test_engine_start_stop() -> void:
	var rms := func(x: PackedFloat32Array) -> float:
		var e := 0.0
		for v in x:
			e += v * v
		return sqrt(e / maxf(x.size(), 1))
	var e := EngineSynth.new()
	e.rpm = 0.3
	e.load = 0.5
	check(rms.call(e.generate(1600)) < 1e-6, "not started: silent")
	e.running = true
	e.generate(1600)
	var crank: float = rms.call(e.generate(1600))
	for i in 8:
		e.generate(1600)
	var run: float = rms.call(e.generate(1600))
	check(crank > 0.01 and run > crank, "starter heard, then the engine runs (%.3f, %.3f)" % [crank, run])
	e.running = false
	for i in 30:
		e.generate(1600)
	check(rms.call(e.generate(1600)) < run * 0.05, "stopped: died away")
	e.free()


## Wind: dipole flow noise, power ~ v^6 (+18 dB per doubled speed), its
## frequencies ~ v (Strouhal); silent standing still.
func test_wind_noise() -> void:
	var rms := func(x: PackedFloat32Array) -> float:
		var e := 0.0
		for v in x:
			e += v * v
		return sqrt(e / maxf(x.size(), 1))
	check(near(WindSynth.level(40.0) / WindSynth.level(20.0), 8.0), "amplitude ~ v^3")
	check(near(WindSynth.shedding_hz(40.0, 0.03), 2.0 * WindSynth.shedding_hz(20.0, 0.03)), "tones ~ v")
	var w := WindSynth.new()
	check(rms.call(w.generate(2205)) == 0.0, "standing: silent")
	var at := func(v: float) -> float:
		w.speed = v
		w.generate(22050)
		return rms.call(w.generate(22050))
	var r20: float = at.call(20.0)
	var r40: float = at.call(40.0)
	var db := 20.0 * log(r40 / r20) / log(10.0)
	check(db > 14.0 and db < 22.0, "doubled speed: about +18 dB (%.1f dB)" % db)
	w.free()


## Advisory speed signs: 150 m before the first jump of a combination, the
## AI's take-off speed rounded to 10 km/h / 5 mph; every figure drawn.
func test_speed_signs() -> void:
	var p := TrackPath.new(TrackLibrary.get_def("the_tower"))
	var sp := SpeedSigns.spots(p)
	check(sp.size() == 1, "the tower: one sign (%d)" % sp.size())
	var g: Array = AiProfile.jumps(p)[0]
	check(sp.size() == 1 and absf(p.delta_s(p.s_arr[g[0]], p.s_arr[sp[0][0]]) + SpeedSigns.SIGN_DIST) < 2.0, "150 m before the take-off")
	check(SpeedSigns.shown(32.8, true) == 120 and SpeedSigns.shown(32.8, false) == 75, "rounded: 120 km/h, 75 mph")
	var m := TrackPath.new(TrackLibrary.get_def("mega_ramp"))
	check(SpeedSigns.spots(m).size() == AiProfile.jumps(m).size() - 1, "mega ramp: the pit right after the first has none")
	var ok := true
	for d in 10:
		ok = ok and not SpeedSigns.figure_lines(d).is_empty()
	check(ok, "figures 0-9")
	var kit := MeshKit.new()
	SpeedSigns.plate(kit, Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK, 120)
	check(kit.verts.size() > 300, "plate built")


## Tyre squeal: friction-induced vibration per wheel - silent while
## gripping, heard when a loaded wheel slides; friction falls with the
## sliding speed (Stribeck), which lets the mode swing up by itself.
func test_tyre_squeal() -> void:
	var rms := func(x: PackedFloat32Array) -> float:
		var e := 0.0
		for v in x:
			e += v * v
		return sqrt(e / maxf(x.size(), 1))
	var q := TyreSquealSynth.new()
	q.load = PackedFloat32Array([2200, 2200, 2200, 2200])
	check(rms.call(q.generate(2205)) == 0.0, "gripping: silent")
	q.slide = PackedFloat32Array([1.5, 0, 0, 0])
	q.generate(2205)
	check(rms.call(q.generate(2205)) > 0.01, "one wheel sliding: squeals")
	q.load = PackedFloat32Array([0, 0, 0, 0])
	q.generate(2205)
	check(rms.call(q.generate(2205)) < 1e-6, "in the air: silent")
	check(TyreSquealSynth.mu(0.0) > TyreSquealSynth.mu(1.0) and TyreSquealSynth.mu(1.0) > TyreSquealSynth.mu(5.0), "friction falls with the sliding speed")
	q.free()
	# a sudden drop of the sliding speed (one physics frame) gives no burst
	# far above the squeal (it was clipped: crackling)
	var r := TyreSquealSynth.new()
	r.load = PackedFloat32Array([0, 0, 2200, 0])
	r.slide = PackedFloat32Array([0, 0, 8.0, 0])
	for k in 60:
		r.generate(367)
	r.slide = PackedFloat32Array([0, 0, 1.0, 0])
	var peak := 0.0
	for k in 6:
		for v in r.generate(367):
			peak = maxf(peak, absf(v))
	check(peak < 0.6, "slide 8 -> 1 m/s at once: no burst (peak %.2f)" % peak)
	r.free()


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
