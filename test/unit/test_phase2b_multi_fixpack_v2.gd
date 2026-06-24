extends GutTest

# Phase 2B 多人 fix pack v2:用户手测发现的 3 个问题
# bug 1: host 自己拿/放物品时 _rpc_take/put_granted/denied.rpc_id(self) 不触发
#        → host 的 inventory 没 add entry,但 container 已 broadcast 删了
#        → fix:_send_take_granted helper,peer == self 时直接 emit signal
# bug 2: A 放回物品后,B 端 entries_synced 时 _state == IDLE 没重启 inspect
#        → fix:_on_container_entries_synced 检测 has_uninspected → 重启 _advance_to_next_inspect
# bug 3: extraction_zone 检测所有 player(包括 host 上的 peer 2 同步 player)
#        → 一人进区,另一人也撤离
#        → fix:_is_local_player(body) 校验 is_multiplayer_authority

var _mm: Node

func before_each() -> void:
	_mm = get_node("/root/MultiplayerManager")
	_mm.mode = _mm.Mode.SINGLE
	_mm.players.clear()
	_mm.peer = null

# ── bug 1:host self-RPC fix ──

func test_mm_has_send_helpers() -> void:
	assert_true(_mm.has_method("_send_take_granted"),
		"MM 必须有 _send_take_granted helper(host self → emit signal,远端 → rpc_id)")
	assert_true(_mm.has_method("_send_take_denied"),
		"MM 必须有 _send_take_denied helper")
	assert_true(_mm.has_method("_send_put_granted"),
		"MM 必须有 _send_put_granted helper")
	assert_true(_mm.has_method("_send_put_denied"),
		"MM 必须有 _send_put_denied helper")

func test_send_helpers_branch_on_local_peer() -> void:
	var src: String = load("res://scripts/autoloads/multiplayer_manager.gd").source_code
	for fn in ["_send_take_granted", "_send_take_denied", "_send_put_granted", "_send_put_denied"]:
		var i: int = src.find("func " + fn)
		assert_gte(i, 0, "%s 函数应存在" % fn)
		var j: int = src.find("\nfunc ", i + 5)
		if j < 0: j = src.length()
		var body: String = src.substr(i, j - i)
		assert_true(body.contains("get_local_peer_id"),
			"%s 必须查 get_local_peer_id 来判断 host self" % fn)
		assert_true(body.contains(".emit("),
			"%s 必须有本地 emit signal 路径(host self)" % fn)
		assert_true(body.contains("rpc_id"),
			"%s 必须有 rpc_id 路径(远端 peer)" % fn)

func test_request_take_uses_send_helpers() -> void:
	# _rpc_request_take 内部 reply 必须用 _send_take_granted/_send_take_denied,不能直接 .rpc_id
	var src: String = load("res://scripts/autoloads/multiplayer_manager.gd").source_code
	var i: int = src.find("func _rpc_request_take")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_send_take_granted"),
		"_rpc_request_take granted reply 必须用 _send_take_granted(host self bug fix)")
	assert_true(body.contains("_send_take_denied"),
		"_rpc_request_take denied reply 必须用 _send_take_denied")
	assert_false(body.contains("_rpc_take_granted.rpc_id"),
		"_rpc_request_take 不能直接调 _rpc_take_granted.rpc_id(host self 不触发)")
	assert_false(body.contains("_rpc_take_denied.rpc_id"),
		"_rpc_request_take 不能直接调 _rpc_take_denied.rpc_id(host self 不触发)")

func test_request_put_uses_send_helpers() -> void:
	var src: String = load("res://scripts/autoloads/multiplayer_manager.gd").source_code
	var i: int = src.find("func _rpc_request_put")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_send_put_granted"),
		"_rpc_request_put 必须用 _send_put_granted")
	assert_true(body.contains("_send_put_denied"),
		"_rpc_request_put 必须用 _send_put_denied")

# ── bug 2:entries_synced 检测 has_uninspected 后重启 inspect ──

func test_search_ui_entries_synced_restarts_inspect() -> void:
	var src: String = load("res://scripts/ui/search_ui.gd").source_code
	var i: int = src.find("func _on_container_entries_synced")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	# 必须检测 IDLE 状态下有未 inspect 的 entry → 重启 inspect 循环
	assert_true(body.contains("UIState.IDLE") or body.contains("_state == "),
		"_on_container_entries_synced 必须检测 _state IDLE")
	assert_true(body.contains("has_uninspected") or body.contains("not e.get(\"inspected\""),
		"_on_container_entries_synced 必须扫描 entries 查找未 inspected")
	# 必须调 _advance_to_next_inspect 重启
	assert_true(body.contains("_advance_to_next_inspect"),
		"_on_container_entries_synced 必须调 _advance_to_next_inspect 重启搜刮(B 端看到 A 放回的物品)")

# ── bug 3:extraction_zone 只反应 local-authority 玩家 ──

func test_extraction_zone_filters_local_player() -> void:
	var src: String = load("res://scripts/entities/extraction_zone.gd").source_code
	# 必须有 _is_local_player helper(或等价的 is_multiplayer_authority 检查)
	assert_true(src.contains("is_multiplayer_authority"),
		"extraction_zone 必须用 is_multiplayer_authority 过滤(防止远端 peer 同步过来的 Player 触发本地撤离)")
	# _on_body_entered 必须按 local 过滤
	var i: int = src.find("func _on_body_entered")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_is_local_player") or body.contains("is_multiplayer_authority"),
		"_on_body_entered 必须只反应 local 玩家")

# ── bug 5 (v3 fix):_initiate_multi_take/put 的 RPC 同步触发顺序 race ──
# host 自取/自放时,mm.request_take 同步触发 take_granted → _on_take_granted → _clear_pending_take_visuals
# 这把 _pending_take 重置成新空 dict。如果 ghost/highlight 在 RPC **之后**写入,
# 就写到了那个新空 dict → 永远清不掉 → ghost 卡左上角 + _pending_take 永远非空 → 拾取被守卫挡

func test_initiate_multi_take_sets_ghost_before_rpc() -> void:
	var src: String = load("res://scripts/ui/search_ui.gd").source_code
	var i: int = src.find("func _initiate_multi_take")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	# 在函数体里:_pending_take 的赋值必须含 ghost/highlight 字段(完整 init)
	# 且 mm.request_take 调用必须在赋值 _pending_take 之后
	var pending_assign: int = body.find("_pending_take = {")
	var rpc_call: int = body.find("mm.request_take(")
	assert_gte(pending_assign, 0, "必须有 _pending_take 完整赋值")
	assert_gte(rpc_call, 0, "必须调 mm.request_take")
	assert_lt(pending_assign, rpc_call,
		"_pending_take 完整赋值(含 ghost/highlight)必须 BEFORE mm.request_take(避免 host self-sync race)")
	# _pending_take 字典字面量内必须有 ghost/highlight key
	var dict_end: int = body.find("}", pending_assign)
	var dict_body: String = body.substr(pending_assign, dict_end - pending_assign)
	assert_true(dict_body.contains("\"ghost\""),
		"_pending_take 字面量必须含 ghost(避免 RPC 后再赋值导致 race)")
	assert_true(dict_body.contains("\"highlight\""),
		"_pending_take 字面量必须含 highlight")

func test_initiate_multi_put_sets_ghost_before_rpc() -> void:
	var src: String = load("res://scripts/ui/search_ui.gd").source_code
	var i: int = src.find("func _initiate_multi_put")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	var pending_assign: int = body.find("_pending_take = {")
	var rpc_call: int = body.find("mm.request_put(")
	assert_gte(pending_assign, 0)
	assert_gte(rpc_call, 0)
	assert_lt(pending_assign, rpc_call,
		"_pending_take 完整赋值必须 BEFORE mm.request_put(同 take 的 race)")

func test_grid_panel_no_double_click_emit() -> void:
	# 删左键双击拾取:grid_panel._on_view_input 不再 emit item_double_clicked
	var src: String = load("res://scripts/ui/grid_panel.gd").source_code
	var i: int = src.find("func _on_view_input")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_false(body.contains("item_double_clicked.emit"),
		"_on_view_input 不能 emit item_double_clicked(用户报双击 race 残留 ghost,改纯单击+右键)")

func test_search_ui_pending_take_guards_pickup() -> void:
	var src: String = load("res://scripts/ui/search_ui.gd").source_code
	var i: int = src.find("func _on_item_pressed")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_pending_take"),
		"_on_item_pressed 必须用 _pending_take 守卫(等 host RPC 时禁止新 begin_drag)")

func test_search_ui_cancel_drag_restores_dim() -> void:
	# multi 模式 cancel_drag 必须还原 source_view modulate(否则灰底残留)
	var src: String = load("res://scripts/ui/search_ui.gd").source_code
	var i: int = src.find("func _cancel_drag")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_restore_source_view"),
		"_cancel_drag 必须 _restore_source_view(no_remove 模式 cancel 不还原 dim 会残留)")

# ── bug 4:round 结束 host 重置 ready 状态 ──

func test_mm_has_reset_all_ready_rpc() -> void:
	var mm: Node = get_node("/root/MultiplayerManager")
	assert_true(mm.has_method("_rpc_reset_all_ready"),
		"MM 必须有 _rpc_reset_all_ready RPC(round 结束后重置 ready 状态)")

func test_check_all_done_broadcasts_ready_reset() -> void:
	var src: String = load("res://scripts/autoloads/multiplayer_manager.gd").source_code
	var i: int = src.find("func _check_all_done_and_settle")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_rpc_reset_all_ready"),
		"_check_all_done_and_settle 必须广播 _rpc_reset_all_ready(下一局可正常 ready)")

func test_home_inits_enter_btn_from_current_state() -> void:
	# home._setup_multiplayer_ui 必须用 mm._all_ready() 当前值初始化按钮(防 signal 错过)
	var src: String = load("res://scripts/home.gd").source_code
	var i: int = src.find("func _setup_multiplayer_ui")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_all_ready()"),
		"home._setup_multiplayer_ui 必须读取当前 _all_ready() 来初始化按钮")
