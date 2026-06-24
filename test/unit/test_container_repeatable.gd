extends GutTest

# 防御:容器第一次开后**仍可重复打开**(用户 2026-06-22 明确要求)
# 之前 looted 字段把"空了"和"锁死"耦合在一起,容易回退

func test_container_no_longer_has_looted_field() -> void:
	# looted 字段已删,免得有人误用(注意 looted_label 是节点引用名,不算)
	var src: String = load("res://scripts/entities/container.gd").source_code
	assert_false(src.contains("var looted: bool"),
		"container.gd 不应再有 var looted: bool 字段")
	assert_false(src.contains("var looted = "),
		"container.gd 不应再有 var looted = ... 字段")

func test_container_is_available_only_checks_opened() -> void:
	var src: String = load("res://scripts/entities/container.gd").source_code
	var i: int = src.find("func is_available")
	assert_gte(i, 0)
	var j: int = src.find("func ", i + 5)
	var body: String = src.substr(i, j - i)
	assert_false(body.contains("looted"), "is_available 不应检查 looted")
	assert_false(body.contains("is_searched"), "is_available 不应检查 is_searched(已搜也能开)")
	assert_false(body.contains("has_been_opened"), "is_available 不应检查 has_been_opened(同上)")
	assert_true(body.contains("opened"), "is_available 必须检查 opened(防止重入)")

func test_container_open_marks_has_been_opened_not_is_searched() -> void:
	# 关键: open() 设 has_been_opened (视觉)而不是 is_searched (跳过 inspect 流程)
	# 否则第一次打开会被 search_ui 当成"已 inspect",跳过放大镜动画
	# Phase 2B Tier B4 refactor:has_been_opened = true 写入移到 _apply_opened_local
	# open() 通过 _apply_opened_local()(单人) 或 mm.notify_container_opened(多人) 间接设
	var src: String = load("res://scripts/entities/container.gd").source_code
	var i: int = src.find("func open()")
	assert_gte(i, 0)
	var j: int = src.find("func ", i + 5)
	var body: String = src.substr(i, j - i)
	# open() 必须触发 has_been_opened 标记(通过 _apply_opened_local 或 notify_container_opened)
	assert_true(body.contains("_apply_opened_local") or body.contains("notify_container_opened"),
		"open() 必须触发 has_been_opened 标记(单人 _apply_opened_local / 多人 mm.notify_container_opened)")
	assert_false(body.contains("is_searched = true"),
		"open() 不能设 is_searched=true(否则 search_ui 跳过 inspect 流程)")
	# _apply_opened_local 必须设 has_been_opened = true
	var ai: int = src.find("func _apply_opened_local")
	assert_gte(ai, 0, "container.gd 必须有 _apply_opened_local 私有方法(Phase 2B Tier B4)")
	var aj: int = src.find("\nfunc ", ai + 5)
	if aj < 0:
		aj = src.length()
	var apply_body: String = src.substr(ai, aj - ai)
	assert_true(apply_body.contains("has_been_opened = true"),
		"_apply_opened_local 必须设 has_been_opened = true")

func test_container_get_prompt_changes_after_searched() -> void:
	var src: String = load("res://scripts/entities/container.gd").source_code
	# 双文案都在
	assert_true(src.contains("按 F 搜刮"), "首次提示必须有'按 F 搜刮'")
	assert_true(src.contains("按 F 再开"), "已搜后提示应有'按 F 再开'")

func test_main_no_longer_blocks_searched_container() -> void:
	var src: String = load("res://scripts/main.gd").source_code
	assert_false(src.contains("c.looted"), "main.gd 不应再检查 c.looted")

func test_hud_no_longer_blocks_searched_container() -> void:
	var src: String = load("res://scripts/ui/hud.gd").source_code
	assert_false(src.contains("c.looted"), "hud.gd 不应再检查 c.looted")

func test_search_ui_no_longer_blocks_searched_container() -> void:
	var src: String = load("res://scripts/ui/search_ui.gd").source_code
	assert_false(src.contains("c.looted"), "search_ui.gd 不应再检查 c.looted")
