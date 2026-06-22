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
