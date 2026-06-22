# v6 → v7 升级日志

## 场景升级
1. **三房间分区** (`main.tscn` + `main.gd._build_walls`)：主厅 16×10 (深灰 #3a3d45) / 卧室 8×8 (棕木 #5a4d3a) / 储藏室 8×8 (水泥 #2a2d35)；外墙 4 面 + 内墙程序化构建（北分区墙 3 段，留 2 个 2.5m 门洞 / 卧储纵墙 8m 实心）。
2. **多色温灯光** (`Lights` 节点)：DirectionalLight energy 0.55；MainHallLight1/2 (#ffe6b8 暖白 2.5)；BedroomLight (#ffd99a 暖黄 3.0)；StorageLight (#c0d4ff 冷蓝 2.0)；ExtractionGlow (#2ec27e 翠绿 4.0)；每容器顶 SpotLight3D 1.2 (`_add_spotlights_above_containers`)；shadow 仅主灯/房间主灯开。
3. **shader 地砖** (`floor_tiles.gdshader` + `materials/floor_*.tres`)：3 种 ShaderMaterial（主厅 1m 砖 / 卧室 0.5×2 长条木板 / 储藏室 2m 水泥块）；step() 判断缝边；踢脚线 `_build_skirting` 沿所有墙段底部生成 (h=0.12, d=0.04, #1a1a1a) 不带碰撞。
4. **三房间装饰** (`World/Decor`)：卧室 床(Frame+Mattress+Pillow+Blanket)/衣柜/红地毯/床头台灯+OmniLight；储藏室 货架(Frame+3Plank+3Box)/3 个不同尺寸旋转纸箱堆/铁皮垃圾桶+盖/立管 Pipe；主厅 沙发(Base+Back+3Cushion #3a4a6a)/茶几(Top+4Leg)/挂画/绿植(Pot+Sphere)。`_strip_collision_from_decor` 防御性删除所有 StaticBody3D/CollisionShape3D。

## 动画升级 (`player.gd`)
1. **走/跑升级** (`_animate_walk`)：freq = current_speed * 0.6；amp_swing = remap(speed, 4.5→7.5, 0.28→0.55)；bob_y = -abs(sin(phase*2))*0.04/0.06；手脚交叉 (arm ±swing / leg ∓swing*0.85)；奔跑前倾 -18°；新 `_update_facing` 用 angular_lerp (TURN_SPEED 10 rad/s) 替代瞬切。
2. **Idle 状态机** (`PlayerState` enum + `_update_state` + `_animate_idle`)：5 状态 (IDLE/WALK/RUN/LOOTING/EXTRACTING)；moving 切 WALK/RUN，静止 0.3s 切 IDLE，状态切换 `_state_time = 0`；breath_timer × 1.4，scale.y = 1+sin(t)*0.015，重心 pos.x = sin(t*0.7)*0.012；四肢/pitch 归 0；2.5-5s 触发头微转 ±20°，3 段 (去 0.6s / 保持 0.45s / 回 0.45s)，head/head_outline/hair 同步 yaw。
3. **动作专属 + 信号** (`_animate_looting/_animate_extracting/_play_celebration/_play_defeat`)：LOOTING 弯腰 -25° 双臂 -60° 腿 +15° + sin*8 抖动；EXTRACTING scale (1,0.85,1) pos.y -0.15 双臂 -80° + 内旋 ±20° 腿 +25° + sin*12 颤抖；EventBus.container_opened/closed 切 LOOTING/IDLE；group("extraction_zone") 的 countdown_started/aborted/succeeded 切 EXTRACTING/IDLE；round_ended 触发 `_play_celebration`（跳起 + 双臂 -160° + 挥手循环）或 `_play_defeat`（弯腰 + 双臂抱头 -150° + Y 内旋 ±40°）；所有结算 Tween 设 `set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)`。
