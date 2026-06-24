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

# Phase 2B Tier B5:多人 take 等 host 确认时的状态(_drag 已被释放,ghost 锁定显示)
var _pending_take: Dictionary = {}  # 空 → 无 pending;非空 → 等 host reply

# Phase 2B helpers
func _is_single() -> bool:
	var mm = get_node_or_null("/root/MultiplayerManager")
	return mm == null or (mm.has_method("is_single") and mm.is_single())

func _is_multiplayer() -> bool:
	return not _is_single()

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
	# Phase 2B Tier B5:订阅 MM take 回调
	var mm = get_node_or_null("/root/MultiplayerManager")
	if mm != null:
		if mm.has_signal("take_granted") and not mm.take_granted.is_connected(_on_take_granted):
			mm.take_granted.connect(_on_take_granted)
		if mm.has_signal("take_denied") and not mm.take_denied.is_connected(_on_take_denied):
			mm.take_denied.connect(_on_take_denied)
		# Phase 2B Q2:put_granted/denied
		if mm.has_signal("put_granted") and not mm.put_granted.is_connected(_on_put_granted):
			mm.put_granted.connect(_on_put_granted)
		if mm.has_signal("put_denied") and not mm.put_denied.is_connected(_on_put_denied):
			mm.put_denied.connect(_on_put_denied)

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
	# Phase 2B Q1 fix:订阅 entries_synced,host 广播容器内容更新时实时刷新 UI
	if c.has_signal("entries_synced") and not c.entries_synced.is_connected(_on_container_entries_synced):
		c.entries_synced.connect(_on_container_entries_synced)
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
	# Phase 2B Q1:断开 entries_synced 监听
	if _container != null and is_instance_valid(_container):
		if _container.has_signal("entries_synced") and _container.entries_synced.is_connected(_on_container_entries_synced):
			_container.entries_synced.disconnect(_on_container_entries_synced)
		_container.close()
	visible = false
	if _player != null:
		_player.movement_locked = false
	_gs.set_state("PLAYING")
	_container = null

# Phase 2B Q1 fix:host 广播容器内容更新时,实时刷新 UI
# 触发场景:其他 peer 拿走/放回了物品(host RPC 同步给所有 peer)
func _on_container_entries_synced() -> void:
	if _container == null or not is_instance_valid(_container):
		return
	# Re-hydrate inspect cache(可能新加了 entry — put 后)
	var lil = get_node_or_null("/root/LocalInspectLog")
	if lil != null and lil.has_method("hydrate_container_entries"):
		lil.hydrate_container_entries(_container)
	# 重新 setup container panel(用新 contents)
	container_panel.setup(_container.contents, "container", _container.get_type_name())
	# 当前 inspecting 的 entry 如果被拿走 → entry 失效,重启 inspect
	if not _current_inspect_entry.is_empty():
		var still_in: bool = false
		var current_uid: int = int(_current_inspect_entry.get("uid", -1))
		for e in _container.contents.entries:
			if int(e.get("uid", -1)) == current_uid:
				still_in = true
				break
		if not still_in:
			# inspecting entry 被他人拿走,重新 advance
			_inspect_timer = 0.0
			_current_inspect_entry = {}
			_advance_to_next_inspect()
			return  # 已 advance,不再继续 IDLE 检测
	# Phase 2B fix bug 2:_state IDLE(已搜完旧 entries)但 entries_synced 后有新 uninspected entry
	# (其他 peer 放回物品 → 新 uid 不在本地 log → hydrate 后 inspected=false)
	# → 需要重启 inspect 循环,否则 B 端永远看不到放回物品的搜刮动画
	if _state == UIState.IDLE:
		var has_uninspected: bool = false
		for e in _container.contents.entries:
			if not e.get("inspected", false):
				has_uninspected = true
				break
		if has_uninspected:
			_state = UIState.OPENING
			_inspect_timer = 0.0
			_current_inspect_entry = {}
			_advance_to_next_inspect()
			return
	# 取消 pending take 视觉(如果当前 entries 已无该 uid)
	if not _pending_take.is_empty():
		var p_uid: int = int(_pending_take.get("uid", -1))
		var still: bool = false
		for e in _container.contents.entries:
			if int(e.get("uid", -1)) == p_uid:
				still = true
				break
		# entry 被移除 = host granted 了我们的 request,_on_take_granted 会清 pending
		# 这里不动,留给 take_granted/denied signal 清理

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
	# Phase 2B fix bug 1v3:等 host RPC 回复时(_pending_take 非空),禁止新拖拽 / 快速转
	# 否则前次 pending 的 ghost / source 引用被新动作覆盖,残留 view + 旧 take_granted ignored
	if not _pending_take.is_empty():
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
	if not _pending_take.is_empty():
		return  # 等 host 回复中,忽略新操作
	var dst: GridPanel = inventory_panel if panel == container_panel else container_panel
	var item: ItemData = entry["item"]
	# 先预探测目标位置（不修改源）
	var fit = GridPlacer.find_first_fit(dst.grid, item)
	if fit == null:
		var v: Control = panel.get_view_for_entry(entry)
		if v != null and is_instance_valid(v):
			_flash_red(v)
		return
	# Phase 2B Tier B5:多人 container → inventory 走 RPC
	if _is_multiplayer() and panel == container_panel and dst == inventory_panel:
		# 用 no_remove 模拟一个临时 ds 来记录 source(给 _initiate_multi_take 用),
		# 然后把 ghost/highlight 也建好
		_drag = DragState.begin_no_remove(entry, panel)
		_dim_source_view(entry, panel)
		_drag.current_rotated = fit[2]
		_create_ghost()
		_create_highlight()
		_initiate_multi_take(dst, fit[0], fit[1], fit[2])
		return
	# Phase 2B Q2:多人 inventory → container 走 put RPC
	if _is_multiplayer() and panel == inventory_panel and dst == container_panel:
		_drag = DragState.begin_no_remove(entry, panel)
		_dim_source_view(entry, panel)
		_drag.current_rotated = fit[2]
		_create_ghost()
		_create_highlight()
		_initiate_multi_put(dst, fit[0], fit[1], fit[2])
		return
	# 单人 / 多人 inventory↔inventory:旧路径
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
	# Phase 2B Tier B5 + Q2:多人 → 总是 no_remove(不管 source)
	# 这样:
	#   container→inventory 走 take RPC(_initiate_multi_take)
	#   inventory→container 走 put RPC(_initiate_multi_put)
	#   inventory→inventory(整理)走 manual 路径(_try_drop 内手动 remove+add)
	# 单人 → 旧 DragState.begin(立即从源移除)
	if _is_multiplayer():
		_drag = DragState.begin_no_remove(entry, panel)
		_dim_source_view(entry, panel)
	else:
		_drag = DragState.begin(entry, panel)
	_create_ghost()
	_create_highlight()

func _dim_source_view(entry: Dictionary, panel: GridPanel) -> void:
	# 多人 take 时,源 view 半透明示意"占位中等 host"
	var view = panel.get_view_for_entry(entry)
	if view != null and is_instance_valid(view):
		view.modulate = Color(0.5, 0.5, 0.5, 0.6)

func _restore_source_view(entry: Dictionary, panel: GridPanel) -> void:
	var view = panel.get_view_for_entry(entry)
	if view != null and is_instance_valid(view):
		view.modulate = Color(1, 1, 1, 1)

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
	# 落点合法性校验:no_remove 模式下源还在,需 ignore 自身防止 can_place 误判
	var ignore = _drag.entry if _drag.is_no_remove else null
	if not p.grid.can_place(item, cx, cy, rot, ignore):
		# 落点非法 → 放回原位
		_cancel_drag()
		return
	var from_id: String = _drag.from_grid_id
	var to_id: String = p.grid_id
	# Phase 2B Tier B5:多人 container → inventory 走 RPC(保守:等 host 回复)
	if _is_multiplayer() and from_id == "container" and to_id == "inventory":
		_initiate_multi_take(p, cx, cy, rot)
		return
	# Phase 2B Q2:多人 inventory → container 走 put RPC(对称)
	if _is_multiplayer() and from_id == "inventory" and to_id == "container":
		_initiate_multi_put(p, cx, cy, rot)
		return
	# Phase 2B 多人 inventory → inventory(整理):本地处理(per-player 背包)
	# _drag 是 no_remove,源还在 grid,需手动 remove + add
	if _is_multiplayer() and from_id == "inventory" and to_id == "inventory":
		_drag.from_panel.remove_entry(_drag.entry)
		_drag.entry["rotated"] = rot
		if not p.add_entry_at(_drag.entry, cx, cy):
			# 失败:回滚到原位
			_drag.entry["rotated"] = _drag.original_rotated
			_drag.from_panel.add_entry_at(_drag.entry, _drag.original_x, _drag.original_y)
		else:
			_bus.item_moved.emit(item, from_id, to_id, cx, cy, rot)
			_inv.changed.emit()
		_finish_drag()
		return
	# 单人:旧路径
	if not _drag.place_to(p, cx, cy):
		_finish_drag()
		return
	_bus.item_moved.emit(item, from_id, to_id, cx, cy, rot)
	if from_id == "inventory" or to_id == "inventory":
		_inv.changed.emit()
	_finish_drag()

# Phase 2B Q2:多人 inventory → container put 入口
func _initiate_multi_put(dest_panel: GridPanel, cx: int, cy: int, rot: bool) -> void:
	var mm = get_node_or_null("/root/MultiplayerManager")
	if mm == null or _container == null or _drag == null:
		_cancel_drag()
		return
	var entry: Dictionary = _drag.entry
	var item: ItemData = entry.get("item", null)
	if item == null:
		_cancel_drag()
		return
	var c_path: String = String(_container.get_path())
	var src_x: int = _drag.original_x
	var src_y: int = _drag.original_y
	var freshness: float = float(entry.get("freshness_elapsed", 0.0))
	var item_path: String = item.resource_path
	# 锁 ghost 显示"等待中"
	if _drag.ghost != null and is_instance_valid(_drag.ghost):
		_drag.ghost.modulate = Color(1, 1, 1, 0.35)
	if _drag.highlight != null and is_instance_valid(_drag.highlight):
		_drag.highlight.color = Color(0.85, 0.6, 0.6, 0.35)
	# Phase 2B fix bug 5:**必须 BEFORE mm.request_put** 完整设置 _pending_take(同 _initiate_multi_take)
	_pending_take = {
		"is_put": true,
		"uid": -1,  # put 不需要 uid(host 会分配新的)
		"item_path": item_path,
		"container_path": c_path,
		"source_entry": entry,
		"source_panel": _drag.from_panel,
		"source_inv_x": src_x,
		"source_inv_y": src_y,
		"dest_x": cx,
		"dest_y": cy,
		"rotated": rot,
		"ghost": _drag.ghost,
		"highlight": _drag.highlight,
	}
	_drag.ghost = null
	_drag.highlight = null
	_drag = null
	# 发 put RPC(host 自己同步触发 put_granted,_pending_take 已就绪可被清掉)
	if mm.has_method("request_put"):
		mm.request_put(c_path, item_path, freshness, cx, cy, rot, src_x, src_y)

# Phase 2B Tier B5:多人 take 入口
# _drag 是 no_remove DragState;ghost 已显示,这里发 RPC 给 host
func _initiate_multi_take(dest_panel: GridPanel, cx: int, cy: int, rot: bool) -> void:
	var mm = get_node_or_null("/root/MultiplayerManager")
	if mm == null or _container == null or _drag == null:
		_cancel_drag()
		return
	var entry: Dictionary = _drag.entry
	var uid: int = int(entry.get("uid", -1))
	if uid < 0:
		_cancel_drag()
		return
	var c_path: String = String(_container.get_path())
	# 锁 ghost 显示"等待中"
	if _drag.ghost != null and is_instance_valid(_drag.ghost):
		_drag.ghost.modulate = Color(1, 1, 1, 0.35)
	if _drag.highlight != null and is_instance_valid(_drag.highlight):
		_drag.highlight.color = Color(0.6, 0.6, 0.85, 0.35)
	# Phase 2B fix bug 5:**必须 BEFORE mm.request_take** 完整设置 _pending_take(含 ghost/highlight)
	# 因为 host 自取时 request_take 同步触发 take_granted → _on_take_granted → _clear_pending_take_visuals
	# 把 _pending_take 重置为新空 dict {}。之后再写 ghost/highlight 就是写到新 dict → 永远清不掉
	# (导致 ghost 卡左上角 + _pending_take 永远非空 → _on_item_pressed 守卫挡住所有新拾取)
	_pending_take = {
		"uid": uid,
		"container_path": c_path,
		"dest_grid_id": dest_panel.grid_id,
		"dest_x": cx,
		"dest_y": cy,
		"rotated": rot,
		"source_entry": entry,
		"source_panel": _drag.from_panel,
		"ghost": _drag.ghost,
		"highlight": _drag.highlight,
	}
	# 释放 _drag 视觉引用(防 _finish_drag 双 free)
	_drag.ghost = null
	_drag.highlight = null
	_drag = null
	# 现在才发 RPC — _pending_take 已就绪,host 自取的同步 take_granted 能正确清理
	if mm.has_method("request_take"):
		mm.request_take(c_path, uid, dest_panel.grid_id, cx, cy, rot)

func _on_take_granted(entry_wire: Dictionary, dest_grid_id: String, dest_x: int, dest_y: int, rotated: bool) -> void:
	# host 同意 take:request 方收到,把 entry 加进自己背包(容器 entries 由 host broadcast 已同步更新)
	if _pending_take.is_empty():
		return
	# 校验 uid 对应
	if int(entry_wire.get("uid", -2)) != int(_pending_take.get("uid", -1)):
		# 不是当前 pending,忽略
		return
	# Reconstruct entry on inventory side
	var item_path: String = String(entry_wire.get("item_path", ""))
	var item: ItemData = null
	if item_path != "":
		item = load(item_path) as ItemData
	if item == null:
		_clear_pending_take_visuals()
		return
	# 找目标 panel(应是 inventory_panel)
	var dst: GridPanel = null
	if dest_grid_id == "inventory":
		dst = inventory_panel
	if dst == null:
		_clear_pending_take_visuals()
		return
	var entry := {
		"uid": int(entry_wire.get("uid", -1)),
		"item": item,
		"x": dest_x,
		"y": dest_y,
		"rotated": rotated,
		"freshness_elapsed": float(entry_wire.get("freshness_elapsed", 0.0)),
		"inspected": true,  # 拿到手就已识别(背包物品默认揭示)
		"examined": true,
		"inspecting": false,
	}
	if not dst.add_entry_at(entry, dest_x, dest_y):
		# 罕见:目标位置同时被自己其他动作占了。fallback first-fit
		var fit = GridPlacer.find_first_fit(dst.grid, item)
		if fit != null:
			entry["rotated"] = fit[2]
			dst.add_entry_at(entry, fit[0], fit[1])
	_inv.changed.emit()
	_clear_pending_take_visuals()

func _on_take_denied(container_path: String, entry_uid: int, reason: String) -> void:
	if _pending_take.is_empty():
		return
	if int(_pending_take.get("uid", -1)) != entry_uid:
		return
	# 恢复源 view 透明度(no_remove 模式下源没动,只是 dim 了)
	var src_panel: GridPanel = _pending_take.get("source_panel", null)
	var src_entry: Dictionary = _pending_take.get("source_entry", {})
	if src_panel != null and is_instance_valid(src_panel) and not src_entry.is_empty():
		_restore_source_view(src_entry, src_panel)
	_clear_pending_take_visuals()
	_show_toast("拿取失败:%s" % reason)

# Phase 2B Q2:put granted — host 已把物品加进容器,客户端从背包移除
# Phase 2B fix bug 2v2:host 在 reply 时附带 container_path + new_entry_uid,
# putter 立即 mark_inspected(避免自己重新搜刮自己刚放进去的物品)
func _on_put_granted(item_path: String, source_inv_x: int, source_inv_y: int,
		container_path: String, new_entry_uid: int) -> void:
	if _pending_take.is_empty():
		return
	if not _pending_take.get("is_put", false):
		return
	if String(_pending_take.get("item_path", "")) != item_path:
		return
	if int(_pending_take.get("source_inv_x", -1)) != source_inv_x:
		return
	if int(_pending_take.get("source_inv_y", -1)) != source_inv_y:
		return
	# 从本地 inventory 移除源 entry(no_remove 模式没移除)
	var src_entry: Dictionary = _pending_take.get("source_entry", {})
	if not src_entry.is_empty():
		inventory_panel.remove_entry(src_entry)
	_inv.changed.emit()
	# Phase 2B fix bug 2v2:把放回的新 uid 标 inspected(我已经认识这个物品了,不用再 inspect)
	# 顺序:_send_put_granted 先发,broadcast_container_entries 后发 — 此 mark 早于 hydrate
	if new_entry_uid >= 0 and container_path != "":
		var lil = get_node_or_null("/root/LocalInspectLog")
		if lil != null and lil.has_method("mark_inspected"):
			lil.mark_inspected(container_path, new_entry_uid)
	_clear_pending_take_visuals()

func _on_put_denied(item_path: String, reason: String) -> void:
	if _pending_take.is_empty():
		return
	if not _pending_take.get("is_put", false):
		return
	if String(_pending_take.get("item_path", "")) != item_path:
		return
	# 恢复源 view modulate(源没移除,只是 dim)
	var src_panel: GridPanel = _pending_take.get("source_panel", null)
	var src_entry: Dictionary = _pending_take.get("source_entry", {})
	if src_panel != null and is_instance_valid(src_panel) and not src_entry.is_empty():
		_restore_source_view(src_entry, src_panel)
	_clear_pending_take_visuals()
	_show_toast("放回失败:%s" % reason)

func _clear_pending_take_visuals() -> void:
	# 释放 ghost / highlight
	var g = _pending_take.get("ghost", null)
	if g != null and is_instance_valid(g):
		g.queue_free()
	var hl = _pending_take.get("highlight", null)
	if hl != null and is_instance_valid(hl):
		hl.queue_free()
	# 恢复源 view modulate(granted 时源 entry 已被 host RPC 移除,view 也被 grid_panel 清掉)
	var src_panel: GridPanel = _pending_take.get("source_panel", null)
	var src_entry: Dictionary = _pending_take.get("source_entry", {})
	if src_panel != null and is_instance_valid(src_panel) and not src_entry.is_empty():
		_restore_source_view(src_entry, src_panel)
	_pending_take = {}

func _show_toast(msg: String) -> void:
	# 简易 toast — 控制台 + 1.5s Label
	push_warning("[take] " + msg)
	if help_label != null:
		var orig_text: String = help_label.text
		help_label.text = msg
		var tw := create_tween()
		tw.tween_interval(1.5)
		tw.tween_callback(func():
			if help_label != null:
				help_label.text = orig_text
		)

func _cancel_drag() -> void:
	if _drag != null:
		# Phase 2B fix bug 1v3:多人 no_remove 模式下,_begin_drag 调了 _dim_source_view
		# (modulate 0.5),取消时必须 _restore_source_view 还原,否则源 view 灰底残留
		if _drag.is_no_remove and _drag.from_panel != null and is_instance_valid(_drag.from_panel):
			_restore_source_view(_drag.entry, _drag.from_panel)
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
	if not _pending_take.is_empty():
		return
	var dst: GridPanel = inventory_panel if panel == container_panel else container_panel
	var item: ItemData = entry["item"]
	var fit = GridPlacer.find_first_fit(dst.grid, item)
	if fit == null:
		var v: Control = panel.get_view_for_entry(entry)
		if v != null and is_instance_valid(v):
			_flash_red(v)
		return
	# Phase 2B Tier B5:多人 container → inventory 走 RPC
	if _is_multiplayer() and panel == container_panel and dst == inventory_panel:
		_drag = DragState.begin_no_remove(entry, panel)
		_dim_source_view(entry, panel)
		_drag.current_rotated = fit[2]
		_create_ghost()
		_create_highlight()
		_initiate_multi_take(dst, fit[0], fit[1], fit[2])
		return
	# Phase 2B Q2:多人 inventory → container 走 put RPC
	if _is_multiplayer() and panel == inventory_panel and dst == container_panel:
		_drag = DragState.begin_no_remove(entry, panel)
		_dim_source_view(entry, panel)
		_drag.current_rotated = fit[2]
		_create_ghost()
		_create_highlight()
		_initiate_multi_put(dst, fit[0], fit[1], fit[2])
		return
	# 单人 / 多人 inventory↔inventory:旧路径
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
