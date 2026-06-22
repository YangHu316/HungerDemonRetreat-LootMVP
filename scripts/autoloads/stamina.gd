extends Node
# Stamina — autoload 本地玩家代理(零数据)
# 历史:这里曾持有体力数据。为了联机(per-player 体力),数据搬到了
# scripts/components/stamina_comp.gd,挂在每个 Player 节点下。
# 现在这个 autoload 只是 forward 到"当前本地玩家"的 StaminaComp。
#
# 测试/早期场景兜底:_fallback_comp 在无 player 注册时充当数据源。

# 常量 forward(给老脚本兼容)
const MAX: float = StaminaComp.MAX
const DRAIN: float = StaminaComp.DRAIN
const RECOVER: float = StaminaComp.RECOVER
const DELAY: float = StaminaComp.DELAY
const MIN_TO_START_RUN: float = StaminaComp.MIN_TO_START_RUN
const MAX_VALUE: float = MAX

signal changed(value: float, max_value: float)
signal run_started
signal run_stopped
signal exhausted
signal recovered_enough

var local_player: Node = null
var _fallback_comp: StaminaComp = null

func _ready() -> void:
	_fallback_comp = StaminaComp.new()
	add_child(_fallback_comp)
	_connect_comp(_fallback_comp)

func _connect_comp(c: StaminaComp) -> void:
	if c == null:
		return
	if not c.changed.is_connected(_on_changed):
		c.changed.connect(_on_changed)
	if not c.run_started.is_connected(_on_run_started):
		c.run_started.connect(_on_run_started)
	if not c.run_stopped.is_connected(_on_run_stopped):
		c.run_stopped.connect(_on_run_stopped)
	if not c.exhausted.is_connected(_on_exhausted):
		c.exhausted.connect(_on_exhausted)
	if not c.recovered_enough.is_connected(_on_recovered_enough):
		c.recovered_enough.connect(_on_recovered_enough)

func _disconnect_comp(c: StaminaComp) -> void:
	if c == null:
		return
	if c.changed.is_connected(_on_changed):
		c.changed.disconnect(_on_changed)
	if c.run_started.is_connected(_on_run_started):
		c.run_started.disconnect(_on_run_started)
	if c.run_stopped.is_connected(_on_run_stopped):
		c.run_stopped.disconnect(_on_run_stopped)
	if c.exhausted.is_connected(_on_exhausted):
		c.exhausted.disconnect(_on_exhausted)
	if c.recovered_enough.is_connected(_on_recovered_enough):
		c.recovered_enough.disconnect(_on_recovered_enough)

func _on_changed(v: float, mx: float) -> void: changed.emit(v, mx)
func _on_run_started() -> void: run_started.emit()
func _on_run_stopped() -> void: run_stopped.emit()
func _on_exhausted() -> void: exhausted.emit()
func _on_recovered_enough() -> void: recovered_enough.emit()

func register_local_player(p: Node) -> void:
	if p == null:
		return
	if local_player != null and is_instance_valid(local_player):
		_disconnect_comp(local_player.get("stamina_comp"))
	local_player = p
	_connect_comp(p.get("stamina_comp"))

func unregister_local_player(p: Node) -> void:
	if local_player != p:
		return
	if local_player != null and is_instance_valid(local_player):
		_disconnect_comp(local_player.get("stamina_comp"))
	local_player = null

func _get_comp() -> StaminaComp:
	if local_player != null and is_instance_valid(local_player):
		var c = local_player.get("stamina_comp")
		if c != null:
			return c
	return _fallback_comp

# property forward
var value: float:
	get:
		var c = _get_comp()
		return c.value if c != null else 0.0
	set(v):
		var c = _get_comp()
		if c != null:
			c.value = v

# 方法 forward
func try_start_run() -> bool:
	return _get_comp().try_start_run()

func stop_run() -> void:
	_get_comp().stop_run()

func reset() -> void:
	_get_comp().reset()

func is_running() -> bool:
	return _get_comp().is_running()

func is_locked() -> bool:
	return _get_comp().is_locked()
