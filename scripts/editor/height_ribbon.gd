class_name HeightRibbon
extends RefCounted
## The height surface of the 3D height editor: the vertical surface over the
## centre line of a TrackPath (path coordinates, as TrackNode builds the
## track). A profile point (x along the lap without loops, height h) lies on
## it; a dragged point keeps to it - two degrees of freedom as in the old
## profile strip. No UI, no autoloads: tested headless.

## Profile window (m) around the dragged point a mouse ray may hit the
## surface in: the point does not jump onto another part of the track
## crossing in front of it.
const HIT_WINDOW := 80.0

var length := 0.0                       # profile length (x of the lap's end)
var _xs := PackedFloat32Array()         # profile x of the centre line points ...
var _ps := PackedVector2Array()         # ... and their plan position (x, z)


func _init(path: TrackPath) -> void:
	length = path.profile_length
	for i in path.n:
		if path.loop_mask[i] == 1:
			continue
		_xs.append(path.px[i])
		_ps.append(Vector2(path.center[i].x, path.center[i].z))
	# the lap closes: the end of the profile is the start again
	_xs.append(length)
	_ps.append(_ps[0])


## Index k of the segment k..k+1 that x lies in.
func _segment(x: float) -> int:
	x = clampf(x, 0.0, length)
	var lo := 0
	var hi := _xs.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if _xs[mid] <= x:
			lo = mid
		else:
			hi = mid
	return lo


func _u(k: int, x: float) -> float:
	var dx := _xs[k + 1] - _xs[k]
	return clampf((x - _xs[k]) / dx, 0.0, 1.0) if dx > 1e-4 else 0.0


## Plan position (x, z) at profile x.
func plan_at(x: float) -> Vector2:
	var k := _segment(x)
	return _ps[k].lerp(_ps[k + 1], _u(k, x))


## Direction of the lap (plan, unit) at profile x.
func tangent_at(x: float) -> Vector2:
	var k := _segment(x)
	var d := _ps[k + 1] - _ps[k]
	var j := k
	while d.length_squared() < 1e-6 and j > 0:     # a wall: no length there
		j -= 1
		d = _ps[j + 1] - _ps[j]
	return d.normalized() if d.length_squared() > 1e-6 else Vector2(0, -1)


## 3D position of the profile point (x, h).
func point_at(x: float, h: float) -> Vector3:
	var p := plan_at(x)
	return Vector3(p.x, h, p.y)


## Distance of x and y along the lap (it wraps at the start).
func lap_distance(x: float, y: float) -> float:
	var d := absf(x - y)
	return minf(d, length - d)


## Where a mouse ray meets the surface: Vector2(x, h), the hit within
## `window` of x_hint (along the lap) nearest to it; none there: the
## vertical plane along the lap at x_hint. null if the ray misses that too.
func hit(from: Vector3, dir: Vector3, x_hint: float, window := HIT_WINDOW) -> Variant:
	var o := Vector2(from.x, from.z)
	var d := Vector2(dir.x, dir.z)
	var best: Variant = null
	var best_d := INF
	if d.length_squared() > 1e-8:
		for k in _xs.size() - 1:
			if lap_distance(_xs[k], x_hint) > window + 2.0 and lap_distance(_xs[k + 1], x_hint) > window + 2.0:
				continue
			var a := _ps[k]
			var e := _ps[k + 1] - a
			var det := d.cross(e)
			if absf(det) < 1e-8:
				continue
			# o + t*d = a + u*e
			var t := (a - o).cross(e) / det
			var u := (a - o).cross(d) / det
			if t <= 0.0 or u < 0.0 or u > 1.0:
				continue
			var x := lerpf(_xs[k], _xs[k + 1], u)
			var dist := lap_distance(x, x_hint)
			if dist <= window and dist < best_d:
				best_d = dist
				best = Vector2(x, from.y + dir.y * t)
	if best != null:
		return best
	# looking along the surface: the plane at x_hint instead
	var p := point_at(x_hint, 0.0)
	var tg := tangent_at(x_hint)
	var n := Vector3(-tg.y, 0.0, tg.x)
	var den := dir.dot(n)
	if absf(den) < 1e-6:
		return null
	var t2 := (p - from).dot(n) / den
	if t2 <= 0.0:
		return null
	var q := from + dir * t2
	var along := (q - p).dot(Vector3(tg.x, 0.0, tg.y))
	return Vector2(clampf(x_hint + along, 0.0, length), q.y)


## Metres that `pixels` cover at distance dist from a camera with vertical
## field of view fov_deg on a view `view_height` pixels high.
static func metres_per_pixels(pixels: float, dist: float, fov_deg: float, view_height: float) -> float:
	return pixels * 2.0 * dist * tan(deg_to_rad(fov_deg) * 0.5) / maxf(view_height, 1.0)


## Wall snap distance for a drag at distance dist: WALL_SNAP, or more when
## the point is far away (as the profile strip did: at least 10 pixels).
static func wall_snap(dist: float, fov_deg: float, view_height: float) -> float:
	return maxf(TrackEditorModel.WALL_SNAP, metres_per_pixels(10.0, dist, fov_deg, view_height))
