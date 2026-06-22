class_name ContainerLootTable
extends Resource

@export var entries: Array[Resource] = []  # 每项 ItemData
@export var weights: Array[int] = []        # 与 entries 同长
@export var min_count: int = 1
@export var max_count: int = 2

func roll(rng: RandomNumberGenerator) -> Array:
	var count: int = rng.randi_range(min_count, max_count)
	var total_w: int = 0
	for w in weights:
		total_w += w
	var result: Array = []
	if total_w <= 0 or entries.is_empty():
		return result
	for i in count:
		var r: int = rng.randi_range(0, total_w - 1)
		var acc: int = 0
		for j in entries.size():
			acc += weights[j]
			if r < acc:
				result.append(entries[j])
				break
	return result
