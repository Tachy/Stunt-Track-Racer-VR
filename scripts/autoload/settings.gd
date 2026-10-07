extends Node
## Persistent user settings (user://settings.cfg).

const PATH := "user://settings.cfg"

## 0 = view always level with the horizon, 1 = view fixed to the car.
var tilt_follow := 0.5
## Physical rotation range configured for the wheel (Thrustmaster control panel).
var wheel_range_deg := 900.0
## Maximum road-wheel steering angle. The steering wheel at its end stop
## (wheel_range_deg / 2) gives exactly this angle - linear 1:1 mapping.
var max_wheel_angle_deg := 32.0
var speed_kmh := false
var volume := 8
var shadows := true
## UI language: "en" (default) or "de".
var language := "en"
var seat_height := 0.0
## Online race server: "host" or "host:port" (default port 27015), set in
## the ONLINE menu, as are the player's name and car colour.
var server_address := ""
var player_name := OS.get_environment("USERNAME").to_upper().left(16) if OS.get_environment("USERNAME") != "" else "PLAYER"
var player_color := Palette.PLAYER_BODY
var recenter_offset := Transform3D.IDENTITY
var has_recenter := false


func _ready() -> void:
	load_settings()
	Lang.current = language


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	tilt_follow = cfg.get_value("view", "tilt_follow", tilt_follow)
	seat_height = cfg.get_value("view", "seat_height", seat_height)
	has_recenter = cfg.get_value("view", "has_recenter", false)
	recenter_offset = cfg.get_value("view", "recenter_offset", Transform3D.IDENTITY)
	wheel_range_deg = cfg.get_value("wheel", "range_deg", wheel_range_deg)
	max_wheel_angle_deg = cfg.get_value("wheel", "max_wheel_angle_deg", max_wheel_angle_deg)
	speed_kmh = cfg.get_value("game", "speed_kmh", speed_kmh)
	volume = cfg.get_value("game", "volume", volume)
	shadows = cfg.get_value("view", "shadows", shadows)
	language = cfg.get_value("game", "language", language)
	server_address = cfg.get_value("online", "server", server_address)
	player_name = cfg.get_value("online", "player_name", player_name)
	player_color = cfg.get_value("online", "player_color", player_color)
	apply_volume()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("view", "tilt_follow", tilt_follow)
	cfg.set_value("view", "seat_height", seat_height)
	cfg.set_value("view", "has_recenter", has_recenter)
	cfg.set_value("view", "recenter_offset", recenter_offset)
	cfg.set_value("wheel", "range_deg", wheel_range_deg)
	cfg.set_value("wheel", "max_wheel_angle_deg", max_wheel_angle_deg)
	cfg.set_value("game", "speed_kmh", speed_kmh)
	cfg.set_value("game", "volume", volume)
	cfg.set_value("view", "shadows", shadows)
	cfg.set_value("game", "language", language)
	cfg.set_value("online", "server", server_address)
	cfg.set_value("online", "player_name", player_name)
	cfg.set_value("online", "player_color", player_color)
	cfg.save(PATH)


func apply_volume() -> void:
	var db := linear_to_db(clampf(volume / 10.0, 0.0001, 1.0))
	AudioServer.set_bus_volume_db(0, db)
