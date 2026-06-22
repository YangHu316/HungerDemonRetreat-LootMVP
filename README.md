# 饿魔退散：搜刮 MVP v13

3D 斜俯视 + 塔克夫式网格搜刮 + 5×4 背包。Godot 4.6.2 / GDScript。

## 🎮 启动
1. Godot 中打开本项目。
2. F5 运行主场景 `res://scenes/main.tscn`。

## ⌨️ 操作
| 按键 | 动作 |
|------|------|
| WASD / 方向键 | 玩家世界坐标移动 4.5 m/s |
| F | 接近容器时打开/关闭搜刮界面 |
| 鼠标悬停 | 0.8s 揭示未探查物品 |
| 鼠标左键拖动 | 拖拽已揭示物品 |
| R | 拖动中旋转 90° |
| 鼠标右键 | 跨面板快速转移 |
| ESC | 取消拖拽 / 关闭 UI |
| 走入绿色区域 | 触发撤离结算 |

## 📐 调参位置
- **倒计时（默认 90s）**：`scripts/autoloads/game_session.gd` 中 `ROUND_TIME`
- **玩家速度**：`scripts/entities/player.gd` 中 `SPEED`
- **相机偏移 / 跟随速率**：`scripts/entities/camera_rig.gd` `offset` / `follow_speed`
- **探查时间（0.8s）**：`scripts/ui/search_progress.gd` 中 `examine_time`
- **物品数值**：`resources/items/*.tres`（value/grid_w/grid_h/rarity/color）
- **战利品表权重**：`resources/loot_tables/*.tres`（entries/weights/min_count/max_count）
- **容器网格尺寸**：`scripts/entities/container.gd` `get_grid_size()`
- **背包尺寸**：`scripts/autoloads/player_inventory.gd` `COLS/ROWS`

## ✅ 三阶段验收概要

### Stage A — 3D 场景 + 玩家 + 斜俯视相机 + 容器骨架
- F5 进入 3D 场景，玩家黄色胶囊体 + 30×18m 房间 + 隔板
- WASD 世界坐标移动，外墙/内隔板阻挡
- 相机 fov=35、pos=(0,12,7)、什 -58°，lerp 跟随不转动
- 近容器 HUD 显示 `"按 F 搜刮 [抽屉/衣柜/保险箱]"`
- 倒计时从 90s 递减；走进绿色区域 → 弹出 ResultPanel 显示总价值

### Stage B — 双面板网格 UI + 揭示动画
- F 键弹出 SearchUI,玩家 `movement_locked = true`
- 左 ContainerPanel（0.8s倒计时进度环 + 旋转放大镜）、右 InventoryPanel 5×4
- 未揭示物品显示半透明 "?"，揭示后按稀有度边框 + 色块 + 首字 + 价值
- 物品按 grid_w×grid_h 占格；容器生成量按 loot_table 权重抽样、放不下丢弃

### Stage C — 拖拽 + 旋转 + 右键转移 + 完整流程
- 左键拖拽显示幽灵（alpha 0.6）+ 落点高亮（绿/红）
- R 键旋转后 grid_w/h 互换并重检 can_place
- 合法落点 → 放入；非法落点 → 取消退回
- 右键一键跨面板转移，找不到位置闪红
- HUD 价值监听 `PlayerInventory.changed` 实时更新
- ESC 关闭 SearchUI 后容器状态写回 contents

## 📁 项目结构
- `scripts/autoloads/`：EventBus / GameSession / PlayerInventory
- `scripts/classes/`：ItemData / ContainerLootTable / GridInventory
- `scripts/utils/grid_placer.gd`：find_first_fit
- `scripts/entities/`：player / camera_rig / container / extraction_zone
- `scripts/ui/`：search_ui / grid_panel / grid_item / search_progress / hud / result_panel
- `scenes/main.tscn`：主场景
- `resources/items/*.tres`：10 件物品
- `resources/loot_tables/*.tres`：3 个战利品表
