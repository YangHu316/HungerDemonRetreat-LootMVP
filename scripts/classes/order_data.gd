class_name OrderData
extends RefCounted

# 外卖侠 §十 基础订单(MVP):"带回 N 件 Rarity 食物"
# 精确订单(具体物品)留 v2

const VALID_RARITY := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]

var rarity_required: String = "Common"
var count_required: int = 3
var reward_base: int = 100

# 完成度:在背包列表里找符合稀有度的,取 min(count, count_required)
func completion_for(items: Array) -> Dictionary:
	var matched: int = 0
	for item in items:
		var it: ItemData = item
		if it != null and it.rarity == rarity_required:
			matched += 1
	var capped: int = min(matched, count_required)
	var ratio: float = 0.0 if count_required <= 0 else float(capped) / float(count_required)
	return {
		"matched": matched,
		"capped": capped,
		"required": count_required,
		"ratio": ratio,
	}

func describe() -> String:
	return "带回 %d 件 %s 食物" % [count_required, rarity_required]

# 从池子里随机抽一个订单
static func random_basic(rng: RandomNumberGenerator = null) -> OrderData:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var o := OrderData.new()
	# 倾向常见稀有度,Legendary 概率最低
	var weights: Array = [
		["Common", 40],
		["Uncommon", 30],
		["Rare", 18],
		["Epic", 10],
		["Legendary", 2],
	]
	var total: int = 0
	for w in weights:
		total += int(w[1])
	var roll: int = rng.randi_range(0, total - 1)
	var acc: int = 0
	o.rarity_required = "Common"
	for w in weights:
		acc += int(w[1])
		if roll < acc:
			o.rarity_required = String(w[0])
			break
	# 数量:1-4 件,稀有度越高数量越少
	match o.rarity_required:
		"Common":
			o.count_required = rng.randi_range(2, 4)
		"Uncommon":
			o.count_required = rng.randi_range(2, 3)
		"Rare":
			o.count_required = rng.randi_range(1, 2)
		_:
			o.count_required = 1
	# 报酬基数 = 数量 × 稀有度系数
	var rarity_mul: int = {
		"Common": 30,
		"Uncommon": 60,
		"Rare": 120,
		"Epic": 250,
		"Legendary": 600,
	}.get(o.rarity_required, 30)
	o.reward_base = o.count_required * rarity_mul
	return o
