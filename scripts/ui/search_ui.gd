extends CanvasLayer

const CELL: int = 64
const INSPECT_TIME: float = 1.0

const RARITY_TIME := {
	"Common": 0.6,
	"Uncommon": 1.0,
	"Rare": 1.6,
	"Epic": 2.4,
	"Legendary": 3.5,
}

enum UIState { IDLE, OPENING, LOOTING }

var _state: int = UIState.IDLE

var _container: Node = null
var _player: Node = null
var _bus: Node
var _gs: Node
var _inv: Node

# 单格 inspect 推进
var _inspect_timer: float = 0.0
var _current_inspect_entry: Dictionary = {}
var _current_inspect_time: float = 1.0

func _get_inspect_time(item: ItemData) -> float:
	if item == null:
		return INSPECT_TIME
	return float(RARITY_TIME.get(item.rarity, INSPECT_TIME))

@onready var bg: ColorRect = $Root/Background
@onready var container_panel: GridPanel = $Root/ContainerPanel
@onready var inventory_panel: GridPanel = $Root/InventoryPanel
@onready var help_label: Label = $Root/HelpLabel
@onready var drag_layer: Control = $Root/DragLayer

# 拖拽状态（§3 drag-out 模式）
var _drag: DragState = null

func _ready() -> void:
	visible = false
	_bus = get_node("/root/EventBus")
	_gs = get_node("/root/GameSession")
	_inv = get_node("/root/PlayerInventory")
	# §5 回合结束 → 强制关闭搜刮 UI
	if not _bus.round_ended.is_connected(_on_round_ended_force_close):
		_bus.round_ended.connect(_on_round_ended_force_close)
	# 旧 v3 ProgressBar / 全局 Magnifier 节点 — 隐藏以防可见
	var pb = get_node_or_null("Root/ContainerPanel/SearchProgressBar")
	if pb != null:
		pb.visible = false
	var mg = get_node_or_null("Root/ContainerPanel/Magnifier")
	if mg != null:
		mg.visible = false

func bind_player(p: Node) -> void:
	_player = p

func open_for(c: Node) -> void:
	if c == null:
		return
	_container = c
	c.open()
	visible = true
	if _player != null:
		_player.movement_locked = true
	_gs.set_state("UI_OPEN")
	# Phase 2B:用 LocalInspectLog 作为 source of truth,hydrate entry cache
	# 旧逻辑只补 entry 字段;新逻辑根据 per-peer log 写入 inspected/examined cache
	var lil = get_node_or_null("/root/LocalInspectLog")
	if lil != null and lil.has_method("hydrate_container_entries"):
		lil.hydrate_container_entries(c)
	for e in c.contents.entries:
		# inspecting 总是从 0 开始(运行时状态,不持久化)
		e["inspecting"] = false
		# 兜底:hydrate 已经写过 inspected/examined,这里再防御一遍
		if not e.has("inspected"):
			e["inspected"] = false
		if not e.has("examined"):
			e["examined"] = e.get("inspected", false)
	container_panel.setup(c.contents, "container", c.get_type_name())
	inventory_panel.setup(_inv.grid, "inventory", "背包")
	_connect_panel(container_panel)
	_connect_panel(inventory_panel)
	# 双击信号
	if not container_panel.item_double_clicked.is_connected(_on_item_double_clicked):
		container_panel.item_double_clicked.connect(_on_item_double_clicked)
	if not inventory_panel.item_double_clicked.is_connected(_on_item_double_clicked):
		inventory_panel.item_double_clicked.connect(_on_item_double_clicked)
	# 整理按钮
	if inventory_panel.has_signal("sort_requested"):
		if not inventory_panel.sort_requested.is_connected(_on_sort_requested):
			inventory_panel.sort_requested.connect(_on_sort_requested)
	# 状态转移
	_inspect_timer = 0.0
	_current_inspect_entry = {}
	# Phase 2B:is_searched 改用 per-peer log 计算,不再读 _container.is_searched
	var fully: bool = false
	if lil != null and lil.has_method("is_container_fully_inspected"):
		fully = lil.is_container_fully_inspected(c)
	if fully:
		_state = UIState.IDLE
	else:
		_state = UIState.OPENING
		_advance_to_next_inspect()

func _connect_panel(p: GridPanel) -> void:
	if not p.item_pressed.is_connected(_on_item_pressed):
		p.item_pressed.connect(_on_item_pressed)

func close_ui() -> void:
	_cancel_drag()
	# inspecting 清零,inspected 保留(cache 由 LocalInspectLog 持久)
	if _container != null and is_instance_valid(_container) and _container.contents != null:
		for e in _container.contents.entries:
			e["inspecting"] = false
		# Phase 2B:is_searched 改 per-peer 计算(LocalInspectLog),不再写 _container.is_searched
		# 旧逻辑写 _container.is_searched = true 让"再开"跳过 inspect — 现在 per-peer 化
		# (open_for 进来时已用 lil.is_container_fully_inspected 决定走 IDLE)
	_state = UIState.IDLE
	_current_inspect_entry = {}
	if _container != null and is_instance_valid(_container):
		_container.close()
	visible = false
	if _player != null:
		_player.movement_locked = false
	_gs.set_state("PLAYING")
	_container = null

# ──────────────────────────────────────────────
# 逐个 inspect：按 (y,x) 排序，每个 INSPECT_TIME 秒
# ──────────────────────────────────────────────
func _advance_to_next_inspect() -> void:
	if _container == null or _container.contents == null:
		_state = UIState.IDLE
		return
	# 清零所有 inspecting,然后挑下一个未 inspected
	for e in _container.contents.entries:
		e["inspecting"] = false
	var next: Dictionary = _pick_next_entry()
	if next.is_empty():
		# 全部完成 — Phase 2B:per-peer 的 is_searched 已通过 LocalInspectLog 体现,
		# 这里仍设 _container.is_searched(单人语义保留;多人时无害)
		_state = UIState.IDLE
		_current_inspect_entry = {}
		_container.is_searched = true
		container_panel.refresh()
		_bus.item_examined.emit(null)
		return
	_current_inspect_entry = next
	_current_inspect_time = _get_inspect_time(next["item"])
	next["inspecting"] = true
	_inspect_timer = 0.0
	_state = UIState.LOOTING
	container_panel.refresh()

func _pick_next_entry() -> Dictionary:
	var pending: Array = []
	for e in _container.contents.entries:
		if not e.get("inspected", false):
			pending.append(e)
	if pending.is_empty():
		return {}
	pending.sort_custom(func(a, b):
		if int(a.get("y", 0)) != int(b.get("y", 0)):
			return int(a.get("y", 0)) < int(b.get("y", 0))
		return int(a.get("x", 0)) < int(b.get("x", 0))
	)
	return pending[0]

func _on_item_pressed(entry: Dictionary, panel: GridPanel, button: int) -> void:
	# 只允许 inspected 的物品交互
	if not entry.get("inspected", false):
		return
	# 已在拖拽中：忽略新按下
	if _drag != null:
		return
	if button == MOUSE_BUTTON_LEFT:
		_begin_drag(entry, panel)
	elif button == MOUSE_BUTTON_RIGHT:
		_quick_transfer(entry, panel)

func _on_item_double_clicked(entry: Dictionary, panel: GridPanel) -> void:
	# 双击 = 自动 fit 到对方面板（drag-out 流程）
	if not entry.get("inspected", false):
		return
	if _drag != null:
		return
	var dst: GridPanel = inventory_panel if panel == container_panel else container_panel
	var item: ItemData = entry["item"]
	# 先预探测目标位置（不修改源）
	var fit = GridPlacer.find_first_fit(dst.grid, item)
	if fit == null:
		var v: Control = panel.get_view_for_entry(entry)
		if v != null and is_instance_valid(v):
			_flash_red(v)
		return
	# drag-out: 立即从源移除
	var ds := DragState.begin(entry, panel)
	ds.current_rotated = fit[2]
	if not ds.place_to(dst, fit[0], fit[1]):
		return
	_bus.item_moved.emit(item, ds.from_grid_id, dst.grid_id, fit[0], fit[1], fit[2])
	if ds.from_grid_id == "inventory" or dst.grid_id == "inventory":
		_inv.changed.emit()

func _on_sort_requested() -> void:
	# 整理：按面积降序，clear 再 auto_place
	var entries: Array = []
	for e in inventory_panel.grid.entries:
		entries.append(e)
	entries.sort_custom(func(a, b):
		var ia: ItemData = a["item"]
		var ib: ItemData = b["item"]
		return (ia.grid_w * ia.grid_h) > (ib.grid_w * ib.grid_h)
	)
	# 清空
	for e in entries:
		inventory_panel.remove_entry(e)
	# 重新放置
	for e in entries:
		var fit = GridPlacer.find_first_fit(inventory_panel.grid, e["item"])
		if fit == null:
			continue
		e["rotated"] = fit[2]
		inventory_panel.add_entry_at(e, fit[0], fit[1])
	_inv.changed.emit()

func _begin_drag(entry: Dictionary, panel: GridPanel) -> void:
	# §3 drag-out: 立即从源面板移除（DragState.begin 内部调用 panel.remove_entry）
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
	drag_layer.add_child(_drag.ghost)

func _create_highlight() -> void:
	if _drag == null:
		return
	if _drag.highlight != null:
		_drag.highlight.queue_free()
	_drag.highlight = ColorRect.new()
	_drag.highlight.color = Color("#2ec27e").lerp(Color.TRANSPARENT, 0.6)
	_drag.highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag.highlight.visible = false
	drag_layer.add_child(_drag.highlight)

func _process(delta: float) -> void:
	if not visible:
		return
	# 推进逐个 inspect
	if _state == UIState.LOOTING and not _current_inspect_entry.is_empty():
		_inspect_timer += delta
		if _inspect_timer >= _current_inspect_time:
			_current_inspect_entry["inspected"] = true
			_current_inspect_entry["examined"] = true  # 兼容旧字段
			_current_inspect_entry["inspecting"] = false
			# Phase 2B:写入 LocalInspectLog(source of truth)
			var lil = get_node_or_null("/root/LocalInspectLog")
			if lil != null and _container != null and is_instance_valid(_container):
				var uid: int = int(_current_inspect_entry.get("uid", -1))
				if uid >= 0:
					lil.mark_inspected(String(_container.get_path()), uid)
			_advance_to_next_inspect()
		else:
			container_panel.queue_redraw_overlays()
	if _drag == null:
		return
	var mouse: Vector2 = drag_layer.get_global_mouse_position()
	if _drag.ghost != null and is_instance_valid(_drag.ghost):
		_drag.ghost.global_position = mouse - _drag.ghost.size * 0.5
	_update_drop_highlight(mouse)

func _hovered_panel(_mouse_global: Vector2) -> GridPanel:
	var mouse_global: Vector2 = drag_layer.get_global_mouse_position()
	for p in [container_panel, inventory_panel]:
		var origin: Vector2 = p.grid_origin_global()
		var grid_size := Vector2(p.grid.cols * CELL, p.grid.rows * CELL)
		var rect := Rect2(origin, grid_size)
		if rect.has_point(mouse_global):
			return p
	return null

func _update_drop_highlight(_mouse: Vector2) -> void:
	if _drag == null or _drag.highlight == null:
		return
	var p: GridPanel = _hovered_panel(_mouse)
	if p == null:
		_drag.highlight.visible = false
		return
	var item: ItemData = _drag.item
	var mouse_global: Vector2 = drag_layer.get_global_mouse_position()
	var local: Vector2 = mouse_global - p.grid_origin_global()
	# 智能旋转：先试当前方向；失败试 NOT rotated（drag-out 已移除源，无需 ignore_entry）
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
	# 若任一可放，则切换 ghost 朝向
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
	var c := Color("#2ec27e") if can else Color("#e74c3c")
	c.a = 0.4
	_drag.highlight.color = c

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("cancel"):
		if _drag != null:
			_cancel_drag()
		else:
			close_ui()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact"):
		if _drag != null:
			_cancel_drag()
		close_ui()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("rotate_item") and _drag != null:
		# R 键强制覆盖
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
	var p: GridPanel = _hovered_panel(Vector2.ZERO)
	if p == null:
		# 鼠标在 UI 外松开 → cancel_drag 放回原位
		_cancel_drag()
		return
	var item: ItemData = _drag.item
	var rot: bool = _drag.current_rotated
	var w: int = item.grid_h if rot else item.grid_w
	var h: int = item.grid_w if rot else item.grid_h
	var mouse_global: Vector2 = drag_layer.get_global_mouse_position()
	var local: Vector2 = mouse_global - p.grid_origin_global()
	var cx: int = int(floor(local.x / CELL)) - int(w / 2)
	var cy: int = int(floor(local.y / CELL)) - int(h / 2)
	# §双击防误触:在源 panel 同位置同朝向放下 = 用户没移动鼠标(双击的第一次 release)
	# → 等同放弃这次拖拽,不发 item_moved,避免视觉抖动和 log 噪音
	if p == _drag.from_panel and cx == _drag.original_x and cy == _drag.original_y and rot == _drag.original_rotated:
		_cancel_drag()
		return
	if not p.grid.can_place(item, cx, cy, rot, null):
		# 落点非法 → 放回原位
		_cancel_drag()
		return
	var from_id: String = _drag.from_grid_id
	var to_id: String = p.grid_id
	if not _drag.place_to(p, cx, cy):
		_finish_drag()
		return
	_bus.item_moved.emit(item, from_id, to_id, cx, cy, rot)
	if from_id == "inventory" or to_id == "inventory":
		_inv.changed.emit()
	_finish_drag()

func _cancel_drag() -> void:
	if _drag != null:
		_drag.cancel_drag()
	_finish_drag()

func _finish_drag() -> void:
	if _drag != null:
		_drag.cleanup_visuals()
	_drag = null

func _quick_transfer(entry: Dictionary, panel: GridPanel) -> void:
	# 右键快速转移 → drag-out 流程
	if _drag != null:
		return
	var dst: GridPanel = inventory_panel if panel == container_panel else container_panel
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
	_bus.item_moved.emit(item, ds.from_grid_id, dst.grid_id, fit[0], fit[1], fit[2])
	if ds.from_grid_id == "inventory" or dst.grid_id == "inventory":
		_inv.changed.emit()

func _flash_red(view: Control) -> void:
	view.modulate = Color(1, 0.3, 0.3, 1)
	var tw := create_tween()
	tw.tween_property(view, "modulate", Color(1, 1, 1, 1), 0.3)

func _close() -> void:
	# 别名：供其他模块强制关闭
	if visible:
		close_ui()

func _on_round_ended_force_close(_total: int, _reason: String) -> void:
	# §5 race fix：回合结束强制关闭搜刮 UI
	if visible:
		close_ui()
