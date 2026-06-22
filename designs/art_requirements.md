# 饿魔退散：搜刮 MVP v2 — Art Requirements

> 🔴 **MVP 极简策略**：所有视觉一律由 Godot 内置 Mesh / Control / 自绘 `_draw()` 实现。
> **禁止生成任何 sprite / texture / 3D 模型 / 音频**。`res://assets/` 除字体外保持空。

---

## 1. 美术风格
极简几何占位 + 鲜明色块。3D 用 StandardMaterial3D；2D UI 用 ColorRect / NinePatchRect / Label / Polygon2D 自绘。无贴图、无音效、无后处理。

## 2. 调色板（hex）
| 用途 | 颜色 |
|------|------|
| 地板 | `#2a2d35` |
| 墙体 | `#4a4d55` |
| 玩家 | `#f5d042` |
| 抽屉 | `#8b6f3a` |
| 衣柜 | `#6a4f2a` |
| 保险箱 | `#8b3a3a` |
| 撤离区 | `#2ec27e` (emission) |
| 物品 苹果 | `#5cd05c` |
| 物品 香蕉 | `#f5d042` |
| 物品 罐头 | `#a87b3a` |
| 物品 面包 | `#d4a574` |
| 物品 医疗包 | `#e74c3c` |
| 物品 金币 | `#ffd040` |
| 物品 步枪 | `#5a5a5a` |
| 物品 弹夹 | `#3a5a3a` |
| 物品 钻石 | `#5bc8ff` |
| 物品 古董 | `#b65bff` |
| 稀有度 Common | `#888888` |
| 稀有度 Uncommon | `#5cd05c` |
| 稀有度 Rare | `#5b9bff` |
| 稀有度 Epic | `#9b5bff` |
| 稀有度 Legendary | `#ff9000` |
| UI 背景遮罩 | `#000000` alpha 0.7 |
| UI 网格底色 | `#1a1c22` |
| UI 网格线 | `#3a3d45` |
| UI 文本 | `#ffffff` |
| 落点 合法 | `#2ec27e` alpha 0.4 |
| 落点 非法 | `#e74c3c` alpha 0.4 |

## 3. 3D 视觉规格（运行时绘制，无资产文件）

| 元素 | Mesh | 尺寸（米） | 材质 |
|------|------|-----------|------|
| 地板 | PlaneMesh | 30×18 | albedo `#2a2d35` |
| 外墙 ×4 | BoxMesh | 各边长×0.6×3 | albedo `#4a4d55` |
| 内隔板 ×2-3 | BoxMesh | 6×3×0.6 | albedo `#4a4d55` |
| 玩家 | CapsuleMesh | r=0.4, h=1.6 | albedo `#f5d042` |
| 抽屉 | BoxMesh | 0.8×0.4×0.5 | albedo `#8b6f3a` |
| 衣柜 | BoxMesh | 1.2×1.6×0.6 | albedo `#6a4f2a` |
| 保险箱 | BoxMesh | 0.8×0.8×0.6 | albedo `#8b3a3a` |
| 撤离区 | BoxMesh | 4×0.1×4 | albedo `#2ec27e` alpha 0.5 + emission `#2ec27e` |
| 容器"已搜刮"灰化 | modulate Color(0.4,0.4,0.4) + Label3D "已搜刮" 上方 0.5m | - | - |

环境：DirectionalLight3D（顶部 45° 投射，能量 1.0），WorldEnvironment（背景 `#1a1c22`，环境光 0.3）。

## 4. 2D UI 视觉规格（CanvasLayer 内）

### 4.1 SearchUI 双面板布局
- 全屏 1152×648，背景 ColorRect 黑 alpha 0.7
- 左 ContainerPanel 居中偏左（中心 x≈340）
- 右 InventoryPanel 居中偏右（中心 x≈810）
- 每个 GridPanel = 标题 Label（28px）+ 网格区（cols×rows × 64px cell）+ 价值/容量 Label
- 网格 cell：64×64，1px 深灰边框 `#3a3d45`，底色 `#1a1c22`
- 操作提示 HelpLabel 底部居中：`"[拖拽] 移动  [R] 旋转  [右键] 快速放入  [ESC] 关闭"`

### 4.2 网格物品渲染（grid_item.gd）

**未揭示**：ColorRect 64×grid_w × 64×grid_h，颜色 `#444444` alpha 0.6 + 居中 Label "?" 32px 白色。

**已揭示**：
- 主体 ColorRect = `item.color`，尺寸 `(64×w, 64×h)`（按 rotated 后 swap）
- 1px 内边框（按稀有度颜色，见调色板）
- 左上 Label = `display_name[0]`（24px 白色）
- 右下 Label = 价值 `"%d" % item.value`（12px）

### 4.3 搜索进度（SearchProgress）

`_draw()` 每帧自绘：
- 圆环进度（圆弧）：圆心 (40,40) 半径 28，从 -π/2 起绘制 progress×TAU 弧度，宽 4，颜色 `#ffd040`
- 放大镜组（围绕圆心旋转 angle += TAU * delta）：
  - `draw_arc(center+Vector2(-4,-4), 10, 0, TAU, 32, white, 3)` 镜圈
  - `draw_line(center+Vector2(3,3), center+Vector2(10,10), white, 3)` 把手

### 4.4 拖拽幽灵 & 落点高亮
- DragLayer（Control 全屏）
- Ghost：复制当前物品 ColorRect 设 alpha 0.6 + 跟随鼠标
- DropHighlight：ColorRect alpha 0.4 颜色由合法/非法切换，覆盖目标 cell 区域

### 4.5 HUD
- TimeLabel 左上：`"00:90"` 18px 白色 + 0.6 alpha 黑底 Panel
- ValueLabel 右上：`"💰 280"` 18px 黄
- HintLabel 底部居中：`"按 E 搜刮 [类型]"` 18px 白；无目标时隐藏

### 4.6 ResultPanel
- Panel 480×280 居中 `#1a1c22` alpha 0.95 + 1px 白边
- TitleLabel 28px：`"撤离成功"` 或 `"时间到"`
- ValueLabel 36px 黄：`"💰 总价值: 1234"`
- RestartButton：`[再来一局]` 24px

## 5. 字体

| 路径 | 用途 | 大小 |
|------|------|------|
| `res://assets/fonts/NotoSansSC-Regular.ttf` | 全局中文 | 12 / 18 / 24 / 28 / 32 / 36 |

> 字体文件**已存在**于 MagicDawnAI 项目模板。Developer 直接 `load()` 引用，不要重新生成或下载。

## 6. 数据资产清单（.tres，由 Developer 创建）

> 这些 `.tres` 不是美术资产，只是数据，由 Developer 在编码阶段创建并填充字段。Artist 不参与。

| 路径 | 类型 | 关键字段 |
|------|------|---------|
| `res://resources/items/apple.tres` | ItemData | value=5, rarity=Common, color=`#5cd05c`, grid=1×1 |
| `res://resources/items/banana.tres` | ItemData | value=12, Common, `#f5d042`, 2×1 |
| `res://resources/items/canned_food.tres` | ItemData | value=25, Uncommon, `#a87b3a`, 1×1 |
| `res://resources/items/bread.tres` | ItemData | value=18, Common, `#d4a574`, 2×1 |
| `res://resources/items/medkit.tres` | ItemData | value=80, Rare, `#e74c3c`, 2×2 |
| `res://resources/items/coin.tres` | ItemData | value=35, Rare, `#ffd040`, 1×1 |
| `res://resources/items/rifle.tres` | ItemData | value=200, Rare, `#5a5a5a`, 4×1 |
| `res://resources/items/ammo_mag.tres` | ItemData | value=45, Uncommon, `#3a5a3a`, 1×2 |
| `res://resources/items/diamond.tres` | ItemData | value=250, Epic, `#5bc8ff`, 1×1 |
| `res://resources/items/relic.tres` | ItemData | value=500, Legendary, `#b65bff`, 2×3 |
| `res://resources/loot_tables/drawer_loot.tres` | ContainerLootTable | 苹果50/香蕉25/罐头15/金币10，1-2 件 |
| `res://resources/loot_tables/cabinet_loot.tres` | ContainerLootTable | 罐头25/面包25/弹夹20/医疗包15/金币15，3-5 件 |
| `res://resources/loot_tables/safe_loot.tres` | ContainerLootTable | 步枪25/医疗包20/钻石20/古董15/金币20，4-7 件 |

## 7. 资产清单总览

| 路径 | 类型 | 规格 | 来源 | 备注 |
|------|------|------|------|------|
| `res://assets/fonts/NotoSansSC-Regular.ttf` | font | TTF | 已存在 | P0，Developer 直接引用 |

> 🔴 **MVP 没有任何 sprite / texture / 模型 / 音频资产**。所有视觉以代码 + 内置 Mesh / Control / `_draw()` 实现。Artist 在本次任务中**无生成工作**。
