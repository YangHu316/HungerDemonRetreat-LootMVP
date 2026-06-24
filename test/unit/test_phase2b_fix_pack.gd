extends GutTest

# Phase 2B Fix Pack:用户手测发现的 4 个问题
# Q1 容器实时同步:search_ui 必须订阅 entries_synced
# Q2 放回功能:search_ui inventory→container 走 put RPC
# Q3 host self-RPC:用 mm.request_take/request_extract helper(避免 rpc_id(1) 自调失败)
# Q4 home UI:多人 ready 浮动 panel,不被屏幕底裁掉

# ── Q1:Container apply_entries 必须 emit entries_synced ──

func test_container_emits_entries_synced_after_apply() -> void:
	var src: String = load("res://scripts/entities/container.gd").source_code
	assert_true(src.contains("signal entries_synced"),
		"container.gd 必须 declare entries_synced signal(Q1 实时同步)")
	# apply_entries 函数体最后必须 emit entries_synced
	var i: int = src.find("func apply_entries")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("entries_synced.emit"),
		"apply_entries 末尾必须 emit entries_synced(Q1)")

func test_search_ui_subscribes_entries_synced() -> void:
	var src: String = load("res://scripts/ui/search_ui.gd").source_code
	# open_for 必须订阅 entries_synced
	var i: int = src.find("func open_for")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("entries_synced"),
		"search_ui.open_for 必须订阅 container.entries_synced(Q1)")
	# 必须有 _on_container_entries_synced 处理函数
	assert_true(src.contains("func _on_container_entries_synced"),
		"search_ui 必须有 _on_container_entries_synced 处理函数")

# ── Q2:Put-back RPC 双向支持 ──

func test_mm_has_put_apis() -> void:
	var mm: Node = get_node("/root/MultiplayerManager")
	assert_true(mm.has_method("request_put"),
		"MM 必须有 request_put helper")
	assert_true(mm.has_method("_rpc_request_put"),
		"MM 必须有 _rpc_request_put RPC")
	assert_true(mm.has_method("_rpc_put_granted"))
	assert_true(mm.has_method("_rpc_put_denied"))
	assert_true(mm.has_signal("put_granted"))
	assert_true(mm.has_signal("put_denied"))

func test_search_ui_has_initiate_multi_put() -> void:
	var src: String = load("res://scripts/ui/search_ui.gd").source_code
	assert_true(src.contains("func _initiate_multi_put"),
		"search_ui 必须有 _initiate_multi_put(Q2 放回功能)")
	assert_true(src.contains("func _on_put_granted"),
		"search_ui 必须订阅 put_granted")
	assert_true(src.contains("func _on_put_denied"),
		"search_ui 必须订阅 put_denied")
	# _try_drop 多人 inventory→container 必须走 put 路径
	var i: int = src.find("func _try_drop")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_initiate_multi_put"),
		"_try_drop 多人 inventory→container 必须调 _initiate_multi_put(不再 toast 拒绝)")

# ── Q3:Host self-RPC bug 修复 ──

func test_mm_has_request_helpers() -> void:
	# request_take / request_extract 必须存在(host 走本地直接调,client rpc_id)
	var mm: Node = get_node("/root/MultiplayerManager")
	assert_true(mm.has_method("request_take"),
		"MM 必须有 request_take helper(Q3 fix:绕开 host self-RPC bug)")
	assert_true(mm.has_method("request_extract"),
		"MM 必须有 request_extract helper")

func test_request_helpers_branch_on_host() -> void:
	var src: String = load("res://scripts/autoloads/multiplayer_manager.gd").source_code
	# request_take 必须按 is_host 分支
	var i: int = src.find("func request_take")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("is_host"),
		"request_take 必须按 is_host 分支")
	# host 分支:直接调本地 _rpc_request_take(NOT .rpc_id)
	assert_true(body.contains("_rpc_request_take("),
		"host 分支必须直接调 _rpc_request_take(本地)")
	# client 分支:.rpc_id(1, ...)
	assert_true(body.contains("rpc_id(1"),
		"client 分支必须 .rpc_id(1, ...)")

	# request_extract 同样
	var i2: int = src.find("func request_extract")
	assert_gte(i2, 0)
	var j2: int = src.find("\nfunc ", i2 + 5)
	if j2 < 0: j2 = src.length()
	var body2: String = src.substr(i2, j2 - i2)
	assert_true(body2.contains("is_host"),
		"request_extract 必须按 is_host 分支")

# ── Q4:Home 多人 UI 浮动 panel ──

func test_home_uses_floating_mp_panel() -> void:
	var src: String = load("res://scripts/home.gd").source_code
	assert_true(src.contains("_mp_panel"),
		"home.gd 必须有 _mp_panel 字段(浮动 PanelContainer)")
	# anchored / offset 浮动定位
	# (源码 grep 不严格检查 anchor;只确保有 PanelContainer.new)
	assert_true(src.contains("PanelContainer.new()"),
		"home.gd 必须创建 PanelContainer(浮动 mp UI 容器)")
