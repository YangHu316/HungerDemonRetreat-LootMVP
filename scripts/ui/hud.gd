extends CanvasLayer

@onready var time_label: Label = $TimeLabel
@onready var value_label: Label = $ValueLabel
@onready var hint_label: Label = $HintLabel
@onready var stamina_panel: Control = get_node_or_null("StaminaPanel")
@onready var stamina_fill: ColorRect = get_node_or_null("StaminaPanel/Fill")
@onready var stamina_label: Label = get_node_or_null("StaminaPanel/Label")
var order_label: Label  # 代码生成 — 显示当前订单进度

const COLOR_FULL: Color = Color("#5cd05c")
const COLOR_MID: Color = Color("#f5d042")
const COLOR_LOW: Color = Color("#e74c3c")

var _bus: Node
var _gs: Node
var _inv: Node
var _stamina: Node
var _current_container: Node = null
var _stamina_full_width: float = 0.0
var _flash_tween: Tween = null

func _ready() -> void:
	_bus = get_node("/root/EventBus")
	_gs = get_node("/root/GameSession")
	_inv = get_node("/root/PlayerInventory")
	_stamina = get_node_or_null("/root/Stamina")
	_bus.container_approached.connect(_on_approach)
	_bus.container_left.connect(_on_left)
	if _bus.has_signal("interact_prompt"):
		_bus.interact_prompt.connect(_on_interact_prompt)
	_inv.changed.connect(_update_value)
	hint_label.visible = false
	_update_value()
	if stamina_panel != null and stamina_fill != null:
		_stamina_full_width = stamina_fill.size.x
		if _stamina_full_width <= 0.0:
			_stamina_full_width = 200.0
	if _stamina != null:
		_stamina.changed.connect(_on_stamina_changed)
		_stamina.exhausted.connect(_on_stamina_exhausted)
		_stamina.recovered_enough.connect(_on_stamina_recovered)
		_refresh_stamina(_stamina.value, _stamina.MAX)
	# 订单标签(代码生成,放在 TimeLabel 下方一行)
	_setup_order_label()
	_refresh_order_text()
	var pool = get_node_or_null("/root/OrderPool")
	if pool != null and pool.has_signal("active_changed"):
		pool.active_changed.connect(_refresh_order_text)
	# 注意:不监听 inv.changed —— HUD 不显示实时计数(搜打撤纪律:撤出才算)

func _setup_order_label() -> void:
	order_label = Label.new()
	order_label.add_theme_font_size_override("font_size", 18)
	order_label.modulate = Color(0.95, 0.85, 0.4)
	# 顶部居中:在 TimeLabel 下方
	order_label.anchor_left = 0.5
	order_label.anchor_right = 0.5
	order_label.offset_top = 36
	order_label.offset_left = -240
	order_label.offset_right = 240
	order_label.offset_bottom = 64
	order_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(order_label)

func _refresh_order_text(_arg = null) -> void:
	if order_label == null:
		return
	var pool = get_node_or_null("/root/OrderPool")
	if pool == null or not pool.has_active():
		order_label.text = "(无订单)"
		order_label.modulate = Color(0.6, 0.6, 0.6)
		return
	var active = pool.get_active()
	# 搜打撤:不实时计数,撤出才算
	order_label.text = "🎯 %s    (撤出后结算)" % active.describe()
	order_label.modulate = Color(0.95, 0.85, 0.4)

func _process(_delta: float) -> void:
	var t: int = int(ceil(_gs.time_left))
	var mm: int = t / 60
	var ss: int = t % 60
	time_label.text = "⏱ %02d:%02d" % [mm, ss]

func _on_approach(c: Node) -> void:
	if c.has_method("get_type_name"):
		_current_container = c
		if c.has_method("get_prompt"):
			hint_label.text = c.get_prompt()
		else:
			hint_label.text = "按 F 搜刮 [%s]" % c.get_type_name()
		hint_label.visible = true

func _on_left(c: Node) -> void:
	if _current_container == c:
		_current_container = null
		hint_label.visible = false

# v8 §4.5 全局交互提示
func _on_interact_prompt(text: String) -> void:
	if text == null or text == "":
		# 仅在没有容器场景提示时隐藏
		if _current_container == null:
			hint_label.visible = false
		return
	hint_label.text = text
	hint_label.visible = true

func _update_value() -> void:
	value_label.text = "💰 %d" % _inv.get_total_value()

func _on_stamina_changed(value: float, max_value: float) -> void:
	_refresh_stamina(value, max_value)

func _refresh_stamina(value: float, max_value: float) -> void:
	if stamina_fill == null or max_value <= 0.0:
		return
	var ratio: float = clamp(value / max_value, 0.0, 1.0)
	stamina_fill.size.x = max(0.0, _stamina_full_width * ratio)
	# 颜色分段：is_locked 强制红，否则按 ratio
	var color: Color = COLOR_FULL
	var locked: bool = false
	if _stamina != null and _stamina.has_method("is_locked"):
		locked = _stamina.is_locked()
	if locked or ratio < 0.25:
		color = COLOR_LOW
	elif ratio < 0.5:
		color = COLOR_MID
	stamina_fill.color = color
	if stamina_label != null:
		stamina_label.text = "STA"

func _on_stamina_exhausted() -> void:
	# 红色闪烁
	if stamina_fill == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween().set_loops(3)
	_flash_tween.tween_property(stamina_fill, "modulate", Color(1, 0.4, 0.4, 1), 0.12)
	_flash_tween.tween_property(stamina_fill, "modulate", Color(1, 1, 1, 1), 0.12)

func _on_stamina_recovered() -> void:
	# 亮闪
	if stamina_fill == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(stamina_fill, "modulate", Color(1.4, 1.4, 1.4, 1), 0.15)
	_flash_tween.tween_property(stamina_fill, "modulate", Color(1, 1, 1, 1), 0.2)
