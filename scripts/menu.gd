extends Control
# 主菜单 — 玩家进入游戏第一个看到的页面
# 单人模式 → home.tscn(现有流程)
# 联机模式 → 占位(disabled,等 Phase 2 上 MultiplayerAPI + ENet)

const HOME_SCENE := "res://scenes/home.tscn"

var _single_btn: Button
var _multi_btn: Button

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	# 全屏深色背景
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 居中垂直布局
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 28)
	vbox.custom_minimum_size = Vector2(420, 360)
	# 居中:position 用锚点 + offset 调整
	vbox.offset_left = -210
	vbox.offset_right = 210
	vbox.offset_top = -180
	vbox.offset_bottom = 180
	add_child(vbox)

	# 标题
	var title := Label.new()
	title.text = "饿魔退散!外卖侠"
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# 副标题
	var subtitle := Label.new()
	subtitle.text = "3D 斜俯视 · 网格搜刮 · 搜打撤"
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	# 间隔
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	# 单人模式按钮
	_single_btn = Button.new()
	_single_btn.text = "单人模式"
	_single_btn.custom_minimum_size = Vector2(0, 60)
	_single_btn.add_theme_font_size_override("font_size", 24)
	_single_btn.pressed.connect(_on_single)
	vbox.add_child(_single_btn)

	# 联机模式按钮(disabled,等 Phase 2)
	_multi_btn = Button.new()
	_multi_btn.text = "联机模式 (开发中)"
	_multi_btn.custom_minimum_size = Vector2(0, 60)
	_multi_btn.add_theme_font_size_override("font_size", 24)
	_multi_btn.disabled = true
	_multi_btn.tooltip_text = "2-3 人主机权威联机,Phase 2 开发中。Player 组件化地基已就绪。"
	vbox.add_child(_multi_btn)

	# 版本号 / 状态
	var version := Label.new()
	version.text = "v0.x MVP — 单人可玩  ·  联机栈待接入"
	version.add_theme_font_size_override("font_size", 12)
	version.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(version)

func _on_single() -> void:
	get_tree().change_scene_to_file(HOME_SCENE)
