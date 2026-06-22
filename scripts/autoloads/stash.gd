extends Node
# Stash — 局间持久仓库(外卖侠 §九)
# 网格化:8×5 = 40 格(文档说 10×50,MVP 先小一点保证屏幕装得下)
# 物品按 grid_w × grid_h 占格,跟背包一致;不旋转(GridPlacer 自动 fallback)

const SAVE_PATH := "user://stash.json"
const COLS: int = 8
const ROWS: int = 5

signal changed

var grid: GridInventory

func _ready() -> void:
	_init_grid()
	load_from_disk()

func _init_grid() -> void:
	grid = GridInventory.new()
	grid.setup(COLS, ROWS)

# 返回是否成功(仓库满则失败)。freshness_elapsed 用于跨背包/仓库保留食物已积累的变质时间。
func try_add(item: ItemData, freshness_elapsed: float = 0.0) -> bool:
	if item == null:
		return false
	var fit = GridPlacer.find_first_fit(grid, item)
	if fit == null:
		return false
	var entry: Dictionary = {
		"item": item, "x": fit[0], "y": fit[1],
		"rotated": fit[2], "examined": true,
		"freshness_elapsed": freshness_elapsed,
	}
	if grid.place(entry, fit[0], fit[1]):
		changed.emit()
		return true
	return false

func remove_entry(entry: Dictionary) -> bool:
	if not grid.entries.has(entry):
		return false
	grid.remove_entry(entry)
	changed.emit()
	return true

func get_total_value() -> int:
	var sum: int = 0
	for e in grid.entries:
		sum += int((e["item"] as ItemData).value)
	return sum

func get_all_items() -> Array:
	# 兼容旧 API:返回 ItemData 列表(供测试/外部 inspect)
	var out: Array = []
	for e in grid.entries:
		out.append(e["item"])
	return out

func clear() -> void:
	_init_grid()
	changed.emit()

# ---- JSON 持久化 ----
func save() -> void:
	var data: Array = []
	for e in grid.entries:
		var item: ItemData = e["item"]
		data.append({
			"path": item.resource_path,
			"x": int(e["x"]),
			"y": int(e["y"]),
			"rotated": bool(e.get("rotated", false)),
			"freshness_elapsed": float(e.get("freshness_elapsed", 0.0)),
		})
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"items": data}))
		f.close()

func load_from_disk() -> void:
	_init_grid()
	if not FileAccess.file_exists(SAVE_PATH):
		changed.emit()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var arr: Array = (parsed as Dictionary).get("items", [])
	for d in arr:
		var dd: Dictionary = d
		var path: String = String(dd.get("path", ""))
		var res: Resource = load(path)
		if res is ItemData:
			var entry: Dictionary = {
				"item": res,
				"x": int(dd.get("x", 0)),
				"y": int(dd.get("y", 0)),
				"rotated": bool(dd.get("rotated", false)),
				"examined": true,
				"freshness_elapsed": float(dd.get("freshness_elapsed", 0.0)),
			}
			grid.place(entry, entry["x"], entry["y"])
	changed.emit()
