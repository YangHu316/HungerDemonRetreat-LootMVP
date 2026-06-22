extends Node
# GameSession — 单局时钟 + 结算触发
# 外卖侠 §三:15min 硬上限。tick(delta) 是测试入口;_process 调它。
const ROUND_TIME: float = 900.0  # 15 分钟硬上限

signal round_started

var time_left: float = ROUND_TIME
var round_active: bool = false
var state: String = "PLAYING"  # PLAYING / UI_OPEN / ROUND_END

func _ready() -> void:
	set_process(false)

func start_round() -> void:
	# 搜打撤纪律:背包跨局保留(上一局撤出来的物品继续在背包,
	# 玩家在 home 自行决定存仓库还是带进下一局再冒险)。
	# 只 timeout(迷失) 时才清空,见 end_round。
	var stamina = get_node_or_null("/root/Stamina")
	if stamina != null:
		stamina.reset()
	time_left = ROUND_TIME
	round_active = true
	state = "PLAYING"
	set_process(true)
	round_started.emit()

func end_round(reason: String) -> void:
	if not round_active:
		return
	round_active = false
	state = "ROUND_END"
	set_process(false)
	var bus = get_node("/root/EventBus")
	var inv = get_node("/root/PlayerInventory")
	# §4 timeout 时清空背包（未及时撤离 = 损失全部物品）
	var total: int = 0
	if reason == "timeout":
		total = 0
		if inv != null and inv.grid != null:
			inv.grid.cells.clear()
			inv.grid.entries.clear()
			inv.reset()
	else:
		total = inv.get_total_value()
	bus.round_ended.emit(total, reason)

func _process(delta: float) -> void:
	if not round_active:
		return
	tick(delta)

# 公共 tick 入口:测试可直接调用,_process 也走这里
func tick(delta: float) -> void:
	if not round_active:
		return
	time_left -= delta
	var bus = get_node_or_null("/root/EventBus")
	if bus != null:
		bus.round_tick.emit(time_left, ROUND_TIME)
	# 外卖侠 §三 后半:推进背包食物变质(仓库不动,锁档)
	_advance_inventory_freshness(delta)
	if time_left <= 0.0:
		time_left = 0.0
		end_round("timeout")

func _advance_inventory_freshness(delta: float) -> void:
	var inv = get_node_or_null("/root/PlayerInventory")
	if inv == null or inv.grid == null:
		return
	for e in inv.grid.entries:
		var item = e.get("item", null)
		if item != null and item.is_food:
			e["freshness_elapsed"] = float(e.get("freshness_elapsed", 0.0)) + delta

func set_state(s: String) -> void:
	# 合法转换表
	match state:
		"PLAYING":
			if s in ["UI_OPEN", "ROUND_END"]:
				state = s
		"UI_OPEN":
			if s == "PLAYING":
				state = s
		"ROUND_END":
			if s == "PLAYING":
				state = s
