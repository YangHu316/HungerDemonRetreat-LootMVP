extends GutTest

# Phase 2B 多人 fix pack v3:用户手测发现的 2 个新 bug
# bug 2v2: A 放回物品后,A 端 entries_synced re-hydrate 把新 uid 标 inspected=false
#          → A 被迫"重新 inspect 自己刚放进去的物品"
#          fix: put_granted RPC 携带 container_path + new_entry_uid,
#               sender 立即 mark_inspected(顺序:reply granted 先发,broadcast 后发)
# bug 3v2: 撤离回家后仓库/背包是空的 — items 丢失
#          根因:Player 节点离场被 free,inventory_comp 数据随节点消失,
#          autoload 的 _fallback_comp 没有保存
#          fix: PlayerInventory.unregister_local_player 把 player.inventory_comp.grid
#               迁移到 _fallback_comp;register 时如新 comp 空且 fallback 有 → 迁移回去

var _mm: Node
var _pinv: Node

func before_each() -> void:
	_mm = get_node("/root/MultiplayerManager")
	_pinv = get_node("/root/PlayerInventory")
	_mm.mode = _mm.Mode.SINGLE
	_mm.players.clear()
	_mm.peer = null
	_pinv.local_player = null
	_pinv.reset()

# ── bug 2v2:put_granted 携带 new_entry_uid + container_path ──

func test_put_granted_signal_has_uid_arg() -> void:
	# put_granted signal 必须有 5 个参数(item_path, source_x, source_y, container_path, new_entry_uid)
	var src: String = load("res://scripts/autoloads/multiplayer_manager.gd").source_code
	# 找 signal 声明
	var i: int = src.find("signal put_granted")
	assert_gte(i, 0)
	var line_end: int = src.find("\n", i)
	var line: String = src.substr(i, line_end - i)
	assert_true(line.contains("container_path"),
		"put_granted signal 必须含 container_path 参数(给 sender mark_inspected 用)")
	assert_true(line.contains("new_entry_uid"),
		"put_granted signal 必须含 new_entry_uid(host 分配给放回的物品)")

func test_request_put_replies_granted_before_broadcast() -> void:
	# bug 2v2 fix:granted 必须先发,broadcast 后发(sender 在 hydrate 前已 mark_inspected)
	var src: String = load("res://scripts/autoloads/multiplayer_manager.gd").source_code
	var i: int = src.find("func _rpc_request_put")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	var granted_pos: int = body.find("_send_put_granted(")
	var bcast_pos: int = body.find("broadcast_container_entries")
	assert_gte(granted_pos, 0)
	assert_gte(bcast_pos, 0)
	assert_lt(granted_pos, bcast_pos,
		"_send_put_granted 必须在 broadcast_container_entries 之前(顺序敏感)")

func test_search_ui_on_put_granted_marks_inspected() -> void:
	var src: String = load("res://scripts/ui/search_ui.gd").source_code
	var i: int = src.find("func _on_put_granted")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	# 函数签名必须含新参数
	var sig_end: int = body.find(")")
	var sig: String = body.substr(0, sig_end)
	assert_true(sig.contains("container_path"),
		"_on_put_granted 必须接收 container_path 参数")
	assert_true(sig.contains("new_entry_uid"),
		"_on_put_granted 必须接收 new_entry_uid 参数")
	# 必须调 lil.mark_inspected
	assert_true(body.contains("mark_inspected"),
		"_on_put_granted 必须 mark_inspected(避免 sender 重新 inspect 自己刚放进去的物品)")

# ── bug 3v2:Player 离场把 inventory_comp 数据迁到 _fallback_comp ──

func test_unregister_saves_to_fallback() -> void:
	# 模拟:Player 注册 → 加物品 → unregister → fallback 应该保留物品(Player 离场后 home 看得到)
	var p := Node.new()
	var comp := InventoryComp.new()
	p.add_child(comp)
	p.set_script(GDScript.new())
	# 用一个有 inventory_comp 字段的 Node:用真正的 Player 节点替代麻烦,这里用 set
	# (FakePlayer pattern in test_autoload_proxy.gd works,但 Node.set 会 no-op)
	# 改用 inner class
	add_child_autofree(p)
	# 直接 hack:测试源码层即可
	var src: String = load("res://scripts/autoloads/player_inventory.gd").source_code
	var i: int = src.find("func unregister_local_player")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_fallback_comp") and body.contains("_migrate_grid"),
		"unregister_local_player 必须把 player 的 inventory grid 迁到 _fallback_comp(跨场景持久化)")

func test_register_restores_from_fallback() -> void:
	var src: String = load("res://scripts/autoloads/player_inventory.gd").source_code
	var i: int = src.find("func register_local_player")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	# register 时检测 new_comp 空 + fallback 有 → 迁移恢复
	assert_true(body.contains("_migrate_grid"),
		"register_local_player 必须支持从 _fallback_comp 迁移恢复")
	assert_true(body.contains("entries.is_empty"),
		"register_local_player 必须检测新 comp 是否为空(避免覆盖 mid-round 数据)")

func test_migrate_grid_helper_exists() -> void:
	var src: String = load("res://scripts/autoloads/player_inventory.gd").source_code
	assert_true(src.contains("func _migrate_grid"),
		"PlayerInventory 必须有 _migrate_grid helper(深拷贝 grid)")

class FakePlayer extends Node:
	var inventory_comp: InventoryComp = null

func test_full_save_restore_cycle() -> void:
	# 完整流程:register p1 → 加物品 → unregister p1 → fallback 应有物品 → register p2(空) → p2 应恢复
	var apple: ItemData = load("res://resources/items/apple.tres")
	var p1 := FakePlayer.new()
	var c1 := InventoryComp.new()
	p1.add_child(c1)
	p1.inventory_comp = c1
	add_child_autofree(p1)
	_pinv.register_local_player(p1)
	_pinv.try_place_item(apple)
	assert_eq(c1.get_total_value(), apple.value)
	# unregister:数据应迁到 fallback
	_pinv.unregister_local_player(p1)
	assert_eq(_pinv._fallback_comp.get_total_value(), apple.value,
		"unregister 后 fallback 应保留 player 的物品")
	# 创建 p2(空),register → 数据应从 fallback 迁回
	var p2 := FakePlayer.new()
	var c2 := InventoryComp.new()
	p2.add_child(c2)
	p2.inventory_comp = c2
	add_child_autofree(p2)
	_pinv.register_local_player(p2)
	assert_eq(c2.get_total_value(), apple.value,
		"register 后,新 player 的 inventory_comp 应从 fallback 恢复(跨场景持久化)")
	_pinv.unregister_local_player(p2)
