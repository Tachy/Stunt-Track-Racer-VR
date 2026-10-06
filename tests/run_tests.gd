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
		"test_custom1_layout", "test_loop_geometry", "test_loop_view_rule",
		"test_league_track_features", "test_no_unintended_crossings", "test_legacy_save_ids", "test_translations",
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
	var b := CockpitMath.base_basis(car, 0.5)
	check(near(rad_to_deg(CockpitMath.pitch_of(b)), 10.0, 0.05), "pitch 20 -> 10 (got %f)" % rad_to_deg(CockpitMath.pitch_of(b)))
	check(near(CockpitMath.level_yaw(b), yaw, 1e-3), "yaw preserved")


func test_cockpit_half_roll() -> void:
	var car := Basis(Vector3.UP, -1.2) * Basis(Vector3.FORWARD, deg_to_rad(30.0))
	var b := CockpitMath.base_basis(car, 0.5)
	check(near(absf(rad_to_deg(CockpitMath.roll_of(b))), 15.0, 0.05), "roll 30 -> 15 (got %f)" % rad_to_deg(CockpitMath.roll_of(b)))


func test_cockpit_extremes() -> void:
	var car := Basis(Vector3.UP, 0.3) * Basis(Vector3.RIGHT, 0.4) * Basis(Vector3.FORWARD, 0.2)
	var b0 := CockpitMath.base_basis(car, 0.0)
	check(near(CockpitMath.pitch_of(b0), 0.0) and near(CockpitMath.roll_of(b0), 0.0), "tilt 0 is level")
	var b1 := CockpitMath.base_basis(car, 1.0)
	check(b1.is_equal_approx(car.orthonormalized()), "tilt 1 follows car")
	# nose straight up must not produce NaN
	var vertical := Basis(Vector3.RIGHT, PI * 0.5)
	var bv := CockpitMath.base_basis(vertical, 0.5, 1.0)
	check(not is_nan(bv.x.x), "vertical car no NaN")
	var xf := Transform3D(car, Vector3(5, 6, 7))
	var bt := CockpitMath.base_transform(xf, Vector3(0, 1, 0.3), 0.5)
	check(bt.origin.is_equal_approx(xf * Vector3(0, 1, 0.3)), "eye point at seat")


func test_recenter() -> void:
	var base := Transform3D(CockpitMath.base_basis(Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, 0.2), 0.5), Vector3(10, 5, -3))
	var head := Transform3D(Basis(Vector3.UP, 0.9) * Basis(Vector3.RIGHT, -0.15), Vector3(0.2, 1.1, 0.4))
	var off := CockpitMath.recenter_offset(head)
	var origin := CockpitMath.origin_transform(base, off)
	var cam := origin * head
	check(cam.origin.is_equal_approx(base.origin), "head at eye point after recenter")
	check(near(CockpitMath.level_yaw(cam.basis), CockpitMath.level_yaw(base.basis), 1e-3), "head yaw matches base yaw")
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


func test_loop_view_rule() -> void:
	check(near(CockpitMath.fold(deg_to_rad(60.0), 0.5), deg_to_rad(30.0)), "fold: below 90 deg follows half")
	check(near(CockpitMath.fold(deg_to_rad(90.0), 0.5), deg_to_rad(45.0)), "fold: 90 -> 45")
	check(near(CockpitMath.fold(deg_to_rad(135.0), 0.5), deg_to_rad(22.5)), "fold: 135 -> 22.5")
	check(near(CockpitMath.fold(deg_to_rad(180.0), 0.5), 0.0), "fold: upside down -> level")
	check(near(CockpitMath.fold(deg_to_rad(-120.0), 0.5), deg_to_rad(-30.0)), "fold: negative side")
	# drive through a full loop: view pitch follows the triangle, no jumps
	var yaw := 0.4
	var entry := Basis(Vector3.UP, yaw)
	var prev_yaw := yaw
	var last_dir := Vector3.ZERO
	var max_jump := 0.0
	var max_abs := 0.0
	for k in 361:
		var car := entry * Basis(Vector3.RIGHT, deg_to_rad(float(k)))
		var view := CockpitMath.view_basis(car, 0.5, prev_yaw)
		prev_yaw = CockpitMath.view_yaw(car, prev_yaw)
		var dir := -view.z
		if k > 0:
			max_jump = maxf(max_jump, rad_to_deg(dir.angle_to(last_dir)))
		last_dir = dir
		max_abs = maxf(max_abs, absf(rad_to_deg(CockpitMath.pitch_of(view))))
		if k == 180:
			check(near(CockpitMath.pitch_of(view), 0.0, 1e-2) and near(CockpitMath.roll_of(view), 0.0, 1e-2), "loop top: view level")
			check(near(angle_difference(CockpitMath.view_yaw(car, prev_yaw), yaw), 0.0, 1e-2), "loop top: heading = entry heading")
	check(max_jump < 2.0, "loop: no jump in view direction (max %.2f deg/step)" % max_jump)
	check(near(max_abs, 45.0, 0.6), "loop: view pitch within +-45 (max %.1f)" % max_abs)
	# roll-over: full roll, view roll folds back, no jumps
	prev_yaw = yaw
	max_jump = 0.0
	var last_up := Vector3.UP
	for k in 361:
		var car := entry * Basis(Vector3.FORWARD, deg_to_rad(float(k)))
		var view := CockpitMath.view_basis(car, 0.5, prev_yaw)
		prev_yaw = CockpitMath.view_yaw(car, prev_yaw)
		if k > 0:
			max_jump = maxf(max_jump, rad_to_deg(view.y.angle_to(last_up)))
		last_up = view.y
		if k == 180:
			check(near(CockpitMath.roll_of(view), 0.0, 1e-2), "roll-over: upside down -> level view")
	check(max_jump < 2.0, "roll-over: no jump (max %.2f deg/step)" % max_jump)


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
