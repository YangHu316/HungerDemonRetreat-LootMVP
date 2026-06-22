extends GutTest

# 防御:Godot 4 Dictionary key 是 content hash —— mutable Dictionary 不能直接作 key
# 起因:2026-06-22 用户反复 inventory↔container 拖食物,后期视觉上变出 4 个面包
# 根因:grid_panel.item_views[entry] 用 entry Dictionary 作 key
#       拖拽中 entry["x"]/["y"]/["rotated"] 被改 → hash 变 → has/erase 失效
#       → 旧 view 不被 free → 屏幕累积幽灵 view → 看起来"复制"
# 修法:item_views 改用 entry 的稳定 int uid 作 key(_entry_uid 分配)

func test_dict_with_mutable_dict_key_loses_track() -> void:
	# 验证 Godot 4 的陷阱行为 —— 内容变后查不到
	var entry: Dictionary = {"x": 0, "y": 0}
	var tracker: Dictionary = {}
	tracker[entry] = "view"
	entry["x"] = 2
	assert_false(tracker.has(entry),
		"Godot 4 陷阱:Dictionary 作 dict key 时 hash 基于 content,key mutate 后 has 返回 false")

func test_dict_with_int_key_survives_mutation() -> void:
	# 验证 fix 路径:用稳定 int(uid)作 key,entry 内容变化不影响查找
	var entry: Dictionary = {"x": 0, "y": 0, "_grid_uid": 42}
	var tracker: Dictionary = {}
	tracker[42] = "view"
	entry["x"] = 2
	entry["y"] = 5
	assert_true(tracker.has(42), "int uid 作 key:entry mutate 后 has 仍 true")

func test_grid_panel_uses_uid_for_item_views() -> void:
	# 防御:确保 grid_panel.gd 没回退到用 entry Dictionary 作 item_views 的 key
	var src: String = load("res://scripts/ui/grid_panel.gd").source_code
	# 1) 必须有 _entry_uid 函数
	assert_gte(src.find("func _entry_uid"), 0, "必须有 _entry_uid 函数分配稳定 uid")
	# 2) _add_item_view 必须 item_views[_entry_uid(entry)] = view,不能 item_views[entry] = view
	var add_idx: int = src.find("func _add_item_view")
	assert_gte(add_idx, 0)
	var add_end: int = src.find("\nfunc ", add_idx + 5)
	if add_end < 0:
		add_end = src.length()
	var add_body: String = src.substr(add_idx, add_end - add_idx)
	assert_true(add_body.contains("item_views[_entry_uid(entry)]"),
		"_add_item_view 必须用 _entry_uid 作 key,绝不能 item_views[entry] = view")
	assert_false(add_body.contains("item_views[entry] = view"),
		"_add_item_view 禁止直接用 entry Dictionary 作 key")