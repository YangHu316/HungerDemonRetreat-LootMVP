extends GutTest

# 验证:autoload PlayerInventory / Stamina 是 InventoryComp/StaminaComp 的代理
# 1) 无 local_player 时用 _fallback_comp(给 GUT 测试和早期场景兜底)
# 2) register_local_player 后 forward 到该 player 的 comp
# 3) unregister 回退到 fallback

# Inner class:模拟 Player 节点(用 GDScript class 保证 inventory_comp/stamina_comp
# 是真实 property,Object.set 才能写进去;裸 Node + set("xxx", v) 是 no-op)
class FakePlayer extends Node:
	var inventory_comp: InventoryComp = null
	var stamina_comp: StaminaComp = null

func before_each() -> void:
	var inv = get_node("/root/PlayerInventory")
	inv.local_player = null
	inv.reset()
	var st = get_node("/root/Stamina")
	st.local_player = null
	st.reset()

# ---- PlayerInventory ----
func test_inventory_proxy_forwards_to_fallback_when_no_player() -> void:
	var inv = get_node("/root/PlayerInventory")
	var apple: ItemData = load("res://resources/items/apple.tres")
	assert_true(inv.try_place_item(apple))
	assert_eq(inv.get_total_value(), apple.value, "无 local_player 时走 _fallback_comp")

func test_inventory_proxy_forwards_to_local_player_after_register() -> void:
	var inv = get_node("/root/PlayerInventory")
	var fake_player := FakePlayer.new()
	var comp := InventoryComp.new()
	fake_player.add_child(comp)
	fake_player.inventory_comp = comp
	add_child_autofree(fake_player)
	inv.register_local_player(fake_player)
	var apple: ItemData = load("res://resources/items/apple.tres")
	inv.try_place_item(apple)
	assert_eq(comp.get_total_value(), apple.value, "register 后 forward 到 player.inventory_comp")
	assert_eq(inv.get_total_value(), apple.value, "autoload 读出来一致")
	inv.unregister_local_player(fake_player)

func test_inventory_proxy_switches_to_new_player() -> void:
	var inv = get_node("/root/PlayerInventory")
	var p1 := FakePlayer.new()
	var c1 := InventoryComp.new()
	p1.add_child(c1)
	p1.inventory_comp = c1
	add_child_autofree(p1)
	var p2 := FakePlayer.new()
	var c2 := InventoryComp.new()
	p2.add_child(c2)
	p2.inventory_comp = c2
	add_child_autofree(p2)
	var apple: ItemData = load("res://resources/items/apple.tres")
	inv.register_local_player(p1)
	inv.try_place_item(apple)
	assert_eq(c1.get_total_value(), apple.value)
	inv.register_local_player(p2)
	assert_eq(inv.get_total_value(), 0, "切到 p2 后 autoload 看到的是 p2 的数据(空)")
	inv.unregister_local_player(p2)

# ---- Stamina ----
func test_stamina_proxy_forwards_to_fallback_when_no_player() -> void:
	var st = get_node("/root/Stamina")
	assert_eq(st.value, StaminaComp.MAX, "无 local_player 时 fallback 给满体力")
	st.try_start_run()
	assert_true(st.is_running())
	st.stop_run()

func test_stamina_proxy_switches_to_new_player() -> void:
	var st = get_node("/root/Stamina")
	var p1 := FakePlayer.new()
	var s1 := StaminaComp.new()
	p1.add_child(s1)
	p1.stamina_comp = s1
	add_child_autofree(p1)
	st.register_local_player(p1)
	st.try_start_run()
	s1._drain(2.0)
	assert_lt(s1.value, StaminaComp.MAX, "p1 体力下降")
	var p2 := FakePlayer.new()
	var s2 := StaminaComp.new()
	p2.add_child(s2)
	p2.stamina_comp = s2
	add_child_autofree(p2)
	st.register_local_player(p2)
	assert_eq(st.value, StaminaComp.MAX, "切到 p2 后看到的是 p2 满体力")
	st.unregister_local_player(p2)
