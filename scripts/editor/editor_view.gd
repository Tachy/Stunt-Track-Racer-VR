class_name EditorView
extends RefCounted
## How the track editor's screen relates to the 3D world: the mouse ray
## through a screen point, where a world point appears on the screen, and how
## many metres a pixel covers there. Desktop: the window is the camera's
## image. VR: the screen is a panel in the world (VrEditorHost), seen from
## the head; its pixels are the panel's texels.

var camera: Camera3D
## VR only: the panel (a quad of panel_size metres, centred on its origin,
## facing +z) showing the screen of panel_px pixels.
var panel: Node3D
var panel_size := Vector2.ONE
var panel_px := Vector2.ONE


func _init(cam: Camera3D, vr_panel: Node3D = null, size_m := Vector2.ONE, size_px := Vector2.ONE) -> void:
	camera = cam
	panel = vr_panel
	panel_size = size_m
	panel_px = size_px


func _eye() -> Vector3:
	return camera.global_position


## Panel point (world) of screen point pos.
func _panel_point(pos: Vector2) -> Vector3:
	var local := Vector3((pos.x / panel_px.x - 0.5) * panel_size.x, (0.5 - pos.y / panel_px.y) * panel_size.y, 0.0)
	return panel.global_transform * local


## Mouse ray through screen point pos: [from, dir].
func ray(pos: Vector2) -> Array:
	if panel == null:
		return [camera.project_ray_origin(pos), camera.project_ray_normal(pos)]
	var e := _eye()
	return [e, (_panel_point(pos) - e).normalized()]


## Screen position of world point p, or null when it is behind the eye.
func to_screen(p: Vector3) -> Variant:
	if panel == null:
		return null if camera.is_position_behind(p) else camera.unproject_position(p)
	var e := _eye()
	var t := panel.global_transform
	var n := t.basis.z.normalized()
	var den := (p - e).dot(n)
	if absf(den) < 1e-6:
		return null
	var k := (t.origin - e).dot(n) / den
	if k <= 0.0:
		return null
	var local := t.affine_inverse() * (e + (p - e) * k)
	return Vector2((local.x / panel_size.x + 0.5) * panel_px.x, (0.5 - local.y / panel_size.y) * panel_px.y)


## Metres one screen pixel covers at world point p.
func pixel_metres(p: Vector3) -> float:
	var d := _eye().distance_to(p)
	if panel == null:
		var h := camera.get_viewport().get_visible_rect().size.y
		return HeightRibbon.metres_per_pixels(1.0, d, camera.fov, h)
	var pd := _eye().distance_to(panel.global_position)
	return panel_size.y / panel_px.y * d / maxf(pd, 0.01)
