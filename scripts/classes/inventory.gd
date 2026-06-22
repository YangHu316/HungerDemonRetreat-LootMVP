extends RefCounted
class_name Inventory

@export var max_weight: float = 8.0

var items: Array = []

func _init(p_max_weight: float = 8.0) -> void:
	max_weight = p_max_weight

func add(item) -> bool:
	if item == null:
		return false
	if get_total_weight() + item.weight > max_weight + 0.0001:
		var bus = Engine.get_main_loop().root.get_node("/root/EventBus")
		bus.inventory_full.emit()
		return false
	items.append(item)
	return true

func get_total_weight() -> float:
	var w: float = 0.0
	for it in items:
		w += it.weight
	return w

func get_total_value() -> int:
	var v: int = 0
	for it in items:
		v += it.value
	return clampi(v, 0, 999999)

func clear() -> void:
	items.clear()
