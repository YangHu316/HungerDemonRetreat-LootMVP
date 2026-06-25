extends GutTest

# P0 护栏 #6: §四 动作三档 — 移速 + 声音半径 + resolve 优先级
# 防御对象: 外卖侠 §四 / §五

# ---- enum 顺序固定(防被改) ----
func test_mode_enum_values_are_fixed() -> void:
	assert_eq(Stance.Mode.SNEAK, 0, "SNEAK=0,enum 顺序不可改")
	assert_eq(Stance.Mode.WALK, 1, "WALK=1")
	assert_eq(Stance.Mode.RUN, 2, "RUN=2")

# ---- 移速常量 ----
func test_sneak_speed() -> void:
	assert_eq(Stance.SNEAK_SPEED, 1.5)

func test_walk_speed_matches_existing() -> void:
	# 与 v11 player.gd 现有 WALK_SPEED 数值一致
	assert_eq(Stance.WALK_SPEED, 4.5)

func test_run_speed_matches_existing() -> void:
	assert_eq(Stance.RUN_SPEED, 7.5)

# ---- 声音半径常量(spec 05_饿魔感知与寻人逻辑.md §1.2) ----
func test_sneak_sound_radius_1_5m() -> void:
	assert_eq(Stance.SNEAK_SOUND_RADIUS, 1.5, "潜行 1.5m 近乎无声 (spec)")

func test_walk_sound_radius_5m() -> void:
	assert_eq(Stance.WALK_SOUND_RADIUS, 5.0, "走路 5m 低噪 (spec)")

func test_run_sound_radius_12m() -> void:
	assert_eq(Stance.RUN_SOUND_RADIUS, 12.0, "奔跑 12m 高噪 (spec)")

# ---- speed() 派发 ----
func test_speed_dispatch() -> void:
	assert_eq(Stance.speed(Stance.Mode.SNEAK), 1.5)
	assert_eq(Stance.speed(Stance.Mode.WALK), 4.5)
	assert_eq(Stance.speed(Stance.Mode.RUN), 7.5)

# ---- sound_radius() 派发 ----
func test_sound_radius_dispatch() -> void:
	assert_eq(Stance.sound_radius(Stance.Mode.SNEAK), 1.5)
	assert_eq(Stance.sound_radius(Stance.Mode.WALK), 5.0)
	assert_eq(Stance.sound_radius(Stance.Mode.RUN), 12.0)

# ---- resolve() 决策 ----
func test_resolve_no_input_is_walk() -> void:
	assert_eq(Stance.resolve(false, false, true), Stance.Mode.WALK, "默认走路")

func test_resolve_sneak_only() -> void:
	assert_eq(Stance.resolve(true, false, true), Stance.Mode.SNEAK)

func test_resolve_run_only() -> void:
	assert_eq(Stance.resolve(false, true, true), Stance.Mode.RUN)

func test_resolve_sneak_beats_run() -> void:
	# 同时按潜行+冲刺 → 潜行优先(安全 > 效率)
	assert_eq(Stance.resolve(true, true, true), Stance.Mode.SNEAK,
		"sneak+sprint 同按时必须 SNEAK 优先")

func test_resolve_run_falls_back_to_walk_when_no_stamina() -> void:
	# 体力不够时 RUN 退到 WALK
	assert_eq(Stance.resolve(false, true, false), Stance.Mode.WALK,
		"can_run=false 时按冲刺只能走路")

func test_resolve_sneak_works_even_without_stamina() -> void:
	# 潜行不消耗体力,can_run 与否不影响
	assert_eq(Stance.resolve(true, false, false), Stance.Mode.SNEAK)
