extends GutTest

# P0 护栏 #1: 所有 ItemData .tres 数值合法性
# 防御对象: 评估文档 §3.1 — 占位/拼写错的 .tres 会导致策划数值悄悄漂移
# 不验感受/视觉,只验数值规则

const ITEMS_DIR := "res://resources/items/"

func _list_item_files() -> Array:
	var out: Array = []
	var d := DirAccess.open(ITEMS_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and f.ends_with(".tres"):
			out.append(ITEMS_DIR + f)
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

func test_item_dir_not_empty() -> void:
	var files := _list_item_files()
	assert_gt(files.size(), 0, "resources/items/ 至少要有一个 .tres")

func test_each_item_loads_as_item_data() -> void:
	for path in _list_item_files():
		var res := load(path)
		assert_not_null(res, "load 失败: %s" % path)
		assert_true(res is ItemData, "%s 不是 ItemData" % path)

func test_item_fields_valid() -> void:
	const VALID_RARITY := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
	for path in _list_item_files():
		var item: ItemData = load(path)
		assert_ne(item.id, "", "%s id 不能为空" % path)
		assert_ne(item.display_name, "", "%s display_name 不能为空" % path)
		assert_gt(item.value, 0, "%s value 必须 > 0" % path)
		assert_true(VALID_RARITY.has(item.rarity), "%s rarity=%s 非法" % [path, item.rarity])
		assert_between(item.grid_w, 1, 4, "%s grid_w 越界" % path)
		assert_between(item.grid_h, 1, 4, "%s grid_h 越界" % path)

func test_item_ids_unique() -> void:
	var seen: Dictionary = {}
	for path in _list_item_files():
		var item: ItemData = load(path)
		assert_false(seen.has(item.id), "id 重复: %s 与 %s 都是 '%s'" % [path, seen.get(item.id, ""), item.id])
		seen[item.id] = path
