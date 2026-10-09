class_name VrEditorHost
extends Node3D
## The track editor in VR: its screen lies on a sphere around the eye
## (DOME_RADIUS), a band of DOME_DEG degrees across the view - each pixel a
## fixed angle (DEG_PER_PX). The mouse is captured and moves a pointer freely
## over that band; its events (and the keys) go on to the editor's viewport.
## The controls and the plan sit in the middle part (UI_PX); in the height
## stage the rest of the sphere is clear and a click there goes through to
## the 3D track - the mouse ray runs from the eye through the pointer
## (EditorView). The sphere is fixed to the XR rig at the seat's eye point:
## it moves with the camera (in the height stage it circles the pivot with
## it), and the head moves and turns freely inside it (6DOF).
## The pointer is a 3D arrow, not part of the screen: on the sphere it would
## sit at another depth than the track behind it and the eyes would not
## agree what it points at. Its direction is always the pointer's own on the
## sphere (it stays put for the viewer while the camera moves); along it it
## is drawn as far as what it points at (HeightEditor3D.cursor_depth: the
## dragged point, a point, the road, the ground, the sky) - on the sphere
## only over a control, which is nearer (TrackEditor.ui_at). The right
## mouse button turns the camera and leaves the pointer where it is.

const DEG_PER_PX := 0.05
const DOME_DEG := Vector2(160.0, 110.0)     # yaw, pitch range of the screen
const DOME_RADIUS := 2.0                     # metres from the eye
const UI_PX := Vector2(1500, 860)            # controls and plan, in the middle
const DOME_STEPS := Vector2i(48, 32)         # mesh resolution of the sphere band
const DOUBLE_CLICK_TIME := 0.4               # s
const DOUBLE_CLICK_PX := 8.0
## Keys that stay with the game (recenter, screenshot, frame rate).
const PASS_KEYS := [KEY_F9, KEY_F10, KEY_F12]

var editor: TrackEditor
var viewport: SubViewport
## The sphere's frame (origin: the eye) and the band shown on it.
var dome: Node3D
var screen: MeshInstance3D
var cursor := Vector2.ZERO
var _px := Vector2.ZERO
var _pointer: Node3D
var _last_press_time := -10.0
var _last_press_pos := Vector2(-100, -100)


func _init(e: TrackEditor) -> void:
	name = "VrEditorHost"
	editor = e
	_px = (DOME_DEG / DEG_PER_PX).round()
	cursor = _px * 0.5
	viewport = SubViewport.new()
	viewport.size = Vector2i(_px)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	editor.world_parent = self
	editor.ui_rect = Rect2((_px - UI_PX) * 0.5, UI_PX)
	viewport.add_child(editor)
	_pointer = _make_pointer()
	add_child(_pointer)
	process_priority = 100        # after the camera (height stage) has been placed
	dome = Node3D.new()
	dome.name = "EditorDome"     # goes on the XR rig (see _ready)
	screen = MeshInstance3D.new()
	screen.name = "Screen"
	screen.mesh = _band_mesh()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = viewport.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 20
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	screen.material_override = mat
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dome.add_child(screen)
	editor.view = EditorView.new(XrManager.active_camera(), dome, DOME_RADIUS, DEG_PER_PX, _px)


## The band of the sphere the screen shows: u along the yaw, v down the
## pitch, both linear in the angle (as EditorView maps pixels).
static func _band_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corner := func(i: int, k: int) -> void:
		var u := float(i) / DOME_STEPS.x
		var v := float(k) / DOME_STEPS.y
		var yaw := deg_to_rad((u - 0.5) * DOME_DEG.x)
		var pitch := deg_to_rad((0.5 - v) * DOME_DEG.y)
		st.set_uv(Vector2(u, v))
		st.add_vertex(Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * DOME_RADIUS)
	for i in DOME_STEPS.x:
		for k in DOME_STEPS.y:
			corner.call(i, k)
			corner.call(i + 1, k)
			corner.call(i + 1, k + 1)
			corner.call(i, k)
			corner.call(i + 1, k + 1)
			corner.call(i, k + 1)
	return st.commit()


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# the mouse is always "in" the screen (a SubViewportContainer would tell
	# it so): else the viewport drops moves without a button (no hover)
	viewport.notification(Viewport.NOTIFICATION_VP_MOUSE_ENTER)
	XrManager.set_base(Transform3D(Basis.IDENTITY, Vector3(0, 10, 0)))
	# on the rig: it moves exactly with the camera, no frame late
	XrManager.origin.add_child(dome)
	_place()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	dome.queue_free()


func _process(_dt: float) -> void:
	_place()
	_place_pointer()


## The pointer where it points (see the class comment), facing the eyes,
## always the same size to them (DEG_PER_PX per pixel of its shape).
func _place_pointer() -> void:
	var h := editor.height_editor()
	var at := editor.view.sphere_point(cursor)
	if h != null and (h.dragging() or not editor.ui_at(cursor)):
		var r := editor.view.ray(cursor)
		at = (r[0] as Vector3) + (r[1] as Vector3) * h.cursor_depth
	var cam := XrManager.active_camera()
	var k := deg_to_rad(DEG_PER_PX) * cam.global_position.distance_to(at)
	_pointer.global_transform = Transform3D(cam.global_transform.basis.orthonormalized(), at).scaled_local(Vector3.ONE * k)


## The sphere's centre is the seat's eye point (the base pose): on the rig
## that is the recentre offset (VR; the desktop camera sits at the origin).
func _place() -> void:
	dome.transform = Settings.recenter_offset if XrManager.xr_active else Transform3D.IDENTITY


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).keycode in PASS_KEYS:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# the pointer moves by angle: one mouse pixel = one screen pixel; with
		# the right button down the mouse turns the camera, the pointer stays
		if not (mm.button_mask & MOUSE_BUTTON_MASK_RIGHT):
			cursor = (cursor + mm.relative).clamp(Vector2.ZERO, _px - Vector2.ONE)
		var ev := InputEventMouseMotion.new()
		ev.position = cursor
		ev.global_position = cursor
		ev.relative = mm.relative
		ev.velocity = mm.velocity
		ev.button_mask = mm.button_mask
		ev.shift_pressed = mm.shift_pressed
		ev.ctrl_pressed = mm.ctrl_pressed
		ev.alt_pressed = mm.alt_pressed
		viewport.push_input(ev, true)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var ev := InputEventMouseButton.new()
		ev.position = cursor
		ev.global_position = cursor
		ev.button_index = mb.button_index
		ev.pressed = mb.pressed
		ev.button_mask = mb.button_mask
		ev.factor = mb.factor
		ev.shift_pressed = mb.shift_pressed
		ev.ctrl_pressed = mb.ctrl_pressed
		ev.alt_pressed = mb.alt_pressed
		# the mouse is captured: a double click is told by time and place here
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var now := Time.get_ticks_msec() / 1000.0
			ev.double_click = now - _last_press_time < DOUBLE_CLICK_TIME and cursor.distance_to(_last_press_pos) < DOUBLE_CLICK_PX
			_last_press_time = -10.0 if ev.double_click else now
			_last_press_pos = cursor
		viewport.push_input(ev, true)
	else:
		viewport.push_input(event, true)
	get_viewport().set_input_as_handled()


## The pointer: an arrow (shape in pixels, tip at the origin, x right, y
## up) with a dark rim, unlit, never hidden.
static func _make_pointer() -> Node3D:
	var arrow := PackedVector2Array([Vector2(0, 0), Vector2(0, -22), Vector2(6, -17), Vector2(10, -26),
		Vector2(14, -24), Vector2(10, -15), Vector2(17, -15)])
	var node := Node3D.new()
	node.name = "EditorPointer"
	var rim: PackedVector2Array = Geometry2D.offset_polygon(arrow, 2.0)[0]
	for part in [[rim, Color.BLACK, 30], [arrow, Color.WHITE, 31]]:
		var poly: PackedVector2Array = part[0]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in Geometry2D.triangulate_polygon(poly):
			st.add_vertex(Vector3(poly[i].x, poly[i].y, 0.0))
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = part[1]
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA     # drawn last, by render_priority
		mat.no_depth_test = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.render_priority = part[2]
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
	return node
