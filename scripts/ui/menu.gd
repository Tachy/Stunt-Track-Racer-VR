class_name Menu
extends Node3D
## VR menu: a panel floating over a track backdrop. Navigation with the wheel
## (turn = select, gas = confirm, brake = back), mapped wheel buttons or the
## keyboard (arrows, Enter, Esc).

signal start_race(request: Dictionary)

const PX := Vector2i(1024, 768)
const WORLD := Vector2(2.0, 1.5)
const DIST := 2.2

var screen_name := "main"
var sel := 0
var items: Array = []
var panel: Panel3D
var base := Transform3D.IDENTITY
var _practice_track := 0
var _practice_opponent := true
var _showcase: Node3D
var _cal: Dictionary = {}
var _time := 0.0
var _pedals_shown := true
# online screen
var _online_track := 0
var _code := "AAAA"
var _code_pos := 0
var _online_msg := ""
var _online_room := ""
var _searching := false
const CODE_LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ"   # as the server's (no I/O)


func _init(start_screen := "main") -> void:
	screen_name = start_screen
	name = "Menu"


func _ready() -> void:
	var track_id := "first_flight"
	if GameState.has_league() and not GameState.league.season_finished():
		track_id = GameState.league.next_race()["track"]
	var path := TrackPath.new(TrackLibrary.get_def(track_id))
	add_child(TrackNode.new().build(path))
	EnvironmentBuilder.build(self, TrackLibrary.TRACKS[track_id]["theme"], path.bounds())

	# viewpoint: beside the start straight, slightly elevated
	var f := path.frame_at_s(20.0)
	var flat := Vector3(-f.basis.z.x, 0, -f.basis.z.z).normalized()
	var side := Vector3(f.basis.x.x, 0, f.basis.x.z).normalized()
	var eye := f.origin - side * 16.0 + Vector3(0, 2.0, 0) - flat * 6.0
	var look := (f.origin + flat * 40.0 - eye)
	look.y = 0.0
	base = Transform3D(Basis.looking_at(look.normalized(), Vector3.UP), eye)

	panel = Panel3D.new().setup(PX, WORLD)
	add_child(panel)
	panel.transform = base * Transform3D(Basis.IDENTITY, Vector3(0, -0.1, -DIST))

	_showcase = CarModel.new().build(Palette.PLAYER_BODY, false)
	add_child(_showcase)
	_showcase.transform = base * Transform3D(Basis.IDENTITY, Vector3(4.2, -1.4, -7.0))

	InputManager.menu_mode = true
	InputManager.capture_mode = false
	InputManager.nav.connect(_on_nav)
	InputManager.nav_side.connect(_on_side)
	InputManager.accept.connect(_on_accept)
	InputManager.back.connect(_on_back)
	InputManager.device_changed.connect(_refresh)
	Net.welcomed.connect(_on_net_change)
	Net.room_created.connect(_on_net_room)
	Net.matched.connect(_on_net_matched)
	Net.failed.connect(_on_net_failed)
	Net.disconnected.connect(_on_net_lost)
	XrManager.set_base(base)
	open(screen_name)


func _exit_tree() -> void:
	InputManager.capture_mode = false
	InputManager.nav.disconnect(_on_nav)
	InputManager.nav_side.disconnect(_on_side)
	InputManager.accept.disconnect(_on_accept)
	InputManager.back.disconnect(_on_back)
	InputManager.device_changed.disconnect(_refresh)
	Net.welcomed.disconnect(_on_net_change)
	Net.room_created.disconnect(_on_net_room)
	Net.matched.disconnect(_on_net_matched)
	Net.failed.disconnect(_on_net_failed)
	Net.disconnected.disconnect(_on_net_lost)


func _process(delta: float) -> void:
	_time += delta
	XrManager.set_base(base)
	if _showcase:
		_showcase.transform = base * Transform3D(Basis(Vector3.UP, _time * 0.4), Vector3(4.2, -1.4, -7.0))
	if screen_name == "calibrate":
		_calibration_step(delta)
		_refresh()
	elif screen_name == "online" and Engine.get_process_frames() % 30 == 0:
		_refresh()   # connection state, ping
	elif screen_name == "main" and InputManager.pedals_ready() != _pedals_shown:
		_pedals_shown = InputManager.pedals_ready()
		_refresh()


# --- screens -----------------------------------------------------------------------

func open(s: String) -> void:
	screen_name = s
	sel = 0
	if s == "calibrate":
		_cal = {"step": "wake", "t": 0.0, "hold": 0.0, "first": InputManager.snapshot_axes(), "moved": {}}
		InputManager.capture_mode = InputManager.device >= 0
	else:
		InputManager.capture_mode = false
	if s == "online":
		_online_msg = ""
		_online_room = ""
		_searching = false
		if Net.status == "offline":
			if not Net.connect_to(Settings.server_host, Settings.server_port, Settings.player_name, Settings.player_color):
				_online_msg = Lang.t("SERVER NOT FOUND")
	_refresh()


func _refresh() -> void:
	items = []
	var sc := panel.screen
	sc.clear()
	sc.frame(Rect2(0, 0, PX.x, PX.y), Palette.LIGHT_BLUE, 6)
	sc.text_centered(26, "STUNT TRACK RACER VR", Palette.YELLOW, 6.0)
	match screen_name:
		"main":
			_screen_main(sc)
		"league":
			_screen_league(sc)
		"practice":
			_screen_practice(sc)
		"settings":
			_screen_settings(sc)
		"calibrate":
			_screen_calibrate(sc)
		"result":
			_screen_result(sc)
		"online":
			_screen_online(sc)
	sel = clampi(sel, 0, maxi(items.size() - 1, 0))   # the item list can shrink
	_draw_items(sc)
	sc.text_centered(PX.y - 40, Lang.t("STEER=SELECT  GAS/ENTER=OK  BRAKE/ESC=BACK  F12=RECENTER VR"), Palette.ROAD_DARK, 2.4)
	sc.commit()


func _draw_items(sc: PixelScreen) -> void:
	if items.is_empty():
		return
	var y0 := PX.y - 90 - items.size() * 50
	for i in items.size():
		var it: Dictionary = items[i]
		var active := i == sel
		var col := Palette.WHITE if active else Palette.ROAD_DARK
		if active:
			sc.rect(Rect2(60, y0 + i * 50 - 8, PX.x - 120, 44), Palette.DARK_BLUE)
		sc.text(90, y0 + i * 50, ("> " if active else "  ") + str(it["label"]), col, 4.0)


func _screen_main(sc: PixelScreen) -> void:
	sc.text_centered(90, Lang.t("INSPIRED BY STUNT CAR RACER (1989)"), Palette.LIGHT_BLUE, 3.0)
	var dev := InputManager.current_device_name()
	sc.text_centered(140, Lang.t("INPUT: ") + dev.left(40), Palette.WHITE, 3.0)
	if InputManager.device >= 0 and not InputManager.calibrated:
		sc.text_centered(180, Lang.t("PLEASE CALIBRATE THE WHEEL FIRST!"), Palette.RED, 3.0)
	elif not InputManager.pedals_ready():
		sc.text_centered(180, Lang.t("PLEASE PRESS GAS AND BRAKE ONCE"), Palette.RED, 3.0)
	if XrManager.xr_active:
		sc.text_centered(220, Lang.t("VR MODE"), Palette.GREEN, 3.0)
	else:
		sc.text_centered(220, Lang.t("DESKTOP MODE"), Palette.YELLOW, 3.0)
	items = [
		{"label": Lang.t("LEAGUE"), "do": func(): open("league")},
		{"label": Lang.t("PRACTICE"), "do": func(): open("practice")},
		{"label": Lang.t("ONLINE"), "do": func(): open("online")},
		{"label": Lang.t("CALIBRATE WHEEL"), "do": func(): open("calibrate")},
		{"label": Lang.t("SETTINGS"), "do": func(): open("settings")},
		{"label": Lang.t("QUIT"), "do": func(): get_tree().quit()},
	]


func _screen_league(sc: PixelScreen) -> void:
	if not GameState.has_league():
		GameState.new_league()
	var lg: League = GameState.league
	if lg.season_finished():
		lg.finish_season()
		GameState.save_game()
	var div := lg.player_division()
	var title := Lang.t("SEASON %d  -  DIVISION %d") % [lg.season, div]
	if lg.super_league:
		title += "  (SUPER LEAGUE)"
	sc.text_centered(90, title, Palette.LIGHT_BLUE, 4.0)
	var y := 150
	for d in 4:
		var ids: Array = lg.standings(d)
		var col := Palette.WHITE if d == div - 1 else Palette.ROAD_DARK
		sc.text(60, y, "DIV %d" % (d + 1), Palette.YELLOW if d == div - 1 else Palette.ROAD_DARK, 2.6)
		var x := 190
		for id in ids:
			var nm := League.driver_name(id)
			var c := Palette.GREEN if id == League.PLAYER else col
			sc.text(x, y, nm.left(12), c, 2.6)
			sc.text_right(x + 255, y, str(lg.points[id]), c, 2.6)
			x += 275
		y += 40
	var race := lg.next_race()
	if not race.is_empty():
		sc.text_centered(330, Lang.t("RACE %d/4: %s VS %s") % [lg.race_index + 1,
			TrackLibrary.display_name(race["track"]), League.driver_name(race["opponent"])], Palette.WHITE, 3.0)
	if lg.holes > 0:
		sc.text_centered(370, Lang.t("HOLES IN THE FRAME: %d") % lg.holes, Palette.RED, 3.0)
	if lg.last_season_report != "":
		sc.text_centered(410, lg.last_season_report, Palette.YELLOW, 3.0)
	items = [
		{"label": Lang.t("START RACE"), "do": func(): start_race.emit(GameState.league_request())},
		{"label": Lang.t("NEW LEAGUE"), "do": _act_new_league},
		{"label": Lang.t("BACK"), "do": func(): open("main")},
	]


func _screen_practice(sc: PixelScreen) -> void:
	sc.text_centered(90, Lang.t("PRACTICE"), Palette.LIGHT_BLUE, 4.0)
	var id: String = _practice_ids()[_practice_track]
	sc.text_centered(160, "DIVISION %d" % TrackLibrary.division_of(id), Palette.WHITE, 3.0)
	items = [
		{"label": Lang.t("TRACK: ") + TrackLibrary.display_name(id), "side": _side_track},
		{"label": Lang.t("OPPONENT: ") + (Lang.t("YES") if _practice_opponent else Lang.t("NO")), "side": _side_opponent},
		{"label": "START", "do": _act_practice_start},
		{"label": Lang.t("BACK"), "do": func(): open("main")},
	]


func _screen_settings(sc: PixelScreen) -> void:
	sc.text_centered(90, Lang.t("SETTINGS"), Palette.LIGHT_BLUE, 4.0)
	sc.text_centered(140, Lang.t("VIEW TILT: SHARE OF THE CAR'S PITCH/ROLL IN THE VIEW"), Palette.ROAD_DARK, 2.0)
	items = [
		{"label": Lang.t("VIEW TILT: %d%%") % int(round(Settings.tilt_follow * 100.0)), "side": _side_tilt},
		{"label": Lang.t("WHEEL RANGE: %d DEG") % int(Settings.wheel_range_deg), "side": _side_range},
		{"label": Lang.t("MAX. STEERING ANGLE: %d DEG") % int(Settings.max_wheel_angle_deg), "side": _side_lock},
		{"label": Lang.t("SEAT HEIGHT: %+.2f M") % Settings.seat_height, "side": _side_seat},
		{"label": Lang.t("SPEEDO: ") + ("KMH" if Settings.speed_kmh else "MPH"), "side": _side_units},
		{"label": Lang.t("SHADOWS: ") + (Lang.t("ON") if Settings.shadows else Lang.t("OFF")), "side": _side_shadows},
		{"label": Lang.t("VOLUME: %d") % Settings.volume, "side": _side_volume},
		{"label": Lang.t("LANGUAGE: %s") % ("DEUTSCH" if Lang.current == "de" else "ENGLISH"), "side": _side_language},
		{"label": Lang.t("BACK"), "do": _act_settings_back},
	]


func _screen_result(sc: PixelScreen) -> void:
	var r: Dictionary = GameState.last_result
	var title := Lang.t("RESULT")
	var col := Palette.WHITE
	if r.get("wrecked", false):
		title = Lang.t("CAR WRECKED - RACE LOST")
		col = Palette.RED
	elif r.get("retired", false):
		title = Lang.t("RETIRED")
		col = Palette.RED
	elif r.get("won", false):
		title = Lang.t("YOU WIN!")
		col = Palette.GREEN
	else:
		title = Lang.t("YOU LOSE")
		col = Palette.RED
	sc.text_centered(100, title, col, 6.0)
	sc.text_centered(180, TrackLibrary.display_name(r.get("track", "first_flight")), Palette.LIGHT_BLUE, 4.0)
	sc.text_centered(240, Lang.t("YOUR BEST LAP: ") + Dashboard.fmt_time(r.get("player_best", -1.0)), Palette.WHITE, 3.0)
	if r.get("opponent_name", "") != "":
		sc.text_centered(280, "%s: %s" % [str(r["opponent_name"]).to_upper(), Dashboard.fmt_time(r.get("opp_best", -1.0))], Palette.WHITE, 3.0)
		sc.text_centered(320, Lang.t("FASTEST LAP: ") + (Lang.t("YOU") if r.get("player_fastest", false) else Lang.t("OPPONENT")), Palette.YELLOW, 3.0)
	if r.has("season_report"):
		sc.text_centered(380, str(r["season_report"]), Palette.YELLOW, 3.0)
	var is_league: bool = GameState.request.get("league", false)
	var next := "league" if is_league else ("online" if r.get("online", false) else "main")
	items = [
		{"label": Lang.t("CONTINUE"), "do": func(): open(next)},
	]


func _screen_online(sc: PixelScreen) -> void:
	sc.text_centered(90, Lang.t("ONLINE RACE (1 VS 1)"), Palette.LIGHT_BLUE, 4.0)
	var status := Lang.t("NOT CONNECTED")
	var col := Palette.RED
	if Net.status == "connecting":
		status = Lang.t("CONNECTING ...")
		col = Palette.YELLOW
	elif Net.is_online():
		status = Lang.t("CONNECTED, PING %d MS") % int(Net.rtt * 1000.0)
		col = Palette.GREEN
	sc.text_centered(140, "%s:%d  -  %s" % [Settings.server_host, Settings.server_port, status], col, 2.6)
	sc.text_centered(180, Lang.t("NAME: %s") % Settings.player_name.to_upper(), Palette.WHITE, 3.0)
	if _online_room != "":
		sc.text_centered(240, Lang.t("ROOM CODE: %s") % _online_room, Palette.YELLOW, 5.0)
		sc.text_centered(300, Lang.t("TELL YOUR OPPONENT THE CODE - WAITING ..."), Palette.WHITE, 2.6)
	elif _searching:
		sc.text_centered(260, Lang.t("SEARCHING FOR AN OPPONENT ..."), Palette.YELLOW, 3.0)
	if _online_msg != "":
		sc.text_centered(340, _online_msg, Palette.RED, 3.0)
	if _online_room != "" or _searching:
		items = [{"label": Lang.t("CANCEL"), "do": _act_online_cancel}]
		return
	var id: String = _practice_ids()[_online_track]
	var code := ""
	for i in 4:
		code += ("[%s]" if i == _code_pos else " %s ") % _code[i]
	items = [
		{"label": Lang.t("TRACK: ") + TrackLibrary.display_name(id), "side": _side_online_track},
		{"label": Lang.t("QUICK MATCH"), "do": func(): _act_online_join(NetCodec.JOIN_QUICK)},
		{"label": Lang.t("CREATE ROOM"), "do": func(): _act_online_join(NetCodec.JOIN_CREATE)},
		{"label": Lang.t("CODE:") + " " + code, "side": _side_code, "do": _act_code_next},
		{"label": Lang.t("JOIN ROOM"), "do": func(): _act_online_join(NetCodec.JOIN_CODE)},
		{"label": Lang.t("BACK"), "do": _act_online_back},
	]


# --- calibration -------------------------------------------------------------------

const CAL_TEXT := {
	"wake": "TURN THE WHEEL, PRESS BOTH PEDALS ONCE (OR ENTER)",
	"rest": "NOW RELEASE EVERYTHING AND KEEP STILL ...",
	"left": "TURN THE WHEEL FULLY LEFT AND HOLD",
	"right": "TURN THE WHEEL FULLY RIGHT AND HOLD",
	"center": "CENTRE THE WHEEL",
	"gas": "PRESS THE GAS PEDAL FULLY AND HOLD",
	"gas_release": "RELEASE THE GAS PEDAL",
	"brake": "PRESS THE BRAKE PEDAL FULLY AND HOLD",
	"brake_release": "RELEASE THE BRAKE PEDAL",
	"btn_boost": "PRESS THE BUTTON FOR BOOST",
	"btn_accept": "PRESS THE BUTTON FOR MENU OK (ENTER = NONE)",
	"btn_back": "PRESS THE BUTTON FOR BACK/PAUSE (ENTER = NONE)",
	"btn_recenter": "PRESS THE BUTTON FOR VR RECENTER (ENTER = NONE)",
	"done": "DONE! CALIBRATION SAVED.",
}
const CAL_ORDER := ["wake", "rest", "left", "right", "center", "gas", "gas_release", "brake", "brake_release",
	"btn_boost", "btn_accept", "btn_back", "btn_recenter", "done"]


func _screen_calibrate(sc: PixelScreen) -> void:
	sc.text_centered(90, Lang.t("CALIBRATE WHEEL"), Palette.LIGHT_BLUE, 4.0)
	if InputManager.device < 0:
		sc.text_centered(200, Lang.t("NO WHEEL / JOYPAD FOUND"), Palette.RED, 4.0)
		sc.text_centered(250, Lang.t("CHECK USB, THEN SEARCH AGAIN"), Palette.WHITE, 3.0)
		items = [
			{"label": Lang.t("SEARCH DEVICE"), "do": _act_find_device},
			{"label": Lang.t("BACK"), "do": func(): open("main")},
		]
		return
	sc.text_centered(140, InputManager.current_device_name().left(48), Palette.WHITE, 3.0)
	var step: String = _cal.get("step", "wake")
	sc.text_centered(200, Lang.t(CAL_TEXT.get(step, "")), Palette.YELLOW, 2.6)
	# live axis bars
	var y := 260
	for a in InputManager.AXES:
		var v := InputManager.raw_axis(a)
		var tag := ""
		if a == InputManager.steer_axis and _cal.has("steer_done"):
			tag = Lang.t("STEERING")
		if a == InputManager.gas_axis and _cal.has("gas_done"):
			tag += Lang.t(" THROTTLE")
		if a == InputManager.brake_axis and _cal.has("brake_done"):
			tag += Lang.t(" BRAKE")
		sc.text(80, y, Lang.t("AXIS %d") % a, Palette.WHITE, 2.0)
		var bar := Rect2(200, y - 2, 420, 16)
		sc.rect(bar, Palette.BLACK)
		var x := bar.position.x + (v + 1.0) * 0.5 * bar.size.x
		sc.rect(Rect2(bar.position.x + bar.size.x * 0.5 - 1, y - 2, 2, 16), Palette.ROAD_DARK)
		sc.rect(Rect2(x - 4, y - 2, 8, 16), Palette.GREEN if tag != "" else Palette.LIGHT_BLUE)
		sc.text(640, y, "%+.2f %s" % [v, tag], Palette.WHITE, 2.0)
		y += 26
	var pb := InputManager.pressed_button()
	sc.text(80, y + 6, Lang.t("BUTTON: ") + (str(pb) if pb >= 0 else "-"), Palette.WHITE, 2.0)
	if step == "done":
		items = [{"label": "OK", "do": func(): open("main")}]
	else:
		items = [{"label": Lang.t("CANCEL (ESC)"), "do": func(): open("main")}]


func _cal_next() -> void:
	var idx := CAL_ORDER.find(_cal["step"])
	_cal["step"] = CAL_ORDER[mini(idx + 1, CAL_ORDER.size() - 1)]
	_cal["t"] = 0.0
	_cal["hold"] = 0.0
	if _cal["step"] == "done":
		InputManager.calibrated = true
		InputManager.save_mapping()
		InputManager.capture_mode = false
		sel = 0
		Sfx.play("beep")
	else:
		Sfx.play("beep_low", -6.0)


func _calibration_step(dt: float) -> void:
	if InputManager.device < 0 or _cal.is_empty():
		return
	var im := InputManager
	_cal["t"] = float(_cal["t"]) + dt
	var step: String = _cal["step"]
	match step:
		"wake":
			# axes report 0 until first moved: wait for the wheel and both pedals
			var first: PackedFloat32Array = _cal["first"]
			var moved: Dictionary = _cal["moved"]
			for a in InputManager.AXES:
				if absf(im.raw_axis(a) - first[a]) > 0.3:
					moved[a] = true
			if moved.size() >= 3 and _cal["t"] > 1.0:
				_cal["last"] = im.snapshot_axes()
				_cal_next()
		"rest":
			var now := im.snapshot_axes()
			var last: PackedFloat32Array = _cal.get("last", now)
			var change := 0.0
			for a in InputManager.AXES:
				change = maxf(change, absf(now[a] - last[a]))
			_cal["last"] = now
			if _held(change < 0.02, dt) and float(_cal["hold"]) > 1.5:
				_cal["base"] = now
				_cal_next()
		"left":
			var a := im.moved_axis(_cal["base"], [], 0.4)
			if _held(a >= 0, dt):
				im.steer_axis = a
				im.steer_min = im.raw_axis(a)
				_cal_next()
		"right":
			var base: PackedFloat32Array = _cal["base"]
			var v := im.raw_axis(im.steer_axis)
			var opposite := signf(v - base[im.steer_axis]) != signf(im.steer_min - base[im.steer_axis]) and absf(v - base[im.steer_axis]) > 0.4
			if _held(opposite, dt):
				im.steer_max = v
				_cal["steer_done"] = true
				_cal_next()
		"center":
			var base: PackedFloat32Array = _cal["base"]
			if _held(absf(im.raw_axis(im.steer_axis) - base[im.steer_axis]) < 0.15, dt):
				_cal_next()
		"gas":
			var a := im.moved_axis(_cal["base"], [im.steer_axis], 0.4)
			if _held(a >= 0, dt):
				im.gas_axis = a
				im.gas_full = im.raw_axis(a)
				_cal["gas_done"] = true
				_cal_next()
		"gas_release":
			# the true rest value is only known once the pedal was moved
			if _held(absf(im.raw_axis(im.gas_axis) - im.gas_full) > 0.5, dt):
				im.gas_rest = im.raw_axis(im.gas_axis)
				_cal["base2"] = im.snapshot_axes()
				_cal_next()
		"brake":
			var a := im.moved_axis(_cal["base2"], [im.steer_axis], 0.4)
			if _held(a >= 0, dt):
				im.brake_axis = a
				im.brake_full = im.raw_axis(a)
				_cal["brake_done"] = true
				_cal_next()
		"brake_release":
			if _held(absf(im.raw_axis(im.brake_axis) - im.brake_full) > 0.5, dt):
				im.brake_rest = im.raw_axis(im.brake_axis)
				_cal["released"] = true
				_cal_next()
		"btn_boost", "btn_accept", "btn_back", "btn_recenter":
			var b := im.pressed_button()
			if not _cal.get("released", false):
				if b < 0:
					_cal["released"] = true
				return
			if b >= 0:
				im.set(step, b)
				_cal["released"] = false
				_cal_next()


func _held(cond: bool, dt: float) -> bool:
	if cond:
		_cal["hold"] = float(_cal["hold"]) + dt
	else:
		_cal["hold"] = 0.0
	return float(_cal["hold"]) > 0.8


# --- input -------------------------------------------------------------------------

func _on_nav(dir: int) -> void:
	if items.is_empty():
		return
	sel = wrapi(sel + dir, 0, items.size())
	Sfx.play("beep", -16.0, 1.5)
	_refresh()


func _on_side(dir: int) -> void:
	if items.is_empty():
		return
	var it: Dictionary = items[sel]
	if it.has("side"):
		it["side"].call(dir)
		Sfx.play("beep", -16.0, 1.2)
		_refresh()


func _on_accept() -> void:
	if screen_name == "calibrate" and InputManager.capture_mode:
		# Enter skips an optional button assignment
		var step: String = _cal.get("step", "")
		if step == "wake":
			# e.g. combined pedal axis: only two axes move
			_cal["last"] = InputManager.snapshot_axes()
			_cal_next()
			_refresh()
		elif step in ["btn_accept", "btn_back", "btn_recenter"]:
			InputManager.set(step, -1)
			_cal["released"] = false
			_cal_next()
			_refresh()
		return
	if items.is_empty():
		return
	var it: Dictionary = items[sel]
	Sfx.play("beep", -10.0)
	if it.has("do"):
		it["do"].call()
	elif it.has("side"):
		it["side"].call(1)
		_refresh()


func _on_back() -> void:
	match screen_name:
		"main":
			pass
		"settings":
			Settings.save_settings()
			open("main")
		"calibrate":
			InputManager.capture_mode = false
			InputManager.load_mapping()
			open("main")
		"result":
			_on_accept()
		"online":
			if _online_room != "" or _searching:
				_act_online_cancel()
			else:
				_act_online_back()
		_:
			open("main")


# --- item actions --------------------------------------------------------------------

func _act_new_league() -> void:
	GameState.new_league()
	_refresh()


func _act_practice_start() -> void:
	start_race.emit(GameState.practice_request(_practice_ids()[_practice_track], _practice_opponent))


func _practice_ids() -> Array:
	return TrackLibrary.ORDER + TrackLibrary.CUSTOM


func _act_online_join(mode: int) -> void:
	if not Net.is_online():
		_online_msg = Lang.t("NOT CONNECTED")
		if Net.status == "offline":
			Net.connect_to(Settings.server_host, Settings.server_port, Settings.player_name, Settings.player_color)
		_refresh()
		return
	_online_msg = ""
	_searching = mode != NetCodec.JOIN_CREATE
	Net.join(mode, _code, _practice_ids()[_online_track], GameState.league != null and GameState.league.super_league)
	_refresh()


func _act_online_cancel() -> void:
	Net.leave()
	_online_room = ""
	_searching = false
	_refresh()


func _act_code_next() -> void:
	_code_pos = (_code_pos + 1) % 4
	_refresh()


func _act_online_back() -> void:
	Net.disconnect_from()
	open("main")


func _side_online_track(d: int) -> void:
	_online_track = wrapi(_online_track + d, 0, _practice_ids().size())


func _side_code(d: int) -> void:
	var i := CODE_LETTERS.find(_code[_code_pos])
	var c := CODE_LETTERS[wrapi(i + d, 0, CODE_LETTERS.length())]
	_code = _code.substr(0, _code_pos) + c + _code.substr(_code_pos + 1)


func _on_net_change() -> void:
	if screen_name == "online":
		_refresh()


func _on_net_room(code: String) -> void:
	_online_room = code
	_searching = false
	_refresh()


func _on_net_matched(info: Dictionary) -> void:
	if screen_name == "online":
		start_race.emit(GameState.online_request(info))


func _on_net_failed(code: int) -> void:
	_searching = false
	_online_room = ""
	_online_msg = {1: Lang.t("ROOM NOT FOUND"), 2: Lang.t("ROOM IS FULL"), 3: Lang.t("SERVER VERSION DIFFERS - UPDATE THE GAME")}.get(code, "ERROR %d" % code)
	_refresh()


func _on_net_lost(_reason: String) -> void:
	_searching = false
	_online_room = ""
	_online_msg = Lang.t("CONNECTION LOST")
	if screen_name == "online":
		_refresh()


func _act_settings_back() -> void:
	Settings.save_settings()
	open("main")


func _act_find_device() -> void:
	InputManager.pick_device()
	open("calibrate")


func _side_track(d: int) -> void:
	_practice_track = wrapi(_practice_track + d, 0, _practice_ids().size())


func _side_opponent(_d: int) -> void:
	_practice_opponent = not _practice_opponent


func _side_tilt(d: int) -> void:
	Settings.tilt_follow = clampf(snappedf(Settings.tilt_follow + 0.1 * d, 0.1), 0.0, 1.0)


func _side_range(d: int) -> void:
	Settings.wheel_range_deg = clampf(Settings.wheel_range_deg + 90.0 * d, 270.0, 1080.0)


func _side_lock(d: int) -> void:
	Settings.max_wheel_angle_deg = clampf(Settings.max_wheel_angle_deg + 2.0 * d, 10.0, 45.0)


func _side_seat(d: int) -> void:
	Settings.seat_height = clampf(snappedf(Settings.seat_height + 0.05 * d, 0.05), -0.4, 0.4)


func _side_language(_d: int) -> void:
	Settings.language = "de" if Lang.current == "en" else "en"
	Lang.current = Settings.language


func _side_shadows(_d: int) -> void:
	Settings.shadows = not Settings.shadows
	get_tree().call_group("sun", "set", "shadow_enabled", Settings.shadows)


func _side_units(_d: int) -> void:
	Settings.speed_kmh = not Settings.speed_kmh


func _side_volume(d: int) -> void:
	Settings.volume = clampi(Settings.volume + d, 0, 10)
	Settings.apply_volume()
