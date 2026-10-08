class_name HeightProfile
extends Control
## Profile strip of the track editor's height stage: the height along the lap
## (loops take no room there) as a spline through the model's points, drawn
## at a fixed ratio (PROFILE_ASPECT) and pushed sideways with the right mouse
## button; a lap shorter than the strip is cut on the right.
##   left click   a point: select and drag it; elsewhere: a new point there
##   right click  a point: delete it; elsewhere: push the profile sideways
## Dragged on by force under (or over) a neighbour, a point snaps there as a
## vertical wall (see TrackEditorModel.move_point).

## A point moved while dragging (the track itself is not rebuilt yet).
signal dragged
## Points changed for good (drag released, point deleted): rebuild the track.
signal edited
## A point or a piece was selected by a click.
signal selected

const WALL_LINE := Color("#ffd400")     # vertical walls and their lower points
const POINT_ON := Color("#4fd8ff")      # selected / hovered point
const PIECE_ON := Color("#e0302a")      # selected piece (also in the plan)
const PROFILE_ASPECT := 4.0             # metres along per metre of height
const BG := Color(0, 0, 0, 0.55)
const ROAD := Color("#999977")          # the plan's road at height 0 (TrackEditor.ROAD_B)
const UNDERGROUND := Color("#4a3a2a")

var model: TrackEditorModel
var point := -1                   # selected point (index in model.points())
var piece := -1                   # selected piece
var _path: TrackPath
var _area := Rect2()              # room for the strip (in the editor)
var _x0 := 0.0                    # profile x (m) at the left edge of the strip
var _hr := Vector2(-10.0, 25.0)   # height range shown (see _compute_h_range)
var _drag := -1                   # point being dragged
var _drag_off := Vector2.ZERO     # point minus mouse at the click
var _pan := false                 # pushing the profile with the right mouse button
var _hover := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func():
		if _hover >= 0:
			_hover = -1
			queue_redraw())


## Road colour by height (also used for the plan of the height stage).
static func height_color(h: float) -> Color:
	if h < 0.0:
		return UNDERGROUND.lerp(Color("#2a2018"), clampf(-h / 10.0, 0.0, 1.0))
	return ROAD.lerp(Color.WHITE, clampf(h / 30.0, 0.0, 1.0))


## Room for the strip, in the coordinates of the parent.
func place(area: Rect2) -> void:
	_area = area
	_fit()


## The track the model makes now (after an edit): height range and size.
func set_path(path: TrackPath) -> void:
	_path = path
	_compute_h_range()
	_fit()


## No selection, no drag (new track, other stage).
func reset() -> void:
	point = -1
	piece = -1
	_drag = -1
	_hover = -1
	_pan = false


func dragging() -> bool:
	return _drag >= 0


## Scrolls the profile so piece k is in view.
func show_piece(k: int) -> void:
	if k < 0:
		return
	var pc: Dictionary = _path.pieces[k]
	var a := float(pc["x0"])
	var b := a + float(pc["length"])
	if a < _x0 or b > _x0 + _visible_m():
		_x0 = (a + b - _visible_m()) * 0.5
		_fit()


func _fit() -> void:
	if _path == null:
		return
	_x0 = clampf(_x0, 0.0, maxf(0.0, _path.profile_length - _visible_m()))
	position = _area.position
	size = Vector2(minf(_area.size.x, _path.profile_length * _xscale()), _area.size.y)
	queue_redraw()


func _visible_m() -> float:
	return _area.size.x / _xscale()


## Pixels per metre of height.
func _scale() -> float:
	return _area.size.y / (_hr.y - _hr.x)


## Pixels per metre along the lap: PROFILE_ASPECT metres of track as wide
## as one metre of height.
func _xscale() -> float:
	return _scale() / PROFILE_ASPECT


## Height range shown, with room to drag a point further down / up. Computed
## when the track is rebuilt (on release), not for every point drawn.
func _compute_h_range() -> void:
	var lo := -10.0
	var hi := 25.0
	for i in range(0, _path.n, 4):
		if _path.loop_mask[i] == 0:
			lo = minf(lo, _path.center[i].y - 10.0)
			hi = maxf(hi, _path.center[i].y + 5.0)
	_hr = Vector2(maxf(lo, TrackEditorModel.MIN_HEIGHT - 5.0), minf(hi, TrackEditorModel.MAX_HEIGHT + 5.0))


func _to_screen(x: float, h: float) -> Vector2:
	return Vector2((x - _x0) * _xscale(), (_hr.y - h) * _scale())


func _height_at(y: float) -> float:
	return _hr.y - y / _scale()


func _x_at(sx: float) -> float:
	return clampf(_x0 + sx / _xscale(), 0.0, _path.profile_length)


## Point (index in model.points()) under the mouse, -1 if none.
func _point_at(pos: Vector2) -> int:
	var pts := model.points()
	var best := -1
	var best_d := 8.0
	for i in pts.size():
		var d := _to_screen(float(pts[i][0]), float(pts[i][1])).distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return best


## Piece at profile x (loops have no width there).
func _piece_at_x(x: float) -> int:
	for k in _path.pieces.size():
		var pc: Dictionary = _path.pieces[k]
		if pc["type"] != "O" and x >= float(pc["x0"]) and x < float(pc["x0"]) + float(pc["length"]):
			return k
	return _path.pieces.size() - 1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		accept_event()   # not on to the plan / the desktop camera
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag >= 0:
			# only the point and the profile follow; the track follows on
			# release. The point keeps its offset to the mouse (no jump on
			# the click); snapping to / off a wall needs a few pixels at least
			var at := mm.position + _drag_off
			var snap := maxf(TrackEditorModel.WALL_SNAP, 10.0 / _xscale())
			model.move_point(_drag, _x_at(at.x), _height_at(at.y), false, snap)
			queue_redraw()
			dragged.emit()
		elif _pan:
			_x0 -= mm.relative.x / _xscale()
			_fit()
		else:
			var h := _point_at(mm.position)
			if h != _hover:
				_hover = h
				queue_redraw()
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		var x := _x_at(mb.position.x)
		var i := _point_at(mb.position)
		_drag_off = Vector2.ZERO
		if i >= 0:
			model.snapshot_heights()
			var q: Array = model.points()[i]
			_drag_off = _to_screen(float(q[0]), float(q[1])) - mb.position
		else:
			i = model.add_point(x, _height_at(mb.position.y))
		point = i
		_drag = i
		piece = _piece_at_x(x)
		queue_redraw()
		selected.emit()
	elif mb.button_index == MOUSE_BUTTON_LEFT and _drag >= 0:
		_drag = -1
		edited.emit()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		var i := _point_at(mb.position)
		if i < 0:
			_pan = true
		elif model.delete_point(i):
			point = -1
			_hover = -1
			edited.emit()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_pan = false


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, BG)
	var font := ThemeDB.fallback_font
	var grid := 5.0 if _hr.y - _hr.x < 60.0 else (10.0 if _hr.y - _hr.x < 120.0 else 20.0)
	var hh := ceilf(_hr.x / grid) * grid
	while hh <= _hr.y:
		var y := _to_screen(0.0, hh).y
		draw_line(Vector2(0, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.25 if is_zero_approx(hh) else 0.07), 2.0 if is_zero_approx(hh) else 1.0)
		if is_zero_approx(fmod(absf(hh), grid * 2.0)) and y - 12.0 > 0.0:
			draw_string(font, Vector2(4, y - 2), "%d M" % int(hh), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.5))
		hh += grid
	_draw_metre_scale(r, font)
	# piece borders, the selected piece, loops (only the visible part)
	for k in _path.pieces.size():
		var pc: Dictionary = _path.pieces[k]
		var x0 := _to_screen(float(pc["x0"]), 0.0).x
		if x0 >= 0.0 and x0 <= r.end.x:
			draw_line(Vector2(x0, 0), Vector2(x0, r.end.y), Color(1, 1, 1, 0.06), 1.0)
			if pc["type"] == "O":
				draw_arc(Vector2(x0, 12), 7.0, 0.0, TAU, 16, Color(1, 1, 1, 0.6), 2.0)
		if k == piece and pc["type"] != "O":
			var x1 := minf(_to_screen(float(pc["x0"]) + float(pc["length"]), 0.0).x, r.end.x)
			x0 = maxf(x0, 0.0)
			if x1 > x0:
				draw_rect(Rect2(x0, 0, maxf(2.0, x1 - x0), r.size.y), Color(PIECE_ON, 0.18))
	# the curve straight from the spline (cheap: follows a dragged point)
	var pts := model.points()
	var x := _x0
	var x_end := minf(_path.profile_length, _x0 + r.size.x / _xscale())
	var seg := 0
	while seg < pts.size() - 2 and x >= float(pts[seg + 1][0]):
		seg += 1
	var prev := Vector2(x, HeightSpline.segment_height(pts, seg, x))
	var px_step := 2.0 / _xscale()
	while x < x_end:
		x = minf(x + px_step, x_end)
		# walls on the way: a yellow vertical line
		while seg < pts.size() - 2 and x >= float(pts[seg + 1][0]):
			if HeightSpline.is_wall(pts, seg + 1):
				var wx := float(pts[seg + 1][0])
				var top := HeightSpline.segment_height(pts, seg, wx)
				draw_line(_to_screen(prev.x, prev.y), _to_screen(wx, top), height_color(top).lightened(0.2), 2.0)
				draw_line(_to_screen(wx, top), _to_screen(wx, float(pts[seg + 2][1])), WALL_LINE, 2.0)
				prev = Vector2(wx, float(pts[seg + 2][1]))
			seg += 1
		var h := HeightSpline.segment_height(pts, seg, x)
		draw_line(_to_screen(prev.x, prev.y), _to_screen(x, h), height_color(h).lightened(0.2), 2.0)
		prev = Vector2(x, h)
	# the points (start and end: the same height)
	for i in pts.size():
		var c := _to_screen(float(pts[i][0]), float(pts[i][1]))
		if c.x < -1.0 or c.x > r.end.x + 1.0:
			continue
		var col := Color.WHITE
		if (HeightSpline.is_wall(pts, i - 1) and float(pts[i][1]) < float(pts[i - 1][1])) \
				or (HeightSpline.is_wall(pts, i) and float(pts[i][1]) < float(pts[i + 1][1])):
			col = WALL_LINE      # the lower point of a wall
		if i == point or i == _hover or i == _drag:
			col = POINT_ON
		if pts[i][2]:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6), c + Vector2(-6, 0)]), col)
		else:
			draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), col)


## Metres along the lap (profile x) as a scale on the zero line: ticks and
## labels spaced to stay readable at the current scale.
func _draw_metre_scale(r: Rect2, font: Font) -> void:
	var k := _xscale()
	var label := 1000.0
	for step in [10.0, 20.0, 50.0, 100.0, 200.0, 500.0]:
		if step * k >= 80.0:
			label = step
			break
	var tick := label / 5.0 if label / 5.0 * k >= 8.0 else label
	var y := _to_screen(0.0, 0.0).y
	var col := Color(1, 1, 1, 0.45)
	var x := ceilf(_x0 / tick) * tick
	while x <= _path.profile_length:
		var sx := _to_screen(x, 0.0).x
		if sx > r.end.x:
			break
		var major := is_zero_approx(fmod(x, label))
		draw_line(Vector2(sx, y - (5.0 if major else 2.5)), Vector2(sx, y + (5.0 if major else 2.5)), col, 1.0)
		if major and sx + 40.0 < r.end.x:
			draw_string(font, Vector2(sx + 3.0, y + 14.0), "%d M" % roundi(x), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		x += tick
