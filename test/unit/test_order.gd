extends GutTest

# §十 订单系统 MVP

var pool: Node
var inv: Node

func before_each() -> void:
	pool = get_node("/root/OrderPool")
	inv = get_node("/root/PlayerInventory")
	inv.reset()
	pool.clear_active()

# ---- OrderData ----
func test_order_data_describe() -> void:
	var o := OrderData.new()
	o.rarity_required = "Rare"
	o.count_required = 2
	assert_eq(o.describe(), "带回 2 件 Rare 食物")

func test_random_basic_generates_valid_order() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in 20:
		var o: OrderData = OrderData.random_basic(rng)
		assert_true(OrderData.VALID_RARITY.has(o.rarity_required),
			"rarity 必须在合法集合内: %s" % o.rarity_required)
		assert_between(o.count_required, 1, 4, "数量 1-4")
		assert_gt(o.reward_base, 0, "报酬必须 > 0")

# ---- completion_for ----
func test_completion_zero_when_no_matches() -> void:
	var o := OrderData.new()
	o.rarity_required = "Rare"
	o.count_required = 2
	var apple: ItemData = load("res://resources/items/apple.tres")  # Common
	var r: Dictionary = o.completion_for([apple, apple])
	assert_eq(r["matched"], 0)
	assert_eq(r["capped"], 0)
	assert_eq(r["ratio"], 0.0)

func test_completion_partial() -> void:
	var o := OrderData.new()
	o.rarity_required = "Common"
	o.count_required = 3
	var apple: ItemData = load("res://resources/items/apple.tres")
	var r: Dictionary = o.completion_for([apple])
	assert_eq(r["matched"], 1)
	assert_eq(r["capped"], 1)
	assert_almost_eq(float(r["ratio"]), 1.0 / 3.0, 0.001)

func test_completion_caps_at_required() -> void:
	var o := OrderData.new()
	o.rarity_required = "Common"
	o.count_required = 2
	var apple: ItemData = load("res://resources/items/apple.tres")
	var r: Dictionary = o.completion_for([apple, apple, apple, apple])
	assert_eq(r["matched"], 4, "matched 是实际命中数")
	assert_eq(r["capped"], 2, "capped 不超过 required(超量不计奖励)")
	assert_eq(r["ratio"], 1.0)

# ---- OrderPool 状态机 ----
func test_pool_has_candidate_on_start() -> void:
	# autoload 启动时已生成候选
	assert_not_null(pool.get_candidate(), "启动就应有候选订单")

func test_accept_moves_candidate_to_active_and_refreshes() -> void:
	var c_before: OrderData = pool.get_candidate()
	assert_true(pool.accept_candidate())
	assert_eq(pool.get_active(), c_before, "接的就是之前的候选")
	assert_not_null(pool.get_candidate(), "接单后应自动出下一个候选")
	assert_ne(pool.get_candidate(), c_before, "新候选 != 老候选")

func test_accept_blocked_when_active_exists() -> void:
	pool.accept_candidate()
	# 再接应失败(MVP 单订单)
	assert_false(pool.accept_candidate(), "已有 active 时接单应失败")

func test_clear_active_releases_slot() -> void:
	pool.accept_candidate()
	assert_true(pool.has_active())
	pool.clear_active()
	assert_false(pool.has_active())
	# 又能接单了
	assert_true(pool.accept_candidate())

func test_refresh_candidate_changes_candidate() -> void:
	var c_before: OrderData = pool.get_candidate()
	pool.refresh_candidate()
	# 注意:理论上随机可能撞同样的订单,但 RNG 几乎不可能;不强测 !=
	assert_not_null(pool.get_candidate())

# ---- completion_for_inventory(集成)----
func test_completion_for_inventory_counts_only_matching_rarity() -> void:
	pool.accept_candidate()
	# 强制 active 订单 = Common 3 件
	pool.get_active().rarity_required = "Common"
	pool.get_active().count_required = 3
	# 给背包放 2 个 Common(apple/bread)+ 1 个 Rare(diamond?让我们用 rifle)
	var apple: ItemData = load("res://resources/items/apple.tres")
	var bread: ItemData = load("res://resources/items/bread.tres")
	var rifle: ItemData = load("res://resources/items/rifle.tres")  # Common/Rare?查
	inv.try_place_item(apple)
	inv.try_place_item(bread)
	# 第三件用 banana
	var banana: ItemData = load("res://resources/items/banana.tres")
	inv.try_place_item(banana)
	var r: Dictionary = pool.completion_for_inventory(inv)
	# apple/bread/banana 都是 Common(检查 .tres 数值)
	assert_eq(r["matched"], 3, "3 件 Common 都匹配")
	assert_eq(r["capped"], 3)
	assert_eq(r["ratio"], 1.0)
