class_name ItemData
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var value: int = 0
@export var rarity: String = "Common"  # Common/Uncommon/Rare/Epic/Legendary
@export var color: Color = Color.WHITE
@export var grid_w: int = 1
@export var grid_h: int = 1
# 外卖侠 §三 后半:食物变质
# 非食物物品(钥匙/武器/战利品)is_food=false,不会变质
@export var is_food: bool = false
# 每个新鲜度档持续多少秒(从 🟢 → 🟡 → 🟠 → 🔴 共 3 段降档)
@export var freshness_tier_seconds: float = 90.0
