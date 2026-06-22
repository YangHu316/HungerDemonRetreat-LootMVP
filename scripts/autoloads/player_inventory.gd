extends Node
# PlayerInventory — 5×4 背包数据
const COLS: int = 5
const ROWS: int = 4

signal changed

var grid: GridInventory

func _ready() -> void:
	reset()

func reset() -> void:
	grid = GridInventory.new()
	grid.setup(COLS, ROWS)
	changed.emit()

func try_place_item(item: ItemData, examined: bool = true) -> bool:
	var fit = GridPlacer.find_first_fit(grid, item)
	if fit == null:
		get_node("/root/EventBus").inventory_full.emit()
		return false
	var entry: Dictionary = {
		"item": item, "x": fit[0], "y": fit[1],
		"rotated": fit[2], "examined": examined,
		"freshness_elapsed": 0.0,
	}
	grid.place(entry, fit[0], fit[1])
	changed.emit()
	return true

func place_entry(entry: Dictionary, x: int, y: int) -> bool:
	if grid.place(entry, x, y):
		changed.emit()
		return true
	return false

func remove_entry(entry: Dictionary) -> void:
	grid.remove_entry(entry)
	changed.emit()

func get_total_value() -> int:
	# 外卖侠 §三/§十三:食物按 freshness tier 打折,非食物按原价
	var sum: int = 0
	for e in grid.entries:
		sum += Freshness.entry_value(e)
	return sum

# 把背包某个 entry 转移到仓库。仓库满则返回 false 且不动背包。
func transfer_to_stash(entry: Dictionary) -> bool:
	var stash = get_node_or_null("/root/Stash")
	if stash == null:
		return false
	if not grid.entries.has(entry):
		return false
	var item: ItemData = entry["item"]
	# 外卖侠 §九:仓库默认暂停变质,但已积累的 freshness_elapsed 保留(回到背包继续算)
	var elapsed: float = float(entry.get("freshness_elapsed", 0.0))
	if not stash.try_add(item, elapsed):
		return false  # 仓库满
	grid.remove_entry(entry)
	stash.save()
	changed.emit()
	return true

# 从仓库取出一个 entry 到背包。背包满则返回 false 且不动仓库。
func transfer_from_stash(stash_entry: Dictionary) -> bool:
	var stash = get_node_or_null("/root/Stash")
	if stash == null:
		return false
	if not stash.grid.entries.has(stash_entry):
		return false
	var item: ItemData = stash_entry["item"]
	var fit = GridPlacer.find_first_fit(grid, item)
	if fit == null:
		return false  # 背包满
	var new_entry: Dictionary = {
		"item": item, "x": fit[0], "y": fit[1],
		"rotated": fit[2], "examined": true,
		"freshness_elapsed": float(stash_entry.get("freshness_elapsed", 0.0)),
	}
	if not grid.place(new_entry, fit[0], fit[1]):
		return false
	stash.remove_entry(stash_entry)
	stash.save()
	changed.emit()
	return true
