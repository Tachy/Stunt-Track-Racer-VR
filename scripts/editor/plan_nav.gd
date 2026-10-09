class_name PlanNav
extends Control
## Navigation window of the 3D height editor (top left): the plan coloured by
## height, the selected piece red, the problems, the start and the camera
## (where it stands and where it looks).
##   left click   select the piece there (the camera turns around it)
##   right mouse  push the plan, wheel: zoom

signal piece_clicked(k: int)

const BG := Color(0, 0, 0, 0.6)
const FRAME := Color(1, 1, 1, 0.35)
const CAMERA := Color("#4fd8ff")
const MIN_ZOOM := 0.02
const MAX_ZOOM := 8.0

var model: TrackEditorModel
var editor3d: HeightEditor3D
var zoom := 0.2                   # pixels per metre
var center := Vector2.ZERO        # plan point in the middle
var _panning := false
var _for_path: TrackPath          # the path the cache below was made for
var _plan := PackedVector2Array() # plan point of every sample
var _order := PackedInt32Array()  # road samples (every second), low to high


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


## Shows the whole track.
func fit() -> void:
	_cache()
	if _plan.is_empty():
		return
	var r := Rect2(_plan[0], Vector2.ZERO)
	for p in _plan:
		r = r.expand(p)
	center = r.get_center()
	zoom = clampf(minf(size.x / maxf(r.size.x + 40.0, 1.0), size.y / maxf(r.size.y + 40.0, 1.0)), MIN_ZOOM, MAX_ZOOM)


func _cache() -> void:
	var path := editor3d.path
	if path == _for_path:
		return
	_for_path = path
	_plan.resize(path.n)
	for i in path.n:
		_plan[i] = model.path_to_plan(path.center[i])
	var order := []
	for i in range(0, path.n, 2):
		if path.road[i] == 1:
			order.append(i)
	order.sort_custom(func(p, q): return path.center[p].y < path.center[q].y)
	_order = PackedInt32Array(order)


func to_screen(w: Vector2) -> Vector2:
	return (w - center) * zoom + size * 0.5


func to_world(s: Vector2) -> Vector2:
	return (s - size * 0.5) / zoom + center


## Nearest piece to a plan point (-1 if none within 20 m).
func piece_at(w: Vector2) -> int:
	_cache()
	var best := -1
	var best_d := 400.0
	for i in _plan.size():
		var d := _plan[i].distance_squared_to(w)
		if d < best_d:
			best_d = d
			best = i
	return editor3d.path.piece_of[best] if best >= 0 else -1


func _process(_dt: float) -> void:
	if is_visible_in_tree():
		queue_redraw()     # the camera moves


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		accept_event()
	if event is InputEventMouseMotion:
		if _panning:
			center -= (event as InputEventMouseMotion).relative / zoom
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var k := piece_at(to_world(mb.position))
				if k >= 0:
					piece_clicked.emit(k)
		MOUSE_BUTTON_RIGHT:
			_panning = mb.pressed
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var before := to_world(mb.position)
				zoom = clampf(zoom * (1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), MIN_ZOOM, MAX_ZOOM)
				center += before - to_world(mb.position)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if editor3d == null or editor3d.path == null:
		return
	_cache()
	var path := editor3d.path
	# drawn from low to high: at crossings the upper road covers the lower one
	var width := maxf(2.0, TrackPath.ROAD_WIDTH * zoom)
	for i in _order:
		var j := i + 2 if i + 2 < path.n else 0
		var col := HeightEditor3D.PIECE_ON if path.piece_of[i] == editor3d.piece else HeightEditor3D.line_color(path.center[i].y)
		draw_line(to_screen(_plan[i]), to_screen(_plan[j]), col, width)
	for o in editor3d.problems:
		draw_arc(to_screen(o["pos"]), maxf(6.0, TrackPath.ROAD_WIDTH * zoom), 0.0, TAU, 20,
			HeightEditor3D.PROBLEM_CROSSING if o["kind"] == "crossing" else HeightEditor3D.PROBLEM_STEEP, 2.0)
	# the selected point
	if editor3d.point >= 0:
		var pp := editor3d.point_pos(editor3d.point)
		draw_circle(to_screen(model.path_to_plan(pp)), 4.0, CAMERA)
	# start
	var s := to_screen(model.start)
	var n := model.start_dir.rotated(PI * 0.5) * maxf(6.0, TrackPath.HALF_WIDTH * zoom)
	draw_line(s - n, s + n, Color.WHITE, 2.0)
	# the camera: where it stands and where it looks
	var e := editor3d.eye()
	var ce := to_screen(model.path_to_plan(e))
	var look := to_screen(model.path_to_plan(editor3d.look_at_point())) - ce
	if look.length() > 1.0:
		var d := look.normalized()
		var side := d.orthogonal() * 7.0
		draw_colored_polygon(PackedVector2Array([ce + d * 12.0, ce + side, ce - side]), CAMERA)
		draw_line(ce, ce + look, Color(CAMERA, 0.4), 1.0)
	else:
		draw_circle(ce, 5.0, CAMERA)
	draw_rect(Rect2(Vector2.ZERO, size), FRAME, false, 1.0)
