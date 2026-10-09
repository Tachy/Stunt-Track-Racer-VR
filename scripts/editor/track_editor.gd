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
##
## Heights (Tab / button, closed lap only): the track in 3D (HeightEditor3D)
## with a see-through ground and tunnels; the height along the lap (loops
## take no room there) is a spline through free points, drawn on the road;
## at first only the start and the end of the lap (always at the same
## height). Click a point: it is selected (blue) and can be dragged (along
## the lap and up / down); double click on it: the camera turns around it;
## double click on the road: a new point; right click: remove it; C kink at the
## point; Up/Down (Shift: x4) its height. The spline is kept within
## MAX_SLOPE (100 %). Dragged on by force under (or over) a neighbour, a
## point snaps there as a vertical wall: wall down + wall up = pit (floor on
## the ground: the ground), wall down alone = ski jump. Dragged away to the
## side again it is a spline point. A click on the road marks its piece
## (B drawbridge) and leaves the camera where it is. The camera turns around
## the point double-clicked last (right mouse button; wheel = distance). Top left
## the plan (PlanNav): click = the piece there, the camera turns around it;
## right mouse = push, wheel = zoom. Esc undo.
## Below the ground the road becomes a cut and a tunnel by itself.

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
var _right_press := Vector2.ZERO

# height stage
var _mode := "plan"              # plan, height
var _h3d: HeightEditor3D
var _nav: PlanNav
var _mode_btn: Button
## Where the 3D view goes (VR: VrEditorHost; else the editor's parent) and
## how the screen maps to it (VR: the panel; else the desktop camera).
var world_parent: Node
var view: EditorView

var _name_edit: LineEdit
var _load_menu: OptionButton
var _status: Label
var _info: Label
## Id of the file the track was loaded from / last saved to ("" = none).
var _saved_id := ""


func _init(file_id := "") -> void:
	name = "TrackEditor"
	if file_id != "":
		var data := TrackLibrary.load_custom(file_id)
		if not data.is_empty():
			model = TrackEditorModel.from_dict(data)
			track_name = str(data.get("name", track_name))
			_saved_id = file_id


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


func _fit_window() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
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
	bar.position = Vector2(10, 8)
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	var title := Label.new()
	title.text = Lang.t("TRACK EDITOR")
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
	_mode_btn = _bar_button("", _toggle_mode, MODE_BUTTON)
	bar.add_child(_mode_btn)
	bar.add_child(_bar_button("TEST DRIVE", _act_test))
	bar.add_child(_bar_button("MENU", func(): leave.emit(), MENU_BUTTON))
	_info = Label.new()
	_info.position = Vector2(12, 44)
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


func _fill_load_menu() -> void:
	_load_menu.clear()
	_load_menu.add_item(Lang.t("LOAD ..."))
	if DirAccess.dir_exists_absolute(TrackLibrary.CUSTOM_DIR):
		for f in DirAccess.get_files_at(TrackLibrary.CUSTOM_DIR):
			if f.ends_with(".json"):
				_load_menu.add_item(f.get_basename())


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
		_mouse_world = to_world(mm.position)
		_update()
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				grab_focus()
				_click(to_world(mb.position), mb.shift_pressed)
			MOUSE_BUTTON_RIGHT:
				_panning = true
				_right_press = mb.position
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				var before := to_world(mb.position)
				zoom = clampf(zoom * (1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.08, 12.0)
				view_center += before - to_world(mb.position)
				_update()
	elif event is InputEventMouseButton and not event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		_panning = false
		if (event as InputEventMouseButton).position.distance_to(_right_press) < CLICK_SLOP:
			_delete_marked()
	if event is InputEventMouse:
		accept_event()   # not on to the desktop camera (right mouse = look around)


## Esc and the shortcuts come before InputManager (which would leave).
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if get_viewport().gui_get_focus_owner() == _name_edit and event.keycode != KEY_ESCAPE:
		return
	var k := event as InputEventKey
	var handled := true
	if k.keycode == KEY_TAB:
		_toggle_mode()
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
	elif k.keycode == KEY_S and k.ctrl_pressed:
		_act_save()
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


# --- state -> picture -----------------------------------------------------------------

func _update() -> void:
	_mode_btn.text = Lang.t("PLAN") if _mode == "height" else Lang.t("HEIGHTS")
	_status.position = Vector2(12, size.y - 34)
	if _mode == "height":
		_nav.position = Vector2(10, 72)
		_nav.size = Vector2(maxf(220.0, size.x * 0.28), maxf(160.0, size.y * 0.34))
		_info.text = _height_info()
		_status.text = Lang.t("CLICK = SELECT / DRAG POINT  DOUBLE CLICK = CAMERA TO POINT / NEW POINT ON ROAD  RIGHT CLICK = REMOVE  RIGHT MOUSE = TURN  WHEEL = DISTANCE  C KINK  UP/DOWN HEIGHT  B BRIDGE  ESC UNDO")
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
	_status.position = Vector2(12, size.y - 34)
	if not model.has_start:
		_status.text = Lang.t("CLICK THE START POINT")
	elif model.start_dir == Vector2.ZERO:
		_status.text = Lang.t("CLICK THE END OF THE START STRAIGHT (ACROSS OR UP/DOWN)")
	elif model.closed:
		_status.text = Lang.t("LAP CLOSED - SAVE OR TEST DRIVE (ESC REOPENS)") + "   " \
			+ Lang.t("CLICK = MARK (SHIFT: MORE)  RIGHT CLICK = DELETE MARKED")
	elif model.has_gap():
		_status.text = Lang.t("DRAW THE GAP TO THE YELLOW MARK  ESC = REMOVE LAST / UNDO THE DELETING")
	else:
		_status.text = Lang.t("CLICK = PLACE  ESC = REMOVE LAST  O / SHIFT+O = LOOP  WHEEL = ZOOM  RIGHT MOUSE = MOVE")
	queue_redraw()


func _info_text() -> String:
	var t := Lang.t("LENGTH %d M  PIECES %d") % [roundi(model.total_length()), model.pieces.size() + model.tail.size()]
	if _crossings.size() > 0:
		t += "  " + Lang.t("CROSSINGS %d") % _crossings.size()
	var desc := []
	for p in _preview:
		desc.append(_piece_text(p))
	if not desc.is_empty():
		t += "   >  " + " + ".join(desc)
	return t


static func _piece_text(p: Dictionary) -> String:
	match p.get("t", "S"):
		"S":
			return ("%s %.0f M" if fmod(float(p["l"]), 1.0) < 0.05 else "%s %.1f M") % [Lang.t("RUN-OUT") if p.get("auto", false) else Lang.t("STRAIGHT"), float(p["l"])]
		"O":
			return Lang.t("LOOP")
	return "%s %d° R%d (%d°)" % [p["t"], int(p["a"]), int(p["r"]), roundi(absf(float(p.get("bank", 0.0))))]


func _flash(text: String) -> void:
	_status.text = text


func _draw() -> void:
	if _mode == "height":
		return      # the 3D view shows through
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	_draw_grid()
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
	for c in _crossings:
		draw_arc(to_screen(c), maxf(10.0, TrackPath.ROAD_WIDTH * zoom), 0.0, TAU, 24, CROSSING, 3.0)
	if model.has_start:
		_draw_start()


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
		draw_circle(to_screen(pts[pts.size() / 2]), maxf(4.0, TrackPath.LOOP_RADIUS * zoom * 0.5), Color(col, 0.5))


func _draw_start() -> void:
	var s := to_screen(model.start)
	var d := model.start_dir if model.start_dir != Vector2.ZERO else Vector2.UP
	var n := d.rotated(PI * 0.5) * maxf(8.0, TrackPath.HALF_WIDTH * zoom)
	draw_line(s - n, s + n, Color.WHITE, 3.0)
	draw_line(s, s + d * maxf(24.0, 20.0 * zoom), Color.WHITE, 2.0)
	draw_circle(s, 4.0, Color.WHITE)


# --- actions ---------------------------------------------------------------------------

func _file_id() -> String:
	var clean := ""
	for ch in track_name.to_lower():
		clean += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	return TrackLibrary.CUSTOM_PREFIX + (clean if clean.strip_edges() != "" else "track")


func _act_save() -> void:
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


## Renames the saved file of the loaded track to the name in the name field
## (the file keeps its content, unsaved changes stay in the editor).
func _act_rename() -> void:
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
	var id := TrackLibrary.CUSTOM_PREFIX + _load_menu.get_item_text(index)
	var data := TrackLibrary.load_custom(id)
	_load_menu.select(0)
	if data.is_empty():
		return
	_set_mode("plan")
	model = TrackEditorModel.from_dict(data)
	track_name = str(data.get("name", track_name))
	_name_edit.text = track_name
	_saved_id = id
	if model.has_start:
		view_center = model.start
	_set_mode("plan")
	_update()


func _act_new() -> void:
	_set_mode("plan")
	model = TrackEditorModel.new()
	_saved_id = ""
	_set_mode("plan")
	_update()


func _act_test() -> void:
	if not model.closed:
		_flash(Lang.t("CLOSE THE LAP FIRST"))
		return
	_act_save()
	start_race.emit({"track": _file_id(), "opponent": -1, "league": false, "super": false, "holes": 0,
		"from_editor": _file_id()})


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
		_h3d.level_eye = XrManager.xr_active
		_h3d.setup(model, view, track_name)
		# deferred: the parent may still be setting up its children (VR host)
		(world_parent if world_parent != null else get_parent()).add_child.call_deferred(_h3d)
		_h3d.dragged.connect(func(): _info.text = _height_info())
		_h3d.edited.connect(_update)
		_h3d.selected.connect(_update)
		_nav.model = model
		_nav.editor3d = _h3d
		_update()
		_nav.fit()
	else:
		_close_3d()


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
			_h3d.select_point(mini(_h3d.point, model.points().size() - 1))
		KEY_UP, KEY_DOWN:
			var pt := _h3d.point
			if pt < 0:
				return true
			var q: Array = model.points()[pt]
			var step := TrackEditorModel.HEIGHT_STEP * (4.0 if k.shift_pressed else 1.0)
			model.move_point(pt, float(q[0]), float(q[1]) + (step if k.keycode == KEY_UP else -step))
		KEY_C:
			if _h3d.point <= 0 or _h3d.point >= model.points().size() - 1:
				_flash(Lang.t("SELECT A POINT FIRST"))
				return true
			if not model.toggle_corner(_h3d.point):
				_flash(Lang.t("NOT POSSIBLE - TOO STEEP"))
				return true
		KEY_B:
			if _h3d.piece < 0:
				_flash(Lang.t("SELECT A PIECE FIRST"))
				return true
			model.toggle_flag(_h3d.piece, "bridge")
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
	if pt == 0 or pt == pts.size() - 1:
		t += "   >  " + Lang.t("START HEIGHT %.1f M") % model.base
	elif pt > 0:
		t += "   >  " + Lang.t("POINT AT %d M  HEIGHT %.1f M") % [roundi(pts[pt][0]), float(pts[pt][1])]
		if pts[pt][2]:
			t += "  " + Lang.t("CORNER")
	elif _h3d.piece >= 0:
		var p: Dictionary = model.pieces[_h3d.piece]
		t += "   >  #%d %s" % [_h3d.piece, _piece_text(p)]
		if p.get("bridge", false):
			t += "  " + Lang.t("DRAWBRIDGE")
	return t
