extends GutTest

# 防御:grid_panel.gd 反复拖动时不能累积"幽灵 view"
# 起因:2026-06-22 用户在 search_ui 反复 container ↔ inventory 拖同一物品,
# 出现"被吞"现象;根因:同 grid 内 place 时旧 view 不 free,屏幕累积孤儿 view
# 注意:不能在 remove_entry 清 _last_click_entry —— 否则破坏双击拾取(已验证 regression)

func test_add_entry_at_frees_old_view() -> void:
	var src: String = load("res://scripts/ui/grid_panel.gd").source_code
	var i: int = src.find("func add_entry_at")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("queue_free"),
		"add_entry_at 必须先 free 旧 view(同 grid 内 place 否则视觉孤儿)")

func test_remove_entry_must_not_clear_last_click() -> void:
	# regression 防御:之前在 remove_entry 清 _last_click_entry 破坏了双击
	var src: String = load("res://scripts/ui/grid_panel.gd").source_code
	var i: int = src.find("func remove_entry")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_false(body.contains("_last_click_entry = {}"),
		"remove_entry 不能清 _last_click_entry,否则双击拾取坏")
