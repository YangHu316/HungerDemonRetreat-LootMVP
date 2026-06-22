# CLAUDE.md — HungerDemonRetreat_LootMVP 工作纪律

> 这个文件只写**怎么协作**和**怎么提交**。游戏设计内容请看 [README.md](README.md)、[designs/](designs/)、[CHANGELOG_*.md](.)。

## 项目快照

- **引擎**: Godot 4.6(本地用 4.6.2/4.6.3,CI 锁 4.6.2)
- **类型**: 3D 斜俯视 + 网格搜刮（"饿魔退散"MVP）
- **autoload**: `EventBus` / `GameSession` / `PlayerInventory` / `Stamina` / `Logger`
- **入口**: `res://scenes/main.tscn`(由 `project.godot run/main_scene` 决定)
- **不要手改的**: `project_state.md`(auto-gen)、`.godot/`(cache)

## 测试与日志纪律

> 这套纪律是 [AI测试工作流-现状评估.md](AI测试工作流-现状评估.md) 落地版,改动代码前必读。

### 双轨原则

| 链路 | 工具 | 验什么 | 不验什么 |
| --- | --- | --- | --- |
| **测试** | GUT (`test/unit/*.gd`) | 纯逻辑、数值、规则、契约 | 手感、节奏、玩家感知 |
| **日志** | Logger (autoload, JSONL) | 事件顺序、链路完整性、玩家感知 | 数值正确性、单元算法 |

**不要混用**:
- 不用单测验"打击感"或"音效是否舒服"。
- 不用日志验"伤害公式"或"价值结算"——那是 GUT 的事。

### 改动前的 7 步闭环（prompt §5）

每次写新功能或改公共行为,严格按这个顺序:

1. **写 / 改 GUT 测试**(`test/unit/test_<module>.gd`)
2. **本地跑 GUT,确认新测试红**(没红就是测试本身没拦住)
3. **改业务代码,让测试转绿**
4. **本地跑全量 GUT,确认 23+/23+ 全绿**
5. **如果涉及玩家感知**(开关/搜刮/撤离),手动跑一局,看 `user://logs/run_*.jsonl` 链路是否完整
6. **故意把代码改坏一次**,确认 GUT 拦住(防御回归测试)
7. **CI 绿灯后再合**

### 本地跑测试

**PowerShell**(默认):
```powershell
cd "C:\Users\vicyanghu\Downloads\game_20260609_200021"
& "C:\Users\vicyanghu\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json
```

**git-bash / WSL**:
```bash
"/c/Users/vicyanghu/Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json
```

输出 `Results saved to res://test_results.xml`(JUnit 格式,CI 上传 artifact)。

### 测试目录约定

- `test/unit/test_<module>.gd`: 纯逻辑单测,不依赖场景树。继承 `GutTest`。
- 不要写需要真 `_physics_process` / 渲染 / 输入回放的"测试" — 那是手测的事。
- 测试不能依赖 autoload 状态(如 `GameSession.round_active`),需要 stub 的话用 `GutTest.add_child_autofree`。

### Logger 用法

**默认走订阅 EventBus**:
- 在 `event_bus.gd` 加 signal → Logger 在 `_subscribe_bus()` 里加一条 `connect`。
- 业务代码只需 `EventBus.<signal>.emit(...)`,日志自动写。

**边角直埋**(签名不在 EventBus 上、或是临时验证):
```gdscript
Logger.event("some_local_check", {"x": 42})
```

**关掉日志**:`Logger.enabled = false`(测试期不需要,GUT 不依赖 Logger)。

### 已覆盖的事件(免费,EventBus 路由)

`container_approached / container_left / container_opened / container_closed / item_examined / item_moved / inventory_full / extracted / round_ended / door_toggled / round_tick`

### 搜打撤纪律(2026-06-22 用户确立)

**"拿到不算,撤出来才算"**。这条规则压在所有 UI 设计上:

- HUD 不能实时显示订单进度 `X/N` —— 物品在搜刮 UI 里 container ↔ inventory 来回拖时,数字跳来跳去,看着像物品被吞
- HUD 只显示**订单需求 + "撤出后结算"提示**
- 真正的完成度计算 + 报酬,只在 **result_panel**(撤离/迷失页)显示
- 同样适用于后续任何"实时反馈" UI:背包内物品状态、变质档色等。能不实时跟随就不要实时跟随,玩家完成动作后再结算

### 还没覆盖的(后续 P1)

`item_inspecting / item_inspected_done / sprint_started / stamina_drain / search_progress_tick` — 需要 EventBus 加 signal + 业务代码 emit。

## 现有 P0 测试覆盖

| 文件 | 防御对象 |
| --- | --- |
| [test/unit/test_item_data_tres.gd](test/unit/test_item_data_tres.gd) | 所有 `resources/items/*.tres` 数值合法性、id 唯一性 |
| [test/unit/test_grid_inventory.gd](test/unit/test_grid_inventory.gd) | 4×5 网格放置/旋转/重叠/越界 |
| [test/unit/test_grid_placer.gd](test/unit/test_grid_placer.gd) | `find_first_fit` 扫描顺序 + 旋转 fallback |
| [test/unit/test_interact_contract.gd](test/unit/test_interact_contract.gd) | F 键契约(InputMap + container 协议 + main/player 监听) |
| [test/unit/test_game_session_time.gd](test/unit/test_game_session_time.gd) | §三 时间系统:ROUND_TIME=900s 硬上限 / EXTRACT_TIME=10s / tick 倒计时 / timeout=迷失清空 / 撤离保留 / round_tick signal |
| [test/unit/test_stance.gd](test/unit/test_stance.gd) | §四 动作三档:enum 顺序 / 移速 1.5/4.5/7.5 / 声音半径 1.5/5/12 / resolve 优先级(sneak > sprint,体力不够退回 walk) |
| [test/unit/test_stash.gd](test/unit/test_stash.gd) | §九 仓库 + 跨局背包:Stash add/remove/json 往返 / 背包<>仓库 transfer / 满背包不丢仓库 / start_round 不清背包 / extracted 保留 / timeout 清背包不动仓库(搜打撤纪律) |
| [test/unit/test_container_repeatable.gd](test/unit/test_container_repeatable.gd) | 容器第一次开后**仍可重复打开**:looted 字段已删 / is_available 只看 opened / open 必设 has_been_opened(不是 is_searched 否则跳过 inspect 流程) / main/hud/search_ui 不再屏蔽 |
| [test/unit/test_home_sort_safety.gd](test/unit/test_home_sort_safety.gd) | home 整理按钮**不能丢 entry**(原代码 continue 会丢,改成 break + 回滚) |
| [test/unit/test_order.gd](test/unit/test_order.gd) | §十 订单系统 MVP:OrderData/random_basic/completion_for(matched/capped/ratio) / OrderPool 候选-接单-清空状态机 / completion_for_inventory |
| [test/unit/test_grid_panel_safety.gd](test/unit/test_grid_panel_safety.gd) | grid_panel 反复拖动不能累积幽灵 view + 双击残留(2026-06-22 用户反复 container↔inventory 拖物品报"被吞") / _process 必须有 grid==null 守卫(2026-06-22 search_ui 中 GridPanel setup 前 _process 跑炸 Nil.entries) / _update_value_label 同 |
| [test/unit/test_freshness.gd](test/unit/test_freshness.gd) | §三 后半 + §十三 食物变质 4 档:tier_for 数学/clamp / multiplier [1.0,0.6,0.3,0.0] / entry_value 非食物原价+食物打折 / GameSession.tick 只推进食物不推非食物 / Stash 不变质(GameSession 不迭代 stash) / get_total_value 自然带打折 / transfer_to/from_stash 保留 freshness_elapsed |
| [test/unit/test_double_click_safety.gd](test/unit/test_double_click_safety.gd) | 双击防误触:_try_drop 检测"源 panel 同 cell 同 rot" → cancel_drag 不 emit item_moved(2026-06-22 用户双击食物报"复制":双击 click 1 release 落同位置产生噪音 item_moved,与 click 2 双击转移叠加视觉抖动) |
| [test/unit/test_dict_as_key.gd](test/unit/test_dict_as_key.gd) | **Godot 4 Dictionary 陷阱**:mutable Dictionary 作 dict key,key 内容变化后 has/erase 失效。grid_panel.item_views 改用 entry 稳定 int uid 作 key,绝不能回退用 entry Dictionary(2026-06-22 用户反复 inv↔container 拖食物,看到 1 个面包变 4 个;根因是旧 view 不被 free 累积,数据层正常) |

跑全量 = 106 测试 / 425+ assert。

## 已知小 bug(P2,先记录不修)

(暂无)

## CI

- Workflow: [.github/workflows/test.yml](.github/workflows/test.yml)
- 触发: push / PR 到 `main` 或 `master`
- 步骤: 拉 Godot 4.6.2 linux → 跑 GUT → 上传 JUnit XML

## 协作约定

> **协作宪法(2026-06-17 用户明确强调,违反就是发火点)**:
>
> 1. **用户不懂技术,描述未必准确**。"画面有毛病"可能是镜头位置、UI 错位、地图缺屋顶,不只是渲染。**不要按字面词跳进技术细节**。
> 2. **每个需求按 PM 思维三步走**:
>    - Step 1: 复述确认("我理解你说的是 X,对吗?")
>    - Step 2: 列 SOP 排查路径(ABC 选项 + 代价/收益)
>    - Step 3: 用户确认后才动手
>    **不要看到截图就闷头摸 main.tscn / shader / Environment**。
> 3. **用户发火 = 重复犯错或低级错**。立刻回上下文找根因 + 把"不再犯"规则更新到本文件 + memory,不辩解。
> 4. 用户偏好极简回复,ABC 选项,每条带一句"代价/收益"摘要,他回 "1A 2B 3跳过" 就够了。

- 阻塞前必须明确指出"哪些事只能用户做"(配 Key、`git init`、改 user-level config)。
- 不要修 `project_state.md`(auto-gen)。
- 不要无故改 `addons/godot_mcp/` 与 `addons/gut/`(三方 addon)。
