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
