# v12 → v13 CHANGELOG

- BaseFloor: Node3D+PlaneMesh → MeshInstance3D+BoxMesh(40,0.1,24), y=-0.10（消除与房间地板 z-fighting 摩尔纹）
- shaders/floor_tiles.gdshader: step() → fwidth+smoothstep(系数1.5)，远距离瓷砖缝抗锯齿
