class_name HeightSpline
extends RefCounted
## Height profile of the editor's tracks: a spline along the lap through
## points [x, h, corner, wall], between the start and the end of the lap
## (both at the start height). x is the profile coordinate (the distance
## along the lap without the loops, see TrackPath). Corner points get a kink
## instead of a smooth tangent; two points at the same x make a vertical
## wall. Static functions only (used by TrackPath, the editor and its model).

## Two points this close in x stand on one wall (float precision).
const WALL_EPS := 0.01

## Start, the points inside the lap (sorted, clipped to it) and the end, each
## [x, h, corner, wall]. wall = 1: the point stands right below / above its
## left neighbour (same x, a vertical wall between them), -1: the same on
## the left of its right neighbour.
static func points(base: float, pts: Array, length: float) -> Array:
	var out := [[0.0, base, false, 0]]
	var sorted := []
	for q in pts:
		sorted.append([float(q[0]), float(q[1]), bool(q[2]) if q.size() > 2 else false, int(q[3]) if q.size() > 3 else 0])
	sorted.sort_custom(func(a, b): return a[3] < b[3] if absf(a[0] - b[0]) < WALL_EPS else a[0] < b[0])
	for q in sorted:
		var x: float = q[0]
		if x < 0.5 or x > length - 0.5:
			continue
		var prev: Array = out[-1]
		var wall_pair: bool = absf(x - prev[0]) < WALL_EPS and out.size() > 1 and (q[3] == 1 or prev[3] == -1) \
			and not (out.size() > 2 and absf(out[-2][0] - x) < WALL_EPS)
		if wall_pair:
			q[0] = prev[0]      # exactly on the wall
		if x > prev[0] + 0.5 or wall_pair:
			out.append(q)
	out.append([length, base, false, 0])
	return out


## True if points i and i+1 form a vertical wall.
static func is_wall(pts: Array, i: int) -> bool:
	return i >= 0 and i < pts.size() - 1 and absf(float(pts[i][0]) - float(pts[i + 1][0])) < WALL_EPS


## Smooth tangent at point i (finite difference of the neighbours; the lap
## wraps, so start and end share one tangent).
static func _tangent(pts: Array, i: int) -> float:
	var last := pts.size() - 1
	var length: float = pts[last][0]
	if last < 2:
		return 0.0
	var a: Array = pts[i - 1] if i > 0 else [pts[last - 1][0] - length, pts[last - 1][1]]
	var b: Array = pts[i + 1] if i < last else [pts[1][0] + length, pts[1][1]]
	return (float(b[1]) - float(a[1])) / maxf(float(b[0]) - float(a[0]), 0.01)


## Height of the spline at profile coordinate x (Hermite segments; next to a
## corner point the segment is a parabola, between two corners a line). At
## a wall the height of the road after it.
static func height(pts: Array, x: float) -> float:
	var i := 0
	while i < pts.size() - 2 and x >= float(pts[i + 1][0]):
		i += 1
	return segment_height(pts, i, x)


## Height on segment i -> i+1 at x (clamped to the segment). The point at
## the top or foot of a wall acts as a corner on that side.
static func segment_height(pts: Array, i: int, x: float) -> float:
	return hermite_at(segment_hermite(pts, i), x)


## The Hermite segment i -> i+1 as [x0, width, h0, h1, tangent0, tangent1]
## (for evaluating it many times: hermite_at).
static func segment_hermite(pts: Array, i: int) -> Array:
	var a: Array = pts[i]
	var b: Array = pts[i + 1]
	var w := maxf(float(b[0]) - float(a[0]), 0.01)
	var sec := (float(b[1]) - float(a[1])) / w
	var ca: bool = a[2] or is_wall(pts, i - 1)
	var cb: bool = b[2] or is_wall(pts, i + 1)
	var ma := sec if ca else _tangent(pts, i)
	var mb := sec if cb else _tangent(pts, i + 1)
	if ca and not cb:
		ma = 2.0 * sec - mb
	elif cb and not ca:
		mb = 2.0 * sec - ma
	return [float(a[0]), w, float(a[1]), float(b[1]), ma, mb]


## Height of a segment from segment_hermite at x (clamped to it).
static func hermite_at(c: Array, x: float) -> float:
	var w: float = c[1]
	var u := clampf((x - float(c[0])) / w, 0.0, 1.0)
	var u2 := u * u
	var u3 := u2 * u
	return (2.0 * u3 - 3.0 * u2 + 1.0) * float(c[2]) + (u3 - 2.0 * u2 + u) * w * float(c[4]) \
		+ (-2.0 * u3 + 3.0 * u2) * float(c[3]) + (u3 - u2) * w * float(c[5])
