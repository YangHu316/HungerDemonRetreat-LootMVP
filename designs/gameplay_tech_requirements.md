# 饿魔退散：搜刮 MVP v2 — Gameplay & Technical Requirements

## Part A — Gameplay

### 1. 概述
- **类型**：3D 斜俯视单人搜刮（塔克夫/三角洲风格）
- **平台**：Godot 4.6.2 桌面端，1152×648
- **核心体验**：进场 → 走动 → 接近容器按 E → **网格搜刮（含搜索动画）→ 拖拽到背包** → 撤离结算
- **标准时长**：90 秒/局
- **参考**：Escape from Tarkov、Delta Force、The Cycle

### 2. 核心机制

**玩家能力表：**
| 能力 | 输入 | 效果 | 备注 |
|------|------|------|------|
| 行走 | WASD | 世界坐标 4.5 m/s | 不依赖镜头朝向 |
| 交互 | E | 打开/关闭最近容器 | 仅在 Area3D 内可触发 |
| 拖拽 | 鼠标左键长按 | 拖动物品到目标格 | 仅 SearchUI 内 |
| 旋转 | R | 拖动中旋转 90° | 拖动期间生效 |
| 快速转移 | 鼠标右键 | 物品跨面板自动放置 | 找不到位置闪红 |
| 取消 | ESC | 取消拖动 / 关闭 UI | 拖动优先 |
| 撤离 | 进入 ExtractionZone | 触发结算 | Area3D 信号 |

### 3. 核心循环
进场 → WASD 移动 → 走近容器（Area3D 触发提示）→ 按 E 弹出双面板 SearchUI → 鼠标悬停未揭示物品 0.8s 触发"放大镜搜索"动画 → 揭示后拖拽到背包 / 右键一键转移 → ESC 关闭 → 走到撤离区 → 结算面板显示总价值。时间到 0 强制结算。

### 4. 关卡设计
单房间矩形地图 30m × 18m。地板（PlaneMesh），4 面外墙（BoxMesh），2-3 块内部隔板形成 L 形/T 形通路。容器分布：抽屉 ×2-3、衣柜 ×1-2、保险箱 ×1。撤离点 4×4 绿色 Area3D 在右下角。玩家出生左上角 Marker3D。

### 5. 美术风格 / 音效 / UI
（详见 `art_requirements.md` — 本文件不重复）

### 7. 技术需求
Godot 4.6.2 / GDScript / 1152×648 / 60 FPS / 单人。

---

## Part B — Technical Specifications

### B1. Viewport Config
- viewport_width = **1152**
- viewport_height = **648**
- stretch/mode = **canvas_items**
- stretch/aspect = **expand**
- 主场景：`res://scenes/main.tscn`
- 渲染：3D（Forward+），UI 用 CanvasLayer 覆盖

### B2. Autoloads
| 名称 | 脚本 | 职责 |
|------|------|------|
| EventBus | `res://scripts/autoloads/event_bus.gd` | 全局信号总线 |
| GameSession | `res://scripts/autoloads/game_session.gd` | 倒计时 / 结算触发 |
| PlayerInventory | `res://scripts/autoloads/player_inventory.gd` | 4×5 网格背包数据 |

### B3. 脚本清单（分层）
```
scripts/
├─ autoloads/
│  ├─ event_bus.gd
│  ├─ game_session.gd
│  └─ player_inventory.gd
├─ classes/
│  ├─ item_data.gd                (Resource)
│  ├─ container_loot_table.gd     (Resource)
│  └─ grid_inventory.gd           (Resource，网格数据结构辅助)
├─ utils/
│  └─ grid_placer.gd              (RefCounted，放置算法)
├─ entities/
│  ├─ player.gd
│  ├─ camera_rig.gd
│  ├─ container.gd
│  └─ extraction_zone.gd
├─ ui/
│  ├─ search_ui.gd
│  ├─ grid_panel.gd
│  ├─ grid_item.gd
│  ├─ search_progress.gd
│  ├─ result_panel.gd
│  └─ hud.gd
└─ main.gd
```

### B4. 节点结构

**main.tscn（Node3D 根）**
```
Main (Node3D, main.gd)
├─ World (Node3D)
│  ├─ Floor (StaticBody3D)
│  │  ├─ MeshInstance3D (PlaneMesh 30×18)
│  │  └─ CollisionShape3D (BoxShape3D 30×0.1×18)
│  ├─ Walls (Node3D)
│  │  ├─ WallN/S/E/W (StaticBody3D + MeshInstance3D BoxMesh + CollisionShape3D)
│  │  └─ DividerA/B/C (StaticBody3D + MeshInstance3D BoxMesh 6×3×0.6 + CollisionShape3D)
│  ├─ Containers (Node3D)
│  │  ├─ Drawer1/2/3 (Container, type=DRAWER)
│  │  ├─ Cabinet1/2 (Container, type=CABINET)
│  │  └─ Safe1 (Container, type=SAFE)
│  ├─ ExtractionZone (Area3D, extraction_zone.gd)
│  │  ├─ MeshInstance3D (BoxMesh 4×0.1×4，绿半透 emission)
│  │  └─ CollisionShape3D (BoxShape3D 4×0.5×4)
│  └─ PlayerSpawn (Marker3D)
├─ Player (CharacterBody3D, player.gd)
│  ├─ MeshInstance3D (CapsuleMesh r=0.4 h=1.6 黄)
│  └─ CollisionShape3D (CapsuleShape3D r=0.4 h=1.6)
├─ CameraRig (Node3D, camera_rig.gd)
│  └─ Camera3D (pos=(0,12,7), rot=(-58°,0,0), fov=35)
├─ HUD (CanvasLayer, hud.gd)
│  ├─ TimeLabel (Label)
│  ├─ ValueLabel (Label)
│  └─ HintLabel (Label，"按 E 搜刮 [类型]")
├─ SearchUI (CanvasLayer, search_ui.gd, visible=false)
│  └─ Root (Control, full rect)
│     ├─ Background (ColorRect alpha=0.7)
│     ├─ ContainerPanel (GridPanel, grid_panel.gd)
│     ├─ InventoryPanel (GridPanel, grid_panel.gd)
│     ├─ HelpLabel (Label，操作提示)
│     └─ DragLayer (Control，幽灵 + 落点高亮)
└─ ResultPanel (CanvasLayer, result_panel.gd, visible=false)
   └─ Panel + ValueLabel + ReasonLabel + RestartButton
```

**container.tscn（Node3D 根，container.gd，@export type）**
```
Container (Node3D)
├─ MeshInstance3D (BoxMesh，按 type 切换尺寸/颜色)
├─ Body (StaticBody3D)
│  └─ CollisionShape3D (BoxShape3D 同 mesh)
├─ Trigger (Area3D，半径 1.5m)
│  └─ CollisionShape3D (SphereShape3D r=1.5)
└─ LootedLabel (Label3D，"已搜刮"，默认隐藏)
```

**search_progress.tscn**
```
SearchProgress (Control, search_progress.gd, custom_minimum_size=80×80)
└─ Painter (Control，_draw 自绘放大镜+圆环)
```

**grid_panel.tscn / grid_item.tscn / hud.tscn / result_panel.tscn / extraction_zone.tscn / player.tscn**：基础 Control/Node，由对应脚本驱动。

### B5. Input Map (project.godot)
| Action | Keys |
|--------|------|
| move_up | W, ↑ |
| move_down | S, ↓ |
| move_left | A, ← |
| move_right | D, → |
| interact | E |
| rotate_item | R |
| cancel | ESC |

（鼠标左/右键由 `_gui_input` 直接处理，不映射到 Action。）

### B6. EventBus 信号
```
container_approached(container)
container_left(container)
container_opened(container)
container_closed(container)
item_examined(item)
item_moved(item, from_grid_id, to_grid_id, x, y, rotated)
inventory_full
extracted(total_value)
round_ended(total_value, reason)   # "extracted" | "timeout"
```

### B7. 状态转换表
| 当前 | 允许转向 | 禁止 | 异常 |
|------|---------|------|------|
| PLAYING | UI_OPEN, ROUND_END | - | - |
| UI_OPEN（SearchUI） | PLAYING | ROUND_END(直接) | 关 UI 后再判断 |
| ROUND_END | （重启场景） | PLAYING/UI_OPEN | 忽略输入 |

玩家移动锁定：`movement_locked = true` 当 SearchUI 打开 或 ROUND_END。

### B8. 物理碰撞层表
| 层 | 名称 | 节点 | layer | mask | 说明 |
|----|------|------|-------|------|------|
| 1 | World | Floor/Walls/Containers.Body | 1 | 0 | 静态阻挡 |
| 2 | Player | Player(CharacterBody3D) | 2 | 1 | 碰撞 World |
| 3 | Trigger | Container.Trigger / ExtractionZone | 0 | 2 | Area3D 检测 Player |

> 所有 StaticBody3D 必须 `collision_layer=1`；Player 必须 `collision_mask=1`，否则会穿墙。所有 Area3D 必须 `collision_mask=2` 才能监测玩家。

### B9. 数值边界
| 实体 | min | max | 越界行为 |
|------|-----|-----|---------|
| 玩家位置 | 世界 AABB | 世界 AABB | 墙体物理钳制 |
| 倒计时 time_left | 0 | 90 | 到 0 强制结算 |
| 物品 grid_w/h | 1 | 4 | 资源校验，超出丢弃 |
| 容器 contents 数量 | 0 | min(min_count,max_count) | 放不下丢弃 |
| 背包格子 | 4×5 | 4×5 | 拒绝 place |

### B10. 实体生命周期

**Container**：`_ready()` 抽样并放置物品（GridPlacer.find_first_fit）→ 运行时被打开（player.interact）→ `open()` 锁定玩家移动并发 `container_opened` → `close()` 写回 contents 并解锁 → 若 contents 为空则 `_set_looted_visual()` 灰化 + 显示 LootedLabel。

**SearchUI**：`open(container)` 初始化两个 GridPanel → 监听拖拽信号 → `close()` 写回容器并隐藏。

### B11. Robustness Checklist
- [ ] `is_instance_valid` 检查容器引用（玩家可能离开 Trigger）
- [ ] 容器内容生成放不下的物品**丢弃**而非报错
- [ ] 时间到 0 自动 `end_round("timeout")`，禁止重复触发（`round_active` 守卫）
- [ ] 撤离后再按 E 不再触发任何交互（检查 `round_active`）
- [ ] 拖拽中目标销毁 → 物品回原位
- [ ] PlayerInventory 多格物品共享同一 Dictionary 引用，移除时遍历所有 cell 清空
- [ ] `load()` 替代 `preload()`（动态加载 Resource）
- [ ] 摄像机 Rig 只 lerp position，不修改 rotation
- [ ] R 键旋转后 grid_w/h 互换 → 重新检测 can_place
- [ ] 鼠标悬停揭示中途离开 → SearchProgress queue_free，物品保持未揭示
