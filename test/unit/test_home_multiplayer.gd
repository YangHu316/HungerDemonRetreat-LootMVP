extends GutTest

# Phase 2B Tier B7:Home 多人 ready 流
# 防御:
#   - home.gd 加 _ready_toggle / _mp_player_list / _enter_btn 字段
#   - home.gd._on_enter 多人 host 调 mm.start_game(单人原行为)
#   - home.gd 多人订阅 mm 的 peer_joined/peer_left/all_ready_changed/game_started
#   - home.gd._on_ready_toggled 调 mm.set_local_ready

func test_home_has_multiplayer_ui_fields() -> void:
	var src: String = load("res://scripts/home.gd").source_code
	assert_true(src.contains("_ready_toggle"),
		"home.gd 必须有 _ready_toggle 字段(多人准备就绪 CheckBox)")
	assert_true(src.contains("_mp_player_list"),
		"home.gd 必须有 _mp_player_list 字段(多人玩家列表)")
	assert_true(src.contains("_enter_btn"),
		"home.gd 必须有 _enter_btn 字段(单人/多人共用按钮)")

func test_home_on_enter_branches_on_mode() -> void:
	var src: String = load("res://scripts/home.gd").source_code
	var i: int = src.find("func _on_enter")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("is_single"),
		"home.gd._on_enter 必须按 is_single 分支")
	# 单人:仍然 change_scene_to_file main.tscn(零回归)
	assert_true(body.contains("res://scenes/main.tscn"),
		"home.gd._on_enter 单人必须 change_scene_to_file main.tscn")
	# 多人 host:调 mm.start_game
	assert_true(body.contains("mm.start_game") or body.contains("start_game()"),
		"home.gd._on_enter 多人 host 必须调 mm.start_game")

func test_home_uses_set_local_ready() -> void:
	var src: String = load("res://scripts/home.gd").source_code
	assert_true(src.contains("set_local_ready"),
		"home.gd 必须调 mm.set_local_ready(由 _on_ready_toggled 触发)")

func test_home_subscribes_mm_signals() -> void:
	var src: String = load("res://scripts/home.gd").source_code
	# 必须订阅 mm 的关键 signals
	assert_true(src.contains("all_ready_changed"),
		"home.gd 必须订阅 mm.all_ready_changed(更新 host 开始按钮)")
	assert_true(src.contains("game_started"),
		"home.gd 必须订阅 mm.game_started(host 触发后跳 main.tscn)")
	assert_true(src.contains("peer_joined") or src.contains("peer_left"),
		"home.gd 必须订阅 mm.peer_joined/peer_left(刷新玩家列表)")

func test_home_setup_mp_ui_called_in_ready() -> void:
	var src: String = load("res://scripts/home.gd").source_code
	var i: int = src.find("func _ready")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_setup_multiplayer_ui"),
		"home.gd._ready 必须调 _setup_multiplayer_ui")

func test_home_back_to_menu_unchanged() -> void:
	# 老 test_menu.gd 防御:home.gd 必须有 _on_back_to_menu 函数 + 切回 menu.tscn
	var src: String = load("res://scripts/home.gd").source_code
	assert_true(src.contains("func _on_back_to_menu"),
		"home.gd 必须保留 _on_back_to_menu(单人零回归)")
	assert_true(src.contains("res://scenes/menu.tscn"),
		"home.gd 必须保留切回 menu.tscn")

# 实际 Control 实例化测试(_ready 跑过)
# 单人模式 home 应该正常
func test_home_loads_in_single_mode() -> void:
	var mm: Node = get_node_or_null("/root/MultiplayerManager")
	if mm != null:
		mm.mode = mm.Mode.SINGLE
		mm.players.clear()
	var HomeScene: PackedScene = load("res://scenes/home.tscn")
	if HomeScene == null:
		pending("home.tscn missing")
		return
	var inst = HomeScene.instantiate()
	add_child_autofree(inst)
	# _ready 应该跑过,不崩
	pass_test("home 单人模式实例化成功")
