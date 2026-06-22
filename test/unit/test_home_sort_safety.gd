extends GutTest

# 防御:home.gd 整理按钮(_on_sort_requested)在重新放置失败时**不能丢 entry**
# 起因:2026-06-22 用户测试旋转时报告物品消失。原代码用 continue 跳过 fit==null,
# 导致 entry 被 remove 后再也放不回去。

func test_home_sort_no_continue_in_fit_null_branch() -> void:
	var src: String = load("res://scripts/home.gd").source_code
	var i: int = src.find("func _on_sort_requested")
	assert_gte(i, 0, "_on_sort_requested 必须存在")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	# fit == null 分支不能用 continue(否则 entry 永久丢失)
	assert_false(body.contains("continue"),
		"_on_sort_requested 不能用 continue,否则 entry 会丢失;应该回滚")
	# 必须有备份概念(backup / 回滚)
	assert_true(
		body.contains("backup") or body.contains("rollback"),
		"_on_sort_requested 必须有备份/回滚机制"
	)

func test_home_sort_breaks_on_first_failure() -> void:
	# 一旦 fit == null 应该 break(然后回滚),而不是继续
	var src: String = load("res://scripts/home.gd").source_code
	var i: int = src.find("func _on_sort_requested")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("break"), "_on_sort_requested 应在第一次失败时 break")
