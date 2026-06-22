extends GutTest

# 防御:双击的第一次 release 不应触发"同位置 item_moved"
# 起因:2026-06-22 用户双击食物快速转移时报"复制",日志显示
#   t=N+0   item_moved: inventory→inventory, x=2,y=0   (双击 click 1 释放)
#   t=N+63  item_moved: inventory→container, x=2,y=0   (双击 click 2 触发)
# 根因:click 1 PRESS 立即 _begin_drag,release 没移动 → _try_drop 落到源 panel 同 cell
#       既产生噪音 item_moved,又让 view free/add 两轮,视觉上像物品被复制
# 修法:_try_drop 检测"源 panel 同 cell 同 rot" → cancel_drag(不 emit)

func test_search_ui_try_drop_guards_same_cell() -> void:
	var src: String = load("res://scripts/ui/search_ui.gd").source_code
	var i: int = src.find("func _try_drop")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	# 必须先检查同位置再调 can_place;同位置走 _cancel_drag
	assert_true(body.contains("_drag.from_panel") and body.contains("_drag.original_x"),
		"search_ui._try_drop 必须检测 from_panel 同位置(双击误触防御)")
	assert_true(body.contains("_cancel_drag"),
		"search_ui._try_drop 同位置应走 _cancel_drag,不 emit item_moved")

func test_home_try_drop_guards_same_cell() -> void:
	var src: String = load("res://scripts/home.gd").source_code
	var i: int = src.find("func _try_drop")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_drag.from_panel") and body.contains("_drag.original_x"),
		"home._try_drop 必须检测 from_panel 同位置(双击误触防御)")
	assert_true(body.contains("_cancel_drag"),
		"home._try_drop 同位置应走 _cancel_drag")
