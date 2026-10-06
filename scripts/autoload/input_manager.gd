extends Node
## Steering wheel (Thrustmaster T150/TMX via USB, read through Godot's joypad
## API) plus keyboard fallback. Axis assignment comes from the in-game
## calibration and is stored in user://input.cfg.

signal nav(dir: int)        # -1 previous / +1 next
signal nav_side(dir: int)   # -1 left / +1 right
signal accept
signal back
signal device_changed

const PATH := "user://input.cfg"
const AXES := 10
const BUTTONS := 64
## Name hints in priority order; flight devices are skipped.
const WHEEL_HINTS := ["t150", "tmx", "t80", "t300", "t248", "t128", "wheel", "racing", "thrustmaster"]
const NOT_WHEEL := ["rudder", "t16000", "twcs", "throttle", "hotas", "stick"]
const NAV_ANGLE := 35.0
const NAV_REPEAT := 0.32

var device := -1
var device_name := ""
var calibrated := false

var steer_axis := 0
var steer_min := -1.0
var steer_max := 1.0
var gas_axis := -1
var gas_rest := -1.0
var gas_full := 1.0
var brake_axis := -1
var brake_rest := -1.0
var brake_full := 1.0
var btn_boost := -1
var btn_accept := -1
var btn_back := -1
var btn_recenter := -1

## True while menus are shown: pedals/wheel also navigate.
var menu_mode := true
## True during calibration: no navigation events.
var capture_mode := false

var _kb_steer := 0.0
var _nav_dir := 0
var _nav_timer := 0.0
var _gas_latched := false
var _brake_latched := false
var _btn_state := {}
## Axes that have reported a real value since start. Godot/SDL report 0 for
## an axis until it moves - a pedal resting at -1 would read as half pressed.
var _live_axes := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_mapping()
	Input.joy_connection_changed.connect(func(_id, _connected): pick_device())
	pick_device()


# --- device -----------------------------------------------------------------

func pick_device() -> void:
	var pads := Input.get_connected_joypads()
	var chosen := -1
	for id in pads:
		if device_name != "" and Input.get_joy_name(id) == device_name:
			chosen = id
	if chosen < 0:
		for hint in WHEEL_HINTS:
			for id in pads:
				var nm := Input.get_joy_name(id).to_lower()
				if nm.contains(hint) and not _is_flight_device(nm):
					chosen = id
					break
			if chosen >= 0:
				break
	if chosen < 0 and pads.size() > 0:
		chosen = pads[0]
	if chosen != device:
		device = chosen
		_live_axes.clear()
		if device >= 0:
			print("[Input] using joypad %d: %s" % [device, Input.get_joy_name(device)])
			if device_name != Input.get_joy_name(device):
				calibrated = false
		else:
			print("[Input] no joypad found - keyboard only")
		device_changed.emit()


static func _is_flight_device(lower_name: String) -> bool:
	for w in NOT_WHEEL:
		if lower_name.contains(w):
			return true
	return false


func cycle_device() -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		device = -1
		return
	var idx := pads.find(device)
	device = pads[(idx + 1) % pads.size()]
	_live_axes.clear()
	calibrated = false
	device_changed.emit()


func current_device_name() -> String:
	return Input.get_joy_name(device) if device >= 0 else "TASTATUR"


# --- raw access (also used by calibration) -----------------------------------

func raw_axis(axis: int) -> float:
	if device < 0 or axis < 0:
		return 0.0
	return Input.get_joy_axis(device, axis as JoyAxis)


func snapshot_axes() -> PackedFloat32Array:
	var a := PackedFloat32Array()
	for i in AXES:
		a.append(raw_axis(i))
	return a


## Axis with the largest deviation from baseline (excluding some), or -1.
func moved_axis(baseline: PackedFloat32Array, exclude: Array, threshold := 0.35) -> int:
	var best := -1
	var best_d := threshold
	for i in AXES:
		if i in exclude:
			continue
		var d := absf(raw_axis(i) - baseline[i])
		if d > best_d:
			best_d = d
			best = i
	return best


func pressed_button() -> int:
	if device < 0:
		return -1
	for b in BUTTONS:
		if Input.is_joy_button_pressed(device, b as JoyButton):
			return b
	return -1


func button(b: int) -> bool:
	return device >= 0 and b >= 0 and Input.is_joy_button_pressed(device, b as JoyButton)


# --- normalised controls -----------------------------------------------------

func wheel_norm() -> float:
	if device < 0 or not calibrated:
		return 0.0
	return InputMath.axis_norm(raw_axis(steer_axis), steer_min, steer_max)


## Physical wheel angle in degrees (for the animated in-car steering wheel).
func wheel_angle_deg() -> float:
	if device >= 0 and calibrated:
		return wheel_norm() * Settings.wheel_range_deg * 0.5
	return _kb_steer * Settings.wheel_range_deg * 0.5


## True once both pedals have sent real values (pressed once after start).
func pedals_ready() -> bool:
	if device < 0 or not calibrated:
		return true
	return axis_live(gas_axis) and axis_live(brake_axis)


func axis_live(axis: int) -> bool:
	return axis < 0 or _live_axes.has(axis)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion and event.device == device:
		_live_axes[event.axis] = true


func gas() -> float:
	if device < 0 or not calibrated or gas_axis < 0:
		return 0.0
	if not axis_live(gas_axis):
		return 0.0
	return InputMath.pedal_norm(raw_axis(gas_axis), gas_rest, gas_full)


func brake() -> float:
	if device < 0 or not calibrated or brake_axis < 0:
		return 0.0
	if not axis_live(brake_axis):
		return 0.0
	return InputMath.pedal_norm(raw_axis(brake_axis), brake_rest, brake_full)


func get_drive() -> Dictionary:
	var direct := false
	var steer := _kb_steer
	if device >= 0 and calibrated and absf(_kb_steer) < 0.01:
		# linear over the full wheel range: end stop = full road-wheel lock
		steer = wheel_norm()
		direct = true
	var throttle := maxf(gas(), 1.0 if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W) else 0.0)
	var brk := maxf(brake(), 1.0 if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S) else 0.0)
	var boost := button(btn_boost) or Input.is_key_pressed(KEY_SPACE)
	return {"steer": steer, "throttle": throttle, "brake": brk, "boost": boost, "direct": direct}


# --- per-frame ---------------------------------------------------------------

func _process(delta: float) -> void:
	var target := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		target -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		target += 1.0
	var rate := 2.5 if absf(target) > 0.0 else 4.0
	_kb_steer = move_toward(_kb_steer, target, rate * delta)

	if capture_mode:
		return
	_poll_buttons()
	if menu_mode and device >= 0 and calibrated:
		_wheel_nav(delta)
		var g := gas()
		if g > 0.6 and not _gas_latched:
			_gas_latched = true
			accept.emit()
		elif g < 0.3:
			_gas_latched = false
		var b := brake()
		if b > 0.6 and not _brake_latched:
			_brake_latched = true
			back.emit()
		elif b < 0.3:
			_brake_latched = false


func _wheel_nav(delta: float) -> void:
	var ang := wheel_angle_deg()
	var dir := 0
	if ang > NAV_ANGLE:
		dir = 1
	elif ang < -NAV_ANGLE:
		dir = -1
	if dir == 0:
		_nav_dir = 0
		return
	if dir != _nav_dir:
		_nav_dir = dir
		_nav_timer = NAV_REPEAT * 1.6
		nav.emit(dir)
		return
	_nav_timer -= delta
	if _nav_timer <= 0.0:
		_nav_timer = NAV_REPEAT
		nav.emit(dir)


func _poll_buttons() -> void:
	for pair in [[btn_accept, "accept"], [btn_back, "back"], [btn_recenter, "recenter"]]:
		var b: int = pair[0]
		if b < 0:
			continue
		var down := button(b)
		var was: bool = _btn_state.get(b, false)
		_btn_state[b] = down
		if down and not was:
			match pair[1]:
				"accept":
					if menu_mode:
						accept.emit()
				"back":
					back.emit()
				"recenter":
					XrManager.recenter()


func _unhandled_input(event: InputEvent) -> void:
	if capture_mode:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				back.emit()
			elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				accept.emit()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_UP:
			if menu_mode:
				nav.emit(-1)
		KEY_DOWN:
			if menu_mode:
				nav.emit(1)
		KEY_LEFT:
			if menu_mode:
				nav_side.emit(-1)
		KEY_RIGHT:
			if menu_mode:
				nav_side.emit(1)
		KEY_ENTER, KEY_KP_ENTER:
			accept.emit()
		KEY_ESCAPE, KEY_BACKSPACE:
			back.emit()


# --- persistence --------------------------------------------------------------

func save_mapping() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("device", "name", Input.get_joy_name(device) if device >= 0 else "")
	cfg.set_value("device", "calibrated", calibrated)
	for key in ["steer_axis", "steer_min", "steer_max", "gas_axis", "gas_rest", "gas_full",
			"brake_axis", "brake_rest", "brake_full", "btn_boost", "btn_accept", "btn_back", "btn_recenter"]:
		cfg.set_value("map", key, get(key))
	cfg.save(PATH)
	device_name = Input.get_joy_name(device) if device >= 0 else ""


func load_mapping() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	device_name = cfg.get_value("device", "name", "")
	calibrated = cfg.get_value("device", "calibrated", false)
	for key in cfg.get_section_keys("map"):
		set(key, cfg.get_value("map", key))
