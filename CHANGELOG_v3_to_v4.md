# CHANGELOG v3 → v4

本次升级共 6 处变更，按 §3-§8 顺序执行。

## §3 / A. 逐个揭示搜刮
- 重构 `scripts/ui/search_ui.gd`：移除 v3 全局 ProgressBar，引入 `UIState { IDLE, OPENING, LOOTING }` 状态机；每个 slot 携带 `inspected/inspecting` 字段；按 (y, x) 升序逐个 inspect，每个 `INSPECT_TIME = 1.0s`；ESC 关闭时清零 `inspecting`，保留 `inspected`。
- 同步 `scripts/ui/grid_panel.gd` + `grid_item.gd` 渲染：未揭示半透 0.4 + "?" 标记；inspecting 在该 slot 中心叠加圆环进度 + 旋转放大镜（自绘 overlay）；已揭示正常显示。

## §4 / B. 搜刮键 E → F
- `project.godot` interact action 改为 `physical_keycode=70 / unicode=102`（F 键）。
- 全文替换 `按 E` → `按 F`（hud.gd + 两份 hud.tscn）。
- 撤离 UI 提示文本固定为 "停留 5 秒撤离"（`extraction_progress_ui.tscn`）。

## §5 / C. 智能旋转拖拽
- `search_ui.gd._update_drop_highlight` 增加智能旋转：先试当前 `_drag_rotated` 方向 `can_place`；若失败试反方向；任一可放则自动翻转 ghost 朝向并更新 `_drag_rotated`。
- R 键保留强制覆盖语义。

## §6 / D. 双击 + 整理
- `grid_panel.gd` 增加 `DOUBLE_CLICK_MS = 300` 双击检测 + `item_double_clicked` 信号；仅 `inspected` 的物品响应。
- `search_ui.gd._on_item_double_clicked` 实现原子 fit：`panel.remove_entry + dst.add_entry_at`，并 `emit item_moved`。
- 背包面板顶部新增 "整理" Button；按面积降序 collect → clear → auto_place（`sort_requested` 信号）。

## §7 / E. 撤离 5 秒停留
- 重写 `scripts/entities/extraction_zone.gd` 为 Duckov CountDownArea 风格：`_hovering_players` 数组、`body_entered/exited` 维护、`_process` 累计 `_elapsed`、`get_tree().paused` 时不计时、达 5s 触发 `GameSession.end_round("extracted")`。
- 信号：`countdown_started / aborted / ticked / succeeded`。
- 新增 `scripts/ui/extraction_progress_ui.gd` + `scenes/extraction_progress_ui.tscn`：屏幕中央 Panel，倒计时数字 + 圆环进度（自绘 `_draw`），仅在计时中可见。
- 撤离按键交互已删除（原 `body_entered` 直接结算逻辑被完全替换）。

## §8 / F. 跨局背包清空 + 容器再生
- `scripts/autoloads/game_session.gd.start_round()` 清空 `PlayerInventory.grid` 并调 `inv.reset()`；新增 `round_started` 信号。
- `scripts/main.gd._ready` 监听 `round_started`，遍历 group `"containers"` 调 `reset_and_regenerate()`，并把玩家送回 spawn。
- `scripts/entities/container.gd._ready` 加入 group `"containers"`；新增 `reset_and_regenerate()`：清 contents、重置 `is_searched/is_emptied/looted/opened`、还原视觉、重新 `_generate_contents()`；slot dict 增加 `inspected=false / inspecting=false` 字段。
- `scripts/ui/result_panel.gd._on_restart` 改为调 `GameSession.start_round()`（不再 `reload_current_scene`）。

## 保留契约
- 摄像机参数：pitch 55° / yaw -30° / distance 45 / FOV 20（未触碰 `camera_rig.gd` / `camera_default.tres`）。
- 全文 `load()`，无 `preload`。
- 全占位美术，未调用任何 `asset_gen_*`。
- v3 数据同步契约（拿走物品不重生）保留 — `reset_and_regenerate` 仅在 `round_started` 触发，单局内不重生。
