extends GutTest

# P0 护栏: 外卖侠 §三 后半 + §十三 — 食物变质 4 档 + 价值打折
# 1) Tier 数学:elapsed/tier_seconds 取整 + clamp(0..3)
# 2) Multiplier:[1.0, 0.6, 0.3, 0.0]
# 3) entry_value:非食物原价,食物 = base * multiplier
# 4) GameSession.tick 推进背包食物 freshness_elapsed,不动非食物
# 5) Stash 不变质(GameSession 只迭代 PlayerInventory)
# 6) Settlement(get_total_value)自然带打折
# 7) 仓库 transfer 保留 freshness_elapsed

var gs: Node
var inv: Node
var stash: Node

func before_each() -> void:
	gs = get_node("/root/GameSession")
	inv = get_node("/root/PlayerInventory")
	stash = get_node("/root/Stash")
	inv.reset()
	stash.clear()
	gs.start_round()
	gs.set_process(false)

func after_each() -> void:
	gs.round_active = false
	gs.set_process(false)
	inv.reset()
	stash.clear()

# ---- 数学 ----
func test_tier_for_zero_elapsed_is_fresh() -> void:
	assert_eq(Freshness.tier_for(0.0, 90.0), 0)

func test_tier_for_advances_each_block() -> void:
	# 90s 一档:0..89=FRESH, 90..179=OK, 180..269=STALE, 270+=ROT
	assert_eq(Freshness.tier_for(89.0, 90.0), 0, "<1 段 = FRESH")
	assert_eq(Freshness.tier_for(90.0, 90.0), 1, "刚到 90s = OK")
	assert_eq(Freshness.tier_for(180.0, 90.0), 2, "刚到 180s = STALE")
	assert_eq(Freshness.tier_for(270.0, 90.0), 3, "刚到 270s = ROT")

func test_tier_for_clamps_at_rot() -> void:
	assert_eq(Freshness.tier_for(9999.0, 90.0), 3, "超长时间仍 clamp 到 ROT")

func test_tier_for_zero_tier_seconds_safe() -> void:
	# 防 0 除:tier_seconds = 0 直接 FRESH
	assert_eq(Freshness.tier_for(123.0, 0.0), 0)

func test_multiplier_values() -> void:
	assert_almost_eq(Freshness.multiplier(0), 1.0, 0.001)
	assert_almost_eq(Freshness.multiplier(1), 0.6, 0.001)
	assert_almost_eq(Freshness.multiplier(2), 0.3, 0.001)
	assert_almost_eq(Freshness.multiplier(3), 0.0, 0.001)

# ---- entry_value ----
func test_entry_value_non_food_is_raw() -> void:
	# 找一个非食物 item:Common 类我们暂用 apple(食物),所以这里手动伪造
	var item := ItemData.new()
	item.id = "test_nonfood"
	item.value = 50
	item.is_food = false
	var e: Dictionary = {"item": item, "freshness_elapsed": 1000.0}
	assert_eq(Freshness.entry_value(e), 50, "非食物不打折")

func test_entry_value_food_fresh_is_raw() -> void:
	var apple: ItemData = load("res://resources/items/apple.tres")
	var e: Dictionary = {"item": apple, "freshness_elapsed": 0.0}
	assert_eq(Freshness.entry_value(e), apple.value, "FRESH = 原价")

func test_entry_value_food_rot_is_zero() -> void:
	var apple: ItemData = load("res://resources/items/apple.tres")
	# 90s/档 × 3 = 270s,刚到 ROT
	var e: Dictionary = {"item": apple, "freshness_elapsed": 9999.0}
	assert_eq(Freshness.entry_value(e), 0, "ROT 价值归零")

func test_entry_value_food_ok_60_percent() -> void:
	var apple: ItemData = load("res://resources/items/apple.tres")  # value=5
	var e: Dictionary = {"item": apple, "freshness_elapsed": 100.0}
	# 100s / 90s = 1 档 = OK = 60%。round(5*0.6) = 3
	assert_eq(Freshness.entry_value(e), 3)

# ---- GameSession tick 推进 freshness ----
func test_tick_advances_food_freshness() -> void:
	var apple: ItemData = load("res://resources/items/apple.tres")
	inv.try_place_item(apple)
	var e: Dictionary = inv.grid.entries[0]
	assert_almost_eq(float(e.get("freshness_elapsed", -1.0)), 0.0, 0.001, "place 后 elapsed=0")
	gs.tick(30.0)
	assert_almost_eq(float(e["freshness_elapsed"]), 30.0, 0.001, "tick(30) 后食物 elapsed=30")

func test_tick_does_not_advance_non_food() -> void:
	# 制造非食物 entry 直接塞 grid(绕开 try_place_item 的 0 初始化)
	var item := ItemData.new()
	item.id = "non_food"
	item.value = 99
	item.is_food = false
	item.grid_w = 1
	item.grid_h = 1
	var entry: Dictionary = {
		"item": item, "x": 0, "y": 0,
		"rotated": false, "examined": true,
		"freshness_elapsed": 0.0,
	}
	inv.grid.place(entry, 0, 0)
	gs.tick(50.0)
	assert_almost_eq(float(entry["freshness_elapsed"]), 0.0, 0.001, "非食物 elapsed 不变")

# ---- Stash 不变质 ----
func test_stash_items_do_not_decay() -> void:
	var apple: ItemData = load("res://resources/items/apple.tres")
	stash.try_add(apple, 50.0)
	var stash_entry: Dictionary = stash.grid.entries[0]
	assert_almost_eq(float(stash_entry["freshness_elapsed"]), 50.0, 0.001, "stash 接受 50s elapsed")
	gs.tick(120.0)
	assert_almost_eq(float(stash_entry["freshness_elapsed"]), 50.0, 0.001, "tick 后 stash 不变")

# ---- Settlement 自然带打折 ----
func test_get_total_value_uses_freshness() -> void:
	var apple: ItemData = load("res://resources/items/apple.tres")  # value=5
	inv.try_place_item(apple)
	# 刚放,FRESH:5
	assert_eq(inv.get_total_value(), 5)
	# tick 100s → OK → round(5*0.6)=3
	gs.tick(100.0)
	assert_eq(inv.get_total_value(), 3, "OK 档 settlement = 3")
	# 继续 tick 到 ROT
	gs.tick(300.0)
	assert_eq(inv.get_total_value(), 0, "ROT settlement = 0")

# ---- 仓库 transfer 保留 freshness ----
func test_transfer_to_stash_preserves_freshness() -> void:
	var apple: ItemData = load("res://resources/items/apple.tres")
	inv.try_place_item(apple)
	var e: Dictionary = inv.grid.entries[0]
	e["freshness_elapsed"] = 75.0
	var ok: bool = inv.transfer_to_stash(e)
	assert_true(ok)
	assert_eq(inv.grid.entries.size(), 0)
	assert_eq(stash.grid.entries.size(), 1)
	assert_almost_eq(float(stash.grid.entries[0]["freshness_elapsed"]), 75.0, 0.001)

func test_transfer_from_stash_preserves_freshness() -> void:
	var apple: ItemData = load("res://resources/items/apple.tres")
	stash.try_add(apple, 120.0)
	var stash_e: Dictionary = stash.grid.entries[0]
	var ok: bool = inv.transfer_from_stash(stash_e)
	assert_true(ok)
	assert_eq(inv.grid.entries.size(), 1)
	assert_almost_eq(float(inv.grid.entries[0]["freshness_elapsed"]), 120.0, 0.001, "回背包保留 elapsed")
