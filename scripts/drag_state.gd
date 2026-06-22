class_name DragState
extends RefCounted

# §3 drag-out 模式：拖起物品时立即从源 grid 移除并保存原始信息
# 落点合法 → place 到目标；非法/ESC/松开在 UI 外 → cancel_drag() 放回原位

var entry: Dictionary = {}
var item: ItemData = null
var from_panel: Object = null  # GridPanel
var from_grid_id: String = ""
var original_x: int = 0
var original_y: int = 0
var original_rotated: bool = false
var current_rotated: bool = false
var ghost: Control = null
var highlight: ColorRect = null

static func begin(p_entry: Dictionary, p_from_panel: Object) -> DragState:
	var ds := DragState.new()
	ds.entry = p_entry
	ds.item = p_entry["item"]
	ds.from_panel = p_from_panel
	ds.from_grid_id = String(p_from_panel.grid_id)
	ds.original_x = int(p_entry.get("x", 0))
	ds.original_y = int(p_entry.get("y", 0))
	ds.original_rotated = bool(p_entry.get("rotated", false))
	ds.current_rotated = ds.original_rotated
	# 立即从源 grid 移除（drag-out）
	p_from_panel.remove_entry(p_entry)
	return ds

func cancel_drag() -> void:
	# 还原 entry 朝向并放回原位
	if entry.is_empty() or from_panel == null or not is_instance_valid(from_panel):
		return
	entry["rotated"] = original_rotated
	if not from_panel.add_entry_at(entry, original_x, original_y):
		# 原位被占（理论不会发生：刚移除）→ 兜底用 GridPlacer 找空位
		var fit = GridPlacer.find_first_fit(from_panel.grid, item)
		if fit != null:
			entry["rotated"] = fit[2]
			from_panel.add_entry_at(entry, fit[0], fit[1])

func place_to(target_panel: Object, x: int, y: int) -> bool:
	# 落点合法时调用：写入新朝向并尝试 place
	entry["rotated"] = current_rotated
	if target_panel.add_entry_at(entry, x, y):
		return true
	# 失败 → 取消放回原位
	cancel_drag()
	return false

func cleanup_visuals() -> void:
	if ghost != null and is_instance_valid(ghost):
		ghost.queue_free()
	if highlight != null and is_instance_valid(highlight):
		highlight.queue_free()
	ghost = null
	highlight = null
