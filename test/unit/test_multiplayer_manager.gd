extends GutTest

# Phase 2A:MultiplayerManager 状态机 + 公共 API(不真起 ENet,只测内部 state)

var mm: Node

func before_each() -> void:
	mm = get_node("/root/MultiplayerManager")
	# 重置到 SINGLE
	mm.mode = mm.Mode.SINGLE
	mm.players.clear()
	mm.peer = null

func test_default_mode_is_single() -> void:
	assert_eq(mm.mode, mm.Mode.SINGLE)
	assert_true(mm.is_single())
	assert_false(mm.is_host())
	assert_false(mm.is_client())

func test_max_peers_is_3() -> void:
	# 文档 v7:固定 3 人合作,不做适配
	assert_eq(mm.MAX_PEERS, 3, "MAX_PEERS 必须 = 3(文档 v7 固定 3 人)")

func test_default_port_constant() -> void:
	assert_eq(mm.DEFAULT_PORT, 12345)

func test_is_host_after_setting_mode() -> void:
	mm.mode = mm.Mode.HOST
	assert_true(mm.is_host())
	assert_false(mm.is_single())

func test_is_client_after_setting_mode() -> void:
	mm.mode = mm.Mode.CLIENT
	assert_true(mm.is_client())
	assert_false(mm.is_single())

func test_all_ready_returns_false_when_empty() -> void:
	mm.players.clear()
	assert_false(mm._all_ready(), "空房间不算 all_ready")

func test_all_ready_returns_false_when_any_not_ready() -> void:
	mm.players = {
		1: {"name": "A", "ready": true, "color": Color.WHITE},
		2: {"name": "B", "ready": false, "color": Color.RED}
	}
	assert_false(mm._all_ready())

func test_all_ready_returns_true_when_all_ready() -> void:
	mm.players = {
		1: {"name": "A", "ready": true, "color": Color.WHITE},
		2: {"name": "B", "ready": true, "color": Color.RED}
	}
	assert_true(mm._all_ready())

func test_get_local_peer_id_single() -> void:
	mm.mode = mm.Mode.SINGLE
	assert_eq(mm.get_local_peer_id(), 0, "单人模式 peer_id = 0")

func test_get_local_peer_id_host() -> void:
	mm.mode = mm.Mode.HOST
	assert_eq(mm.get_local_peer_id(), 1, "host 的 peer_id 永远 = 1")

func test_has_required_signals() -> void:
	for sig_name in ["peer_joined", "peer_left", "connection_failed",
			"connected_to_server", "disconnected_from_server",
			"all_ready_changed", "game_started", "mode_changed"]:
		assert_true(mm.has_signal(sig_name), "必须有 signal: %s" % sig_name)

func test_has_required_methods() -> void:
	for m in ["host_room", "join_room", "leave_room", "set_local_ready",
			"start_game", "is_host", "is_client", "is_single"]:
		assert_true(mm.has_method(m), "必须有 method: %s" % m)
