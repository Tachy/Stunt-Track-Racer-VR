class_name MeshKit
extends RefCounted
## Small flat-shaded mesh builder (per-face normals, vertex colours).
## The shared material is lit by the sun (Lambert, no specular) and receives
## shadows, which keeps the flat retro look but shows the car's shadow on the
## track - very helpful to judge jumps in VR.
## Set `shade = true` to bake simple lighting into colours instead (unlit use).

const LIGHT_DIR := Vector3(0.45, 0.8, 0.35)
const SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_disabled, diffuse_lambert;

varying vec3 v_albedo;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	v_albedo = srgb_to_linear(COLOR.rgb);
}

void fragment() {
	ALBEDO = v_albedo;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	// abs(): face winding is not consistent, so light both sides alike
	DIFFUSE_LIGHT += abs(dot(NORMAL, LIGHT)) * ATTENUATION * LIGHT_COLOR / PI;
}
"""

static var _material: ShaderMaterial
static var _see_through_shader: Shader

var verts := PackedVector3Array()
var colors := PackedColorArray()
var normals := PackedVector3Array()
var shade := false


static func material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = sh
	return _material


## Material that lets the world behind show through (the editor's ground and
## tunnel walls): opacity alpha, drawn without depth (no shadows either).
static func see_through_material(alpha: float) -> ShaderMaterial:
	if _see_through_shader == null:
		_see_through_shader = Shader.new()
		_see_through_shader.code = SHADER 			.replace("render_mode cull_disabled,", "render_mode blend_mix, depth_draw_never, cull_disabled,") 			.replace("varying vec3 v_albedo;", "varying vec3 v_albedo;
uniform float alpha = 1.0;") 			.replace("SPECULAR = 0.0;", "SPECULAR = 0.0;
	ALPHA = alpha;")
	var mat := ShaderMaterial.new()
	mat.shader = _see_through_shader
	mat.set_shader_parameter("alpha", alpha)
	return mat


static func shade_color(col: Color, n: Vector3) -> Color:
	var k := 0.62 + 0.38 * absf(n.dot(LIGHT_DIR.normalized()))
	return Color(col.r * k, col.g * k, col.b * k, col.a)


func is_empty() -> bool:
	return verts.is_empty()


func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	var c2 := shade_color(col, n) if shade else col
	verts.append(a)
	verts.append(b)
	verts.append(c)
	for i in 3:
		colors.append(c2)
		normals.append(n)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	tri(a, b, c, col)
	tri(a, c, d, col)


## Axis-aligned (in the given basis) box around center.
func box(center: Vector3, size: Vector3, col: Color, basis := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var p := []
	for i in 8:
		var v := Vector3(
			h.x if (i & 1) else -h.x,
			h.y if (i & 2) else -h.y,
			h.z if (i & 4) else -h.z)
		p.append(center + basis * v)
	quad(p[0], p[1], p[3], p[2], col) # -z
	quad(p[4], p[6], p[7], p[5], col) # +z
	quad(p[0], p[2], p[6], p[4], col) # -x
	quad(p[1], p[5], p[7], p[3], col) # +x
	quad(p[0], p[4], p[5], p[1], col) # -y
	quad(p[2], p[3], p[7], p[6], col) # +y


## Square-section bar from p0 to p1.
func bar(p0: Vector3, p1: Vector3, thickness: float, col: Color) -> void:
	var d := p1 - p0
	var length := d.length()
	if length < 1e-5:
		return
	var up := Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var basis := Basis.looking_at(d / length, up)
	box((p0 + p1) * 0.5, Vector3(thickness, thickness, length), col, basis)


## Cylinder along an axis (unit vector), centred at center.
func cylinder(center: Vector3, axis: Vector3, radius: float, length: float, segments: int, col: Color, cap_col := Color(-1, 0, 0)) -> void:
	axis = axis.normalized()
	var helper := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var u := axis.cross(helper).normalized()
	var v := axis.cross(u).normalized()
	var a := center - axis * length * 0.5
	var b := center + axis * length * 0.5
	var cc := col if cap_col.r < 0.0 else cap_col
	for i in segments:
		var t0 := TAU * i / segments
		var t1 := TAU * (i + 1) / segments
		var r0 := (u * cos(t0) + v * sin(t0)) * radius
		var r1 := (u * cos(t1) + v * sin(t1)) * radius
		quad(a + r0, a + r1, b + r1, b + r0, col)
		tri(a, a + r1, a + r0, cc)
		tri(b, b + r0, b + r1, cc)


## Round tube along a polyline (wire, pipe, ring): a `sides`-gon swept with a
## twist-free (parallel-transported) frame, so segments join without gaps.
## closed = the last point connects back to the first.
func tube(points: PackedVector3Array, radius: float, sides: int, col: Color, closed := false) -> void:
	var n := points.size()
	if n < 2:
		return
	var tangents: Array[Vector3] = []
	for i in n:
		var a := points[(i - 1 + n) % n] if (closed or i > 0) else points[i]
		var b := points[(i + 1) % n] if (closed or i < n - 1) else points[i]
		tangents.append((b - a).normalized())
	var helper := Vector3.UP if absf(tangents[0].dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var u := tangents[0].cross(helper).normalized()
	var rings: Array = []
	for i in n:
		var t := tangents[i]
		u = (u - t * u.dot(t)).normalized()
		var v := t.cross(u)
		var ring := PackedVector3Array()
		for k in sides:
			var ang := TAU * k / sides
			ring.append(points[i] + (u * cos(ang) + v * sin(ang)) * radius)
		rings.append(ring)
	for i in (n if closed else n - 1):
		var r0: PackedVector3Array = rings[i]
		var r1: PackedVector3Array = rings[(i + 1) % n]
		for k in sides:
			var k1 := (k + 1) % sides
			quad(r0[k], r0[k1], r1[k1], r1[k], col)


## Pyramid / cone-like peak used for scenery.
func peak(base_center: Vector3, radius: float, height: float, sides: int, col: Color, snow_col := Color(-1, 0, 0), snow_frac := 0.0, rot := 0.0) -> void:
	var top := base_center + Vector3(0, height, 0)
	for i in sides:
		var t0 := rot + TAU * i / sides
		var t1 := rot + TAU * (i + 1) / sides
		var p0 := base_center + Vector3(cos(t0), 0, sin(t0)) * radius
		var p1 := base_center + Vector3(cos(t1), 0, sin(t1)) * radius
		if snow_col.r >= 0.0 and snow_frac > 0.0:
			var s0 := p0.lerp(top, 1.0 - snow_frac)
			var s1 := p1.lerp(top, 1.0 - snow_frac)
			quad(p0, p1, s1, s0, col)
			tri(s0, s1, top, snow_col)
		else:
			tri(p0, p1, top, col)


func build(mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material())
	return mesh


## alpha < 1: see-through (see_through_material), casting no shadow.
func build_instance(alpha := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = build()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if alpha < 1.0:
		mi.material_override = see_through_material(alpha)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
