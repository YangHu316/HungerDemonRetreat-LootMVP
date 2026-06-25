extends GutTest

# 外卖侠 §06 玩家躲避系统 — HidingSpot 实体
# 防御 spec 03 §九 / 06_玩家躲避系统.md:
#   容量 1 (储物柜/床底/桌底) 或 2 (纸箱堆)
#   被发现概率 export 配置(10/20/35%)
#   add/remove occupant + can_hide 行为
#   group "hiding_spots" + "interactables"

const HidingSpotScript := preload("res://scripts/entities/hiding_spot.gd")

func _spawn_spot() -> Node3D:
	var hs := Node3D.new()
	hs.set_script(HidingSpotScript)
	add_child_autofree(hs)
	return hs

func _make_fake_player() -> Node3D:
	var p := Node3D.new()
	p.add_to_group("player")
	add_child_autofree(p)
	return p

# ── 默认值 ──

func test_hiding_spot_default_capacity_one() -> void:
	var hs := _spawn_spot()
	assert_eq(hs.capacity, 1, "默认容量 1")

func test_hiding_spot_default_detection_prob() -> void:
	var hs := _spawn_spot()
	assert_almost_eq(hs.detection_prob, 0.20, 0.001, "默认被发现概率 20%")

# ── group 注册 ──

func test_hiding_spot_in_groups() -> void:
	var hs := _spawn_spot()
	assert_true(hs.is_in_group("hiding_spots"),
		"HidingSpot 必须在 hiding_spots group(monster._check_hiding_spot_detect 用)")
	assert_true(hs.is_in_group("interactables"),
		"HidingSpot 必须在 interactables group")

# ── 容量 1 行为 ──

func test_can_hide_when_empty() -> void:
	var hs := _spawn_spot()
	assert_true(hs.can_hide(), "空 spot 必须 can_hide=true")

func test_add_occupant_fills_capacity_1() -> void:
	var hs := _spawn_spot()
	var p := _make_fake_player()
	assert_true(hs.add_occupant(p), "首次加 occupant 成功")
	assert_false(hs.can_hide(), "容量 1 加满后 can_hide=false")
	assert_eq(hs.get_occupants().size(), 1, "occupants 计数 1")
	assert_true(hs.has_occupant(p), "has_occupant 返 true")

func test_add_occupant_rejects_when_full() -> void:
	var hs := _spawn_spot()
	hs.capacity = 1
	var p1 := _make_fake_player()
	var p2 := _make_fake_player()
	assert_true(hs.add_occupant(p1))
	assert_false(hs.add_occupant(p2),
		"容量 1 已满,第 2 人 add_occupant 必须返 false")

func test_remove_occupant_frees_spot() -> void:
	var hs := _spawn_spot()
	var p := _make_fake_player()
	hs.add_occupant(p)
	hs.remove_occupant(p)
	assert_true(hs.can_hide(), "移除后 can_hide=true")
	assert_eq(hs.get_occupants().size(), 0)

# ── 容量 2 行为(纸箱堆) ──

func test_capacity_2_allows_two_occupants() -> void:
	var hs := _spawn_spot()
	hs.capacity = 2
	var p1 := _make_fake_player()
	var p2 := _make_fake_player()
	var p3 := _make_fake_player()
	assert_true(hs.add_occupant(p1), "纸箱堆第 1 人 OK")
	assert_true(hs.add_occupant(p2), "纸箱堆第 2 人 OK")
	assert_false(hs.can_hide(), "容量 2 满后 can_hide=false")
	assert_false(hs.add_occupant(p3),
		"纸箱堆容量 2,第 3 人必须被拒")

# ── add 同一玩家幂等 ──

func test_add_same_player_idempotent() -> void:
	var hs := _spawn_spot()
	var p := _make_fake_player()
	hs.add_occupant(p)
	hs.add_occupant(p)  # 第二次加同一 player
	assert_eq(hs.get_occupants().size(), 1,
		"重复 add 同一玩家应幂等 — occupants 计数仍 1")

# ── 交互协议 ──

func test_hiding_spot_get_prompt() -> void:
	var hs := _spawn_spot()
	hs.spot_label = "储物柜"
	var prompt: String = hs.get_prompt()
	assert_true(prompt.contains("E"), "prompt 必须含 E 键")
	assert_true(prompt.contains("储物柜"), "prompt 必须含 spot_label")

func test_hiding_spot_is_available_when_can_hide() -> void:
	var hs := _spawn_spot()
	assert_true(hs.is_available(), "空 spot is_available=true")
	var p := _make_fake_player()
	hs.add_occupant(p)
	assert_false(hs.is_available(), "容量 1 满后 is_available=false")

# ── invalid occupant 自动清理 ──

func test_invalid_occupants_auto_cleaned() -> void:
	var hs := _spawn_spot()
	var p := Node3D.new()  # 不 autofree,我们自己 free
	p.add_to_group("player")
	add_child(p)
	hs.add_occupant(p)
	p.free()  # player 已被销毁
	# get_occupants 应清掉无效引用
	var occs: Array = hs.get_occupants()
	assert_eq(occs.size(), 0,
		"get_occupants 必须自动剔除已销毁的 player 引用")
