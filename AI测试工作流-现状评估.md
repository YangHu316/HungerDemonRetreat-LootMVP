# AI 测试工作流 — 现状评估（v2 完整范围）

> 第一轮评估只读了 designs/ 下 v2/v3 三份，本轮按你选的方案 B 已读完 [CHANGELOG_v3_to_v4](CHANGELOG_v3_to_v4.md) ~ [CHANGELOG_v12_to_v13](CHANGELOG_v12_to_v13.md) 共 10 份增量，可测模块从 8 个扩到 17 个，Stamina 数值锚已找到。
> 看完后告诉我**哪些确认、哪些要调整**，我再进入第 2 步（搭基础设施）。

---

## 1. v3 → v13 增量里新增的可测/可埋日志模块

### 1.1 v4-v13 引入的纯逻辑模块（GUT 单测）

| # | 模块 | 文件 | 来源 | 测试要点 |
|---|------|------|------|---------|
| L9 | **DragState 流** | [scripts/drag_state.gd](scripts/drag_state.gd) | [v5 §3](CHANGELOG_v4_to_v5.md) | 拖起立即 `remove_entry`；`cancel_drag()` 还原 original_x/y/rotated；`place_to(target,x,y)` 落点合法时 commit；ESC/UI 外松开 → cancel 路径 |
| L10 | **智能旋转放置** | [scripts/ui/search_ui.gd](scripts/ui/search_ui.gd) `_update_drop_highlight` | [v4 §5](CHANGELOG_v3_to_v4.md) | 先试当前 rotated，失败再试反向；任一可放即翻转 ghost。这部分逻辑应抽成纯函数（接受 grid + item + xy + rotated → 返回 final_rotated 或 null），抽出后可测 |
| L11 | **双击 + 整理** | [scripts/ui/grid_panel.gd](scripts/ui/grid_panel.gd) | [v4 §6](CHANGELOG_v3_to_v4.md) | DOUBLE_CLICK_MS=300 间隔检测；整理时按 entry 面积（grid_w×grid_h）降序 collect → clear → auto_place |
| L12 | **ExtractionZone 5s 倒计时** | [scripts/entities/extraction_zone.gd](scripts/entities/extraction_zone.gd) | [v4 §7](CHANGELOG_v3_to_v4.md) + [v5 §5](CHANGELOG_v4_to_v5.md) + [v6 §3](CHANGELOG_v5_to_v6.md) | `get_tree().paused` 不计时；5s 达到触发 `end_round("extracted")`；round_ended 后 abort + monitoring=false；round_started 后 deferred 重启 monitoring + 主动遍历 overlapping。**注意**：节点+物理依赖重，建议把"5s 累计"和"abort 重置"逻辑抽到 RefCounted 上单测，物理触发部分只做集成 smoke |
| L13 | **Stamina（数值锚已锁定）** | [scripts/autoloads/stamina.gd](scripts/autoloads/stamina.gd) | [v6 §4](CHANGELOG_v5_to_v6.md) **MAX=100 / DRAIN=25 / RECOVER=18 / DELAY=0.7 / MIN_TO_START_RUN=8** | `try_start_run` 在 locked/value=0 时 false；exhausted 后 _is_locked=true 直到 value≥MIN_TO_START_RUN；DELAY 期内不恢复；DRAIN/RECOVER 速率（用确定 delta 调用 `_drain`/`_recover` 验数值） |
| L14 | **interact 键 E→F** | [project.godot](project.godot) input action `interact` | [v4 §4](CHANGELOG_v3_to_v4.md) | 这一项不是单测，是**契约测试**：assert project.godot 里 interact 绑的是 keycode 70（F）。一旦谁误改回 E，CI 立刻拦下 |
| L15 | **player FALL_THRESHOLD respawn** | [scripts/entities/player.gd](scripts/entities/player.gd) | [v8 §3](CHANGELOG_v7_to_v8.md) FALL_THRESHOLD=-1.5 / RESPAWN_POS=(0,1,0) | y < -1.5 → 传送回 (0,1,0)。物理依赖重，建议**只在集成 smoke 跑**而非纯单测 |
| L16 | **player nearest interactable 选择** | player.gd `_candidates` + `_update_nearest_interactable` | [v8 §4](CHANGELOG_v7_to_v8.md) | register/unregister 维护数组；多候选时按欧几里得距离选最近；候选清空时清 _nearest |
| L17 | **Door 状态 + 跨局 reset** | [scripts/entities/door.gd](scripts/entities/door.gd) | [v8 §4](CHANGELOG_v7_to_v8.md) + [v9 §4](CHANGELOG_v8_to_v9.md) | toggle 翻转 is_open + 信号；reset_state 强制 rotation=ZERO + collision 重启 + disabled=false 兜底 |

### 1.2 v4-v13 的"感觉/视觉"模块（不写单测，按需埋日志）

这些不进 GUT，只在出问题时靠 Logger.event + 玩家按 F12 标记定位：

- **search_ui UIState 状态机**（v4 §3）—— IDLE/OPENING/LOOTING 切换 + 逐个 inspect 计时。可埋 `ui.state_change`、`ui.inspect_complete`。
- **chibi 动画**（v6 §5、v7 动画、v8 §3-4、v10 §3-4、v11 §3）—— 整套四肢摆动+反向摆臂修复。**纯视觉**，但 v9-v11 反复修同一个反向摆臂 bug 三次说明它**值得一个契约测试**：v11 里有 4 个 @export 的 sign 字段，最终值都是 -1.0，可以加测试 `assert player.tscn 里这些 sign 默认值都是 -1.0`，防止再次被人误改回去。
- **关卡构建**（v6 §1-3、v7、v9 §5、v10 §5、v11 §4-6、v12、v13）—— `main.gd._build_walls / _build_windows / _build_extra_decor` 等程序化生成。可埋 `level.build_complete`（节点数、墙段数）做基线对比。
- **门 collision + 动画**（v8 §4、v9 §4）—— 物理触发，靠玩验证。

### 1.3 取消的内容

- v3 §B 引入的"全局 ProgressBar + Magnifier"在 v4 §3 已被**整体删除**，改成 per-slot 逐个揭示。`scripts/ui/magnifier_widget.gd` 实际还在但已经没人用——这是 [v3_upgrade_spec.md](designs/v3_upgrade_spec.md) §E 标的"删除（可选保留）"。给它写测试是浪费。
- 第一轮评估里的 L1-L8 全部仍然有效，无需修改。

---

## 2. 完整可测模块清单（汇总）

| # | 模块 | 优先级 | 备注 |
|---|------|--------|------|
| L1 | GridInventory | **P0** | 算法纯、断言点最多，**第一个测试就选它** |
| L2 | GridPlacer.find_first_fit | **P0** | 算法纯，跟 L1 一起写 |
| L3 | PlayerInventory | P1 | 5×4 形状 + inventory_full 信号 |
| L4 | GameSession | P1 | 倒计时 + 状态机 + timeout 清空背包契约 |
| L5 (=L13) | Stamina | P1 | 数值锚已锁定 |
| L6 | ContainerLootTable.roll | P1 | 用固定 seed 验权重比例 |
| L7 | ItemData .tres 数值 | **P0** | 防数值被误改的护栏，**写起来最便宜** |
| L8 | Container 数据驱动 getter | P2 | 抽出静态部分单测 |
| L9 | DragState 流 | P1 | RefCounted，纯逻辑 |
| L10 | 智能旋转 | P2 | 先抽出纯函数再测 |
| L11 | 双击+整理 | P2 | 双击间隔好测，auto_place 排序好测 |
| L12 | ExtractionZone 5s | P2 | 抽逻辑出来，物理部分跳过 |
| L14 | interact=F 契约 | **P0** | 一行 assert，立刻能拦回退 |
| L15 | player respawn | P3 | 集成 smoke，不进单测 |
| L16 | nearest interactable | P2 | |
| L17 | Door 状态+reset | P2 | |
| **L18** | **player.tscn anim sign 契约** | P1 | v9-v11 反复修反向摆臂 3 次的教训，钉死 4 个 @export sign 默认值 |

**P0 一共 4 项**（L1/L2/L7/L14）—— 这是第一周的目标，能拿到"第 5 节 7 步闭环跑通"+ 4 张护栏，足够立刻产生价值。
**P1 一共 6 项**，第二周补完。
**P2-P3 看预算再排**。

---

## 3. 感觉模块的 Logger 事件命名（草案）

| 事件 | data 字段 | 触发点 |
|------|----------|--------|
| `round.start` | `{}` | GameSession.start_round |
| `round.end` | `total, reason` | GameSession.end_round |
| `stamina.run_start` | `{value}` | Stamina.try_start_run 成功 |
| `stamina.exhausted` | `{}` | Stamina._drain 触发 |
| `stamina.recovered` | `{}` | Stamina._recover 解锁 |
| `container.approach` | `{type, id}` | EventBus.container_approached |
| `container.open` | `{type, search_time, grid_size}` | container.open |
| `container.search_progress` | `{progress}` | search_ui inspect 推进（节流，每 200ms 一条） |
| `container.close` | `{is_emptied}` | container.close |
| `inventory.place` | `{item_id, x, y, rotated}` | PlayerInventory.place_entry 成功 |
| `inventory.remove` | `{item_id}` | PlayerInventory.remove_entry |
| `inventory.full` | `{tried_item_id}` | EventBus.inventory_full |
| `ui.drag_start` | `{item_id, from}` | DragState init |
| `ui.drag_drop` | `{item_id, to, rotated}` | DragState.place_to 成功 |
| `ui.drag_cancel` | `{item_id, reason}` | cancel_drag |
| `ui.quick_transfer` | `{item_id, from, to, ok}` | 右键转移 |
| `ui.rotate` | `{item_id}` | R 键 |
| `extraction.enter` | `{}` | extraction_zone body_entered |
| `extraction.tick` | `{elapsed}` | _process（每 1s 一条，避免刷屏） |
| `extraction.complete` | `{}` | succeeded |
| `extraction.abort` | `{reason}` | aborted |
| `door.toggle` | `{id, is_open}` | Door.toggle |
| `player.respawn` | `{prev_pos}` | FALL_THRESHOLD 触发 |
| `user.mark` | `{note}` | F12（已在 prompt §3.1） |

---

## 4. 基础设施缺口（更新）

| 项 | 状态 | 备注 |
|---|------|------|
| GUT addon | ❌ 不存在 | |
| `test/` 目录 | ❌ 不存在 | |
| `.github/workflows/test.yml` | ❌ 不存在 | |
| Logger autoload | ❌ 不存在 | |
| CLAUDE.md 测试纪律章节 | ❌ 不存在 | |
| **Godot MCP 工具链** | ⚠️ **半就绪**：进程已启动（`verify_api_key` 有响应），但 **`GODOT_API_KEY` 未配置**，`get_debug_errors` 因此失败。这不是"连接问题"，是认证缺失——需要你在 `.mcp.json` 的 `env.GODOT_API_KEY` 字段填值。在我能扫到当前编译错误之前，无法确认"工程当前是否全绿" | |
| Git 仓库 | ❌ **未初始化** | CI 链路前置 |

---

## 5. 已发现的不一致

- [README.md](README.md) 多处过时（4×5、E 键、斜仰视错别字、调参位置写的是 v2 字段名）。我会**精修关键 4 项**：4×5→5×4、E→F、"搜别"→"搜刮"、"斜仰视"→"斜俯视"。其他过时部分等大改时再说。
- [project_state.md](project_state.md) 文件头第 2 行写明 **"Auto-generated. Do not edit manually."**，里面的 "v8" 是某个生成脚本写的。我**不会改**这个文件——改了下次生成会被覆盖，等于做无用功。要修得修生成它的工具/工作流（不在我现在的范围内）。先在评估里点出来，给你决定。
- Stamina 数值出处现已锁定到 [CHANGELOG_v5_to_v6.md](CHANGELOG_v5_to_v6.md) §4。L13 测试可以直接以这份 changelog 的常量为期望值。

---

## 6. 我接下来的计划

等你点头后：

1. 你帮忙：**配 GODOT_API_KEY** + 在 Godot 编辑器启动项目让 godot_mcp 服务可用 → 我跑 `get_debug_errors` 把当前编译错误清零（如有）
2. 你帮忙：**`git init` + 推到 GitHub**（CI 前置）
3. 装 GUT addon、建 `test/` 骨架
4. 按 P0 顺序写 4 张护栏：**ItemData .tres 数值（L7）→ GridInventory（L1）→ GridPlacer（L2）→ interact=F 契约（L14）**
5. 写 `.github/workflows/test.yml`，跑通 prompt §5 的 7 步闭环
6. 加 Logger autoload + CLAUDE.md 测试纪律
7. 给容器开/关搜刮埋 Logger 事件验证日志链路
