extends GutTest

# 防御:menu.tscn 入口 + 单人/联机按钮接线
# - menu.gd 必须存在,单人按钮指向 home.tscn,联机按钮 disabled
# - project.godot main_scene 必须指向 menu.tscn(进入游戏第一个看到的)
# - home.gd 必须有"返回主菜单"按钮接线

func test_menu_scene_file_exists() -> void:
	assert_true(ResourceLoader.exists("res://scenes/menu.tscn"), "menu.tscn 必须存在")
	assert_true(ResourceLoader.exists("res://scripts/menu.gd"), "menu.gd 必须存在")

func test_project_main_scene_points_to_menu() -> void:
	# 读 project.godot 确保 main_scene 指向 menu(玩家进游戏先看菜单)
	var f := FileAccess.open("res://project.godot", FileAccess.READ)
	assert_not_null(f, "project.godot 应可读")
	var txt: String = f.get_as_text()
	f.close()
	assert_true(txt.contains("run/main_scene=\"res://scenes/menu.tscn\""),
		"project.godot run/main_scene 必须指向 menu.tscn")

func test_menu_single_button_goes_to_home() -> void:
	var src: String = load("res://scripts/menu.gd").source_code
	# 单人按钮的 _on_single 必须 change_scene_to_file 到 home.tscn
	assert_true(src.contains("change_scene_to_file") and src.contains("res://scenes/home.tscn"),
		"menu.gd 单人按钮必须切到 home.tscn")

func test_menu_multi_button_is_disabled() -> void:
	# 联机按钮必须 disabled(Phase 2 才接入)
	var src: String = load("res://scripts/menu.gd").source_code
	# 简单匹配:_multi_btn.disabled = true
	assert_true(src.contains("_multi_btn.disabled = true") or src.contains("multi_btn.disabled = true"),
		"联机按钮必须 disabled,Phase 2 真联机才解锁")

func test_home_has_back_to_menu_button() -> void:
	var src: String = load("res://scripts/home.gd").source_code
	# 必须有 _on_back_to_menu 函数,且切回 menu.tscn
	assert_true(src.contains("func _on_back_to_menu"),
		"home.gd 必须有 _on_back_to_menu 函数(让用户切回主菜单)")
	assert_true(src.contains("res://scenes/menu.tscn"),
		"home.gd 必须有切回 menu.tscn 的代码")
