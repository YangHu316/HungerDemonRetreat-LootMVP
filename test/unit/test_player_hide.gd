extends GutTest

# 外卖侠 §06 玩家躲避系统 — Player hide/unhide 状态
# 防御 spec 06_玩家躲避系统.md:
#   - E 键(InputMap action "hide")
#   - is_hidden_now()/hide_in(spot)/unhide() API
#   - 躲藏中 movement_locked=true / _tick_sound_emit skip
#   - _input "hide" 分支必须在 movement_locked 检查前(否则进了出不来)
#   - 容量满时 hide_in 不进入

const PlayerScript := preload("res://scripts/entities/player.gd")
const HidingSpotScript := preload("res://scripts/entities/hiding_spot.gd")

# ── InputMap ──

func test_project_godot_has_hide_action() -> void:
	# project.godot 必须有 hide action(E 键 keycode 69)
	var f := FileAccess.open("res://project.godot", FileAccess.READ)
	assert_not_null(f, "project.godot 必须能读")
	var content: String = f.get_as_text()
	f.close()
	assert_true(content.contains("hide={"),
		"project.godot 必须有 hide action")
	# E 键 keycode 69
	var i: int = content.find("hide={")
	var section: String = content.substr(i, 400)
	assert_true(section.contains("69"),
		"hide action 必须绑定 E (keycode 69)")

# ── 源码层契约 ──

func test_player_has_hide_methods() -> void:
	var src: String = load("res://scripts/entities/player.gd").source_code
	assert_true(src.contains("func is_hidden_now"),
		"Player 必须有 is_hidden_now() 方法(给 monster 调用)")
	assert_true(src.contains("func hide_in"),
		"Player 必须有 hide_in(spot) 方法")
	assert_true(src.contains("func unhide"),
		"Player 必须有 unhide() 方法")
	assert_true(src.contains("var is_hidden"),
		"Player 必须有 is_hidden 字段")

func test_player_has_nearby_hiding_spot_api() -> void:
	var src: String = load("res://scripts/entities/player.gd").source_code
	assert_true(src.contains("func set_nearby_hiding_spot"),
		"Player 必须有 set_nearby_hiding_spot(spot)(HidingSpot.body_entered 调)")
	assert_true(src.contains("func clear_nearby_hiding_spot"),
		"Player 必须有 clear_nearby_hiding_spot(spot)")

func test_player_input_has_hide_branch_before_movement_locked() -> void:
	# 关键:_input 的 hide 分支必须在 movement_locked 检查前
	# 否则躲藏中 movement_locked=true,E 按了被吞,玩家出不来
	var src: String = load("res://scripts/entities/player.gd").source_code
	var i: int = src.find("func _input")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	var hide_idx: int = body.find("\"hide\"")
	var locked_idx: int = body.find("if movement_locked")
	assert_true(hide_idx > 0, "_input 必须处理 hide action")
	assert_true(locked_idx > 0, "_input 必须有 movement_locked 守卫")
	assert_lt(hide_idx, locked_idx,
		"hide 分支必须在 movement_locked 检查前(否则躲藏中 E 出不来)")

func test_player_tick_sound_emit_skips_when_hidden() -> void:
	var src: String = load("res://scripts/entities/player.gd").source_code
	var i: int = src.find("func _tick_sound_emit")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("is_hidden"),
		"_tick_sound_emit 必须查 is_hidden(躲藏中声半径 ≈ 0)")

# ── 行为测试(用 spawn 实例) ──

func _spawn_player() -> Node:
	var p := CharacterBody3D.new()
	p.set_script(PlayerScript)
	add_child_autofree(p)
	return p

func _spawn_spot(capacity: int = 1) -> Node:
	var hs := Node3D.new()
	hs.set_script(HidingSpotScript)
	add_child_autofree(hs)
	hs.capacity = capacity
	return hs

func test_player_default_not_hidden() -> void:
	var p := _spawn_player()
	assert_false(p.is_hidden, "默认 is_hidden=false")
	assert_false(p.is_hidden_now(), "is_hidden_now() 默认 false")

func test_player_hide_sets_state() -> void:
	var p := _spawn_player()
	var hs := _spawn_spot(1)
	p.hide_in(hs)
	assert_true(p.is_hidden, "hide_in 后 is_hidden=true")
	assert_true(p.is_hidden_now(), "hide_in 后 is_hidden_now()=true")
	assert_true(p.movement_locked, "hide_in 后 movement_locked=true")
	assert_true(hs.has_occupant(p), "hide_in 后 spot.has_occupant(player)=true")

func test_player_unhide_resets_state() -> void:
	var p := _spawn_player()
	var hs := _spawn_spot(1)
	p.hide_in(hs)
	p.unhide()
	assert_false(p.is_hidden, "unhide 后 is_hidden=false")
	assert_false(p.movement_locked, "unhide 后 movement_locked=false")
	assert_false(hs.has_occupant(p), "unhide 后 spot 不再含 player")

func test_player_hide_rejected_when_spot_full() -> void:
	var p1 := _spawn_player()
	var p2 := _spawn_player()
	var hs := _spawn_spot(1)  # 容量 1
	# 用第一个 player 占位(直接 add_occupant 模拟另一玩家已躲)
	hs.add_occupant(p1)
	p2.hide_in(hs)
	assert_false(p2.is_hidden,
		"容量已满,hide_in 必须被拒(is_hidden 不变)")

func test_player_hide_idempotent() -> void:
	# 已躲时再调 hide_in 应该 no-op(防重复 add_occupant)
	var p := _spawn_player()
	var hs := _spawn_spot(2)
	p.hide_in(hs)
	p.hide_in(hs)
	assert_eq(hs.get_occupants().size(), 1,
		"重复 hide_in 应幂等 — occupants 不重复加")

func test_player_unhide_when_not_hidden_is_noop() -> void:
	var p := _spawn_player()
	# 未躲过,直接调 unhide 应 no-op
	p.unhide()
	assert_false(p.is_hidden, "unhide 未躲时 is_hidden 仍 false")
	assert_false(p.movement_locked, "unhide 未躲时 movement_locked 仍 false")

func test_player_set_nearby_hiding_spot() -> void:
	var p := _spawn_player()
	var hs := _spawn_spot()
	p.set_nearby_hiding_spot(hs)
	# 通过 _nearby_hiding_spot 触发 hide
	p.hide_in(p._nearby_hiding_spot)
	assert_true(p.is_hidden, "set_nearby_hiding_spot 后通过 _nearby_hiding_spot hide 应成功")

func test_player_clear_nearby_hiding_spot() -> void:
	var p := _spawn_player()
	var hs := _spawn_spot()
	p.set_nearby_hiding_spot(hs)
	p.clear_nearby_hiding_spot(hs)
	assert_eq(p._nearby_hiding_spot, null,
		"clear_nearby_hiding_spot 后 _nearby_hiding_spot=null")
