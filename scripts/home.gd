extends Control

# §九 主页面:网格化背包 + 网格化仓库
# 交互方式与战局 search_ui 完全一致:
# - 左键拖动:drag-out 模式(按下立即从源移除,ghost 跟随鼠标,松开落到目标)
# - 双击:自动 fit 到对方面板
# - 右键:同双击(快速转移)
# - R 键:拖拽中旋转
# - ESC:取消拖拽 / 释放选中

const GRID_PANEL_SCRIPT = preload("res://scripts/ui/grid_panel.gd")
const CELL: int = 64

var _inv_panel: GridPanel
var _stash_panel: GridPanel
var _drag_layer: Control
var _drag: DragState = null
var _active_label: Label
var _candidate_label: Label
var _accept_btn: Button
var _refresh_btn: Button

# Phase 2B Tier B7:多人 ready 流(home → 下一把)
var _enter_btn: Button = null              # 共用按钮(单人:进入战局;多人:开始下一局/等 host)
var _ready_toggle: CheckBox = null         # 多人 ready 开关(单人时隐藏)
var _mp_player_list: VBoxContainer = null  # 多人玩家列表(显示各人 ready 状态)
var _mp_status_label: Label = null         # 多人状态提示(等 host / 全员 ready 等)
var _mp_panel: PanelContainer = null       # Q4:浮动 panel,单人时整体隐藏

func _ready() -> void:
	_build_ui()
	var stash = get_node("/root/Stash")
	var inv = get_node("/root/PlayerInventory")
	var pool = get_node("/root/OrderPool")
	if not stash.changed.is_connected(_refresh_stash):
		stash.changed.connect(_refresh_stash)
	if not inv.changed.is_connected(_refresh_inv):
		inv.changed.connect(_refresh_inv)
	if not pool.candidate_changed.is_connected(_refresh_orders):
		pool.candidate_changed.connect(_refresh_orders)
	if not pool.active_changed.is_connected(_refresh_orders):
		pool.active_changed.connect(_refresh_orders)
	_refresh_orders()
	# Phase 2B Tier B7:多人 ready 流接线
	_setup_multiplayer_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.11, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 30
	vbox.offset_right = -30
	vbox.offset_top = 24
	vbox.offset_bottom = -24
	vbox.add_theme_constant_override("separation", 16)
	add_child(vbox)

	var title := Label.new()
	title.text = "家 — 饿魔退散!外卖侠     [左键拖 / 双击自动到对面 / 右键快速转 / R 旋转]"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	# 右上角"返回主菜单"按钮(锚定在屏幕右上)
	var menu_btn := Button.new()
	menu_btn.text = "← 主菜单"
	menu_btn.add_theme_font_size_override("font_size", 14)
	menu_btn.anchor_left = 1.0
	menu_btn.anchor_right = 1.0
	menu_btn.offset_left = -120
	menu_btn.offset_right = -16
	menu_btn.offset_top = 16
	menu_btn.offset_bottom = 44
	menu_btn.pressed.connect(_on_back_to_menu)
	add_child(menu_btn)

	# 订单区(在标题和网格之间)
	var order_hbox := HBoxContainer.new()
	order_hbox.add_theme_constant_override("separation", 24)
	order_hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var active_panel := PanelContainer.new()
	active_panel.custom_minimum_size = Vector2(360, 60)
	var active_inner := VBoxContainer.new()
	active_panel.add_child(active_inner)
	var active_title := Label.new()
	active_title.text = "🎯 当前订单"
	active_title.add_theme_font_size_override("font_size", 14)
	active_title.modulate = Color(0.9, 0.85, 0.5)
	active_inner.add_child(active_title)
	_active_label = Label.new()
	_active_label.add_theme_font_size_override("font_size", 16)
	active_inner.add_child(_active_label)
	order_hbox.add_child(active_panel)

	var candidate_panel := PanelContainer.new()
	candidate_panel.custom_minimum_size = Vector2(360, 60)
	var candidate_inner := VBoxContainer.new()
	candidate_panel.add_child(candidate_inner)
	var cand_title := Label.new()
	cand_title.text = "📝 候选订单"
	cand_title.add_theme_font_size_override("font_size", 14)
	cand_title.modulate = Color(0.7, 0.85, 1.0)
	candidate_inner.add_child(cand_title)
	_candidate_label = Label.new()
	_candidate_label.add_theme_font_size_override("font_size", 16)
	candidate_inner.add_child(_candidate_label)
	var cand_btn_row := HBoxContainer.new()
	_accept_btn = Button.new()
	_accept_btn.text = "接单"
	_accept_btn.pressed.connect(_on_accept_order)
	cand_btn_row.add_child(_accept_btn)
	_refresh_btn = Button.new()
	_refresh_btn.text = "刷新"
	_refresh_btn.pressed.connect(_on_refresh_candidate)
	cand_btn_row.add_child(_refresh_btn)
	candidate_inner.add_child(cand_btn_row)
	order_hbox.add_child(candidate_panel)

	vbox.add_child(order_hbox)

	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 60)
	vbox.add_child(hbox)

	# 左:背包(grid_id="inventory" 有整理按钮)
	var inv = get_node("/root/PlayerInventory")
	_inv_panel = GRID_PANEL_SCRIPT.new()
	_inv_panel.setup(inv.grid, "inventory", "背包(下一局会带进去)")
	hbox.add_child(_inv_panel)
	_wire_panel(_inv_panel)

	# 右:仓库
	var stash = get_node("/root/Stash")
	_stash_panel = GRID_PANEL_SCRIPT.new()
	_stash_panel.setup(stash.grid, "stash", "仓库(安全)")
	hbox.add_child(_stash_panel)
	_wire_panel(_stash_panel)

	var enter_btn := Button.new()
	enter_btn.text = "进入战局"
	enter_btn.custom_minimum_size = Vector2(0, 56)
	enter_btn.add_theme_font_size_override("font_size", 22)
	enter_btn.pressed.connect(_on_enter)
	vbox.add_child(enter_btn)
	_enter_btn = enter_btn

	# Phase 2B Tier B7 + Q4 fix:多人 ready 流 UI 用浮动 PanelContainer
	# (anchored 屏幕右上,下方紧挨"主菜单"按钮)— 不挤占主 vbox,任何分辨率都看得见
	var mp_panel := PanelContainer.new()
	mp_panel.anchor_left = 1.0
	mp_panel.anchor_right = 1.0
	mp_panel.offset_left = -340
	mp_panel.offset_right = -16
	mp_panel.offset_top = 56
	mp_panel.offset_bottom = 280
	add_child(mp_panel)
	# 白底带边框
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.16, 0.92)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.95, 0.85, 0.4, 0.5)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	mp_panel.add_theme_stylebox_override("panel", sb)

	var mp_vbox := VBoxContainer.new()
	mp_vbox.add_theme_constant_override("separation", 10)
	mp_panel.add_child(mp_vbox)

	var mp_title := Label.new()
	mp_title.text = "🌐 联机准备"
	mp_title.add_theme_font_size_override("font_size", 16)
	mp_title.modulate = Color(0.95, 0.85, 0.4)
	mp_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mp_vbox.add_child(mp_title)

	_ready_toggle = CheckBox.new()
	_ready_toggle.text = "✓ 准备就绪"
	_ready_toggle.add_theme_font_size_override("font_size", 18)
	_ready_toggle.toggled.connect(_on_ready_toggled)
	mp_vbox.add_child(_ready_toggle)

	var list_title := Label.new()
	list_title.text = "玩家列表"
	list_title.add_theme_font_size_override("font_size", 13)
	list_title.modulate = Color(0.7, 0.85, 1.0)
	mp_vbox.add_child(list_title)

	_mp_player_list = VBoxContainer.new()
	mp_vbox.add_child(_mp_player_list)

	_mp_status_label = Label.new()
	_mp_status_label.add_theme_font_size_override("font_size", 13)
	_mp_status_label.modulate = Color(0.85, 0.85, 0.5)
	_mp_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mp_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mp_vbox.add_child(_mp_status_label)
	# 单人模式下整个 mp_panel 隐藏(_setup_multiplayer_ui 处理)
	mp_panel.visible = false  # 默认隐藏,_setup_multiplayer_ui 多人时打开
	_mp_panel = mp_panel

	# DragLayer 在最上面,放 ghost 和 highlight
	_drag_layer = Control.new()
	_drag_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_drag_layer)

func _wire_panel(p: GridPanel) -> void:
	p.item_pressed.connect(_on_item_pressed)
	p.item_double_clicked.connect(_on_item_double_clicked)
	if p.has_signal("sort_requested"):
		p.sort_requested.connect(_on_sort_requested.bind(p))

# ---- 信号回调 ----
func _on_item_pressed(entry: Dictionary, panel: GridPanel, button: int) -> void:
	if _drag != null:
		return
	if button == MOUSE_BUTTON_LEFT:
		_begin_drag(entry, panel)
	elif button == MOUSE_BUTTON_RIGHT:
		_quick_transfer(entry, panel)

func _on_item_double_clicked(entry: Dictionary, panel: GridPanel) -> void:
	if _drag != null:
		return
	_quick_transfer(entry, panel)

func _on_sort_requested(panel: GridPanel) -> void:
	# 整理:按面积降序重新放置。**整理失败必须回滚**,绝不能丢 entry。
	var entries: Array = panel.grid.entries.duplicate()
	# 备份原位置/朝向
	var backup: Array = []
	for e in entries:
		backup.append({
			"entry": e,
			"x": int(e.get("x", 0)),
			"y": int(e.get("y", 0)),
			"rotated": bool(e.get("rotated", false)),
		})
	entries.sort_custom(func(a, b):
		var ia: ItemData = a["item"]
		var ib: ItemData = b["item"]
		return (ia.grid_w * ia.grid_h) > (ib.grid_w * ib.grid_h)
	)
	# 全部 remove
	for e in entries:
		panel.remove_entry(e)
	# 试着重新放
	var placed_count: int = 0
	for e in entries:
		var fit = GridPlacer.find_first_fit(panel.grid, e["item"])
		if fit == null:
			break  # 一旦失败立刻停 + 回滚,绝不跳过(否则 entry 永久丢失)
		e["rotated"] = fit[2]
		panel.add_entry_at(e, fit[0], fit[1])
		placed_count += 1
	# 如果有任何 entry 没放下,回滚到原状态
	if placed_count != entries.size():
		for e in panel.grid.entries.duplicate():
			panel.remove_entry(e)
		for b in backup:
			var e: Dictionary = b["entry"]
			e["rotated"] = b["rotated"]
			panel.add_entry_at(e, b["x"], b["y"])
	_post_change_emit(panel)

# ---- 快速转移(双击 / 右键)----
func _quick_transfer(entry: Dictionary, panel: GridPanel) -> void:
	var dst: GridPanel = _stash_panel if panel == _inv_panel else _inv_panel
	var item: ItemData = entry["item"]
	var fit = GridPlacer.find_first_fit(dst.grid, item)
	if fit == null:
		var v: Control = panel.get_view_for_entry(entry)
		if v != null and is_instance_valid(v):
			_flash_red(v)
		return
	var ds := DragState.begin(entry, panel)
	ds.current_rotated = fit[2]
	if not ds.place_to(dst, fit[0], fit[1]):
		return
	_post_change_emit(panel)
	_post_change_emit(dst)

# ---- 拖拽流程 ----
func _begin_drag(entry: Dictionary, panel: GridPanel) -> void:
	_drag = DragState.begin(entry, panel)
	_create_ghost()
	_create_highlight()

func _create_ghost() -> void:
	if _drag == null:
		return
	if _drag.ghost != null:
		_drag.ghost.queue_free()
	var view_script = load("res://scripts/ui/grid_item.gd")
	_drag.ghost = view_script.new()
	var e: Dictionary = _drag.entry.duplicate()
	e["rotated"] = _drag.current_rotated
	e["inspected"] = true
	e["examined"] = true
	_drag.ghost.setup(e)
	_drag.ghost.modulate = Color(1, 1, 1, 0.6)
	_drag.ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_layer.add_child(_drag.ghost)

func _create_highlight() -> void:
	if _drag == null:
		return
	if _drag.highlight != null:
		_drag.highlight.queue_free()
	_drag.highlight = ColorRect.new()
	_drag.highlight.color = Color("#2ec27e").lerp(Color.TRANSPARENT, 0.6)
	_drag.highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag.highlight.visible = false
	_drag_layer.add_child(_drag.highlight)

func _process(_delta: float) -> void:
	if _drag == null:
		return
	var mouse: Vector2 = _drag_layer.get_global_mouse_position()
	if _drag.ghost != null and is_instance_valid(_drag.ghost):
		_drag.ghost.global_position = mouse - _drag.ghost.size * 0.5
	_update_drop_highlight()

func _hovered_panel() -> GridPanel:
	var mouse_global: Vector2 = _drag_layer.get_global_mouse_position()
	for p in [_inv_panel, _stash_panel]:
		var origin: Vector2 = p.grid_origin_global()
		var grid_size := Vector2(p.grid.cols * CELL, p.grid.rows * CELL)
		var rect := Rect2(origin, grid_size)
		if rect.has_point(mouse_global):
			return p
	return null

func _update_drop_highlight() -> void:
	if _drag == null or _drag.highlight == null:
		return
	var p: GridPanel = _hovered_panel()
	if p == null:
		_drag.highlight.visible = false
		return
	var item: ItemData = _drag.item
	var mouse_global: Vector2 = _drag_layer.get_global_mouse_position()
	var local: Vector2 = mouse_global - p.grid_origin_global()
	# 智能旋转 fallback
	var primary_rot: bool = _drag.current_rotated
	var alt_rot: bool = not _drag.current_rotated
	var picked_rot: bool = primary_rot
	var picked_can: bool = false
	for try_rot in [primary_rot, alt_rot]:
		var w_t: int = item.grid_h if try_rot else item.grid_w
		var h_t: int = item.grid_w if try_rot else item.grid_h
		var cx_t: int = int(floor(local.x / CELL)) - int(w_t / 2)
		var cy_t: int = int(floor(local.y / CELL)) - int(h_t / 2)
		if p.grid.can_place(item, cx_t, cy_t, try_rot, null):
			picked_rot = try_rot
			picked_can = true
			break
	if picked_can and picked_rot != _drag.current_rotated:
		_drag.current_rotated = picked_rot
		var e := _drag.entry.duplicate()
		e["rotated"] = _drag.current_rotated
		e["inspected"] = true
		e["examined"] = true
		if _drag.ghost != null and is_instance_valid(_drag.ghost):
			_drag.ghost.setup(e)
	var w: int = item.grid_h if _drag.current_rotated else item.grid_w
	var h: int = item.grid_w if _drag.current_rotated else item.grid_h
	var cx: int = int(floor(local.x / CELL)) - int(w / 2)
	var cy: int = int(floor(local.y / CELL)) - int(h / 2)
	var can: bool = p.grid.can_place(item, cx, cy, _drag.current_rotated, null)
	_drag.highlight.visible = true
	_drag.highlight.position = p.grid_origin_global() + Vector2(cx * CELL, cy * CELL)
	_drag.highlight.size = Vector2(w * CELL, h * CELL)
	var col := Color("#2ec27e") if can else Color("#e74c3c")
	col.a = 0.4
	_drag.highlight.color = col

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		if _drag != null:
			_cancel_drag()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("rotate_item") and _drag != null:
		_drag.current_rotated = not _drag.current_rotated
		var e := _drag.entry.duplicate()
		e["rotated"] = _drag.current_rotated
		e["inspected"] = true
		e["examined"] = true
		if _drag.ghost != null and is_instance_valid(_drag.ghost):
			_drag.ghost.setup(e)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and _drag != null:
			_try_drop()

func _try_drop() -> void:
	if _drag == null:
		return
	var p: GridPanel = _hovered_panel()
	if p == null:
		_cancel_drag()
		return
	var item: ItemData = _drag.item
	var rot: bool = _drag.current_rotated
	var w: int = item.grid_h if rot else item.grid_w
	var h: int = item.grid_w if rot else item.grid_h
	var mouse_global: Vector2 = _drag_layer.get_global_mouse_position()
	var local: Vector2 = mouse_global - p.grid_origin_global()
	var cx: int = int(floor(local.x / CELL)) - int(w / 2)
	var cy: int = int(floor(local.y / CELL)) - int(h / 2)
	# §双击防误触:在源 panel 同位置同朝向放下 = 没真正拖动(双击第一次 release)
	# → 放回原位、不 emit changed,避免视觉抖动 + 与双击逻辑叠加产生"伪复制"感
	if p == _drag.from_panel and cx == _drag.original_x and cy == _drag.original_y and rot == _drag.original_rotated:
		_cancel_drag()
		return
	if not p.grid.can_place(item, cx, cy, rot, null):
		_cancel_drag()
		return
	var src_panel: GridPanel = _drag.from_panel
	if not _drag.place_to(p, cx, cy):
		_finish_drag()
		return
	_post_change_emit(src_panel)
	if p != src_panel:
		_post_change_emit(p)
	_finish_drag()

func _cancel_drag() -> void:
	if _drag != null:
		var src_panel: GridPanel = _drag.from_panel
		_drag.cancel_drag()
		_post_change_emit(src_panel)
	_finish_drag()

func _finish_drag() -> void:
	if _drag != null:
		_drag.cleanup_visuals()
	_drag = null

# ---- 数据同步 ----
func _post_change_emit(panel: GridPanel) -> void:
	# 转移完毕,emit changed signal + stash 落盘 + UI 刷新
	if panel.grid_id == "inventory":
		var inv = get_node("/root/PlayerInventory")
		inv.changed.emit()
	elif panel.grid_id == "stash":
		var stash = get_node("/root/Stash")
		stash.save()
		stash.changed.emit()

func _refresh_inv() -> void:
	if _inv_panel != null:
		_inv_panel.refresh()

func _refresh_stash() -> void:
	if _stash_panel != null:
		_stash_panel.refresh()

func _flash_red(view: Control) -> void:
	view.modulate = Color(1, 0.3, 0.3, 1)
	var tw := create_tween()
	tw.tween_property(view, "modulate", Color(1, 1, 1, 1), 0.3)

func _on_enter() -> void:
	# Phase 2B Tier B7:多人模式下,host 才能调 mm.start_game(全员 ready 时);
	# client 此按钮被隐藏(只能 ready),实际不会进这里
	var mm = get_node_or_null("/root/MultiplayerManager")
	if mm == null or (mm.has_method("is_single") and mm.is_single()):
		# 单人:旧行为
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		return
	# 多人 host:调 mm.start_game(MM 内部 _all_ready 校验 + RPC 广播 _rpc_start_game)
	if mm.is_host():
		mm.start_game()
		# 注意:mm._rpc_start_game 自动 change_scene_to_file("main.tscn"),host 也通过 call_local 走

func _on_back_to_menu() -> void:
	# 切回主菜单 — 不清 stash/inventory(玩家的存档保留)
	# Phase 2B:多人也不主动 leave_room,让用户手动决定
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _on_accept_order() -> void:
	var pool = get_node("/root/OrderPool")
	pool.accept_candidate()

func _on_refresh_candidate() -> void:
	var pool = get_node("/root/OrderPool")
	pool.refresh_candidate()

func _refresh_orders() -> void:
	var pool = get_node("/root/OrderPool")
	var active = pool.get_active()
	if active != null:
		_active_label.text = "%s    (报酬基数 %d)" % [active.describe(), active.reward_base]
	else:
		_active_label.text = "(无,从右侧候选选一个接单)"
	var cand = pool.get_candidate()
	if cand != null:
		_candidate_label.text = "%s    (报酬基数 %d)" % [cand.describe(), cand.reward_base]
	else:
		_candidate_label.text = "(空)"
	# 已有 active 时禁用接单按钮
	_accept_btn.disabled = (active != null) or (cand == null)

# ──────────────────────────────────────────────────────────────
# Phase 2B Tier B7:多人 ready 流
# ──────────────────────────────────────────────────────────────

func _setup_multiplayer_ui() -> void:
	var mm = get_node_or_null("/root/MultiplayerManager")
	if mm == null or (mm.has_method("is_single") and mm.is_single()):
		# 单人:整个 mp_panel 隐藏
		if _mp_panel != null:
			_mp_panel.visible = false
		return
	# 多人:显示 mp_panel + 订阅 mm 信号 + 初始化 UI
	if _mp_panel != null:
		_mp_panel.visible = true
	if mm.has_signal("peer_joined") and not mm.peer_joined.is_connected(_mp_on_peer_changed):
		mm.peer_joined.connect(_mp_on_peer_changed)
	if mm.has_signal("peer_left") and not mm.peer_left.is_connected(_mp_on_peer_left):
		mm.peer_left.connect(_mp_on_peer_left)
	if mm.has_signal("all_ready_changed") and not mm.all_ready_changed.is_connected(_mp_on_all_ready):
		mm.all_ready_changed.connect(_mp_on_all_ready)
	if mm.has_signal("game_started") and not mm.game_started.is_connected(_mp_on_game_started):
		mm.game_started.connect(_mp_on_game_started)
	# Phase 2B v2:订阅 peer_done(刷新等待状态)+ team_result_ready(弹结算 popup)
	if mm.has_signal("peer_done") and not mm.peer_done.is_connected(_mp_on_peer_done_in_home):
		mm.peer_done.connect(_mp_on_peer_done_in_home)
	if mm.has_signal("team_result_ready") and not mm.team_result_ready.is_connected(_mp_on_team_result):
		mm.team_result_ready.connect(_mp_on_team_result)
	# host 看到"开始下一局"按钮(默认 disabled,等全员 ready)
	# client 看到"等待 host 开局",enter_btn 隐藏
	if mm.is_host():
		_enter_btn.text = "开始下一局(等待全员 ready)"
		_enter_btn.disabled = true
	else:
		_enter_btn.visible = false
	# Phase 2B fix bug 4:home 重新加载时 mm.players 可能已有 ready 状态(上局残留 / reset 后等)
	# 必须根据当前 _all_ready 设置 enter_btn 初始状态(否则 signal 不会再触发)
	# 同时 ready_toggle 反映本地 player 当前 ready 状态
	var my_id: int = mm.get_local_peer_id()
	if mm.players.has(my_id) and _ready_toggle != null:
		_ready_toggle.button_pressed = bool(mm.players[my_id].get("ready", false))
	if mm.is_host():
		_mp_on_all_ready(mm._all_ready())  # 用当前状态初始化按钮(防 signal 错过)
	_mp_refresh_player_list()
	_mp_refresh_status()
	# Phase 2B v2:进 home 时检查是否有未结束的 round / 已就绪的 team result
	_mp_refresh_round_state()
	# 主动查 _last_team_result(home 是切场景过来,可能 signal 已过)
	if not mm._last_team_result.is_empty():
		_mp_on_team_result(mm._last_team_result)

func _on_ready_toggled(pressed: bool) -> void:
	var mm = get_node_or_null("/root/MultiplayerManager")
	if mm == null or (mm.has_method("is_single") and mm.is_single()):
		return
	mm.set_local_ready(pressed)

func _mp_on_peer_changed(_id: int, _info: Dictionary) -> void:
	_mp_refresh_player_list()
	_mp_refresh_status()

func _mp_on_peer_left(_id: int) -> void:
	_mp_refresh_player_list()
	_mp_refresh_status()

func _mp_on_all_ready(all_ready: bool) -> void:
	_mp_refresh_player_list()
	var mm = get_node_or_null("/root/MultiplayerManager")
	if mm == null or _enter_btn == null:
		return
	if mm.is_host():
		_enter_btn.disabled = not all_ready
		_enter_btn.text = "开始下一局" if all_ready else "开始下一局(等待全员 ready)"
	if _mp_status_label != null:
		_mp_status_label.text = "全员就绪 — host 可开始" if all_ready else "等待全员 ready..."

func _mp_on_game_started() -> void:
	# host 触发的 _rpc_start_game 已 change_scene_to_file("main.tscn"),
	# 这里再一次防御(如果 home 没接到 _rpc_start_game 的 call_local,手动跳)
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _mp_refresh_player_list() -> void:
	if _mp_player_list == null:
		return
	for c in _mp_player_list.get_children():
		c.queue_free()
	var mm = get_node_or_null("/root/MultiplayerManager")
	if mm == null:
		return
	var ids: Array = mm.players.keys()
	ids.sort()
	for pid in ids:
		var info: Dictionary = mm.players[pid]
		var lbl := Label.new()
		var ready_mark: String = "✓" if bool(info.get("ready", false)) else "·"
		var name_str: String = String(info.get("name", "Player%d" % pid))
		lbl.text = "%s [%d] %s" % [ready_mark, pid, name_str]
		lbl.modulate = Color(0.5, 1.0, 0.5) if bool(info.get("ready", false)) else Color(0.85, 0.85, 0.85)
		_mp_player_list.add_child(lbl)

func _mp_refresh_status() -> void:
	if _mp_status_label == null:
		return
	var mm = get_node_or_null("/root/MultiplayerManager")
	if mm == null:
		return
	if mm.is_host():
		_mp_status_label.text = "等待全员 ready..."
	else:
		_mp_status_label.text = "等待 host 开始下一局..."

# ──────────────────────────────────────────────────────────────
# Phase 2B v2:home 等待状态 + 团队订单结算 popup
# ──────────────────────────────────────────────────────────────

func _is_round_in_progress() -> bool:
	var mm = get_node_or_null("/root/MultiplayerManager")
	if mm == null or mm.is_single():
		return false
	if mm._peer_round_status.is_empty():
		return false
	for pid in mm._peer_round_status.keys():
		if String(mm._peer_round_status[pid]) == "playing":
			return true
	return false

func _mp_refresh_round_state() -> void:
	# 如果 round 还在进行(其他 peer 还在打)→ disable ready toggle / enter button + 显示等待
	if _ready_toggle == null or _enter_btn == null:
		return
	if _is_round_in_progress():
		_ready_toggle.disabled = true
		_ready_toggle.tooltip_text = "等待其他玩家结束本局"
		_enter_btn.disabled = true
		if _mp_status_label != null:
			_mp_status_label.text = "🕐 等待其他玩家结束本局..."
	else:
		_ready_toggle.disabled = false
		_ready_toggle.tooltip_text = ""
		# enter_btn 状态由 _mp_on_all_ready 控制
		_mp_refresh_status()

func _mp_on_peer_done_in_home(_peer_id: int, _reason: String) -> void:
	# 其他 peer done 时刷新等待状态
	_mp_refresh_round_state()

func _mp_on_team_result(payload: Dictionary) -> void:
	# 全员 done,弹团队订单结算 popup
	_show_team_result_popup(payload)
	_mp_refresh_round_state()

func _show_team_result_popup(payload: Dictionary) -> void:
	# 用 AcceptDialog 简洁展示
	var dlg := AcceptDialog.new()
	dlg.title = "🎯 团队订单结算"
	var describe: String = String(payload.get("order_describe", "(无订单)"))
	var required: int = int(payload.get("required", 0))
	var capped: int = int(payload.get("capped", 0))
	var ratio: float = float(payload.get("ratio", 0.0))
	var reward_per_peer: int = int(payload.get("reward_per_peer", 0))
	var reward_total: int = int(payload.get("reward_total", 0))
	var per_peer_status: Dictionary = payload.get("per_peer_status", {})
	# 各 peer 状态摘要
	var status_lines: Array = []
	for pid in per_peer_status.keys():
		var s: String = String(per_peer_status[pid])
		var icon: String = "✅" if s == "extracted" else "❌"
		status_lines.append("  %s peer %d: %s" % [icon, int(pid), s])
	var msg: String = "%s\n\n📦 合计:%d / %d  (完成度 %.0f%%)\n💰 总报酬:%d\n👥 你分到:%d\n\n各人状态:\n%s" % [
		describe, capped, required, ratio * 100.0, reward_total, reward_per_peer,
		"\n".join(status_lines)
	]
	dlg.dialog_text = msg
	dlg.set_anchors_preset(Control.PRESET_CENTER)
	add_child(dlg)
	dlg.popup_centered(Vector2i(480, 400))
	# 关掉 popup 时:把 reward 加到本机 stash(简单方案;Phase 2C 再细化)+ 清 mm 缓存
	dlg.confirmed.connect(func():
		var stash = get_node_or_null("/root/Stash")
		if stash != null and stash.has_method("add_money"):
			stash.add_money(reward_per_peer)
		# 清 active order(本局已结算)
		var pool = get_node_or_null("/root/OrderPool")
		if pool != null:
			pool.clear_active()
		var mm = get_node_or_null("/root/MultiplayerManager")
		if mm != null:
			mm._last_team_result.clear()
		dlg.queue_free()
	)
