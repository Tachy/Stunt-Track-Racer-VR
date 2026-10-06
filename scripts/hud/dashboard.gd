class_name Dashboard
extends Panel3D
## In-car instrument panel in the style of the original: lap, boost,
## distance to opponent, lap times, speed bar, leader flag and messages.

const PX := Vector2i(640, 210)
const SIZE := Vector2(0.42, 0.138)
const REFRESH := 1.0 / 15.0

var _timer := 0.0
var _data := {}
var _blink := 0.0


func _init() -> void:
	setup(PX, SIZE)
	name = "Dashboard"


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
	sc.text(16, 14, "L%d/%d" % [d.get("lap", 1), d.get("laps", 3)], Palette.YELLOW, s)
	sc.text(170, 14, "B%02d" % d.get("boost", 0), Palette.LIGHT_BLUE if not d.get("boosting", false) else Palette.WHITE, s)
	if d.has("gap"):
		var gap: float = d["gap"]
		var col := Palette.GREEN if gap >= 0.0 else Palette.RED
		sc.text_right(560, 14, "%+dM" % int(gap), col, s)
		# leader flag
		sc.rect(Rect2(580, 12, 42, 30), col)
		sc.rect(Rect2(576, 12, 4, 44), Palette.WHITE)
	sc.text(16, 64, Lang.t("TIME ") + fmt_time(d.get("lap_time", 0.0)), Palette.WHITE, s)
	sc.text_right(624, 64, Lang.t("BEST ") + fmt_time(d.get("best", -1.0)), Palette.WHITE, s)

	# speed bar
	var speed_ms: float = d.get("speed", 0.0)
	var mph := absf(speed_ms) * 2.23694
	var bar := Rect2(16, 112, 430, 34)
	sc.rect(bar, Palette.BLACK)
	var frac := clampf(mph / 250.0, 0.0, 1.0)
	var segs := 25
	for i in int(frac * segs + 0.5):
		var col := Palette.GREEN if i < 15 else (Palette.YELLOW if i < 21 else Palette.RED)
		sc.rect(Rect2(bar.position.x + 3 + i * (bar.size.x - 6) / segs, bar.position.y + 4, (bar.size.x - 6) / segs - 3, bar.size.y - 8), col)
	var unit_text := "%d KMH" % int(absf(speed_ms) * 3.6) if Settings.speed_kmh else "%d MPH" % int(mph)
	sc.text_right(624, 116, unit_text, Palette.WHITE, s)

	var msg: String = d.get("message", "")
	if msg != "" and fmod(_blink, 0.8) < 0.55:
		sc.text_centered(166, msg, Palette.YELLOW, s)
	sc.commit()
