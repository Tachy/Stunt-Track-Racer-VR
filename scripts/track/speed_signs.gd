class_name SpeedSigns
extends Node3D
## Advisory speed signs before the jumps, after the German "Richtgeschwindigkeit"
## (Zeichen 380): a blue square plate with a white edge band and the speed
## in white DIN 1451 Mittelschrift figures. SIGN_DIST before the first jump of
## a combination (the jumps right after it get none), showing the take-off
## speed the AI plans with (AiProfile.plan_jump), rounded to 10 km/h or 5 mph.
## Each hangs on a gantry to the right of the road: an arm out sideways from
## the road's edge, a post up from its end, the plate on the post. In a
## tunnel (and a cut) it is fixed to the right wall instead, as tunnel signs
## are, reaching over the road at a height cars pass under - in a tunnel lit
## from inside (its face glows).

const SIGN_DIST := 150.0          # m before the take-off
const SIGN_SHIFT := 80.0          # m it may move further back for room
## A jump whose take-off is this close after another's landing belongs to
## its combination: no sign of its own.
const COMBO_DIST := 150.0
const PLATE := 1.8                # m, square
const PLATE_DEPTH := 0.05
const ARM_OUT := 2.4              # m out from the road's edge
const ARM_DROP := 0.35            # arm this far below the road's edge
const CLEARANCE := 2.2            # m from the edge up to the plate's lower edge
const BAR := 0.14                 # arm and post (square section)
const BLUE := Color("#005387")    # RAL 5017 traffic blue
const STEEL := Color("#9a9ea3")
## On a tunnel wall: lower edge of the plate this high over the road, the
## plate this far off the wall (brackets).
const WALL_CLEARANCE := 3.0
const WALL_GAP := 0.25
## Internally lit faces: their colours as they are, no shading.
const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	vec3 c = COLOR.rgb;
	ALBEDO = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
"""

## DIN 1451 Mittelschrift figures: height 1, width FIG_W, stroke width 1/7
## of the height; centre lines of their strokes (open polylines; closed ones
## end on their first point).
const FIG_W := 0.56
const STROKE := 1.0 / 7.0
const FIG_GAP := 0.12             # between two figures


## [sample of the sign, take-off speed (m/s)] for every sign of the track.
static func spots(path: TrackPath) -> Array:
	var js := AiProfile.jumps(path)
	var out := []
	for g in js:
		var i0: int = g[0]
		var combo := false
		for h in js:
			if h != g:
				var d := path._fwd_dist(int(h[1]), i0)
				if d < COMBO_DIST and path._fwd_dist(int(h[0]), i0) > 0:
					combo = true
		if combo:
			continue
		# SIGN_DIST before it, or where there is no room (loop, hole) a
		# little further back, else closer to it
		var shifts := range(0, int(SIGN_SHIFT), 2) + range(-2, -int(SIGN_SHIFT), -2)
		for back in shifts:
			var at := path.index_at_s(path.s_arr[i0] - SIGN_DIST - back)
			if path.loop_mask[at] == 0 and path.road[at] == 1 and path.bridge_zone[at] == 0:
				out.append([at, AiProfile.plan_jump(path, i0, int(g[1]), AiProfile.VMAX).x])
				break
	return out


## The speed as shown: km/h to 10, mph to 5.
static func shown(v: float, kmh: bool) -> int:
	return int(round(v * 3.6 / 10.0)) * 10 if kmh else int(round(v * 2.23694 / 5.0)) * 5


func build(path: TrackPath, kmh: bool) -> SpeedSigns:
	name = "SpeedSigns"
	var kit := MeshKit.new()
	var glow := MeshKit.new()
	for sp in spots(path):
		var i: int = sp[0]
		var value := shown(float(sp[1]), kmh)
		if path.tunnel[i] == 1 or path.cut[i] == 1:
			_on_wall(kit, glow if path.tunnel[i] == 1 else kit, path, i, value)
		else:
			_gantry(kit, path, i, value)
	if not kit.is_empty():
		add_child(kit.build_instance())
	if not glow.is_empty():
		var lit := glow.build_instance()
		var mat := ShaderMaterial.new()
		mat.shader = Shader.new()
		mat.shader.code = GLOW_SHADER
		lit.material_override = mat
		lit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lit)
	return self


## One sign at sample i in a tunnel or a cut: on the right wall, two
## brackets out from it, the plate reaching over the road edge; its face in
## face_kit (glowing in a tunnel).
func _on_wall(kit: MeshKit, face_kit: MeshKit, path: TrackPath, i: int, value: int) -> void:
	var r := path.right[i].normalized()
	var up := path.tunnel_up(i)
	var fwd := up.cross(r).normalized()        # along the road
	var wall := path.center[i] + r * path.tunnel_half_width(i)
	var mid := WALL_CLEARANCE + PLATE * 0.5
	var c := wall + up * mid - r * (WALL_GAP + PLATE * 0.5)
	var behind := fwd * (PLATE_DEPTH * 0.5 + BAR * 0.3)
	for k in [-0.3, 0.3]:
		var at: Vector3 = wall + up * (mid + float(k) * PLATE) + behind
		kit.bar(at, at - r * (WALL_GAP + PLATE * 0.3), BAR * 0.6, STEEL)
	plate(kit, c, r, up, -fwd, value, face_kit)


## One sign at sample i: gantry and plate.
func _gantry(kit: MeshKit, path: TrackPath, i: int, value: int) -> void:
	var r := path.right_flat[i].normalized()
	var fwd := Vector3(path.forward[i].x, 0.0, path.forward[i].z).normalized()
	var edge := path.center[i] + path.right[i] * path.half_width[i] - Vector3.UP * ARM_DROP
	var foot := edge + r * ARM_OUT
	var top := foot + Vector3.UP * (ARM_DROP + CLEARANCE + PLATE)
	kit.bar(edge - r * 0.3, foot + r * BAR * 0.5, BAR, STEEL)
	kit.bar(foot - Vector3.UP * BAR * 0.5, top, BAR, STEEL)
	# the plate on the post's side facing the traffic
	var c := foot + Vector3.UP * (ARM_DROP + CLEARANCE + PLATE * 0.5) - fwd * (BAR * 0.5 + PLATE_DEPTH * 0.5)
	plate(kit, c, r, Vector3.UP, -fwd, value)


## A Zeichen 380 plate centred at c: x right (as the driver sees it), y up,
## n its face's normal (towards the driver).
static func plate(kit: MeshKit, c: Vector3, x: Vector3, y: Vector3, n: Vector3, value: int, face_kit: MeshKit = null) -> void:
	kit.box(c, Vector3(PLATE, PLATE, PLATE_DEPTH), STEEL, Basis(x, y, n))
	if face_kit != null:
		kit = face_kit
	var face := c + n * (PLATE_DEPTH * 0.5 + 0.005)
	var h := PLATE * 0.5
	_rect(kit, face, x, y, n, -h, -h, h, h, BLUE)
	# white edge band, inset like the original
	var o := PLATE * 0.035
	var b := PLATE * 0.03
	var f2 := face + n * 0.004
	_rect(kit, f2, x, y, n, -h + o, -h + o, h - o, -h + o + b, Palette.WHITE)
	_rect(kit, f2, x, y, n, -h + o, h - o - b, h - o, h - o, Palette.WHITE)
	_rect(kit, f2, x, y, n, -h + o, -h + o, -h + o + b, h - o, Palette.WHITE)
	_rect(kit, f2, x, y, n, h - o - b, -h + o, h - o, h - o, Palette.WHITE)
	# the figures
	var text := str(value)
	var k := text.length()
	var span := k * FIG_W + (k - 1) * FIG_GAP
	var fh := minf(PLATE * 0.5, PLATE * 0.78 / span)
	var x0 := -span * fh * 0.5
	for ch in text:
		_figure(kit, f2, x, y, n, int(ch), x0, -fh * 0.5, fh)
		x0 += (FIG_W + FIG_GAP) * fh


static func _rect(kit: MeshKit, o: Vector3, x: Vector3, y: Vector3, n: Vector3, x0: float, y0: float, x1: float, y1: float, col: Color) -> void:
	kit.quad(o + x * x0 + y * y0, o + x * x1 + y * y0, o + x * x1 + y * y1, o + x * x0 + y * y1, col)


## Figure d (0..9) with its lower left corner at (fx, fy) of the plate, height fh.
static func _figure(kit: MeshKit, o: Vector3, x: Vector3, y: Vector3, n: Vector3, d: int, fx: float, fy: float, fh: float) -> void:
	var w := STROKE * fh
	for line in figure_lines(d):
		var pts: PackedVector2Array = line
		var closed := pts.size() > 2 and pts[0].distance_to(pts[pts.size() - 1]) < 1e-4
		var p3 := []
		for p in pts:
			p3.append(o + x * (fx + p.x * fh) + y * (fy + p.y * fh))
		for s in pts.size() - 1:
			var a: Vector3 = p3[s]
			var b: Vector3 = p3[s + 1]
			var along := (b - a).normalized()
			var side := n.cross(along).normalized() * (w * 0.5)
			kit.quad(a - side, b - side, b + side, a + side, Palette.WHITE)
			# round joints (none at the open ends: DIN cuts them square)
			if s > 0 or closed:
				_disc(kit, a, x, y, w * 0.5)


static func _disc(kit: MeshKit, c: Vector3, x: Vector3, y: Vector3, r: float) -> void:
	var m := 10
	for k in m:
		var a0 := TAU * k / m
		var a1 := TAU * (k + 1) / m
		kit.tri(c, c + (x * cos(a0) + y * sin(a0)) * r, c + (x * cos(a1) + y * sin(a1)) * r, Palette.WHITE)


## Points of an arc around (cx, cy), radius r, from angle a0 to a1 (deg).
static func _arc(cx: float, cy: float, r: float, a0: float, a1: float, steps := 14) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in steps + 1:
		var a := deg_to_rad(lerpf(a0, a1, float(k) / steps))
		out.append(Vector2(cx + r * cos(a), cy + r * sin(a)))
	return out


## The strokes of DIN 1451 figure d: centre lines in a box of height 1 and
## width FIG_W (the strokes reach half a stroke width beyond them).
static func figure_lines(d: int) -> Array:
	var h := STROKE * 0.5
	var x0 := h
	var x1 := FIG_W - h
	var xm := FIG_W * 0.5
	var y0 := h
	var y1 := 1.0 - h
	var r := xm - h                      # bowls as wide as the figure
	match d:
		0:
			var p := PackedVector2Array([Vector2(x0, y1 - r), Vector2(x0, y0 + r)])
			p.append_array(_arc(xm, y0 + r, r, 180.0, 360.0))
			p.append(Vector2(x1, y1 - r))
			p.append_array(_arc(xm, y1 - r, r, 0.0, 180.0))
			return [p]
		1:
			var sx := FIG_W * 0.62
			return [PackedVector2Array([Vector2(sx, y0), Vector2(sx, y1), Vector2(sx - 0.26, y1 - 0.24)])]
		2:
			var p := _arc(xm, y1 - r, r, 160.0, -38.0)
			p.append(Vector2(x0, y0))
			p.append(Vector2(x1 + h * 0.5, y0))
			return [p]
		3:
			var cy := y0 + 0.24
			var rr := r + 0.02
			var p := PackedVector2Array([Vector2(x0 + 0.02, y1), Vector2(x1, y1)])
			var start := Vector2(xm + rr * cos(deg_to_rad(105.0)), cy + rr * sin(deg_to_rad(105.0)))
			p.append(start)
			p.append_array(_arc(xm, cy, rr, 105.0, -155.0, 20))
			return [p]
		4:
			var sx := FIG_W * 0.7
			var by := 0.3
			return [PackedVector2Array([Vector2(sx, y0), Vector2(sx, y1), Vector2(x0, by), Vector2(x1 + h * 0.5, by)])]
		5:
			var cy := y0 + 0.24
			var rr := r + 0.02
			var p := PackedVector2Array([Vector2(x1, y1), Vector2(x0 + 0.02, y1), Vector2(x0 + 0.02, 0.56)])
			p.append_array(_arc(xm, cy, rr, 128.0, -155.0, 20))
			return [p]
		6:
			var cy := y0 + r
			var bowl := _arc(xm, cy, r, 0.0, 360.0, 24)
			var a := deg_to_rad(165.0)
			return [bowl, PackedVector2Array([Vector2(xm + r * cos(a), cy + r * sin(a)), Vector2(x1 - 0.06, y1)])]
		7:
			return [PackedVector2Array([Vector2(x0, y1), Vector2(x1, y1), Vector2(x0 + 0.1, y0)])]
		8:
			var ru := r - 0.03
			var rl := r
			return [_arc(xm, y1 - ru, ru, 0.0, 360.0, 24), _arc(xm, y0 + rl, rl, 0.0, 360.0, 24)]
		9:
			# a 6 turned round
			var out := []
			for line in figure_lines(6):
				var q := PackedVector2Array()
				for p in (line as PackedVector2Array):
					q.append(Vector2(FIG_W - p.x, 1.0 - p.y))
				out.append(q)
			return out
	return []
