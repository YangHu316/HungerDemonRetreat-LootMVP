extends GutTest

# P0 护栏 #4: interact=F 输入契约
# 防御对象: 评估文档 §3.4 — README 写"按 F 搜刮",
# 一旦 InputMap 改键或 container 协议被破坏,UI 提示与实际不一致

const KEY_F := 70

func test_interact_action_exists_and_uses_F() -> void:
	assert_true(InputMap.has_action("interact"), "interact action 必须存在")
	var has_f := false
	for ev in InputMap.action_get_events("interact"):
		if ev is InputEventKey:
			# physical_keycode 优先,fallback keycode
			var k: int = (ev as InputEventKey).keycode
			var pk: int = (ev as InputEventKey).physical_keycode
			if k == KEY_F or pk == KEY_F:
				has_f = true
				break
	assert_true(has_f, "interact 必须绑定 F (keycode=70)")

func test_container_implements_interactables_protocol() -> void:
	# 不实例化 container.tscn(需要场景树),只验脚本符号
	var script: GDScript = load("res://scripts/entities/container.gd")
	assert_not_null(script)
	var src: String = script.source_code
	# 协议四件套
	for method in ["get_interact_position", "get_prompt", "is_available", "interact"]:
		assert_true(
			src.contains("func %s" % method),
			"container.gd 必须定义 %s()" % method
		)
	# 必须自登记进 interactables 组
	assert_true(
		src.contains("add_to_group(\"interactables\")"),
		"container.gd 必须 add_to_group(\"interactables\")"
	)

func test_player_consumes_interact_action() -> void:
	var script: GDScript = load("res://scripts/entities/player.gd")
	assert_not_null(script)
	assert_true(
		script.source_code.contains("is_action_pressed(\"interact\")"),
		"player.gd 必须监听 interact action"
	)

func test_main_consumes_interact_action_for_container() -> void:
	var script: GDScript = load("res://scripts/main.gd")
	assert_not_null(script)
	assert_true(
		script.source_code.contains("is_action_pressed(\"interact\")"),
		"main.gd 必须监听 interact action(打开搜刮 UI)"
	)

func test_container_prompt_text_mentions_F() -> void:
	# README 与 UI 提示一致性: "按 F 搜刮"
	var script: GDScript = load("res://scripts/entities/container.gd")
	assert_true(
		script.source_code.contains("按 F 搜刮"),
		"container 的提示文案必须包含 '按 F 搜刮'(README 契约)"
	)
