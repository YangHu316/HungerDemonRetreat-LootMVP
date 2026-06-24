extends Node
# GameSession — 单局时钟 + 结算触发
# 外卖侠 §三:15min 硬上限。tick(delta) 是测试入口;_process 调它。
# Phase 2B §联机:start_round/end_round/tick 加 host-authoritative 分支
#   - 单人(mm==null or is_single):走旧逻辑
#   - 多人 host:本地 start_round 后,main.gd 触发 mm.broadcast_round_start 广播
#   - 多人 client:gs.start_round 不在 main.gd 本地调,等 mm._rpc_apply_round_start
#   - timeout 触发只 host 决定(client tick 只减时钟不调 end_round)
const ROUND_TIME: float = 900.0  # 15 分钟硬上限

signal round_started

var time_left: float = ROUND_TIME
var round_active: bool = false
var state: String = "PLAYING"  # PLAYING / UI_OPEN / ROUND_END
# Phase 2B:per-peer 本局是否撤离成功(用于 _rpc_apply_round_end 区分 extracted vs 迷失)
var _extracted_this_round: bool = false
# Phase 2B:round-scoped entry uid 计数器(host 给容器 entry 分配,round 内 unique)
var _next_entry_uid: int = 0

func _ready() -> void:
	set_process(false)

# Phase 2B:host 给每个新生成的 entry 分配 uid。round 内 unique。
func next_entry_uid() -> int:
	var uid: int = _next_entry_uid
	_next_entry_uid += 1
	return uid

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
	_extracted_this_round = false  # Phase 2B:reset 本局撤离标志
	_next_entry_uid = 0             # Phase 2B:重置 uid 计数器
	# Phase 2B:清 inspect log(每局重新搜刮)— LocalInspectLog 在 B3 创建,先 soft-call
	var lil = get_node_or_null("/root/LocalInspectLog")
	if lil != null and lil.has_method("clear"):
		lil.clear()
	set_process(true)
	round_started.emit()

func mark_extracted_this_round() -> void:
	# Phase 2B:extraction_zone 撤离成功时,本地标记。
	# 多人下 _rpc_apply_round_end 根据这个判断 reason
	_extracted_this_round = true

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
		# Phase 2B:timeout 触发只 host(or 单人) 决定。
		# client 的 tick 也减时钟用于 UI 同步,但不直接 end_round —
		# 等 host 广播 _rpc_apply_round_end("timeout") 时统一结束。
		var mm = get_node_or_null("/root/MultiplayerManager")
		if mm == null or not mm.has_method("is_client") or not mm.is_client():
			# 单人 or host
			if mm != null and mm.has_method("is_host") and mm.is_host():
				# 多人 host:走 RPC 广播,call_local 让自己也 end_round
				mm.broadcast_round_end_timeout()
			else:
				# 单人:直接 end_round
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
