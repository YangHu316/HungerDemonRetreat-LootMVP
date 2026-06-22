# v8 → v9 CHANGELOG

1. **§3 手脚跟随**：`player.tscn` 重组——HandL/R 改挂为 ArmL/R 子节点（local y=-0.42），BootL/R 改挂为 LegL/R 子节点（local y=-0.32, z=0.04），Mesh 子节点 y=-0.20/-0.15；`player.gd` 旋转 ArmL/LegL 时手脚自动跟随，无需独立动画。
2. **§4 门 collision**：`door_assembly.tscn` DoorPanel/DoorCollision size 改为 1.2×2.2×(0.08/0.20)，DoorPivot 局部 x=-0.6 作铰链；`door.gd` `_ready()` 加防御（layer=1/mask=0/shape 非空兜底/disabled=false），动画改旋转 DoorPivot.rotation.y；`main.gd` 跨局 reset_state 强制 rotation=ZERO + 重启 collision；project.godot 加 [layer_names] World/Player/Interactable。
3. **§5 房间可达性**：`main.tscn` 门位置 DoorBedroom x=-3.0、DoorStorage x=5.0；`main.gd` 内墙重新分段（段a -8~-3.6 长 4.4 / 段b -2.4~4.4 长 6.8 / 段c 5.6~8 长 2.4 / 门洞 1.2m）+ InnerWallEW 完整 8m + `_verify_reachability()` 射线自检（push_warning，不阻止启动）。
