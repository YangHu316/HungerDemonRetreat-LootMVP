# v4 → v5 修复日志

按 v5 文档 §3 → §4 → §5 → §6 顺序，4 处 MINOR_MODIFY 修复全部完成。

## §3 拖拽 drag-out 模式（最关键）
- 新建 `res://scripts/drag_state.gd`（class_name DragState extends RefCounted）：拖起时立即 `from_panel.remove_entry(entry)` 并保存 original_x/y/rotated；提供 `cancel_drag()` 还原原位、`place_to(target,x,y)` 落点合法时写入新朝向。
- `scripts/ui/search_ui.gd` 全面切换到 DragState：`_on_item_pressed` / `_on_item_double_clicked` / `_quick_transfer` / `_try_drop` 全部走 drag-out 流程；落点非法 / ESC / 鼠标在 UI 外松开 → `_cancel_drag()` 自动放回原位。R 键和智能旋转沿用，并因源已移除改用 `ignore_entry=null`。

## §4 结算面板兜底
- `scripts/ui/result_panel.gd` 监听 `EventBus.round_ended`，按 `result.reason` 分支：extracted="✅ 撤离成功"金色 / timeout="⏱ 时间到 — 未撤离"暗红 / 其他="回合结束"；触发 `get_tree().paused = true`，面板/按钮 `process_mode = PROCESS_MODE_ALWAYS` 保证暂停期间仍可点击。
- `scripts/autoloads/game_session.gd::end_round`：timeout 时清空 `PlayerInventory.grid` 并 `inv.reset()`，`total_value` 设 0；非 timeout 仍按 `inv.get_total_value()` 注入。state 表新增 ROUND_END→PLAYING 合法转换。
- `scenes/result_panel.tscn` 新增 `QuitButton`，并把 `RestartButton` 改为左半侧。

## §5 撤离 race fix
- `scripts/entities/extraction_zone.gd`：监听 `round_ended` → `_abort_countdown()` + `set_process(false)` + `area.monitoring=false`；监听 `round_started` 重新启用并清 `_hovering_players` / `_counting_down=false` / `_time_began=INF`；保留 `if not gs.round_active: return` guard。
- `scripts/ui/search_ui.gd` 新增 `_on_round_ended_force_close` + `_close()` 别名，回合结束强制关闭搜刮 UI。
- `scripts/ui/extraction_progress_ui.gd` 新增 `_on_round_ended_force_hide`，强制 `panel.visible=false`。
- `scripts/autoloads/game_session.gd::end_round` 已有 `if not round_active: return` guard。

## §6 装饰（仅 MeshInstance3D 子节点，无碰撞，无 .glb / asset_gen）
- `scenes/main.tscn` 的 Player CharacterBody3D 新增 5 个装饰子 MeshInstance3D：Head(SphereMesh #f5d042) / Beak(BoxMesh #ff8c00) / EyeL+EyeR(SphereMesh #1a1a1a) / Backpack(BoxMesh #5a4a3a)。CollisionShape3D 保持单一 CapsuleShape3D 不变。
- `scripts/entities/container.gd::_apply_decor` 在运行时给 drawer/cabinet/safe 各加 Decor 子 Node3D：drawer=横向抽屉缝+圆形把手；cabinet=竖直门缝+左右两个把手；safe=圆形密码盘+四角铆钉。全部 MeshInstance3D 无碰撞。
- `scenes/main.tscn` 升级灯光与环境：DirectionalLight3D `rotation_degrees=(-50,-30,0) energy=1.2 shadow_enabled=true`；新增 WorldEnvironment（ProceduralSky 背景 / ambient 0.3 / glow 0.4 / FILMIC tonemap）。
- `scenes/main.tscn` World/Decor 节点群：2 张 DecorTable（桌面 BoxMesh + 4 条腿）+ 3 把 DecorChair（座+背+4 腿）+ 3 条深色地板装饰条 FloorStripA/B/C，全部 MeshInstance3D 无碰撞，避开走道。

## 验证
```
Compiled 25 script(s): 25 valid, 0 with errors.
Scenes validated (5 scenes): 0 errors, 0 warnings
Ran 8s: 0 errors, 0 warnings
```
