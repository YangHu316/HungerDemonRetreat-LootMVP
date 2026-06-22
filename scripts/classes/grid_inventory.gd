class_name GridInventory
extends Resource

# 网格背包/容器内容数据结构。cells[y][x] = entry dict 或 null
# entry: {"item": ItemData, "x": int, "y": int, "rotated": bool, "examined": bool}
var cols: int = 4
var rows: int = 5
var cells: Array = []
var entries: Array = []  # 所有入格的 entry（去重）

func setup(c: int, r: int) -> void:
	cols = c
	rows = r
	cells = []
	entries = []
	for y in rows:
		var row: Array = []
		for x in cols:
			row.append(null)
		cells.append(row)

func _wh(entry: Dictionary) -> Vector2i:
	var item: ItemData = entry["item"]
	if entry.get("rotated", false):
		return Vector2i(item.grid_h, item.grid_w)
	return Vector2i(item.grid_w, item.grid_h)

func can_place(item: ItemData, x: int, y: int, rotated: bool, ignore_entry = null) -> bool:
	var w: int = item.grid_h if rotated else item.grid_w
	var h: int = item.grid_w if rotated else item.grid_h
	if x < 0 or y < 0 or x + w > cols or y + h > rows:
		return false
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			var c = cells[yy][xx]
			if c != null and c != ignore_entry:
				return false
	return true

func place(entry: Dictionary, x: int, y: int) -> bool:
	var item: ItemData = entry["item"]
	var rotated: bool = entry.get("rotated", false)
	if not can_place(item, x, y, rotated, entry):
		return false
	remove_entry(entry)
	entry["x"] = x
	entry["y"] = y
	var wh: Vector2i = _wh(entry)
	for yy in range(y, y + wh.y):
		for xx in range(x, x + wh.x):
			cells[yy][xx] = entry
	if not entries.has(entry):
		entries.append(entry)
	return true

func remove_entry(entry: Dictionary) -> void:
	for y in rows:
		for x in cols:
			if cells[y][x] == entry:
				cells[y][x] = null
	entries.erase(entry)

func get_entry_at(x: int, y: int):
	if x < 0 or y < 0 or x >= cols or y >= rows:
		return null
	return cells[y][x]

func total_value() -> int:
	var sum: int = 0
	for e in entries:
		if e.get("examined", false):
			sum += (e["item"] as ItemData).value
	return sum
