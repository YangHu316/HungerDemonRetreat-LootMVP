extends Node
# MultiplayerManager — autoload,跨场景管理 ENet host/client + 玩家列表
# Phase 2A scope:LAN 主机权威。host 创 server,client connect server。
# 玩家列表用 Dictionary[peer_id] → {name, ready, color}。
# host 调 start_game() → RPC 让所有 peer 切到 main.tscn。

enum Mode { SINGLE, HOST, CLIENT }

const DEFAULT_PORT: int = 12345
const MAX_PEERS: int = 3  # 文档 v7:固定 3 人

signal mode_changed(mode: int)
signal peer_joined(id: int, info: Dictionary)
signal peer_left(id: int)
signal connection_failed
signal connected_to_server
signal disconnected_from_server
signal local_ready_changed(ready: bool)
signal all_ready_changed(all_ready: bool)
signal game_started
# Phase 2B Tier B5:take-item RPC 回调 → search_ui 监听
signal take_granted(entry_wire: Dictionary, dest_grid_id: String, dest_x: int, dest_y: int, rotated: bool)
signal take_denied(container_path: String, entry_uid: int, reason: String)
# Phase 2B Q2:put-back(背包→容器)对称 RPC
signal put_granted(item_path: String, source_inv_x: int, source_inv_y: int)
signal put_denied(item_path: String, reason: String)

var mode: int = Mode.SINGLE
var peer: ENetMultiplayerPeer = null
# peer_id → {"name": String, "ready": bool, "color": Color}
var players: Dictionary = {}
var local_name: String = "Player"

func _ready() -> void:
	# 全局 multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# ---------- host / join / leave ----------

func host_room(port: int = DEFAULT_PORT) -> bool:
	_reset_state()
	peer = ENetMultiplayerPeer.new()
	var err: int = peer.create_server(port, MAX_PEERS)
	if err != OK:
		peer = null
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	# host 自己也是 peer 1
	players[1] = _make_local_info()
	mode_changed.emit(mode)
	peer_joined.emit(1, players[1])
	return true

func join_room(ip: String, port: int = DEFAULT_PORT) -> bool:
	_reset_state()
	peer = ENetMultiplayerPeer.new()
	var err: int = peer.create_client(ip, port)
	if err != OK:
		peer = null
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	mode_changed.emit(mode)
	# 我自己的信息会在 _on_connected_ok 后通过 RPC 同步给 host
	return true

func leave_room() -> void:
	if peer != null:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	_reset_state()
	mode = Mode.SINGLE
	mode_changed.emit(mode)

func _reset_state() -> void:
	players.clear()

func _make_local_info() -> Dictionary:
	return {"name": local_name, "ready": false, "color": Color.WHITE}

# ---------- 多人事件回调 ----------

func _on_peer_connected(id: int) -> void:
	# host 视角:新 peer 连上,等 client 调 RPC 注册自己
	if mode == Mode.HOST:
		# 把当前 players 数据 RPC 推给新 peer
		for pid in players.keys():
			_rpc_register_peer.rpc_id(id, pid, players[pid])

func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		players.erase(id)
		peer_left.emit(id)
		_recheck_all_ready()

func _on_connected_ok() -> void:
	# client 视角:连上 host 了
	connected_to_server.emit()
	# 把自己注册给 host
	var my_id: int = multiplayer.get_unique_id()
	players[my_id] = _make_local_info()
	_rpc_register_peer.rpc(my_id, players[my_id])

func _on_connection_failed() -> void:
	connection_failed.emit()
	leave_room()

func _on_server_disconnected() -> void:
	disconnected_from_server.emit()
	leave_room()

# ---------- RPC ----------

# any_peer 调用,任何 peer 注册自己。host 收到后广播给其他人。
@rpc("any_peer", "call_local", "reliable")
func _rpc_register_peer(peer_id: int, info: Dictionary) -> void:
	players[peer_id] = info
	peer_joined.emit(peer_id, info)
	_recheck_all_ready()
	# host 广播给其他人(除发起者)
	if mode == Mode.HOST and multiplayer.get_remote_sender_id() != 0:
		var sender: int = multiplayer.get_remote_sender_id()
		for other_id in players.keys():
			if other_id != sender and other_id != 1:
				_rpc_register_peer.rpc_id(other_id, peer_id, info)

# any_peer 切换自己的 ready 状态
@rpc("any_peer", "call_local", "reliable")
func _rpc_set_ready(peer_id: int, is_ready: bool) -> void:
	if players.has(peer_id):
		players[peer_id]["ready"] = is_ready
		if peer_id == multiplayer.get_unique_id():
			local_ready_changed.emit(is_ready)
		_recheck_all_ready()

# host 才能调,广播开局
@rpc("authority", "call_local", "reliable")
func _rpc_start_game() -> void:
	game_started.emit()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

# ──────────────────────────────────────────────────────────────
# Phase 2B Tier B1:Round 生命周期 host-authoritative
# ──────────────────────────────────────────────────────────────

# host 在 main.gd._ready 完成本地 start_round 后调,广播给所有 client
# B2 会扩 payload 加 container entries(每个容器 path → wire entries)
func broadcast_round_start() -> void:
	if not is_host():
		return
	var containers_payload: Dictionary = {}
	# 收集所有 containers 当前的 wire entries
	# main.gd._on_round_started 已先调过 reset_and_regenerate(host 分支),uid 全新
	for c in get_tree().get_nodes_in_group("containers"):
		if c.has_method("serialize_entries"):
			containers_payload[String(c.get_path())] = c.serialize_entries()
	var payload: Dictionary = {
		"round_time": 900.0,
		"containers": containers_payload,
	}
	# 测试 / mock 模式(无真实 peer):.rpc() 不触发 call_local,直接本地调用
	if multiplayer.multiplayer_peer == null:
		# host 已本地 start_round 过,_rpc_apply_round_start 内部 round_active guard 会跳过 — OK
		_rpc_apply_round_start(payload)
	else:
		_rpc_apply_round_start.rpc(payload)

# host 广播给所有 peer(host 也通过 call_local 进来,但 round_active 已 true → guard 跳过)
@rpc("authority", "call_local", "reliable")
func _rpc_apply_round_start(payload: Dictionary) -> void:
	var gs = get_node_or_null("/root/GameSession")
	if gs == null:
		return
	# Guard:host 已经本地 start_round 过,跳过(避免 round_started 信号重复 emit)
	if gs.round_active:
		# host call_local 走这里;同时 host 的 containers 已生成。客户端也不该到这条路径,因为 round_active 仅在 start_round 后 true。
		return
	gs.start_round()
	# Apply container entries(client 第一次收到)
	var containers: Dictionary = payload.get("containers", {})
	for path in containers.keys():
		var c = get_tree().root.get_node_or_null(NodePath(String(path)))
		if c != null and c.has_method("apply_entries"):
			c.apply_entries(containers[path])

# host 在拿物品后,把单容器的最新 entries 推给所有 peer
func broadcast_container_entries(container_path: String, wire_entries: Array) -> void:
	if not is_host():
		return
	_rpc_apply_container_entries.rpc(container_path, wire_entries)

@rpc("authority", "call_local", "reliable")
func _rpc_apply_container_entries(container_path: String, wire_entries: Array) -> void:
	var c = get_tree().root.get_node_or_null(NodePath(container_path))
	if c != null and c.has_method("apply_entries"):
		c.apply_entries(wire_entries)

# ──────────────────────────────────────────────────────────────
# Phase 2B Tier B4:has_been_opened 全局同步(已搜 badge 给所有 peer)
# ──────────────────────────────────────────────────────────────

# Container.open() 多人模式调:host 直接广播,client 通过 host 转发
func notify_container_opened(container_path: String) -> void:
	if is_single():
		return  # 不该被单人调
	if is_host():
		# host 直接广播(包含 host 自己 via call_local)
		_rpc_apply_container_opened.rpc(container_path)
	else:
		# client 发请求给 host
		_rpc_request_container_opened.rpc_id(1, container_path)

# Phase 2B Tier B5 / B6 fix:host self-RPC 不会触发(rpc_id(1) from peer 1 无 call_local).
# 用 helper 让 host 直接调本地函数。
func request_take(container_path: String, entry_uid: int,
		dest_grid_id: String, dest_x: int, dest_y: int, rotated: bool) -> void:
	if is_single():
		return
	if is_host():
		# host 自己拿物品:直接调本地处理(sender_id=0 → 视为 1)
		_rpc_request_take(container_path, entry_uid, dest_grid_id, dest_x, dest_y, rotated)
	else:
		_rpc_request_take.rpc_id(1, container_path, entry_uid, dest_grid_id, dest_x, dest_y, rotated)

func request_extract(peer_id: int) -> void:
	if is_single():
		return
	if is_host():
		_rpc_request_extract(peer_id)
	else:
		_rpc_request_extract.rpc_id(1, peer_id)

# Phase 2B Q2 fix:背包→容器放回(对称 take RPC)
func request_put(container_path: String, item_path: String, freshness: float,
		dest_x: int, dest_y: int, rotated: bool, source_inv_x: int, source_inv_y: int) -> void:
	if is_single():
		return
	if is_host():
		_rpc_request_put(container_path, item_path, freshness, dest_x, dest_y, rotated, source_inv_x, source_inv_y)
	else:
		_rpc_request_put.rpc_id(1, container_path, item_path, freshness, dest_x, dest_y, rotated, source_inv_x, source_inv_y)

# Client → Host 请求"我开了 path 这个容器"
@rpc("any_peer", "reliable")
func _rpc_request_container_opened(container_path: String) -> void:
	if not is_host():
		return  # 只 host 处理
	var c = get_tree().root.get_node_or_null(NodePath(container_path))
	if c == null:
		return
	if "has_been_opened" in c and c.has_been_opened:
		return  # 已标过,不重复广播
	_rpc_apply_container_opened.rpc(container_path)

# Host → All peers 广播"标记 path 容器已搜"
@rpc("authority", "call_local", "reliable")
func _rpc_apply_container_opened(container_path: String) -> void:
	var c = get_tree().root.get_node_or_null(NodePath(container_path))
	if c != null and c.has_method("_apply_opened_local"):
		c._apply_opened_local()

# ──────────────────────────────────────────────────────────────
# Phase 2B Tier B5:Take-item 保守 RPC
#   Client 想拿物品 → _rpc_request_take 给 host
#   Host 校验:容器存在 + entry by uid 还在容器内
#   通过:从 container 移 entry,broadcast 全员 entries 更新,reply granted 给请求方
#   失败:reply denied(toast 拿取失败)
#   注:背包 can_place 校验 trust client(plan §关键不确定点 5,Phase 2D/E 再防作弊)
# ──────────────────────────────────────────────────────────────

# Client → Host:请求拿物品
@rpc("any_peer", "reliable")
func _rpc_request_take(container_path: String, entry_uid: int,
		dest_grid_id: String, dest_x: int, dest_y: int, rotated: bool) -> void:
	if not is_host():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	# host call_local 不会进这里(没 call_local),但 host 自己也要能 take →
	# 经 _initiate_multi_take 走 rpc_id(1, ...);targeting peer 1 from peer 1 in Godot
	# 会本地调度(同进程内 RPC 不走 net)。sender_id 此时是 0(本机调用)。
	if sender_id == 0:
		sender_id = 1
	var c = get_tree().root.get_node_or_null(NodePath(container_path))
	if c == null or c.contents == null:
		_rpc_take_denied.rpc_id(sender_id, container_path, entry_uid, "容器不存在")
		return
	# 找 entry by uid
	var found_idx: int = -1
	for i in range(c.contents.entries.size()):
		if int(c.contents.entries[i].get("uid", -1)) == entry_uid:
			found_idx = i
			break
	if found_idx < 0:
		_rpc_take_denied.rpc_id(sender_id, container_path, entry_uid, "物品已被他人拿走")
		return
	var entry = c.contents.entries[found_idx]
	var item: ItemData = entry.get("item", null)
	if item == null:
		_rpc_take_denied.rpc_id(sender_id, container_path, entry_uid, "物品资源缺失")
		return
	# 构建 wire entry(给请求方加进背包)
	var entry_wire: Dictionary = {
		"uid": entry_uid,
		"item_path": item.resource_path,
		"x": dest_x,
		"y": dest_y,
		"rotated": rotated,
		"freshness_elapsed": float(entry.get("freshness_elapsed", 0.0)),
	}
	# 从 container 移除
	c.contents.remove_entry(entry)
	# 广播 container entries 更新(所有 peer 看到容器少了这个 entry)
	broadcast_container_entries(container_path, c.serialize_entries())
	# Reply granted 给请求方
	_rpc_take_granted.rpc_id(sender_id, entry_wire, dest_grid_id, dest_x, dest_y, rotated)

# Host → 单个请求方:granted,把物品加进自己背包
@rpc("authority", "reliable")
func _rpc_take_granted(entry_wire: Dictionary, dest_grid_id: String,
		dest_x: int, dest_y: int, rotated: bool) -> void:
	take_granted.emit(entry_wire, dest_grid_id, dest_x, dest_y, rotated)

# Host → 单个请求方:denied,UI 解锁 + toast
@rpc("authority", "reliable")
func _rpc_take_denied(container_path: String, entry_uid: int, reason: String) -> void:
	take_denied.emit(container_path, entry_uid, reason)

# ──────────────────────────────────────────────────────────────
# Phase 2B Q2:Put-back RPC(背包 → 容器)
#   Client 想放回物品 → _rpc_request_put 给 host
#   Host 校验:容器存在 + can_place
#   通过:host 在容器中创建 entry(分配新 uid),broadcast entries 更新,reply granted 给请求方
#   失败:reply denied
# ──────────────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func _rpc_request_put(container_path: String, item_path: String, freshness: float,
		dest_x: int, dest_y: int, rotated: bool, source_inv_x: int, source_inv_y: int) -> void:
	if not is_host():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1
	var c = get_tree().root.get_node_or_null(NodePath(container_path))
	if c == null or c.contents == null:
		_rpc_put_denied.rpc_id(sender_id, item_path, "容器不存在")
		return
	var item: ItemData = load(item_path) as ItemData
	if item == null:
		_rpc_put_denied.rpc_id(sender_id, item_path, "物品资源缺失")
		return
	if not c.contents.can_place(item, dest_x, dest_y, rotated, null):
		_rpc_put_denied.rpc_id(sender_id, item_path, "目标位置不可放")
		return
	# Host 创建 entry(新 uid)
	var gs = get_node_or_null("/root/GameSession")
	var new_uid: int = -1
	if gs != null and gs.has_method("next_entry_uid"):
		new_uid = gs.next_entry_uid()
	var entry: Dictionary = {
		"uid": new_uid,
		"item": item,
		"x": dest_x,
		"y": dest_y,
		"rotated": rotated,
		"freshness_elapsed": freshness,
		"examined": false,  # 容器内 entry 是否 inspected 由 per-peer log 管(放回去,所有 peer 都重新 inspect)
		"inspected": false,
		"inspecting": false,
	}
	if not c.contents.place(entry, dest_x, dest_y):
		_rpc_put_denied.rpc_id(sender_id, item_path, "place 失败")
		return
	# 广播 container entries 更新
	broadcast_container_entries(container_path, c.serialize_entries())
	# Reply granted(请求方从背包移除)
	_rpc_put_granted.rpc_id(sender_id, item_path, source_inv_x, source_inv_y)

@rpc("authority", "reliable")
func _rpc_put_granted(item_path: String, source_inv_x: int, source_inv_y: int) -> void:
	put_granted.emit(item_path, source_inv_x, source_inv_y)

@rpc("authority", "reliable")
func _rpc_put_denied(item_path: String, reason: String) -> void:
	put_denied.emit(item_path, reason)

# ──────────────────────────────────────────────────────────────
# Phase 2B Tier B6:Round end host-authoritative
#   任一 peer 撤离 → host 收到 _rpc_request_extract → 广播 _rpc_apply_round_end
#   timeout 也 host 触发(GameSession.tick host 决定,调 broadcast_round_end_timeout)
#   各 peer 收到 _rpc_apply_round_end:
#     - if local_peer_id == extracted_by → mark + end_round("extracted")(保留 inventory)
#     - else → end_round("timeout")(清 inventory,迷失结算)
# ──────────────────────────────────────────────────────────────

# Client → Host:我撤离成功了
@rpc("any_peer", "reliable")
func _rpc_request_extract(peer_id: int) -> void:
	if not is_host():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1  # host self-call
	# Trust client peer_id == sender_id(简化,Phase 2D 防作弊再校)
	var actual_extracted: int = peer_id if peer_id == sender_id else sender_id
	# 广播:任一 peer 撤离即结束 round
	_rpc_apply_round_end.rpc("extracted", actual_extracted)

# host 在 timeout 时也调,广播给所有 peer(含自己 via call_local)
func broadcast_round_end_timeout() -> void:
	if not is_host():
		return
	# 测试 / mock 模式(无真实 peer):call_local 不触发,直接调
	if multiplayer.multiplayer_peer == null:
		_rpc_apply_round_end("timeout", -1)
	else:
		_rpc_apply_round_end.rpc("timeout", -1)

# Host → All peers 广播:本局结束。
# extracted_by = 撤离者 peer_id;timeout 时 = -1
@rpc("authority", "call_local", "reliable")
func _rpc_apply_round_end(reason: String, extracted_by: int) -> void:
	var gs = get_node_or_null("/root/GameSession")
	if gs == null:
		return
	if not gs.round_active:
		return  # 已结束,幂等
	var my_id: int = get_local_peer_id()
	# Phase 2B Q5 决定 A:谁撤离谁结束;没撤的视为迷失
	if reason == "extracted" and extracted_by == my_id:
		# 我撤了 → 保留 inventory
		gs.mark_extracted_this_round()
		gs.end_round("extracted")
	elif reason == "extracted":
		# 别人撤了 → 我迷失,清 inventory
		gs.end_round("timeout")
	else:
		# reason == "timeout":全员都迷失
		gs.end_round("timeout")

# ---------- 公共 API ----------

func set_local_ready(is_ready: bool) -> void:
	var my_id: int = 1 if mode == Mode.HOST else multiplayer.get_unique_id()
	_rpc_set_ready.rpc(my_id, is_ready)

func start_game() -> void:
	# 只有 host 能调用
	if mode != Mode.HOST:
		return
	if not _all_ready():
		return
	_rpc_start_game.rpc()

func _all_ready() -> bool:
	if players.is_empty():
		return false
	for info in players.values():
		if not bool(info.get("ready", false)):
			return false
	return true

func _recheck_all_ready() -> void:
	all_ready_changed.emit(_all_ready())

func is_host() -> bool:
	return mode == Mode.HOST

func is_client() -> bool:
	return mode == Mode.CLIENT

func is_single() -> bool:
	return mode == Mode.SINGLE

func get_local_peer_id() -> int:
	if mode == Mode.HOST:
		return 1
	if mode == Mode.CLIENT and peer != null:
		return multiplayer.get_unique_id()
	return 0  # single player
