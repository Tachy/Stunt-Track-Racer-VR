class_name VrEditorHost
extends Node3D
## The track editor in VR: its screen is a panel floating in front of the
## seat (it follows XrManager's base pose, so in the height stage it travels
## with the camera). Where the editor draws nothing the panel is clear: the
## 3D height editor shows through it. The mouse is captured and moves a
## pointer on the panel; its events (and the keys) go on to the editor's
## viewport, and EditorView turns pointer positions into rays from the head.

const PANEL_PX := Vector2i(1280, 720)       # 2.5 mm per pixel: readable in the headset
const PANEL_SIZE := Vector2(3.2, 1.8)     # metres
const PANEL_DIST := 2.2                   # in front of the eyes (m)
const PANEL_DROP := 0.15                  # below eye height (m)
const DOUBLE_CLICK_TIME := 0.4            # s
const DOUBLE_CLICK_PX := 8.0
## Keys that stay with the game (recenter, screenshot, frame rate).
const PASS_KEYS := [KEY_F9, KEY_F10, KEY_F12]

var editor: TrackEditor
var viewport: SubViewport
var panel: MeshInstance3D
var cursor := Vector2(PANEL_PX) * 0.5
var _pointer: Control
var _last_press_time := -10.0
var _last_press_pos := Vector2(-100, -100)


func _init(e: TrackEditor) -> void:
	name = "VrEditorHost"
	editor = e
	viewport = SubViewport.new()
	viewport.size = PANEL_PX
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	editor.world_parent = self
	viewport.add_child(editor)
	_pointer = _Pointer.new()
	viewport.add_child(_pointer)
	panel = Panel3D.make_quad(PANEL_SIZE, viewport.get_texture())
	var mat := panel.material_override as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 20
	panel.name = "Screen"
	add_child(panel)
	editor.view = EditorView.new(XrManager.active_camera(), panel, PANEL_SIZE, Vector2(PANEL_PX))


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	XrManager.set_base(Transform3D(Basis.IDENTITY, Vector3(0, 10, 0)))
	_place()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_dt: float) -> void:
	_place()
	_pointer.position = cursor


## The panel in front of the seat (the base pose, not the head: it stays
## put while the head looks around).
func _place() -> void:
	panel.global_transform = XrManager.base_transform() * Transform3D(Basis.IDENTITY, Vector3(0, -PANEL_DROP, -PANEL_DIST))


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).keycode in PASS_KEYS:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		cursor = (cursor + mm.relative).clamp(Vector2.ZERO, Vector2(PANEL_PX) - Vector2.ONE)
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


## The mouse pointer on the panel (an arrow with a dark rim).
class _Pointer extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 100
		top_level = true

	func _draw() -> void:
		var arrow := PackedVector2Array([Vector2(0, 0), Vector2(0, 22), Vector2(6, 17), Vector2(10, 26), Vector2(14, 24), Vector2(10, 15), Vector2(17, 15)])
		var rim := PackedVector2Array()
		for p in arrow:
			rim.append(p)
		rim.append(arrow[0])
		draw_colored_polygon(arrow, Color.WHITE)
		draw_polyline(rim, Color.BLACK, 2.0)
