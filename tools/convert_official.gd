extends SceneTree
## One-off: turns the official tracks' heights per piece (h, profiles,
## bumps) into the editor's height spline, so the track editor can tune
## them (docs/official-tracks-plan.md, step 3).
##   godot --headless --xr-mode off --path . --script res://tools/convert_official.gd [-- --write]
## Pits (steep ramps the old build turned into steps) become spline walls
## right where the old steps stood; the rest of the profile gets points
## where the spline is furthest from the old heights until it is within
## TOLERANCE everywhere. Without --write: the report only.

const TOLERANCE := 0.08          # m, the spline vs the old heights
## A slope jump this large at a piece border: a corner point (a kink).
const KINK := 0.04
const NEAR_WALL := 1.5           # m: samples this near a wall are not compared
const MAX_POINTS := 400
## Steeper than this (rise per metre), at most STEEP_RUN long and at least
## STEEP_DROP high: a wall, not a slope.
const STEEP := 1.05
const STEEP_RUN := 6.0
const STEEP_DROP := 2.0
## A wall down stands this far behind the old lip sample: that sample stays
## on top, as in the old build (on the wall it would take the foot's height
## and the short ramp piece would lie in the pit - the lap counter, which
## lets a car fly over two pieces at most, then missed three).
const LIP_SHIFT := 0.05


func _init() -> void:
	var write := OS.get_cmdline_user_args().has("--write")
	print("track           points walls  max err  mean err  steps old/new  pits old/new  tunnel old/new  len diff  problems")
	for id in TrackLibrary.ORDER + TrackLibrary.CUSTOM:
		var data := TrackLibrary.load_official(id)
		var old_def: Dictionary = data["def"]
		if old_def.has("heights"):
			print("%-15s already a spline" % id)
			continue
		var r := _convert(id, data)
		print("%-15s %6d %5d  %6.3f m  %6.3f m   %5d/%-5d    %4d/%-4d    %5d/%-5d    %6.3f m  %s" % [id, r["points"], r["walls"], r["max"], r["mean"],
			r["steps_old"], r["steps_new"], r["pits_old"], r["pits_new"], r["tunnel_old"], r["tunnel_new"], r["len_diff"], r["problems"]])
		if write:
			var f := FileAccess.open(TrackLibrary.official_path(id), FileAccess.WRITE)
			f.store_string(JSON.stringify(r["data"], "  ", false))
			f.close()
	if write:
		print("written to ", TrackLibrary.OFFICIAL_DIR)
	quit()


func _convert(id: String, data: Dictionary) -> Dictionary:
	var old_def: Dictionary = data["def"]
	var old := TrackPath.new(old_def)
	# the old steps: walls at their place, with the heights on both sides
	var walls := []
	for i in old.n:
		if old.step[i] == 1:
			var j := (i + 1) % old.n
			var down := old.center[j].y < old.center[i].y
			walls.append([old.px[i] + LIP_SHIFT if down else old.px[j], old.center[i].y, old.center[j].y])
	# short steep drops or rises the old build left as a slope (a ski jump's
	# lip: 7 m down on 3 m) - the editor's wall (down alone: a ski jump)
	var skip := []        # [x0, x1] of the steep runs: not compared
	var i0 := 0
	while i0 < old.n - 1:
		var run_end := i0
		while run_end < old.n - 1 and old.step[run_end] == 0 and old.loop_mask[run_end] == 0 and old.loop_mask[run_end + 1] == 0 \
				and absf(old.center[run_end + 1].y - old.center[run_end].y) > STEEP * maxf(old.px[run_end + 1] - old.px[run_end], 0.01):
			run_end += 1
		var dh := old.center[run_end].y - old.center[i0].y
		if run_end > i0 and old.px[run_end] - old.px[i0] <= STEEP_RUN and absf(dh) >= STEEP_DROP:
			walls.append([old.px[i0] + LIP_SHIFT if dh < 0.0 else old.px[run_end], old.center[i0].y, old.center[run_end].y])
			skip.append([old.px[i0], old.px[run_end]])
			i0 = run_end
		i0 += 1
	walls.sort_custom(func(a, b): return a[0] < b[0])
	var free := []
	for w in walls:
		free.append([float(w[0]), snappedf(w[1], 0.01), false, 0])
		free.append([float(w[0]), snappedf(w[2], 0.01), false, 1])
	# kinks: where the old profile's slope jumps at a piece border (humps
	# set one after the other, a ramp onto a flat) - a corner point there,
	# as the car takes off at such a kink
	for k in range(1, old.pieces.size()):
		var pc: Dictionary = old.pieces[k]
		if pc["type"] == "O" or old.pieces[k - 1]["type"] == "O":
			continue
		var i := int(pc["i0"])
		if i < 2 or i > old.n - 3 or old.step[i - 1] == 1 or old.step[i] == 1:
			continue
		var before := (old.center[i].y - old.center[i - 2].y) / maxf(old.px[i] - old.px[i - 2], 0.01)
		var after := (old.center[i + 2].y - old.center[i].y) / maxf(old.px[i + 2] - old.px[i], 0.01)
		var x := old.px[i]
		var free_x := true
		for q in free:
			if absf(float(q[0]) - x) < TrackEditorModel.MIN_POINT_GAP:
				free_x = false
		if absf(after - before) > KINK and free_x:
			free.append([x, snappedf(old.center[i].y, 0.01), true, 0])
	# the old profile: (x, h) of every sample off a loop, not right at a wall
	var xs := PackedFloat64Array()
	var hs := PackedFloat64Array()
	for i in old.n:
		if old.loop_mask[i] == 1:
			continue
		var near := false
		for w in walls:
			if absf(old.px[i] - float(w[0])) < NEAR_WALL:
				near = true
				break
		for s in skip:
			if old.px[i] > float(s[0]) - NEAR_WALL and old.px[i] < float(s[1]) + NEAR_WALL:
				near = true
		if not near:
			xs.append(old.px[i])
			hs.append(old.center[i].y)
	var base := float(old_def.get("base", 5.0))
	var length := old.profile_length
	# points where the spline is furthest off, until it fits
	var err := PackedFloat64Array()
	while true:
		var pts := HeightSpline.points(base, free, length)
		err = _errors(pts, xs, hs)
		var worst := -1
		var worst_e := TOLERANCE
		for k in xs.size():
			if err[k] > worst_e and _room(pts, xs[k]):
				worst_e = err[k]
				worst = k
		if worst < 0 or free.size() >= MAX_POINTS:
			break
		free.append([xs[worst], snappedf(hs[worst], 0.01), false, 0])
	var max_e := 0.0
	var sum_e := 0.0
	for e in err:
		max_e = maxf(max_e, e)
		sum_e += e
	# the new definition: the pieces without their heights, the spline
	var pieces := []
	for p in old_def["pieces"]:
		var q: Dictionary = p.duplicate(true)
		for k in ["h", "p", "bump"]:
			q.erase(k)
		pieces.append(q)
	var new_def := old_def.duplicate(true)
	new_def["pieces"] = pieces
	new_def["heights"] = HeightSpline.points(base, free, length).slice(1, -1)
	var nu := TrackPath.new(new_def)
	var out := data.duplicate(true)
	var editor_pieces := []
	for k in pieces.size():
		var q: Dictionary = pieces[k].duplicate(true)
		q["g"] = k
		editor_pieces.append(q)
	out["pieces"] = editor_pieces
	out["heights"] = new_def["heights"]
	out["def"] = new_def
	var m := TrackEditorModel.from_dict(out)
	var probs := m.problems(nu)
	var kinds := {}
	for o in probs:
		kinds[o["kind"]] = kinds.get(o["kind"], 0) + 1
	return {"data": out, "points": new_def["heights"].size(), "walls": walls.size(), "max": max_e,
		"mean": sum_e / maxf(err.size(), 1.0), "steps_old": Array(old.step).count(1), "steps_new": Array(nu.step).count(1),
		"pits_old": old.pits.size(), "pits_new": nu.pits.size(), "tunnel_old": Array(old.tunnel).count(1),
		"tunnel_new": Array(nu.tunnel).count(1), "len_diff": absf(nu.total_length - old.total_length), "problems": kinds}


## |spline - old height| at every compared sample (xs ascending).
static func _errors(pts: Array, xs: PackedFloat64Array, hs: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(xs.size())
	var seg := 0
	var herm := HeightSpline.segment_hermite(pts, 0)
	for k in xs.size():
		var x := xs[k]
		var moved := false
		while seg < pts.size() - 2 and x >= float(pts[seg + 1][0]):
			seg += 1
			moved = true
		if moved:
			herm = HeightSpline.segment_hermite(pts, seg)
		out[k] = absf(HeightSpline.hermite_at(herm, x) - hs[k])
	return out


## A new point at x keeps TrackEditorModel.MIN_POINT_GAP to the others.
static func _room(pts: Array, x: float) -> bool:
	for q in pts:
		if absf(float(q[0]) - x) < TrackEditorModel.MIN_POINT_GAP:
			return false
	return true
