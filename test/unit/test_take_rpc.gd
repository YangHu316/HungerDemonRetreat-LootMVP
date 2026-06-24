extends GutTest

# Phase 2B Tier B5:Take-item 保守 RPC
# 防御:
#   - search_ui 加 _pending_take 字段 + _is_multiplayer / _is_single 助手
#   - search_ui._try_drop 多人 container→inventory 走 _initiate_multi_take(RPC)
#   - search_ui._on_item_double_clicked / _quick_transfer 多人也分支
#   - DragState 加 is_no_remove + begin_no_remove
#   - MM 加 take_granted/take_denied signal + 3 RPCs

var _mm: Node

func before_each() -> void:
	_mm = get_node_or_null("/root/MultiplayerManager")
	if _mm != null:
		_mm.mode = _mm.Mode.SINGLE
		_mm.players.clear()
		_mm.peer = null

# ── DragState ──

func test_drag_state_has_is_no_remove() -> void:
	var ds := DragState.new()
	assert_true("is_no_remove" in ds,
		"DragState 必须有 is_no_remove 字段")
	assert_false(ds.is_no_remove, "默认 false(单人旧路径)")

func test_drag_state_begin_no_remove_factory() -> void:
	# DragState.begin_no_remove 是 static 工厂方法
	# 没法直接 has_method on 类,而是通过 .new() 验证
	var ds := DragState.new()
	assert_true(ds.has_method("cancel_drag"), "DragState 应有 cancel_drag")
	# 用源码层验证 static 函数存在
	var src: String = load("res://scripts/drag_state.gd").source_code
	assert_true(src.contains("static func begin_no_remove"),
		"DragState 必须有 static begin_no_remove 工厂(多人 take 用)")

func test_drag_state_no_remove_cancel_no_op() -> void:
	# no_remove 模式下 cancel_drag 不动 grid(源没移除,host RPC 控制)
	var ds := DragState.new()
	ds.is_no_remove = true
	# 不该崩。空 entry 也安全 return
	ds.cancel_drag()
	pass_test("no_remove cancel_drag 不崩")

# ── MM RPC + signals ──

func test_mm_has_take_signals() -> void:
	assert_true(_mm.has_signal("take_granted"))
	assert_true(_mm.has_signal("take_denied"))

func test_mm_has_take_rpcs() -> void:
	assert_true(_mm.has_method("_rpc_request_take"))
	assert_true(_mm.has_method("_rpc_take_granted"))
	assert_true(_mm.has_method("_rpc_take_denied"))

func test_mm_request_take_rejects_non_host() -> void:
	# 非 host(SINGLE 或 CLIENT)接收 _rpc_request_take 应直接 return
	# 源码层验证 is_host() 早 return
	var src: String = load("res://scripts/autoloads/multiplayer_manager.gd").source_code
	var i: int = src.find("func _rpc_request_take")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("is_host"),
		"_rpc_request_take 必须以 is_host 校验开头(非 host 早 return)")
	# 必须找 entry by uid
	assert_true(body.contains("uid"),
		"_rpc_request_take 必须按 uid 在 container.contents.entries 中找物品")
	# 必须 broadcast 后 reply granted
	assert_true(body.contains("broadcast_container_entries"),
		"_rpc_request_take 通过后必须 broadcast_container_entries(同步所有 peer 容器内容)")
	assert_true(body.contains("_rpc_take_granted") or body.contains("take_granted.rpc_id"),
		"_rpc_request_take 通过后必须 reply _rpc_take_granted 给请求方")
	assert_true(body.contains("_rpc_take_denied") or body.contains("take_denied.rpc_id"),
		"_rpc_request_take 失败时必须 reply _rpc_take_denied")

# ── search_ui 源码层 ──

func test_search_ui_has_pending_take() -> void:
	var src: String = load("res://scripts/ui/search_ui.gd").source_code
	assert_true(src.contains("var _pending_take"),
		"search_ui.gd 必须有 _pending_take 字段")
	assert_true(src.contains("func _is_multiplayer") or src.contains("_is_multiplayer()"),
		"search_ui.gd 必须有 _is_multiplayer 助手")

func test_search_ui_try_drop_branches_on_mode() -> void:
	var src: String = load("res://scripts/ui/search_ui.gd").source_code
	var i: int = src.find("func _try_drop")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_is_multiplayer") or body.contains("_is_single"),
		"_try_drop 必须按 multi/single 分支")
	assert_true(body.contains("_initiate_multi_take") or body.contains("_rpc_request_take"),
		"_try_drop 多人分支必须调 _initiate_multi_take")

func test_search_ui_initiate_multi_take_uses_rpc() -> void:
	var src: String = load("res://scripts/ui/search_ui.gd").source_code
	var i: int = src.find("func _initiate_multi_take")
	assert_gte(i, 0, "search_ui 必须有 _initiate_multi_take 方法")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_rpc_request_take"),
		"_initiate_multi_take 必须调 mm._rpc_request_take.rpc_id(1, ...)")
	assert_true(body.contains("_pending_take"),
		"_initiate_multi_take 必须把状态记到 _pending_take")

func test_search_ui_take_handlers_exist() -> void:
	var src: String = load("res://scripts/ui/search_ui.gd").source_code
	assert_true(src.contains("func _on_take_granted"),
		"search_ui 必须有 _on_take_granted 处理 host granted RPC")
	assert_true(src.contains("func _on_take_denied"),
		"search_ui 必须有 _on_take_denied 处理 host denied RPC")

func test_search_ui_connects_mm_signals() -> void:
	var src: String = load("res://scripts/ui/search_ui.gd").source_code
	var i: int = src.find("func _ready")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("take_granted.connect") or body.contains("take_granted.is_connected"),
		"search_ui._ready 必须订阅 mm.take_granted")
	assert_true(body.contains("take_denied.connect") or body.contains("take_denied.is_connected"),
		"search_ui._ready 必须订阅 mm.take_denied")

# ── 单人模式不应走 RPC ──

func test_single_player_path_unchanged() -> void:
	# 单人模式下,_try_drop 走旧路径 → _drag.place_to + bus.item_moved.emit
	# 源码层确认这段还在
	var src: String = load("res://scripts/ui/search_ui.gd").source_code
	var i: int = src.find("func _try_drop")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_drag.place_to"),
		"_try_drop 单人路径必须保留 _drag.place_to(单人零回归)")
	assert_true(body.contains("item_moved.emit"),
		"_try_drop 单人路径必须 emit item_moved")
