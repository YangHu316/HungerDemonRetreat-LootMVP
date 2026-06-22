# CHANGELOG v7 → v8

## A. §3 修地图漏洞
- 移除 `World/Floors/{MainHallFloor,BedroomFloor,StorageFloor}` 的 `StaticBody3D + CollisionShape3D`，改为 `Node3D`，仅保留 `MeshInstance3D`（PlaneMesh y=+0.001，每块尺寸 +0.5m overlap）。
- 新增 `World/Foundation` `StaticBody3D` (BoxShape3D 40×0.5×24, position.y=-0.25, layer=1)；`player.gd` 加 `FALL_THRESHOLD=-1.5` + `RESPAWN_POS=Vector3(0,1,0)` 的 `_physics_process` 兜底。

## B. §4 加门交互
- `event_bus.gd` 新增 `door_toggled(door,is_open)` / `interact_prompt(text)`。
- 新建 `scripts/entities/door.gd`（`class_name Door extends StaticBody3D`，实现 interactables 协议；Tween 旋转 ±90°）。
- 新建 `scenes/entities/door_assembly.tscn`（DoorAssembly Node3D 根：Door StaticBody3D 含 DoorPivot/Mesh/DoorCollision/Handle；InteractArea Area3D 平级，layer=0/mask=2）。
- `main.tscn` 在 X=-4/X=4 处实例化 2 个 DoorAssembly（World/Doors/）。
- `container.gd` 加 `add_to_group("interactables")` + `get_interact_position/get_prompt/is_available/interact`；body_entered/exited 调用 `player.register_interactable/unregister_interactable`。
- `player.gd` 加 `_candidates` 数组 + `register_interactable/unregister_interactable/_update_nearest_interactable`；`_input` 检测 F 键调用 `_nearest.interact()`（仅 doors）；玩家 `_ready` 加 group。
- `main.gd._on_round_started` 新增对 `doors` 组调用 `reset_state()`；`hud.gd` 连接 `interact_prompt` 显示提示。
- `project.godot` 已确认 interact 绑 F 键(70)。

## C. §5 人物去方块
- `player.tscn` 全部 BoxMesh 部件改 CapsuleMesh / SphereMesh：Torso/TorsoOutline/Pants → CapsuleMesh；ArmL/R Mesh、LegL/R Mesh → CapsuleMesh；BootL/R → CapsuleMesh + scale(1.4,0.6,1.6)；Backpack → CapsuleMesh + scale(1.3,1.1,0.55)；Head/HeadOutline + scale(1,1.1,0.95) (HeadOutline 1.166)；Hair SphereMesh height=0.50；Mouth → CapsuleMesh + rotation_z=90°（transform basis 旋转）。装饰物 BoxMesh 不改。

## D. §6 动画重做
- `_animate_walk` 屈肘抬肘 -35° 基线 + 摆幅 ±20°（跑 ±28°）+ 落地下沉 2-3cm + 奔跑前倾 -12°。
- `_animate_looting` 双手交替 1.6s 周期 (sin/-sin amp=±25°) + 头低 25°（head/hair rotation.x） + 身体前倾 -20°。
- `_exit_looting_reset` Tween 平滑回正 head/hair.x 与 arm.z（在 `_on_container_closed` 调用）。
