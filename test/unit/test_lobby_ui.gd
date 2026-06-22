extends GutTest

# Phase 2A:大厅 UI 源码层防御 — lobby.gd 必须有正确的按钮接线

func test_lobby_scene_and_script_exist() -> void:
	assert_true(ResourceLoader.exists("res://scenes/lobby.tscn"))
	assert_true(ResourceLoader.exists("res://scripts/lobby.gd"))

func test_lobby_creates_room_via_mm() -> void:
	var src: String = load("res://scripts/lobby.gd").source_code
	assert_true(src.contains("_mm.host_room"),
		"创建房间按钮必须调 MultiplayerManager.host_room")

func test_lobby_joins_room_via_mm() -> void:
	var src: String = load("res://scripts/lobby.gd").source_code
	assert_true(src.contains("_mm.join_room"),
		"加入房间按钮必须调 MultiplayerManager.join_room")

func test_lobby_back_to_menu() -> void:
	var src: String = load("res://scripts/lobby.gd").source_code
	assert_true(src.contains("res://scenes/menu.tscn"),
		"必须有返回菜单的 change_scene")

func test_lobby_leave_room() -> void:
	var src: String = load("res://scripts/lobby.gd").source_code
	assert_true(src.contains("_mm.leave_room"),
		"离开房间按钮必须调 MultiplayerManager.leave_room")

func test_lobby_set_ready() -> void:
	var src: String = load("res://scripts/lobby.gd").source_code
	assert_true(src.contains("_mm.set_local_ready"),
		"Ready 按钮必须调 MultiplayerManager.set_local_ready")

func test_lobby_start_game() -> void:
	var src: String = load("res://scripts/lobby.gd").source_code
	assert_true(src.contains("_mm.start_game"),
		"开始按钮必须调 MultiplayerManager.start_game")
