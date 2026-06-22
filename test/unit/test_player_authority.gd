extends GutTest

# Phase 2A:player.gd 必须以 is_multiplayer_authority 守卫开头
# 否则联机时所有 peer 的 Player 都会读本地 Input,导致网络混乱

func _get_func_body(src: String, fn_name: String) -> String:
	var i: int = src.find("func %s" % fn_name)
	if i < 0:
		return ""
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	return src.substr(i, j - i)

func test_input_guards_authority() -> void:
	var src: String = load("res://scripts/entities/player.gd").source_code
	var body: String = _get_func_body(src, "_input")
	assert_ne(body, "", "应有 _input 函数")
	assert_true(body.contains("is_multiplayer_authority"),
		"player._input 必须检查 is_multiplayer_authority(否则远端 peer 的 Player 也会响应本地输入)")
	# 单机零回归:必须先判断 multiplayer_peer != null,否则单人模式
	# is_multiplayer_authority 内部调 get_unique_id 会 push error 刷屏
	assert_true(body.contains("multiplayer_peer != null") or body.contains("has_multiplayer_peer"),
		"player._input 必须先判 peer 存在,否则单机刷 error")

func test_physics_process_guards_authority() -> void:
	var src: String = load("res://scripts/entities/player.gd").source_code
	var body: String = _get_func_body(src, "_physics_process")
	assert_ne(body, "", "应有 _physics_process 函数")
	assert_true(body.contains("is_multiplayer_authority"),
		"player._physics_process 必须检查 is_multiplayer_authority")
	assert_true(body.contains("multiplayer_peer != null") or body.contains("has_multiplayer_peer"),
		"player._physics_process 必须先判 peer 存在,否则单机刷 error")

func test_guards_are_early_return() -> void:
	# 验证守卫是 early return,且检查 peer 存在(避免单机刷 error)
	var src: String = load("res://scripts/entities/player.gd").source_code
	var input_body: String = _get_func_body(src, "_input")
	assert_true(input_body.contains("not is_multiplayer_authority()") and input_body.contains("return"),
		"_input 应该 early return on no authority(联机时)")
	var phys_body: String = _get_func_body(src, "_physics_process")
	assert_true(phys_body.contains("not is_multiplayer_authority()") and phys_body.contains("return"),
		"_physics_process 应该 early return on no authority(联机时)")
