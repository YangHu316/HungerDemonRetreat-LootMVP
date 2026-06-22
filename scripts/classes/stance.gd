class_name Stance
extends RefCounted

# 外卖侠 §四 动作系统:三档移动(潜行/走路/奔跑)
# 每档对应"移速 + 声音半径",声音半径给 §五 声音系统输入
# 优先级:同时按 sneak+sprint → SNEAK 优先(安全比效率重要)

enum Mode { SNEAK, WALK, RUN }

# 移速(米/秒) — 来自现有 player.gd 数值 + 文档 §四 三档语义
const SNEAK_SPEED: float = 1.5
const WALK_SPEED: float = 4.5
const RUN_SPEED: float = 7.5

# 声音半径(米) — 文档 §四 / §五 表 7
# 潜行 ~1.5m 近乎无声,走路 ~5m 低噪,奔跑 ~12m 高噪
const SNEAK_SOUND_RADIUS: float = 1.5
const WALK_SOUND_RADIUS: float = 5.0
const RUN_SOUND_RADIUS: float = 12.0

# 输入 + 体力状态 → 决定档位
static func resolve(wants_sneak: bool, wants_run: bool, can_run: bool) -> int:
	# 同时按潜行 + 冲刺 → 潜行优先(安全比效率重要)
	if wants_sneak:
		return Mode.SNEAK
	if wants_run and can_run:
		return Mode.RUN
	return Mode.WALK

static func speed(mode: int) -> float:
	match mode:
		Mode.SNEAK:
			return SNEAK_SPEED
		Mode.RUN:
			return RUN_SPEED
		_:
			return WALK_SPEED

static func sound_radius(mode: int) -> float:
	match mode:
		Mode.SNEAK:
			return SNEAK_SOUND_RADIUS
		Mode.RUN:
			return RUN_SOUND_RADIUS
		_:
			return WALK_SOUND_RADIUS
