class_name TrackPath
extends RefCounted
## Turns a TrackLibrary definition into a densely sampled centre line with
## banking, heights and road/gap flags. Used by the mesh builder, the AI,
## lap counting, the crane and the dashboard.
## Piece types: "S" straight, "L"/"R" curve, "O" loop (vertical circle that
## ends shifted sideways so entry and exit pass each other).

const ROAD_WIDTH := 10.0
const HALF_WIDTH := ROAD_WIDTH * 0.5
const STEP := 1.0
const DEFAULT_RADIUS := 55.0
const BRIDGE_U0 := 0.2
const BRIDGE_U1 := 0.8
const BRIDGE_MAX_ANGLE := deg_to_rad(14.0)
const BRIDGE_PERIOD := 14.0
const LOOP_RADIUS := 12.0
const LOOP_SHIFT := 11.0          # sideways shift of a loop: road width + 1 m
## Underpass: a road section with another part of the track below it is
## built as a deck (slab) instead of a wall down to the ground.
const DECK_CLEARANCE := 4.0
const DECK_MARGIN := 2.0

var def: Dictionary
var pieces: Array = []
var total_length := 0.0
var closure_error := 0.0
var heading_error := 0.0

var n := 0
var s_arr := PackedFloat32Array()
var center := PackedVector3Array()
var right := PackedVector3Array()
var right_flat := PackedVector3Array()
var up := PackedVector3Array()
var forward := PackedVector3Array()
var piece_of := PackedInt32Array()
var road := PackedByteArray()
var bridge_zone := PackedByteArray()
## Half road width per sample (original tracks: 4 m, own tracks: 5 m).
var half_width := PackedFloat32Array()
## 1 = drawn black (very steep segment, e.g. pit walls).
var steep := PackedByteArray()
## Pits: [lip_index, landing_index] - steep drop followed by a steep rise,
## to be jumped over (original tracks have no missing road).
var pits: Array = []
var pit_mask := PackedByteArray()      # 1 = inside a pit (between lip and landing)
## 1 = sample belongs to a loop piece
var loop_mask := PackedByteArray()
## 1 = build as a deck/slab with thickness (overhead part of a loop, or a
## section another part of the track passes under)
var deck := PackedByteArray()



func _init(track_def: Dictionary) -> void:
	def = track_def
	_layout()
	_sample()
	_finish_frames()
	_detect_pits()
	_detect_decks()


# --- layout -----------------------------------------------------------------

func _layout() -> void:
	var pos := Vector2.ZERO
	var dir := Vector2(0, -1)
	var s := 0.0
	var h: float = def.get("base", 5.0)
	for raw in def["pieces"]:
		var p := {}
		p["type"] = raw.get("t", "S")
		p["start"] = pos
		p["dir"] = dir
		p["s0"] = s
		p["h0"] = h
		p["h1"] = float(raw.get("h", h))
		p["profile"] = raw.get("p", "ramp")
		p["bump"] = float(raw.get("bump", 0.0))
		p["bank"] = deg_to_rad(float(raw.get("bank", 0.0)))
		p["gap"] = bool(raw.get("gap", false))
		p["bridge"] = bool(raw.get("bridge", false))
		p["no_crane"] = bool(raw.get("no_crane", false))
		var length: float
		if p["type"] == "S":
			length = float(raw.get("l", 40.0))
			pos += dir * length
		elif p["type"] == "O":
			p["radius"] = float(raw.get("r", LOOP_RADIUS))
			p["side"] = float(raw.get("side", 1))
			p["shift"] = float(raw.get("shift", LOOP_SHIFT))
			p["h1"] = h
			p["profile"] = "lin"
			length = _loop_length(p)
			pos += dir.rotated(PI * 0.5) * float(p["side"]) * float(p["shift"])
		else:
			var r := float(raw.get("r", DEFAULT_RADIUS))
			var a := deg_to_rad(float(raw.get("a", 90.0)))
			var sgn := 1.0 if p["type"] == "R" else -1.0
			var c := pos + dir.rotated(PI * 0.5) * r * sgn
			p["center"] = c
			p["sign"] = sgn
			p["angle"] = a
			length = r * a
			pos = c + (pos - c).rotated(sgn * a)
			dir = dir.rotated(sgn * a)
		p["length"] = length
		s += length
		h = p["h1"]
		pieces.append(p)
	total_length = s
	closure_error = pos.length()
	heading_error = absf(dir.angle_to(Vector2(0, -1)))


func _loop_length(p: Dictionary) -> float:
	var total := 0.0
	var prev := _loop_point(p, 0.0)
	for k in range(1, 201):
		var cur := _loop_point(p, k / 200.0)
		total += prev.distance_to(cur)
		prev = cur
	return total


## Loop position relative to its start: (forward, up, sideways).
func _loop_point(p: Dictionary, u: float) -> Vector3:
	var r: float = p["radius"]
	var phi := TAU * u
	var side_off: float = float(p["side"]) * float(p["shift"]) * (1.0 - cos(PI * u)) * 0.5
	return Vector3(r * sin(phi), r * (1.0 - cos(phi)), side_off)


static func profile_value(profile: String, u: float) -> float:
	match profile:
		"lin":
			return u
		"kick":
			return u * u
		"land":
			return 1.0 - (1.0 - u) * (1.0 - u)
		_:
			return u * u * (3.0 - 2.0 * u)


func piece_height(p: Dictionary, u: float) -> float:
	if p["type"] == "O":
		return float(p["h0"]) + _loop_point(p, u).y
	var h0: float = p["h0"]
	var h1: float = p["h1"]
	return h0 + (h1 - h0) * profile_value(p["profile"], u) + float(p["bump"]) * sin(PI * u)


func _piece_pos(p: Dictionary, u: float) -> Array:
	if p["type"] == "S":
		var d: Vector2 = p["dir"]
		return [p["start"] + d * float(p["length"]) * u, d]
	if p["type"] == "O":
		var d2: Vector2 = p["dir"]
		var lp := _loop_point(p, u)
		return [p["start"] + d2 * lp.x + d2.rotated(PI * 0.5) * lp.z, d2]
	var ang: float = float(p["sign"]) * float(p["angle"]) * u
	var c: Vector2 = p["center"]
	var st: Vector2 = p["start"]
	return [c + (st - c).rotated(ang), (p["dir"] as Vector2).rotated(ang)]


# --- sampling ---------------------------------------------------------------

func _sample() -> void:
	var closure_vec := Vector2.ZERO
	if pieces.size() > 0:
		var last: Dictionary = pieces[pieces.size() - 1]
		closure_vec = _piece_pos(last, 1.0)[0]
	for pi_ in pieces.size():
		var p: Dictionary = pieces[pi_]
		var length: float = p["length"]
		var m := maxi(1, ceili(length / STEP))
		p["i0"] = s_arr.size()
		for k in m:
			var u := float(k) / m
			var s: float = float(p["s0"]) + length * u
			var pd := _piece_pos(p, u)
			# distribute any tiny closure error along the lap
			var pos2: Vector2 = pd[0] - closure_vec * (s / total_length)
			var dir2: Vector2 = pd[1]
			var h := piece_height(p, u)
			var rf := Vector3(dir2.rotated(PI * 0.5).x, 0.0, dir2.rotated(PI * 0.5).y)
			s_arr.append(s)
			center.append(Vector3(pos2.x, h, pos2.y))
			right_flat.append(rf)
			right.append(rf)
			piece_of.append(pi_)
			var in_bridge: bool = p["bridge"] and u >= BRIDGE_U0 and u < BRIDGE_U1
			road.append(0 if (p["gap"] or in_bridge) else 1)
			bridge_zone.append(1 if in_bridge else 0)
			half_width.append(HALF_WIDTH)
			loop_mask.append(1 if p["type"] == "O" else 0)
		p["i1"] = s_arr.size()
	n = s_arr.size()
	_apply_banking()
	steep.resize(n)
	for i in n:
		var j := (i + 1) % n
		var d := Vector2(center[j].x - center[i].x, center[j].z - center[i].z).length()
		var is_steep := absf(center[j].y - center[i].y) > 0.33 * maxf(d, 0.01)
		steep[i] = 1 if is_steep and loop_mask[i] == 0 and loop_mask[j] == 0 else 0


## Banking: a curve is banked over its whole length; the road twists in and
## out over BANK_RAMP metres of the neighbouring pieces (as on real banked
## turns), so the car never meets a flat road while still cornering.
const BANK_RAMP := 40.0

func _apply_banking() -> void:
	# contributions of all curves are summed with sign (so an S-bend twists
	# smoothly through zero) and limited to the largest bank involved
	var bank := PackedFloat32Array()
	var limit := PackedFloat32Array()
	bank.resize(n)
	limit.resize(n)
	var ramp := int(BANK_RAMP / STEP)
	for p in pieces:
		var b: float = p["bank"]
		if absf(b) < 1e-4:
			continue
		var i0: int = p["i0"]
		var i1: int = p["i1"]
		for i in range(i0, i1):
			bank[i] += b
			limit[i] = maxf(limit[i], absf(b))
		for k in range(1, ramp + 1):
			var f := smoothstep(0.0, 1.0, 1.0 - float(k) / ramp)
			for i in [(i0 - k + n) % n, (i1 - 1 + k) % n]:
				bank[i] += b * f
				limit[i] = maxf(limit[i], absf(b))
	for i in n:
		var bi := clampf(bank[i], -limit[i], limit[i])
		var rf := right_flat[i]
		right[i] = Vector3(rf.x * cos(bi), -sin(bi), rf.z * cos(bi))


## Deck samples: the overhead part of loops, and sections with another part
## of the track passing underneath (underpass). Uses a coarse spatial hash.
func _detect_decks() -> void:
	deck.resize(n)
	deck.fill(0)
	var grid := {}
	var cell := 12.0
	for i in n:
		var key := Vector2i(floori(center[i].x / cell), floori(center[i].z / cell))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)    # plain Array: packed arrays are copied on access
	for i in n:
		if loop_mask[i] == 1 and up[i].y < 0.1:
			deck[i] = 1
			continue
		var key := Vector2i(floori(center[i].x / cell), floori(center[i].z / cell))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var bucket = grid.get(key + Vector2i(dx, dz))
				if bucket == null:
					continue
				for j in bucket:
					if absf(delta_s(s_arr[i], s_arr[j])) < 40.0:
						continue
					if center[j].y > center[i].y - DECK_CLEARANCE:
						continue
					var dist := Vector2(center[j].x - center[i].x, center[j].z - center[i].z).length()
					if dist < half_width[i] + half_width[j] + DECK_MARGIN:
						deck[i] = 1
						break
				if deck[i] == 1:
					break
			if deck[i] == 1:
				break


func _finish_frames() -> void:
	forward.resize(n)
	up.resize(n)
	for i in n:
		var f := (center[(i + 1) % n] - center[(i - 1 + n) % n]).normalized()
		var u3 := right[i].cross(f).normalized()
		forward[i] = f
		up[i] = u3
		right[i] = f.cross(u3).normalized()


func _detect_pits() -> void:
	pits.clear()
	var i := 0
	while i < n:
		var j := (i + 1) % n
		var down := steep[i] == 1 and center[j].y < center[i].y
		if not down:
			i += 1
			continue
		var lip := i
		var k := i
		var found := -1
		for step in 140:
			var a := (k + 1) % n
			var b := (k + 2) % n
			if steep[a] == 1 and center[b].y > center[a].y:
				# end of the rising run
				var e := a
				while steep[e] == 1 and center[(e + 1) % n].y > center[e].y:
					e = (e + 1) % n
				found = e
				break
			k = a
		if found < 0:
			i += 1
			continue
		# land where the road flattens out, not on a still rising face
		for step in 60:
			var a2 := (found + 1) % n
			var d2 := Vector2(center[a2].x - center[found].x, center[a2].z - center[found].z).length()
			if center[a2].y - center[found].y > 0.25 * maxf(d2, 0.01):
				found = a2
			else:
				break
		if not pits.is_empty() and _fwd_dist(pits[-1][1], lip) < 20:
			pits[-1][1] = found
		else:
			pits.append([lip, found])
		i = lip + _fwd_dist(lip, found) + 1
		if i >= n:
			break
	pit_mask.resize(n)
	pit_mask.fill(0)
	for pt in pits:
		var k: int = pt[0]
		while k != pt[1]:
			pit_mask[k] = 1
			k = (k + 1) % n


func _fwd_dist(a: int, b: int) -> int:
	return (b - a + n) % n


func half_width_at(i: int) -> float:
	return half_width[i]


# --- queries ----------------------------------------------------------------

func wrap_s(s: float) -> float:
	return fposmod(s, total_length)


## Signed shortest distance from a to b along the loop.
func delta_s(a: float, b: float) -> float:
	var d := fposmod(b - a, total_length)
	if d > total_length * 0.5:
		d -= total_length
	return d


func index_at_s(s: float) -> int:
	s = wrap_s(s)
	var lo := 0
	var hi := n - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if s_arr[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	return lo


func piece_at_s(s: float) -> int:
	return piece_of[index_at_s(s)]


## Nearest sample in the horizontal plane. With hint >= 0 only a window
## around the hint is searched (cheap per-frame tracking).
func nearest(pos: Vector3, hint := -1, window := 48) -> int:
	var best := 0
	var best_d := INF
	if hint < 0:
		for i in n:
			var d := pos.distance_squared_to(center[i])
			if d < best_d:
				best_d = d
				best = i
		return best
	for k in range(-window, window + 1):
		var i := (hint + k + n) % n
		var d := pos.distance_squared_to(center[i])
		if d < best_d:
			best_d = d
			best = i
	return best


## Continuous position along the loop for a world point near sample i.
func s_of(pos: Vector3, i: int) -> float:
	var along := (pos - center[i]).dot(forward[i])
	return wrap_s(s_arr[i] + along)


## Height of a point above the road surface, measured along the surface
## normal (works upside down in loops).
func height_above(pos: Vector3, i: int) -> float:
	return (pos - center[i]).dot(up[i])


func lateral(pos: Vector3, i: int) -> float:
	return (pos - center[i]).dot(right_flat[i])


## Road surface height at a lateral offset for sample i (static road only).
func road_height(i: int, lat := 0.0) -> float:
	var r := right[i]
	var rf := right_flat[i]
	var k := rf.dot(r)
	if absf(k) < 0.01:
		return center[i].y
	return center[i].y + r.y * (lat / k)


func center_at_s(s: float) -> Vector3:
	var i := index_at_s(s)
	var j := (i + 1) % n
	var s0 := s_arr[i]
	var s1 := s_arr[j] if j > 0 else total_length
	var t := clampf((wrap_s(s) - s0) / maxf(s1 - s0, 1e-4), 0.0, 1.0)
	return center[i].lerp(center[j], t)


func frame_at_s(s: float) -> Transform3D:
	var i := index_at_s(s)
	var b := Basis(right[i], up[i], -forward[i]).orthonormalized()
	return Transform3D(b, center_at_s(s))


static func bridge_angle(t: float) -> float:
	var ph := fposmod(t, BRIDGE_PERIOD) / BRIDGE_PERIOD
	var f := 0.0
	if ph < 0.35:
		f = 0.0
	elif ph < 0.5:
		f = smoothstep(0.35, 0.5, ph)
	elif ph < 0.85:
		f = 1.0
	else:
		f = 1.0 - smoothstep(0.85, 1.0, ph)
	return BRIDGE_MAX_ANGLE * f


## Surface height including drawbridge leaves at time t. -INF where there is
## no surface (gaps, open bridge).
func surface_height(s: float, t: float, lat := 0.0) -> float:
	var i := index_at_s(s)
	if road[i] == 1:
		# interpolate between samples (a per-sample value would be a staircase)
		var j := (i + 1) % n
		var s1 := s_arr[j] if j > 0 else total_length
		var t01 := clampf((wrap_s(s) - s_arr[i]) / maxf(s1 - s_arr[i], 1e-4), 0.0, 1.0)
		return lerpf(road_height(i, lat), road_height(j, lat), t01)
	if bridge_zone[i] == 0:
		return -INF
	var p: Dictionary = pieces[piece_of[i]]
	var length: float = p["length"]
	var sh0: float = float(p["s0"]) + length * BRIDGE_U0
	var sh1: float = float(p["s0"]) + length * BRIDGE_U1
	var leaf := (sh1 - sh0) * 0.5
	var ang := bridge_angle(t)
	var hb: float = p["h1"]
	s = wrap_s(s)
	var d := s - sh0
	if d > leaf:
		d = sh1 - s
	if d <= leaf * cos(ang) + 0.01:
		return hb + d * tan(ang)
	return -INF


func is_crane_allowed(piece_index: int) -> bool:
	var p: Dictionary = pieces[piece_index]
	if p["type"] != "S" or p["gap"] or p["bridge"] or p["no_crane"]:
		return false
	for i in range(p["i0"], p["i1"]):
		if deck[i] == 1:
			return false
	if p["profile"] == "kick" or p["profile"] == "land":
		return false
	return absf(float(p["h1"]) - float(p["h0"])) / float(p["length"]) < 0.3


## Where the crane puts a car back: a few metres into the nearest allowed
## piece at or before s.
func recovery_s(s: float) -> float:
	var pi_ := piece_at_s(s)
	for k in pieces.size():
		var idx := (pi_ - k + pieces.size()) % pieces.size()
		if is_crane_allowed(idx):
			var p: Dictionary = pieces[idx]
			return wrap_s(float(p["s0"]) + minf(6.0, float(p["length"]) * 0.3))
	return 6.0


## Returns [takeoff_index, landing_index] pairs for every gap.
func gaps() -> Array:
	var result := []
	for i in n:
		var j := (i + 1) % n
		if road[i] == 1 and road[j] == 0 and bridge_zone[j] == 0:
			var k := j
			var guard := 0
			while road[k] == 0 and guard < n:
				k = (k + 1) % n
				guard += 1
			result.append([i, k])
	result.append_array(pits)
	return result


func bounds() -> AABB:
	var box := AABB(center[0], Vector3.ZERO)
	for i in n:
		box = box.expand(center[i])
	return box
