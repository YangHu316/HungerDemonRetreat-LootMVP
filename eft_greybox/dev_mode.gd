extends Node
## 全局「开发者模式」开关（autoload 名 = Dev）。
## 按 F1 切换；**开启后**，各小游戏场景里的测试用快捷键（R 重置 / 1·2·3 切换冰柜大小 等）才生效。
## 正式接入大地图时默认关闭——玩家碰不到这些开发快捷键，小游戏只响应正常玩法操作。

signal toggled(on: bool)

@export var toggle_key := KEY_F1
var enabled := false

var _label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 128                       # 永远置顶
	add_child(layer)
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC"])
	_label = Label.new()
	_label.add_theme_font_override("font", sf)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	_label.text = "● 开发者模式 ON（F1 关）"
	_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_label.offset_left = -270.0
	_label.offset_right = -12.0
	_label.offset_top = 6.0
	_label.offset_bottom = 30.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.visible = false
	layer.add_child(_label)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == toggle_key:
		set_enabled(not enabled)


func set_enabled(on: bool) -> void:
	enabled = on
	if _label != null:
		_label.visible = on
	toggled.emit(on)
