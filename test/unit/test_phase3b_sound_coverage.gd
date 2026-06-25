extends GutTest

# 外卖侠 §06 Phase 3B 发声覆盖
# 防御 spec 05§1.2:容器搜刮 4m/8m / 大门 8m / 拾取 1.5m
# 设计:single-player 时 emit;多人模式跳过(host 权威 Phase 2C 再做)

var _gs: Node
var _bus: Node
var _mm: Node

func before_each() -> void:
	_gs = get_node("/root/GameSession")
	_bus = get_node("/root/EventBus")
	_mm = get_node("/root/MultiplayerManager")
	_mm.mode = _mm.Mode.SINGLE
	_mm.players.clear()
	_mm.peer = null
	_gs.round_active = false

# ── 容器 — get_search_sound_radius ──

func test_container_drawer_search_sound_4m() -> void:
	var src: String = load("res://scripts/entities/container.gd").source_code
	assert_true(src.contains("func get_search_sound_radius"),
		"Container 必须有 get_search_sound_radius() 方法")
	# spec 05§1.2:抽屉(低噪)4m / 衣柜(同低噪)4m / 保险箱(中噪)8m
	var i: int = src.find("func get_search_sound_radius")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("4.0"), "drawer/cabinet 应是 4m")
	assert_true(body.contains("8.0"), "safe 应是 8m")

# ── 容器 open() emit sound ──

func test_container_open_emits_search_sound() -> void:
	var src: String = load("res://scripts/entities/container.gd").source_code
	var i: int = src.find("func open")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_emit_search_sound"),
		"container.open() 必须调 _emit_search_sound")
	assert_true(src.contains("func _emit_search_sound"),
		"Container 必须有 _emit_search_sound 方法")

func test_container_emit_search_sound_skips_multiplayer() -> void:
	var src: String = load("res://scripts/entities/container.gd").source_code
	var i: int = src.find("func _emit_search_sound")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("is_single"),
		"_emit_search_sound 必须查 is_single(多人 host 权威 Phase 2C 再做)")
	assert_true(body.contains("sound_emitted"),
		"_emit_search_sound 必须 emit bus.sound_emitted")

# ── 门 — door.gd 8m ──

func test_door_has_toggle_sound_constant() -> void:
	var src: String = load("res://scripts/entities/door.gd").source_code
	assert_true(src.contains("DOOR_TOGGLE_SOUND_RADIUS"),
		"Door 必须有 DOOR_TOGGLE_SOUND_RADIUS 常量(spec 8m)")
	# 确认 8.0 出现在常量行
	var i: int = src.find("DOOR_TOGGLE_SOUND_RADIUS")
	var line_end: int = src.find("\n", i)
	var line: String = src.substr(i, line_end - i)
	assert_true(line.contains("8.0"),
		"DOOR_TOGGLE_SOUND_RADIUS 应是 8.0(spec 大门 8-10m 取低)")

func test_door_toggle_emits_sound() -> void:
	var src: String = load("res://scripts/entities/door.gd").source_code
	var i: int = src.find("func _apply_toggle_local")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_emit_door_sound"),
		"_apply_toggle_local 必须调 _emit_door_sound")
	assert_true(src.contains("func _emit_door_sound"),
		"Door 必须有 _emit_door_sound 方法")

func test_door_emit_sound_skips_multiplayer() -> void:
	var src: String = load("res://scripts/entities/door.gd").source_code
	var i: int = src.find("func _emit_door_sound")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("is_single"),
		"_emit_door_sound 必须查 is_single 跳过多人")
	assert_true(body.contains("sound_emitted"),
		"_emit_door_sound 必须 emit bus.sound_emitted")

# ── 拾取 — player.gd item_moved → 1.5m ──

func test_player_has_pickup_sound_constant() -> void:
	var src: String = load("res://scripts/entities/player.gd").source_code
	assert_true(src.contains("PICKUP_SOUND_RADIUS"),
		"Player 必须有 PICKUP_SOUND_RADIUS 常量(spec 1.5m)")
	var i: int = src.find("PICKUP_SOUND_RADIUS")
	var line_end: int = src.find("\n", i)
	var line: String = src.substr(i, line_end - i)
	assert_true(line.contains("1.5"),
		"PICKUP_SOUND_RADIUS 应是 1.5m(spec 拾取近乎无声)")

func test_player_listens_to_item_moved() -> void:
	var src: String = load("res://scripts/entities/player.gd").source_code
	assert_true(src.contains("item_moved.connect"),
		"Player._ready 必须订阅 EventBus.item_moved")
	assert_true(src.contains("func _on_item_moved"),
		"Player 必须有 _on_item_moved handler")

func test_player_pickup_only_when_to_inventory() -> void:
	var src: String = load("res://scripts/entities/player.gd").source_code
	var i: int = src.find("func _on_item_moved")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	# 只有 to_grid_id == "inventory" 才算拾取
	assert_true(body.contains("inventory"),
		"_on_item_moved 必须只在 to_grid_id == inventory 时 emit")
	# 必须排除 inventory→inventory(整理)
	assert_true(body.contains("from_grid_id"),
		"_on_item_moved 必须查 from_grid_id 排除 inventory→inventory(整理)")
	assert_true(body.contains("PICKUP_SOUND_RADIUS"),
		"_on_item_moved 必须用 PICKUP_SOUND_RADIUS")
	assert_true(body.contains("is_single"),
		"_on_item_moved 必须查 is_single 跳过多人")
