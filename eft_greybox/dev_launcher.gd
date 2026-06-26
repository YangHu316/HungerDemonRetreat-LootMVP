extends Node
## 开发沙盒入口（仅供 F5 调试用，本身不接入大地图）。
## 把某个小游戏「组件场景」实例化并设为 standalone=true（自带相机/环境/自动开始），方便单独试玩。
##   · F2 = 切换到下一个小游戏
##   · F1 = 开发者模式开关（开启后小游戏内的测试快捷键 R / 1·2·3 才生效）
## 正式接入大地图时：直接把 ice_cabinet.tscn / electric_crossing.tscn / gluttony_portal.tscn
## 作为子场景实例化（standalone 留默认 false），由交互触发 begin()、监听 finished 信号即可。

const GAMES := [
	"res://eft_greybox/electric_crossing.tscn",
	"res://eft_greybox/ice_cabinet.tscn",
	"res://eft_greybox/gluttony_portal.tscn",
]
var _idx := 0
var _current: Node


func _ready() -> void:
	_load(_idx)


func _load(i: int) -> void:
	_idx = (i % GAMES.size() + GAMES.size()) % GAMES.size()
	if _current != null and is_instance_valid(_current):
		_current.queue_free()
	var scn := (load(String(GAMES[_idx])) as PackedScene).instantiate()
	scn.set("standalone", true)               # 沙盒模式：自带相机/环境 + 自动开始
	if scn.has_signal("finished"):
		scn.connect("finished", _on_finished)
	add_child(scn)
	_current = scn


func _on_finished(result: Dictionary) -> void:
	print("[沙盒] 小游戏结束 → ", result, "（大地图里此处把控制权交还主循环）")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		_load(_idx + 1)
