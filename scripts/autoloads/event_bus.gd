extends Node
# EventBus — 全局信号总线
signal container_approached(container)
signal container_left(container)
signal container_opened(container)
signal container_closed(container)
signal item_examined(item)
signal item_moved(item, from_grid_id, to_grid_id, x, y, rotated)
signal inventory_full
signal extracted(total_value)
signal round_ended(total_value, reason)
# v8 §4 门交互
signal door_toggled(door, is_open)
signal interact_prompt(text)
# 外卖侠 §三 时间系统:每帧广播局内时钟,给变质/UI/Logger 监听
signal round_tick(time_left, total)
# 外卖侠 §五 声音事件:动作系统/搜刮发声 → 怪物寻人系统订阅
# pos = 发声位置(玩家当前位置);radius = stance 声半径
signal sound_emitted(pos: Vector3, radius: float)
# 外卖侠 §五 怪物 catch 玩家(占位,正式版接小游戏遭遇);time_penalty = 扣多少秒
signal monster_caught_player(time_penalty: float)
