# v5 → v6 CHANGELOG

## §3 第二局撤离 5s 提示 bug 修复
- `extraction_zone.gd::_on_round_started`：清状态 → `set_deferred("monitoring", true)` → `await physics_frame ×2` → 主动遍历 `get_overlapping_bodies()` 触发 `_on_body_entered`
- `extraction_progress_ui`：UI 改为 Panel + ProgressBar + `EventBus.round_started` 重置 `panel.visible=false / progress_bar.value=0.0`
- `result_panel.gd::_on_restart`：visible=false → unpause → player 重置至 Vector3(0,1,0) + reset_motion → start_round
- `player.tscn` 根节点确认 `groups=["player"]`

## §4 Shift 奔跑 + 体力
- `stamina.gd` Autoload：MAX=100/DRAIN=25/RECOVER=18/DELAY=0.7/MIN_TO_START_RUN=8；信号 `changed/run_started/run_stopped/exhausted/recovered_enough`；方法 `try_start_run/stop_run/_drain/_recover/reset/is_running/is_locked`
- `project.godot`：autoload Stamina + input action `sprint` (physical_keycode=4194325)
- `player.gd` WALK=4.5 / RUN=7.5 / ACCEL=30 / DECEL=20 + 重力 + move_toward 平滑 + look_at(yaw)；Shift 必须 direction!=ZERO 才 try_start_run
- `game_session.gd::start_round` 调 `Stamina.reset()`
- `hud.tscn` StaminaPanel 左下；`hud.gd` 颜色绿/黄/红 + 闪烁/亮闪 tween，is_locked 强制红

## §5 chibi 小人美术升级
- `player.tscn` 删除 v5 鸭子节点（Beak/Wing/Foot/Tuft/Belly/Blush）；按 §5.2 重建：Torso/TorsoOutline/Pants/Head/HeadOutline/Hair/EyeWhiteL/R/PupilL/R/Mouth/HandL/R/BootL/R/Backpack；ArmL/R + LegL/R 用 Node3D 容器（pivot 在肩/胯）+ 子 MeshInstance3D
- `shaders/shadow_blob.gdshader`：unshaded + blend_mix + cull_disabled + depth_draw_never；中心黑 α=0.5 渐隐
- `player.gd` 新增 `_animate_walk` (走 freq=3 amp_bob=0.04 amp_swing=0.3；跑 freq=5 amp_bob=0.06 amp_swing=0.5 + 前倾-18°；arm/leg 反相，腿×0.7) 与 `_reset_limb_swing` (静止 lerp 回 0)
- `main.tscn` 改用 player.tscn 实例；DirectionalLight3D energy=1.4 color=#fff5e0 shadow_enabled bias=0.05 normal_bias=1.0；Environment ambient_light_color=#b0c0d0 energy=0.4 ssao_enabled radius=1.5 intensity=1.0
