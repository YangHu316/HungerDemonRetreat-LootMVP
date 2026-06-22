extends PopupPanel


# Chinese font for CJK display support
var _chinese_font: Font

var current_container = null
var current_player = null

@onready var bus = get_node("/root/EventBus")
@onready var title_label: Label = $Margin/VBox/TitleLabel
@onready var item_list: VBoxContainer = $Margin/VBox/ItemList
@onready var footer_label: Label = $Margin/VBox/FooterLabel

const RARITY_COLORS = {
	"common": Color(0.604, 0.604, 0.604, 1),
	"uncommon": Color(0.361, 0.816, 0.361, 1),
	"rare": Color(0.357, 0.784, 1.0, 1),
	"epic": Color(0.761, 0.400, 1.0, 1),
}

func _ready() -> void:
	# Load Chinese font for dynamic UI
	if ResourceLoader.exists("res://assets/fonts/NotoSansSC-Regular.ttf"):
		_chinese_font = load("res://assets/fonts/NotoSansSC-Regular.ttf")

	bus.container_opened.connect(_on_container_opened)
	about_to_popup.connect(_on_about_to_popup)
	popup_hide.connect(_on_popup_hide)

func _on_container_opened(c) -> void:
	current_container = c
	var tree_root = get_tree().root.get_node("Main")
	if tree_root != null and tree_root.has_node("Player"):
		current_player = tree_root.get_node("Player")
	_refresh()
	var viewport_size = get_viewport().get_visible_rect().size
	popup_centered()

func _on_about_to_popup() -> void:
	pass

func _on_popup_hide() -> void:
	if current_container != null:
		bus.container_closed.emit(current_container)
	current_container = null
	current_player = null

func _refresh() -> void:
	for child in item_list.get_children():
		child.queue_free()
	if current_container == null:
		hide()
		return
	if current_container.is_empty():
		hide()
		return
	title_label.text = "搜刮 — %s" % _size_label(current_container.container_size)
	var idx: int = 1
	for item in current_container.contents:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var num := Label.new()
		num.text = "[%d]" % idx
		num.custom_minimum_size = Vector2(28, 0)
		num.add_theme_font_size_override("font_size", 18)
		num.modulate = Color(0.7, 0.7, 0.7, 1)
		if _chinese_font:
			num.add_theme_font_override("font", _chinese_font)
		row.add_child(num)
		var ring := ColorRect.new()
		ring.custom_minimum_size = Vector2(32, 32)
		ring.color = RARITY_COLORS.get(item.rarity, Color.GRAY)
		var inner := ColorRect.new()
		inner.custom_minimum_size = Vector2(24, 24)
		inner.color = item.color
		inner.anchor_left = 0.5
		inner.anchor_top = 0.5
		inner.anchor_right = 0.5
		inner.anchor_bottom = 0.5
		inner.offset_left = -12
		inner.offset_top = -12
		inner.offset_right = 12
		inner.offset_bottom = 12
		ring.add_child(inner)
		row.add_child(ring)
		var name_label := Label.new()
		name_label.text = item.display_name
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _chinese_font:
			name_label.add_theme_font_override("font", _chinese_font)
		row.add_child(name_label)
		var value_label := Label.new()
		value_label.text = "价值 %d" % item.value
		value_label.add_theme_font_size_override("font_size", 16)
		value_label.modulate = Color(1.0, 0.816, 0.251, 1)
		if _chinese_font:
			value_label.add_theme_font_override("font", _chinese_font)
		row.add_child(value_label)
		var weight_label := Label.new()
		weight_label.text = "重 %.1f" % item.weight
		weight_label.add_theme_font_size_override("font_size", 16)
		weight_label.modulate = Color(0.7, 0.7, 0.7, 1)
		if _chinese_font:
			weight_label.add_theme_font_override("font", _chinese_font)
		row.add_child(weight_label)
		item_list.add_child(row)
		idx += 1
	_update_footer()

func _update_footer() -> void:
	if current_player == null or current_player.inventory == null:
		footer_label.text = ""
		return
	var inv = current_player.inventory
	footer_label.text = "背包: %.1f/%.1f 重量 | %d 价值   [F] 全拾  [E/ESC] 关闭" % [inv.get_total_weight(), inv.max_weight, inv.get_total_value()]

func _size_label(s: String) -> String:
	match s:
		"small": return "小箱子"
		"medium": return "中箱子"
		"large": return "大箱子"
		_: return "容器"

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("interact"):
		hide()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("loot_all"):
		_loot_all()
		get_viewport().set_input_as_handled()
		return
	for i in range(1, 10):
		if event.is_action_pressed("slot_%d" % i):
			_pick_index(i - 1)
			get_viewport().set_input_as_handled()
			return

func _pick_index(idx: int) -> void:
	if current_container == null or current_player == null:
		return
	if idx < 0 or idx >= current_container.contents.size():
		return
	var item = current_container.contents[idx]
	if current_player.try_pick(item):
		current_container.remove_item(item)
		bus.item_picked.emit(current_player, item)
	_refresh()
	if current_container == null or current_container.is_empty():
		hide()

func _loot_all() -> void:
	if current_container == null or current_player == null:
		return
	var to_remove: Array = []
	for item in current_container.contents:
		if current_player.try_pick(item):
			to_remove.append(item)
			bus.item_picked.emit(current_player, item)
		else:
			break
	for item in to_remove:
		current_container.remove_item(item)
	_refresh()
	if current_container == null or current_container.is_empty():
		hide()
