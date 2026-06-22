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
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_back_to_menu() -> void:
	# 切回主菜单 — 不清 stash/inventory(玩家的存档保留)
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
