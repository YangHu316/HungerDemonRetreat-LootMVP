# v9 → v10 CHANGELOG

## §3 反向摆臂修复（player.gd）
- `_animate_walk`: arm swing 改为 `elbow_lift - arm_swing` / `+ arm_swing`，腿 swing 翻转（leg_l=`+leg_swing`、leg_r=`-leg_swing`），实现同侧手脚反相，手臂正确前后摆。
- `_animate_looting`: 改成单手前抬式（左右轮替，半周期 0.8s，幅度 75°），另一手前垂 -15°；腿保持垂直（蹲感由 body_root 下移 -0.08 + 前倾 -20° 表达）。
- `_animate_extracting`: 去掉腿弯（leg_l/r → 0），改用 `body_root.scale=(1,0.85,1)` 压扁 + `position.y=-0.15` 下移；双臂 -80° + 内合 ±20°。
- `_play_defeat`: body_root.rotation.x 从 +20°(后仰) 改为 -30°(弯腰)，双臂 -150° + 外展 ±40°。

## §4 美团外卖小哥外形（player.tscn）
- 删除 `Hair` 节点，新增 `Helmet`（BodyRoot 子节点 y=1.32）：HelmetShell/Outline（SphereMesh radius=0.31 scale 1.0×0.85×1.05，黄色 #ffc300/边缘 #b08800）+ HelmetBrim（前沿帽檐）+ ChinStrapL/R（黑色下颚带）+ M logo 4 节点（白色 unshaded 在 z=+0.30 头盔正前方）。
- 删除 `Backpack`，新增 `DeliveryBox`（BodyRoot 子节点 (0,0.75,-0.32)）：黄色 box body 0.55×0.65×0.45 + 黑色框边/带子/锁扣 + M logo 4 节点（白色 unshaded 在 z=-0.23 箱子最外侧朝后那面）。
- 材质重染：Torso/Arm `#ff7a3a`→`#ffc300`（美团黄）；TorsoOutline `#b04820`→`#cc9d00`；Pants `#3a5a8b`→`#1a1a1a`（黑裤）；HandL/R `#f5cba0`→`#1a1a1a`（黑手套）。
- 新增 `Collar` 白领口（BodyRoot 子节点 y=0.97 CylinderMesh top_r=0.18 bottom_r=0.20 h=0.06）。
- player.gd 同步：所有 `_hair_node` 引用改为 `helmet`；删除 `_hair_node` 字段；新增 `@onready var helmet := $BodyRoot/Helmet`、`head_outline := $BodyRoot/HeadOutline`。

## §5 家居化场景 + 5 扇窗户（main.gd / shaders/window_glass.gdshader）
- `_build_walls`: 主厅南墙拆 7 段（窗洞 X=-4 与 X=+4 处各拆下窗下/上半墙）、主厅东墙拆 4 段（窗洞 Z=4 处）、卧室西墙拆 4 段（窗洞 Z=-5 处）、储藏室东墙拆 4 段（窗洞 Z=-5 处，1.4~1.8m）；每段都带 StaticBody3D + CollisionShape3D。
- `_build_windows`: 5 扇窗户（主厅南窗 ×2、主厅东窗、卧室西窗、储藏室东磨砂窗），每扇含 Glass(ShaderMaterial 用新 shader) + 6 段窗框 + SunLight SpotLight3D（shadow_enabled=false）。
- `_build_extra_decor`: 主厅西半客厅（TVStand+TV+FloorLamp+Bulb+Rug）、东半餐厅（DiningTable+4 Chair+DiningCabinet+3 Plate）、卧室增强（BedNightstand+Pillow2+DressingTable+Mirror+HangingClothes）、储藏室增强（WashingMachine+VacuumCleaner+Toolbox 红+Umbrella）。
- 新建 `res://shaders/window_glass.gdshader`: blend_mix + cull_disabled + Fresnel + EMISSION + tint uniform，磨砂窗改 tint=(0.85,0.85,0.85,0.7) roughness=0.6。
