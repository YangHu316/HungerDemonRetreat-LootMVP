extends GutTest

# Phase 2A Tier 3-5:Player 改动态 spawn 架构
# 防御:main.tscn 不能再有 hardcoded Player;main.gd 必须走 _spawn_players + local_player
# player.tscn 必须挂 MultiplayerSynchronizer(否则远端 peer 看不到对方移动)

func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt: String = f.get_as_text()
	f.close()
	return txt

func test_main_tscn_has_no_hardcoded_player() -> void:
	# 老 main.tscn 在根下挂 [node name="Player"...],新架构必须删
	var txt := _read_text("res://scenes/main.tscn")
	assert_ne(txt, "", "main.tscn 应可读")
	# 不能有 hardcoded Player 节点(parent="." 表示挂在根)
	assert_false(txt.contains("[node name=\"Player\" parent=\".\""),
		"main.tscn 不能再有 hardcoded $Player(Phase 2A 改动态 spawn)")
	# 必须有 PlayersRoot 容器
	assert_true(txt.contains("[node name=\"PlayersRoot\""),
		"main.tscn 必须加 PlayersRoot 容器节点")

func test_main_gd_dynamic_spawn() -> void:
	var src: String = load("res://scripts/main.gd").source_code
	# 必须 preload Player 场景
	assert_true(src.contains("preload(\"res://scenes/entities/player.tscn\")"),
		"main.gd 必须 preload player.tscn")
	# 必须有 local_player 字段(替代旧 @onready var player = $Player)
	assert_true(src.contains("local_player"),
		"main.gd 必须有 local_player 字段")
	# 必须有 _spawn_players 入口
	assert_true(src.contains("func _spawn_players"),
		"main.gd 必须有 _spawn_players 函数")
	# 不能再有旧的 @onready var player = $Player
	assert_false(src.contains("@onready var player: CharacterBody3D = $Player"),
		"main.gd 不能再 @onready var player = $Player(已改动态 spawn)")

func test_main_gd_authority_set_in_multiplayer() -> void:
	# 多人模式必须按 peer_id set_multiplayer_authority
	var src: String = load("res://scripts/main.gd").source_code
	assert_true(src.contains("set_multiplayer_authority"),
		"main.gd 多人 spawn 必须设 multiplayer_authority(否则所有 peer 都跑物理)")

func test_player_tscn_has_synchronizer() -> void:
	# MultiplayerSynchronizer 必须挂在 player.tscn 上,且 replication_config 配好关键 path
	var txt := _read_text("res://scenes/entities/player.tscn")
	assert_ne(txt, "", "player.tscn 应可读")
	assert_true(txt.contains("MultiplayerSynchronizer"),
		"player.tscn 必须挂 MultiplayerSynchronizer")
	# 关键同步属性:位置 + 朝向 + stance
	assert_true(txt.contains("global_position"),
		"MultiplayerSynchronizer 必须同步 global_position")
	assert_true(txt.contains("BodyRoot:rotation"),
		"MultiplayerSynchronizer 必须同步 BodyRoot:rotation(玩家朝向)")
	assert_true(txt.contains("current_stance"),
		"MultiplayerSynchronizer 必须同步 current_stance(声音半径/动作档)")

func test_player_gd_no_autoload_register_in_ready() -> void:
	# 之前 player._ready() 直接调 PlayerInventory.register_local_player(self)
	# 多人模式下每个 peer 本地 spawn 3 个 Player,3 个都 register 会覆盖本地指针
	# 现在改由 main.gd._bind_local 在确认是本地 player 后再 register
	var src: String = load("res://scripts/entities/player.gd").source_code
	# 找 _ready 函数体
	var i: int = src.find("func _ready")
	assert_gte(i, 0, "应有 _ready 函数")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var ready_body: String = src.substr(i, j - i)
	assert_false(ready_body.contains("pinv.register_local_player"),
		"player.gd._ready 不能再 register 到 PlayerInventory(多人会覆盖)")
	assert_false(ready_body.contains(".register_local_player(self)"),
		"player.gd._ready 不能 register_local_player(self) 任何 autoload")
