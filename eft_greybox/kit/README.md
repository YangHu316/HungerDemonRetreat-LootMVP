# 🧱 关卡白盒搭建套件 kit/ — 预制件清单

> 每个 `.tscn` 都是**独立可实例化预制件**。在 FileSystem 面板里**直接拖进你的关卡场景**即可。
> 约定：**4m 网格**、**根原点 = 落地接触点**（放到 y=0 就贴地）。开编辑器**磁吸(Snap=1m/2m)**对齐。
> 实心件已开 `use_collision`（能走/被挡/可躲）；装饰件(灌木/树冠/灯头/井水)多无碰撞、可穿过。
> （`kit_palette.tscn` 是这些件的可视化目录，想看全貌可打开它。）

## 结构 Structure
| 文件 | 说明 |
|------|------|
| `kit_floor` | 4×4 地板瓦片 |
| `kit_wall` | 4×3 实心墙 |
| `kit_wall_door` | 带门洞的墙(进出口/视线漏口) |
| `kit_wall_window` | 带窗洞的墙(室内对视/采光) |
| `kit_ramp` | **斜坡·升 3m**(上二层/高台·垂直度) |
| `kit_platform` | **二层楼板**(y=3·夹层/屋顶) |
| `kit_railing` | 栏杆(二层/桥边) |

## 掩体 / 室内 Cover & Interior
| 文件 | 说明 |
|------|------|
| `kit_cover` | 半身掩体(蹲下断视线;放大=全身) |
| `kit_crates` | 箱堆(全身掩体·室内杂物) |
| `kit_shelf` | 货架(室内·可当搜刮容器) |

## 障碍物 Obstacles（挡路 / 掩体占位）
| 文件 | 说明 |
|------|------|
| `kit_obstacle_boulder` | 巨石(全身硬掩体·圆形) |
| `kit_obstacle_barrel` | 油桶(小掩体·圆柱) |
| `kit_obstacle_fence` | 栅栏段(矮挡路/分区) |
| `kit_obstacle_cart` | 板车/车体(大型全身掩体) |
| `kit_obstacle_planter` | 花坛/水槽(矮掩体) |
| `kit_obstacle_rubble` | 瓦砾堆(矮·不规则·氛围障碍) |

## 装饰品 Decorations（氛围 / 变数）
| 文件 | 说明 |
|------|------|
| `kit_deco_tree` | 树(干有碰撞·树冠无·遮俯视) |
| `kit_deco_bush` | 灌木(可穿过·软遮挡) |
| `kit_deco_pole` | 电线杆(细高·氛围) |
| `kit_deco_lamp` | 路灯(发光·夜景/地标) |
| `kit_deco_well` | 水井(村落氛围·小障碍) |
| `kit_deco_haystack` | 草垛(农田氛围·全身掩体) |

## 锚点 Anchors（功能标记）
| 文件 | 说明 |
|------|------|
| `kit_spawn` | 出生点(绿台 + `SpawnPoint` Marker3D) |
| `kit_extract` | 撤离点(橙台 + `ExtractPoint` Marker3D) |
| `kit_container` | 容器(搜刮·出食物/钥匙) |
| `kit_minigame_socket` | 小游戏插槽：把 `ice_cabinet`/`electric_crossing`/`gluttony_portal` 拖成它的**子节点**(组件 `standalone` 留 false) |
| `kit_enemy_node` | 饿魔巡逻锚(`PatrolPoint` Marker3D) |
| `kit_hide` | 躲藏点 |

## 🟦 可控角色 Player（即放即用）
| 文件 | 说明 |
|------|------|
| `kit_player` | **可控角色方块**：拖进关卡场景即玩。**WASD / 方向键**移动、**Shift** 跑(无需在 project.godot 配输入动作，直接读物理键)；自带**顶视跟随相机**。蓝身+黄鼻指示朝向。CharacterBody3D + CapsuleShape3D，根原点=脚底(放 y=0 即贴地)。 |

**`kit_player` 可调参数(Inspector)**：`move_speed`/`run_speed`(走/跑速)、`gravity`(重力·无地面展示场景设 0 可悬浮平移)、`auto_camera`(true=自带相机即用；想用关卡自己的相机时设 false)、`control_enabled`(过场/被抓时关掉)、`player_model`(**美术替换槽**：放角色模型则占位方块自动隐藏)。
> 调色板 `kit_palette.tscn` 里也放了一个 `kit_player`(auto_camera=off、gravity=0)——**运行后可直接 WASD 驾驶它逛整个目录**。

---
- 想改尺寸/颜色：选中件，在 Inspector 调 `size`/`material` 即可(白盒占位，随便改)。
- 想要新件(楼梯踏步/斜屋顶/围墙/特定家具)：告诉我，我补进 kit/。
- 度量：用 `level_metrics.gd`(@tool)看声半径环/出生→撤离估时；搭法见《关卡手搓指南》。
