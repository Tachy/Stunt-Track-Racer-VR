class_name EditorView
extends RefCounted
## How the track editor's screen relates to the 3D world: the mouse ray
## through a screen point, where a world point appears on the screen, and how
## many metres a pixel covers there. Desktop: the window is the camera's
## image. VR: the screen lies on a sphere around the seat's eye point
## (VrEditorHost); a pixel is a fixed angle there - x the yaw, y the pitch -
## seen from the sphere's centre. The head moves freely inside it (6DOF):
## the mouse ray runs from the eye as it is now through the pointer's spot on
## the sphere, so it meets what the pointer is seen in front of.

var camera: Camera3D
## VR only: the sphere's frame (origin: its centre, -z: the middle of the
## screen), its radius, the angle of a pixel (degrees) and the screen size.
var dome: Node3D
var radius := 2.0
var deg_per_px := 0.05
var size_px := Vector2.ONE


func _init(cam: Camera3D, vr_dome: Node3D = null, dome_radius := 2.0, degrees_per_pixel := 0.05, screen_px := Vector2.ONE) -> void:
	camera = cam
	dome = vr_dome
	radius = dome_radius
	deg_per_px = degrees_per_pixel
	size_px = screen_px


## Global transform (outside the tree - headless tests - the node's own).
static func _xf(n: Node3D) -> Transform3D:
	return n.global_transform if n.is_inside_tree() else n.transform


## VR: the direction (sphere frame) of screen point pos.
func _dir(pos: Vector2) -> Vector3:
	var yaw := deg_to_rad((pos.x - size_px.x * 0.5) * deg_per_px)
	var pitch := deg_to_rad((size_px.y * 0.5 - pos.y) * deg_per_px)
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


## VR: the spot of screen point pos on the sphere (world).
func sphere_point(pos: Vector2) -> Vector3:
	return _xf(dome) * (_dir(pos) * radius)


## Mouse ray through screen point pos: [from, dir].
func ray(pos: Vector2) -> Array:
	if dome == null:
		return [camera.project_ray_origin(pos), camera.project_ray_normal(pos)]
	var eye := _xf(camera).origin
	return [eye, (sphere_point(pos) - eye).normalized()]


## Screen position of world point p (where the line from the eye to it
## passes the sphere), or null when it is behind.
func to_screen(p: Vector3) -> Variant:
	if dome == null:
		return null if camera.is_position_behind(p) else camera.unproject_position(p)
	var t := _xf(dome)
	var eye := _xf(camera).origin
	var d := (p - eye).normalized()
	# eye + k*d on the sphere (the eye is inside it)
	var oc := eye - t.origin
	var b := d.dot(oc)
	var disc := b * b - (oc.length_squared() - radius * radius)
	if disc < 0.0:
		return null
	var v := t.basis.inverse() * (eye + d * (-b + sqrt(disc)) - t.origin)
	if v.z >= 0.0:
		return null
	var yaw := rad_to_deg(atan2(v.x, -v.z))
	var pitch := rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length()))
	return Vector2(size_px.x * 0.5 + yaw / deg_per_px, size_px.y * 0.5 - pitch / deg_per_px)


## Metres one screen pixel covers at world point p.
func pixel_metres(p: Vector3) -> float:
	var eye := _xf(camera).origin
	if dome == null:
		var h := camera.get_viewport().get_visible_rect().size.y
		return HeightRibbon.metres_per_pixels(1.0, eye.distance_to(p), camera.fov, h)
	return deg_to_rad(deg_per_px) * eye.distance_to(p)     # (the eye is near the centre)
