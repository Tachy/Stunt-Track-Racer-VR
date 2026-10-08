class_name TrackEditorModel
extends RefCounted
## Plan-view logic of the track editor (no UI, no autoloads: tested
## headless). A chain of catalogue pieces from a start pose; the piece that
## best fits the mouse; automatic run-out straights where the banking
## changes; the solver that closes the lap exactly. Pieces use the
## TrackLibrary format, so a closed layout is a drivable track.
## Plan coordinates: x = world x, y = world z (TrackPath convention).

const ANGLES := [30, 45, 60, 90, 120]
const RADII := [40, 55, 75, 100]
## Banking from the radius (deg), tight curves steep. Left curves bank the
## other way (negative), as in the league tracks.
const BANK_BY_RADIUS := {40: 36.0, 55: 30.0, 75: 24.0, 100: 18.0}
const GRID := 5.0
const MIN_STRAIGHT := 10.0
## Run-out straight for a full change of banking (+36 -> -36 deg); smaller
## changes get a share of it (at least MIN_STRAIGHT).
const TRANSITION_FULL := 40.0
## Straight run-up / run-out next to a loop.
const LOOP_RUNWAY := 30.0
## Mouse this near the start: the closing pieces are offered.
const CLOSE_RADIUS := 60.0
## Curves of the radius of the latest curve win by this much (m, default of
## candidate()): the ends of flat curves with different radii lie only a few
## metres apart. The editor scales it with the zoom.
const RADIUS_STICK := 10.0
const DEFAULT_BASE := 6.0

var start := Vector2.ZERO
var has_start := false
## Zero until the first straight (which fixes the direction) is placed.
var start_dir := Vector2.ZERO
## TrackLibrary piece dicts; "g" = placement group (one click: the piece and
## its automatic run-out), "auto" = run-out added by the editor.
var pieces: Array = []
var closed := false
var _redo: Array = []
var _next_group := 0
## Height of the start and of the end of the lap (track "base"), the free
## points of the height profile ([x, h, corner], see TrackPath "heights") and
## undo snapshots of the height stage.
var base := DEFAULT_BASE
var heights: Array = []
var _height_undo: Array = []


# --- geometry (mirrors TrackPath._layout) ------------------------------------------

static func is_curve(p: Dictionary) -> bool:
	return p.get("t", "S") == "L" or p.get("t", "S") == "R"


## Pose after piece p from (pos, dir): [pos, dir].
static func advance(pos: Vector2, dir: Vector2, p: Dictionary) -> Array:
	var t: String = p.get("t", "S")
	if t == "S":
		return [pos + dir * float(p.get("l", 40.0)), dir]
	if t == "O":
		return [pos + dir.rotated(PI * 0.5) * float(p.get("side", 1)) * TrackPath.LOOP_SHIFT, dir]
	var r := float(p.get("r", TrackPath.DEFAULT_RADIUS))
	var a := deg_to_rad(float(p.get("a", 90.0)))
	var sgn := 1.0 if t == "R" else -1.0
	var c := pos + dir.rotated(PI * 0.5) * r * sgn
	return [c + (pos - c).rotated(sgn * a), dir.rotated(sgn * a)]


## Points along piece p (about every `step` m), including both ends.
static func sample(pos: Vector2, dir: Vector2, p: Dictionary, step := 2.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var t: String = p.get("t", "S")
	if t == "S":
		var l := float(p.get("l", 40.0))
		var m := maxi(1, ceili(l / step))
		for k in m + 1:
			out.append(pos + dir * l * float(k) / m)
		return out
	if t == "O":
		var side := float(p.get("side", 1))
		for k in 41:
			var u := k / 40.0
			var fwd := TrackPath.LOOP_RADIUS * sin(TAU * u)
			var off := side * TrackPath.LOOP_SHIFT * (1.0 - cos(PI * u)) * 0.5
			out.append(pos + dir * fwd + dir.rotated(PI * 0.5) * off)
		return out
	var r := float(p.get("r", TrackPath.DEFAULT_RADIUS))
	var a := deg_to_rad(float(p.get("a", 90.0)))
	var sgn := 1.0 if t == "R" else -1.0
	var c := pos + dir.rotated(PI * 0.5) * r * sgn
	var m2 := maxi(2, ceili(r * a / step))
	for k in m2 + 1:
		out.append(c + (pos - c).rotated(sgn * a * float(k) / m2))
	return out


static func piece_length(p: Dictionary) -> float:
	var t: String = p.get("t", "S")
	if t == "S":
		return float(p.get("l", 40.0))
	if t == "O":
		return 2.0 * PI * TrackPath.LOOP_RADIUS
	return float(p.get("r", TrackPath.DEFAULT_RADIUS)) * deg_to_rad(float(p.get("a", 90.0)))


static func bank_for(t: String, radius: int) -> float:
	var b: float = BANK_BY_RADIUS.get(radius, 30.0)
	return b if t == "R" else -b


static func curve(t: String, angle: int, radius: int) -> Dictionary:
	return {"t": t, "r": radius, "a": angle, "bank": bank_for(t, radius)}


static func straight(l: float) -> Dictionary:
	return {"t": "S", "l": l}


static func snap(l: float) -> float:
	return maxf(MIN_STRAIGHT, roundf(l / GRID) * GRID)


## Length of the run-out straight needed between `last` and `next` (0 = none).
static func transition_length(last: Dictionary, next: Dictionary) -> float:
	if last.is_empty():
		return 0.0
	if next.get("t", "S") == "O":
		return LOOP_RUNWAY if last.get("t", "S") != "S" else 0.0
	if not is_curve(next):
		return 0.0
	if last.get("t", "S") == "O":
		return LOOP_RUNWAY
	if not is_curve(last):
		return 0.0
	var change := absf(float(last.get("bank", 0.0)) - float(next.get("bank", 0.0)))
	if change < 0.5:
		return 0.0
	return snap(TRANSITION_FULL * change / 72.0)


# --- state ---------------------------------------------------------------------------

func end_pose() -> Array:
	var pos := start
	var dir := start_dir
	for p in pieces:
		var e := advance(pos, dir, p)
		pos = e[0]
		dir = e[1]
	return [pos, dir]


func last_piece() -> Dictionary:
	return pieces[-1] if not pieces.is_empty() else {}


func total_length() -> float:
	var l := 0.0
	for p in pieces:
		l += piece_length(p)
	return l


## The pieces one click would add for `next`: an automatic run-out (if the
## banking changes) and the piece itself.
func group_for(next: Dictionary, after: Dictionary = {}) -> Array:
	var last := after if not after.is_empty() else last_piece()
	var g := []
	var tl := transition_length(last, next)
	if tl > 0.0:
		var s := straight(tl)
		s["auto"] = true
		g.append(s)
	g.append(next)
	return g


func set_start(p: Vector2) -> void:
	start = p
	has_start = true
	start_dir = Vector2.ZERO
	pieces.clear()
	closed = false
	_redo.clear()


## Before the first straight: direction (axis only) and length from the mouse.
func first_straight_for(mouse: Vector2) -> Array:
	var d := mouse - start
	if d.length() < 1.0:
		return []
	var dir := Vector2(signf(d.x), 0.0) if absf(d.x) >= absf(d.y) else Vector2(0.0, signf(d.y))
	return [dir, snap(absf(d.dot(dir)))]


## Best group of pieces for the mouse point: [] if nothing fits. stick: the
## head start (m) of curves with the radius of the latest curve.
func candidate(mouse: Vector2, stick := RADIUS_STICK) -> Array:
	if not has_start or closed:
		return []
	if start_dir == Vector2.ZERO:
		var f := first_straight_for(mouse)
		return [straight(f[1])] if not f.is_empty() else []
	var e := end_pose()
	var pos: Vector2 = e[0]
	var dir: Vector2 = e[1]
	# the mouse marks where the piece ends: the curve whose end is nearest
	# (by the exit direction alone, curves of one angle and different radii
	# all point the same way and the wide ones were hardly ever chosen);
	# the radius of the latest curve is kept unless the mouse clearly asks
	# for another one
	var keep := 0
	for i in range(pieces.size() - 1, -1, -1):
		if is_curve(pieces[i]):
			keep = int(pieces[i]["r"])
			break
	var best := []
	var best_err := INF
	var best_dist := INF
	for t in ["L", "R"]:
		for a in ANGLES:
			for r in RADII:
				var g := group_for(curve(t, a, r))
				var pe := pos
				var de := dir
				for p in g:
					var adv := advance(pe, de, p)
					pe = adv[0]
					de = adv[1]
				var dist := pe.distance_to(mouse)
				var err := dist + (stick if keep != 0 and r != keep else 0.0)
				if err < best_err:
					best_err = err
					best_dist = dist
					best = g
	# straight on: its length follows the mouse, so only the sideways
	# distance counts
	var along := (mouse - pos).dot(dir)
	if along > 0.0 and absf(dir.cross(mouse - pos)) <= best_dist:
		return [straight(snap(along))]
	return best


## Places a group (from candidate() / closing_group() / loop_group()).
func place(group: Array, closes := false) -> void:
	if group.is_empty():
		return
	for p in group:
		var q: Dictionary = p.duplicate()
		q["g"] = _next_group
		pieces.append(q)
	_next_group += 1
	_redo.clear()
	if closes:
		closed = true


## The first straight fixes the direction too.
func place_first(mouse: Vector2) -> void:
	var f := first_straight_for(mouse)
	if f.is_empty():
		return
	start_dir = f[0]
	place([straight(f[1])])


## A loop (with its run-up straight if needed), to the left or right.
func loop_group(side: int) -> Array:
	return group_for({"t": "O", "side": side})


## Removes the last placement group (Esc). Back to "no direction" / "no
## start" when nothing is left.
func undo() -> void:
	if pieces.is_empty():
		if start_dir != Vector2.ZERO:
			start_dir = Vector2.ZERO
		else:
			has_start = false
		return
	var g = pieces[-1].get("g", -1)
	var removed := []
	while not pieces.is_empty() and pieces[-1].get("g", -1) == g:
		removed.push_front(pieces.pop_back())
	_redo.append(removed)
	closed = false
	if pieces.is_empty():
		start_dir = Vector2.ZERO


func redo() -> void:
	if _redo.is_empty():
		return
	var g: Array = _redo.pop_back()
	if pieces.is_empty() and start_dir == Vector2.ZERO:
		return
	for p in g:
		pieces.append(p)


# --- closing the lap -----------------------------------------------------------------

## Pieces that lead exactly back onto the start (position and direction):
## one or two catalogue curves with straights before, between and after;
## two of those straights are solved for (any length), the shortest
## solution wins. [] if there is none.
func closing_group() -> Array:
	if closed or pieces.size() < 2:
		return []
	var e := end_pose()
	var p0: Vector2 = e[0]
	var d0: Vector2 = e[1]
	var need := d0.angle_to(start_dir)
	var best := []
	var best_len := INF
	# already in line with the start: one straight
	if absf(need) < 1e-3:
		var along := (start - p0).dot(d0)
		if along > 1.0 and absf(d0.cross(start - p0)) < 0.05:
			return [straight(along)]
	var curves := []
	for t in ["L", "R"]:
		for a in ANGLES:
			for r in RADII:
				curves.append(curve(t, a, r))
	for c1 in curves:
		if _turn_matches(_turn(c1), need):
			_try_close([c1], p0, d0, best, best_len)
			if not best.is_empty():
				best_len = _group_length(best)
	for c1 in curves:
		for c2 in curves:
			if _turn_matches(_turn(c1) + _turn(c2), need):
				_try_close([c1, c2], p0, d0, best, best_len)
				if not best.is_empty():
					best_len = _group_length(best)
	return best


static func _turn(c: Dictionary) -> float:
	return deg_to_rad(float(c["a"])) * (1.0 if c["t"] == "R" else -1.0)


static func _turn_matches(turn: float, need: float) -> bool:
	return absf(wrapf(turn - need, -PI, PI)) < 1e-3


static func _group_length(g: Array) -> float:
	var l := 0.0
	for p in g:
		l += piece_length(p)
	return l


## Curves cs with straight slots before / between / after them: every slot
## has its minimum (run-out rules); two slots get solved extra length so the
## chain ends on the start. Writes the shortest solution into best.
func _try_close(cs: Array, p0: Vector2, d0: Vector2, best: Array, best_len: float) -> void:
	var slots := cs.size() + 1
	var mins := []
	mins.append(transition_length(last_piece(), cs[0]))
	for k in range(1, cs.size()):
		mins.append(transition_length(cs[k - 1], cs[k]))
	mins.append(0.0)
	# direction of every slot and the end point with all slots at their minimum
	var dirs := []
	var pos := p0
	var dir := d0
	for k in slots:
		dirs.append(dir)
		pos += dir * float(mins[k])
		if k < cs.size():
			var adv := advance(pos, dir, cs[k])
			pos = adv[0]
			dir = adv[1]
	var gap := start - pos
	for i in slots:
		for j in range(i + 1, slots):
			var u: Vector2 = dirs[i]
			var v: Vector2 = dirs[j]
			var det := u.cross(v)
			if absf(det) < 1e-6:
				continue
			# x*u + y*v = gap
			var x := gap.cross(v) / det
			var y := u.cross(gap) / det
			if x < -1e-6 or y < -1e-6:
				continue
			var lens := mins.duplicate()
			lens[i] = float(lens[i]) + maxf(x, 0.0)
			lens[j] = float(lens[j]) + maxf(y, 0.0)
			var g := []
			for k in slots:
				if float(lens[k]) > 0.01:
					g.append(straight(snappedf(float(lens[k]), 0.01)))
				if k < cs.size():
					g.append(cs[k])
			var l := _group_length(g)
			if l < best_len:
				best_len = l
				best.clear()
				best.append_array(g)


## Whether the mouse is near enough to the start to offer closing.
func near_start(mouse: Vector2) -> bool:
	return has_start and not pieces.is_empty() and mouse.distance_to(start) < CLOSE_RADIUS


# --- checks ----------------------------------------------------------------------------

## Points where the layout crosses itself (to be resolved by heights later).
func crossings() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var ss := PackedFloat32Array()
	var in_loop := PackedByteArray()   # a loop passes over its own entry: wanted
	var pos := start
	var dir := start_dir
	var s := 0.0
	for p in pieces:
		var smp := sample(pos, dir, p, 3.0)
		var l := piece_length(p)
		for k in smp.size():
			pts.append(smp[k])
			ss.append(s + l * float(k) / maxi(1, smp.size() - 1))
			in_loop.append(1 if p.get("t", "S") == "O" else 0)
		var e := advance(pos, dir, p)
		pos = e[0]
		dir = e[1]
		s += l
	var total := s
	var found := PackedVector2Array()
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			var ds := absf(ss[j] - ss[i])
			if ds < 40.0 or (closed and total - ds < 40.0) or in_loop[i] == 1 or in_loop[j] == 1:
				continue
			if pts[i].distance_to(pts[j]) < TrackPath.ROAD_WIDTH:
				var m := (pts[i] + pts[j]) * 0.5
				var dup := false
				for f in found:
					if f.distance_to(m) < 20.0:
						dup = true
						break
				if not dup:
					found.append(m)
	return found


# --- heights (stage 2) -----------------------------------------------------------------

const MIN_SEPARATION := 7.0     # crossing roads at least this far apart in height
const HEIGHT_STEP := 0.5
## Height range of the profile points: tunnels down to 100 m below the ground.
const MIN_HEIGHT := -100.0
const MAX_HEIGHT := 60.0
const MIN_POINT_GAP := 2.0      # profile points at least this far apart (m)
## Steepest slope the spline may have (steeper: only vertical walls).
const MAX_SLOPE := 1.0
## Walls: a point dragged this far (m) past the slope limit snaps to a
## neighbour within WALL_SNAP (m) of the mouse.
const WALL_FORCE := 3.0
const WALL_SNAP := 4.0
## The lower point of a wall this close (m) to the ground snaps onto it.
const GROUND_SNAP := 5.0


## Profile length of one piece (loops: 0, they keep their start height).
static func profile_len(p: Dictionary) -> float:
	match p.get("t", "S"):
		"S":
			return float(p.get("l", 40.0))
		"L", "R":
			return float(p.get("r", TrackPath.DEFAULT_RADIUS)) * deg_to_rad(float(p.get("a", 90.0)))
	return 0.0


## Length of the height profile: the lap without its loops (TrackPath x).
func profile_length() -> float:
	return piece_x(pieces.size())


## Profile x where piece k starts.
func piece_x(k: int) -> float:
	var x := 0.0
	for i in k:
		x += profile_len(pieces[i])
	return x


## All profile points [x, h, corner]: 0 = start, then the free points, last =
## end of the lap (always at the start height).
func points() -> Array:
	return HeightSpline.points(base, heights, profile_length())


func _snapshot() -> void:
	_height_undo.append([pieces.duplicate(true), base, heights.duplicate(true)])
	if _height_undo.size() > 100:
		_height_undo.pop_front()


## Undo of the height stage (Esc there).
func undo_height() -> bool:
	if _height_undo.is_empty():
		return false
	var snap: Array = _height_undo.pop_back()
	pieces = snap[0]
	base = snap[1]
	heights = snap[2]
	return true


func snapshot_heights() -> void:
	_snapshot()


## Keeps the free points sorted and inside the lap.
func _tidy_heights() -> void:
	var pts := points()
	heights = pts.slice(1, pts.size() - 1)


# --- slope limit ---

## Steepest slope of the spline pts between x0 and x1 (1 m steps; walls,
## i.e. segments of no width, do not count).
static func _max_slope(pts: Array, x0: float, x1: float) -> float:
	var m := 0.0
	for i in pts.size() - 1:
		var a := float(pts[i][0])
		var b := float(pts[i + 1][0])
		if b - a < 0.01 or b < x0 or a > x1:
			continue
		var x := maxf(a, x0)
		var end := minf(b, x1)
		var prev := HeightSpline.segment_height(pts, i, x)
		while x < end - 1e-6:
			var nx := minf(x + 1.0, end)
			var h := HeightSpline.segment_height(pts, i, nx)
			m = maxf(m, absf(h - prev) / maxf(nx - x, 0.01))
			prev = h
			x = nx
	return m


## Steepest slope near point i of pts (its segments and those of the
## neighbours, whose tangents it changes; the lap wraps at the start).
static func _slope_near(pts: Array, i: int) -> float:
	var last := pts.size() - 1
	var m := _max_slope(pts, float(pts[maxi(i - 2, 0)][0]), float(pts[mini(i + 2, last)][0]))
	if i <= 2:
		m = maxf(m, _max_slope(pts, float(pts[maxi(last - 2, 0)][0]), float(pts[last][0])))
	if i >= last - 2:
		m = maxf(m, _max_slope(pts, 0.0, float(pts[mini(2, last)][0])))
	return m


## pts with point i at (x, h) (start and end: both at h).
static func _with_point(pts: Array, i: int, x: float, h: float) -> Array:
	var out := pts.duplicate(true)
	if i <= 0 or i >= out.size() - 1:
		out[0][1] = h
		out[-1][1] = h
	else:
		out[i][0] = x
		out[i][1] = h
	return out


## The other point of the wall point i stands in (-1 if none).
static func _wall_partner(pts: Array, i: int) -> int:
	if HeightSpline.is_wall(pts, i - 1):
		return i - 1
	if HeightSpline.is_wall(pts, i):
		return i + 1
	return -1


## New free point; returns its index in points() (-1 if too close to
## another). Too steep: it goes only as far up / down as the slope allows.
func add_point(x: float, h: float, record := true) -> int:
	x = roundf(x)
	h = snappedf(clampf(h, MIN_HEIGHT, MAX_HEIGHT), HEIGHT_STEP)
	var pts := points()
	for q in pts:
		if absf(float(q[0]) - x) < MIN_POINT_GAP:
			return -1
	var i := 1
	while float(pts[i][0]) < x:
		i += 1
	var on_curve := snappedf(HeightSpline.height(pts, x), HEIGHT_STEP)
	pts.insert(i, [x, on_curve, false, 0])
	var limit := maxf(MAX_SLOPE, _slope_near(pts, i))
	h = _limit_move(pts, i, Vector2(x, on_curve), Vector2(x, h), limit).y
	if record:
		_snapshot()
	heights.append([x, h, false, 0])
	_tidy_heights()
	return i


## Furthest point from a towards b (snapped) that keeps the slope near
## point i of pts within limit.
func _limit_move(pts: Array, i: int, a: Vector2, b: Vector2, limit: float) -> Vector2:
	if _slope_near(_with_point(pts, i, b.x, b.y), i) <= limit + 1e-3:
		return b
	var lo := 0.0
	var hi := 1.0
	for it in 8:
		var t := (lo + hi) * 0.5
		var c := a.lerp(b, t)
		if _slope_near(_with_point(pts, i, c.x, c.y), i) <= limit + 1e-3:
			lo = t
		else:
			hi = t
	var r := a.lerp(b, lo)
	# a move straight up / down keeps x exactly (a wall point must stay on
	# its wall, even at a fractional x from an older file)
	var rx := a.x if is_equal_approx(a.x, b.x) else roundf(r.x)
	var snapped := Vector2(rx, snappedf(r.y, HEIGHT_STEP))
	# snapping must not cross the limit
	if _slope_near(_with_point(pts, i, snapped.x, snapped.y), i) > limit + 1e-3:
		snapped = Vector2(rx, snappedf(r.y, HEIGHT_STEP) - signf(b.y - a.y) * HEIGHT_STEP)
		if _slope_near(_with_point(pts, i, snapped.x, snapped.y), i) > limit + 1e-3:
			return a
	return snapped


## Moves point i of points() towards (x, h) - the mouse:
## - start and end only change the start height (both together);
## - a free point stays between its neighbours and stops where the spline
##   would get steeper than MAX_SLOPE. Pulled on by force (WALL_FORCE past
##   that) to within WALL_SNAP of a neighbour, it snaps below / above it:
##   a vertical wall (jump, pit, ski jump);
## - the snapped point of a wall moves only up and down; pulled WALL_SNAP
##   away to its free side it is a spline point again;
## - the other point of a wall takes the wall along sideways.
## snap: WALL_SNAP, or more when the profile is drawn small (the editor
## passes a few pixels' worth).
func move_point(i: int, x: float, h: float, record := true, snap := WALL_SNAP) -> void:
	h = snappedf(clampf(h, MIN_HEIGHT, MAX_HEIGHT), HEIGHT_STEP)
	var pts := points()
	var last := pts.size() - 1
	if i <= 0 or i >= last:
		var b0 := _limit_move(pts, 0, Vector2(0, base), Vector2(0, h), maxf(MAX_SLOPE, _slope_near(pts, 0)))
		if not is_equal_approx(b0.y, base):
			if record:
				_snapshot()
			base = b0.y
		return
	var q: Array = pts[i]
	var limit := maxf(MAX_SLOPE, _slope_near(pts, i))
	var a := Vector2(float(q[0]), float(q[1]))
	var partner := _wall_partner(pts, i)
	if partner >= 0 and int(q[3]) != 0:
		var free_side := 1.0 if partner < i else -1.0
		var wx := float(pts[partner][0])
		if (x - wx) * free_side > snap:
			# pulled off the wall: a spline point again
			var lo := wx + MIN_POINT_GAP if free_side > 0.0 else float(pts[i - 1][0]) + MIN_POINT_GAP
			var hi := float(pts[i + 1][0]) - MIN_POINT_GAP if free_side > 0.0 else wx - MIN_POINT_GAP
			if lo <= hi:      # no room beside the wall: it stays
				_set_point(i, [clampf(roundf(x), lo, hi), h, q[2], 0], record)
				return
		# keep a wall at least 1 m high, on the side it is
		var ph := float(pts[partner][1])
		var sgn := signf(float(q[1]) - ph)
		if (h - ph) * sgn < 1.0:
			h = ph + sgn * 1.0
		if h < ph:
			h = _ground_snap(h)
		var bw := _limit_move(pts, i, a, Vector2(a.x, h), limit)
		if not a.is_equal_approx(bw):
			_set_point(i, [float(q[0]), bw.y, q[2], q[3]], record)   # x not via Vector2 (32 bit)
		return
	if partner >= 0:
		# the top / foot point of a wall: height on its own, the wall moves along
		var left := mini(i, partner)
		var right := maxi(i, partner)
		var nx := clampf(roundf(x), float(pts[left - 1][0]) + MIN_POINT_GAP, float(pts[right + 1][0]) - MIN_POINT_GAP)
		if h < float(pts[partner][1]):
			h = _ground_snap(h)
		var bh := _limit_move(pts, i, a, Vector2(a.x, h), limit).y
		if is_equal_approx(nx, a.x) and is_equal_approx(bh, a.y):
			return
		var hs := heights.duplicate(true)
		hs[i - 1] = [nx, bh, q[2], q[3]]
		hs[partner - 1][0] = nx
		_set_heights(hs, record)
		return
	var xc := clampf(roundf(x), float(pts[i - 1][0]) + MIN_POINT_GAP, float(pts[i + 1][0]) - MIN_POINT_GAP)
	var b := _limit_move(pts, i, a, Vector2(xc, h), limit)
	# pulled on by force next to a neighbour: snap to a wall there
	if Vector2(x, h).distance_to(b) > WALL_FORCE:
		for nb in [i - 1, i + 1]:
			if nb <= 0 or nb >= last or _wall_partner(pts, nb) >= 0:
				continue
			var n_pt: Array = pts[nb]
			if absf(x - float(n_pt[0])) <= snap and absf(h - float(n_pt[1])) >= 1.0:
				var hw := _ground_snap(h) if h < float(n_pt[1]) else h
				_set_point(i, [float(n_pt[0]), hw, q[2], 1 if nb < i else -1], record)
				return
	if not a.is_equal_approx(b):
		_set_point(i, [b.x, b.y, q[2], q[3]], record)


## Heights within GROUND_SNAP of the ground: on it.
static func _ground_snap(h: float) -> float:
	return 0.0 if absf(h) < GROUND_SNAP else h


func _set_point(i: int, q: Array, record: bool) -> void:
	var hs := heights.duplicate(true)
	hs[i - 1] = q
	_set_heights(hs, record)


## Takes the new free points only if every one of them stays (a move never
## removes a point - only delete_point does).
func _set_heights(hs: Array, record: bool) -> bool:
	var pts := HeightSpline.points(base, hs, profile_length())
	if pts.size() != hs.size() + 2:
		return false
	if record:
		_snapshot()
	heights = pts.slice(1, pts.size() - 1)
	return true


## Removes free point i of points() (start and end stay); not if the curve
## would get too steep without it (a point of a wall always goes; its
## partner is a plain point then).
func delete_point(i: int) -> bool:
	if i <= 0 or i > heights.size():
		return false
	var pts := points()
	var partner := _wall_partner(pts, i)
	if partner < 0:
		var limit := maxf(MAX_SLOPE, _slope_near(pts, i))
		var without := pts.duplicate(true)
		without.remove_at(i)
		if _slope_near(without, mini(i, without.size() - 1)) > limit + 1e-3:
			return false
	_snapshot()
	if partner >= 0:
		heights[partner - 1][3] = 0
	heights.remove_at(i - 1)
	_tidy_heights()
	return true


## Kink at free point i of points() instead of a smooth curve (not if that
## makes the curve too steep).
func toggle_corner(i: int) -> bool:
	if i <= 0 or i > heights.size():
		return false
	var pts := points()
	var limit := maxf(MAX_SLOPE, _slope_near(pts, i))
	var other := pts.duplicate(true)
	other[i][2] = not other[i][2]
	if _slope_near(other, i) > limit + 1e-3:
		return false
	_snapshot()
	heights[i - 1][2] = not heights[i - 1][2]
	return true


## Drawbridge: straights of at least 40 m only.
func toggle_flag(k: int, flag: String) -> void:
	if pieces[k].get("t", "S") != "S":
		return
	if flag == "bridge" and float(pieces[k]["l"]) < 40.0:
		return
	_snapshot()
	pieces[k][flag] = not pieces[k].get(flag, false)


## Plan coordinates of a TrackPath point (the track is built from the origin
## heading -z; the editor's start and direction place it in the plan).
func path_to_plan(v: Vector3) -> Vector2:
	return start + Vector2(v.x, v.z).rotated(Vector2(0, -1).angle_to(start_dir))


## Problems of the built track: crossings closer than MIN_SEPARATION in
## height ("crossing") and very steep road outside pits ("steep"), as
## [{pos: plan point, kind}].
func problems(path: TrackPath) -> Array:
	var out := []
	# crossings: every third sample in a 20 m grid, compared within the cell
	# and its neighbours only
	var grid := {}
	for i in range(0, path.n, 3):
		if path.loop_mask[i] == 0:
			var c := Vector2i(floori(path.center[i].x / 20.0), floori(path.center[i].z / 20.0))
			if not grid.has(c):
				grid[c] = []
			grid[c].append(i)
	for c in grid:
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var other: Array = grid.get(c + Vector2i(dx, dz), [])
				for i in grid[c]:
					for j in other:
						if j <= i or absf(path.delta_s(path.s_arr[i], path.s_arr[j])) < 40.0:
							continue
						var d := Vector2(path.center[j].x - path.center[i].x, path.center[j].z - path.center[i].z).length()
						if d < path.half_width[i] + path.half_width[j] and absf(path.center[i].y - path.center[j].y) < MIN_SEPARATION:
							_add_problem(out, path_to_plan(path.center[i]), "crossing")
	# steeper than the spline may be (older files; walls do not count)
	for i in path.n:
		var j := (i + 1) % path.n
		var d := Vector2(path.center[j].x - path.center[i].x, path.center[j].z - path.center[i].z).length()
		var rise := absf(path.center[j].y - path.center[i].y)
		if path.road[i] == 1 and path.step[i] == 0 and path.loop_mask[i] == 0 and path.loop_mask[j] == 0 \
				and rise > (MAX_SLOPE + 0.05) * maxf(d, 0.01):
			_add_problem(out, path_to_plan(path.center[i]), "steep")
	return out


static func _add_problem(out: Array, pos: Vector2, kind: String) -> void:
	for o in out:
		if o["kind"] == kind and (o["pos"] as Vector2).distance_to(pos) < 20.0:
			return
	out.append({"pos": pos, "kind": kind})


# --- export / save ---------------------------------------------------------------------

## A TrackLibrary definition of the (closed) layout. The start straight is
## piece 0; heights are flat at base until the height stage adds points.
func to_def(track_name: String) -> Dictionary:
	var ps := []
	for p in pieces:
		var q: Dictionary = p.duplicate()
		q.erase("g")
		q.erase("auto")
		ps.append(q)
	return {"name": track_name, "theme": 0, "base": base, "boost": 60, "boost_super": 45,
		"division": 1, "pieces": ps, "heights": points().slice(1, -1)}


func to_dict(track_name: String) -> Dictionary:
	return {"version": 1, "name": track_name, "start": [start.x, start.y], "start_dir": [start_dir.x, start_dir.y],
		"has_start": has_start, "closed": closed, "base": base, "heights": heights.duplicate(true),
		"pieces": pieces.duplicate(true)}


static func from_dict(d: Dictionary) -> TrackEditorModel:
	var m := TrackEditorModel.new()
	var s: Array = d.get("start", [0, 0])
	var sd: Array = d.get("start_dir", [0, 0])
	m.start = Vector2(s[0], s[1])
	m.start_dir = Vector2(sd[0], sd[1])
	m.has_start = d.get("has_start", false)
	m.closed = d.get("closed", false)
	m.base = float(d.get("base", DEFAULT_BASE))
	m.pieces = (d.get("pieces", []) as Array).duplicate(true)
	for p in m.pieces:
		m._next_group = maxi(m._next_group, int(p.get("g", 0)) + 1)
	if d.has("heights"):
		m.heights = (d["heights"] as Array).duplicate(true)
	else:
		m._heights_from_pieces()
	for p in m.pieces:
		p.erase("gap")       # older files: gap pieces are plain road now
		p.erase("no_crane")
	return m


## Older files: the end heights of the pieces become profile points.
func _heights_from_pieces() -> void:
	var h := base
	var x := 0.0
	for k in pieces.size():
		var p: Dictionary = pieces[k]
		x += profile_len(p)
		if p.get("t", "S") != "O" and p.has("h") and k < pieces.size() - 1 and not is_equal_approx(float(p["h"]), h):
			heights.append([x, float(p["h"]), p.get("p", "") == "kick" or p.get("p", "") == "lin"])
		h = float(p.get("h", h))
		for key in ["h", "p", "bump"]:
			p.erase(key)
	_tidy_heights()
