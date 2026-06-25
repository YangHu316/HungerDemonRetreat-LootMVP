# CLAUDE.md — HungerDemonRetreat_LootMVP 工作纪律

> 这个文件只写**怎么协作**和**怎么提交**。游戏设计内容请看 [README.md](README.md)、[designs/](designs/)、[CHANGELOG_*.md](.)。

## 项目快照

- **引擎**: Godot 4.6(本地用 4.6.2/4.6.3,CI 锁 4.6.2)
- **类型**: 3D 斜俯视 + 网格搜刮（"饿魔退散"MVP）
- **autoload**: `EventBus` / `GameSession` / `PlayerInventory`(本地玩家代理) / `Stamina`(本地玩家代理) / `Logger` / `Stash` / `OrderPool` / `MultiplayerManager`(LAN host/client + 大厅) / `LocalInspectLog`(per-peer inspect 状态)
- **per-player 组件**: `InventoryComp` / `StaminaComp` 挂在 Player 节点下 — autoload 只是 forward 层
- **联机进度(Phase 2B v2 完)**: ENet host/client + 大厅 + Player 动态 spawn + 同步(global_position/BodyRoot:rotation/current_stance) + **容器 host 权威 entries 同步(uid 跨 peer)+ 实时 entries_synced** + **per-peer inspect log**(每人独立放大镜动画)+ **已搜 badge 全局共享**(任一 peer 开过 → 所有 peer 看到)+ **取物/放回对称 RPC**(client 发请求 → host 验证 + 广播 + reply granted/denied)+ **Per-peer 独立 done + 团队订单结算**(每人各自撤离/迷失,全员 done 后 host 计算订单合计 + reward_per_peer)+ **Home 多人 ready 流 + waiting state**(其他 peer 还在打时,本机 home 显示等待)。host 全局 timer(mm._process)即使本人撤了仍 tick → 到 0 全员 timeout。**背包/Stash 各人独立**(per-machine,无需同步)。
- **入口**: `res://scenes/menu.tscn` → home.tscn(单人) / 联机模式占位 → main.tscn(战局)
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
| [test/unit/test_inventory_comp.gd](test/unit/test_inventory_comp.gd) | **§联机准备**:InventoryComp 独立组件 — 两个实例数据完全隔离 / changed signal per-instance(per-player 背包基础) |
| [test/unit/test_stamina_comp.gd](test/unit/test_stamina_comp.gd) | **§联机准备**:StaminaComp 独立组件 — 两个实例状态完全隔离(per-player 体力基础) |
| [test/unit/test_autoload_proxy.gd](test/unit/test_autoload_proxy.gd) | **§联机准备**:autoload `PlayerInventory`/`Stamina` 是 forward 代理 — 无 local_player 时 _fallback_comp 兜底,register 后 forward 到 player.inventory_comp,切换 local_player 时透明换源 |
| [test/unit/test_menu.gd](test/unit/test_menu.gd) | **主菜单入口**:menu.tscn 存在 / project.godot main_scene 指向 menu / 单人按钮切 home / **联机按钮已解锁(Phase 2A)** / home 有"返回主菜单"按钮 |
| [test/unit/test_multiplayer_manager.gd](test/unit/test_multiplayer_manager.gd) | **Phase 2A 联机**:状态机(SINGLE/HOST/CLIENT) / MAX_PEERS=3 / _all_ready 逻辑 / get_local_peer_id 路径 / 必备 signal+method 清单 |
| [test/unit/test_lobby_ui.gd](test/unit/test_lobby_ui.gd) | **Phase 2A 大厅**:lobby.gd 必须调 MM.host_room/join_room/leave_room/set_local_ready/start_game,有返回菜单接线 |
| [test/unit/test_player_authority.gd](test/unit/test_player_authority.gd) | **Phase 2A Player 权限**:player.gd `_input` 和 `_physics_process` 必须以 `if not is_multiplayer_authority(): return` 开头(否则远端 peer 的 Player 也会响应本地输入,网络混乱) |
| [test/unit/test_main_dynamic_spawn.gd](test/unit/test_main_dynamic_spawn.gd) | **Phase 2A Tier 3-5 架构**:main.tscn 不能有 hardcoded $Player(必须 PlayersRoot 容器+动态 spawn) / main.gd preload player.tscn + _spawn_players + 多人调 set_multiplayer_authority / player.tscn 必挂 MultiplayerSynchronizer 同步 global_position/BodyRoot:rotation/current_stance / player.gd._ready 不能自动 register PlayerInventory(多人会覆盖本地指针,改由 main.gd._bind_local 显式 register) |
| [test/unit/test_round_lifecycle_rpc.gd](test/unit/test_round_lifecycle_rpc.gd) | **Phase 2B Tier B1**:GameSession 加 _extracted_this_round / _next_entry_uid;tick timeout multi client 不本地结束(等 host 广播);MM 加 broadcast_round_start + _rpc_apply_round_start;main.gd._ready 按 mm.mode 决定本地 start_round vs 等 RPC |
| [test/unit/test_container_sync.gd](test/unit/test_container_sync.gd) | **Phase 2B Tier B2**:container 加 entry uid(host 从 gs.next_entry_uid 分配);加 serialize_entries / apply_entries(wire 用 item_path 跨网);_ready 多人 client 跳过 _generate_contents;main.gd._on_round_started client 跳过 reset_and_regenerate;MM 加 broadcast_container_entries / _rpc_apply_container_entries;broadcast_round_start payload 含 containers map |
| [test/unit/test_inspect_log.gd](test/unit/test_inspect_log.gd) | **Phase 2B Tier B3**:LocalInspectLog autoload(Dict[container_path][entry_uid]→bool);mark/is/clear/hydrate/is_container_fully_inspected API;search_ui 用 lil 替代 entry["inspected"] 字段(cache 策略 — lil 是 source of truth,entry 是 hydrate cache);GameSession.start_round 清空 lil |
| [test/unit/test_container_opened_sync.gd](test/unit/test_container_opened_sync.gd) | **Phase 2B Tier B4**:container.gd 加 _apply_opened_local 私有方法(给 RPC 调,幂等);open() 多人调 mm.notify_container_opened;MM 加 notify_container_opened (host 直接广播 / client 通过 host 转发) + _rpc_request/apply_container_opened |
| [test/unit/test_take_rpc.gd](test/unit/test_take_rpc.gd) | **Phase 2B Tier B5**:DragState 加 is_no_remove + begin_no_remove(多人 take 不删源);search_ui 加 _pending_take 字段 + _is_multiplayer/_is_single 助手;_try_drop / _quick_transfer / _on_item_double_clicked 多人 container→inventory 走 _initiate_multi_take(RPC);MM 加 take_granted/take_denied signals + _rpc_request_take/_rpc_take_granted/_rpc_take_denied;is_host 校验 + 找 entry by uid + broadcast_container_entries 后 reply granted |
| [test/unit/test_round_end_rpc.gd](test/unit/test_round_end_rpc.gd) | **Phase 2B v2 — Per-peer 独立 done + 团队订单结算**:extraction_zone 多人发 mm.request_extract(收集 inv_paths)→ notify_extracted(host 直接调本地 / client rpc_id);MM 加 _peer_round_status / _peer_inventories / _last_team_result / _global_round_active 字段;peer_done / team_result_ready 信号;_rpc_request_peer_done(host 校验 + 广播 + _check_all_done) / _rpc_apply_peer_done(本人 → end_round;其他 → emit signal hide Player) / _rpc_apply_team_result;_check_all_done_and_settle 收集撤离 peer 物品 → completion_for → reward_per_peer 广播;broadcast_round_end_timeout(host timer 到 0 时把所有 playing 标 timeout);host _process 全局 timer(client 不动);broadcast_round_start 重置 per-peer 状态 |
| [test/unit/test_home_multiplayer.gd](test/unit/test_home_multiplayer.gd) | **Phase 2B Tier B7**:home.gd 加 _ready_toggle / _mp_player_list / _enter_btn 字段;_on_enter 多人 host 调 mm.start_game(单人 change_scene main 旧路径);_on_ready_toggled 调 mm.set_local_ready;订阅 mm.peer_joined/peer_left/all_ready_changed/game_started;_setup_multiplayer_ui 在 _ready 调 |
| [test/unit/test_restart_round_clean.gd](test/unit/test_restart_round_clean.gd) | **Phase 2B Tier B8**:start_round 重置 _extracted_this_round / _next_entry_uid / time_left / round_active;清 LocalInspectLog;emit round_started;完整 round 重开循环(start → end → start)状态干净;result_panel._on_restart 必须 paused = false 在 change_scene 之前 + clear_active 订单 |
| [test/unit/test_monster.gd](test/unit/test_monster.gd) | **§五 饕餮怪物寻人(单人 MVP)**:EventBus 加 sound_emitted/monster_caught_player signals;GameSession.apply_time_penalty(扣时间 + 立即广播 round_tick);Player 加 is_invincible/grant_invincibility/_tick_sound_emit(stance 周期 emit 声音);Monster 状态机 IDLE/INVESTIGATE/SEARCH/CHASE/RETURNING/COOLDOWN(Plan A:IDLE 聋瞎 / 90° 前向锥 4m / 仅警觉态查视野 / CHASE→1.5s 跟丢→SEARCH 4s→RETURNING 走回 spawn→IDLE);main.gd 单人 spawn 怪物(多人不 spawn) + round_started 重置;§06 视野 hidden 检查 + _check_hiding_spot_detect SEARCH 极近 1.5m 一次 roll(命中 unhide+_catch) |
| [test/unit/test_hiding_spot.gd](test/unit/test_hiding_spot.gd) | **§06 玩家躲避 — HidingSpot**:capacity 1 / 2 + detection_prob export;add/remove/get_occupants 维护;group hiding_spots + interactables;容量满拒绝 add;invalid occupant 自动清理;get_prompt 含 E 键 |
| [test/unit/test_player_hide.gd](test/unit/test_player_hide.gd) | **§06 玩家躲避 — Player hide**:project.godot hide action E(keycode 69);Player 加 is_hidden/is_hidden_now/hide_in/unhide/set_nearby_hiding_spot/clear_nearby_hiding_spot;_input hide 分支必须在 movement_locked 检查前(否则躲了出不来);_tick_sound_emit 查 is_hidden(躲藏中声半径 ≈ 0);hide_in 容量满被拒;unhide 状态恢复 |

跑全量 = 340 测试 / 983 assert。

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
