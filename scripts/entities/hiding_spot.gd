extends Node3D
class_name HidingSpot

# 外卖侠 §06 玩家躲避系统:躲藏点(spec 06_玩家躲避系统.md / 03 §九)
# - 容量 1 (储物柜/床底/桌底) 或 2 (纸箱堆)
# - 被发现概率:储物柜 10% / 床底 20% / 纸箱堆 20% / 桌底 35%
# - 仅当怪物在 SEARCH 态、极近(1.5m)时判一次(由 monster.gd 调用)
# - 躲藏中:玩家声半径=0(player skip emit) + 怪物视野返 false
# - 无屏息条 / 无 QTE,玩家随时按 E 出来

@export var capacity: int = 1
@export var detection_prob: float = 0.20
@export var spot_label: String = "储物柜"

var _occupants: Array = []

@onready var visual: MeshInstance3D = $Visual if has_node("Visual") else null
@onready var interact_area: Area3D = $InteractArea if has_node("InteractArea") else null
@onready var anchor: Marker3D = $Anchor if has_node("Anchor") else null

func _ready() -> void:
	add_to_group("hiding_spots")
	add_to_group("interactables")
	if interact_area != null:
		if not interact_area.body_entered.is_connected(_on_body_entered):
			interact_area.body_entered.connect(_on_body_entered)
		if not interact_area.body_exited.is_connected(_on_body_exited):
			interact_area.body_exited.connect(_on_body_exited)

# ── 容量管理 ──
func can_hide() -> bool:
	return _occupants.size() < capacity

func add_occupant(player: Node) -> bool:
	if not can_hide():
		return false
	if _occupants.has(player):
		return true
	_occupants.append(player)
	return true

func remove_occupant(player: Node) -> void:
	_occupants.erase(player)

func get_occupants() -> Array:
	# 返回引用副本(防外部修改)
	var out: Array = []
	for p in _occupants:
		if is_instance_valid(p):
			out.append(p)
	# 同时清掉无效引用
	_occupants = out.duplicate()
	return out

func has_occupant(player: Node) -> bool:
	return _occupants.has(player)

# ── 玩家邻接侦测(给 player.gd 用) ──
func _on_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if body.has_method("set_nearby_hiding_spot"):
		body.set_nearby_hiding_spot(self)

func _on_body_exited(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if body.has_method("clear_nearby_hiding_spot"):
		body.clear_nearby_hiding_spot(self)

# ── 交互协议(与 container/door 一致风格) ──
func get_interact_position() -> Vector3:
	return global_position

func get_prompt() -> String:
	# 玩家若已在此躲点中 → 提示出来
	# (player 自己读 is_hidden 决定 UI;这里给通用 prompt)
	return "按 E 躲 [%s]" % spot_label

func is_available() -> bool:
	return can_hide()
