class_name Dashboard
extends Panel3D
## In-car instrument panel in the style of the original, three rows:
## lap, boost, distance to opponent with leader flag / lap time and best lap
## (or a message) / speed bar, frame rate and latency, speed.

const PX := Vector2i(640, 140)
const SIZE := Vector2(0.42, 0.42 * 140.0 / 640.0)
## Height of the earlier 4-row panel: the bottom edge stays where it was.
const OLD_HEIGHT := 0.138
## The whole display shrunk around its centre (content and layout unchanged).
const DISPLAY_SCALE := 0.8
const REFRESH := 1.0 / 15.0

var _timer := 0.0
var _data := {}
var _blink := 0.0


func _init() -> void:
	setup(PX, SIZE)
	name = "Dashboard"
	position.y = -(OLD_HEIGHT - SIZE.y) * 0.5
	scale = Vector3.ONE * DISPLAY_SCALE


func set_data(d: Dictionary) -> void:
	_data = d


static func fmt_time(t: float) -> String:
	if t < 0.0 or t > 5999.0:
		return "-:--.-"
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return "%d:%04.1f" % [m, s]


func _process(delta: float) -> void:
	_timer -= delta
	_blink += delta
	if _timer > 0.0:
		return
	_timer = REFRESH
	_redraw()


func _redraw() -> void:
	var sc := screen
	sc.clear()
	if _data.is_empty():
		sc.commit()
		return
	var d := _data
	var s := 4.0
	sc.frame(Rect2(0, 0, PX.x, PX.y), Palette.DARK_BLUE, 4)
	# row 1: lap, boost, gap + leader flag
	sc.text(16, 12, "L%d/%d" % [d.get("lap", 1), d.get("laps", 3)], Palette.YELLOW, s)
	sc.text(170, 12, "B%02d" % d.get("boost", 0), Palette.LIGHT_BLUE if not d.get("boosting", false) else Palette.WHITE, s)
	if d.has("gap"):
		var gap: float = d["gap"]
		var col := Palette.GREEN if gap >= 0.0 else Palette.RED
		sc.text_right(560, 12, "%+dM" % int(gap), col, s)
		# leader flag
		sc.rect(Rect2(580, 10, 42, 26), col)
		sc.rect(Rect2(576, 10, 4, 36), Palette.WHITE)

	# row 2: lap time and best lap - or a blinking message in their place
	var msg: String = d.get("message", "")
	if msg != "":
		if fmod(_blink, 0.8) < 0.55:
			sc.text_centered(56, msg, Palette.YELLOW, s)
	else:
		sc.text(16, 56, Lang.t("TIME ") + fmt_time(d.get("lap_time", 0.0)), Palette.WHITE, s)
		sc.text_right(624, 56, Lang.t("BEST ") + fmt_time(d.get("best", -1.0)), Palette.WHITE, s)

	# row 3: frame rate / latency, speed bar, speed (the middle is where the
	# steering wheel's top marker sits in the driver's view)
	var speed_ms: float = d.get("speed", 0.0)
	var mph := absf(speed_ms) * 2.23694
	var bar := Rect2(176, 98, 236, 32)
	sc.rect(bar, Palette.BLACK)
	var frac := clampf(mph / 250.0, 0.0, 1.0)
	var segs := 14
	for i in int(frac * segs + 0.5):
		var col := Palette.GREEN if i < 8 else (Palette.YELLOW if i < 12 else Palette.RED)
		sc.rect(Rect2(bar.position.x + 3 + i * (bar.size.x - 6) / segs, bar.position.y + 4, (bar.size.x - 6) / segs - 3, bar.size.y - 8), col)
	var unit_text := "%d KMH" % int(absf(speed_ms) * 3.6) if Settings.speed_kmh else "%d MPH" % int(mph)
	sc.text_right(624, 100, unit_text, Palette.WHITE, s)
	var status: PackedStringArray = d.get("status", PackedStringArray())
	for i in status.size():
		sc.text(16, 100 + i * 16, status[i], Palette.LIGHT_BLUE, 1.8)
	sc.commit()
