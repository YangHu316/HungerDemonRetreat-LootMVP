extends GutTest

# Phase 2B Tier B4:has_been_opened 全局同步("已搜 badge")
# 防御:
#   - container.gd 把 has_been_opened 标记拆出 _apply_opened_local 私有方法(给 RPC 调)
#   - container.open() 多人模式调 mm.notify_container_opened(走 RPC)
#   - mm 加 notify_container_opened / _rpc_request_container_opened / _rpc_apply_container_opened

var _mm: Node
var _ContainerScene: PackedScene

func before_each() -> void:
	_mm = get_node_or_null("/root/MultiplayerManager")
	if _mm != null:
		_mm.mode = _mm.Mode.SINGLE
		_mm.players.clear()
		_mm.peer = null
	_ContainerScene = load("res://scenes/container.tscn")

# ── 源码层契约 ──

func test_container_has_apply_opened_local() -> void:
	var src: String = load("res://scripts/entities/container.gd").source_code
	assert_true(src.contains("func _apply_opened_local"),
		"container.gd 必须有 _apply_opened_local 私有方法(给 RPC 调,幂等本地标记)")

func test_container_open_branches_on_mode() -> void:
	var src: String = load("res://scripts/entities/container.gd").source_code
	var i: int = src.find("func open")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("is_single"),
		"container.open 必须有 is_single 分支判断")
	assert_true(body.contains("notify_container_opened"),
		"container.open 多人分支必须调 mm.notify_container_opened")

func test_mm_has_open_rpcs() -> void:
	assert_true(_mm.has_method("notify_container_opened"),
		"MM 必须有 notify_container_opened API")
	assert_true(_mm.has_method("_rpc_request_container_opened"),
		"MM 必须有 _rpc_request_container_opened RPC")
	assert_true(_mm.has_method("_rpc_apply_container_opened"),
		"MM 必须有 _rpc_apply_container_opened RPC")

func test_mm_notify_container_opened_routing() -> void:
	var src: String = load("res://scripts/autoloads/multiplayer_manager.gd").source_code
	var i: int = src.find("func notify_container_opened")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("is_host"),
		"notify_container_opened 必须按 is_host 分流")
	assert_true(body.contains("_rpc_apply_container_opened"),
		"host 分支必须 _rpc_apply_container_opened.rpc(广播)")
	assert_true(body.contains("_rpc_request_container_opened"),
		"client 分支必须 _rpc_request_container_opened.rpc_id (发给 host)")

# ── 单人功能等价(open → has_been_opened=true)──

func test_single_player_open_marks_has_been_opened() -> void:
	_mm.mode = _mm.Mode.SINGLE
	var c: Node = _ContainerScene.instantiate()
	add_child_autofree(c)
	assert_false(c.has_been_opened, "新 container has_been_opened=false")
	c.open()
	assert_true(c.has_been_opened, "open() 后(单人)has_been_opened=true")
	# looted_label 应可见
	assert_true(c.looted_label.visible,
		"open() 后 looted_label 应显示(已搜 badge)")

func test_apply_opened_local_idempotent() -> void:
	# 重复调不应崩
	_mm.mode = _mm.Mode.SINGLE
	var c: Node = _ContainerScene.instantiate()
	add_child_autofree(c)
	c._apply_opened_local()
	c._apply_opened_local()  # 第二次幂等
	assert_true(c.has_been_opened)
