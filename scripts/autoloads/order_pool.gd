extends Node
# OrderPool — 订单池 + 接单状态(外卖侠 §十,MVP 单订单)
# 候选订单跨主页刷新保留,接单后绑定到本局,撤离/迷失后 active 清空

signal candidate_changed     # 候选订单变了(刷新)
signal active_changed        # 玩家接/卸订单

var _candidate: OrderData = null     # 主页面上看到的候选
var _active: OrderData = null        # 当前局已接的订单

func _ready() -> void:
	# 启动就生成一个候选,玩家进主页就能看到
	if _candidate == null:
		_candidate = OrderData.random_basic()
		candidate_changed.emit()

func get_candidate() -> OrderData:
	return _candidate

func get_active() -> OrderData:
	return _active

func has_active() -> bool:
	return _active != null

func refresh_candidate() -> void:
	_candidate = OrderData.random_basic()
	candidate_changed.emit()

func accept_candidate() -> bool:
	if _candidate == null:
		return false
	if _active != null:
		return false  # MVP:已有 active,不允许再接
	_active = _candidate
	_candidate = OrderData.random_basic()  # 自动出下一个候选
	active_changed.emit()
	candidate_changed.emit()
	return true

func clear_active() -> void:
	if _active != null:
		_active = null
		active_changed.emit()

# 用 PlayerInventory 当前内容算完成度
func completion_for_inventory(inv: Node) -> Dictionary:
	if _active == null or inv == null or inv.grid == null:
		return {"matched": 0, "capped": 0, "required": 0, "ratio": 0.0}
	var items: Array = []
	for e in inv.grid.entries:
		items.append(e["item"])
	return _active.completion_for(items)
