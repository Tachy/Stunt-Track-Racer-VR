extends Node
## Owns the XR rig (XROrigin3D + XRCamera3D) for the whole game.
## Game code calls set_base() every frame with the desired eye pose
## (see CockpitMath); the HMD then moves in 6DOF relative to that pose.
## F12 recenters: the current head pose becomes the seat eye point.
## VR and desktop are separate start modes (no switching at runtime):
##   VR:      normal start, OpenXR + headset required
##   Desktop: start with --xr-mode off (OpenXR never initialised)

signal recentered

const AUTO_RECENTER_DELAY := 2.0

var origin: XROrigin3D
var camera: XRCamera3D
## Plain camera for desktop mode (the XRCamera3D would follow the HMD lying
## on the desk).
var desktop_camera: Camera3D
var interface: XRInterface
var xr_active := false

var _base := Transform3D.IDENTITY
## Follows the active camera; fade sphere and FPS panel hang here.
var _head: Node3D
var _fade_mat: StandardMaterial3D
var _fade_mesh: MeshInstance3D
var _fade_tween: Tween
var _desktop_yaw := 0.0
var _desktop_pitch := 0.0
var _auto_recenter_timer := -1.0

# frame-rate statistics (F10 shows them, logged every 5 s with --fps)
var fps_visible := false
var _fps_panel: Panel3D
var _fps_frames := 0
var _fps_time := 0.0
var _fps_worst := 0.0
var _fps_text := ""
var _fps_log := OS.get_cmdline_user_args().has("--fps")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	origin = XROrigin3D.new()
	origin.name = "XROrigin3D"
	origin.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(origin)
	origin.current = true
	camera = XRCamera3D.new()
	camera.name = "XRCamera3D"
	camera.near = 0.05
	camera.far = 6000.0
	camera.fov = 75.0
	origin.add_child(camera)
	desktop_camera = Camera3D.new()
	desktop_camera.name = "DesktopCamera"
	desktop_camera.near = 0.05
	desktop_camera.far = 6000.0
	desktop_camera.fov = 75.0
	origin.add_child(desktop_camera)
	_head = Node3D.new()
	_head.name = "HeadAnchor"
	origin.add_child(_head)
	_setup_fade()
	interface = XRServer.find_interface("OpenXR")
	var xr_ready := interface != null and interface.is_initialized()
	if xr_ready and OS.get_cmdline_user_args().has("--no-xr"):
		# desktop requested although OpenXR started: shut it down for good,
		# otherwise its frame loop throttles the desktop
		interface.uninitialize()
		xr_ready = false
	if xr_ready:
		if interface.has_signal("pose_recentered"):
			interface.connect("pose_recentered", recenter)
		get_viewport().use_xr = true
		camera.current = true
		xr_active = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		if not Settings.has_recenter:
			_auto_recenter_timer = AUTO_RECENTER_DELAY
		print("[XR] VR mode")
	else:
		var want_desktop := OS.get_cmdline_user_args().has("--no-xr") or DisplayServer.get_name() == "headless"
		if not want_desktop:
			# VR start without a usable headset: no silent fallback to desktop
			OS.alert(Lang.t("No VR headset found.\n\nSwitch the headset on and start its runtime software,\nor start the desktop version (Start-Desktop.cmd)."), "Stunt Track Racer VR")
			get_tree().quit(1)
			return
		get_viewport().use_xr = false
		desktop_camera.current = true
		xr_active = false
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		print("[XR] desktop mode (right mouse button = look around)")
	_apply()


func active_camera() -> Camera3D:
	return camera if xr_active else desktop_camera


func set_base(base: Transform3D) -> void:
	_base = base
	_apply()


func _apply() -> void:
	var rec := Settings.recenter_offset if xr_active else Transform3D.IDENTITY
	# optional seat height trim along the (blended) up axis
	var base := _base.translated_local(Vector3(0, Settings.seat_height, 0))
	origin.global_transform = CockpitMath.origin_transform(base, rec)
	desktop_camera.transform = Transform3D(Basis.from_euler(Vector3(_desktop_pitch, _desktop_yaw, 0.0)), Vector3.ZERO)
	_head.transform = active_camera().transform


func recenter() -> void:
	if xr_active:
		Settings.recenter_offset = CockpitMath.recenter_offset(camera.transform)
		Settings.has_recenter = true
		Settings.save_settings()
		print("[XR] recentered at head pose ", camera.transform.origin)
	else:
		_desktop_yaw = 0.0
		_desktop_pitch = 0.0
	_apply()
	recentered.emit()


func head_transform() -> Transform3D:
	return active_camera().global_transform


func _process(delta: float) -> void:
	_head.transform = active_camera().transform
	_update_fps(delta)
	if _auto_recenter_timer > 0.0:
		_auto_recenter_timer -= delta
		if _auto_recenter_timer <= 0.0:
			recenter()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			recenter()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F9:
			save_screenshot()
		elif event.keycode == KEY_F10:
			fps_visible = not fps_visible
			if _fps_panel:
				_fps_panel.visible = fps_visible
	if not xr_active and event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
		_desktop_yaw -= event.relative.x * 0.004
		_desktop_pitch = clampf(_desktop_pitch - event.relative.y * 0.004, -1.3, 1.3)
		_apply()


func save_screenshot(path := "") -> String:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	if path == "":
		path = "user://screenshots/shot_%d.png" % Time.get_unix_time_from_system()
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[XR] screenshot saved: ", ProjectSettings.globalize_path(path))
	return path


# --- frame rate ------------------------------------------------------------------

func _update_fps(delta: float) -> void:
	_fps_frames += 1
	_fps_time += delta
	_fps_worst = maxf(_fps_worst, delta)
	if _fps_time < 1.0:
		return
	var avg := _fps_frames / _fps_time
	var refresh := 0.0
	if xr_active and interface and interface.has_method("get_display_refresh_rate"):
		refresh = interface.call("get_display_refresh_rate")
	_fps_text = "%.0f FPS  MIN %.0f  %.1f MS%s" % [avg, 1.0 / maxf(_fps_worst, 1e-4), 1000.0 / avg,
		("  HMD %.0f HZ" % refresh) if refresh > 0.0 else ""]
	if _fps_log:
		print("[FPS] ", _fps_text)
	_fps_frames = 0
	_fps_time = 0.0
	_fps_worst = 0.0
	if fps_visible:
		_show_fps()


func _show_fps() -> void:
	if _fps_panel == null:
		_fps_panel = Panel3D.new().setup(Vector2i(512, 48), Vector2(0.32, 0.03), true)
		_fps_panel.position = Vector3(0, -0.16, -0.6)
		_head.add_child(_fps_panel)
	_fps_panel.visible = true
	var sc := _fps_panel.screen
	sc.clear()
	sc.background = Palette.BLACK
	sc.text(10, 10, _fps_text, Palette.GREEN, 4.0)
	sc.commit()


# --- fade to black (used for crane transitions) -------------------------------

func _setup_fade() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	sphere.radial_segments = 16
	sphere.rings = 8
	_fade_mat = StandardMaterial3D.new()
	_fade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fade_mat.no_depth_test = true
	_fade_mat.render_priority = 127
	_fade_mat.albedo_color = Color(0, 0, 0, 0)
	_fade_mesh = MeshInstance3D.new()
	_fade_mesh.mesh = sphere
	_fade_mesh.material_override = _fade_mat
	_fade_mesh.visible = false
	_fade_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_head.add_child(_fade_mesh)


func fade_to(alpha: float, duration: float) -> Tween:
	if _fade_tween:
		_fade_tween.kill()
	_fade_mesh.visible = true
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_mat, "albedo_color:a", alpha, duration)
	if alpha <= 0.0:
		_fade_tween.tween_callback(func(): _fade_mesh.visible = false)
	return _fade_tween


func set_fade(alpha: float) -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_mat.albedo_color.a = alpha
	_fade_mesh.visible = alpha > 0.001
