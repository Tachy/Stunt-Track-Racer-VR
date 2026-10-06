class_name Race
extends Node3D
## One race: track, player car, optional opponent, crane start ("DROP START"),
## lap counting, falling off + crane recovery, damage, boost and the cockpit
## viewpoint for VR. The opponent is the same physical car (PlayerCar) as the
## player's, driven by an AiDriver instead of wheel and pedals.

signal finished(result: Dictionary)

const LAPS := 3
const START_S := 8.0
const START_LAT := 2.4
const HOLD_HEIGHT := 1.5
const END_DELAY := 4.5
const AI_CRANE_DELAY := 1.2
const AI_DROP_DELAY := 1.2

var req: Dictionary
var def: Dictionary
var path: TrackPath
var track: TrackNode
var tuning: CarTuning
var car: PlayerCar
var car_model: CarModel
var dashboard: Dashboard
var banner: Panel3D
var crane: Crane
var engine: EngineSynth
var ptrack: CarTracker

# opponent: identical physics, AI driver
var opp_car: PlayerCar
var opp_model: CarModel
var opp_track: CarTracker
var opp_ai: AiDriver
var opp_crane: Crane
var opp_engine: EngineSynth
var opp_driver := {}
var opp_state := "held"       # held, racing, falling, craned, finished, wrecked
var opp_state_time := 0.0
var _opp_slow_time := 0.0

var state := "hold"
var state_time := 0.0
var race_time := 0.0
var message := ""
var drop_at := 3.0
var opp_finished_first := false
var result := {}
var autopilot := false
var _chase := OS.get_cmdline_user_args().has("--chase")
var _overview := OS.get_cmdline_user_args().has("--overview")

var _fallback_yaw := 0.0
var _rng := RandomNumberGenerator.new()
var _pause_panel: Panel3D
var _pause_sel := 0
var _banner_text := ""
var _ap: AiDriver
var _ground_dist := 0.0   # debug: path distance driven with wheel 0 on the ground
var _accept_pressed := false

const PAUSE_ITEMS := ["CONTINUE", "RETIRE"]


func _init(request: Dictionary) -> void:
	req = request
	name = "Race"


func _ready() -> void:
	_rng.randomize()
	autopilot = OS.get_cmdline_user_args().has("--autopilot")
	def = TrackLibrary.get_def(req["track"])
	var super_league: bool = req.get("super", false)
	path = TrackPath.new(def)
	track = TrackNode.new().build(path)
	add_child(track)
	EnvironmentBuilder.build(self, def["theme"], path.bounds())

	tuning = CarTuning.super_league() if super_league else CarTuning.standard()
	tuning.max_steer_deg = Settings.max_wheel_angle_deg
	car = PlayerCar.new()
	car.name = "PlayerCar"
	car.setup(tuning, int(req.get("holes", 0)))
	add_child(car)
	car.boost_units = def["boost_super"] if super_league else def["boost"]
	car_model = CarModel.new().build(Palette.PLAYER_BODY, true)
	car.add_child(car_model)
	dashboard = Dashboard.new()
	car_model.dashboard_anchor.add_child(dashboard)
	banner = Panel3D.new().setup(Vector2i(512, 96), Vector2(0.8, 0.15))
	banner.position = Vector3(0, 1.05, -1.7)
	banner.visible = false
	car_model.add_child(banner)
	engine = EngineSynth.new().setup(false, -8.0)
	car.add_child(engine)
	car.landed.connect(_on_landed)
	car.impacted.connect(_on_impact)
	car.damage.wrecked.connect(_on_wrecked)
	car.damage.hole_added.connect(func(): Sfx.play("crash", 0.0, 0.8))

	crane = Crane.new()
	add_child(crane)

	car.verbose = true
	var profile := AiProfile.compute(path, super_league)
	var floors := AiProfile.floors(path, super_league)
	var opp_index: int = req.get("opponent", -1)
	var lat := 0.0
	var start_lat := minf(START_LAT, path.half_width[path.index_at_s(START_S)] * 0.5)
	if opp_index >= 0:
		lat = -start_lat
		opp_driver = Drivers.get_driver(opp_index)
		opp_car = PlayerCar.new()
		opp_car.name = "Opponent"
		var opp_tuning := CarTuning.super_league() if super_league else CarTuning.standard()
		opp_tuning.max_steer_deg = tuning.max_steer_deg
		opp_car.setup(opp_tuning, 0)
		add_child(opp_car)
		opp_car.boost_units = car.boost_units
		opp_model = CarModel.new().build(Color(opp_driver.get("color", "#2266dd")), false)
		opp_car.add_child(opp_model)
		opp_engine = EngineSynth.new().setup(true, -2.0)
		opp_car.add_child(opp_engine)
		opp_car.damage.wrecked.connect(_on_opponent_wrecked)
		opp_crane = Crane.new()
		add_child(opp_crane)
		var oxf := _hold_transform(START_S, start_lat, HOLD_HEIGHT)
		opp_car.teleport(oxf)
		opp_car.hold(true)
		opp_crane.hold(oxf)
		opp_track = CarTracker.new(path, opp_car, START_S)
		opp_ai = AiDriver.new(opp_track, profile, floors, opp_driver.get("skill", 0.85), opp_driver.get("flags", []))

	var xf := _hold_transform(START_S, lat, HOLD_HEIGHT)
	car.teleport(xf)
	car.hold(true)
	crane.hold(xf)
	ptrack = CarTracker.new(path, car, START_S)
	_reset_view_yaw()
	if autopilot:
		_ap = AiDriver.new(ptrack, profile, floors, 0.95, [])
	drop_at = 2.0 + _rng.randf_range(1.0, 3.0)
	state = "hold"
	state_time = 0.0

	InputManager.menu_mode = false
	InputManager.back.connect(_on_back)
	InputManager.accept.connect(_on_accept)
	InputManager.nav.connect(_on_nav)
	_update_view()
	print("[Race] %s vs %s (super=%s)" % [def["name"], Drivers.get_driver(opp_index)["name"] if opp_index >= 0 else "-", super_league])


func _exit_tree() -> void:
	get_tree().paused = false
	if InputManager.back.is_connected(_on_back):
		InputManager.back.disconnect(_on_back)
		InputManager.accept.disconnect(_on_accept)
		InputManager.nav.disconnect(_on_nav)
	XrManager.set_fade(0.0)


func _hold_transform(s: float, lat: float, height: float) -> Transform3D:
	var i := path.index_at_s(s)
	var f := path.frame_at_s(s)
	var flat := Vector3(-f.basis.z.x, 0, -f.basis.z.z).normalized()
	var basis := Basis.looking_at(flat, Vector3.UP)
	var pos := f.origin + path.right_flat[i] * lat
	pos.y = path.road_height(i, lat) + CarModel.RIDE_HEIGHT + height
	return Transform3D(basis, pos)


# --- simulation ----------------------------------------------------------------

func _physics_process(dt: float) -> void:
	car.input = _ap.compute(dt, opp_track) if autopilot else InputManager.get_drive()
	if opp_car:
		_update_opponent(dt)
	state_time += dt
	match state:
		"hold":
			if not autopilot and not InputManager.pedals_ready():
				# pedal values unknown until moved once - wait for them
				message = Lang.t("PRESS GAS + BRAKE")
				drop_at = maxf(drop_at, state_time + 2.0)
			elif state_time > 1.5:
				message = "DROP START"
			if state_time >= drop_at:
				_drop_start()
		"racing":
			race_time += dt
			if PlayerCar.debug and Engine.get_physics_frames() % 12 == 0:
				var i := ptrack.idx
				var in_pit := path.pit_mask.size() == path.n and (path.pit_mask[i] == 1 or path.pit_mask[(i + 40) % path.n] == 1)
				in_pit = in_pit or path.loop_mask[i] == 1 or path.loop_mask[(i + 60) % path.n] == 1
				in_pit = in_pit or path.road[(i + 30) % path.n] == 0 or path.road[i] == 0
				if in_pit or OS.get_cmdline_user_args().has("--trace-all"):
					print("[Trace] s=%.0f i=%d v=%.1f y=%.1f road=%.1f lat=%.1f grounded=%d up=%s steer=%.2f" % [ptrack.s, i, car.speed, car.global_position.y, path.center[i].y, ptrack.lateral(), car.grounded, car.global_transform.basis.y.snapped(Vector3.ONE * 0.01), car.steer_angle])
			if car.wheel_contact[0]:
				_ground_dist += car.linear_velocity.length() * dt
			ptrack.update_position()
			if ptrack.update_laps(race_time):
				_lap_completed()
			if not car.is_wrecked() and ptrack.check_off(dt):
				print("[Race] player off track at s=%.1f piece=%d %s" % [ptrack.s, path.piece_of[ptrack.idx], _piece_desc(path.piece_of[ptrack.idx])])
				state = "falling"
				state_time = 0.0
		"falling":
			race_time += dt
			ptrack.update_position()
			if state_time > 0.9 and state_time - dt <= 0.9:
				XrManager.fade_to(1.0, 0.3).tween_callback(_crane_reposition)
		"craned":
			race_time += dt
			if state_time > 0.8 and (car.input["throttle"] > 0.5 or _accept_pressed or (autopilot and state_time > 1.5)):
				car.hold(false)
				crane.release()
				Sfx.play("drop", -6.0)
				message = ""
				state = "racing"
				state_time = 0.0
		"finished", "wrecked":
			if state_time > END_DELAY and result.get("_sent", false) == false:
				result["_sent"] = true
				finished.emit(result)
	_accept_pressed = false


## The opponent runs the same crane / lap / off-track cycle as the player,
## just without fade and with automatic drops.
func _update_opponent(dt: float) -> void:
	opp_state_time += dt
	var idle := {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "boost": false}
	match opp_state:
		"held":
			opp_car.input = idle
		"racing", "finished":
			opp_track.update_position()
			opp_ai.race_time = race_time
			opp_car.input = opp_ai.compute(dt, ptrack)
			if opp_track.update_laps(race_time) and opp_state == "racing":
				_on_opponent_lap()
			_opp_slow_time = _opp_slow_time + dt if absf(opp_car.speed) < 0.5 else 0.0
			if opp_track.check_off(dt) or _opp_slow_time > 4.0:
				print("[Race] opponent off track at s=%.1f piece=%d %s" % [opp_track.s, path.piece_of[opp_track.idx], _piece_desc(path.piece_of[opp_track.idx])])
				_opp_slow_time = 0.0
				opp_state = "falling"
				opp_state_time = 0.0
		"falling":
			opp_track.update_position()
			opp_car.input = idle
			if opp_state_time > AI_CRANE_DELAY:
				var rs := path.recovery_s(opp_track.s)
				opp_track.move_to(rs)
				var xf := _hold_transform(rs, 0.0, HOLD_HEIGHT)
				opp_car.teleport(xf)
				opp_car.hold(true)
				opp_crane.hold(xf)
				opp_state = "craned"
				opp_state_time = 0.0
		"craned":
			opp_car.input = idle
			if opp_state_time > AI_DROP_DELAY:
				opp_car.hold(false)
				opp_crane.release()
				opp_state = "finished" if opp_ai.finished else "racing"
				opp_state_time = 0.0
		"wrecked":
			opp_car.input = {"steer": 0.0, "throttle": 0.0, "brake": 1.0, "boost": false}


func _drop_start() -> void:
	car.hold(false)
	crane.release()
	if opp_car:
		opp_car.hold(false)
		opp_crane.release()
		opp_state = "racing"
		opp_state_time = 0.0
	Sfx.play("drop")
	message = ""
	state = "racing"
	state_time = 0.0
	race_time = 0.0


func _lap_completed() -> void:
	print("[Race] lap %d: %s" % [ptrack.laps_done(), Dashboard.fmt_time(ptrack.last_lap)])
	if ptrack.laps_done() >= LAPS:
		_finish(false)
	else:
		Sfx.play("beep")
		if ptrack.laps_done() == LAPS - 1:
			_flash(Lang.t("FINAL LAP"))


func _crane_reposition() -> void:
	var rs := path.recovery_s(ptrack.s)
	ptrack.move_to(rs)
	var xf := _hold_transform(rs, 0.0, HOLD_HEIGHT)
	car.teleport(xf)
	car.hold(true)
	crane.hold(xf)
	_reset_view_yaw()
	Sfx.play("clank")
	state = "craned"
	state_time = 0.0
	message = Lang.t("GAS = DROP")
	_update_view()
	XrManager.fade_to(0.0, 0.35)


func _finish(retired: bool) -> void:
	if state == "finished":
		return
	state = "finished"
	state_time = 0.0
	car.controls_enabled = false
	var opp_best := opp_track.best_lap if opp_track else -1.0
	var best_lap := ptrack.best_lap
	var won := not opp_finished_first and not retired
	var fastest := best_lap > 0.0 and (opp_best < 0.0 or best_lap <= opp_best) and not retired
	if opp_car == null:
		won = not retired
	result = {
		"won": won, "player_fastest": fastest, "wrecked": false, "retired": retired,
		"holes": car.damage.holes, "player_best": best_lap, "opp_best": opp_best,
		"race_time": race_time, "track": req["track"],
		"opponent_name": opp_driver.get("name", ""),
	}
	if retired:
		message = Lang.t("RETIRED")
	else:
		message = Lang.t("YOU WIN!") if won else Lang.t("YOU LOSE")
		Sfx.play("beep_low" if not won else "beep", 0.0, 1.0 if won else 0.8)
	_flash(message)


func _on_wrecked() -> void:
	if state == "finished" or state == "wrecked":
		return
	state = "wrecked"
	state_time = 0.0
	car.controls_enabled = false
	Sfx.play("wreck")
	message = Lang.t("WRECKED!")
	_flash(Lang.t("CAR WRECKED!"))
	result = {
		"won": false, "player_fastest": false, "wrecked": true, "retired": false,
		"holes": car.damage.holes, "player_best": ptrack.best_lap, "opp_best": opp_track.best_lap if opp_track else -1.0,
		"race_time": race_time, "track": req["track"],
		"opponent_name": opp_driver.get("name", ""),
	}


func _on_opponent_lap() -> void:
	print("[Race] opponent lap %d: %s" % [opp_track.laps_done(), Dashboard.fmt_time(opp_track.last_lap)])
	if opp_track.laps_done() >= LAPS and not opp_ai.finished:
		opp_ai.finished = true
		opp_state = "finished"
		if state == "racing" or state == "falling" or state == "craned":
			opp_finished_first = true
			_flash(Lang.t("OPPONENT FINISHED"))


func _on_opponent_wrecked() -> void:
	opp_state = "wrecked"
	opp_car.controls_enabled = false
	print("[Race] opponent wrecked")
	if state == "racing" or state == "falling" or state == "craned":
		_flash(Lang.t("OPPONENT WRECKED!"))


func _on_landed(strength: float) -> void:
	if strength > 4.0:
		Sfx.play("thump", clampf(-14.0 + strength * 1.5, -14.0, 4.0), randf_range(0.9, 1.1))
	else:
		Sfx.play("bump", -12.0)


func _on_impact(strength: float) -> void:
	if PlayerCar.debug:
		print("[Trace] impact %.1f at s=%.0f piece=%d i=%d v=%.1f y=%.1f road=%.1f" % [strength, ptrack.s, path.piece_of[ptrack.idx], ptrack.idx, car.speed, car.global_position.y, path.center[ptrack.idx].y])
	Sfx.play("crash", clampf(-12.0 + strength, -12.0, 3.0))


func _flash(text: String) -> void:
	_banner_text = text
	banner.visible = true
	var sc := banner.screen
	sc.clear()
	sc.background = Palette.BLACK
	sc.frame(Rect2(0, 0, 512, 96), Palette.YELLOW, 4)
	sc.text_centered(30, text, Palette.YELLOW, 5.0)
	sc.commit()
	var t := create_tween()
	t.tween_interval(2.2)
	t.tween_callback(func():
		if _banner_text == text:
			banner.visible = false)


# --- per-frame visuals / VR viewpoint ----------------------------------------------

func _process(delta: float) -> void:
	_update_view()
	car_model.update_wheels(car.wheel_comp, car.steer_angle, car.wheel_spin, tuning.suspension_rest, delta)
	var wheel_deg := InputManager.wheel_angle_deg()
	if autopilot:
		wheel_deg = float(car.input["steer"]) * Settings.wheel_range_deg * 0.5
	car_model.set_steering_wheel_deg(wheel_deg)
	car_model.set_damage(car.damage.crack, car.damage.holes)

	var data := {
		"lap": mini(ptrack.laps_done() + 1, LAPS), "laps": LAPS,
		"boost": car.boost_units, "boosting": car.boosting,
		"lap_time": race_time - ptrack.lap_start if state != "hold" else 0.0,
		"best": ptrack.best_lap, "speed": car.speed, "message": message,
	}
	if opp_car:
		data["gap"] = ptrack.progress - opp_track.progress
		opp_model.update_wheels(opp_car.wheel_comp, opp_car.steer_angle, opp_car.wheel_spin, opp_car.tuning.suspension_rest, delta)
	dashboard.set_data(data)

	var airborne := car.grounded == 0
	engine.rpm = clampf(absf(car.speed) / tuning.top_speed, 0.0, 1.0) * 0.85 + float(car.input["throttle"]) * (0.35 if airborne or state == "hold" else 0.15)
	engine.load = float(car.input["throttle"])
	engine.boost = car.boosting
	engine.wind = clampf(car.linear_velocity.length() / 70.0, 0.0, 1.0) * 0.35
	engine.muted = car.is_wrecked()
	if opp_car:
		var oin: Dictionary = opp_car.input
		opp_engine.rpm = clampf(absf(opp_car.speed) / opp_car.tuning.top_speed, 0.0, 1.0) * 0.85 + float(oin.get("throttle", 0.0)) * 0.15
		opp_engine.load = float(oin.get("throttle", 0.0))
		opp_engine.boost = opp_car.boosting
		opp_engine.muted = opp_car.is_wrecked()


func _update_view() -> void:
	var xf := car.get_global_transform_interpolated()
	var eye := CarModel.SEAT_EYE
	if _chase:
		eye = Vector3(-2.6, 1.6, 6.5)   # debug: external view, behind-left
	if _overview:
		# debug: oblique bird's-eye view of the whole track
		var b := path.bounds()
		var size := maxf(b.size.x, b.size.z)
		var c := b.get_center()
		var cam_pos := Vector3(c.x, size * 0.75, c.z + size * 0.55)
		XrManager.set_base(Transform3D(Basis.looking_at(c - cam_pos, Vector3.UP), cam_pos))
		return
	# folding rule for pitch and roll (loops, roll-overs), continuous heading
	var view := CockpitMath.view_basis(xf.basis, Settings.tilt_follow, _fallback_yaw)
	_fallback_yaw = CockpitMath.view_yaw(xf.basis, _fallback_yaw)
	XrManager.set_base(Transform3D(view, xf * eye))


func _piece_desc(pi_: int) -> String:
	var pc: Dictionary = path.pieces[pi_]
	return "%s%s h%.0f->%.0f bank%.0f%s" % [pc["type"], (" l%.0f" % pc["length"]), pc["h0"], pc["h1"], rad_to_deg(pc["bank"]), " pit" if pc["no_crane"] else ""]


## Heading reference for the view after the car was placed (start, crane).
func _reset_view_yaw() -> void:
	_fallback_yaw = car.global_transform.basis.get_euler(EULER_ORDER_YXZ).y


# --- input / pause ----------------------------------------------------------------

func _on_accept() -> void:
	if _pause_panel and _pause_panel.visible:
		_pause_action()
		return
	_accept_pressed = true


func _on_back() -> void:
	if state == "finished" or state == "wrecked":
		return
	_set_paused(not get_tree().paused)


func _on_nav(dir: int) -> void:
	if _pause_panel and _pause_panel.visible:
		_pause_sel = wrapi(_pause_sel + dir, 0, PAUSE_ITEMS.size())
		_draw_pause()


func _set_paused(p: bool) -> void:
	get_tree().paused = p
	InputManager.menu_mode = p
	if _pause_panel == null:
		_pause_panel = Panel3D.new().setup(Vector2i(512, 256), Vector2(0.7, 0.35))
		_pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
		_pause_panel.position = Vector3(0, 1.0, -1.1)
		car_model.add_child(_pause_panel)
	_pause_panel.visible = p
	_pause_sel = 0
	_draw_pause()


func _draw_pause() -> void:
	var sc := _pause_panel.screen
	sc.clear()
	sc.frame(Rect2(0, 0, 512, 256), Palette.YELLOW, 4)
	sc.text_centered(24, Lang.t("PAUSE"), Palette.YELLOW, 6.0)
	for i in PAUSE_ITEMS.size():
		var col := Palette.WHITE if i == _pause_sel else Palette.ROAD_DARK
		var label: String = ("> " if i == _pause_sel else "  ") + Lang.t(PAUSE_ITEMS[i])
		sc.text(120, 110 + i * 56, label, col, 5.0)
	sc.commit()


func _pause_action() -> void:
	var item: String = PAUSE_ITEMS[_pause_sel]
	_set_paused(false)
	if item == "RETIRE":
		_finish(true)
		state_time = END_DELAY - 1.0
