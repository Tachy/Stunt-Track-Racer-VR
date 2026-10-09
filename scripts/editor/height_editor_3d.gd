class_name HeightEditor3D
extends Node3D
## The track editor's height stage in 3D (desktop and VR): the track with a
## see-through ground and tunnels, the height line and its points drawn on
## the road, the camera circling the point double-clicked last or the piece
## picked in the navigation window (XrManager's rig: the HMD adds the head's
## own movement in VR).
##   left click   a point: select it (blue) and drag it (along the lap and up
##                / down, on the vertical surface over the plan -
##                HeightRibbon); the road: mark its piece. The camera stays.
##   double click a point: the camera turns around it from now on;
##                the road: a new point there (not selected)
##   right click  a point: delete it; dragged: turn the camera
##   wheel        camera distance
## The point logic is TrackEditorModel's (snapping to walls, slope limit,
## undo). While a point is dragged the line follows at once, the road
## PREVIEW_RATE times a second (built in a worker thread).

## A point moved while dragging (the line follows, the road a bit later).
signal dragged
## Points changed for good (drag released, point added or deleted).
signal edited
## A point or a piece was selected.
signal selected

const WALL_LINE := Color("#ffd400")     # vertical walls and their lower points
const POINT_ON := Color("#4fd8ff")      # selected point
const PIECE_ON := Color("#e0302a")      # selected piece (also in the plan)
const PROBLEM_CROSSING := Color(1.0, 0.25, 0.2)
const PROBLEM_STEEP := Color(1.0, 0.6, 0.1)
const PREVIEW_RATE := 4.0               # road rebuilds per second while dragging
const LINE_LIFT := 0.35                 # the line above the road (m)
const LINE_WIDTH := 1.5
const LINE_STEP := 2.0                  # profile metres per line piece ...
const LINE_STEP_MAX := 10.0             # ... longer on long spline segments,
const LINE_STEPS := 120.0               # at most this many per segment
const ARROW_SPACING := 40.0             # driving direction: an arrow every ... m
const ARROW_LENGTH := 8.0
const ARROW_WIDTH := 5.5
const POINT_PX := 11.0                  # point size on the screen (pixels)
const PICK_PX := 12.0                   # a click this near a point takes it ...
const OCCLUDE_MARGIN := 0.2             # ... unless another road hides it (by more than this, m;
const SKY_DEPTH := 2000.0               # VR pointer over nothing: this far (m)
const OWN_ROAD := 20.0                  # a road this near along the lap is its own)
const CLICK_SLOP := 4.0                 # px a right click may move (else: turning)
const XRAY_ALPHA := 0.35                # line and points through walls and ground
const FOCUS_DIST := 140.0               # camera distance onto a selection
const CAM_SPEED := 5.0                  # camera travel (1/s)
const PITCH_MIN := -0.6                 # below the (see-through) ground
const PITCH_MAX := 1.5

var model: TrackEditorModel
var view: EditorView
## The track as built last (lags behind a dragged point) and its height surface.
var path: TrackPath
var ribbon: HeightRibbon
var point := -1                   # selected point (index in model.points())
var piece := -1                   # selected piece
## Problems of the built track: [{pos: plan point, kind, at: path point}].
var problems: Array = []
## Where the camera turns around (the point double-clicked last or the piece
## picked in the navigation window; null: the whole track).
var _pivot: Variant = null

var _hover := -1
## VR: how far along the mouse ray the pointer is drawn (its direction is
## the pointer's own, fixed to the viewer): the dragged point, the point or
## the road under it, the ground, else the sky far away - at the depth of
## what it points at, so both eyes agree. Worked out anew whenever the mouse
## or the camera moves.
var track_cursor := false
var cursor_depth := SKY_DEPTH
var _mouse := Vector2(-1, -1)
var _cursor_from := Transform3D()   # camera the depth was worked out for
var _drag := -1
var _drag_off := Vector2.ZERO     # point minus mouse on the surface (x, h)
var _right_moved := 0.0           # mouse travel with the right button down (px)
var _right_down := false
var _turning := false

# camera
var _yaw := 0.7
var _pitch := 0.6
var _zoom_dist := 0.0             # set by the wheel (0: automatic)
var _c := Vector3.ZERO            # look-at point and distance now ...
var _d := 0.0
var _target_c := Vector3.ZERO     # ... and where the camera travels to
var _target_d := 0.0

# the built track, rebuilt in a worker thread
var _content: Node3D
var _job := -1
var _job_full := false
var _job_out: Dictionary = {}
var _dirty := false               # a dragged point moved since the last rebuild
var _full_pending := false        # rebuild with the checks when the job is done
var _rebuild_t := 0.0

# overlay: line (+ selected piece, problems) and points, each drawn twice:
# depth-tested and faint through everything
var _line_mesh := ArrayMesh.new()
var _point_mesh := ArrayMesh.new()
var _line_dirty := true
var _static_dirty := true        # selected piece / problems changed
var _static_v := PackedVector3Array()
var _static_c := PackedColorArray()
var _seg_cache: Array = []         # [corners, colours] of the line per spline segment


func setup(m: TrackEditorModel, v: EditorView, track_name: String) -> void:
	model = m
	view = v
	name = "HeightEditor3D"
	for mesh in [_line_mesh, _point_mesh]:
		for xray in [false, true]:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = _overlay_material(xray)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
	# the first build at once (the height surface needs the path)
	var out := _build(model.to_def(track_name), model, true)
	_take(out)
	ribbon = HeightRibbon.new(path)      # the plan: it stays for the whole stage
	_retarget()


static func _overlay_material(xray: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if xray:
		mat.no_depth_test = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, XRAY_ALPHA)
		mat.render_priority = 10
	return mat


## Colour of the height line (and of the plan in the navigation window):
## bright over the 3D track - pale above the ground, ochre to rust below.
static func line_color(h: float) -> Color:
	if h < 0.0:
		return Color("#f0b860").lerp(Color("#c0582a"), clampf(-h / 60.0, 0.0, 1.0))
	return Color("#d8e8a0").lerp(Color.WHITE, clampf(h / 30.0, 0.0, 1.0))


func dragging() -> bool:
	return _drag >= 0


# --- building the track ------------------------------------------------------------

## Worker thread: the track and its world from a definition (no scene tree,
## no physics). full: the checks too.
static func _build(def: Dictionary, m: TrackEditorModel, full: bool) -> Dictionary:
	var p := TrackPath.new(def)
	var node := Node3D.new()
	node.name = "Track3D"
	node.add_child(TrackNode.new().build(p, true))
	EnvironmentBuilder.build(node, 0, p.bounds(), p.ground_holes(), TrackNode.SEE_THROUGH_ALPHA)
	var out := {"path": p, "node": node}
	if full:
		var probs := m.problems(p)
		for o in probs:
			o["at"] = _nearest_center(p, m.plan_to_path(o["pos"]))
		out["problems"] = probs
	return out


static func _nearest_center(p: TrackPath, plan: Vector2) -> Vector3:
	var best := 0
	var best_d := INF
	for i in p.n:
		var d := Vector2(p.center[i].x, p.center[i].z).distance_squared_to(plan)
		if d < best_d:
			best_d = d
			best = i
	return p.center[best]


func _take(out: Dictionary) -> void:
	if _content:
		_content.queue_free()
	_content = out["node"]
	add_child(_content)
	path = out["path"]
	if out.has("problems"):
		problems = out["problems"]
	_line_dirty = true
	_static_dirty = true


## The model changed outside (keys, undo): line, road and camera follow.
func changed() -> void:
	rebuild(true)
	_line_dirty = true
	_retarget()


## Rebuild the road (full: with the checks - after an edit).
func rebuild(full := true) -> void:
	if full:
		_full_pending = true
	else:
		_dirty = true


func _start_job(full: bool) -> void:
	var def := model.to_def("t")
	_job_full = full
	_job = WorkerThreadPool.add_task(func(): _job_out = _build(def, model, full))


func _poll_job() -> void:
	if _job >= 0 and WorkerThreadPool.is_task_completed(_job):
		WorkerThreadPool.wait_for_task_completion(_job)
		_job = -1
		_take(_job_out)
		_job_out = {}
		if _job_full:
			edited.emit()        # the checks are new: the info line follows
	if _job >= 0:
		return
	if _full_pending and _drag < 0:
		_full_pending = false
		_dirty = false
		_start_job(true)
	elif _dirty and _rebuild_t >= 1.0 / PREVIEW_RATE:
		_dirty = false
		_rebuild_t = 0.0
		_start_job(false)


func _exit_tree() -> void:
	if _job >= 0:
		WorkerThreadPool.wait_for_task_completion(_job)
		_job = -1
		if _job_out.has("node"):
			(_job_out["node"] as Node).free()


# --- selection and camera -------------------------------------------------------------

## 3D position of point i of model.points() (on the line).
func point_pos(i: int) -> Vector3:
	var q: Array = model.points()[i]
	return ribbon.point_at(float(q[0]), float(q[1])) + Vector3.UP * LINE_LIFT


## Selects point i (blue). move_camera (a double click on it): the camera
## turns around it from now on; else it stays where it is.
func select_point(i: int, move_camera := false) -> void:
	point = i
	if i >= 0:
		piece = _piece_at_x(float(model.points()[i][0]))
		if move_camera:
			_pivot = point_pos(i)
			_retarget()
	_line_dirty = true
	_static_dirty = true
	selected.emit()


## Marks piece k (B drawbridge, info line). move_camera (a click in the
## navigation window): the camera turns around its middle from now on; else
## (a click in the 3D view) it stays where it is.
func select_piece(k: int, move_camera := false) -> void:
	piece = k
	point = -1
	if move_camera and k >= 0 and k < path.pieces.size():
		var pc: Dictionary = path.pieces[k]
		_pivot = path.center[(int(pc["i0"]) + int(pc["i1"])) / 2]
		_retarget()
	_line_dirty = true
	_static_dirty = true
	selected.emit()


## Piece at profile x (loops have no length there).
func _piece_at_x(x: float) -> int:
	for k in path.pieces.size():
		var pc: Dictionary = path.pieces[k]
		if pc["type"] != "O" and x >= float(pc["x0"]) and x < float(pc["x0"]) + float(pc["length"]):
			return k
	return path.pieces.size() - 1


## What the camera turns around: _pivot (the point double-clicked last, or
## the middle of the piece picked in the navigation window - it stays put
## while that point is dragged); null: the whole track.
func focus() -> Variant:
	return _pivot


func _auto_dist() -> float:
	if focus() != null:
		return FOCUS_DIST
	var b := path.bounds()
	return maxf(b.size.x, b.size.z) * 0.9 + 60.0


func _retarget() -> void:
	var f: Variant = focus()
	_target_c = f if f != null else path.bounds().get_center()
	_target_d = _zoom_dist if _zoom_dist > 0.0 else _auto_dist()
	if _d <= 0.0:      # first view: no travel
		_c = _target_c
		_d = _target_d


## Eye position of the camera now.
func eye() -> Vector3:
	return _c + Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _d


## The point the camera looks at now.
func look_at_point() -> Vector3:
	return _c


func turn(relative: Vector2) -> void:
	_yaw -= relative.x * 0.01
	_pitch = clampf(_pitch + relative.y * 0.01, PITCH_MIN, PITCH_MAX)


## Wheel: factor < 1 closer, > 1 farther.
func zoom(factor: float) -> void:
	_zoom_dist = clampf((_auto_dist() if _zoom_dist <= 0.0 else _zoom_dist) * factor, 8.0, 5000.0)
	_target_d = _zoom_dist


func _place_camera() -> void:
	# the eye looks at the pivot, turning up / down with it too (VR: the head
	# looks around from there, 6DOF on top)
	var e := eye()
	var look := _c - e
	var b := Basis.looking_at(look if look.length_squared() > 1e-6 else Vector3.FORWARD, Vector3.UP)
	XrManager.set_base(Transform3D(b, e))


func _process(dt: float) -> void:
	_rebuild_t += dt
	_poll_job()
	if not _c.is_equal_approx(_target_c) or not is_equal_approx(_d, _target_d):
		var k := 1.0 - exp(-dt * CAM_SPEED)
		_c = _c.lerp(_target_c, k)
		_d = lerpf(_d, _target_d, k)
		if _c.distance_to(_target_c) < 0.05 and absf(_d - _target_d) < 0.05:
			_c = _target_c
			_d = _target_d
	_place_camera()
	if track_cursor and not XrManager.base_transform().is_equal_approx(_cursor_from):
		_update_cursor()      # the track moved under the pointer
	if _line_dirty:
		_line_dirty = false
		_draw_line()
	_draw_points()     # every frame: their size follows the camera


# --- input -------------------------------------------------------------------------------

## Mouse in the 3D view (not over the editor's controls). True if used.
func handle(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_mouse = mm.position
		if _drag >= 0:
			_drag_to(mm.position)
		elif _right_down:
			# by the mouse's own travel: in VR the pointer stays put meanwhile
			_right_moved += mm.relative.length()
			if _turning or _right_moved >= CLICK_SLOP:
				_turning = true
				turn(mm.relative)
		_update_cursor()
		return true
	if not (event is InputEventMouseButton):
		return false
	var mb := event as InputEventMouseButton
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_left_click(mb.position, mb.double_click)
			elif _drag >= 0:
				_drag = -1
				_update_cursor()
				rebuild(true)
				_line_dirty = true
		MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_right_down = true
				_turning = false
				_right_moved = 0.0
			else:
				if not _turning:
					var i := _point_at(mb.position)
					if i >= 0 and model.delete_point(i):
						point = -1
						_hover = -1
						rebuild(true)
						_line_dirty = true
						edited.emit()
				_right_down = false
				_turning = false
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				zoom(0.87 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.15)
		_:
			return false
	return true


func _left_click(pos: Vector2, double: bool) -> void:
	var i := _point_at(pos)
	if i >= 0:
		if not double:
			model.snapshot_heights()     # (the first click of a double click took one)
		_start_drag(i, pos)
		if double:
			select_point(i, true)      # the camera turns around it now
		return
	var hit: Variant = _road_hit(pos)
	if hit == null:
		return
	if double:
		var x := _x_of_hit(hit[0], hit[1])
		var j := model.add_point(x, HeightSpline.height(model.points(), x))
		if j >= 0:
			# only added: a click on it selects it (and moves the camera)
			if point >= j:
				point += 1       # the selected point keeps its place
			_line_dirty = true
			rebuild(true)
			edited.emit()
		return
	select_piece(path.piece_of[hit[1]])


func _start_drag(i: int, pos: Vector2) -> void:
	select_point(i)
	_drag = i
	_drag_off = Vector2.ZERO
	var q: Array = model.points()[i]
	var r := view.ray(pos)
	var h: Variant = ribbon.hit(r[0], r[1], float(q[0]))
	if h != null:
		_drag_off = Vector2(float(q[0]), float(q[1])) - h


## The point under the mouse (hover) and, in VR, the pointer's depth (see
## cursor_depth) - after the mouse or the camera moved.
func _update_cursor() -> void:
	_cursor_from = XrManager.base_transform()
	if _mouse.x < 0.0:
		return
	if _drag < 0 and not _turning:
		_hover = _point_at(_mouse)
	if not track_cursor:
		return
	var r := view.ray(_mouse)
	var from: Vector3 = r[0]
	var dir: Vector3 = r[1]
	if _drag >= 0:
		cursor_depth = from.distance_to(point_pos(_drag))
	elif _hover >= 0:
		cursor_depth = from.distance_to(point_pos(_hover))
	else:
		var hit: Variant = _road_hit_ray(from, dir)
		if hit != null:
			cursor_depth = from.distance_to(hit[0])
		elif absf(dir.y) > 1e-4 and -from.y / dir.y > 0.0:
			cursor_depth = minf(-from.y / dir.y, SKY_DEPTH)     # the ground
		else:
			cursor_depth = SKY_DEPTH


func _drag_to(pos: Vector2) -> void:
	var q: Array = model.points()[_drag]
	var r := view.ray(pos)
	var h: Variant = ribbon.hit(r[0], r[1], float(q[0]))
	if h == null:
		return
	var at: Vector2 = h + _drag_off
	# snapping to / off a wall: WALL_SNAP, or 10 pixels' worth far away
	var snap := maxf(TrackEditorModel.WALL_SNAP, 10.0 * view.pixel_metres(point_pos(_drag)))
	model.move_point(_drag, at.x, at.y, false, snap)
	_line_dirty = true
	_dirty = true
	dragged.emit()


## Point under the screen position (-1 if none). A point behind the road the
## mouse is on does not count: at a crossing a click on the upper road must
## not take a point of the road below (it shows through, but is not there).
func _point_at(pos: Vector2) -> int:
	var pts := model.points()
	var near := []          # [screen distance, index] within PICK_PX
	for i in pts.size():
		var s: Variant = view.to_screen(point_pos(i))
		if s == null:
			continue
		var d := (s as Vector2).distance_to(pos)
		if d < PICK_PX:
			near.append([d, i])
	if near.is_empty():
		return -1
	near.sort_custom(func(a, b): return a[0] < b[0])
	var eye_pos: Vector3 = view.ray(pos)[0]
	for c in near:
		# hidden only by another part of the lap (a crossing): the ray from
		# the eye to it meets a road before it that is far from it along the
		# lap. Its own road around it (the upper end of its pit or jump) does
		# not count - the point shows through there and is meant to be taken
		var p := point_pos(c[1])
		var hit: Variant = _road_hit_ray(eye_pos, (p - eye_pos).normalized())
		if hit == null or eye_pos.distance_to(hit[0]) > eye_pos.distance_to(p) - OCCLUDE_MARGIN \
				or ribbon.lap_distance(_x_of_hit(hit[0], hit[1]), float(pts[c[1]][0])) < OWN_ROAD:
			return c[1]
	return -1


## Profile x of a point p on the road between sample i and the next one
## (from _road_hit): on that very road - at a crossing not the other one,
## however near its centre line is.
func _x_of_hit(p: Vector3, i: int) -> float:
	var j := (i + 1) % path.n
	var a := path.center[i]
	var ab := path.center[j] - a
	var u := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0) if ab.length_squared() > 1e-8 else 0.0
	var xj := path.px[j] if j > 0 else path.profile_length     # the lap ends at the start
	return lerpf(path.px[i], xj, u)


## The road under the screen position: [world point, sample index] or null.
func _road_hit(pos: Vector2) -> Variant:
	var r := view.ray(pos)
	return _road_hit_ray(r[0], r[1])


## The first road a ray from `from` along dir meets: [world point, sample
## index] or null.
func _road_hit_ray(from: Vector3, dir: Vector3) -> Variant:
	var best: Variant = null
	var best_d := INF
	for i in path.n:
		# no road: gaps, and the vertical walls of pits and jumps (the
		# segment across a wall would stand in the wall and hide its foot point)
		if path.road[i] == 0 or path.step[i] == 1:
			continue
		var j := (i + 1) % path.n
		var li := path.center[i] - path.right[i] * path.half_width[i]
		var ri := path.center[i] + path.right[i] * path.half_width[i]
		var lj := path.center[j] - path.right[j] * path.half_width[j]
		var rj := path.center[j] + path.right[j] * path.half_width[j]
		for tri in [[li, lj, rj], [li, rj, ri]]:
			var p: Variant = Geometry3D.ray_intersects_triangle(from, dir, tri[0], tri[1], tri[2])
			if p != null:
				var d := from.distance_squared_to(p)
				if d < best_d:
					best_d = d
					best = [p, i]
	return best


# --- overlay ------------------------------------------------------------------------------

## The six corners of a flat band from a to b, w wide across the plan
## normal n (unlit overlay: no normals needed).
static func _band(a: Vector3, b: Vector3, n: Vector2, w: float) -> PackedVector3Array:
	var s := Vector3(n.x, 0.0, n.y) * w * 0.5
	return PackedVector3Array([a - s, b - s, b + s, a - s, b + s, a + s])


static func _six(col: Color) -> PackedColorArray:
	return PackedColorArray([col, col, col, col, col, col])


## The height line (walls yellow) and the selected piece and the problems
## (kept until they change). The line is kept per spline segment: while a
## point is dragged only the segments its move reaches are drawn anew.
func _draw_line() -> void:
	if _static_dirty:
		_static_dirty = false
		_draw_static()
	var pts := model.points()
	var nseg := pts.size() - 1
	var first := 0
	var last := nseg - 1
	if _drag >= 0 and _seg_cache.size() == nseg:
		# point i changes the tangents at i-1 .. i+1: segments i-2 .. i+1
		first = maxi(0, _drag - 2)
		last = mini(nseg - 1, _drag + 1)
	else:
		_seg_cache.resize(nseg)
	for k in range(first, last + 1):
		_seg_cache[k] = _segment_line(pts, k)
	var v := PackedVector3Array()
	var c := PackedColorArray()
	for s in _seg_cache:
		v.append_array(s[0])
		c.append_array(s[1])
	v.append_array(_static_v)
	c.append_array(_static_c)
	_line_mesh.clear_surfaces()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_COLOR] = c
	_line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## The line along spline segment k (a wall: the yellow vertical one), as
## [corners, colours].
func _segment_line(pts: Array, k: int) -> Array:
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var lift := Vector3.UP * LINE_LIFT
	var x0 := float(pts[k][0])
	var x1 := float(pts[k + 1][0])
	if HeightSpline.is_wall(pts, k):
		var n := ribbon.tangent_at(x0).orthogonal()
		v.append_array(_band(ribbon.point_at(x0, float(pts[k][1])) + lift, ribbon.point_at(x0, float(pts[k + 1][1])) + lift, n, LINE_WIDTH))
		c.append_array(_six(WALL_LINE))
		return [v, c]
	var herm := HeightSpline.segment_hermite(pts, k)
	# long segments in longer steps (at most LINE_STEPS of them): smooth
	# enough, and quick to draw anew while dragging
	var step := clampf((x1 - x0) / LINE_STEPS, LINE_STEP, LINE_STEP_MAX)
	var x := x0
	var prev := ribbon.point_at(x0, HeightSpline.hermite_at(herm, x0)) + lift
	while x < x1 - 1e-4:
		# on a grid along the lap (rounding must not keep x where it is)
		var nx := (floorf(x / step + 1e-6) + 1.0) * step
		x = minf(nx if nx > x + 1e-3 else x + step, x1)
		var h := HeightSpline.hermite_at(herm, x)
		var cur := ribbon.point_at(x, h) + lift
		v.append_array(_band(prev, cur, ribbon.tangent_at(x).orthogonal(), LINE_WIDTH))
		c.append_array(_six(line_color(h)))
		prev = cur
	# arrows in the driving direction, on a grid along the lap (they stay
	# where they are while a point is dragged)
	var xa := ceilf(x0 / ARROW_SPACING) * ARROW_SPACING
	while xa < x1:
		if xa - x0 > ARROW_LENGTH and x1 - xa > ARROW_LENGTH:
			_arrow(v, c, herm, xa)
		xa += ARROW_SPACING
	return [v, c]


## An arrow on the line at profile x, pointing along the lap (and up or
## down the slope there), darker than the line.
func _arrow(v: PackedVector3Array, c: PackedColorArray, herm: Array, x: float) -> void:
	var lift := Vector3.UP * (LINE_LIFT + 0.08)
	var h := HeightSpline.hermite_at(herm, x)
	var p := ribbon.point_at(x, h) + lift
	var d := (ribbon.point_at(x + 0.5, HeightSpline.hermite_at(herm, x + 0.5)) \
		- ribbon.point_at(x - 0.5, HeightSpline.hermite_at(herm, x - 0.5))).normalized()
	var n := ribbon.tangent_at(x).orthogonal()
	var s := Vector3(n.x, 0.0, n.y) * ARROW_WIDTH * 0.5
	var tip := p + d * ARROW_LENGTH * 0.6
	var back := p - d * ARROW_LENGTH * 0.4
	var notch := p - d * ARROW_LENGTH * 0.1     # an arrowhead with a notch
	var col := line_color(h).darkened(0.8)
	v.append_array(PackedVector3Array([back - s, tip, notch, notch, tip, back + s]))
	c.append_array(_six(col))


## The selected piece (red strips along both road edges, the line stays
## visible between them) and rings around the problems.
func _draw_static() -> void:
	var kit := MeshKit.new()
	if piece >= 0 and piece < path.pieces.size():
		var pc: Dictionary = path.pieces[piece]
		for i in range(int(pc["i0"]), int(pc["i1"])):
			if path.step[i] == 1:
				continue     # across a wall (pit, jump): the strips break off there
			var j := mini(i + 1, path.n - 1)
			var lift_i := path.up[i] * 0.12
			var lift_j := path.up[j] * 0.12
			for side: float in [-1.0, 1.0]:
				var a_i := path.center[i] + path.right[i] * side * path.half_width[i] + lift_i
				var a_j := path.center[j] + path.right[j] * side * path.half_width[j] + lift_j
				var b_i := a_i - path.right[i] * side * 1.6
				var b_j := a_j - path.right[j] * side * 1.6
				kit.quad(a_i, a_j, b_j, b_i, PIECE_ON)
	for o in problems:
		var at: Vector3 = o["at"]
		var ring := PackedVector3Array()
		for k in 24:
			var a := TAU * k / 24.0
			ring.append(at + Vector3(cos(a), 0.0, sin(a)) * TrackPath.ROAD_WIDTH * 1.2 + Vector3.UP * 1.0)
		kit.tube(ring, 0.5, 4, PROBLEM_CROSSING if o["kind"] == "crossing" else PROBLEM_STEEP, true)
	_static_v = kit.verts
	_static_c = kit.colors


## The points: squares (corners: diamonds) of a constant size on the screen.
func _draw_points() -> void:
	var kit := MeshKit.new()
	var pts := model.points()
	for i in pts.size():
		var p := point_pos(i)
		var s := POINT_PX * view.pixel_metres(p)
		var col := Color.WHITE
		if (HeightSpline.is_wall(pts, i - 1) and float(pts[i][1]) < float(pts[i - 1][1])) \
				or (HeightSpline.is_wall(pts, i) and float(pts[i][1]) < float(pts[i + 1][1])):
			col = WALL_LINE      # the lower point of a wall
		if i == point or i == _drag:
			col = POINT_ON       # blue: selected only
		if i == _hover:
			s *= 1.4             # under the mouse: a bit bigger
		if pts[i][2]:
			_diamond(kit, p, s * 0.75, col)
		else:
			kit.box(p, Vector3.ONE * s, col)
	_point_mesh.clear_surfaces()
	kit.build(_point_mesh)


static func _diamond(kit: MeshKit, c: Vector3, r: float, col: Color) -> void:
	var v := [c + Vector3(r, 0, 0), c + Vector3(0, 0, r), c + Vector3(-r, 0, 0), c + Vector3(0, 0, -r)]
	var top := c + Vector3(0, r, 0)
	var bottom := c - Vector3(0, r, 0)
	for k in 4:
		kit.tri(v[k], v[(k + 1) % 4], top, col)
		kit.tri(v[(k + 1) % 4], v[k], bottom, col)
