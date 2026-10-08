class_name TrackEditor
extends Control
## Track editor, plan view (desktop only, mouse + keyboard). Logic in
## TrackEditorModel; this node draws the plan and turns clicks into pieces.
##   left click   start point / first direction / place the previewed piece
##   Esc          remove the last piece (Ctrl+Z / Ctrl+Y undo / redo)
##   O, Shift+O   loop (shifted to the right / left)
##   wheel        zoom, right mouse button: pan
## Near the start the closing pieces are previewed in green; a click closes
## the lap. Closed tracks can be saved, test-driven and raced in practice.
##
## Heights (Tab / button, closed lap only): the profile strip shows the
## height along the lap (loops take no room there) as a spline through free
## points; at first only the start and the end of the lap (always at the same
## height). Click in the strip: new point, drag it; only a right click
## removes one; C kink at the point; Up/Down (Shift: x4) its height. The
## spline is kept within MAX_SLOPE (100 %). Dragged on by force under (or over) a neighbour, a
## point snaps there as a vertical wall: wall down + wall up = pit (floor on
## the ground: the ground), wall down alone = ski jump. Dragged away to the
## side again it is a spline point. B drawbridge (piece selected in the
## plan), Esc undo, V 3D preview (drag = turn, wheel = zoom).
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
const PREVIEW_RATE := 4.0               # 3D preview updates per second while dragging
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

# height stage
var _mode := "plan"              # plan, height
var _path: TrackPath
var _problems: Array = []
var _profile: HeightProfile     # holds the selected point and piece
var _orbiting := false
var _preview_dirty := false              # a dragged point moved since the last preview
var _preview_t := 0.0
var _preview_box: EditorPreview
var _mode_btn: Button

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
		# debug / screenshots: straight into the height stage with the 3D preview
		_set_mode("height")
		_preview_box.visible = true
		_profile.piece = mini(3, model.pieces.size() - 1)
		_layout_preview()
		_rebuild_preview()
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
	# profile strip and 3D preview of the height stage
	_profile = HeightProfile.new()
	_profile.model = model
	_profile.visible = false
	_profile.dragged.connect(func():
		_preview_dirty = true
		_info.text = _height_info())
	_profile.edited.connect(func():
		_preview_dirty = false
		_rebuild_path(true)
		_update())
	_profile.selected.connect(func():
		grab_focus()
		_update())
	add_child(_profile)
	_preview_box = EditorPreview.new()
	add_child(_preview_box)


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
	if _mode == "height" and _height_mouse(event):
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
				_click(to_world(mb.position))
			MOUSE_BUTTON_RIGHT:
				_panning = true
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				var before := to_world(mb.position)
				zoom = clampf(zoom * (1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.08, 12.0)
				view_center += before - to_world(mb.position)
				_update()
	elif event is InputEventMouseButton and not event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		_panning = false
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


func _click(w: Vector2) -> void:
	if not model.has_start:
		model.set_start(w.snapped(Vector2.ONE * TrackEditorModel.GRID))
	elif model.start_dir == Vector2.ZERO:
		model.place_first(w)
	elif not model.closed and not _preview.is_empty():
		model.place(_preview, _preview_closes)
		if model.closed:
			_flash(Lang.t("LAP CLOSED - SAVE OR TEST DRIVE"))
	_update()


# --- state -> picture -----------------------------------------------------------------

func _update() -> void:
	_mode_btn.text = Lang.t("PLAN") if _mode == "height" else Lang.t("HEIGHTS")
	_status.position = Vector2(12, size.y - 34)
	_layout_preview()
	_profile.place(Rect2(10, size.y - 250, size.x - 20, 200))
	if _mode == "height":
		_info.text = _height_info()
		if _preview_box.visible:
			_preview_box.set_focus(_preview_focus())   # follows the selected point / piece
		_status.text = Lang.t("CLICK = POINT  PULL HARD UNDER A NEIGHBOUR = WALL  RIGHT CLICK = REMOVE  C KINK  UP/DOWN HEIGHT  B BRIDGE  ESC UNDO  V 3D")
		queue_redraw()
		_profile.queue_redraw()
		return
	_preview = []
	_preview_closes = false
	if model.near_start(_mouse_world):
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
		_status.text = Lang.t("LAP CLOSED - SAVE OR TEST DRIVE (ESC REOPENS)")
	else:
		_status.text = Lang.t("CLICK = PLACE  ESC = REMOVE LAST  O / SHIFT+O = LOOP  WHEEL = ZOOM  RIGHT MOUSE = MOVE")
	queue_redraw()


func _info_text() -> String:
	var t := Lang.t("LENGTH %d M  PIECES %d") % [roundi(model.total_length()), model.pieces.size()]
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
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	_draw_grid()
	if _mode == "height":
		_draw_heights()
		return
	var pos := model.start
	var dir := model.start_dir
	var k := 0
	for p in model.pieces:
		var col := ROAD_AUTO if p.get("auto", false) else (ROAD_A if k % 2 == 0 else ROAD_B)
		_draw_piece(pos, dir, p, col)
		var e := TrackEditorModel.advance(pos, dir, p)
		pos = e[0]
		dir = e[1]
		k += 1
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
	model = TrackEditorModel.from_dict(data)
	_profile.model = model
	track_name = str(data.get("name", track_name))
	_name_edit.text = track_name
	_saved_id = id
	if model.has_start:
		view_center = model.start
	_set_mode("plan")
	_update()


func _act_new() -> void:
	model = TrackEditorModel.new()
	_profile.model = model
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
	_mode = m
	_profile.reset()
	_profile.visible = m == "height"
	if m == "height":
		_rebuild_path(true)
	else:
		_preview_box.visible = false


func _rebuild_path(full: bool) -> void:
	_path = TrackPath.new(model.to_def(track_name))
	_profile.set_path(_path)
	_problems = model.problems(_path)
	if full and _preview_box.visible:
		_rebuild_preview()


func _preview_rect() -> Rect2:
	return Rect2(size.x * 0.52, 76, size.x * 0.48 - 10, size.y * 0.5 - 70)


func _layout_preview() -> void:
	var r := _preview_rect()
	_preview_box.position = r.position
	_preview_box.size = r.size


## Plan point -> nearest piece.
func _piece_at_plan(w: Vector2) -> int:
	var v := (w - model.start).rotated(-Vector2(0, -1).angle_to(model.start_dir))
	var best := 0
	var best_d := INF
	for i in _path.n:
		var d := Vector2(_path.center[i].x, _path.center[i].z).distance_squared_to(v)
		if d < best_d:
			best_d = d
			best = i
	return _path.piece_of[best] if best_d < 400.0 else -1


## Mouse in the height stage outside the profile strip (which takes its own):
## the 3D preview (drag = turn, wheel = zoom) and pieces picked in the plan.
func _height_mouse(event: InputEvent) -> bool:
	var prev := _preview_rect()
	if event is InputEventMouseMotion:
		if _orbiting:
			_preview_box.orbit((event as InputEventMouseMotion).relative)
			return true
		return false    # panning etc. of the plan
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_orbiting = false
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			grab_focus()
			if _preview_box.visible and prev.has_point(mb.position):
				_orbiting = true
			else:
				_profile.piece = _piece_at_plan(to_world(mb.position))
				_profile.point = -1
				_profile.show_piece(_profile.piece)
			_update()
			return true
		if (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN) and _preview_box.visible and prev.has_point(mb.position):
			_preview_box.zoom(0.87 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.15)
			return true
	return false


func _height_key(k: InputEventKey) -> bool:
	match k.keycode:
		KEY_ESCAPE:
			if not model.undo_height():
				_flash(Lang.t("NOTHING TO UNDO"))
			_profile.point = mini(_profile.point, model.points().size() - 1)
		KEY_V:
			_preview_box.visible = not _preview_box.visible
			if _preview_box.visible:
				_rebuild_preview()
		KEY_UP, KEY_DOWN:
			var pt := _profile.point
			if pt < 0:
				return true
			var q: Array = model.points()[pt]
			var step := TrackEditorModel.HEIGHT_STEP * (4.0 if k.shift_pressed else 1.0)
			model.move_point(pt, float(q[0]), float(q[1]) + (step if k.keycode == KEY_UP else -step))
		KEY_C:
			if _profile.point <= 0 or _profile.point >= model.points().size() - 1:
				_flash(Lang.t("SELECT A POINT FIRST"))
			elif not model.toggle_corner(_profile.point):
				_flash(Lang.t("NOT POSSIBLE - TOO STEEP"))
		KEY_B:
			if _profile.piece < 0:
				_flash(Lang.t("SELECT A PIECE FIRST"))
				return true
			model.toggle_flag(_profile.piece, "bridge")
		_:
			return false
	_rebuild_path(true)
	return true


func _height_info() -> String:
	var t := Lang.t("LENGTH %d M  PIECES %d") % [roundi(_path.total_length), model.pieces.size()]
	var nc := _problems.filter(func(o): return o["kind"] == "crossing").size()
	var ns := _problems.filter(func(o): return o["kind"] == "steep").size()
	if nc > 0:
		t += "  " + Lang.t("CROSSINGS TOO LOW %d") % nc
	if ns > 0:
		t += "  " + Lang.t("TOO STEEP %d") % ns
	var pts := model.points()
	var pt := _profile.point
	if pt == 0 or pt == pts.size() - 1:
		t += "   >  " + Lang.t("START HEIGHT %.1f M") % model.base
	elif pt > 0:
		t += "   >  " + Lang.t("POINT AT %d M  HEIGHT %.1f M") % [roundi(pts[pt][0]), float(pts[pt][1])]
		if pts[pt][2]:
			t += "  " + Lang.t("CORNER")
	elif _profile.piece >= 0:
		var p: Dictionary = model.pieces[_profile.piece]
		t += "   >  #%d %s" % [_profile.piece, _piece_text(p)]
		if p.get("bridge", false):
			t += "  " + Lang.t("DRAWBRIDGE")
	return t


func _draw_heights() -> void:
	# plan, coloured by height; the selected piece red. Drawn from low to
	# high, so at crossings the upper road covers the lower one
	var width := maxf(2.0, TrackPath.ROAD_WIDTH * zoom)
	var order := []
	for i in range(0, _path.n, 2):
		if _path.road[i] == 1:
			order.append(i)
	order.sort_custom(func(p, q): return _path.center[p].y < _path.center[q].y)
	for i in order:
		var j := mini(i + 2, _path.n - 1) if i + 2 < _path.n else 0
		var a := to_screen(model.path_to_plan(_path.center[i]))
		var b := to_screen(model.path_to_plan(_path.center[j]))
		draw_line(a, b, HeightProfile.PIECE_ON if _path.piece_of[i] == _profile.piece else HeightProfile.height_color(_path.center[i].y), width)
	for o in _problems:
		draw_arc(to_screen(o["pos"]), maxf(10.0, TrackPath.ROAD_WIDTH * zoom), 0.0, TAU, 24,
			CROSSING if o["kind"] == "crossing" else STEEP, 3.0)
	_draw_start()


# --- 3D preview -------------------------------------------------------------------------

## path: while a point is dragged a path of its own (the editor's _path,
## its checks and the profile scale follow only on release).
func _rebuild_preview(path: TrackPath = null) -> void:
	_preview_box.build(path if path != null else _path)
	_preview_box.set_focus(_preview_focus())


## What the 3D preview looks at: the selected (light blue) profile point,
## else the middle of the selected (red) piece; null: the whole track.
func _preview_focus() -> Variant:
	if _profile.point >= 0:
		var q: Array = model.points()[mini(_profile.point, model.points().size() - 1)]
		var best := 0
		for i in _path.n:
			if _path.loop_mask[i] == 0 and absf(_path.px[i] - float(q[0])) < absf(_path.px[best] - float(q[0])):
				best = i
		var c := _path.center[best]
		return Vector3(c.x, float(q[1]), c.z)
	var sel := _profile.piece
	if sel >= 0 and sel < _path.pieces.size():
		var pc: Dictionary = _path.pieces[sel]
		return _path.center[(int(pc["i0"]) + int(pc["i1"])) / 2]
	return null


func _process(dt: float) -> void:
	# while dragging: the preview follows PREVIEW_RATE times a second
	_preview_t += dt
	if _preview_dirty and _profile.dragging() and _preview_box.visible and _preview_t >= 1.0 / PREVIEW_RATE:
		_preview_t = 0.0
		_preview_dirty = false
		_rebuild_preview(TrackPath.new(model.to_def(track_name)))
