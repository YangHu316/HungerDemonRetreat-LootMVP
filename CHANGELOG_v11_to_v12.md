# v11 → v12 单点修复：地板漏洞（双层地板方案）

- 新增 `BaseFloor` 30→40×24 兜底视觉层（`y=0.0005`，#1a1d22，无 collision），杜绝任何缝隙穿地。
- 回退 `BedroomFloor` / `StorageFloor` 至严格贴墙 8×8（中心 `z=-5`），`MainHallFloor` 校正为 16×10；地板节点均无 StaticBody3D，仅 `Foundation` 30×0.5×18 兜底碰撞保留。
