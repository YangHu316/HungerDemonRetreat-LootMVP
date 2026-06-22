# Verification Plan (v10 / v11)

## §7 v10 验证项

### §7.1 反向摆臂动画
- 启动后 WASD 走动：手臂与同侧腿反相（左臂前摆时左腿后摆），手脚在身体前后方向上正确交替（不再固定身后）。
- Shift 跑动：身体前倾 -12°，手臂屈肘 -35° 基线，幅度 ±20°，腿幅度 ±18°。
- LOOTING（打开容器）：身体前倾 -20°，下移 -0.08，左右手交替前抬至 -75°，腿保持垂直。
- EXTRACTING（撤离区）：body_root.scale.y=0.85 压扁，下移 -0.15，双臂 -80° + 内合，腿垂直。
- 失败结算：弯腰 -30°（不再后仰），双臂 -150° 外展。

### §7.2 美团外卖小哥外形
- 头部为黄色头盔（SphereMesh 压扁），白色 M logo 在头盔正前面（朝玩家面方向 z=+0.30）。
- 身体为黄色 Torso，黑色裤腿/手套，白色领口。
- 背后挂黄色外卖箱（DeliveryBox 位置 y=0.75 z=-0.32），白色 M logo 在箱子背面（z=-0.23 朝玩家身后）。
- 黑色 chin strap 与黑色 box strap 视觉清晰。

### §7.3 家居化场景
- 主厅西半客厅：可见 TVStand+TV（蓝光 emission）+ FloorLamp（暖光 emission） + Rug。
- 主厅东半餐厅：可见 DiningTable + 4 Chair + DiningCabinet + 3 Plate（圆盘装饰）。
- 卧室：可见 BedNightstand + Pillow2 + DressingTable + Mirror（高金属 metallic=0.9 roughness=0.1） + HangingClothes(Pole + 2 Coat)。
- 储藏室：可见 WashingMachine（带 Door 金属感 + ControlPanel + 3 Knob） + VacuumCleaner + 红色 Toolbox + Umbrella。

### §7.4 窗户（5 扇）
- 主厅南窗1 (-4,1.4,9) 1.6×0.9：透明蓝玻璃，SunLight 暖白进光。
- 主厅南窗2 (4,1.4,9) 1.6×0.9：同上。
- 主厅东窗 (8,1.4,4) 1.6×0.9：同上，朝东。
- 卧室西窗 (-8,1.4,-5) 1.4×0.9：同上，朝西。
- 储藏室东磨砂窗 (8,1.6,-5) 0.6×0.4：磨砂灰玻璃（tint=(0.85,0.85,0.85,0.7) roughness=0.6），SunLight energy=1.0。
- 玩家无法从窗户跳出（窗下半墙 0~1m + 窗上半墙 1.9~3m 均带 collision）。
- 所有 SunLight shadow_enabled=false（性能）。

### §7.5 v9 玩法回归
- 跨房间可达：主厅 → 卧室门洞 (-3,_,-1) → 卧室；主厅 → 储藏室门洞 (4,_,-1) → 储藏室。
- 容器搜刮（5 个）/ 撤离区倒计时 / 跨局重置 / 门状态重置正常工作。
- 玩家碰撞 layer=2 mask=1；墙/家具 layer=1 mask=0。

---

## §8 v11 验收项（MINOR_MODIFY）

### §8.1 反向摆臂 bug 永久修复
- `scripts/entities/player.gd` 含 4 个新 export：`anim_test_mode / arm_swing_sign / leg_swing_sign / arm_lift_sign`。
- **最终值**：`arm_swing_sign = -1.0`、`leg_swing_sign = -1.0`、`arm_lift_sign = -1.0`。
- 全部摆臂/抬臂/弯腰/庆祝/失败的 `deg_to_rad(...)` 与 `sin(phase)` 已乘对应 sign。
- `_run_anim_test_sync()` 测试基础设施已就位（提交时 `anim_test_mode = false`）。
- WASD 走动：左臂前抬时同侧左腿后摆、对侧右腿前迈；HandL 在 BodyRoot 局部坐标 z = -0.406（身前）。
- LOOTING / EXTRACTING / 失败结算姿态方向正确（不再反向）。
- 详见 `CHANGELOG_v10_to_v11.md` §3 推导。

### §8.2 卧室重组
- 卧室无 `Bedroom_Cabinet` 与 Storage_Boxes 节点。
- `Bedroom_Drawer` 位于 (-7, 0, -8.5) type=DRAWER。
- 床位 (-7, 0, -7) 靠西墙；衣柜 (-3.5, 0, -8.7) 靠北墙；梳妆台 (-1.5, 0, -3.5) 靠东墙；床头柜 (-7, 0, -8.5)。
- 卧室地毯 2.5×1.8m 位于 (-5.5, 0.005, -7)。

### §8.3 主厅组织
- 客厅区（西）：Sofa(-5.5,0,4) rot.y=PI、CoffeeTable(-5.5,0,2.5)、TVStand(-5.5,0,0.5)、TV(-5.5,0.55,0.3) rot.y=PI、FloorLamp(-7,0,1.5)、Rug 4×5。
- 餐厅区（东）：DiningTable(4,0,4)、4 椅 (3/5,0,3/5)、DiningCabinet(7,0,0.5)、Rug 3×3。
- 玄关：ShoeCabinet(-3,0,8.5)、EntrancePlant(-1.5,0,8.5)。
- `MainHall_Cabinet` 节点位于 (7, 0, 0.5) type=CABINET，Spot 灯随之移动。

### §8.4 生活细节（全部 NO collision）
- 客厅：CoffeeTable_Magazine1/2 + CoffeeCup（杯白瓷+棕咖啡液）；TV_PhotoFrame + TV_SmallPot（陶土+绿植）。
- 餐厅：Bowl1/2（y=0.79）、Bottle1/2（y=0.83 深绿玻璃）、4 对 Chopstick（前缀 `Chopstick_` 进 NO_COLLISION）。
- 卧室：AlarmClock 红色显示 `emission_energy_multiplier = 0.30 严格`；3 本 Books 堆叠；西墙 BedroomPainting。
- 储物间：Storage_Safe 迁入 (6.5, 0, -7.5) type=SAFE；5 张 Newspaper；Charger 含绿色 LED（emission 1.5）；3 堆 CardPile。
- 玄关：KeyHookBoard + 3 钩；Doormat；UmbrellaStand + 2 雨伞。

### §8.5 硬约束
- Godot 4.6.2 / 1152×648 / 全部 Mesh+GDShader（无新 .glb/.png/.wav，无 asset_gen_*）。
- v3-v10 玩法 + v10 美团小哥外观全保留。
- `anim_test_mode` 提交版强制 false（player.tscn + player.gd export 默认值）。
- 全部装饰物无碰撞；y-layering 0.76 / 0.79 / 0.83 防 z-fighting。

### §8.6 全绿验证（已执行）
| 项 | 命令 | 结果 |
|----|------|------|
| 编译 | `godot_compile_scripts(res://scripts/)` | 27 valid / 0 errors |
| 场景 | `godot_run_scenes(main.tscn + player.tscn, instantiate=true)` | 0 errors / 0 warnings |
| 运行 | `godot_run_project(duration=8)` | 0 errors / 0 warnings |
