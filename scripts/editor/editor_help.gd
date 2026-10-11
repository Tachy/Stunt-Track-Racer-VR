class_name EditorHelp
extends PanelContainer
## The track editor's help (H or the HELP button): the keys and mouse actions
## of the plan or the height stage, by topic, in two columns (key, what it
## does). Lies over the editor and lets the mouse through (the wheel scrolls
## it when it does not fit).

const BG := Color(0.0, 0.0, 0.0, 0.72)
const HEAD := Color("#ffd400")
const KEY := Color("#9fe0ff")
const FONT_SIZE := 14

## Sections: [title, [[key, what], ...]] (English, Lang.t() translates).
const PLAN := [
	["Drawing", [
		["Click", "Start point, then the end of the start straight"],
		["Click", "Place the previewed piece (green: closes the lap)"],
		["O / Shift+O", "Loop (shifted to the right / left; radius: in the heights)"],
	]],
	["Closed lap", [
		["Click on the road", "Mark a piece (click beside: unmark)"],
		["Shift+click", "Mark a stretch up to here"],
		["Drag the marked", "Move them (gaps are filled, red: no fit)"],
		["Arrow keys", "Move the marked one grid step"],
		["Right click", "Delete the marked, draw the gap to the yellow mark"],
		["Drag the start line", "Move it along the straights"],
		["R", "Reverse the direction of the lap"],
	]],
	["View", [
		["Mouse wheel", "Zoom"],
		["Right mouse + drag", "Move the view"],
	]],
	["General", [
		["Esc / Ctrl+Z", "Undo (e.g. the last piece)"],
		["Ctrl+Y", "Redo"],
		["Ctrl+S", "Save"],
		["Tab", "Heights (closed lap only)"],
		["H", "This help on / off"],
	]],
]

const HEIGHT := [
	["Height points", [
		["Click on a point", "Select and drag (along the lap, up / down)"],
		["Shift+click", "Mark all points from the one marked last"],
		["Ctrl+click", "Mark a point too / no longer"],
		["Double click on the road", "New point"],
		["Up / Down", "Height of the point (Shift: x4)"],
		["Left / Right", "Point 1 m back / on along the lap"],
		["C", "Kink at the point on / off"],
		["Right click / Del", "Delete the point (Del: all marked)"],
		["Steeper than 80°", "Vertical wall (pit / ski jump)"],
	]],
	["Waves and banking", [
		["W", "Wave at the edge of the road under the mouse"],
		["U", "Hold the curve's banking up to the mouse"],
		["Click on a mark", "Select and drag along the lap"],
		["Arrow keys", "Move the mark (Up / Down: wave height, Shift: x4)"],
		["Right click / Del", "Delete the mark"],
	]],
	["Loops", [
		["Click on the green mark", "Select the loop (mark on its top)"],
		["Up / Down", "Loop radius 8 to 30 m (Shift: x4)"],
	]],
	["Pieces", [
		["Click on the road", "Select its piece (red)"],
		["B", "Drawbridge on / off"],
	]],
	["Camera", [
		["Double click on a point", "The camera turns around it"],
		["Right mouse + drag", "Turn"],
		["Middle mouse + drag", "Move"],
		["Mouse wheel", "Distance"],
		["Plan (top left)", "Click: camera to the piece, right mouse: move, wheel: zoom"],
	]],
	["General", [
		["Esc", "Undo"],
		["Ctrl+S", "Save"],
		["Tab", "Back to the plan"],
		["H", "This help on / off"],
	]],
]

var _scroll: ScrollContainer
var _list: VBoxContainer
var _shown := ""          # stage, language and columns the rows are built for


func _init() -> void:
	name = "EditorHelp"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS     # the wheel scrolls, clicks go on to the editor
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)


## The sections for a stage ("plan" / "height").
static func sections(mode: String) -> Array:
	return HEIGHT if mode == "height" else PLAN


## Every text of the help (for the translation test).
static func texts() -> Array:
	var out := []
	for s in PLAN + HEIGHT:
		out.append(s[0])
		for r in s[1]:
			out.append_array(r)
	return out


## Shows the help for the stage at rect's top left, at most rect's size: in
## one column, or in two side by side if one is too tall (scrolls if that
## is too tall as well).
func place(mode: String, rect: Rect2) -> void:
	var inner := get_theme_stylebox("panel").get_minimum_size()
	var want := Vector2.ZERO
	for cols in [1, 2]:
		var key := "%s %s %d" % [mode, Lang.current, cols]
		if key != _shown:
			_shown = key
			_build(sections(mode), cols)
		want = _list.get_combined_minimum_size() + inner
		if want.y <= rect.size.y:
			break
	position = rect.position
	size = Vector2(minf(want.x, rect.size.x), minf(want.y, maxf(rect.size.y, 60.0)))


## The sections in cols columns (about the same number of lines each), each
## column one grid: the keys and texts line up through all its sections.
func _build(secs: Array, cols: int) -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var lines := 0
	for s in secs:
		lines += 1 + (s[1] as Array).size()
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 28)
	_list.add_child(row)
	var grid: GridContainer = null
	var done := 0
	for s in secs:
		# a new column once this one has its share
		if grid == null or (row.get_child_count() < cols and done >= lines * row.get_child_count() / cols):
			grid = GridContainer.new()
			grid.columns = 2
			grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_theme_constant_override("h_separation", 16)
			grid.add_theme_constant_override("v_separation", 1)
			row.add_child(grid)
		elif grid.get_child_count() > 0:
			for i in 2:      # a gap between sections
				var gap := Control.new()
				gap.custom_minimum_size.y = 5
				gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
				grid.add_child(gap)
		grid.add_child(_label(Lang.t(s[0]), HEAD))
		grid.add_child(_label("", HEAD))
		for r in s[1]:
			grid.add_child(_label(Lang.t(r[0]), KEY))
			grid.add_child(_label(Lang.t(r[1]), Color.WHITE))
		done += 1 + (s[1] as Array).size()


func _label(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	l.add_theme_color_override("font_color", col)
	return l
