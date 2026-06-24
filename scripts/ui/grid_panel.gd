extends Control
class_name GridPanel


# Chinese font for CJK display support
var _chinese_font: Font

const CELL: int = 64
const DOUBLE_CLICK_MS: int = 300

@export var title_text: String = "背包"
@export var grid_id: String = "inventory"

var grid: GridInventory
var item_views: Dictionary = {}  # int uid -> GridItemView
# 给 entry 分配稳定 uid 用作 item_views 的 key。
# 不能直接用 entry Dictionary 作 key —— Godot 4 Dictionary key 用 content hash,
# entry 的 x/y/rotated 在拖拽中会变,导致 hash 不一致、has/erase 失效,旧 view 不被
# free → 屏幕累积"幽灵 view",肉眼看像物品被复制(2026-06-22 用户报"4个面包")。
const _UID_KEY := "_grid_uid"
var _uid_counter: int = 0

func _entry_uid(entry: Dictionary) -> int:
	if not entry.has(_UID_KEY):
		_uid_counter += 1
		entry[_UID_KEY] = _uid_counter
	return int(entry[_UID_KEY])
var _bg: Control
var _items_container: Control
var _overlay: Control  # 用于绘制 inspecting 的放大镜+圆环
var _title_label: Label
var _value_label: Label
var _sort_button: Button

# 双击检测
var _last_click_entry: Dictionary = {}
var _last_click_ms: int = 0

# 用于驱动 _overlay 自绘动画
var _anim_time: float = 0.0
# 食物 freshness 边框定时重绘累计(每秒刷一次即可,降档分钟级)
var _fresh_redraw_accum: float = 0.0

signal item_pressed(entry: Dictionary, panel: GridPanel, button: int)
signal item_double_clicked(entry: Dictionary, panel: GridPanel)
signal item_hovered(entry: Dictionary, panel: GridPanel, view: Control)
signal item_unhovered(entry: Dictionary, panel: GridPanel)
signal sort_requested

func setup(g: GridInventory, gid: String, title: String) -> void:
	grid = g
	grid_id = gid
	title_text = title
	_build()
	call_deferred("_refresh")

func _build() -> void:
	for c in get_children():
		c.queue_free()
	item_views.clear()
	var W: int = grid.cols * CELL
	var H: int = grid.rows * CELL
	custom_minimum_size = Vector2(W + 20, H + 90)
	_title_label = Label.new()
	_title_label.text = title_text
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.position = Vector2(0, 0)
	add_child(_title_label)
	# 仅 inventory 显示 "整理" 按钮
	if grid_id == "inventory":
		_sort_button = Button.new()
		_sort_button.text = "整理"
		_sort_button.position = Vector2(W - 80, 0)
		_sort_button.size = Vector2(80, 32)
		_sort_button.add_theme_font_size_override("font_size", 16)
		_sort_button.pressed.connect(_on_sort_pressed)
		add_child(_sort_button)
	_bg = Control.new()
	_bg.name = "GridBG"
	_bg.position = Vector2(0, 36)
	_bg.size = Vector2(W, H)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_bg.draw.connect(_draw_bg)
	add_child(_bg)
	_items_container = Control.new()
	_items_container.name = "Items"
	_items_container.position = Vector2(0, 36)
	_items_container.size = Vector2(W, H)
	_items_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_items_container)
	# overlay 用来绘制 inspecting 进度环+放大镜（叠在物品上方）
	_overlay = Control.new()
	_overlay.name = "InspectOverlay"
	_overlay.position = Vector2(0, 36)
	_overlay.size = Vector2(W, H)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_value_label = Label.new()
	_value_label.add_theme_font_size_override("font_size", 18)
	_value_label.position = Vector2(0, 36 + H + 4)
	add_child(_value_label)

func _draw_bg() -> void:
	var W: int = grid.cols * CELL
	var H: int = grid.rows * CELL
	_bg.draw_rect(Rect2(Vector2.ZERO, Vector2(W, H)), Color("#1a1c22"))
	var line := Color("#3a3d45")
	for x in grid.cols + 1:
		_bg.draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, H), line, 1.0)
	for y in grid.rows + 1:
		_bg.draw_line(Vector2(0, y * CELL), Vector2(W, y * CELL), line, 1.0)

func _process(delta: float) -> void:
	_anim_time += delta
	# setup() 还没被调用前 grid 是 null —— 直接退出,避免后续访问 grid.entries 炸
	if grid == null:
		return
	# 仅在有 inspecting 时重绘 overlay
	for e in grid.entries:
		if e.get("inspecting", false):
			_overlay.queue_redraw()
			break
	# 每秒刷一次 freshness 边框 + value label(背包格才动,仓库不变质所以也只是浪费一次绘制)
	_fresh_redraw_accum += delta
	if _fresh_redraw_accum >= 1.0:
		_fresh_redraw_accum = 0.0
		for v in item_views.values():
			if is_instance_valid(v):
				v.queue_redraw()
		_update_value_label()

func _draw_overlay() -> void:
	if grid == null:
		return
	for e in grid.entries:
		if not e.get("inspecting", false):
			continue
		var item: ItemData = e["item"]
		var rotated: bool = e.get("rotated", false)
		var w: int = item.grid_h if rotated else item.grid_w
		var h: int = item.grid_w if rotated else item.grid_h
		var rect := Rect2(Vector2(e["x"] * CELL, e["y"] * CELL), Vector2(w * CELL, h * CELL))
		var center: Vector2 = rect.position + rect.size * 0.5
		# 1) 暗化背景
		_overlay.draw_rect(rect, Color(0, 0, 0, 0.45))
		var radius: float = min(rect.size.x, rect.size.y) * 0.35
		# 2) 放大镜沿圆周平移（仅画小镜片+镜柄，无任何圆环/背景圆/进度弧）
		var angle: float = _anim_time * TAU * 0.6
		var lens_off := Vector2(cos(angle), sin(angle)) * (radius * 0.5)
		var lens_center: Vector2 = center + lens_off
		_overlay.draw_arc(lens_center, radius * 0.18, 0, TAU, 16, Color.WHITE, 2.0)
		var dir := Vector2(1, 1).normalized()
		_overlay.draw_line(lens_center + dir * (radius * 0.18), lens_center + dir * (radius * 0.4), Color.WHITE, 2.5)

func _find_search_ui() -> Node:
	# 沿 parent 链向上找 search_ui CanvasLayer
	var n: Node = self
	while n != null:
		if n.has_method("_advance_to_next_inspect"):
			return n
		n = n.get_parent()
	return null

func _refresh() -> void:
	for v in item_views.values():
		if is_instance_valid(v):
			v.queue_free()
	item_views.clear()
	for entry in grid.entries:
		_add_item_view(entry)
	_update_value_label()
	_overlay.queue_redraw()

func _add_item_view(entry: Dictionary) -> void:
	var view_script = load("res://scripts/ui/grid_item.gd")
	var view = view_script.new()
	view.position = Vector2(entry["x"] * CELL, entry["y"] * CELL)
	view.setup(entry)
	view.gui_input.connect(_on_view_input.bind(entry, view))
	view.mouse_entered.connect(_on_view_mouse_entered.bind(entry, view))
	view.mouse_exited.connect(_on_view_mouse_exited.bind(entry))
	_items_container.add_child(view)
	item_views[_entry_uid(entry)] = view

func _on_view_input(event: InputEvent, entry: Dictionary, _view: Control) -> void:
	if event is InputEventMouseButton and event.pressed:
		var btn: int = (event as InputEventMouseButton).button_index
		# Phase 2B fix bug 1v3:左键双击拾取删除(用户报多人下双击 race condition 导致 ghost 残留)
		# 改成纯单击拖拽 + 右键快速转。双击不再 emit signal。
		# (home.gd / search_ui.gd 仍可订阅 item_double_clicked,但不会再触发)
		item_pressed.emit(entry, self, btn)

func _on_view_mouse_entered(entry: Dictionary, view: Control) -> void:
	item_hovered.emit(entry, self, view)

func _on_view_mouse_exited(entry: Dictionary) -> void:
	item_unhovered.emit(entry, self)

func _on_sort_pressed() -> void:
	sort_requested.emit()

func _update_value_label() -> void:
	if grid == null or _value_label == null:
		return
	var sum: int = 0
	for e in grid.entries:
		if e.get("inspected", false) or e.get("examined", false):
			sum += Freshness.entry_value(e)
	_value_label.text = "价值: %d" % sum

func refresh() -> void:
	_refresh()

func queue_redraw_overlays() -> void:
	if _overlay != null:
		_overlay.queue_redraw()

func cell_at_local(local_pos: Vector2) -> Vector2i:
	var p: Vector2 = local_pos - _bg.position
	var cx: int = int(floor(p.x / CELL))
	var cy: int = int(floor(p.y / CELL))
	return Vector2i(cx, cy)

func grid_origin_global() -> Vector2:
	return _bg.global_position

func get_view_for_entry(entry: Dictionary) -> Control:
	# 外部访问入口:用 entry 的稳定 uid 查 view。不要直接读 item_views[entry] —— 那会
	# 因为 Dictionary content-hash 陷阱在 entry mutate 后失效(见 _entry_uid 注释)。
	if entry == null or not entry.has(_UID_KEY):
		return null
	return item_views.get(int(entry[_UID_KEY]), null)

func add_entry_at(entry: Dictionary, x: int, y: int) -> bool:
	if grid.place(entry, x, y):
		# 防视觉孤儿:同 grid 内 place 时,旧 view 还在 _items_container,必须先 free
		var uid: int = _entry_uid(entry)
		if item_views.has(uid):
			var old: Control = item_views[uid]
			if is_instance_valid(old):
				old.queue_free()
			item_views.erase(uid)
		_add_item_view(entry)
		_update_value_label()
		return true
	return false

func remove_entry(entry: Dictionary) -> void:
	grid.remove_entry(entry)
	var uid: int = _entry_uid(entry)
	if item_views.has(uid):
		var v = item_views[uid]
		if is_instance_valid(v):
			v.queue_free()
		item_views.erase(uid)
	# 注意:这里**不能**清 _last_click_entry —— 否则破坏双击拾取
	# (双击场景:click 1 触发 drag-out → remove_entry → 若清记录则 click 2 不识别)
	_update_value_label()
