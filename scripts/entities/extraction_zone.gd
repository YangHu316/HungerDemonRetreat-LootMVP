extends Area3D

# CountDownArea 风格的撤离区:玩家停留 10 秒触发结算(外卖侠 §十二)
const EXTRACT_TIME: float = 10.0

signal countdown_started(total_time: float)
signal countdown_aborted
signal countdown_ticked(elapsed: float, total: float)
signal countdown_succeeded

var _hovering_players: Array = []
var _elapsed: float = 0.0
var _counting_down: bool = false
var _time_began: float = INF

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	set_process(true)
	# §5 race fix：监听回合事件
	var bus = get_node_or_null("/root/EventBus")
	var gs = get_node_or_null("/root/GameSession")
	if bus != null and not bus.round_ended.is_connected(_on_round_ended):
		bus.round_ended.connect(_on_round_ended)
	if gs != null and not gs.round_started.is_connected(_on_round_started):
		gs.round_started.connect(_on_round_started)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if not _hovering_players.has(body):
		_hovering_players.append(body)
	if not _counting_down:
		_begin_countdown()

func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_hovering_players.erase(body)
	if _hovering_players.is_empty() and _counting_down:
		_abort_countdown()

func _begin_countdown() -> void:
	var gs = get_node_or_null("/root/GameSession")
	if gs != null and not gs.round_active:
		return
	_counting_down = true
	_elapsed = 0.0
	_time_began = Time.get_ticks_msec() / 1000.0
	countdown_started.emit(EXTRACT_TIME)

func _abort_countdown() -> void:
	_counting_down = false
	_elapsed = 0.0
	_time_began = INF
	countdown_aborted.emit()

func _process(delta: float) -> void:
	if not _counting_down:
		return
	if get_tree().paused:
		return
	var gs = get_node_or_null("/root/GameSession")
	if gs == null or not gs.round_active:
		# §5 guard：回合不活跃直接停止
		_counting_down = false
		return
	_elapsed += delta
	countdown_ticked.emit(_elapsed, EXTRACT_TIME)
	if _elapsed >= EXTRACT_TIME:
		_counting_down = false
		countdown_succeeded.emit()
		var inv = get_node_or_null("/root/PlayerInventory")
		var bus = get_node_or_null("/root/EventBus")
		if inv != null and bus != null:
			bus.extracted.emit(inv.get_total_value())
		# Phase 2B Tier B6:撤离触发分支
		# 单人:本地标 _extracted + 直接 end_round("extracted")
		# 多人:走 mm.request_extract(host 自己直接调本地;client rpc_id(1, ...))
		var mm = get_node_or_null("/root/MultiplayerManager")
		if mm == null or (mm.has_method("is_single") and mm.is_single()):
			gs.mark_extracted_this_round()
			gs.end_round("extracted")
		else:
			# Q3 fix:host self-RPC 不工作(rpc_id(1) from peer 1 无 call_local)
			# 用 mm.request_extract helper 自动按 is_host 分支
			var my_id: int = mm.get_local_peer_id()
			if mm.has_method("request_extract"):
				mm.request_extract(my_id)

# §5 race fix：回合结束 → 中止倒计时 + 关掉 process + 关掉 area 监听
func _on_round_ended(_total: int, _reason: String) -> void:
	_abort_countdown()
	set_process(false)
	monitoring = false

# §5 race fix：回合开始 → 重新启用 + 清状态 + 主动重扫已重叠物体
func _on_round_started() -> void:
	_hovering_players.clear()
	_counting_down = false
	_time_began = INF
	_elapsed = 0.0
	set_deferred("monitoring", true)
	set_process(true)
	# 等两个物理帧让物理世界稳定 + monitoring 生效
	await get_tree().physics_frame
	await get_tree().physics_frame
	# 主动遍历当前重叠的 body 触发 enter
	for body in get_overlapping_bodies():
		if body != null and body.is_in_group("player"):
			_on_body_entered(body)
