# eft_greybox/ — 灰盒/小游戏原型 合并包（READ ME FIRST）

> 这是把另一套 Godot 工程（`EFT-Delivery/Godot_Demo/eft-delivery`，关卡灰盒 + 三小游戏原型 + 搭建套件）**整体并入本工程的隔离子文件夹**。
> **本次合并未改动本工程任何已有文件**——`git status` 仅显示新增 `eft_greybox/` 一项，无任何 `M`/`D`。`project.godot`、`icon.svg`、`.gitignore` 等均原封未动。

## 这里有什么
- `map_greybox.tscn` — 5 分钟单向搜打撤 关卡灰盒（CSG 手搭）
- `ice_cabinet.tscn` / `electric_crossing.tscn` / `gluttony_portal.tscn` — 🧊敲冰 / ⚡渡电 / 🌀暴食 三个小游戏原型（各自 `*_game.gd`，可嵌入：`@export standalone` 默认 false、`begin()` 触发、`finished` 信号）
- `kit/` — **29 件可拖拽预制件**（结构/掩体/障碍/装饰/锚点/**可控角色 `kit_player`**），清单见 `kit/README.md`
- `kit_palette.tscn` — 部件可视化目录（运行后可 WASD 驾驶 `kit_player` 逛目录）
- `level_metrics.gd` — @tool 关卡度量尺（声半径环/出生→撤离估时）
- `dev_mode.gd` / `dev_launcher.*` — 开发者模式开关与小游戏沙盒启动器
- `assets/food/` — 16 张食物图（敲冰内容物用）
- 多份 `*-说明.md` / `关卡手搓指南.md` — 设计与用法文档

## ⚠️ 三件需要你知道的事

1. **引擎版本**：本工程锁 **Godot 4.6**；这批文件在 **4.7** 下创作并验证（合并者机器上没有 4.6）。用到的节点（CSG*/CharacterBody3D/Label3D/SystemFont/Marker3D/Camera3D/DirectionalLight3D/WorldEnvironment/StandardMaterial3D）4.6 全部存在，**预期可加载，但请你在 4.6 下再过一遍确认**。
   - **不要用 4.7 打开本合并工程**——那会自动升级你现有的 4.6 文件、并可能破坏锁 4.6.2 的 CI。

2. **`project.godot` 未改（按要求保持零改动）**，因此：
   - `Dev` 自动加载**未注册** → F1 开发者模式不生效。小游戏对 `/root/Dev` 做了空守卫，**不会崩**，只是开发快捷键不可用。
   - 想启用：在 `[autoload]` 自行加 `Dev="*res://eft_greybox/dev_mode.gd"`（这一步等于改 `project.godot`，主动权在你）。
   - 主场景、物理引擎沿用你工程的设置。**任何场景用 F6 单独运行即可。**

3. **食物图的 `.import` 已剥离**，Godot 4.6 首次打开会自动重新导入。导入前敲冰小游戏会用纯色占位图兜底（代码内置 fallback）。

## 不影响你的现有流程
- **未新增任何测试文件** → 你的 GUT 套件 / CI 不受影响。
- 所有内部引用已改写为 `res://eft_greybox/…`，自成闭环，不引用本工程其它资源。

## 想真正"打通进主循环"时
把小游戏接进 `scenes/main.tscn`：用 `kit/kit_minigame_socket` 当插槽，把 `ice_cabinet.tscn` 等拖成子节点，交互触发 `begin()`、监听 `finished(result)`。细节见本文件夹内《接入大地图与开发者模式-说明.md》。这一步需要你按 4.6 的架构（你们的 Player/容器/EventBus）来对接。
