class_name TrackPath
extends RefCounted
## Turns a TrackLibrary definition into a densely sampled centre line with
## banking, heights and road/gap flags. Used by the mesh builder, the AI,
## lap counting, the crane and the dashboard.
## Piece types: "S" straight, "L"/"R" curve, "O" loop (vertical circle that
## ends shifted sideways so entry and exit pass each other).
## Heights: either per piece ("h" end height, "p" profile, "bump"), or - own
## tracks from the editor - a HeightSpline along the lap (def "heights",
## between the start and the end of the lap, both at "base"). Its x is the
## profile coordinate: the distance along the lap without the loops (a loop
## keeps the height it starts at). A vertical wall down and one up again
## form a pit, a wall down alone a ski jump.

const ROAD_WIDTH := 10.0
const HALF_WIDTH := ROAD_WIDTH * 0.5
const STEP := 1.0
const DEFAULT_RADIUS := 55.0
## Crane: a car is set down at least this far (m) before a jump, this far
## before a stretch where the crane can't go, nowhere within this margin (m)
## of a road above.
const JUMP_RUNUP := 200.0
const CRANE_BACK := 2.0
const CRANE_COVER_MARGIN := 2.0
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
## Tunnels: where the road dips below the ground (y = 0). Covered where the
## whole tunnel box - roof included - lies below the ground; an open cut
## with retaining walls where the road is below ground but the box is not.
const TUNNEL_HEIGHT := 6.0      # clear height above the road
const TUNNEL_SIDE := 0.5        # extra width beyond the road on each side
const TUNNEL_ROOF := 0.6        # roof thickness

var def: Dictionary
var pieces: Array = []
var total_length := 0.0
## Length of the lap without the loops (x range of the height profile).
var profile_length := 0.0
## Spline points [x, h, corner] incl. start and end; empty = piece heights.
var spline: Array = []
## 1 = segment i -> i+1 is a vertical wall (pit, ski jump): built as a step.
var step := PackedByteArray()
## Spline walls: where in segment i the wall stands (0..1; -1: not known -
## older tracks, see step_info) and the road's height just before and just
## after it (the wall's two points).
var step_t := PackedFloat64Array()
var step_before := PackedFloat64Array()
var step_after := PackedFloat64Array()
## Ski jumps [lip_index, landing_index] (also in gaps() for the AI).
var ramps: Array = []
var _floor_ranges: Array = []    # [first, end) sample ranges of pit floors
var closure_error := 0.0
var heading_error := 0.0

var n := 0
var s_arr := PackedFloat64Array()     # distance along the lap per sample (sample_s, 64 bit)
var center := PackedVector3Array()
var right := PackedVector3Array()
var right_flat := PackedVector3Array()
var up := PackedVector3Array()
var forward := PackedVector3Array()
var piece_of := PackedInt32Array()
## Profile coordinate per sample (see profile_length): 64 bit, exactly the x
## the sample's height was taken at (sample_x) - compared with the spline's
## walls it must fall on the same side the height did.
var px := PackedFloat64Array()
var road := PackedByteArray()
var bridge_zone := PackedByteArray()
## Half road width per sample (original tracks: 4 m, own tracks: 5 m).
var half_width := PackedFloat32Array()
## 1 = very steep segment (e.g. pit walls; the editor reports these).
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
## 1 = covered tunnel / 1 = open cut (road below ground, no roof)
var tunnel := PackedByteArray()
var cut := PackedByteArray()
## Distance (m) from a tunnel sample to the nearest portal, 0 outside.
var tunnel_depth := PackedFloat32Array()
## 1 = pit floor on the ground (y = 0): no road there, the ground is the floor.
var ground_floor := PackedByteArray()



func _init(track_def: Dictionary) -> void:
	def = track_def
	_layout()
	_sample()
	_finish_frames()
	_detect_pits()
	_finish_frames()      # again: pit walls are vertical now
	_find_ground_floors()
	_detect_tunnels()
	_detect_decks()


# --- layout -----------------------------------------------------------------

func _layout() -> void:
	var pos := Vector2.ZERO
	var dir := Vector2(0, -1)
	var s := 0.0
	var x := 0.0
	var h: float = def.get("base", 5.0)
	for raw in def["pieces"]:
		var p := {}
		p["type"] = raw.get("t", "S")
		p["start"] = pos
		p["dir"] = dir
		p["s0"] = s
		p["x0"] = x
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
		if p["type"] != "O":
			x += length
		h = p["h1"]
		pieces.append(p)
	total_length = s
	profile_length = x
	if def.has("heights"):
		spline = HeightSpline.points(float(def.get("base", 5.0)), def["heights"], x)
		for p in pieces:
			p["h0"] = HeightSpline.height(spline, p["x0"])
			p["h1"] = p["h0"] if p["type"] == "O" else HeightSpline.height(spline, p["x0"] + p["length"])
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


## Profile x of sample k of the m samples of piece p - the one place it is
## worked out: length * k / m, not length * (k / m) (k / m is rarely exact in
## binary: 400 * (57 / 400) = 56.99999999999999, a hair before a wall at 57,
## while the sample's px became 57). Loops keep their start x.
static func sample_x(p: Dictionary, k: int, m: int) -> float:
	if p["type"] == "O":
		return float(p["x0"])
	return float(p["x0"]) + float(p["length"]) * k / m


## Distance along the lap of sample k of the m samples of piece p (as
## sample_x: length * k / m, exact at whole metres).
static func sample_s(p: Dictionary, k: int, m: int) -> float:
	return float(p["s0"]) + float(p["length"]) * k / m


## Height of piece p at fraction u, profile x (spline tracks; sample_x).
func piece_height(p: Dictionary, u: float, x: float) -> float:
	if p["type"] == "O":
		return float(p["h0"]) + _loop_point(p, u).y
	if not spline.is_empty():
		return HeightSpline.height(spline, x)
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
			var s := sample_s(p, k, m)
			var pd := _piece_pos(p, u)
			# distribute any tiny closure error along the lap
			var pos2: Vector2 = pd[0] - closure_vec * (s / total_length)
			var dir2: Vector2 = pd[1]
			var x := sample_x(p, k, m)
			var h := piece_height(p, u, x)
			var rf := Vector3(dir2.rotated(PI * 0.5).x, 0.0, dir2.rotated(PI * 0.5).y)
			s_arr.append(s)
			center.append(Vector3(pos2.x, h, pos2.y))
			right_flat.append(rf)
			right.append(rf)
			piece_of.append(pi_)
			px.append(x)
			var in_bridge: bool = p["bridge"] and u >= BRIDGE_U0 and u < BRIDGE_U1
			road.append(0 if (p["gap"] or in_bridge) else 1)
			bridge_zone.append(1 if in_bridge else 0)
			half_width.append(HALF_WIDTH)
			loop_mask.append(1 if p["type"] == "O" else 0)
		p["i1"] = s_arr.size()
	n = s_arr.size()
	_apply_banking()
	step.resize(n)
	step.fill(0)
	step_t.resize(n)
	step_t.fill(-1.0)
	step_before.resize(n)
	step_after.resize(n)
	for k in range(1, spline.size() - 2):
		if HeightSpline.is_wall(spline, k):
			var x := float(spline[k][0])
			var lip := _lip_at_x(x)
			var xj := px[lip + 1] if lip + 1 < n else profile_length
			step[lip] = 1
			step_t[lip] = clampf((x - px[lip]) / maxf(xj - px[lip], 1e-6), 0.0, 1.0)
			step_before[lip] = float(spline[k][1])
			step_after[lip] = float(spline[k + 1][1])
	steep.resize(n)
	for i in n:
		var j := (i + 1) % n
		var d := Vector2(center[j].x - center[i].x, center[j].z - center[i].z).length()
		var is_steep := absf(center[j].y - center[i].y) > 0.33 * maxf(d, 0.01)
		steep[i] = 1 if is_steep and loop_mask[i] == 0 and loop_mask[j] == 0 and step[i] == 0 else 0


## The wall in step segment i: [t (where in the segment, 0..1), height of
## the road just before it, just after it]. Without a spline wall there
## (older tracks: steep steps found in the heights) the wall stands at the
## higher end and the lower road runs on under it at its own height.
func step_info(i: int) -> Array:
	var j := (i + 1) % n
	if step_t[i] >= 0.0:
		return [step_t[i], step_before[i], step_after[i]]
	return [0.0 if center[j].y < center[i].y else 1.0, center[i].y, center[j].y]


## Last sample before profile x (at a wall: its top, the step starts there).
func _lip_at_x(x: float) -> int:
	return (_index_at_x(x) - 1 + n) % n


## First sample at or after profile x.
func _index_at_x(x: float) -> int:
	for i in n:
		if px[i] >= x and loop_mask[i] == 0:
			return i
	return 0


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
					# (a road over a tunnel stands on the ground: no deck)
					if absf(delta_s(s_arr[i], s_arr[j])) < 40.0 or tunnel[j] == 1:
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
		# one-sided next to a vertical wall (the wall is no slope)
		var a := i if step[(i - 1 + n) % n] == 1 else (i - 1 + n) % n
		var b := i if step[i] == 1 else (i + 1) % n
		var f := (center[b] - center[a]).normalized() if a != b else forward[i]
		var u3 := right[i].cross(f).normalized()
		forward[i] = f
		up[i] = u3
		right[i] = f.cross(u3).normalized()


func tunnel_half_width(i: int) -> float:
	return half_width[i] + TUNNEL_SIDE


## "Up" of the tunnel cross-section at sample i: square to the road's
## right (so the box banks with the road) but in a vertical plane - not
## pitched with the slope, so portals stand upright and meet the cut walls.
func tunnel_up(i: int) -> Vector3:
	var f := Vector3(forward[i].x, 0.0, forward[i].z).normalized()
	return right[i].cross(f).normalized()


## Corners of the tunnel cross-section at sample i: [bottom left, bottom
## right, top left, top right]. The box turns and banks with the road.
func tunnel_corners(i: int) -> Array:
	var hw := tunnel_half_width(i)
	var bl := center[i] - right[i] * hw
	var br := center[i] + right[i] * hw
	var u := tunnel_up(i) * TUNNEL_HEIGHT
	return [bl, br, bl + u, br + u]


func _detect_tunnels() -> void:
	tunnel.resize(n)
	tunnel.fill(0)
	cut.resize(n)
	cut.fill(0)
	for i in n:
		if road[i] == 0 or loop_mask[i] == 1 or ground_floor[i] == 1:
			continue
		var c := tunnel_corners(i)
		var roof_top := maxf(c[2].y, c[3].y) + TUNNEL_ROOF
		if roof_top <= 0.0:
			tunnel[i] = 1
		elif minf(c[0].y, c[1].y) < 0.0:
			cut[i] = 1
	tunnel_depth.resize(n)
	tunnel_depth.fill(0.0)
	for i in n:
		if tunnel[i] == 0:
			continue
		var d := 0
		while d < n and tunnel[(i + d) % n] == 1 and tunnel[(i - d + n) % n] == 1:
			d += 1
		tunnel_depth[i] = d * STEP


## Where a cut wall from road corner c along the tunnel's up vector u meets
## the ground (c itself if it is above the ground).
static func to_ground(c: Vector3, u: Vector3) -> Vector3:
	if c.y >= 0.0 or u.y <= 0.01:
		return Vector3(c.x, maxf(c.y, 0.0), c.z)
	var g := c + u * (-c.y / u.y)
	g.y = 0.0
	return g


## Openings in the ground over the open cuts, as plan-view polygons (x, z):
## each runs along both retaining walls, from the sample before the cut to
## the one after it (the tunnel portal, or the road back above ground).
func ground_holes() -> Array:
	var holes := []
	var start := 0
	while start < n and cut[start] == 1:
		start += 1
	if start >= n:
		return holes
	var i := 0
	while i < n:
		var k := (start + i) % n
		if cut[k] == 0:
			i += 1
			continue
		var run := [(k - 1 + n) % n]
		while i < n and cut[(start + i) % n] == 1:
			run.append((start + i) % n)
			i += 1
		run.append((start + i) % n)
		var poly := PackedVector2Array()
		var rights := PackedVector2Array()
		for idx in run:
			# the hole ends where the tilted cut walls meet the ground
			var c := tunnel_corners(idx)
			var u := tunnel_up(idx)
			var gl := to_ground(c[0], u)
			var gr := to_ground(c[1], u)
			if tunnel[idx] == 1:      # the portal: the line of its top edge
				gl = to_ground(c[2], u)
				gr = to_ground(c[3], u)
			poly.append(Vector2(gl.x, gl.z))
			rights.append(Vector2(gr.x, gr.z))
		rights.reverse()
		poly.append_array(rights)
		holes.append(poly)
	return holes


func _detect_pits() -> void:
	pits.clear()
	ramps.clear()
	if not spline.is_empty():
		_spline_pits()
		return
	var walls := []   # [lip, top of the far wall] of each pit
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
		var wall_top := -1
		for step in 140:
			var a := (k + 1) % n
			var b := (k + 2) % n
			if steep[a] == 1 and center[b].y > center[a].y:
				# end of the rising run
				var e := a
				while steep[e] == 1 and center[(e + 1) % n].y > center[e].y:
					e = (e + 1) % n
				found = e
				wall_top = e
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
		walls.append([lip, wall_top])
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
	for w in walls:
		_vertical_pit(w[0], w[1])


## League pits are built with short steep ramps as walls: the floor runs on
## to the foot of both (lip and top keep their place, so the jump stays as
## long) and the walls stand vertical there.
func _vertical_pit(lip: int, top: int) -> void:
	var floor_y := INF
	var k := (lip + 1) % n
	while k != top:
		floor_y = minf(floor_y, center[k].y)
		k = (k + 1) % n
	if floor_y == INF:
		return
	k = (lip + 1) % n
	while k != top:
		center[k].y = floor_y
		steep[k] = 0
		k = (k + 1) % n
	steep[lip] = 0
	steep[(top - 1 + n) % n] = 0
	step[lip] = 1
	step[(top - 1 + n) % n] = 1
	_floor_ranges.append([(lip + 1) % n, top])


## Pits and ski jumps from the walls of the spline: a wall down followed by
## a wall up (within PIT_MAX) is a pit that lands on top of the far wall; a
## wall down alone a ski jump (landing 15 m on, for the AI). lip = last
## sample before the wall.
const PIT_MAX := 80.0

func _spline_pits() -> void:
	pit_mask.resize(n)
	pit_mask.fill(0)
	var walls := []    # [x, down]
	for k in range(1, spline.size() - 2):
		if HeightSpline.is_wall(spline, k):
			walls.append([float(spline[k][0]), float(spline[k + 1][1]) < float(spline[k][1])])
	var w := 0
	while w < walls.size():
		if not walls[w][1]:
			w += 1
			continue
		var lip := _lip_at_x(walls[w][0])
		if w + 1 < walls.size() and not walls[w + 1][1] and walls[w + 1][0] - walls[w][0] <= PIT_MAX:
			var landing := _index_at_x(walls[w + 1][0])
			_floor_ranges.append([(lip + 1) % n, landing])
			# pits this close are one long jump (as the league pits always were)
			if not pits.is_empty() and _fwd_dist(pits[-1][1], lip) < 20:
				pits[-1][1] = landing
			else:
				pits.append([lip, landing])
			w += 2
		else:
			ramps.append([lip, _index_at_x(walls[w][0] + 15.0)])
			w += 1
	for pt in pits:
		var k: int = pt[0]
		while k != pt[1]:
			pit_mask[k] = 1
			k = (k + 1) % n


## Pit floors at ground level (between two lower wall points snapped to 0):
## no road there, also in a banked curve - a gap, the car lands on the
## ground. These samples are no cut either (see _detect_tunnels).
func _find_ground_floors() -> void:
	ground_floor.resize(n)
	ground_floor.fill(0)
	for r in _floor_ranges:
		var k: int = r[0]
		while k != r[1]:
			if center[k].y <= 0.05:
				ground_floor[k] = 1
			k = (k + 1) % n


func _fwd_dist(a: int, b: int) -> int:
	return (b - a + n) % n


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


## Where the crane puts a car back that left the road at s: right there, but
## at least JUMP_RUNUP before a jump ahead (or one it was on), before a tunnel,
## and never on a loop, a gap, a drawbridge, a deck, under another road or on
## a piece marked "no crane". Open cuts are fine: the crane lowers the car in.
func recovery_s(s: float) -> float:
	var r := wrap_s(s)
	var jumps := gaps()
	for _guard in 64:
		var nr := _recovery_back(r, jumps)
		if is_equal_approx(nr, r):
			return r
		r = nr
	return r


## r, or further back if r is no place for the crane (see recovery_s).
func _recovery_back(r: float, jumps: Array) -> float:
	var i := index_at_s(r)
	for jp in jumps:
		var take: int = jp[0]
		var land: int = jp[1]
		var ahead := fposmod(s_arr[take] - r, total_length)
		var over := _fwd_dist(take, i) <= _fwd_dist(take, land)
		if ahead < JUMP_RUNUP or over:
			return wrap_s(s_arr[take] - JUMP_RUNUP)
	if not _crane_spot(i):
		# back to just before the stretch that is no place for it
		var k := i
		for _guard in n:
			if _crane_spot(k):
				break
			k = (k - 1 + n) % n
		return wrap_s(s_arr[k] - CRANE_BACK)
	return r


## Whether the crane may set a car down at sample i.
func _crane_spot(i: int) -> bool:
	var p: Dictionary = pieces[piece_of[i]]
	if p["gap"] or p["bridge"] or p["no_crane"]:
		return false
	if road[i] != 1 or tunnel[i] == 1 or loop_mask[i] == 1 or deck[i] == 1 or bridge_zone[i] == 1:
		return false
	if (pit_mask.size() == n and pit_mask[i] == 1) or (step.size() == n and step[i] == 1):
		return false
	return not _covered(i)


## Another part of the track passes over sample i (the crane's chain would
## go through it).
func _covered(i: int) -> bool:
	var c := center[i]
	var reach := half_width[i] + CRANE_COVER_MARGIN
	for j in n:
		if center[j].y > c.y + 2.0 and absf(delta_s(s_arr[i], s_arr[j])) > 30.0:
			if Vector2(center[j].x - c.x, center[j].z - c.z).length() < reach + half_width[j]:
				return true
	return false


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
	result.append_array(ramps)
	return result


func bounds() -> AABB:
	var box := AABB(center[0], Vector3.ZERO)
	for i in n:
		box = box.expand(center[i])
	return box
