extends Control
# Phase 2A 大厅 — 创建房间 / 加入房间 / 玩家列表 / Ready / 开始游戏
# 代码生成 UI(和 menu.gd 同风格,深色背景 + 居中布局)

const MENU_SCENE := "res://scenes/menu.tscn"

var _mm: Node = null  # MultiplayerManager

# Page 1: 选择面板(创建 / 加入 / 返回)
var _page_select: Control
var _ip_input: LineEdit

# Page 2: 房间面板(玩家列表 + ready + start)
var _page_room: Control
var _player_list_vbox: VBoxContainer
var _ready_btn: Button
var _start_btn: Button
var _status_label: Label

func _ready() -> void:
	_mm = get_node("/root/MultiplayerManager")
	_build_ui()
	_show_page_select()
	# 订阅 MM signal
	_mm.peer_joined.connect(_on_peer_joined)
	_mm.peer_left.connect(_on_peer_left)
	_mm.connection_failed.connect(_on_connection_failed)
	_mm.connected_to_server.connect(_on_connected_to_server)
	_mm.disconnected_from_server.connect(_on_disconnected)
	_mm.all_ready_changed.connect(_on_all_ready_changed)
	_mm.game_started.connect(_on_game_started)

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build_page_select()
	_build_page_room()

func _build_page_select() -> void:
	_page_select = Control.new()
	_page_select.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_page_select)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	vbox.anchor_left = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -220
	vbox.offset_right = 220
	vbox.offset_top = -180
	vbox.offset_bottom = 180
	_page_select.add_child(vbox)

	var title := Label.new()
	title.text = "联机大厅"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "LAN 主机权威 · 最多 3 人"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	var create_btn := Button.new()
	create_btn.text = "创建房间(成为主机)"
	create_btn.custom_minimum_size = Vector2(0, 50)
	create_btn.add_theme_font_size_override("font_size", 20)
	create_btn.pressed.connect(_on_create_room)
	vbox.add_child(create_btn)

	# IP 输入 + 加入
	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 8)
	vbox.add_child(ip_row)

	_ip_input = LineEdit.new()
	_ip_input.placeholder_text = "主机 IP(如 127.0.0.1 或 192.168.x.x)"
	_ip_input.text = "127.0.0.1"
	_ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_input.custom_minimum_size = Vector2(0, 50)
	_ip_input.add_theme_font_size_override("font_size", 16)
	ip_row.add_child(_ip_input)

	var join_btn := Button.new()
	join_btn.text = "加入"
	join_btn.custom_minimum_size = Vector2(100, 50)
	join_btn.add_theme_font_size_override("font_size", 20)
	join_btn.pressed.connect(_on_join_room)
	ip_row.add_child(join_btn)

	var back_btn := Button.new()
	back_btn.text = "← 返回菜单"
	back_btn.custom_minimum_size = Vector2(0, 40)
	back_btn.add_theme_font_size_override("font_size", 16)
	back_btn.pressed.connect(_on_back_to_menu)
	vbox.add_child(back_btn)

func _build_page_room() -> void:
	_page_room = Control.new()
	_page_room.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_page_room)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	vbox.anchor_left = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -240
	vbox.offset_right = 240
	vbox.offset_top = -220
	vbox.offset_bottom = 220
	_page_room.add_child(vbox)

	var title := Label.new()
	title.text = "房间"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status_label)

	var list_panel := PanelContainer.new()
	list_panel.custom_minimum_size = Vector2(0, 200)
	vbox.add_child(list_panel)
	_player_list_vbox = VBoxContainer.new()
	_player_list_vbox.add_theme_constant_override("separation", 6)
	list_panel.add_child(_player_list_vbox)

	_ready_btn = Button.new()
	_ready_btn.text = "准备就绪"
	_ready_btn.toggle_mode = true
	_ready_btn.custom_minimum_size = Vector2(0, 50)
	_ready_btn.add_theme_font_size_override("font_size", 20)
	_ready_btn.toggled.connect(_on_ready_toggled)
	vbox.add_child(_ready_btn)

	_start_btn = Button.new()
	_start_btn.text = "开始游戏(主机)"
	_start_btn.custom_minimum_size = Vector2(0, 50)
	_start_btn.add_theme_font_size_override("font_size", 20)
	_start_btn.disabled = true
	_start_btn.pressed.connect(_on_start_game)
	vbox.add_child(_start_btn)

	var leave_btn := Button.new()
	leave_btn.text = "← 离开房间"
	leave_btn.custom_minimum_size = Vector2(0, 36)
	leave_btn.add_theme_font_size_override("font_size", 14)
	leave_btn.pressed.connect(_on_leave_room)
	vbox.add_child(leave_btn)

# ---- page 切换 ----
func _show_page_select() -> void:
	_page_select.visible = true
	_page_room.visible = false

func _show_page_room() -> void:
	_page_select.visible = false
	_page_room.visible = true
	_refresh_player_list()
	_refresh_room_state()

# ---- 回调 ----
func _on_create_room() -> void:
	var ok: bool = _mm.host_room()
	if not ok:
		_status_label.text = "创建房间失败(端口被占用?)"
		return
	_show_page_room()
	_status_label.text = "已开房 · 端口 12345 · 等待玩家加入"

func _on_join_room() -> void:
	var ip: String = _ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	var ok: bool = _mm.join_room(ip)
	if not ok:
		_status_label.text = "加入失败:IP 格式错"
		return
	_show_page_room()
	_status_label.text = "正在连接 %s..." % ip

func _on_back_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)

func _on_leave_room() -> void:
	_mm.leave_room()
	_show_page_select()

func _on_ready_toggled(pressed: bool) -> void:
	_mm.set_local_ready(pressed)
	_ready_btn.text = "已就绪 ✓" if pressed else "准备就绪"

func _on_start_game() -> void:
	_mm.start_game()

func _on_peer_joined(_id: int, _info: Dictionary) -> void:
	_refresh_player_list()
	_refresh_room_state()

func _on_peer_left(_id: int) -> void:
	_refresh_player_list()
	_refresh_room_state()

func _on_connected_to_server() -> void:
	_status_label.text = "已连接到主机"
	_refresh_player_list()

func _on_connection_failed() -> void:
	_status_label.text = "连接失败"
	_show_page_select()

func _on_disconnected() -> void:
	_status_label.text = "已与主机断开"
	_show_page_select()

func _on_all_ready_changed(all_ready: bool) -> void:
	if _mm.is_host():
		_start_btn.disabled = not all_ready

func _on_game_started() -> void:
	# MM 自己会切场景,这里不重复切
	pass

# ---- 刷新 ----
func _refresh_player_list() -> void:
	for c in _player_list_vbox.get_children():
		c.queue_free()
	for peer_id in _mm.players.keys():
		var info: Dictionary = _mm.players[peer_id]
		var lbl := Label.new()
		var status: String = "✓ 就绪" if info.get("ready", false) else "等待"
		var role: String = "(主机)" if peer_id == 1 else ""
		lbl.text = "  Peer %d  %s  %s  %s" % [peer_id, info.get("name", "?"), role, status]
		lbl.add_theme_font_size_override("font_size", 16)
		_player_list_vbox.add_child(lbl)

func _refresh_room_state() -> void:
	_start_btn.visible = _mm.is_host()
