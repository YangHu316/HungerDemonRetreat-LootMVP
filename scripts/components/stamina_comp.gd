class_name StaminaComp
extends Node
# 玩家体力组件 — 挂在 Player 节点下,per-player 实例
# 为联机做准备:autoload Stamina 现在只是这个组件的"本地玩家代理"
# 数据全在这里。两个 StaminaComp 实例数据完全独立。

const MAX: float = 100.0
const DRAIN: float = 25.0
const RECOVER: float = 18.0
const DELAY: float = 0.7
const MIN_TO_START_RUN: float = 8.0

const MAX_VALUE: float = MAX

signal changed(value: float, max_value: float)
signal run_started
signal run_stopped
signal exhausted
signal recovered_enough

var value: float = MAX
var _is_running: bool = false
var _is_locked: bool = false
var _recover_timer: float = 0.0

func _ready() -> void:
	set_process(true)

func try_start_run() -> bool:
	if _is_locked:
		return false
	if value <= 0.0:
		return false
	if _is_running:
		return true
	_is_running = true
	_recover_timer = 0.0
	run_started.emit()
	return true

func stop_run() -> void:
	if not _is_running:
		return
	_is_running = false
	_recover_timer = 0.0
	run_stopped.emit()

func reset() -> void:
	value = MAX
	_is_running = false
	_is_locked = false
	_recover_timer = 0.0
	changed.emit(value, MAX)

func is_running() -> bool:
	return _is_running

func is_locked() -> bool:
	return _is_locked

func _drain(delta: float) -> void:
	value = max(0.0, value - DRAIN * delta)
	if value <= 0.0:
		value = 0.0
		_is_running = false
		_is_locked = true
		exhausted.emit()
		run_stopped.emit()
		_recover_timer = 0.0

func _recover(delta: float) -> void:
	_recover_timer += delta
	if _recover_timer < DELAY:
		return
	var before: float = value
	value = min(MAX, value + RECOVER * delta)
	if _is_locked and before < MIN_TO_START_RUN and value >= MIN_TO_START_RUN:
		_is_locked = false
		recovered_enough.emit()

func _process(delta: float) -> void:
	var prev_value: float = value
	if _is_running:
		_drain(delta)
	else:
		_recover(delta)
	if not is_equal_approx(prev_value, value):
		changed.emit(value, MAX)
