class_name CarPhotos
extends Node3D
## Debug (--car-photos): close-ups of the car model - steering wheel,
## front suspension, engine, rear - saved to user://screenshots/car_*.png,
## then quits. For checking model changes without driving.

const SHOTS := [
	["wheel", Vector3(0.0, 0.92, 0.95), Vector3(0, 0.56, 0.58)],
	["suspension", Vector3(-2.3, 0.15, -2.6), Vector3(-0.8, -0.1, -1.6)],
	["engine", Vector3(-1.5, 1.1, -2.4), Vector3(0, 0.35, -0.95)],
	["rear", Vector3(2.4, 0.3, 2.5), Vector3(0.8, -0.1, 1.15)],
	["exhaust", Vector3(-0.95, 0.75, -0.2), Vector3(-0.3, 0.35, -0.95)],
]


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.6, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0)
	add_child(sun)
	var car := CarModel.new().build(Palette.PLAYER_BODY, true)
	add_child(car)
	car.set_steering_wheel_deg(30.0)
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	for s in SHOTS:
		cam.look_at_from_position(s[1], s[2], Vector3.UP)
		cam.make_current()
		for i in 4:
			await get_tree().process_frame
		var path := "user://screenshots/car_%s.png" % s[0]
		get_viewport().get_texture().get_image().save_png(path)
		print("[Photo] ", ProjectSettings.globalize_path(path))
	get_tree().quit()
