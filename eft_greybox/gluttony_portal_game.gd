extends Node2D
## 🌀 暴食传送门 · 外卖叠叠乐 — Godot 白盒复现（2D 网格）
## 严格遵循《策划文件/小游戏策划案/饿魔退散外卖侠-小游戏-暴食传送门.md》：
##   5×6 临时背包 · 传送门逐件掉落(仅⚪🟢🔵) · 俄罗斯方块移动/旋转/软降/硬降
##   · 同稀有度正交相邻→自动合成升级并从顶部重新下落(可连锁) · 🟡封顶
##   · N 件全落定不溢出→入可搜刮容器(胜利) · 溢出→撕裂(巨响+散落一地)→限时抢救/逃
## 灰盒：方块/合成/溢出抢救逻辑为重点；无settle沉降(见README)、无精细美术音效。

# ---------------- 可配置参数（§五 · 起调值，需手调）----------------
@export var drop_count := 14          # 每局掉落固定数量 N（仅⚪🟢🔵）
@export var fall_interval := 0.55     # 每格下落间隔（秒）；软降加速
@export var salvage_window := 7.0     # 撕裂后抢救窗口/敌人ETA（秒）
@export var garbage_rate := 0.18      # 变质堵块出现概率（取值掉落前掷，不占用 N）
@export var max_garbage := 5          # 每局变质堵块上限

# ---------------- 接入大地图 ----------------
signal finished(result: Dictionary)   # 胜利(入容器)或抢救结束时发出 → 主循环收回控制
## standalone=true：沙盒模式，自动开始（仅 F5 调试）。
## false（默认，接大地图）：等宿主调用 begin() 才开始（本玩法是 2D UI 面板，宿主在交互时显示它）。
@export var standalone := false

# ---------------- 美术替换槽（2D：留空=纯色块占位）----------------
@export_group("美术替换槽")
@export var food_textures: Dictionary = {}   # 稀有度(int 0~5) → Texture2D，替换方块贴图
@export var portal_texture: Texture2D         # 传送门贴图
@export_group("")

# ---------------- 常量 ----------------
const COLS := 5
const ROWS := 6
const CELL := 64.0
const GRID_X := 416.0
const GRID_Y := 140.0

const COMMON := 0
const QUALITY := 1
const RARE := 2
const LEGENDARY := 3
const MYTH := 4
const GARBAGE := 5            # 变质堵块（不可合成）

const COLORS := [
	Color(0.90, 0.90, 0.92),   # ⚪
	Color(0.40, 0.85, 0.42),   # 🟢
	Color(0.35, 0.62, 1.00),   # 🔵
	Color(0.72, 0.42, 0.95),   # 🟣
	Color(1.00, 0.82, 0.20),   # 🟡
	Color(0.34, 0.32, 0.16),   # 变质（馊绿褐）
]
const VALUES := [1, 3, 9, 27, 81, 0]
const RNAMES := ["普通", "优质", "稀有", "传说", "神话", "变质"]
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
# 各稀有度合成所需"同色相邻数"：⚪🟢🔵 2 连、🟣 3 连（2蓝→紫、3紫→金；🟡封顶 / 变质 不在表内＝不合成）
const MERGE_NEED := {0: 2, 1: 2, 2: 2, 3: 3}

var NAMES := {
	0: ["米饭", "馒头", "面包", "地瓜", "玉米", "挂面"],
	1: ["包子", "饺子", "炒饭", "蘑菇汤"],
	2: ["汉堡", "盖饭", "水果蛋糕"],
	3: ["黯然销魂饭", "烧鹅"],
	4: ["佛跳墙"],
	5: ["变质", "馊饭", "霉块", "烂菜"],
}
# 各稀有度占格形状（canonical offsets，可旋转）：⚪1 🟢2 🔵3(L) 🟣4(O) 🟡5(P) 变质2(占地堵块)
var SHAPES := {
	0: [Vector2i(0, 0)],
	1: [Vector2i(0, 0), Vector2i(1, 0)],
	2: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)],
	3: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	4: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2)],
	5: [Vector2i(0, 0), Vector2i(1, 0)],
}

enum State { SORTING, WIN, SCATTER, DONE }

# ---------------- 状态 ----------------
var grid: Array = []          # 1D：COLS*ROWS，存 piece id（-1 空）
var locked := {}              # id -> {rarity, name, cells:Array[Vector2i]}
var next_id := 0
var drops_remaining := 0
var pending_merge_rarity := -1
var garbage_spawned := 0

var active_rarity := -1
var active_name := ""
var active_cells: Array = []  # 当前（已旋转）offsets
var active_pos := Vector2i.ZERO

var fall_accum := 0.0
var state: State = State.SORTING
var merge_flash := 0.0

# 撕裂抢救
var scattered: Array = []     # {rarity,name,value,pos:Vector2,salvaged:bool}
var salvage_time_left := 0.0
var bagged_value := 0
var bagged_count := 0
var fled_result := false

var _font: SystemFont
var _started := false


func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Microsoft YaHei UI", "SimHei", "Noto Sans CJK SC", "sans-serif"])
	if standalone:
		begin()


## 公开入口：宿主在玩家交互时调用，开始一局整理。
func begin() -> void:
	start_round()


## 是否处于开发者模式（F1 开关 · 全局 Dev autoload）。
func _dev_on() -> bool:
	var n := get_node_or_null("/root/Dev")
	return n != null and bool(n.get("enabled"))


# ======================= 回合控制 =======================
func start_round() -> void:
	grid.resize(COLS * ROWS)
	grid.fill(-1)
	locked.clear()
	scattered.clear()
	next_id = 0
	drops_remaining = drop_count
	pending_merge_rarity = -1
	garbage_spawned = 0
	active_rarity = -1
	active_cells = []
	fall_accum = 0.0
	merge_flash = 0.0
	bagged_value = 0
	bagged_count = 0
	fled_result = false
	state = State.SORTING
	_started = true
	_spawn_next()
	queue_redraw()


# ======================= 网格存取（1D）=======================
func _gget(x: int, y: int) -> int:
	return int(grid[x * ROWS + y])


func _gset(x: int, y: int, v: int) -> void:
	grid[x * ROWS + y] = v


# ======================= 主循环 =======================
func _process(delta: float) -> void:
	if merge_flash > 0.0:
		merge_flash = max(merge_flash - delta, 0.0)
	if state == State.SORTING:
		var mult := 1.0
		if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
			mult = 9.0
		fall_accum += delta * mult
		if fall_accum >= fall_interval:
			fall_accum = 0.0
			_step_down()
	elif state == State.SCATTER:
		salvage_time_left -= delta
		if salvage_time_left <= 0.0:
			salvage_time_left = 0.0
			_end_salvage(false)
	queue_redraw()


func _step_down() -> void:
	if active_rarity < 0:
		return
	if _can_place(active_cells, active_pos + Vector2i(0, 1)):
		active_pos += Vector2i(0, 1)
	else:
		_lock_active()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if k == KEY_R and _dev_on():   # 测试快捷键：需开发者模式(F1)
			begin()
			return
		if state == State.SORTING and active_rarity >= 0:
			if k == KEY_LEFT or k == KEY_A:
				_move(-1)
			elif k == KEY_RIGHT or k == KEY_D:
				_move(1)
			elif k == KEY_UP or k == KEY_W:
				_rotate()
			elif k == KEY_SPACE:
				_hard_drop()
		elif state == State.SCATTER and k == KEY_F:
			_end_salvage(true)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if state == State.SCATTER:
			_try_salvage(event.position)


# ======================= 操作 =======================
func _move(dx: int) -> void:
	var np := active_pos + Vector2i(dx, 0)
	if _can_place(active_cells, np):
		active_pos = np


func _rotate() -> void:
	var rc := _rotate_offsets(active_cells)
	if _can_place(rc, active_pos):
		active_cells = rc


func _hard_drop() -> void:
	while _can_place(active_cells, active_pos + Vector2i(0, 1)):
		active_pos += Vector2i(0, 1)
	_lock_active()


func _rotate_offsets(cells: Array) -> Array:
	var out: Array = []
	for c: Vector2i in cells:
		out.append(Vector2i(c.y, -c.x))   # 90° 顺时针
	var minx := 9999
	var miny := 9999
	for c: Vector2i in out:
		minx = min(minx, c.x)
		miny = min(miny, c.y)
	for i in out.size():
		var v: Vector2i = out[i]
		out[i] = v - Vector2i(minx, miny)
	return out


func _shape_width(cells: Array) -> int:
	var maxx := 0
	for c: Vector2i in cells:
		maxx = max(maxx, c.x)
	return maxx + 1


func _can_place(cells: Array, pos: Vector2i) -> bool:
	for off: Vector2i in cells:
		var c := pos + off
		if c.x < 0 or c.x >= COLS or c.y < 0 or c.y >= ROWS:
			return false
		if _gget(c.x, c.y) != -1:
			return false
	return true


# ======================= 锁定 / 合成 / 生成 =======================
func _lock_active() -> void:
	var id := next_id
	next_id += 1
	var cells: Array = []
	for off: Vector2i in active_cells:
		cells.append(active_pos + off)
	locked[id] = {"rarity": active_rarity, "name": active_name, "cells": cells}
	for c: Vector2i in cells:
		_gset(c.x, c.y, id)
	active_rarity = -1
	# 落定噪音接口（~4~5m，§八），白盒不发实声
	_check_merge(id)
	_spawn_next()


func _check_merge(id: int) -> void:
	var p: Dictionary = locked[id]
	var rar := int(p["rarity"])
	if not MERGE_NEED.has(rar):
		return   # 🟡 封顶 / 变质堵块：不合成
	var need := int(MERGE_NEED[rar])
	var cluster := _cluster(id, rar)
	if cluster.size() >= need:
		_do_merge(cluster.slice(0, need), rar)   # 取 need 个同色相邻件合成


func _cluster(start_id: int, rar: int) -> Array:
	# 从 start_id 起 BFS 收集"同稀有度且正交相邻"的连通件（返回 piece id 列表，start 居首）
	var seen := {start_id: true}
	var order: Array = [start_id]
	var queue: Array = [start_id]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		var p: Dictionary = locked[cur]
		var cells: Array = p["cells"]
		for c: Vector2i in cells:
			for d: Vector2i in DIRS:
				var nc := c + d
				if nc.x < 0 or nc.x >= COLS or nc.y < 0 or nc.y >= ROWS:
					continue
				var nid := _gget(nc.x, nc.y)
				if nid != -1 and not seen.has(nid):
					var q: Dictionary = locked[nid]
					if int(q["rarity"]) == rar:
						seen[nid] = true
						order.append(nid)
						queue.append(nid)
	return order


func _do_merge(ids: Array, rar: int) -> void:
	for mid in ids:
		var pm: Dictionary = locked[mid]
		var cm: Array = pm["cells"]
		for c: Vector2i in cm:
			_gset(c.x, c.y, -1)
		locked.erase(mid)
	pending_merge_rarity = rar + 1   # 升级件从顶部重新下落（§一.3）
	merge_flash = 0.35
	# 合成噪音接口（~5~6m，§八）


func _spawn_next() -> void:
	var rarity: int
	if pending_merge_rarity >= 0:
		rarity = pending_merge_rarity
		pending_merge_rarity = -1
	elif drops_remaining > 0:
		if garbage_spawned < max_garbage and randf() < garbage_rate:
			rarity = GARBAGE           # 变质堵块：额外掉落、不占用 N
			garbage_spawned += 1
		else:
			rarity = _random_drop_rarity()
			drops_remaining -= 1
	else:
		_win()
		return
	active_rarity = rarity
	active_name = _random_name(rarity)
	var shp: Array = SHAPES[rarity]
	active_cells = shp.duplicate()
	var w := _shape_width(active_cells)
	active_pos = Vector2i(int((COLS - w) / 2.0), 0)
	if not _can_place(active_cells, active_pos):
		_tear()   # 顶部塞不下 → 溢出撕裂


func _random_drop_rarity() -> int:
	# 仅 ⚪🟢🔵 掉落（44/33/22，=40:30:20 归一）；🟣🟡 只能合成
	var r := randf()
	if r < 0.44:
		return COMMON
	elif r < 0.77:
		return QUALITY
	return RARE


func _random_name(rarity: int) -> String:
	var arr: Array = NAMES[rarity]
	return String(arr[randi() % arr.size()])


func _win() -> void:
	state = State.WIN   # 全部食物整齐入可搜刮容器
	var loot: Array = []
	for id in locked:
		var p: Dictionary = locked[id]
		if int(p["rarity"]) < 5:
			loot.append(String(p["name"]))
	finished.emit({"won": true, "loot": loot})   # → 主循环：把容器内容物给玩家


# ======================= 撕裂 → 散落抢救 =======================
func _tear() -> void:
	state = State.SCATTER
	# 撕裂巨响接口（~12~15m，§八）→ 招饿魔，启动抢救倒计时
	scattered.clear()
	var items: Array = []
	for id in locked:
		items.append(locked[id])
	for i in items.size():
		var it: Dictionary = items[i]
		var col := i % 7
		var rowi := 0
		if i >= 7:
			rowi = 1
		if i >= 14:
			rowi = 2
		var sx := 170.0 + float(col) * 120.0
		var sy := 360.0 + float(rowi) * 96.0
		scattered.append({
			"rarity": int(it["rarity"]),
			"name": String(it["name"]),
			"value": VALUES[int(it["rarity"])],
			"pos": Vector2(sx, sy),
			"salvaged": false,
		})
	salvage_time_left = salvage_window
	bagged_value = 0
	bagged_count = 0


func _try_salvage(mp: Vector2) -> void:
	for it in scattered:
		var d: Dictionary = it
		if bool(d["salvaged"]):
			continue
		var p: Vector2 = d["pos"]
		var rect := Rect2(p.x - 54.0, p.y - 34.0, 108.0, 68.0)
		if rect.has_point(mp):
			d["salvaged"] = true
			bagged_value += int(d["value"])
			bagged_count += 1
			return


func _end_salvage(fled: bool) -> void:
	fled_result = fled
	state = State.DONE
	finished.emit({"won": false, "fled": fled, "bagged_value": bagged_value, "bagged_count": bagged_count})


# ======================= 渲染 =======================
func _draw() -> void:
	if not _started:
		return   # 接大地图：begin() 之前不绘制（避免空面板盖住世界）
	draw_rect(Rect2(0, 0, 1152, 648), Color(0.07, 0.08, 0.11), true)
	_text(Vector2(GRID_X - 16, 34), "🌀 暴食传送门 · 外卖叠叠乐（白盒）", 22, Color(0.82, 0.72, 1.0))
	_text(Vector2(GRID_X - 16, 58), "←/→ 移动 · ↑ 旋转 · ↓ 软降 · 空格 硬降 · R 重来", 14, Color(0.78, 0.82, 0.9))

	if state == State.SORTING or state == State.WIN:
		_draw_board()
	if state == State.SORTING:
		_draw_sorting_hud()
	elif state == State.WIN:
		_draw_win()
	elif state == State.SCATTER:
		_draw_scatter()
	elif state == State.DONE:
		_draw_done()


func _draw_board() -> void:
	# 传送门
	var portal_x := GRID_X + COLS * CELL / 2.0
	if portal_texture != null:
		var ps := portal_texture.get_size()
		draw_texture(portal_texture, Vector2(portal_x - ps.x * 0.5, GRID_Y - 26.0 - ps.y * 0.5))
	else:
		draw_circle(Vector2(portal_x, GRID_Y - 26.0), 22.0, Color(0.55, 0.32, 0.78, 0.85))
		draw_circle(Vector2(portal_x, GRID_Y - 26.0), 12.0, Color(0.9, 0.7, 1.0, 0.7))
	# 网格底
	for cx in COLS:
		for cy in ROWS:
			var r := Rect2(GRID_X + cx * CELL, GRID_Y + cy * CELL, CELL - 2.0, CELL - 2.0)
			draw_rect(r, Color(0.14, 0.15, 0.19), true)
			draw_rect(r, Color(0.28, 0.30, 0.38), false)
	# 顶部危险边
	var dl := Color(1.0, 0.32, 0.32, 0.7)
	draw_line(Vector2(GRID_X, GRID_Y), Vector2(GRID_X + COLS * CELL, GRID_Y), dl, 2.0)
	# 已锁定食物
	for id in locked:
		var p: Dictionary = locked[id]
		var rr := int(p["rarity"])
		var col: Color = COLORS[rr]
		var cells: Array = p["cells"]
		for c: Vector2i in cells:
			_draw_block(c, rr, col)
		var c0: Vector2i = cells[0]
		_text(Vector2(GRID_X + c0.x * CELL + 5.0, GRID_Y + c0.y * CELL + 24.0), String(p["name"]), 12, Color(0.08, 0.08, 0.1))
	# 当前下落件
	if active_rarity >= 0:
		var ac: Color = COLORS[active_rarity].lightened(0.12)
		for off: Vector2i in active_cells:
			_draw_block(active_pos + off, active_rarity, ac)
		var f0: Vector2i = active_pos + (active_cells[0] as Vector2i)
		_text(Vector2(GRID_X + f0.x * CELL + 5.0, GRID_Y + f0.y * CELL + 24.0), active_name, 12, Color(0.08, 0.08, 0.1))


func _draw_block(c: Vector2i, rarity: int, color: Color) -> void:
	var r := Rect2(GRID_X + c.x * CELL + 3.0, GRID_Y + c.y * CELL + 3.0, CELL - 6.0, CELL - 6.0)
	if food_textures.has(rarity):
		draw_texture_rect(food_textures[rarity] as Texture2D, r, false)   # 美术贴图替换纯色块
	else:
		draw_rect(r, color, true)
		draw_rect(r, color.darkened(0.45), false)


func _draw_sorting_hud() -> void:
	var bx := GRID_X + COLS * CELL + 40.0
	_text(Vector2(bx, GRID_Y + 20.0), "剩余掉落：%d / %d" % [drops_remaining, drop_count], 18, Color(0.9, 0.9, 0.95))
	if active_rarity >= 0:
		_text(Vector2(bx, GRID_Y + 52.0), "当前：%s（%s·%d格）" % [active_name, RNAMES[active_rarity], (active_cells.size())], 15, COLORS[active_rarity])
	if pending_merge_rarity >= 0:
		_text(Vector2(bx, GRID_Y + 80.0), "合成升级 → %s 落下！" % RNAMES[pending_merge_rarity], 15, Color(1, 0.9, 0.4))
	_text(Vector2(bx, GRID_Y + 130.0), "掉落：仅 ⚪🟢🔵（+变质堵块）", 14, Color(0.8, 0.8, 0.85))
	_text(Vector2(bx, GRID_Y + 152.0), "合成：⚪🟢🔵 2连 · 🟣 3连 · 🟡封顶", 14, Color(0.8, 0.85, 0.7))
	_text(Vector2(bx, GRID_Y + 174.0), "🟣🟡 只能靠合成拼出", 14, Color(0.8, 0.8, 0.85))
	_text(Vector2(bx, GRID_Y + 196.0), "变质块不可合成·只占地", 14, Color(0.62, 0.6, 0.45))
	if merge_flash > 0.0:
		_text(Vector2(GRID_X, GRID_Y + COLS * 0 - 6.0), "✨合成！", 18, Color(1, 0.95, 0.4, merge_flash / 0.35))


func _draw_win() -> void:
	draw_rect(Rect2(0, 0, 1152, 648), Color(0, 0.05, 0, 0.55), true)
	_text(Vector2(330, 150), "✅ 成功！全部食物整齐入可搜刮容器", 30, Color(0.5, 1.0, 0.55))
	var counts := [0, 0, 0, 0, 0]
	for id in locked:
		var p: Dictionary = locked[id]
		var rr := int(p["rarity"])
		if rr < 5:
			counts[rr] += 1   # 变质块(5)不计入战利品
	var total := 0
	var y := 210.0
	for r in 5:
		total += counts[r] * VALUES[r]
		if counts[r] > 0:
			_text(Vector2(430, y), "%s ×%d（单价%d）" % [RNAMES[r], counts[r], VALUES[r]], 18, COLORS[r])
			y += 30.0
	_text(Vector2(430, y + 16.0), "容器总价值：%d" % total, 22, Color(1, 0.95, 0.6))
	_text(Vector2(430, y + 54.0), "按 R 再来一局", 16, Color(0.85, 0.85, 0.9))


func _draw_scatter() -> void:
	draw_rect(Rect2(0, 0, 1152, 648), Color(0.22, 0.02, 0.02, 0.4), true)
	_text(Vector2(150, 150), "💥 容器撕裂！巨响招怪 —— 点击抢救高价值食物入包，或按 [F] 逃走", 22, Color(1, 0.6, 0.5))
	# 敌人 ETA 条
	var frac: float = salvage_time_left / salvage_window
	draw_rect(Rect2(150, 180, 500, 18), Color(0.25, 0.25, 0.3), true)
	draw_rect(Rect2(150, 180, 500.0 * frac, 18), Color(1.0, 0.42, 0.2), true)
	_text(Vector2(664, 196), "敌人 %.1fs 后到达" % salvage_time_left, 16, Color(1, 0.8, 0.7))
	_text(Vector2(150, 246), "散落一地（点贵的先捡）：", 16, Color(0.9, 0.9, 0.9))
	# 散落物
	for it in scattered:
		var d: Dictionary = it
		if bool(d["salvaged"]):
			continue
		var p: Vector2 = d["pos"]
		var col: Color = COLORS[int(d["rarity"])]
		var rect := Rect2(p.x - 54.0, p.y - 34.0, 108.0, 68.0)
		draw_rect(rect, col, true)
		draw_rect(rect, col.darkened(0.45), false)
		_text(Vector2(p.x - 48.0, p.y - 6.0), String(d["name"]), 14, Color(0.08, 0.08, 0.1))
		_text(Vector2(p.x - 48.0, p.y + 18.0), "价值 %d" % int(d["value"]), 13, Color(0.1, 0.1, 0.12))
	_text(Vector2(150, 600), "已抢救 %d 件 · 价值 %d" % [bagged_count, bagged_value], 20, Color(0.6, 1.0, 0.65))


func _draw_done() -> void:
	draw_rect(Rect2(0, 0, 1152, 648), Color(0, 0, 0, 0.6), true)
	var head := "🏃 弃货逃走！" if fled_result else "⏱ 敌人已到，抢救结束"
	_text(Vector2(420, 260), head, 28, Color(0.95, 0.85, 0.6))
	_text(Vector2(420, 308), "带走：%d 件 · 总价值 %d" % [bagged_count, bagged_value], 20, Color(0.7, 1.0, 0.7))
	_text(Vector2(420, 350), "（未捡的食物已丢失） 按 R 再来一局", 16, Color(0.85, 0.85, 0.9))


func _text(pos: Vector2, s: String, size: int, color: Color) -> void:
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
