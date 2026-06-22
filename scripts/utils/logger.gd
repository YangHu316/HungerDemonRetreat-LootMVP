extends Node
# Logger — 结构化事件日志
# 默认订阅 EventBus 的关键信号,转 JSONL 写到 user://logs/。
# 边角处可调 Logger.event(name, payload) 直埋(凭 Logger 单例,不需要 EventBus 信号)。
#
# 设计契约(见 CLAUDE.md §测试与日志纪律):
# - 日志验"玩家感知/手感/链路顺序",不验数值规则(那是 GUT 的事)
# - 每条日志一行 JSON: {"t": ms, "name": str, "payload": {...}}
# - 测试时 Logger.silent = true 关 print,但仍写文件
# - 跑测试时不应启动游戏,所以 Logger 也不会被加载;只有 main scene 跑才生效

const LOG_DIR := "user://logs"

@export var enabled: bool = true
@export var silent: bool = false       # 仅 stdout 静音,文件照写
@export var write_to_file: bool = true

var _file: FileAccess = null
var _t0_ms: int = 0
var _bus: Node = null

func _ready() -> void:
	_t0_ms = Time.get_ticks_msec()
	if not enabled:
		return
	if write_to_file:
		_open_file()
	_bus = get_node_or_null("/root/EventBus")
	if _bus != null:
		_subscribe_bus()
	event("logger_started", {"version": 1})

func _open_file() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))
	# user:// 是用户写入目录,DirAccess 直接用相对 path
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var ts := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "%s/run_%s.jsonl" % [LOG_DIR, ts]
	_file = FileAccess.open(path, FileAccess.WRITE)

func _subscribe_bus() -> void:
	# 容器交互链路
	_bus.container_approached.connect(func(c): event("container_approached", _container_payload(c)))
	_bus.container_left.connect(func(c): event("container_left", _container_payload(c)))
	_bus.container_opened.connect(func(c): event("container_opened", _container_payload(c)))
	_bus.container_closed.connect(func(c): event("container_closed", _closed_payload(c)))
	# 物品/价值
	_bus.item_examined.connect(func(item): event("item_examined", _item_payload(item)))
	_bus.item_moved.connect(func(item, from_id, to_id, x, y, rotated):
		event("item_moved", {
			"id": _item_id(item),
			"from": from_id, "to": to_id,
			"x": x, "y": y, "rotated": rotated,
		}))
	_bus.inventory_full.connect(func(): event("inventory_full", {}))
	# 撤离 / 局结束
	_bus.extracted.connect(func(total): event("extracted", {"total_value": int(total)}))
	_bus.round_ended.connect(func(total, reason): event("round_ended", {"total_value": int(total), "reason": String(reason)}))
	# 门
	_bus.door_toggled.connect(func(door, is_open): event("door_toggled", {
		"id": _node_id(door), "is_open": bool(is_open),
	}))

func event(name: String, payload: Dictionary = {}) -> void:
	if not enabled:
		return
	var dt := Time.get_ticks_msec() - _t0_ms
	var line := JSON.stringify({"t": dt, "name": name, "payload": payload})
	if not silent:
		print("[Logger] ", line)
	if _file != null:
		_file.store_line(line)
		_file.flush()

# ---- payload helpers ----
func _container_payload(c: Node) -> Dictionary:
	if c == null:
		return {}
	var d: Dictionary = {"id": _node_id(c)}
	if c.has_method("get_type_name_key"):
		d["type"] = c.get_type_name_key()
	return d

func _closed_payload(c: Node) -> Dictionary:
	var d := _container_payload(c)
	if c != null and "is_emptied" in c:
		d["is_emptied"] = bool(c.is_emptied)
	return d

func _item_payload(item) -> Dictionary:
	return {"id": _item_id(item)}

func _item_id(item) -> String:
	if item == null:
		return ""
	if item is ItemData:
		return (item as ItemData).id
	if item is Dictionary and item.has("item"):
		return _item_id(item["item"])
	return ""

func _node_id(n: Node) -> String:
	if n == null:
		return ""
	return n.name

func _exit_tree() -> void:
	if _file != null:
		_file.close()
		_file = null
