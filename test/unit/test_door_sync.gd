extends GutTest

# Phase 2B fix bug 6:Door 状态多人同步
# 用户报:A 开门后 B 看到门没开,B 还过不去
# 根因:door.gd toggle() 没走 RPC,各 peer 本地独立切 is_open
# Fix:同 container_opened 模式 — host 权威 + RPC 广播

var _mm: Node

func before_each() -> void:
	_mm = get_node("/root/MultiplayerManager")
	_mm.mode = _mm.Mode.SINGLE
	_mm.players.clear()
	_mm.peer = null

func test_door_toggle_branches_on_mode() -> void:
	var src: String = load("res://scripts/entities/door.gd").source_code
	var i: int = src.find("func toggle")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("is_single"),
		"door.toggle 必须按 mm.is_single 分支")
	assert_true(body.contains("notify_door_toggle"),
		"door.toggle 多人必须调 mm.notify_door_toggle(走 RPC,host 权威)")
	assert_true(body.contains("_apply_toggle_local"),
		"door.toggle 单人必须直接调 _apply_toggle_local")

func test_door_has_apply_toggle_local() -> void:
	var src: String = load("res://scripts/entities/door.gd").source_code
	assert_true(src.contains("func _apply_toggle_local"),
		"door 必须有 _apply_toggle_local(给 RPC 调,真正切 is_open + 动画)")

func test_mm_has_door_toggle_rpcs() -> void:
	assert_true(_mm.has_method("notify_door_toggle"),
		"MM 必须有 notify_door_toggle helper")
	assert_true(_mm.has_method("_rpc_request_door_toggle"),
		"MM 必须有 _rpc_request_door_toggle(client → host)")
	assert_true(_mm.has_method("_rpc_apply_door_toggle"),
		"MM 必须有 _rpc_apply_door_toggle(host 广播)")

func test_notify_door_toggle_branches_on_host() -> void:
	var src: String = load("res://scripts/autoloads/multiplayer_manager.gd").source_code
	var i: int = src.find("func notify_door_toggle")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("is_host"),
		"notify_door_toggle 必须按 is_host 分支(host 直接广播,client rpc_id 转发)")
	assert_true(body.contains("_rpc_apply_door_toggle.rpc("),
		"host 分支必须 _rpc_apply_door_toggle.rpc(...)(call_local 自己也跑)")
	assert_true(body.contains("rpc_id(1"),
		"client 分支必须 rpc_id(1, ...) 给 host")

func test_request_door_toggle_only_host() -> void:
	var src: String = load("res://scripts/autoloads/multiplayer_manager.gd").source_code
	var i: int = src.find("func _rpc_request_door_toggle")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("is_host"),
		"_rpc_request_door_toggle 必须以 is_host 校验开头")
	assert_true(body.contains("_rpc_apply_door_toggle"),
		"_rpc_request_door_toggle 通过后必须广播 _rpc_apply_door_toggle")
