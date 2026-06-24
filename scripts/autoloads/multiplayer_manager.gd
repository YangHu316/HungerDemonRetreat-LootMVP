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
signal put_granted(item_path: String, source_inv_x: int, source_inv_y: int, container_path: String, new_entry_uid: int)
signal put_denied(item_path: String, reason: String)
# Phase 2B v2:per-peer 独立 done + 全员 done 后团队订单结算
signal peer_done(peer_id: int, reason: String)            # 任一 peer 结束本局(其他 peer 用于 hide Player_X)
signal team_result_ready(payload: Dictionary)              # 全员 done,订单合计就绪

var mode: int = Mode.SINGLE
var peer: ENetMultiplayerPeer = null
# peer_id → {"name": String, "ready": bool, "color": Color}
var players: Dictionary = {}
var local_name: String = "Player"
# Phase 2B v2:per-peer 本局状态(host 权威维护)
# peer_id → "playing" / "extracted" / "timeout"
# round 开始时 broadcast_round_start 初始化为全 "playing"
var _peer_round_status: Dictionary = {}
# peer_id → Array[String] item resource paths(撤离 peer 上报的背包物品 ResourcePath 列表;timeout 不上报)
var _peer_inventories: Dictionary = {}
# Phase 2B v2:最近一次团队订单结算(home 切场景过来时主动查,以防错过 signal)
var _last_team_result: Dictionary = {}
# Phase 2B v2:host 全局 round timer(host 即使本人撤了,timer 仍 tick;到 0 触发全员 timeout)
# 不依赖 gs.tick(host 本人 gs.round_active=false 会停 tick → 其他 peer 永远不 timeout)
var _global_round_active: bool = false
var _global_round_time_left: float = 0.0

func _ready() -> void:
	# 全局 multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# Phase 2B v2:host 全局 round timer 推进
func _process(delta: float) -> void:
	if not is_host():
		return
	if not _global_round_active:
		return
	_global_round_time_left -= delta
	if _global_round_time_left <= 0.0:
		_global_round_time_left = 0.0
		_global_round_active = false
		broadcast_round_end_timeout()

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
	# Phase 2B v2:reset per-peer round status,所有人 "playing"
	_peer_round_status.clear()
	_peer_inventories.clear()
	_last_team_result.clear()
	# Phase 2B v2:host 启动全局 round timer
	_global_round_time_left = 900.0
	_global_round_active = true
	for pid in players.keys():
		_peer_round_status[int(pid)] = "playing"
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
	# Phase 2B v2:client 也 init _peer_round_status(用于 home 查询其他人状态)
	if not is_host():
		_peer_round_status.clear()
		_peer_inventories.clear()
		_last_team_result.clear()
		for pid in players.keys():
			_peer_round_status[int(pid)] = "playing"
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
	# Phase 2B v2:撤离时收集本地 inventory 物品 path 上报 host(用于团队订单合计)
	var inv_paths: Array = []
	var inv = get_node_or_null("/root/PlayerInventory")
	if inv != null and inv.grid != null:
		for e in inv.grid.entries:
			var item: ItemData = e.get("item", null)
			if item != null and item.resource_path != "":
				inv_paths.append(item.resource_path)
	notify_extracted(peer_id, inv_paths)

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
# Phase 2B fix bug 6:Door 状态全局同步(host 权威)
#   - 任 peer interact door → mm.notify_door_toggle(path)
#   - host 直接广播 _rpc_apply_door_toggle(call_local 自己也跑)
#   - client 走 _rpc_request_door_toggle 转发给 host
#   - 各 peer _rpc_apply_door_toggle → 调 door._apply_toggle_local 同步开/关动画
# ──────────────────────────────────────────────────────────────

func notify_door_toggle(door_path: String) -> void:
	if is_single():
		return
	if is_host():
		_rpc_apply_door_toggle.rpc(door_path)
	else:
		_rpc_request_door_toggle.rpc_id(1, door_path)

@rpc("any_peer", "reliable")
func _rpc_request_door_toggle(door_path: String) -> void:
	if not is_host():
		return
	var d = get_tree().root.get_node_or_null(NodePath(door_path))
	if d == null:
		return
	_rpc_apply_door_toggle.rpc(door_path)

@rpc("authority", "call_local", "reliable")
func _rpc_apply_door_toggle(door_path: String) -> void:
	var d = get_tree().root.get_node_or_null(NodePath(door_path))
	if d != null and d.has_method("_apply_toggle_local"):
		d._apply_toggle_local()

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
		_send_take_denied(sender_id, container_path, entry_uid, "容器不存在")
		return
	# 找 entry by uid
	var found_idx: int = -1
	for i in range(c.contents.entries.size()):
		if int(c.contents.entries[i].get("uid", -1)) == entry_uid:
			found_idx = i
			break
	if found_idx < 0:
		_send_take_denied(sender_id, container_path, entry_uid, "物品已被他人拿走")
		return
	var entry = c.contents.entries[found_idx]
	var item: ItemData = entry.get("item", null)
	if item == null:
		_send_take_denied(sender_id, container_path, entry_uid, "物品资源缺失")
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
	# Reply granted 给请求方(host self → 直接 emit signal,绕开 rpc_id(self) 不触发 bug)
	_send_take_granted(sender_id, entry_wire, dest_grid_id, dest_x, dest_y, rotated)

# Phase 2B fix bug 1:host self-RPC reply helper
# rpc_id(self_id) on @rpc(authority,reliable) without call_local 不在 host 本地触发 →
# host 自己拿/放物品时,_on_take_granted/put_granted 永远不会跑,导致背包没加 entry
# 但 container 已 broadcast 删 entry → host 看到的是错位状态
# Fix:peer_id == local 时直接 emit signal,绕开 rpc 路由
func _send_take_granted(peer_id: int, entry_wire: Dictionary, dest_grid_id: String,
		dest_x: int, dest_y: int, rotated: bool) -> void:
	if peer_id == get_local_peer_id():
		take_granted.emit(entry_wire, dest_grid_id, dest_x, dest_y, rotated)
	else:
		_rpc_take_granted.rpc_id(peer_id, entry_wire, dest_grid_id, dest_x, dest_y, rotated)

func _send_take_denied(peer_id: int, container_path: String, entry_uid: int, reason: String) -> void:
	if peer_id == get_local_peer_id():
		take_denied.emit(container_path, entry_uid, reason)
	else:
		_rpc_take_denied.rpc_id(peer_id, container_path, entry_uid, reason)

func _send_put_granted(peer_id: int, item_path: String, source_inv_x: int, source_inv_y: int,
		container_path: String, new_entry_uid: int) -> void:
	if peer_id == get_local_peer_id():
		put_granted.emit(item_path, source_inv_x, source_inv_y, container_path, new_entry_uid)
	else:
		_rpc_put_granted.rpc_id(peer_id, item_path, source_inv_x, source_inv_y, container_path, new_entry_uid)

func _send_put_denied(peer_id: int, item_path: String, reason: String) -> void:
	if peer_id == get_local_peer_id():
		put_denied.emit(item_path, reason)
	else:
		_rpc_put_denied.rpc_id(peer_id, item_path, reason)

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
		_send_put_denied(sender_id, item_path, "容器不存在")
		return
	var item: ItemData = load(item_path) as ItemData
	if item == null:
		_send_put_denied(sender_id, item_path, "物品资源缺失")
		return
	if not c.contents.can_place(item, dest_x, dest_y, rotated, null):
		_send_put_denied(sender_id, item_path, "目标位置不可放")
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
		_send_put_denied(sender_id, item_path, "place 失败")
		return
	# Phase 2B fix bug 2v2:reply granted FIRST(让 sender 在 entries_synced 之前 mark_inspected)
	# 这样 sender 端 hydrate_container_entries 时,新 uid 已在 log 中 → inspected=true
	# 不会强制 putter 重新 inspect 自己的物品
	_send_put_granted(sender_id, item_path, source_inv_x, source_inv_y, container_path, new_uid)
	# 然后广播 container entries 给所有 peer(其他 peer 看到新物品 → 需 inspect 一次)
	broadcast_container_entries(container_path, c.serialize_entries())

@rpc("authority", "reliable")
func _rpc_put_granted(item_path: String, source_inv_x: int, source_inv_y: int,
		container_path: String, new_entry_uid: int) -> void:
	put_granted.emit(item_path, source_inv_x, source_inv_y, container_path, new_entry_uid)

@rpc("authority", "reliable")
func _rpc_put_denied(item_path: String, reason: String) -> void:
	put_denied.emit(item_path, reason)

# ──────────────────────────────────────────────────────────────
# Phase 2B v2 — Per-peer 独立 done + 全员 done 后团队订单结算
#   流程:
#     1. peer 撤离 → mm.notify_extracted(peer_id, inv_paths) → host
#     2. peer timeout(host 时钟) → host 主动给该 peer 标 "timeout"
#     3. 各 peer 收 _rpc_apply_peer_done(id, reason):
#         本人 → 自己 end_round;其他 peer → emit signal 让 main.gd 隐藏 Player_<id>
#     4. host 检查全员 done → 计算订单合计 → _rpc_apply_team_result 广播
#     5. home 监听 team_result_ready → 显示团队订单 popup + reward
# ──────────────────────────────────────────────────────────────

# 撤离的 peer 调:把自己的 inventory 物品 path 上报给 host
# host: 直接调本地处理。client: rpc_id(1, ...)
func notify_extracted(peer_id: int, inv_paths: Array) -> void:
	if is_single():
		return
	if is_host():
		_rpc_request_peer_done(peer_id, "extracted", inv_paths)
	else:
		_rpc_request_peer_done.rpc_id(1, peer_id, "extracted", inv_paths)

# host 检查全员 done 时调,触发结算广播
func _check_all_done_and_settle() -> void:
	if not is_host():
		return
	for pid in _peer_round_status.keys():
		if String(_peer_round_status[pid]) == "playing":
			return  # 还有人在打
	# 全员 done — 计算订单合计
	var pool = get_node_or_null("/root/OrderPool")
	var payload: Dictionary = {
		"per_peer_status": _peer_round_status.duplicate(),
		"order_describe": "",
		"required": 0,
		"capped": 0,
		"matched": 0,
		"ratio": 0.0,
		"reward_total": 0,
		"reward_per_peer": 0,
	}
	if pool != null and pool.has_active():
		var active = pool.get_active()
		# 收集所有撤离 peer 的物品(timeout peer 不贡献)
		var all_items: Array = []
		for pid in _peer_inventories.keys():
			var paths: Array = _peer_inventories[pid]
			for p in paths:
				var item: ItemData = load(String(p)) as ItemData
				if item != null:
					all_items.append(item)
		var r: Dictionary = active.completion_for(all_items)
		payload["order_describe"] = active.describe()
		payload["required"] = int(r.get("required", 0))
		payload["capped"] = int(r.get("capped", 0))
		payload["matched"] = int(r.get("matched", 0))
		payload["ratio"] = float(r.get("ratio", 0.0))
		var reward_total: int = int(round(active.reward_base * float(r.get("ratio", 0.0))))
		var n: int = max(1, _peer_round_status.size())
		payload["reward_total"] = reward_total
		payload["reward_per_peer"] = int(reward_total / n)
	# 广播
	if multiplayer.multiplayer_peer == null:
		_rpc_apply_team_result(payload)
	else:
		_rpc_apply_team_result.rpc(payload)
	# Phase 2B fix bug 4:round 结束后重置所有 peer 的 ready 状态(host 权威)
	# 让下一局必须重新点 ready 才能开始,且 home 加载时按钮初始 disabled 状态正确
	if multiplayer.multiplayer_peer == null:
		_rpc_reset_all_ready()
	else:
		_rpc_reset_all_ready.rpc()

# Client → Host:我结束本局了(reason=extracted/timeout),附背包物品 path
@rpc("any_peer", "reliable")
func _rpc_request_peer_done(peer_id: int, reason: String, inv_paths: Array) -> void:
	if not is_host():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1
	# Trust sender 提供的 peer_id == 自己
	var actual_id: int = peer_id if peer_id == sender_id else sender_id
	if not _peer_round_status.has(actual_id):
		return  # 不在 round 内,丢弃
	if String(_peer_round_status[actual_id]) != "playing":
		return  # 已 done,幂等
	_peer_round_status[actual_id] = reason
	if reason == "extracted":
		_peer_inventories[actual_id] = inv_paths
	# 广播 "X 结束了" 给所有 peer
	if multiplayer.multiplayer_peer == null:
		_rpc_apply_peer_done(actual_id, reason)
	else:
		_rpc_apply_peer_done.rpc(actual_id, reason)
	# 检查全员 done
	_check_all_done_and_settle()

# Host → All peers:peer X 结束本局
# 各 peer:
#   - 本人 X → 自己 end_round(单人式)
#   - 其他人 → emit signal,main.gd hide 对应 Player 节点
@rpc("authority", "call_local", "reliable")
func _rpc_apply_peer_done(peer_id: int, reason: String) -> void:
	# 所有 peer 都更新本地 _peer_round_status(用于 home 查询)
	_peer_round_status[peer_id] = reason
	var my_id: int = get_local_peer_id()
	if peer_id == my_id:
		var gs = get_node_or_null("/root/GameSession")
		if gs != null and gs.round_active:
			if reason == "extracted":
				gs.mark_extracted_this_round()
				gs.end_round("extracted")
			else:
				gs.end_round("timeout")
	else:
		# 其他 peer 结束 → 通知 main 隐藏对应 Player
		peer_done.emit(peer_id, reason)

# Host → All peers:全员 done,团队订单结算 payload
@rpc("authority", "call_local", "reliable")
func _rpc_apply_team_result(payload: Dictionary) -> void:
	_last_team_result = payload
	team_result_ready.emit(payload)

# Phase 2B fix bug 4:round 结束后所有 peer ready 状态重置
# 否则上一局的 ready=true 残留 → home 重新加载时 _all_ready 已 true → all_ready_changed
# 不会再触发 → host 的"开始下一局"按钮永远 disabled,无法开下一局
@rpc("authority", "call_local", "reliable")
func _rpc_reset_all_ready() -> void:
	for pid in players.keys():
		players[pid]["ready"] = false
	# 本地 ready 状态变(false)→ 通知 UI
	local_ready_changed.emit(false)
	# 全员 ready 状态变(应为 false)→ 通知 host UI 更新按钮
	_recheck_all_ready()

# Host tick timeout 时调:对所有 status="playing" 的 peer 标记 timeout 并广播
func broadcast_round_end_timeout() -> void:
	if not is_host():
		return
	for pid in _peer_round_status.keys():
		var pid_int: int = int(pid)
		if String(_peer_round_status[pid_int]) != "playing":
			continue
		_peer_round_status[pid_int] = "timeout"
		# 广播给所有 peer
		if multiplayer.multiplayer_peer == null:
			_rpc_apply_peer_done(pid_int, "timeout")
		else:
			_rpc_apply_peer_done.rpc(pid_int, "timeout")
	# 全员 timeout → 触发结算
	_check_all_done_and_settle()

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
