class_name TrackEditor
extends Control
## Track editor (mouse + keyboard; in VR on a screen panel, VrEditorHost).
## Logic in TrackEditorModel; this node draws the plan and turns clicks into
## pieces.
##   left click   start point / first direction / place the previewed piece
##   Esc          remove the last piece (Ctrl+Z / Ctrl+Y undo / redo)
##   O, Shift+O   loop (shifted to the right / left)
##   wheel        zoom, right mouse button: pan
## Near the start the closing pieces are previewed in green; a click closes
## the lap. Closed tracks can be saved, test-driven and raced in practice.
## In a closed lap a click on the road marks a piece (with its run-out),
## Shift+click a stretch of them; a right click (without dragging) deletes
## the marked ones. The gap is drawn as usual and closed onto its anchor
## (yellow mark) like a lap onto its start; Esc right after the cut undoes it.
## The marked pieces can be dragged: the gaps before and after them are
## filled (green while dragging, red: no fit), on release for good; their
## height points go along. The cursor keys move them a grid step (or on to
## the nearest step that fits). The start line can be dragged along the
## straights. R (or the button) reverses the direction of the lap, the start
## line stays where it is. Esc undoes these.
##
## Heights (Tab / button, closed lap only): the track in 3D (HeightEditor3D)
## with a see-through ground and tunnels; the height along the lap (loops
## take no room there) is a spline through free points, drawn on the road;
## at first only the start and the end of the lap (always at the same
## height). Click a point: it is selected (blue) and can be dragged (along
## the lap and up / down); double click on it: the camera turns around it;
## double click on the road: a new point; right click: remove it; C kink at the
## point; Up/Down (Shift: x4) its height, Left/Right 1 m back / on along the
## lap. A loop (set in the plan) has a green mark on its top: click it, then
## Up/Down change its radius. No slope limit: dragged at least 80 deg steep to a neighbour, a
## point snaps under (or over) it as a vertical wall: wall down + wall up = pit (floor on
## the ground: the ground), wall down alone = ski jump. Dragged away to the
## side again it is a spline point. A click on the road marks its piece
## (B drawbridge) and leaves the camera where it is. The camera turns around
## the point double-clicked last (right mouse button; wheel = distance). Top left
## the plan (PlanNav): click = the piece there, the camera turns around it;
## right mouse = push, wheel = zoom. Esc undo.
## Below the ground the road becomes a cut and a tunnel by itself.
##
## H (or the HELP button) shows / hides the keys of the stage (EditorHelp):
## in the plan stage under the info line, in the height stage under the plan.

signal start_race(request: Dictionary)
signal leave

const BG := Color("#4f5a37")
const GRID_MINOR := Color(1, 1, 1, 0.05)
const GRID_MAJOR := Color(1, 1, 1, 0.12)
const ROAD_A := Color("#bbbb99")
const ROAD_B := Color("#999977")
const ROAD_AUTO := Color("#d8c48a")
const GHOST := Color(1.0, 0.85, 0.2, 0.55)
const GHOST_CLOSE := Color(0.3, 1.0, 0.4, 0.6)
const CROSSING := Color(1.0, 0.25, 0.2, 0.9)
const STEEP := Color(1.0, 0.6, 0.1, 0.9)
## Head start of curves with the radius of the latest one (screen pixels).
const RADIUS_STICK_PX := 9.0
const SELECT := Color(1.0, 0.9, 0.2)
const MARKED := Color(0.95, 0.35, 0.25)          # pieces marked for deleting
const ANCHOR := Color(1.0, 0.85, 0.2)            # where a gap is closed to
const CLICK_SLOP := 4.0                          # px a right click may move
const MODE_BUTTON := Color("#2f6db5")   # heights / plan
const MENU_BUTTON := Color("#a83a32")   # leave the editor
const HELP_BUTTON := Color("#3d8a4a")   # help on / off

var model := TrackEditorModel.new()
var track_name := "MY TRACK"
var zoom := 0.9                 # pixels per metre
var view_center := Vector2.ZERO
var _mouse_world := Vector2.ZERO
var _panning := false
var _preview: Array = []
var _preview_closes := false
var _crossings := PackedVector2Array()
## Marked pieces (first, last; x < 0 = none) and the piece Shift extends from.
var _marked := Vector2i(-1, -1)
var _mark_anchor := -1
var _right_moved := 0.0         # mouse travel with the right button down (px)
## Dragging with the left button in a closed lap: "block" (the marked
## pieces), "start" (the start line) or ""; where it began, whether the mouse
## has moved yet, and the lap it would give (TrackEditorModel.moved(), {}:
## no fit) / the start spot ([] none).
var _drag := ""
var _drag_from := Vector2.ZERO
var _drag_px := Vector2.ZERO
var _drag_moved := false
var _drag_offset := Vector2.ZERO
var _drag_lap: Dictionary = {}
var _drag_spot: Array = []

# height stage
var _mode := "plan"              # plan, height
var _h3d: HeightEditor3D
var _nav: PlanNav
var _mode_btn: Button
## Where the 3D view goes (VR: VrEditorHost; else the editor's parent) and
## how the screen maps to it (VR: the panel; else the desktop camera).
var world_parent: Node
var view: EditorView
## VR: the part of the screen sphere in front for the controls and the plan
## (empty: the whole window).
var ui_rect := Rect2()
var _bar: HBoxContainer
var _help: EditorHelp

var _name_edit: LineEdit
var _load_menu: OptionButton
var _status: Label
var _info: Label
## Id of the file the track was loaded from / last saved to ("" = none).
var _saved_id := ""
## Admin mode (--admin, run from the project only - an exported game cannot
## write res://): an official track is saved back to server/official, an
## example track (TrackLibrary.EXAMPLES) back to examples/.
var admin := OS.get_cmdline_user_args().has("--admin") and OS.has_feature("editor")
## Admin: the example track being edited (its id; "" = none).
var _example := ""


func _init(file_id := "") -> void:
	name = "TrackEditor"
	var data := _load_data(file_id)
	if not data.is_empty():
		model = TrackEditorModel.from_dict(data)
		track_name = str(data.get("name", track_name))
		_saved_id = file_id
		_example = file_id.trim_prefix(TrackLibrary.EXAMPLE_PREFIX) if TrackLibrary.is_example(file_id) else ""


## The editor file of track id ({}: none; official and example tracks in
## admin mode only).
func _load_data(id: String) -> Dictionary:
	if id == "":
		return {}
	if TrackLibrary.is_official(id):
		return TrackLibrary.load_official(id) if admin else {}
	if TrackLibrary.is_example(id):
		return TrackLibrary.load_example(id) if admin else {}
	var data := TrackLibrary.load_custom(id)
	data.erase("official")     # an own file is never an official track
	return data


func _ready() -> void:
	# not inside a Control: follow the window size by hand
	_fit_window()
	get_viewport().size_changed.connect(_fit_window)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_build_bar()
	if model.has_start:
		view_center = model.start
	if OS.get_cmdline_user_args().has("--editor-heights") and model.closed:
		# debug / screenshots: straight into the height stage
		_set_mode("height")
		_h3d.select_piece(mini(3, model.pieces.size() - 1))
	_update()
	XrManager.set_fade(0.0)
	Sfx.stop_music()      # the title music is for the menus only


## Where the controls (and the plan) go: ui_rect, else the whole window.
func _ui() -> Rect2:
	return ui_rect if ui_rect.has_area() else Rect2(Vector2.ZERO, get_viewport_rect().size)


## The plan stage fills _ui(); the height stage the whole window (in VR the
## whole sphere: a click beside the controls goes to the 3D track).
func _fit_window() -> void:
	var r := Rect2(Vector2.ZERO, get_viewport_rect().size) if _mode == "height" else _ui()
	position = r.position
	size = r.size
	if _status:
		_update()


## Button of the top bar; tint = background colour (default theme if clear).
func _bar_button(label: String, action: Callable, tint := Color.TRANSPARENT) -> Button:
	var btn := Button.new()
	btn.text = Lang.t(label)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(action)
	if tint.a > 0.0:
		for state in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = tint.lightened(0.15 if state == "hover" else 0.0).darkened(0.15 if state == "pressed" else 0.0)
			sb.set_corner_radius_all(3)
			sb.content_margin_left = 8
			sb.content_margin_right = 8
			btn.add_theme_stylebox_override(state, sb)
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
	return btn


func _build_bar() -> void:
	var bar := HBoxContainer.new()
	_bar = bar
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	var title := Label.new()
	title.text = Lang.t("TRACK EDITOR") + (" (ADMIN)" if admin else "")
	bar.add_child(title)
	_load_menu = OptionButton.new()
	_load_menu.focus_mode = Control.FOCUS_NONE
	_load_menu.item_selected.connect(_act_load)
	bar.add_child(_load_menu)
	_fill_load_menu()
	bar.add_child(_bar_button("NEW", _act_new))
	_name_edit = LineEdit.new()
	_name_edit.text = track_name
	_name_edit.custom_minimum_size = Vector2(200, 0)
	_name_edit.max_length = 24
	_name_edit.text_changed.connect(func(t: String): track_name = t)
	bar.add_child(_name_edit)
	for b in [["SAVE", _act_save], ["DELETE", _act_delete], ["RENAME", _act_rename]]:
		bar.add_child(_bar_button(b[0], b[1]))
	bar.add_child(_bar_button("REVERSE", _act_reverse))
	_mode_btn = _bar_button("", _toggle_mode, MODE_BUTTON)
	bar.add_child(_mode_btn)
	bar.add_child(_bar_button("TEST DRIVE", _act_test))
	bar.add_child(_bar_button("HELP (H)", _toggle_help, HELP_BUTTON))
	bar.add_child(_bar_button("MENU", func(): leave.emit(), MENU_BUTTON))
	_info = Label.new()
	add_child(_info)
	_status = Label.new()
	add_child(_status)
	for l in [_info, _status]:     # readable over the 3D view too
		l.add_theme_constant_override("outline_size", 5)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	# navigation window of the height stage
	_nav = PlanNav.new()
	_nav.visible = false
	_nav.piece_clicked.connect(func(k: int): _h3d.select_piece(k, true))   # the camera goes there
	add_child(_nav)
	_help = EditorHelp.new()
	add_child(_help)


## Admin: the official tracks first (to tune them) and the shipped example
## tracks; then the own ones. The item's metadata is the track id.
func _fill_load_menu() -> void:
	_load_menu.clear()
	_load_menu.add_item(Lang.t("LOAD ..."))
	for id in TrackLibrary.ORDER:
		if admin and TrackLibrary.is_official(id):
			_load_menu.add_item(Lang.t("OFFICIAL: %s") % TrackLibrary.display_name(id))
			_load_menu.set_item_metadata(_load_menu.item_count - 1, id)
	if admin:
		for ex in TrackLibrary.EXAMPLES:
			var id: String = TrackLibrary.EXAMPLE_PREFIX + ex
			_load_menu.add_item(Lang.t("EXAMPLE: %s") % TrackLibrary.display_name(id))
			_load_menu.set_item_metadata(_load_menu.item_count - 1, id)
	if DirAccess.dir_exists_absolute(TrackLibrary.CUSTOM_DIR):
		for f in DirAccess.get_files_at(TrackLibrary.CUSTOM_DIR):
			if f.ends_with(".json"):
				_load_menu.add_item(f.get_basename())
				_load_menu.set_item_metadata(_load_menu.item_count - 1, TrackLibrary.CUSTOM_PREFIX + f.get_basename())


# --- view ----------------------------------------------------------------------------

func to_screen(w: Vector2) -> Vector2:
	return (w - view_center) * zoom + size * 0.5


func to_world(s: Vector2) -> Vector2:
	return (s - size * 0.5) / zoom + view_center


# --- input ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if _mode == "height":
		if event is InputEventMouseButton and event.pressed:
			grab_focus()
		_h3d.handle(event)
		accept_event()
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			view_center -= mm.relative / zoom
			_right_moved += mm.relative.length()
		_mouse_world = to_world(mm.position)
		if _drag != "":
			_drag_motion(mm.position)
		_update()
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				grab_focus()
				if not _drag_begin(mb.position, mb.shift_pressed):
					_click(to_world(mb.position), mb.shift_pressed)
			MOUSE_BUTTON_RIGHT:
				_panning = true
				_right_moved = 0.0
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				var before := to_world(mb.position)
				zoom = clampf(zoom * (1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.08, 12.0)
				view_center += before - to_world(mb.position)
				_update()
	elif event is InputEventMouseButton and not event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag_end()
	elif event is InputEventMouseButton and not event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		_panning = false
		if _right_moved < CLICK_SLOP:     # by the mouse's travel (in VR the pointer stays put)
			_delete_marked()
	if event is InputEventMouse:
		accept_event()   # not on to the desktop camera (right mouse = look around)


## Esc and the shortcuts come before InputManager (which would leave).
func _input(event: InputEvent) -> void:
	# held down, only the cursor keys repeat (as real keys); Esc and the
	# others act once per press
	if not (event is InputEventKey) or not event.pressed \
			or (event.echo and not (event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN])):
		return
	if get_viewport().gui_get_focus_owner() == _name_edit and event.keycode != KEY_ESCAPE:
		return
	var k := event as InputEventKey
	var handled := true
	if k.keycode == KEY_TAB:
		_toggle_mode()
	elif k.keycode == KEY_H and not k.ctrl_pressed:
		_toggle_help()
	elif k.keycode == KEY_S and k.ctrl_pressed:
		_act_save()
	elif _mode == "height":
		handled = _height_key(k)
	elif k.keycode == KEY_ESCAPE:
		if get_viewport().gui_get_focus_owner() == _name_edit:
			_name_edit.release_focus()
		else:
			model.undo()
	elif k.keycode == KEY_Z and k.ctrl_pressed:
		model.undo()
	elif k.keycode == KEY_Y and k.ctrl_pressed:
		model.redo()
	elif k.keycode == KEY_O and model.start_dir != Vector2.ZERO and not model.closed:
		model.place(model.loop_group(-1 if k.shift_pressed else 1))
	elif k.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN] and model.closed and _marked.x >= 0 and _drag == "":
		_nudge(k.keycode)
		get_viewport().set_input_as_handled()
		return
	elif k.keycode == KEY_R and not k.ctrl_pressed and model.closed:
		_act_reverse()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()
		_update()


func _click(w: Vector2, shift := false) -> void:
	if model.closed:
		_mark(w, shift)
	elif not model.has_start:
		model.set_start(w.snapped(Vector2.ONE * TrackEditorModel.GRID))
	elif model.start_dir == Vector2.ZERO:
		model.place_first(w)
	elif not model.closed and not _preview.is_empty():
		model.place(_preview, _preview_closes)
		if model.closed:
			_flash(Lang.t("LAP CLOSED - SAVE OR TEST DRIVE"))
	_update()


## Closed lap: a click on the road marks its piece (with the run-out placed
## along with it), Shift+click stretches the marking up to it; a click
## beside the road clears it.
func _mark(w: Vector2, shift: bool) -> void:
	var k := model.piece_at(w)
	if k < 0:
		_marked = Vector2i(-1, -1)
		_mark_anchor = -1
		return
	var r := model.group_range(k)
	if shift and _mark_anchor >= 0 and _mark_anchor < model.pieces.size():
		var a := model.group_range(_mark_anchor)
		_marked = Vector2i(mini(a.x, r.x), maxi(a.y, r.y))
	else:
		_marked = r
		_mark_anchor = k


## Cursor keys: the marked pieces a grid step that way, or on to the
## nearest step that fits (TrackEditorModel.nudge()).
func _nudge(key: int) -> void:
	var dir: Vector2 = {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT, KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}[key]
	var r := model.nudge(_marked.x, _marked.y, dir)
	if not r.is_empty():
		_marked = r["block"]
		_mark_anchor = _marked.x
	_update()
	if r.is_empty():
		_flash(Lang.t("NOT POSSIBLE - THE GAPS CANNOT BE FILLED"))


## Right click: the marked pieces go, a gap is left to draw anew.
func _delete_marked() -> void:
	if _mode != "plan" or _marked.x < 0 or not model.closed:
		return
	var ok := model.cut(_marked.x, _marked.y)
	_marked = Vector2i(-1, -1)
	_mark_anchor = -1
	_update()
	if not ok:
		_flash(Lang.t("NOT POSSIBLE - THE WHOLE LAP"))


## Left button down in a closed lap: on the start line it starts dragging
## that, on a marked piece the marked ones. False if neither.
func _drag_begin(px: Vector2, shift: bool) -> bool:
	if _mode != "plan" or not model.closed or shift:
		return false
	var w := to_world(px)
	if px.distance_to(to_screen(model.start)) < maxf(10.0, TrackPath.HALF_WIDTH * zoom):
		_drag = "start"
	elif _marked.x >= 0:
		var k := model.piece_at(w)
		if k < _marked.x or k > _marked.y:
			return false
		_drag = "block"
	else:
		return false
	_drag_from = w
	_drag_px = px
	_drag_moved = false
	_drag_offset = Vector2.ZERO
	_drag_lap = {}
	_drag_spot = []
	return true


func _drag_motion(px: Vector2) -> void:
	if not _drag_moved and px.distance_to(_drag_px) < CLICK_SLOP:
		return
	_drag_moved = true
	var w := to_world(px)
	if _drag == "start":
		_drag_spot = model.start_spot(w)
		return
	var off := (w - _drag_from).round()     # whole metres
	if off != _drag_offset:
		_drag_offset = off
		_drag_lap = model.moved(_marked.x, _marked.y, off) if off != Vector2.ZERO else {}


## Left button up: the drag is done for good (a click without moving marks
## as usual).
func _drag_end() -> void:
	if _drag == "":
		return
	var what := _drag
	_drag = ""
	if not _drag_moved:
		_click(_drag_from)
		return
	if what == "start":
		if not _drag_spot.is_empty() and not (_drag_spot[0] == 0 and float(_drag_spot[1]) < 0.01) \
				and not model.move_start(_drag_spot[0], _drag_spot[1]):
			_update()
			_flash(Lang.t("NOT POSSIBLE - TOO NEAR A HEIGHT POINT"))
			return
	elif _drag_offset != Vector2.ZERO:
		if _drag_lap.is_empty():
			_update()
			_flash(Lang.t("NOT POSSIBLE - THE GAPS CANNOT BE FILLED"))
			return
		var block: Vector2i = _drag_lap["block"]
		model.move_block(_marked.x, _marked.y, _drag_offset)
		_marked = block
		_mark_anchor = block.x
	_update()


# --- state -> picture -----------------------------------------------------------------

func _update() -> void:
	_mode_btn.text = Lang.t("PLAN") if _mode == "height" else Lang.t("HEIGHTS")
	# the controls in _ui() (this node may be larger: the height stage)
	var o := _ui().position - position
	var us := _ui().size
	_bar.position = o + Vector2(10, 8)
	_info.position = o + Vector2(12, 44)
	_status.position = o + Vector2(12, us.y - 34)
	# the help: under the plan (height stage) / the info line, down to the status line
	var help_top := 72.0
	if _mode == "height":
		_nav.position = o + Vector2(10, 72)
		_nav.size = Vector2(maxf(220.0, us.x * 0.28), maxf(160.0, us.y * 0.34))
		help_top += _nav.size.y + 8.0
	if _help.visible:
		_help.place(_mode, Rect2(o + Vector2(10, help_top), Vector2(us.x - 20.0, us.y - help_top - 44.0)))
	if _mode == "height":
		_info.text = _height_info()
		_status.text = Lang.t("H = HELP: KEYS AND MOUSE")
		queue_redraw()
		return
	_preview = []
	_preview_closes = false
	if not model.closed or _marked.y >= model.pieces.size():
		_marked = Vector2i(-1, -1)
		_mark_anchor = -1
	if model.near_target(_mouse_world):
		_preview = model.closing_group()
		_preview_closes = not _preview.is_empty()
	if _preview.is_empty():
		# zoomed in, another radius is easier to pick (the head start of the
		# radius kept is a fixed number of pixels)
		_preview = model.candidate(_mouse_world, RADIUS_STICK_PX / zoom)
	_crossings = model.crossings()
	_info.text = _info_text()
	if not model.has_start:
		_status.text = Lang.t("CLICK THE START POINT")
	elif model.start_dir == Vector2.ZERO:
		_status.text = Lang.t("CLICK THE END OF THE START STRAIGHT (ACROSS OR UP/DOWN)")
	elif model.closed:
		_status.text = Lang.t("LAP CLOSED - SAVE OR TEST DRIVE (ESC REOPENS)")
	elif model.has_gap():
		_status.text = Lang.t("DRAW THE GAP TO THE YELLOW MARK  ESC = REMOVE LAST / UNDO THE DELETING")
	else:
		_status.text = Lang.t("CLICK = PLACE  ESC = REMOVE LAST")
	_status.text += "   " + Lang.t("H = HELP: KEYS AND MOUSE")
	queue_redraw()


func _info_text() -> String:
	var t := Lang.t("LENGTH %d M  PIECES %d") % [roundi(model.total_length()), model.pieces.size() + model.tail.size()]
	if _crossings.size() > 0:
		t += "  " + Lang.t("CROSSINGS %d") % _crossings.size()
	var desc := []
	for p in _preview:
		desc.append(_piece_text(p))
	# the marked pieces, as while drawing (a longer stretch: how many, how long)
	if desc.is_empty() and _marked.x >= 0 and _marked.y < model.pieces.size():
		var ps := model.pieces.slice(_marked.x, _marked.y + 1)
		if ps.size() <= 3:
			for p in ps:
				desc.append(_piece_text(p))
		else:
			desc.append(Lang.t("%d PIECES MARKED  %d M") % [ps.size(), roundi(TrackEditorModel._group_length(ps))])
	if not desc.is_empty():
		t += "   >  " + " + ".join(desc)
	return t


static func _piece_text(p: Dictionary) -> String:
	match p.get("t", "S"):
		"S":
			return ("%s %.0f M" if fmod(float(p["l"]), 1.0) < 0.05 else "%s %.1f M") % [Lang.t("RUN-OUT") if p.get("auto", false) else Lang.t("STRAIGHT"), float(p["l"])]
		"O":
			return "%s R%.1f M" % [Lang.t("LOOP"), TrackEditorModel.loop_radius(p)]
	return "%s %d° R%d (%d°)" % [p["t"], int(p["a"]), int(p["r"]), roundi(absf(float(p.get("bank", 0.0))))]


func _toggle_help() -> void:
	_help.visible = not _help.visible
	_update()


func _flash(text: String) -> void:
	_status.text = text


func _draw() -> void:
	if _mode == "height":
		return      # the 3D view shows through
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	_draw_grid()
	if _drag == "block" and _drag_moved and not _drag_lap.is_empty():
		_draw_moved()
		return
	var pos := model.start
	var dir := model.start_dir
	var k := 0
	for p in model.pieces:
		var col := ROAD_AUTO if p.get("auto", false) else (ROAD_A if k % 2 == 0 else ROAD_B)
		if k >= _marked.x and k <= _marked.y:
			col = MARKED
		_draw_piece(pos, dir, p, col)
		var e := TrackEditorModel.advance(pos, dir, p)
		pos = e[0]
		dir = e[1]
		k += 1
	# the tail of a gap, from its anchor on
	if model.has_gap():
		var tpos := model.tail_pos
		var tdir := model.tail_dir
		for p in model.tail:
			_draw_piece(tpos, tdir, p, ROAD_AUTO if p.get("auto", false) else (ROAD_A if k % 2 == 0 else ROAD_B))
			var e3 := TrackEditorModel.advance(tpos, tdir, p)
			tpos = e3[0]
			tdir = e3[1]
			k += 1
		var a := to_screen(model.tail_pos)
		var n := model.tail_dir.rotated(PI * 0.5) * maxf(8.0, TrackPath.HALF_WIDTH * zoom)
		draw_line(a - n, a + n, ANCHOR, 4.0)
		draw_arc(a, maxf(10.0, TrackPath.ROAD_WIDTH * zoom), 0.0, TAU, 24, ANCHOR, 2.0)
	# preview
	if not _preview.is_empty():
		var gpos := pos
		var gdir := dir
		if model.start_dir == Vector2.ZERO:
			var f := model.first_straight_for(_mouse_world)
			gdir = f[0] if not f.is_empty() else Vector2.UP
		for p in _preview:
			_draw_piece(gpos, gdir, p, GHOST_CLOSE if _preview_closes else GHOST)
			var e2 := TrackEditorModel.advance(gpos, gdir, p)
			gpos = e2[0]
			gdir = e2[1]
	if _drag == "block" and _drag_moved and _drag_offset != Vector2.ZERO:
		# no fit: the marked pieces where the mouse is, in red
		var bp: Array = model.poses()[_marked.x]
		var bpos: Vector2 = bp[0] + _drag_offset
		var bdir: Vector2 = bp[1]
		for i in range(_marked.x, _marked.y + 1):
			_draw_piece(bpos, bdir, model.pieces[i], Color(CROSSING, 0.6))
			var e4 := TrackEditorModel.advance(bpos, bdir, model.pieces[i])
			bpos = e4[0]
			bdir = e4[1]
	elif _drag == "" or not _drag_moved:
		for c in _crossings:
			draw_arc(to_screen(c), maxf(10.0, TrackPath.ROAD_WIDTH * zoom), 0.0, TAU, 24, CROSSING, 3.0)
	if model.has_start:
		_draw_start(model.start, model.start_dir, Color.WHITE)
	if _drag == "start" and _drag_moved and not _drag_spot.is_empty():
		var sp := model.spot_pose(_drag_spot)
		_draw_start(sp[0], sp[1], GHOST_CLOSE)


## The lap as dragging the marked pieces would leave it: the filled gaps in
## green, the dragged pieces marked.
func _draw_moved() -> void:
	var lap := _drag_lap
	var block: Vector2i = lap["block"]
	var pos: Vector2 = lap["start"]
	var dir: Vector2 = lap["start_dir"]
	var ps: Array = lap["pieces"]
	for k in ps.size():
		var p: Dictionary = ps[k]
		var col := ROAD_AUTO if p.get("auto", false) else (ROAD_A if k % 2 == 0 else ROAD_B)
		if (lap["fill"] as Array).has(k):
			col = GHOST_CLOSE
		elif (block.x >= 0 and k >= block.x and k <= block.y) or (block.x < 0 and _in_block(p)):
			col = MARKED
		_draw_piece(pos, dir, p, col)
		var e := TrackEditorModel.advance(pos, dir, p)
		pos = e[0]
		dir = e[1]
	_draw_start(lap["start"], lap["start_dir"], Color.WHITE)


## Whether piece dictionary p is one of the marked (dragged) pieces.
func _in_block(p: Dictionary) -> bool:
	for i in range(_marked.x, _marked.y + 1):
		if is_same(model.pieces[i], p):
			return true
	return false


func _draw_grid() -> void:
	var step := 10.0
	while step * zoom < 12.0:
		step *= 5.0
	var a := to_world(Vector2.ZERO)
	var b := to_world(size)
	var x := floorf(a.x / step) * step
	while x <= b.x:
		var major := is_zero_approx(fmod(absf(x), step * 5.0))
		draw_line(to_screen(Vector2(x, a.y)), to_screen(Vector2(x, b.y)), GRID_MAJOR if major else GRID_MINOR)
		x += step
	var y := floorf(a.y / step) * step
	while y <= b.y:
		var major2 := is_zero_approx(fmod(absf(y), step * 5.0))
		draw_line(to_screen(Vector2(a.x, y)), to_screen(Vector2(b.x, y)), GRID_MAJOR if major2 else GRID_MINOR)
		y += step


func _draw_piece(pos: Vector2, dir: Vector2, p: Dictionary, col: Color) -> void:
	var pts := TrackEditorModel.sample(pos, dir, p, maxf(1.0, 3.0 / zoom))
	var scr := PackedVector2Array()
	for q in pts:
		scr.append(to_screen(q))
	draw_polyline(scr, col, maxf(2.0, TrackPath.ROAD_WIDTH * zoom), true)
	if p.get("t", "S") == "O":
		draw_circle(to_screen(pts[pts.size() / 2]), maxf(4.0, TrackEditorModel.loop_radius(p) * zoom * 0.5), Color(col, 0.5))


## The start: the line across the road and an arrow in the direction of travel.
func _draw_start(at: Vector2, d: Vector2, col: Color) -> void:
	var s := to_screen(at)
	if d == Vector2.ZERO:
		d = Vector2.UP
	var side := d.rotated(PI * 0.5)
	var n := side * maxf(8.0, TrackPath.HALF_WIDTH * zoom)
	draw_line(s - n, s + n, col, 3.0)
	var tip := s + d * maxf(40.0, 30.0 * zoom)
	var head := maxf(13.0, 9.0 * zoom)
	draw_line(s, tip - d * head * 0.5, col, 3.0)
	draw_colored_polygon(PackedVector2Array([tip, tip - d * head + side * head * 0.6, tip - d * head - side * head * 0.6]), col)


# --- actions ---------------------------------------------------------------------------

func _file_id() -> String:
	var clean := ""
	for ch in track_name.to_lower():
		clean += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	return TrackLibrary.CUSTOM_PREFIX + (clean if clean.strip_edges() != "" else "track")


func _act_save() -> void:
	if _example != "" and admin:
		_save_example()
		return
	if model.official != "":     # (loaded in admin mode only)
		_save_official()
		return
	DirAccess.make_dir_recursive_absolute(TrackLibrary.CUSTOM_DIR)
	var data := model.to_dict(track_name)
	if model.closed:
		data["def"] = model.to_def(track_name)
	var f := FileAccess.open(TrackLibrary.custom_path(_file_id()), FileAccess.WRITE)
	if f == null:
		_flash(Lang.t("COULD NOT SAVE"))
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	_saved_id = _file_id()
	_fill_load_menu()
	_flash(Lang.t("SAVED: %s") % TrackLibrary.custom_path(_file_id()))


## Admin: an official track back to server/official/<id>.json (in the
## project: commit it; it becomes official online with the next release).
## The game uses it at once (test drive).
func _save_official() -> void:
	if not model.closed:
		_flash(Lang.t("CLOSE THE LAP FIRST"))
		return
	var id := model.official
	var data := model.to_dict(track_name)
	data["def"] = model.to_def(track_name)
	var f := FileAccess.open(TrackLibrary.official_path(id), FileAccess.WRITE)
	if f == null:
		_flash(Lang.t("COULD NOT SAVE"))
		return
	f.store_string(JSON.stringify(data, "  ", false))
	f.close()
	TrackLibrary.TRACKS = TrackLibrary._load_official()
	_saved_id = id
	_fill_load_menu()
	_flash(Lang.t("OFFICIAL TRACK SAVED: %s (COMMIT IT)") % TrackLibrary.official_path(id))


## Admin: an example track back to examples/<id>.json (commit it; new
## players get it with the next release) and the same file into the own
## tracks (replacing the copy there): the template and the playable track
## stay the same.
func _save_example() -> void:
	var path := TrackLibrary.example_path(_example)
	var own := TrackLibrary.custom_path(TrackLibrary.CUSTOM_PREFIX + _example)
	var data := model.to_dict(track_name)
	if model.closed:
		data["def"] = model.to_def(track_name)
	var text := JSON.stringify(data, "  ")
	DirAccess.make_dir_recursive_absolute(TrackLibrary.CUSTOM_DIR)
	for p in [path, own]:
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f == null:
			_flash(Lang.t("COULD NOT SAVE"))
			return
		f.store_string(text)
		f.close()
	_saved_id = TrackLibrary.EXAMPLE_PREFIX + _example
	_fill_load_menu()
	_flash(Lang.t("EXAMPLE TRACK SAVED: %s (COMMIT IT)") % path + "  " + Lang.t("COPY: %s") % own)


## Renames the saved file of the loaded track to the name in the name field
## (the file keeps its content, unsaved changes stay in the editor).
func _act_rename() -> void:
	if model.official != "" or _example != "":
		_flash(Lang.t("NOT FOR AN OFFICIAL TRACK"))
		return
	var data := TrackLibrary.load_custom(_saved_id) if _saved_id != "" else {}
	if data.is_empty():
		_flash(Lang.t("NOT SAVED: %s") % track_name)
		return
	var new_id := _file_id()
	if new_id == _saved_id:
		_flash(Lang.t("TYPE THE NEW NAME FIRST"))
		return
	if FileAccess.file_exists(TrackLibrary.custom_path(new_id)):
		_flash(Lang.t("NAME ALREADY TAKEN: %s") % track_name)
		return
	data["name"] = track_name
	if data.has("def"):
		data["def"]["name"] = track_name
	var f := FileAccess.open(TrackLibrary.custom_path(new_id), FileAccess.WRITE)
	if f == null:
		_flash(Lang.t("COULD NOT SAVE"))
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	TrackLibrary.delete_custom(_saved_id)
	_saved_id = new_id
	_fill_load_menu()
	_flash(Lang.t("RENAMED: %s") % track_name)


## Deletes the saved file of the loaded track (after a question); the layout
## stays in the editor and can be saved again.
func _act_delete() -> void:
	if model.official != "" or _example != "":
		_flash(Lang.t("NOT FOR AN OFFICIAL TRACK"))
		return
	var id := _saved_id if _saved_id != "" else _file_id()
	if not FileAccess.file_exists(TrackLibrary.custom_path(id)):
		_flash(Lang.t("NOT SAVED: %s") % track_name)
		return
	var shown := str(TrackLibrary.load_custom(id).get("name", track_name))
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = Lang.t("DELETE THE TRACK \"%s\"?") % shown
	dlg.ok_button_text = Lang.t("DELETE")
	dlg.cancel_button_text = Lang.t("CANCEL")
	dlg.confirmed.connect(func():
		var ok := TrackLibrary.delete_custom(id)
		if ok:
			_saved_id = ""
		_fill_load_menu()
		_flash(Lang.t("DELETED: %s") % shown if ok else Lang.t("COULD NOT DELETE")))
	dlg.visibility_changed.connect(func():
		if not dlg.visible:
			dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()


func _act_load(index: int) -> void:
	if index <= 0:
		return
	var id := str(_load_menu.get_item_metadata(index))
	var data := _load_data(id)
	_load_menu.select(0)
	if data.is_empty():
		return
	_set_mode("plan")
	model = TrackEditorModel.from_dict(data)
	track_name = str(data.get("name", track_name))
	_name_edit.text = track_name
	_saved_id = id
	_example = id.trim_prefix(TrackLibrary.EXAMPLE_PREFIX) if TrackLibrary.is_example(id) else ""
	if model.has_start:
		view_center = model.start
	_set_mode("plan")
	_update()


func _act_new() -> void:
	_set_mode("plan")
	model = TrackEditorModel.new()
	_saved_id = ""
	_example = ""
	_set_mode("plan")
	_update()


## Reverses the direction of the closed lap (the start line stays; drag it
## onto a straight if a curve follows it now).
func _act_reverse() -> void:
	if not model.closed:
		_flash(Lang.t("CLOSE THE LAP FIRST"))
		return
	_set_mode("plan")
	model.reverse()
	_marked = Vector2i(-1, -1)
	_mark_anchor = -1
	_update()


func _act_test() -> void:
	if not model.closed:
		_flash(Lang.t("CLOSE THE LAP FIRST"))
		return
	_act_save()
	# admin: the official / example track itself (saved just now); else the own file
	var id := _file_id()
	if admin and model.official != "":
		id = model.official
	elif admin and _example != "":
		id = TrackLibrary.EXAMPLE_PREFIX + _example
	var req := {"track": id, "opponent": -1, "league": false, "super": false, "holes": 0, "from_editor": id}
	# a point selected (blue) in the height stage: the drive starts before it
	if _mode == "height" and _h3d.point > 0 and _h3d.point < model.points().size() - 1:
		req["start_x"] = float(model.points()[_h3d.point][0])
	start_race.emit(req)


# --- height stage ----------------------------------------------------------------------

func _toggle_mode() -> void:
	_set_mode("plan" if _mode == "height" else "height")
	_update()


func _set_mode(m: String) -> void:
	if m == "height" and not model.closed:
		_flash(Lang.t("CLOSE THE LAP FIRST"))
		return
	if m == _mode:
		return
	_mode = m
	_nav.visible = m == "height"
	if m == "height":
		if view == null:
			view = EditorView.new(XrManager.desktop_camera)
		XrManager.free_look = false
		_h3d = HeightEditor3D.new()
		_h3d.track_cursor = view.dome != null      # VR: the pointer is drawn in 3D
		_h3d.setup(model, view, track_name)
		# deferred: the parent may still be setting up its children (VR host)
		(world_parent if world_parent != null else get_parent()).add_child.call_deferred(_h3d)
		_h3d.dragged.connect(func(): _info.text = _height_info())
		_h3d.edited.connect(_update)
		_h3d.selected.connect(_update)
		_nav.model = model
		_nav.editor3d = _h3d
		_fit_window()      # the whole window / sphere now
		_nav.fit()
	else:
		_close_3d()
		if is_inside_tree():
			_fit_window()


## The 3D height editor (null outside the height stage).
func height_editor() -> HeightEditor3D:
	return _h3d


## Whether screen point pos is on a control (VR: the pointer stays on the
## screen sphere there): the top bar, the navigation window, an open menu or
## dialog; in the plan stage all of the plan.
func ui_at(pos: Vector2) -> bool:
	if _mode != "height":
		return true
	for w in get_viewport().get_embedded_subwindows():
		if w.visible and Rect2(Vector2(w.position), Vector2(w.size)).has_point(pos):
			return true
	return _bar.get_global_rect().has_point(pos) or (_nav.visible and _nav.get_global_rect().has_point(pos))


func _close_3d() -> void:
	if _h3d:
		_h3d.queue_free()
		_h3d = null
	XrManager.free_look = true


func _exit_tree() -> void:
	_close_3d()


func _height_key(k: InputEventKey) -> bool:
	match k.keycode:
		KEY_ESCAPE:
			if not model.undo_height():
				_flash(Lang.t("NOTHING TO UNDO"))
				return true
			_h3d.wave = -1
			_h3d.hold = []
			_h3d.select_point(mini(_h3d.point, model.points().size() - 1))
		KEY_W:
			if not _h3d.add_wave_at_mouse():
				_flash(Lang.t("POINT AT THE ROAD FIRST"))
				return true
		KEY_U:
			if not _h3d.add_hold_at_mouse():
				_flash(Lang.t("POINT AT A STRAIGHT NEXT TO A BANKED CURVE"))
				return true
		KEY_LEFT, KEY_RIGHT when not _h3d.hold.is_empty():
			var hx := model.hold_x(_h3d.hold[0], _h3d.hold[1])
			model.move_hold(_h3d.hold[0], _h3d.hold[1], hx + (1.0 if k.keycode == KEY_RIGHT else -1.0) * (4.0 if k.shift_pressed else 1.0))
		KEY_UP, KEY_DOWN when _h3d.loop >= 0 and _h3d.loop < model.pieces.size():
			var step := TrackEditorModel.LOOP_R_STEP * (4.0 if k.shift_pressed else 1.0)
			var r := TrackEditorModel.loop_radius(model.pieces[_h3d.loop]) + (step if k.keycode == KEY_UP else -step)
			if not model.set_loop_radius(_h3d.loop, r):
				_flash(Lang.t("LOOP RADIUS: %d TO %d M") % [int(TrackEditorModel.LOOP_R_MIN), int(TrackEditorModel.LOOP_R_MAX)])
				return true
		KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT when _h3d.wave >= 0 and _h3d.wave < model.waves.size():
			var w: Array = model.waves[_h3d.wave]
			var step := TrackEditorModel.WAVE_STEP if k.keycode in [KEY_UP, KEY_DOWN] else 1.0
			var dx: float = {KEY_LEFT: -1.0, KEY_RIGHT: 1.0}.get(k.keycode, 0.0) * (4.0 if k.shift_pressed else 1.0)
			var dh: float = {KEY_UP: step, KEY_DOWN: -step}.get(k.keycode, 0.0)
			_h3d.wave = model.set_wave(_h3d.wave, float(w[0]) + dx, float(w[2]) + dh)
		KEY_UP, KEY_DOWN:
			var pt := _h3d.point
			if pt < 0:
				return true
			var q: Array = model.points()[pt]
			var step := TrackEditorModel.HEIGHT_STEP * (4.0 if k.shift_pressed else 1.0)
			if _h3d.marked.size() > 1:
				model.move_points(_h3d.marked, 0.0, step if k.keycode == KEY_UP else -step)
			else:
				model.move_point(pt, float(q[0]), float(q[1]) + (step if k.keycode == KEY_UP else -step), true,
					TrackEditorModel.WALL_SNAP, true)
		KEY_LEFT, KEY_RIGHT:
			var pt := _h3d.point
			if pt < 0:
				return true
			var q: Array = model.points()[pt]
			if _h3d.marked.size() > 1:
				model.move_points(_h3d.marked, 1.0 if k.keycode == KEY_RIGHT else -1.0, 0.0)
			else:
				model.move_point(pt, float(q[0]) + (1.0 if k.keycode == KEY_RIGHT else -1.0), float(q[1]), true,
					TrackEditorModel.WALL_SNAP, true)
		KEY_DELETE:
			# all marked points at once (or the selected wave / hold point)
			if not _h3d.hold.is_empty():
				model.delete_hold(_h3d.hold[0], _h3d.hold[1])
				_h3d.hold = []
			elif _h3d.wave >= 0 and _h3d.wave < model.waves.size():
				model.delete_wave(_h3d.wave)
				_h3d.wave = -1
			elif not model.delete_points(_h3d.marked if not _h3d.marked.is_empty() else [_h3d.point]):
				_flash(Lang.t("SELECT A POINT FIRST"))
				return true
			else:
				_h3d.select_point(-1)
		KEY_C:
			if _h3d.point <= 0 or _h3d.point >= model.points().size() - 1:
				_flash(Lang.t("SELECT A POINT FIRST"))
				return true
			model.toggle_corner(_h3d.point)
		KEY_B:
			if _h3d.piece < 0:
				_flash(Lang.t("SELECT A PIECE FIRST"))
				return true
			if not model.toggle_flag(_h3d.piece, "bridge"):
				_flash(Lang.t("NOT POSSIBLE HERE"))
				return true
		_:
			return false
	_h3d.changed()
	return true


func _height_info() -> String:
	var t := Lang.t("LENGTH %d M  PIECES %d") % [roundi(_h3d.path.total_length), model.pieces.size()]
	var nc := _h3d.problems.filter(func(o): return o["kind"] == "crossing").size()
	var ns := _h3d.problems.filter(func(o): return o["kind"] == "steep").size()
	if nc > 0:
		t += "  " + Lang.t("CROSSINGS TOO LOW %d") % nc
	if ns > 0:
		t += "  " + Lang.t("TOO STEEP %d") % ns
	var pts := model.points()
	var pt := _h3d.point
	if _h3d.loop >= 0 and _h3d.loop < model.pieces.size():
		var r := TrackEditorModel.loop_radius(model.pieces[_h3d.loop])
		t += "   >  " + Lang.t("LOOP RADIUS %.1f M  HEIGHT %.1f M") % [r, 2.0 * r]
	elif not _h3d.hold.is_empty():
		var hp: Dictionary = model.pieces[_h3d.hold[0]]
		t += "   >  " + (Lang.t("BANKING HELD ON %d M AFTER THE CURVE") % roundi(float(hp.get("bank_out", 0.0))) if _h3d.hold[1] == "out"
			else Lang.t("BANKING FROM %d M BEFORE THE CURVE") % roundi(float(hp.get("bank_in", 0.0))))
	elif _h3d.wave >= 0 and _h3d.wave < model.waves.size():
		var w: Array = model.waves[_h3d.wave]
		t += "   >  " + Lang.t("WAVE AT %d M  HEIGHT %.1f M") % [roundi(float(w[0])), float(w[2])] + "  " \
			+ Lang.t("RIGHT EDGE" if int(w[1]) > 0 else "LEFT EDGE")
	elif pt == 0 or pt == pts.size() - 1:
		t += "   >  " + Lang.t("START HEIGHT %.1f M") % model.base
	elif pt > 0:
		t += "   >  " + Lang.t("POINT AT %d M  HEIGHT %.1f M") % [roundi(pts[pt][0]), float(pts[pt][1])]
		if _h3d.marked.size() > 1:
			t += "  " + Lang.t("%d POINTS MARKED") % _h3d.marked.size()
		if pts[pt][2]:
			t += "  " + Lang.t("CORNER")
	elif _h3d.piece >= 0:
		var p: Dictionary = model.pieces[_h3d.piece]
		t += "   >  #%d %s" % [_h3d.piece, _piece_text(p)]
		if p.get("bridge", false):
			t += "  " + Lang.t("DRAWBRIDGE")
	return t
