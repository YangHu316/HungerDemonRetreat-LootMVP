# v2 → v3 升级 CHANGELOG

## A. 摄像机重写（Duckov 真实参数）
- **新增** `res://scripts/classes/camera_tuning.gd` — CameraTuning Resource，封装 pitch/yaw/distance/fov/aim_offset/lerp_speed/height_offset
- **新增** `res://resources/tuning/camera_default.tres` — 默认参数实例（pitch=55, yaw=-30, distance=45, fov=20）
- **重写** `res://scripts/entities/camera_rig.gd` — 完整实现 §3.3：YawRoot/PitchRoot 设角度 + 鼠标偏移在玩家平面上投影到 forward/right + 平滑 lerp
- **修改** `res://scenes/main.tscn` — CameraRig 子树替换为 YawRoot/PitchRoot/Camera3D 三层结构，并绑定 tuning ExtResource
- **修改** `res://scripts/main.gd` — 改用统一字段名 `camera_rig.target = player`

## B. 容器自动搜刮（删 hover，加整体进度条）
- **新增** `res://scripts/classes/container_data.gd` — ContainerData Resource（container_type/search_time/grid_cols/grid_rows/loot_table）
- **新增** `res://resources/containers/drawer.tres` — 抽屉数据（2×2，1.5s）
- **新增** `res://resources/containers/cabinet.tres` — 衣柜数据（3×3，2.5s）
- **新增** `res://resources/containers/safe.tres` — 保险箱数据（4×3，4.0s）
- **修改** `res://scripts/entities/container.gd` — 加 data/is_searched/is_emptied 字段；新增 get_search_time()、remove_slot()/add_slot() 包装；数据驱动尺寸/名称/物品表，兼容旧 type enum

## C. 数据同步契约
- 搜刮完成后 `c.is_searched = true` 持久化在 Container 节点上
- 再次 open_for 时整体跳过进度条且强制所有 entry.examined=true
- 关闭 UI 不动 contents，重开复用原引用

## D. UI 翻转 + 背包 5×4 + 放大镜
- **修改** `res://scripts/autoloads/player_inventory.gd` — COLS=5, ROWS=4
- **修改** `res://scenes/search_ui.tscn` — InventoryPanel 移到左侧 (80–560)，ContainerPanel 移到右侧 (700–1100)；ContainerPanel 顶部加 SearchProgressBar，底部加 Magnifier；HelpLabel 文本更新
- **重构** `res://scripts/ui/search_ui.gd` — 删除 _on_item_hovered/_on_item_unhovered/_clear_hover/_on_examine_complete/_hover_* 字段；新增 search_progress/is_searched 状态机；`_process` 推进整体进度，达成后批量 examined=true 并 refresh；拖拽与右键转移以 `is_searched` 为门控
- **新增** `res://scripts/ui/magnifier_widget.gd` — _process 旋转 + _draw 自绘放大镜

## 兼容性
- v2 已有 ItemData / ContainerLootTable / GridInventory / GridPlacer / PlayerInventory autoload 全部复用
- v2 物品 .tres 全部不动
- search_progress.gd 保留（未引用），避免破坏 .uid
