extends Node
## Switches between the menu and races.
##
## Command line (after `--`):
##   --track=<id>        start a race directly (ids: see TrackLibrary.ORDER)
##   --opponent=<n>      opponent driver index 0..10 (default none)
##   --super             super league car/AI
##   --autopilot         the player car drives itself (testing)
##   --no-xr             force desktop mode
##   --quit-after=<sec>  quit after some seconds (testing)
##   --screenshot=<sec>[,<sec>...]  save screenshots after some seconds
##                       (auto.png; with several times auto_1.png, auto_2.png ...)
##   --menu=<screen>     open a menu screen (main, league, practice, settings, calibrate)
##   --chase             debug camera behind the car
##   --render-scale=<x>  3D render scale (benchmark VR-like pixel counts)
##   --vr-bench          render 2 off-screen Pimax-size eyes and log GPU time
##   --fps               log frame rate every second
##   --joydump           print joypad axes/buttons twice a second
##   --lang=<en|de>      UI language for this run (not saved)
##   --online=<host[:port]> quick match on that server (with --track=<id>)
##   --name=<name>       online player name for this run
##   --car-photos        save close-ups of the car model, then quit

var current: Node
var _args := {}
var _elapsed := 0.0
var _shots_taken := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _args.get("lang", "") in Lang.LANGUAGES:
		Lang.current = _args["lang"]
	if _args.has("render-scale"):
		# benchmark: render the 3D scene at a multiple of the window size
		get_viewport().scaling_3d_scale = float(_args["render-scale"])
		var vp := get_viewport()
		print("[Main] window %s, 3D render scale %.2f -> %s px" % [DisplayServer.window_get_size(), vp.scaling_3d_scale, Vector2(DisplayServer.window_get_size()) * vp.scaling_3d_scale])
	if _args.has("vr-bench"):
		add_child(VrBench.new())
	if _args.has("car-photos"):
		_swap(CarPhotos.new())   # debug: close-ups of the car model, then quit
	elif _args.has("online"):
		_start_online()
	elif _args.has("track"):
		var req := {"track": _args["track"], "opponent": int(_args.get("opponent", "-1")),
			"league": false, "super": _args.has("super"), "holes": 0}
		_start_race(req)
	else:
		show_menu(_args.get("menu", "main"))


func _process(delta: float) -> void:
	_elapsed += delta
	if _args.has("joydump") and fmod(_elapsed, 0.5) < delta:
		print("[Joy] live axes: %s  pedals_ready=%s gas=%.2f brake=%.2f" % [InputManager._live_axes, InputManager.pedals_ready(), InputManager.gas(), InputManager.brake()])
		for id in Input.get_connected_joypads():
			var axes := []
			for a in 10:
				axes.append("%+.2f" % Input.get_joy_axis(id, a as JoyAxis))
			var btns := []
			for b in 64:
				if Input.is_joy_button_pressed(id, b as JoyButton):
					btns.append(b)
			print("[Joy %d] %s | known=%s | axes %s | buttons %s" % [id, Input.get_joy_name(id), Input.is_joy_known(id), " ".join(axes), btns])
	if _args.has("screenshot"):
		var times: PackedStringArray = _args["screenshot"].split(",")
		if _shots_taken < times.size() and _elapsed >= float(times[_shots_taken]):
			_shots_taken += 1
			var file := "auto.png" if times.size() == 1 else "auto_%d.png" % _shots_taken
			XrManager.save_screenshot("user://screenshots/" + file)
	if _args.has("quit-after") and _elapsed >= float(_args["quit-after"]):
		_report_and_quit()


## Command line: connect, quick match, race (testing without the menu).
func _start_online() -> void:
	var nm: String = _args.get("name", Settings.player_name)
	Net.matched.connect(func(info: Dictionary): _start_race(GameState.online_request(info)))
	Net.welcomed.connect(func(): Net.join(NetCodec.JOIN_QUICK, "", _args.get("track", "first_flight"), _args.has("super")), CONNECT_ONE_SHOT)
	if not Net.connect_to(_args["online"], nm, Settings.player_color):
		push_error("[Main] cannot connect to %s" % _args["online"])
		get_tree().quit(1)


func _report_and_quit() -> void:
	if current is Race:
		var r: Race = current
		print("[Main] quit: state=%s laps=%d progress=%.1f crack=%.3f holes=%d boost=%d time=%.1f best=%s opp=%s" % [
			r.state, r.ptrack.laps_done(), r.ptrack.progress, r.car.damage.crack, r.car.damage.holes,
			r.car.boost_units, r.race_time, Dashboard.fmt_time(r.ptrack.best_lap),
			("%s laps=%d crack=%.2f best=%s" % [r.opp_state, r.opp_track.laps_done(), r.opp_car.damage.crack, Dashboard.fmt_time(r.opp_track.best_lap)]) if r.opp_car else "-"])
		print("[Main] wheel check: rolled on radius %.1f m vs driven on ground %.1f m (%.2f %%)" % [r.car.rolled_distance, r._ground_dist, 100.0 * (r.car.rolled_distance - r._ground_dist) / maxf(r._ground_dist, 1.0)])
	get_tree().quit()


func _swap(node: Node) -> void:
	if current:
		current.queue_free()
	current = node
	add_child(node)


func show_menu(screen: String) -> void:
	var m := Menu.new(screen)
	m.start_race.connect(_start_race)
	_swap(m)


func _start_race(req: Dictionary) -> void:
	GameState.request = req
	var r := Race.new(req)
	r.finished.connect(_on_race_finished)
	_swap(r)


func _on_race_finished(result: Dictionary) -> void:
	print("[Main] race finished: ", result)
	if _args.has("track") or _args.has("online"):
		_report_and_quit()
		return
	GameState.apply_result(result)
	show_menu("result")
