extends Node
# LocalInspectLog — per-peer inspect 状态缓存(Phase 2B Tier B3)
#
# 设计意图:
#   - 容器 entries 是 host 权威全局同步,但 inspect 状态(放大镜转圈)必须 per-player 独立
#   - 不能把 inspecting/inspected/examined 存在 entry 字典里 —— 否则容器内容同步时会被冲掉
#   - 每个 peer 本地维护:Dictionary[container_path: String] → Dictionary[entry_uid: int → bool]
#   - GameSession.start_round 时清空(每局重新搜刮)
#   - search_ui 完成 inspect 时调 mark_inspected,生成 UI 时调 is_inspected 决定是否揭示
#
# 缓存策略(plan §B3):LocalInspectLog 是 source of truth,
# entry["inspected"] 是 cache(search_ui.open_for 时 hydrate)。
# grid_panel / grid_item 现有读 entry 不改,只是 entry 的 inspected 值由 hydrate 写。

var _log: Dictionary = {}  # path → {uid: true}

func mark_inspected(container_path: String, entry_uid: int) -> void:
	if entry_uid < 0:
		return
	if not _log.has(container_path):
		_log[container_path] = {}
	_log[container_path][entry_uid] = true

func is_inspected(container_path: String, entry_uid: int) -> bool:
	if entry_uid < 0:
		return false
	if not _log.has(container_path):
		return false
	return bool(_log[container_path].get(entry_uid, false))

func clear() -> void:
	_log.clear()

# 给定 container,遍历 contents.entries,全部 uid 都在 log 中 → true
# 用于 search_ui 关 UI 时计算 is_searched(per-peer)
func is_container_fully_inspected(container: Node) -> bool:
	if container == null:
		return false
	if container.contents == null:
		return false
	if container.contents.entries.is_empty():
		# 空容器不算"已 inspect 完整流程"
		return false
	var path: String = String(container.get_path())
	for e in container.contents.entries:
		var uid: int = int(e.get("uid", -1))
		if not is_inspected(path, uid):
			return false
	return true

# 用于 search_ui.open_for 时 hydrate entry["inspected"] cache
func hydrate_container_entries(container: Node) -> void:
	if container == null or container.contents == null:
		return
	var path: String = String(container.get_path())
	for e in container.contents.entries:
		var uid: int = int(e.get("uid", -1))
		var done: bool = is_inspected(path, uid)
		e["inspected"] = done
		e["examined"] = done   # 兼容旧字段(grid_item.gd:40 也读 examined)
		# 注意:不动 inspecting(运行时 flag,search_ui 自己控制)
