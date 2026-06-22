extends GutTest

# 验证:StaminaComp 是独立组件 — 两个实例数据完全独立(联机基础)

func test_can_instantiate_standalone() -> void:
	var c := StaminaComp.new()
	add_child_autofree(c)
	assert_eq(c.value, StaminaComp.MAX, "实例化后体力满")
	assert_false(c.is_running())
	assert_false(c.is_locked())

func test_two_instances_have_independent_state() -> void:
	var c1 := StaminaComp.new()
	var c2 := StaminaComp.new()
	add_child_autofree(c1)
	add_child_autofree(c2)
	c1.try_start_run()
	c1._drain(1.0)  # 直接调内部:扣 DRAIN=25 体力
	assert_lt(c1.value, StaminaComp.MAX, "c1 体力下降")
	assert_eq(c2.value, StaminaComp.MAX, "c2 必须仍满(数据互不影响)")
	assert_true(c1.is_running())
	assert_false(c2.is_running())

func test_exhaust_locks_only_this_instance() -> void:
	var c1 := StaminaComp.new()
	var c2 := StaminaComp.new()
	add_child_autofree(c1)
	add_child_autofree(c2)
	c1.try_start_run()
	c1._drain(10.0)  # 直接抽干
	assert_eq(c1.value, 0.0)
	assert_true(c1.is_locked(), "c1 应锁定")
	assert_false(c2.is_locked(), "c2 不该受影响")

func test_reset_returns_to_max() -> void:
	var c := StaminaComp.new()
	add_child_autofree(c)
	c.try_start_run()
	c._drain(2.0)
	assert_lt(c.value, StaminaComp.MAX)
	c.reset()
	assert_eq(c.value, StaminaComp.MAX)
	assert_false(c.is_running())
	assert_false(c.is_locked())
