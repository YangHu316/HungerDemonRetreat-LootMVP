# 《饿魔退散》搜刮 MVP v3 — 升级说明（MINOR_MODIFY）

> 在现有 v2 代码上做 **4 处升级**，不重建项目。复用所有物品 .tres、容器实体、玩家、HUD、ResultPanel。

---

## A. 摄像机重写（§3 — Duckov 反编译真实参数）

### A.1 新建 Resource

**新建 `res://scripts/classes/camera_tuning.gd`**
```gdscript
class_name CameraTuning
extends Resource

@export var pitch_degrees: float = 55.0
@export var yaw_degrees: float = -30.0
@export var distance: float = 45.0
@export var fov: float = 20.0
@export var default_aim_offset: float = 5.0
@export var aim_offset_distance_factor: float = 0.5
@export var lerp_speed_normal: float = 12.0
@export var height_offset: float = 0.5
```

**新建 `res://resources/tuning/camera_default.tres`**：实例化 CameraTuning（所有字段保持默认）。

### A.2 重写 `res://scripts/entities/camera_rig.gd`

完全替换 v2 版本（v2 的只 lerp position，没有 yaw/pitch/鼠标偏移），按需求文档 §3.3 完整实现：
- `_ready()`：YawRoot 设 yaw_degrees，PitchRoot 设 pitch_degrees，Camera3D origin = (0,0,distance)，fov = tuning.fov
- `_process(delta)`：更新 forward/right 向量 → 计算鼠标偏移 → 更新 virtual_target → lerp global_position
- `_update_camera_vectors()`：从 Camera3D basis 提取水平 forward (-Z) 和 right (+X)，清零 Y 分量
- `_screen_point_to_character_plane(screen_pos)`：射线投射到 y = player.y + height_offset 的平面
- `_update_aim_offset(delta)`：屏幕中心和鼠标位置投影到平面→差向量→限长 default_aim_offset→投影到 forward/right→clamp + factor→lerp 到 offset_from_target_x/z

### A.3 `main.tscn` 节点结构改造

CameraRig 子树原本是：
```
CameraRig (Node3D + camera_rig.gd, transform 在 (0,12,7))
  └── Camera3D (rotation pitch≈58°, fov=35)
```

改为：
```
CameraRig (Node3D + camera_rig.gd, transform 重置为 Identity)
  ├── tuning = ExtResource("camera_default.tres")
  └── YawRoot (Node3D)
      └── PitchRoot (Node3D)
          └── Camera3D (transform 由 _ready() 设置，fov 由 _ready 设置)
```

`main.gd` 中 `camera_rig._target = player` → 改为 `camera_rig.target = player`（统一字段名）。
保留 `target_path` 字段（仅作为编辑器导出 NodePath 兼容），_ready 中若 target_path 不空则解析为 target。

---

## B. 容器自动搜刮（§4 — 删 per-hover，加整体进度条）

### B.1 新建 ContainerData Resource

**新建 `res://scripts/classes/container_data.gd`**
```gdscript
class_name ContainerData
extends Resource

@export_enum("drawer", "cabinet", "safe") var container_type: String = "drawer"
@export var search_time: float = 1.5
@export var grid_cols: int = 2
@export var grid_rows: int = 2
@export var loot_table: ContainerLootTable
```

**新建 `res://resources/containers/drawer.tres`**：container_type="drawer", search_time=1.5, grid_cols=2, grid_rows=2, loot_table=drawer_loot.tres

**新建 `res://resources/containers/cabinet.tres`**：container_type="cabinet", search_time=2.5, grid_cols=3, grid_rows=3, loot_table=cabinet_loot.tres

**新建 `res://resources/containers/safe.tres`**：container_type="safe", search_time=4.0, grid_cols=4, grid_rows=3, loot_table=safe_loot.tres

### B.2 改 `res://scripts/entities/container.gd`

新增字段：
```gdscript
@export var data: ContainerData    # 新数据驱动入口（可选；为空时仍用 type enum 兼容）
var is_searched: bool = false      # 整体搜刮完成
var is_emptied: bool = false       # 内容全空
```

`_generate_contents()` 改为：优先用 `data.loot_table`/`data.grid_cols`/`data.grid_rows`；若 data 为空则按旧逻辑用 type enum。
`get_type_name()` / `get_grid_size()` 同样数据驱动。
新增 `remove_slot(entry)` / `add_slot(entry)` 包装（实际转调 contents 的 GridInventory）。
**保留** v2 的 `type` 字段做兼容，但 main.tscn 中的容器实例可同时指定 data。

### B.3 重构 `res://scripts/ui/search_ui.gd`

- **删除** `_on_item_hovered` / `_on_item_unhovered` / `_clear_hover` / `_on_examine_complete` / `_hover_*` 字段
- **新增** 整体进度条逻辑：`search_progress: float`, `is_searched: bool`
- `open_for(c)` 中：
  - `is_searched = c.is_searched`
  - `search_progress = 1.0 if is_searched else 0.0`
  - 若 is_searched 则把容器面板所有 entry 的 examined 全置 true
- `_process(delta)`：若 !is_searched 则推进 progress；达到 1.0 时设置 c.is_searched=true、所有 entry.examined=true、刷新面板
- 进度条 UI：容器面板顶部加 ProgressBar + Magnifier（自绘旋转放大镜）
- 拖拽与右键转移条件改为 `if not is_searched: return`（搜完后才能操作）

### B.4 `res://scenes/search_ui.tscn` 改造（见 §D 一并改）

- 删除 search_progress.gd 的 hover 使用方式（保留文件做组件库或删除）
- 容器面板上方加 `SearchProgressBar` (ProgressBar) 节点
- 容器面板下方居中加 `Magnifier` (Control) 节点，挂 magnifier_widget.gd（自绘旋转放大镜）

---

## C. 数据同步契约（§5 — 修 bug）

### C.1 Bug 根因

v2 `search_ui.gd._try_drop()` 中：
```
from_panel.remove_entry(entry)  # 只清 GridPanel 内部 dict，并未真正改 Container.contents 或 PlayerInventory.grid
```
实际 GridPanel.remove_entry 调用的是 `grid.remove_entry(entry)`，但当 `grid_id == "container"` 时 grid 指向 `container.contents`，而 v2 关闭/再打开容器后 `open_for` 再 setup 时传的还是同一个引用，**所以这点 v2 实际是同步的**。

⚠️ **真实 Bug 重新审视**：v2 `_generate_contents()` 在容器 _ready 中执行一次；contents 是 GridInventory 引用。SearchUI.open_for 传 c.contents，GridPanel.grid = c.contents。拖拽时 from_panel.remove_entry → c.contents.remove_entry 应该是同步的。

但是 v2 还存在 **examined 状态依赖** 问题：v2 拖拽前 entry 必须 examined=true。若关闭 UI 后 examined 状态丢失（其实在 entry dict 里持续保留），下次打开又是 false → 重新揭示 → 物品就"重新出现"了。

**v3 修复**：搜刮完成后将 `c.is_searched=true` 持久化在 Container 节点上，再次 open_for 时整体跳过进度条且强制所有 entry.examined=true。这就是契约。

### C.2 契约规则

1. **单一数据源**：
   - 容器内容 = `Container.contents` (GridInventory)
   - 背包内容 = `PlayerInventory.grid` (GridInventory)
2. **打开容器时**：
   - 始终从 `Container.contents` 重建 GridPanel
   - `is_searched` 状态决定是否跑进度条
3. **拖拽完成**（原子）：
   - 验证 `target_grid.can_place(...)`
   - 从 source.grid 移除 entry
   - 放入 target.grid
   - 双方面板局部更新（不重建）
   - 发 `EventBus.item_moved`
4. **关闭 UI**：
   - 仅 `visible = false`，**不动数据**
   - 调用 `container.close()`，其中检查 contents.entries.is_empty() → is_emptied=true + 变灰

### C.3 验证

打开 cabinet → 等满 → 拖走金币 → 关 UI → 重开 → 金币应不在容器（因为已从 contents 移除）。
关键：**关闭 UI 不要重新生成 contents**。v2 `_generate_contents()` 已经放在 _ready 仅执行一次，所以 OK。

---

## D. UI 翻转 + 背包 5×4（§6）

### D.1 改 `res://scripts/autoloads/player_inventory.gd`

```
const COLS: int = 5   # 原 4
const ROWS: int = 4   # 原 5
```

其他不变。

### D.2 改 `res://scenes/search_ui.tscn`

- 把 ContainerPanel 从左侧 (offset 80~480) 移到右侧 (offset 700~1100)
- 把 InventoryPanel 从右侧移到左侧 (offset 80~560)（5×4 占宽 5*64=320，加边距）
- 容器面板上方添加 `SearchProgressBar` (子节点 ProgressBar)
- 容器面板底部添加 `Magnifier` (子节点 Control + magnifier_widget.gd)
- HelpLabel 文本改为 "[拖拽] 移动  [R] 旋转  [鼠标右键] 一键转移  [ESC] 关闭"

### D.3 SearchUI 节点引用更新

- `@onready var container_panel: GridPanel = $Root/ContainerPanel` 仍指向 ContainerPanel
- `@onready var inventory_panel: GridPanel = $Root/InventoryPanel` 仍指向 InventoryPanel
- 不依赖左右位置，靠节点名

### D.4 新组件 `res://scripts/ui/magnifier_widget.gd`

```gdscript
extends Control
func _process(delta: float) -> void:
	rotation += TAU * delta
	queue_redraw()
func _draw() -> void:
	draw_arc(Vector2(0, -8), 16, 0, TAU, 32, Color.WHITE, 4.0)
	draw_line(Vector2(11, 8), Vector2(20, 16), Color.WHITE, 4.0)
```

---

## E. 文件清单

### 新增
- `res://scripts/classes/camera_tuning.gd`
- `res://resources/tuning/camera_default.tres`
- `res://scripts/classes/container_data.gd`
- `res://resources/containers/drawer.tres`
- `res://resources/containers/cabinet.tres`
- `res://resources/containers/safe.tres`
- `res://scripts/ui/magnifier_widget.gd`
- `res://CHANGELOG_v2_to_v3.md`
- `res://VERIFICATION.md`（更新）

### 修改
- `res://scripts/entities/camera_rig.gd`（完全重写）
- `res://scripts/entities/container.gd`（加 data/is_searched/is_emptied 字段及 slot 包装方法）
- `res://scripts/ui/search_ui.gd`（删 hover，加整体进度条）
- `res://scripts/autoloads/player_inventory.gd`（COLS=5 ROWS=4）
- `res://scenes/search_ui.tscn`（翻转布局 + 加进度条/放大镜）
- `res://scenes/main.tscn`（CameraRig 子树：YawRoot/PitchRoot + Camera3D 重组）
- `res://scripts/main.gd`（camera_rig.target = player）

### 删除（可选）
- `res://scripts/ui/search_progress.gd`（v3 不再使用 per-item hover 进度）— 可选保留，避免引用错误更安全（不删）

---

## F. 验收清单（增量）

### F.1 摄像机
- [ ] 进游戏：斜俯视，pitch≈55°、yaw≈-30°、fov=20、距离 45m
- [ ] 鼠标移动到屏幕右上 → 摄像机看向偏右上 ~5m
- [ ] 鼠标静止屏幕中心 → 玩家居中
- [ ] 玩家走动 → 摄像机平滑跟随
- [ ] 改 camera_default.tres 的 pitch 为 75 → 视角变得更接近顶视

### F.2 容器自动搜刮
- [ ] 按 E 开抽屉 → 立即开始进度条 → 1.5s 后所有物品揭示
- [ ] 按 E 开衣柜 → 2.5s 揭示
- [ ] 按 E 开保险箱 → 4.0s 揭示
- [ ] 搜中按 ESC → UI 关闭，重开重新计时
- [ ] 搜完关闭再开 → 直接显示已揭示，不再跑进度条

### F.3 数据同步
- [ ] 拿走容器物品 → 关 UI → 重开 → 物品不在容器
- [ ] 把背包物品拖回容器 → 关再开 → 物品在容器
- [ ] 拿光所有 → 容器变灰 → 重开 → 显示空网格
- [ ] HUD 价值 = PlayerInventory.get_total_value()

### F.4 UI 布局
- [ ] 左侧 = 背包 (5 列 × 4 行)
- [ ] 右侧 = 容器
- [ ] 步枪 (4×1) 能横放进背包
- [ ] 古董 (2×3) 旋转后能放进背包

### F.5 整体
- [ ] /godot-verify 全 ✅
- [ ] v2 已有 5 个关键瞬间仍成立
