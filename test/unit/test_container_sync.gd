extends GutTest

# Phase 2B Tier B2:Container content host-authoritative 同步
# 防御:
#   - container.gd 加 uid 字段(host 分配,wire 传输)
#   - container.gd 加 serialize_entries / apply_entries
#   - container._ready 多人 client 跳过本地生成
#   - GameSession 加 _next_entry_uid + next_entry_uid()
#   - MM 加 broadcast_container_entries / _rpc_apply_container_entries

var _gs: Node
var _mm: Node

func before_each() -> void:
	_gs = get_node_or_null("/root/GameSession")
	_mm = get_node_or_null("/root/MultiplayerManager")
	if _mm != null:
		_mm.mode = _mm.Mode.SINGLE
		_mm.players.clear()
		_mm.peer = null
	if _gs != null:
		_gs.round_active = false
		_gs._next_entry_uid = 0

func after_each() -> void:
	if _mm != null:
		_mm.mode = _mm.Mode.SINGLE
		_mm.players.clear()
		_mm.peer = null

# ── 字段/方法存在性 ──

func test_game_session_has_uid_counter() -> void:
	assert_true("_next_entry_uid" in _gs,
		"GameSession 必须有 _next_entry_uid 字段")
	assert_true(_gs.has_method("next_entry_uid"),
		"GameSession 必须有 next_entry_uid() 方法")

func test_next_entry_uid_increments() -> void:
	_gs._next_entry_uid = 0
	var a: int = _gs.next_entry_uid()
	var b: int = _gs.next_entry_uid()
	var c: int = _gs.next_entry_uid()
	assert_eq(a, 0, "第 1 个 uid = 0")
	assert_eq(b, 1, "第 2 个 uid = 1")
	assert_eq(c, 2, "第 3 个 uid = 2")
	# 全 unique
	assert_ne(a, b)
	assert_ne(b, c)

func test_start_round_resets_uid_counter() -> void:
	_gs._next_entry_uid = 99
	_gs.start_round()
	assert_eq(_gs._next_entry_uid, 0,
		"start_round 必须重置 _next_entry_uid = 0")
	_gs.round_active = false

# ── container.gd 源码层 ──

func test_container_has_serialize_apply_methods() -> void:
	var src: String = load("res://scripts/entities/container.gd").source_code
	assert_true(src.contains("func serialize_entries"),
		"container.gd 必须有 serialize_entries 方法(host 序列化给 RPC)")
	assert_true(src.contains("func apply_entries"),
		"container.gd 必须有 apply_entries 方法(client 收 RPC 后应用)")

func test_container_ready_guards_client_generation() -> void:
	var src: String = load("res://scripts/entities/container.gd").source_code
	# _ready 函数体应该含 is_client() 判断(多人 client 跳过 _generate_contents)
	var i: int = src.find("func _ready")
	assert_gte(i, 0, "container.gd 应有 _ready")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("is_client"),
		"container.gd._ready 必须有 mm.is_client() 判断(client 跳过本地 _generate_contents)")

func test_container_generate_uses_uid_counter() -> void:
	# _generate_contents 应调 next_entry_uid 给 entry 分 uid
	var src: String = load("res://scripts/entities/container.gd").source_code
	var i: int = src.find("func _generate_contents")
	assert_gte(i, 0, "container.gd 应有 _generate_contents")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("next_entry_uid") or body.contains("\"uid\""),
		"_generate_contents 必须给 entry 加 uid 字段")

# ── serialize / apply 往返 ──

func test_serialize_apply_roundtrip() -> void:
	# 用一个临时 container 实例验证 serialize → apply 数据不丢
	# 直接构造 entries 测试 apply_entries 的反序列化
	var ContainerScene: PackedScene = load("res://scenes/container.tscn")
	if ContainerScene == null:
		pending("container.tscn missing — skipping roundtrip")
		return
	# 用 ContainerLootTable 太复杂,直接手工构造 wire entries
	var wire: Array = [{
		"uid": 42,
		"item_path": "res://resources/items/canned_food.tres",
		"x": 0, "y": 0,
		"rotated": false,
		"freshness_elapsed": 12.5,
	}]
	# instantiate container,但绕开 _ready 的网络判断(GUT 环境单人)
	var c: Node = ContainerScene.instantiate()
	add_child_autofree(c)
	# _ready 会自己 _generate_contents(单人),先清掉
	if c.contents != null:
		c.contents.cells.clear()
		c.contents.entries.clear()
	c.apply_entries(wire)
	assert_eq(c.contents.entries.size(), 1, "apply_entries 应放 1 个 entry")
	var entry = c.contents.entries[0]
	assert_eq(int(entry["uid"]), 42, "uid 应保留 42")
	assert_eq(float(entry["freshness_elapsed"]), 12.5, "freshness_elapsed 应保留")
	# serialize 再回
	var out: Array = c.serialize_entries()
	assert_eq(out.size(), 1, "serialize 应有 1 个 entry")
	assert_eq(int(out[0]["uid"]), 42)

# ── MM RPC 接线 ──

func test_mm_has_rpc_apply_container_entries() -> void:
	assert_true(_mm.has_method("_rpc_apply_container_entries"),
		"MM 必须有 _rpc_apply_container_entries RPC")

func test_mm_has_broadcast_container_entries() -> void:
	assert_true(_mm.has_method("broadcast_container_entries"),
		"MM 必须有 broadcast_container_entries(host 调,推给所有 peer)")

func test_mm_broadcast_round_start_includes_containers() -> void:
	var src: String = load("res://scripts/autoloads/multiplayer_manager.gd").source_code
	var i: int = src.find("func broadcast_round_start")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("serialize_entries"),
		"broadcast_round_start 必须 serialize_entries 容器")
	assert_true(body.contains("containers"),
		"broadcast_round_start payload 必须含 containers key")

# ── main.gd 客户端跳过 reset_and_regenerate ──

func test_main_gd_client_skips_container_regen() -> void:
	var src: String = load("res://scripts/main.gd").source_code
	var i: int = src.find("func _on_round_started")
	assert_gte(i, 0, "main.gd 应有 _on_round_started")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("is_client"),
		"main.gd._on_round_started 必须有 is_client 判断(client 跳过 reset_and_regenerate)")
