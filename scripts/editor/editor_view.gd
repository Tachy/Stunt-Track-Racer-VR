class_name EditorView
extends RefCounted
## How the track editor's screen relates to the 3D world: the mouse ray
## through a screen point, where a world point appears on the screen, and how
## many metres a pixel covers there. Desktop: the window is the camera's
## image. VR: the screen lies on a sphere around the eye (VrEditorHost); a
## pixel is a fixed angle there - x the yaw, y the pitch - so every pixel is
## a direction from the eye and the mouse ray goes straight through it.

var camera: Camera3D
## VR only: the sphere's frame (origin: the eye, -z: the middle of the
## screen), the angle of a pixel (degrees) and the screen size (pixels).
var dome: Node3D
var deg_per_px := 0.05
var size_px := Vector2.ONE


func _init(cam: Camera3D, vr_dome: Node3D = null, degrees_per_pixel := 0.05, screen_px := Vector2.ONE) -> void:
	camera = cam
	dome = vr_dome
	deg_per_px = degrees_per_pixel
	size_px = screen_px


## VR: the direction (dome frame) of screen point pos.
func _dir(pos: Vector2) -> Vector3:
	var yaw := deg_to_rad((pos.x - size_px.x * 0.5) * deg_per_px)
	var pitch := deg_to_rad((size_px.y * 0.5 - pos.y) * deg_per_px)
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


## Mouse ray through screen point pos: [from, dir].
func ray(pos: Vector2) -> Array:
	if dome == null:
		return [camera.project_ray_origin(pos), camera.project_ray_normal(pos)]
	var t := dome.global_transform
	return [t.origin, (t.basis * _dir(pos)).normalized()]


## Screen position of world point p, or null when it is behind the eye.
func to_screen(p: Vector3) -> Variant:
	if dome == null:
		return null if camera.is_position_behind(p) else camera.unproject_position(p)
	var t := dome.global_transform
	var v := t.basis.inverse() * (p - t.origin)
	if v.z >= 0.0:
		return null
	var yaw := rad_to_deg(atan2(v.x, -v.z))
	var pitch := rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length()))
	return Vector2(size_px.x * 0.5 + yaw / deg_per_px, size_px.y * 0.5 - pitch / deg_per_px)


## Metres one screen pixel covers at world point p.
func pixel_metres(p: Vector3) -> float:
	if dome == null:
		var h := camera.get_viewport().get_visible_rect().size.y
		return HeightRibbon.metres_per_pixels(1.0, camera.global_position.distance_to(p), camera.fov, h)
	return deg_to_rad(deg_per_px) * dome.global_position.distance_to(p)
