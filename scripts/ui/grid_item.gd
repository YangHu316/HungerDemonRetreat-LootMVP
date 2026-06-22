extends Control
class_name GridItemView

const CELL: int = 64

var entry: Dictionary = {}
var rarity_colors: Dictionary = {
	"Common": Color("#888888"),
	"Uncommon": Color("#5cd05c"),
	"Rare": Color("#5b9bff"),
	"Epic": Color("#9b5bff"),
	"Legendary": Color("#ff9000"),
}

func setup(e: Dictionary) -> void:
	entry = e
	var item: ItemData = e["item"]
	var rotated: bool = e.get("rotated", false)
	var w: int = item.grid_h if rotated else item.grid_w
	var h: int = item.grid_w if rotated else item.grid_h
	custom_minimum_size = Vector2(w * CELL, h * CELL)
	size = Vector2(w * CELL, h * CELL)
	mouse_filter = Control.MOUSE_FILTER_PASS
	queue_redraw()

func set_examined(v: bool) -> void:
	entry["examined"] = v
	entry["inspected"] = v
	queue_redraw()

func _draw() -> void:
	if entry.is_empty():
		return
	var item: ItemData = entry["item"]
	var rotated: bool = entry.get("rotated", false)
	var w: int = item.grid_h if rotated else item.grid_w
	var h: int = item.grid_w if rotated else item.grid_h
	var rect := Rect2(Vector2(2, 2), Vector2(w * CELL - 4, h * CELL - 4))
	# 已揭示 = inspected 或 examined
	var revealed: bool = entry.get("inspected", false) or entry.get("examined", false)
	var font := get_theme_default_font()
	if not revealed:
		# 未揭示：半透 0.4 + 居中 "?"
		var faded: Color = item.color
		faded.a = 0.4
		draw_rect(rect, faded)
		# 1px 灰边
		draw_rect(rect, Color(0.3, 0.3, 0.3, 0.6), false, 1.0)
		var fs: int = 32
		var text := "?"
		var ts: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		var pos: Vector2 = rect.position + (rect.size - ts) * 0.5 + Vector2(0, ts.y * 0.85)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 1, 1, 0.85))
	else:
		# 已揭示：正常颜色 + 稀有度边框
		draw_rect(rect, item.color)
		var border: Color = rarity_colors.get(item.rarity, Color.WHITE)
		draw_rect(rect, border, false, 2.0)
		# 食物:在外稀有度边框内再画一圈 freshness tier 色(2px,内缩 3px)
		if item.is_food:
			var tier: int = Freshness.entry_tier(entry)
			var fresh_col: Color = Freshness.color_for(tier)
			var fresh_rect := Rect2(rect.position + Vector2(3, 3), rect.size - Vector2(6, 6))
			draw_rect(fresh_rect, fresh_col, false, 2.0)
		# 左上首字
		if item.display_name.length() > 0:
			draw_string(font, rect.position + Vector2(6, 22), item.display_name.substr(0, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
		# 右下价值(食物显示打折后的价值)
		var val_disp: int = Freshness.entry_value(entry) if item.is_food else int(item.value)
		var val_text := "%d" % val_disp
		var fs2: int = 12
		var vts: Vector2 = font.get_string_size(val_text, HORIZONTAL_ALIGNMENT_RIGHT, -1, fs2)
		draw_string(font, rect.position + rect.size - Vector2(vts.x + 4, 4), val_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color.WHITE)
