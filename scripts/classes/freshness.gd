class_name Freshness
extends RefCounted

# 外卖侠 §三 后半 + §十三 结算:食物 4 档新鲜度 + 价值系数
# 计时:elapsed_seconds 累计;tier_seconds = ItemData.freshness_tier_seconds(每档秒数)
# 4 档 = 3 段降档(🟢 → 🟡 → 🟠 → 🔴),tier 索引 0/1/2/3

enum Tier { FRESH, OK, STALE, ROT }

# 价值系数(§十三 文档:🟢100/🟡60/🟠30/🔴0%)
const MULTIPLIER: Array = [1.0, 0.6, 0.3, 0.0]

# 用于 UI 显示的边框色
const COLORS: Array = [
	Color(0.4, 0.95, 0.4),    # 🟢 鲜绿
	Color(0.95, 0.9, 0.3),    # 🟡 黄
	Color(0.95, 0.55, 0.2),   # 🟠 橙
	Color(0.6, 0.25, 0.25),   # 🔴 暗红
]

const ICON: Array = ["🟢", "🟡", "🟠", "🔴"]

# elapsed 秒数 → tier 索引
static func tier_for(elapsed: float, tier_seconds: float) -> int:
	if tier_seconds <= 0.0:
		return Tier.FRESH
	var idx: int = int(elapsed / tier_seconds)
	return clamp(idx, 0, Tier.ROT)

static func multiplier(tier: int) -> float:
	if tier < 0 or tier >= MULTIPLIER.size():
		return 0.0
	return float(MULTIPLIER[tier])

static func color_for(tier: int) -> Color:
	if tier < 0 or tier >= COLORS.size():
		return COLORS[0]
	return COLORS[tier]

static func icon_for(tier: int) -> String:
	if tier < 0 or tier >= ICON.size():
		return ICON[0]
	return String(ICON[tier])

# 给一个 entry 算当前 tier:非食物永远 🟢
static func entry_tier(entry: Dictionary) -> int:
	var item: ItemData = entry.get("item", null)
	if item == null or not item.is_food:
		return Tier.FRESH
	var elapsed: float = float(entry.get("freshness_elapsed", 0.0))
	return tier_for(elapsed, item.freshness_tier_seconds)

# entry 的实际价值(算变质打折后)
static func entry_value(entry: Dictionary) -> int:
	var item: ItemData = entry.get("item", null)
	if item == null:
		return 0
	var base: int = int(item.value)
	if not item.is_food:
		return base
	var tier: int = entry_tier(entry)
	return int(round(base * multiplier(tier)))
