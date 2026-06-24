extends Node
# PlayerInventory — autoload 本地玩家代理(零数据)
# 历史:这里曾持有 5×4 背包数据。为了联机(per-player 背包),数据搬到了
# scripts/components/inventory_comp.gd,挂在每个 Player 节点下。
# 现在这个 autoload 只是 forward 到"当前本地玩家"的 InventoryComp。
#
# 用法:Player._ready() 调用 PlayerInventory.register_local_player(self)
# 该 player 离场时 unregister_local_player(self)
#
# 测试/早期场景兜底:_fallback_comp 在无 player 注册时充当数据源,
# 现有 GUT 测试不依赖场景树,通过 fallback 透明使用。

signal changed

var local_player: Node = null
# 兜底 comp:当 GUT 测试或场景里还没 Player 时使用,保证 autoload API 不崩
var _fallback_comp: InventoryComp = null

func _ready() -> void:
	_fallback_comp = InventoryComp.new()
	add_child(_fallback_comp)
	_fallback_comp.changed.connect(_on_comp_changed)

func _on_comp_changed() -> void:
	changed.emit()

# Player 节点 _ready 时调用,注册自己为本地玩家
func register_local_player(p: Node) -> void:
	if p == null:
		return
	# 切换 local_player:断开旧的 signal,接新的
	if local_player != null and is_instance_valid(local_player):
		var old_comp = local_player.get("inventory_comp")
		if old_comp != null and old_comp.changed.is_connected(_on_comp_changed):
			old_comp.changed.disconnect(_on_comp_changed)
	local_player = p
	var new_comp = p.get("inventory_comp")
	if new_comp != null:
		# Phase 2B fix bug 3v2:跨场景持久化 — 上一局的物品在 _fallback_comp 中保存
		# 进新场景,新 Player 的 inventory_comp 是空的 → 从 fallback 迁移过来
		# (home → main 重开战局:把上局撤回的物品恢复到新 Player 背包)
		if new_comp.grid != null and new_comp.grid.entries.is_empty() \
				and _fallback_comp != null and _fallback_comp.grid != null \
				and not _fallback_comp.grid.entries.is_empty():
			_migrate_grid(_fallback_comp.grid, new_comp.grid)
		if not new_comp.changed.is_connected(_on_comp_changed):
			new_comp.changed.connect(_on_comp_changed)
	changed.emit()  # 切换玩家 = 数据变化

func unregister_local_player(p: Node) -> void:
	if local_player != p:
		return
	if local_player != null and is_instance_valid(local_player):
		var old_comp = local_player.get("inventory_comp")
		if old_comp != null:
			# Phase 2B fix bug 3v2:Player 即将被 free(scene change),先把数据搬到
			# _fallback_comp 持久化。否则 home.tscn 看到 fallback 是空的(物品丢失)
			if old_comp.grid != null and _fallback_comp != null and _fallback_comp.grid != null:
				_migrate_grid(old_comp.grid, _fallback_comp.grid)
			if old_comp.changed.is_connected(_on_comp_changed):
				old_comp.changed.disconnect(_on_comp_changed)
	local_player = null
	changed.emit()

# 把 src grid 内容深拷贝到 dst grid(持久化用)
func _migrate_grid(src: GridInventory, dst: GridInventory) -> void:
	if src == null or dst == null:
		return
	dst.cells.clear()
	dst.entries.clear()
	dst.setup(src.cols, src.rows)
	for e in src.entries:
		var ne: Dictionary = e.duplicate(true)
		dst.place(ne, int(ne.get("x", 0)), int(ne.get("y", 0)))

# 内部分派:有 local_player 用它的 comp,否则用 _fallback_comp
func _get_comp() -> InventoryComp:
	if local_player != null and is_instance_valid(local_player):
		var c = local_player.get("inventory_comp")
		if c != null:
			return c
	return _fallback_comp

# property forward:grid
var grid: GridInventory:
	get:
		var c = _get_comp()
		return c.grid if c != null else null

# 9 个方法 forward
func reset() -> void:
	_get_comp().reset()

func try_place_item(item: ItemData, examined: bool = true) -> bool:
	return _get_comp().try_place_item(item, examined)

func place_entry(entry: Dictionary, x: int, y: int) -> bool:
	return _get_comp().place_entry(entry, x, y)

func remove_entry(entry: Dictionary) -> void:
	_get_comp().remove_entry(entry)

func get_total_value() -> int:
	return _get_comp().get_total_value()

func transfer_to_stash(entry: Dictionary) -> bool:
	return _get_comp().transfer_to_stash(entry)

func transfer_from_stash(stash_entry: Dictionary) -> bool:
	return _get_comp().transfer_from_stash(stash_entry)
