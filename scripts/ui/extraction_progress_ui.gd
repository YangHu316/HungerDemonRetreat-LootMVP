extends CanvasLayer

# 撤离倒计时 UI：屏幕中央 Panel 显示数字 + ProgressBar
var _elapsed: float = 0.0
var _total: float = 5.0
var _active: bool = false

@onready var panel: Panel = $Panel
@onready var time_label: Label = $Panel/TimeLabel
@onready var hint_label: Label = $Panel/HintLabel
@onready var progress_bar: ProgressBar = $Panel/ProgressBar

func _ready() -> void:
	visible = false
	if panel != null:
		panel.visible = false
	if progress_bar != null:
		progress_bar.max_value = _total
		progress_bar.value = 0.0
	call_deferred("_connect_zone")
	# §5 race fix：回合结束强制隐藏
	var bus = get_node_or_null("/root/EventBus")
	if bus != null and not bus.round_ended.is_connected(_on_round_ended_force_hide):
		bus.round_ended.connect(_on_round_ended_force_hide)
	# §3 v6 fix：回合开始 → 重置 UI 状态（panel.visible=false + progress_bar.value=0.0）
	var gs = get_node_or_null("/root/GameSession")
	if gs != null and not gs.round_started.is_connected(_on_round_started):
		gs.round_started.connect(_on_round_started)

func _on_round_started() -> void:
	_active = false
	_elapsed = 0.0
	visible = false
	if panel != null:
		panel.visible = false
	if progress_bar != null:
		progress_bar.value = 0.0

func _on_round_ended_force_hide(_total_v: int, _reason: String) -> void:
	_active = false
	visible = false
	if panel != null:
		panel.visible = false

func _connect_zone() -> void:
	var zones: Array = get_tree().get_nodes_in_group("extraction_zone")
	for z in zones:
		_bind(z)
	if zones.is_empty():
		var ez = get_tree().current_scene.get_node_or_null("World/ExtractionZone")
		if ez != null:
			_bind(ez)

func _bind(z: Node) -> void:
	if z.has_signal("countdown_started") and not z.countdown_started.is_connected(_on_countdown_started):
		z.countdown_started.connect(_on_countdown_started)
	if z.has_signal("countdown_ticked") and not z.countdown_ticked.is_connected(_on_ticked):
		z.countdown_ticked.connect(_on_ticked)
	if z.has_signal("countdown_aborted") and not z.countdown_aborted.is_connected(_on_aborted):
		z.countdown_aborted.connect(_on_aborted)
	if z.has_signal("countdown_succeeded") and not z.countdown_succeeded.is_connected(_on_succeeded):
		z.countdown_succeeded.connect(_on_succeeded)

func _on_countdown_started(total: float) -> void:
	_total = total
	_elapsed = 0.0
	_active = true
	visible = true
	if panel != null:
		panel.visible = true
	if progress_bar != null:
		progress_bar.max_value = _total
		progress_bar.value = 0.0
	_refresh()

func _on_ticked(elapsed: float, total: float) -> void:
	_elapsed = elapsed
	_total = total
	_refresh()

func _on_aborted() -> void:
	_active = false
	visible = false
	if panel != null:
		panel.visible = false
	if progress_bar != null:
		progress_bar.value = 0.0

func _on_succeeded() -> void:
	_active = false
	visible = false
	if panel != null:
		panel.visible = false

func _refresh() -> void:
	if time_label != null:
		var remaining: float = max(0.0, _total - _elapsed)
		time_label.text = "%.1f s" % remaining
	if progress_bar != null:
		progress_bar.max_value = _total
		progress_bar.value = clamp(_elapsed, 0.0, _total)
