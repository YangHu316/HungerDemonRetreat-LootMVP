extends CanvasLayer

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/TitleLabel
@onready var value_label: Label = $Panel/ValueLabel
@onready var reason_label: Label = $Panel/ReasonLabel
@onready var restart_button: Button = $Panel/RestartButton
var order_label: Label  # 代码生成,显示订单完成度

func _ready() -> void:
	visible = false
	get_node("/root/EventBus").round_ended.connect(_on_round_ended)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_always_recursive(self)
	if restart_button != null:
		restart_button.pressed.connect(_on_restart)
	# 订单完成度 Label,放在 ReasonLabel 下方一行
	order_label = Label.new()
	order_label.add_theme_font_size_override("font_size", 18)
	order_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order_label.anchor_right = 1.0
	order_label.offset_top = 180.0
	order_label.offset_bottom = 210.0
	panel.add_child(order_label)

func _set_always_recursive(n: Node) -> void:
	n.process_mode = Node.PROCESS_MODE_ALWAYS
	for c in n.get_children():
		_set_always_recursive(c)

func _on_round_ended(total: int, reason: String) -> void:
	visible = true
	if reason == "extracted":
		title_label.text = "✅ 撤离成功"
		title_label.modulate = Color(1, 0.85, 0.25, 1)
		reason_label.text = "安全退出"
	elif reason == "timeout":
		title_label.text = "⏱ 时间到 — 未撤离"
		title_label.modulate = Color(0.7, 0.2, 0.2, 1)
		reason_label.text = "未能及时撤离至撤离区"
	else:
		title_label.text = "回合结束"
		title_label.modulate = Color(1, 1, 1, 1)
		reason_label.text = String(reason)
	value_label.text = "💰 总价值: %d" % total
	# 订单完成度
	var pool = get_node_or_null("/root/OrderPool")
	if pool != null and pool.has_active():
		var active = pool.get_active()
		if reason == "timeout":
			# 迷失 = 完成度 0
			order_label.text = "🎯 %s   0/%d (迷失)" % [active.describe(), active.count_required]
			order_label.modulate = Color(0.7, 0.2, 0.2)
		else:
			var inv = get_node("/root/PlayerInventory")
			var r: Dictionary = pool.completion_for_inventory(inv)
			var reward: int = int(round(active.reward_base * float(r["ratio"])))
			order_label.text = "🎯 %s   %d/%d  奖励 %d" % [
				active.describe(), int(r["capped"]), int(r["required"]), reward
			]
			if float(r["ratio"]) >= 1.0:
				order_label.modulate = Color(0.5, 1.0, 0.5)
			else:
				order_label.modulate = Color(0.95, 0.85, 0.4)
	else:
		order_label.text = ""
	get_tree().paused = true

func _on_restart() -> void:
	# 返回主页前,清掉本局的 active 订单(下一局重新接)
	var pool = get_node_or_null("/root/OrderPool")
	if pool != null:
		pool.clear_active()
	visible = false
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/home.tscn")

