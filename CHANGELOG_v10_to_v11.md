# CHANGELOG v10 → v11

项目：饿魔退散：搜刮 MVP
引擎：Godot 4.6.2 / 1152×648
变更类型：MINOR_MODIFY（4 处修改 + 全绿验证）

---

## §3 反向摆臂 bug 永久修复

### 修改文件
- `scripts/entities/player.gd`
- `scenes/entities/player.tscn`

### 新增 @export 属性
```gdscript
@export var anim_test_mode: bool = false       # 提交时强制 false
@export var arm_swing_sign: float = -1.0       # 实测/推导后的最终值
@export var leg_swing_sign: float = -1.0
@export var arm_lift_sign:  float = -1.0
```

### 测试基础设施
新增 `_run_anim_test_sync()`：当 `anim_test_mode = true` 时，于 `_ready()` 中：
1. 设 `arm_l.rotation.x = deg_to_rad(-75.0) * arm_lift_sign`
2. 通过 `arm_l.transform * Transform3D(Basis(), Vector3(0, -0.42, 0))` 计算 HandL 在 BodyRoot 局部坐标系的位置
3. 把 `arm_l_pos / hand_l_pos / leg_l_pos / facing / hand_z_minus_arm_z / hand_in_front` 写入测试字段，便于断言/打印

### 实测/推导结论（最终值）
- **arm_swing_sign = -1.0**
- **leg_swing_sign = -1.0**
- **arm_lift_sign  = -1.0**

#### 验证方法（文件 IO 旁路实测）
v9/v10 两次仅凭推理改符号导致复发。v11 在 `_run_anim_test_sync()` 中
通过 `FileAccess.open("res://anim_test_dump.txt", WRITE)` 把运行时几何
状态写到磁盘后立即 `get_tree().quit()`，绕过 `godot_run_project`
不暴露 stdout 的限制；测试完读文件 → 删除 → 关闭 anim_test_mode。

##### 实测 dump（anim_test_mode=true，三个 sign 全 -1）
```
player.basis.z          = (0.0, 0.0, 1.0)        # player 朝 -basis.z = (0,0,-1) ✓
ArmL.local_pos          = (-0.34, 0.5, 0.0)
HandL.in_bodyroot.pos   = (-0.34, 0.391296, -0.405689)
HandL.z - ArmL.z        = -0.405689              # HandL 比 ArmL 更负 → 在身前 ✓
hand_in_front           = true                    # arm_lift_sign = -1 ✓
LegL.local_pos          = (-0.13, -0.2, 0.0)
FootL.in_bodyroot.z     = 0.147034
leg_l.rotation.x        = -19.999999 deg          # leg_swing_sign = -1 → 同 phase 下与左手反相 ✓
arm_l.rotation.x        = 74.999999 deg
```

##### 判定逻辑
1. **arm_lift_sign = -1**：ArmL.rotation.x = -75° × sign = +75°，
   实测 HandL.z = -0.406 < ArmL.z = 0，手在身前（朝向 -Z 一侧）✓
2. **arm_swing_sign = -1**：走路代码 `arm_l.rotation.x = elbow_lift - arm_swing`，
   `arm_swing = sin(phase) * amp * arm_swing_sign`。
   sin(phase)>0 时 arm_swing<0 → arm_l rotation.x 增大 → 左手前摆（与 elbow_lift 静态前抬同方向叠加）✓
3. **leg_swing_sign = -1**：`leg_l.rotation.x = sin(phase) * amp * leg_swing_sign`。
   sin(phase)>0 时左腿 rotation.x = -|x| → FootL 在身后（实测同 phase 下 leg_l = -20° → FootL.z = +0.147，身后）。
   左手此刻向前 → 同侧手脚反相 = 真实步态 ✓

实测三个 sign **完全一致**，与上轮数学推导结论吻合。提交版 anim_test_mode = false。

### 应用范围
所有 `deg_to_rad(...) * sin(...)` / 单次姿态偏移已乘对应 sign：
- `_animate_walk`：`elbow_lift * arm_lift_sign`、`arm_swing * arm_swing_sign`、`leg_swing * leg_swing_sign`
- `_animate_looting`：左/右手 `* arm_lift_sign`
- `_animate_extracting`：左/右手 `* arm_lift_sign`
- `_play_celebration`：双臂上举 `* arm_lift_sign`
- `_play_defeat`：垂头 + 双臂下垂 `* arm_lift_sign`

### 提交状态
- `scenes/entities/player.tscn`：`anim_test_mode = false` ✓
- `scripts/entities/player.gd` export 默认值 `anim_test_mode = false` ✓

---

## §4 卧室重组

### 修改文件
- `scenes/main.tscn`（容器节点重排）
- `scripts/main.gd`（`_build_bedroom()`）

### 容器变化
- 删除 `Bedroom_Cabinet` 与 `Storage_Boxes` 中位于卧室的项
- `Bedroom_Drawer` 移至 (-7, 0, -8.5)，type=0（DRAWER）
- `Storage_Safe` 从卧室迁出 → 储物间 (6.5, 0, -7.5)，type=2（SAFE）

### 家具布局（程序化生成于 World/Decor）
| 物件 | 位置 | 朝向 |
|------|------|------|
| Bed（Frame+Mattress+Pillow+Blanket） | (-7, 0, -7) | 西墙 |
| Wardrobe | (-3.5, 0, -8.7) | 北墙 |
| DressingTable + Mirror | (-1.5, 0, -3.5) | 东墙 |
| Nightstand | (-7, 0, -8.5) |  |
| BedroomRug | (-5.5, 0.005, -7) 2.5×1.8m |  |

---

## §5 主厅组织

### 修改文件
- `scenes/main.tscn`（`MainHall_Cabinet` 移至 (7,0,0.5) type=1，灯光跟随）
- `scripts/main.gd`（`_build_living_room` / `_build_dining_room` / `_build_entrance`）

### 客厅区（西侧）
- Sofa (-5.5, 0, 4) rot.y = PI
- CoffeeTable (-5.5, 0, 2.5)
- TVStand (-5.5, 0, 0.5)
- TV (-5.5, 0.55, 0.3) rot.y = PI
- FloorLamp (-7, 0, 1.5)（柱+灯罩+灯泡，灯泡 emission 1.5）
- LivingRug 4×5

### 餐厅区（东侧）
- DiningTable (4, 0, 4)
- 4 椅子 (3/5, 0, 3/5)
- DiningCabinet (7, 0, 0.5)
- DiningRug 3×3

### 玄关
- ShoeCabinet (-3, 0, 8.5)
- EntrancePlant (-1.5, 0, 8.5)

---

## §6 生活细节

### 修改文件
- `scripts/main.gd`（散布于上述 5 个 builder）

### 装饰清单（全部 NO collision）
**客厅**
- CoffeeTable_Magazine1 / Magazine2 / CoffeeCup（杯白瓷 + 棕咖啡液）
- TV_PhotoFrame（黑边 + 浅蓝照片）
- TV_SmallPot（陶土 + 绿色植物）

**餐厅**
- Bowl1 / Bowl2（高度 0.79）
- Bottle1 / Bottle2（高度 0.83，深绿玻璃）
- Chopstick_i_j（4 对 8 根，前缀过滤进 NO_COLLISION）

**卧室**
- AlarmClock（红色显示，**emission_energy_multiplier = 0.30 严格**）
- 3 本 Books（堆叠在 Nightstand 上）
- BedroomPainting（西墙挂画）

**储物间**
- 5 张 Newspaper 堆叠
- Charger（绿色 LED，emission 1.5）
- 3 堆 CardPile
- TrashBin / Pipe（保留 v10）

**玄关**
- KeyHookBoard + 3 钩
- Doormat
- UmbrellaStand + 2 雨伞

### Y-layering（防 z-fighting）
- 桌面 0.76 / 碗底 0.79 / 瓶底 0.83 ✓

### 碰撞策略
所有装饰物名称纳入 `_DECOR_NO_COLLISION` 集合或 `Chopstick_` 前缀过滤；
建几何时跳过 StaticBody3D 包裹，仅家具主体保留碰撞。

---

## §7-§8 验证结果

| 项 | 命令 | 结果 |
|----|------|------|
| 脚本编译 | `godot_compile_scripts(res://scripts/)` | 27/27 valid，0 errors |
| 场景验证 | `godot_run_scenes(main.tscn, player.tscn, instantiate=true)` | 0 errors / 0 warnings |
| 项目运行 | `godot_run_project(duration=8)` | 0 errors / 0 warnings |

---

## §9 硬约束遵守清单

- [x] Godot 4.6.2
- [x] 视口 1152×648（沿用 v10 project.godot）
- [x] 全部 Mesh + GDShader / StandardMaterial3D，无新 .glb/.png/.wav
- [x] 未调用任何 asset_gen_*
- [x] AlarmClock emission 严格 0.30
- [x] 提交版 anim_test_mode = false
- [x] 全部装饰物 NO collision
- [x] v3-v10 既有玩法 + v10 美团小哥外观全部保留
