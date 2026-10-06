class_name Panel3D
extends Node3D
## A PixelScreen rendered into a SubViewport and shown on a quad in 3D space.

var screen: PixelScreen
var viewport: SubViewport
var quad: MeshInstance3D


func setup(pixel_size: Vector2i, world_size: Vector2, always_on_top := false) -> Panel3D:
	viewport = SubViewport.new()
	viewport.size = pixel_size
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	screen = PixelScreen.new()
	screen.size = Vector2(pixel_size)
	viewport.add_child(screen)

	var mesh := QuadMesh.new()
	mesh.size = world_size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = viewport.get_texture()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	if always_on_top:
		mat.no_depth_test = true
		mat.render_priority = 10
	quad = MeshInstance3D.new()
	quad.mesh = mesh
	quad.material_override = mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)
	return self
