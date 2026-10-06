class_name PixelScreen
extends Control
## Retained-mode 2D "screen": collect text/rect commands, then commit() redraws.

var background := Palette.PANEL_BG
var _items: Array = []


func clear() -> void:
	_items.clear()


func rect(r: Rect2, color: Color) -> void:
	_items.append({"rect": r, "color": color})


func frame(r: Rect2, color: Color, w: float = 3.0) -> void:
	rect(Rect2(r.position, Vector2(r.size.x, w)), color)
	rect(Rect2(r.position + Vector2(0, r.size.y - w), Vector2(r.size.x, w)), color)
	rect(Rect2(r.position, Vector2(w, r.size.y)), color)
	rect(Rect2(r.position + Vector2(r.size.x - w, 0), Vector2(w, r.size.y)), color)


func text(x: float, y: float, s: String, color: Color = Palette.WHITE, scale: float = 3.0) -> void:
	_items.append({"text": s, "pos": Vector2(x, y), "color": color, "scale": scale})


func text_centered(y: float, s: String, color: Color = Palette.WHITE, scale: float = 3.0) -> void:
	text((size.x - PixelFont.text_width(s, scale)) * 0.5, y, s, color, scale)


func text_right(x_right: float, y: float, s: String, color: Color = Palette.WHITE, scale: float = 3.0) -> void:
	text(x_right - PixelFont.text_width(s, scale), y, s, color, scale)


func commit() -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background)
	for it in _items:
		if it.has("rect"):
			draw_rect(it["rect"], it["color"])
		else:
			PixelFont.draw_text(self, it["pos"], it["text"], it["color"], it["scale"])
