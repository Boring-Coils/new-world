# HumanAI 原实现交互与接口分析

> 分析对象：`Scripts/Human/HumanAI.gd`
>
> 分析范围：当前工作区中的原居民 AI，以及仓库内所有对 `HumanAI` 的引用
>
> 分析方式：静态阅读源码，不包含重构方案
>
> 结论基准：以代码实际行为为准；注释与代码不一致时会单独指出

## 1. 组件定位

`HumanAI` 是一个 `RefCounted` 类，不是 `Node`，也不是 Autoload：

```gdscript
extends RefCounted
class_name HumanAI
```

它由 `Human._ready()` 创建并保存在 `Human.ai` 中：

```gdscript
ai = HumanAI.new(self)
```

因此：

- 每个 `Human` 拥有一个独立的 `HumanAI` 实例。
- `HumanAI` 不进入场景树，不参与 `_process`。
- `HumanAI` 不直接注册到 `TickManager`，由 `Human.on_tick()` 间接驱动。
- `HumanAI` 没有定义信号，也没有连接其它脚本的信号。
- `HumanAI` 的生命周期跟随 `Human` 对象，没有单独的退出清理逻辑。

### 1.1 职责边界

| 职责 | 归属 |
| --- | --- |
| 目标和阶段状态 | `HumanAI` |
| 水和食物的需求量、消耗、上限写回 | `HumanAI` 触发写回，资源字段归 `Human` |
| 决策、寻路、移动、等待 | `HumanAI` |
| 进水站、出水站、维护工作站占位名单 | `HumanAI` 发起，`WorkStation` 保存状态 |
| Buff 效果、剩余时间、倍率汇总 | `BuffSystem` |
| 移动动画和朝向 | `HumanAI` 调用，`HumanVisual` 表现 |
| 网格、路径和可走性 | `WorldGridGlobal.world` / `WorldGrid` |
| 建筑列表、游戏时间常量 | `TickManager` |

`HumanAI` 只保存 AI 状态。居民的消耗、Buff 和外观资产仍由 `Human` 管理，但 AI 会直接读写其中一部分字段和节点。

## 2. 提供给其它脚本交互的内容

### 2.1 枚举

#### `Goal`

源码位置：`HumanAI.gd:10-15`

| 值 | 含义 | 当前外部用途 |
| --- | --- | --- |
| `Goal.NONE` | 没有目标 | 测试场景统计空闲居民 |
| `Goal.WATER` | 去取水 | 测试场景统计取水居民 |
| `Goal.FOOD` | 去取食 | 测试场景统计取食居民 |
| `Goal.WORK` | 去上班 | 测试场景统计上班居民；Buff 自测检查眩晕时是否错误出现工作目标 |

这个枚举同时被 `HumanAI` 作为整数传给 `BuffSystem.get_weight_multiplier()`。

#### `Phase`

源码位置：`HumanAI.gd:18-23`

| 值 | 含义 | 当前外部用途 |
| --- | --- | --- |
| `Phase.IDLE` | 原地待着 | 测试场景通过排除法统计空闲 |
| `Phase.MOVING` | 正沿路径移动 | 主要供 `HumanAI` 内部驱动动画和移动 |
| `Phase.WAITING` | 已到出入口，等待服务 | 主要供 `HumanAI` 内部倒计时 |
| `Phase.INSIDE_WORK` | 在工作站内部，居民模型隐藏 | 测试场景单独统计站内人数 |

### 2.2 常量

这些常量都可通过 `HumanAI.常量名` 被其它脚本读取。

| 常量 | 值 | 功能 | 当前使用方 |
| --- | ---: | --- | --- |
| `DECISION_INTERVAL` | `5` | 每隔多少刻执行一次常规决策 | `HumanAI` 内部；初始化决策相位也使用 |
| `WORK_WEIGHT` | `10.0` | 工作目标的固定基础权重 | `HumanAI` 内部 |
| `URGENT_GAME_SECONDS` | `2160.0` | 水或食物按当前消耗速度只剩 36 游戏分钟时，资源权重达到工作权重 | `HumanAI` 内部 |
| `WALK_CELLS_PER_DAY` | `750.0` | 成年人一天的理论移动格数 | `HumanAI` 内部；`BuffSelfTest` 用它反推基础速度 |
| `CHILD_SPEED_SCALE` | `0.71` | 儿童速度倍率 | `HumanAI` 内部；`BuffSelfTest` 用它计算预期速度 |
| `OLD_SPEED_SCALE` | `0.86` | 老年人速度倍率 | `HumanAI` 内部 |

### 2.3 公开状态字段

GDScript 中没有下划线前缀的字段均可在外部直接读写。当前代码没有为这些字段提供 setter、只读包装或状态变更信号。

| 字段 | 类型 | 默认值 | 功能 | 当前外部引用 |
| --- | --- | --- | --- | --- |
| `human` | `Human` | 构造时传入 | AI 控制的居民，所有资源、位置、外观和 Buff 访问都从这里进入 | 当前仓库未发现外部读取 |
| `goal` | `Goal` | `Goal.NONE` | 当前选择的目标 | `TestScene`、`BuffSelfTest` 读取 |
| `phase` | `Phase` | `Phase.IDLE` | 当前行为阶段 | `TestScene` 读取 |
| `target` | `Building` | `null` | 当前目标建筑，移动、等待和站内阶段使用 | 当前仓库未发现外部读取 |
| `path` | `Array[Vector2i]` | `[]` | 当前格子路径，包含起点 | `TestScene` 读取 `path.size()` |
| `path_index` | `int` | `0` | 下一个要到达的路径点索引 | 当前仓库未发现外部读取 |
| `wait_left` | `int` | `0` | 在出入口还需等待的刻数 | 当前仓库未发现外部读取 |

外部脚本目前只读取这些字段。`HumanAI` 自身会在决策、移动和状态切换中直接修改它们。

### 2.4 公开方法

源码位置：`HumanAI.gd:77-96`、`HumanAI.gd:100-114`、`HumanAI.gd:227-244`、`HumanAI.gd:258-291`

| 方法 | 功能 | 谁调用 | 调用时机 |
| --- | --- | --- | --- |
| `_init(host: Human)` | 绑定居民；随机生成决策相位和 `0.9~1.1` 的速度偏移 | `Human._ready()` 通过 `HumanAI.new(self)` 间接调用 | 居民进入场景树时 |
| `on_tick()` | 推进决策计时，执行移动或等待，并更新行走动画状态 | `Human.on_tick()` | 每游戏刻，Buff 和消耗结算之后 |
| `enforce_work_gate()` | 如果当前目标是工作且 Buff 已禁止工作，立即退出工作站并清空目标 | `Human.on_tick()` | 每游戏刻，Buff 结算之后、消耗和 AI 更新之前 |
| `evict_out()` | 居民被新建筑压在占地格内时，退出工作站并走到最近可走格；无路时直接移动过去 | `PlacementController._evict_humans_in()` | 建筑放置成功后 |
| `is_relocating()` | 返回是否正在执行“被建筑挤出”的移动 | `TestScene` | 自动放置验证时 |
| `get_water_ticks_left()` | 按居民每日基础耗水量估算剩余水还能支撑多少刻 | `HumanAI._decide()`；当前无外部调用 | 计算取水权重时 |
| `get_food_ticks_left()` | 按居民每日基础耗食量估算剩余食物还能支撑多少刻 | `HumanAI._decide()`；当前无外部调用 | 计算取食权重时 |
| `get_speed_cells_per_tick()` | 计算本刻移动格数，包含年龄、随机偏移和 Buff 速度倍率 | `HumanAI._move()`；`BuffSelfTest` | 每刻移动前；Buff 自测校验速度倍率 |

`HumanAI` 没有提供公开的“设置目标”“取消目标”“取得决策结果”等方法。目标切换完全发生在内部 `_decide()` 中，外部可读取 `goal` 和 `phase`，但不能通过正式接口订阅变化。

## 3. HumanAI 对其它脚本的依赖

### 3.1 对 `Human` 的交互

源码位置：`Scripts/Human/Human.gd`

| `Human` 成员 | 访问方式 | 功能 |
| --- | --- | --- |
| `position` | 读写 | 从世界坐标换算格子；沿路径更新连续坐标；无路挤出时直接设置位置 |
| `water` | 读写 | 计算剩余水刻数；到达取水站后写为 `Human.MAX_WATER` |
| `food` | 读写 | 计算剩余食物刻数；到达取食站后写为 `Human.MAX_FOOD` |
| `age_status` | 读 | 选择儿童、成年人或老年人的速度倍率 |
| `get_daily_water()` | 调用 | 计算每日基础耗水速度 |
| `get_daily_food()` | 调用 | 计算每日基础耗食速度 |
| `buff_system` | 调用其接口 | 查询工作资格、目标权重倍率、速度倍率 |
| `visual` | 调用其接口 | 切换行走动画和朝向 |
| `show()` / `hide()` | 调用 | 进入工作站时隐藏；离开工作站或被挤出时显示 |
| `name` | 读 | 寻路失败时写入警告日志 |

`Human.MAX_WATER` 和 `Human.MAX_FOOD` 是 `Human` 的公开常量，`HumanAI` 在补给完成时直接使用它们写满资源。

### 3.2 对 `BuffSystem` 的交互

源码位置：`Scripts/Buff/BuffSystem.gd`

| `BuffSystem` 接口 | 功能 |
| --- | --- |
| `can_work()` | 决定工作目标能否参与决策；决定已选工作目标是否要立即中止 |
| `get_weight_multiplier(goal: int)` | 分别读取取水、取食、工作目标的权重倍率 |
| `get_speed_multiplier()` | 将所有 Buff 的速度倍率乘入居民移动速度 |

交互点：

- `_decide()` 用 `can_work()` 跳过工作权重，并分别用 `Goal.WATER`、`Goal.FOOD`、`Goal.WORK` 查询权重倍率。
- `enforce_work_gate()` 用 `can_work()` 检查当前工作是否已被禁止。
- `get_speed_cells_per_tick()` 用 `get_speed_multiplier()` 读取最终速度倍率。

### 3.3 对 `TickManager` 的交互

源码位置：`Scripts/Core/TickManager.gd`

| 接口或常量 | 功能 |
| --- | --- |
| `TICKS_PER_DAY` | 把每日耗水量、耗食量换算为每刻消耗速度；参与移动速度公式 |
| `GAME_SECONDS_PER_TICK` | 把 `URGENT_GAME_SECONDS` 换算为提前量刻数 |
| `get_buildings_of_type(type)` | 按水、食物、工作类型取得当前有效的候选建筑 |

`HumanAI` 不调用 `register_human()` 或 `unregister_human()`。居民注册由 `Human` 自己完成，`HumanAI` 只被 `Human` 回调。

### 3.4 对世界网格的交互

源码位置：`Scripts/Grid/WorldGridGlobal.gd`、`Scripts/Grid/WorldGrid.gd`

| 接口 | 功能 |
| --- | --- |
| `WorldGridGlobal.world.world_to_cell(position)` | 把居民世界坐标换算为当前格子 |
| `WorldGridGlobal.world.cell_to_world(cell)` | 把路径格或目标空地换算成格子中心世界坐标 |
| `WorldGridGlobal.world.get_path(from, to)` | 生成包含起点和终点的格子路径 |
| `WorldGridGlobal.world.find_nearest_walkable(cell)` | 被建筑压住时，在默认半径 60 内寻找最近空地 |
| `WorldGridGlobal.world.is_walkable(cell)` | 被挤出前记录脚下格是否可走 |
| `WorldGridGlobal.world.set_walkable(cell, value)` | 当脚下已变成建筑格时，临时放行以计算离开建筑的路径，随后恢复为不可走 |
| `WorldGrid.CELL_SIZE` | 把“每刻走多少格”换算成世界像素移动距离 |

临时修改可走性是 `evict_out()` 的特例，其它移动流程只读取网格和路径。

### 3.5 对建筑和工作站的交互

源码位置：`Scripts/Building/Building.gd`、`Scripts/Building/WorkStation.gd`

| 接口或字段 | 功能 |
| --- | --- |
| `Building.building_type` | 到达并等待结束后，决定补水、补食还是进入工作站 |
| `Building.get_nearest_entrance_cell(from_cell)` | 为候选建筑选择离居民最近的出入口 |
| `Building.get_wait_ticks()` | 到达出入口后取得需要等待的刻数 |
| `WorkStation.enter(human)` | 居民进入工作站时登记到 `occupants` |
| `WorkStation.leave(human)` | 因补给、工作禁令或建筑挤压离开工作站时，从 `occupants` 移除 |

水站、食物站和工作站当前等待时间分别为 2、2、1 刻。`HumanAI` 不限制建筑同时服务的人数，也不做排队、容量或预约。

### 3.6 对枚举的交互

| 枚举 | 用途 |
| --- | --- |
| `GlobalEnum.BuildingType.WATER` | 查找水站，并在到达后补水 |
| `GlobalEnum.BuildingType.FOOD` | 查找食物站，并在到达后补食 |
| `GlobalEnum.BuildingType.WORK` | 查找工作站，并在到达后进入内部 |
| `GlobalEnum.AgeStatus.CHILD` | 使用儿童速度倍率 |
| `GlobalEnum.AgeStatus.OLD` | 使用老年人速度倍率 |
| 其它年龄段 | 使用成年人基础速度倍率 `1.0` |

### 3.7 对 `HumanVisual` 的交互

源码位置：`Scripts/Human/HumanVisual.gd`

| 接口 | 功能 |
| --- | --- |
| `set_moving(phase == Phase.MOVING)` | 每刻同步行走或站立动画 |
| `set_facing(to_destination)` | 移动时按下一路径点的方向切换朝向 |

## 4. 其它脚本对 HumanAI 的调用

| 调用方 | 调用内容 | 目的 | 源码位置 |
| --- | --- | --- | --- |
| `Human._ready()` | `HumanAI.new(self)` | 创建居民 AI | `Scripts/Human/Human.gd:51` |
| `Human.on_tick()` | `ai.enforce_work_gate()` | Buff 更新后立即处理工作资格 | `Scripts/Human/Human.gd:62` |
| `Human.on_tick()` | `ai.on_tick()` | 消耗结算后推进 AI | `Scripts/Human/Human.gd:64` |
| `PlacementController._evict_humans_in()` | `human.ai.evict_out()` | 新建筑压住居民时把居民挤出 | `Scripts/World/PlacementController.gd:171` |
| `TestScene` 自动放置验证 | `victim.ai.is_relocating()`、`victim.position` | 验证居民确实离开被占格 | `Scripts/TestScene.gd:224` |
| `TestScene` 统计 | `h.ai.phase`、`h.ai.goal` | 汇总空闲、取水、取食、上班和站内人数 | `Scripts/TestScene.gd:257-267` |
| `TestScene` 日志 | `HumanAI.Goal`、`HumanAI.Phase`、`h.ai.path` | 输出居民状态和路径长度 | `Scripts/TestScene.gd:296-299` |
| `BuffSelfTest` | `watched.ai.goal == HumanAI.Goal.WORK` | 验证眩晕期间不会选择工作 | `Scripts/Debug/BuffSelfTest.gd:43` |
| `BuffSelfTest` | `HumanAI.WALK_CELLS_PER_DAY`、`HumanAI.CHILD_SPEED_SCALE`、`get_speed_cells_per_tick()` | 验证 Buff 速度倍率进入移动速度 | `Scripts/Debug/BuffSelfTest.gd:102-104` |

没有任何脚本连接 `HumanAI` 的信号，因为该类没有信号。所有外部观察都是主动读取字段或调用查询方法。

## 5. 每刻调用链

`TickManager.advance_tick()` 先更新建筑，再更新居民：

```text
TickManager.advance_tick()
└─ Human.on_tick()
   ├─ BuffSystem.on_tick()
   ├─ HumanAI.enforce_work_gate()
   ├─ Human._consume()
   └─ HumanAI.on_tick()
      ├─ 到点则 HumanAI._decide()
      ├─ MOVING 则 HumanAI._move()
      ├─ WAITING 则 HumanAI._update_wait()
      └─ HumanVisual.set_moving()
```

这个顺序产生以下实际行为：

1. Buff 先倒计时和结算，再检查工作资格。
2. 工作资格检查发生在水、食物消耗之前。
3. 本刻消耗可能触发新增虚弱 Buff，但它不会在同一刻被 `enforce_work_gate()` 看到。
4. 随后执行的 `_decide()` 会立即看到新增虚弱并跳过工作；如果本刻不是决策刻，正在执行的工作目标可能继续到下一刻才被工作闸门中止。
5. 水、食物先扣除，再计算资源剩余量并决策。

## 6. 状态机

### 6.1 阶段行为

| 阶段 | 每刻行为 | 退出条件 |
| --- | --- | --- |
| `IDLE` | 不做移动；仍会按决策间隔尝试选择新目标 | 决策选出有效目标后进入 `MOVING` |
| `MOVING` | 沿 `path` 连续移动；至少到达一个路径点 | 路径走完进入 `WAITING`；挤出移动走完回到 `IDLE` 并立即决策 |
| `WAITING` | 每刻将 `wait_left` 减 1 | 等待结束，执行补水、补食或进入工作站 |
| `INSIDE_WORK` | 不移动；水和食物继续由 `Human` 消耗；模型保持隐藏 | 工作资格被禁止、选择补给目标或被建筑挤出时退出 |

### 6.2 主要状态转换

```text
初始：
Goal.NONE + Phase.IDLE

常规目标：
Phase.IDLE
  -> _decide() 选中目标
  -> Phase.MOVING
  -> 路径结束
  -> Phase.WAITING

取水 / 取食：
Phase.WAITING
  -> _finish_wait()
  -> 水或食物写满
  -> Phase.IDLE
  -> 立即 _decide()

工作：
Phase.WAITING
  -> _finish_wait()
  -> Phase.INSIDE_WORK
  -> WorkStation.enter()
  -> Human.hide()

站内离开：
Phase.INSIDE_WORK
  -> 选择补给目标，或工作资格失效
  -> WorkStation.leave()
  -> Human.show()
  -> Phase.MOVING 或 Phase.IDLE

建筑挤压：
任意阶段
  -> 需要时离开工作站并显示
  -> Goal.NONE + Phase.MOVING
  -> 走到最近可走格
  -> Phase.IDLE
  -> 立即 _decide()
```

### 6.3 阶段与目标的常见组合

| 组合 | 含义 |
| --- | --- |
| `IDLE` + `NONE` | 正常空闲 |
| `MOVING` + `WATER/FOOD/WORK` | 正前往对应建筑 |
| `WAITING` + `WATER/FOOD/WORK` | 已到目标建筑出入口，正在等待 |
| `INSIDE_WORK` + `WORK` | 正在工作站内部 |
| `MOVING` + `NONE` + `is_relocating() == true` | 正在被新建筑挤出 |

`target` 在常规移动、等待和站内阶段指向目标建筑；`_go_idle()` 会将其清空。挤出移动会主动清空目标和 `goal`，但保留路径与移动阶段。

## 7. 决策逻辑

### 7.1 决策周期

- 每名居民初始化时随机产生 `_decision_offset = randi() % 5`。
- `on_tick()` 每刻增加 `_tick_count`。
- 当 `(_tick_count + _decision_offset) % 5 == 0` 时调用 `_decide()`。
- 每人仍保持每 5 刻决策一次，但不同居民的决策刻错开。
- 补给完成后和挤出完成后会立即额外调用一次 `_decide()`，不等待下一个 5 刻周期。

### 7.2 目标锁定

`_decide()` 先执行两个短路条件：

1. `_is_relocating == true` 时不做常规决策。
2. 当前目标是 `WATER` 或 `FOOD`，且阶段是 `MOVING` 或 `WAITING` 时，不改变目标。

因此居民在前往水站或食物站以及等待取用期间，不会因为权重变化改去另一栋建筑。工作目标没有这个锁定条件。

### 7.3 权重公式

```text
urgent_ticks = 2160 / 12 = 180
weight_scale = 180 * 10 = 1800

water_weight = 1800 / max(get_water_ticks_left(), 1) * water_buff_multiplier
food_weight  = 1800 / max(get_food_ticks_left(), 1)  * food_buff_multiplier
work_weight  = 10 * work_buff_multiplier
```

剩余资源刻数：

```text
water_ticks_left = human.water / (human.get_daily_water() / 1800)
food_ticks_left  = human.food  / (human.get_daily_food()  / 1800)
```

当前实现使用每日基础消耗量，没有乘 `BuffSystem.get_consume_multiplier()`。口渴 Buff 额外扣水、虚弱 Buff 降低基础消耗等效果会改变实际库存变化，但不会改变这两个估算函数的分母。

工作权重只在 `BuffSystem.can_work()` 为真时参与比较。被禁止工作时，工作权重相当于不存在。

### 7.4 实际优先级和注释差异

比较顺序是：

1. 工作权重先与 `0` 比较，成为初始最佳目标。
2. 水权重使用严格大于号 `>` 比较。
3. 食物权重使用严格大于号 `>` 比较。

因此代码实际行为是：

- 如果工作、取水、取食权重完全相等，工作目标保留。
- 如果水权和食物权相等且都高于工作，取水目标保留。
- 如果食物权严格高于工作权和水权，选择取食。
- 如果水权严格高于工作权且不低于食物权，选择取水。

源码注释写的是“平手时优先级：水 > 食物 > 工作”，但代码中的严格 `>` 和工作目标先入场的顺序并不满足这个描述。尤其在水或食物的剩余量恰好等于 36 游戏分钟时，资源权重名义上等于工作权重，实际仍会继续工作。重构时需要明确以哪套规则为准。

### 7.5 选择目标建筑

`_find_nearest_building(type)` 的流程：

1. 把居民当前位置换算为格子。
2. 从 `TickManager.get_buildings_of_type(type)` 取得该类型的有效建筑。
3. 对每栋建筑调用 `get_nearest_entrance_cell()`，选择离居民最近的出入口。
4. 用切比雪夫距离比较建筑。
5. 距离相同时保留先遍历到的建筑，即 `TickManager.buildings` 中先注册的建筑。

没有对应类型建筑时，目标回到 `IDLE`，不会保留等待状态。

### 7.6 寻路

选定建筑后：

1. 把居民当前位置换算为起点格。
2. 取得目标建筑最近的出入口格。
3. 调用 `WorldGrid.get_path()`。
4. 路径为空时输出警告，并清空目标和阶段。
5. 路径有效时保存路径，从索引 0 开始，阶段设为 `MOVING`。

寻路失败不会立刻反复重试；需要等待下一次决策周期。

## 8. 移动、到达和等待

### 8.1 移动速度

```text
speed_scale =
    0.71  儿童
    0.86  老年人
    1.0   其它年龄段

cells_per_tick =
    750 * speed_scale / 1800
    * random_speed_offset(0.9~1.1)
    * buff_speed_multiplier

world_pixels_per_tick = cells_per_tick * 10
```

成年人在没有 Buff 时的基础值为：

```text
750 / 1800 = 0.416666... 格/刻
0.416666... * 10 = 4.166666... 世界像素/刻
```

儿童和老年人的最终速度还会分别乘以 `0.71`、`0.86`。随机速度偏移在每个 `HumanAI` 实例创建时生成一次，不会每刻变化。

### 8.2 连续移动

`_move()` 在一个 tick 内可以经过多个路径点：

- 每次取路径索引当前格的中心作为目的地。
- 按本刻剩余移动距离逐步推进连续世界坐标。
- 到达当前点时推进 `path_index`，剩余距离继续用于下一个点。
- 未到达时把剩余移动距离耗尽并结束本刻移动。
- 每个目标点都按位移方向调用 `HumanVisual.set_facing()`。

### 8.3 到达与等待

路径走完后 `_arrive()`：

1. 清空 `path`，将 `path_index` 设为 0。
2. 如果是建筑挤出移动，清除挤出标记、目标和阶段，立即重新决策。
3. 常规目标进入 `WAITING`。
4. `wait_left` 从目标建筑的 `get_wait_ticks()` 取得。
5. `wait_left <= 0` 时当刻立刻执行完成逻辑，否则后续每刻递减。

等待结束后按 `target.building_type` 分流：

| 建筑类型 | 结果 |
| --- | --- |
| `WATER` | `human.water = Human.MAX_WATER` |
| `FOOD` | `human.food = Human.MAX_FOOD` |
| `WORK` | 阶段改为 `INSIDE_WORK`；若是 `WorkStation` 则调用 `enter()`；隐藏居民 |

取水或取食完成后，立即清空目标、进入空闲并重新决策。进入工作站后保持 `INSIDE_WORK`，不会继续走等待逻辑。

## 9. 工作资格闸门

`enforce_work_gate()` 只在以下条件同时成立时生效：

- 当前 `goal == Goal.WORK`。
- `human.buff_system.can_work() == false`。

生效后：

1. 如果居民正在工作站内部，调用 `WorkStation.leave(human)`。
2. 调用 `human.show()` 恢复模型。
3. 调用 `_go_idle()` 清空目标、阶段、路径和等待计数。

这个检查是独立于决策周期的，因此 Buff 一旦在 `BuffSystem.on_tick()` 后使居民失去工作资格，下一游戏刻开始时就会立即中止工作目标。新增 Buff 若发生在 `_consume()` 中，工作闸门要等到下一刻才能看到；但同刻 `_decide()` 若执行，会直接看到新 Buff。

## 10. 被新建筑挤出的流程

放置控制器只对脚下格落进新建筑占地范围的居民调用 `evict_out()`。

流程如下：

1. 将居民位置换算为格子。
2. 调用 `WorldGrid.find_nearest_walkable(from_cell)`，默认最大搜索半径为 60。
3. 如果目标格就是当前格，立即返回，不改变状态。
4. 如果脚下已经不可走，临时调用 `set_walkable(from_cell, true)`。
5. 计算从当前格到最近空地的路径。
6. 恢复脚下格原来的可走性。
7. 如果居民在工作站内部，调用 `leave()` 并调用 `show()`。
8. 有路径时清空目标和目标建筑，替换路径，进入 `MOVING`，设置 `_is_relocating = true`。
9. 无路径时直接把居民位置设为最近空地，清除挤出标记，进入空闲并立即决策。
10. 挤出移动到达终点后，清除挤出标记，进入空闲并立即决策。

挤出移动期间：

- `goal` 为 `NONE`。
- `target` 为 `null`。
- `phase` 为 `MOVING`。
- `_decide()` 会因 `_is_relocating` 直接返回。
- 外部可通过 `is_relocating()` 判断居民正在执行这次特殊移动。

如果 `find_nearest_walkable()` 在半径 60 内找不到空地，会返回原格，`evict_out()` 随即提前返回，居民不会移动。

## 11. 内部函数清单

以下函数不以下划线以外的形式直接提供给外部脚本，但构成原 AI 行为。

| 函数 | 功能 |
| --- | --- |
| `_decide()` | 计算权重、选择目标、维持水食目标锁定、触发新目标 |
| `_start_goal(new_goal)` | 退出旧工作站、查找建筑、计算路径、进入移动阶段 |
| `_find_nearest_building(type)` | 按入口切比雪夫距离选择最近建筑 |
| `_go_idle()` | 清空 `goal`、`phase`、`target`、`path`、`path_index`、`wait_left` |
| `_move()` | 按速度沿路径连续移动，更新朝向，路径结束后触发到达 |
| `_arrive()` | 处理常规到达、挤出到达、进入等待或立即完成等待 |
| `_update_wait()` | 减少 `wait_left` 并在归零后完成等待 |
| `_finish_wait()` | 补水、补食、进入工作站，或立即重新决策 |

内部状态字段：

| 字段 | 功能 |
| --- | --- |
| `_is_relocating` | 标记当前是否为建筑挤压移动；为真时暂停常规决策 |
| `_tick_count` | 该 AI 收到的 tick 总数，用于计算决策周期 |
| `_decision_offset` | 初始化时随机生成的决策相位 |
| `_random_speed_offset` | 初始化时生成的 `0.9~1.1` 个体速度偏移 |

## 12. 当前行为的边界和重构关注点

1. `HumanAI` 同时承担决策、寻路、移动、建筑进入/离开、资源写回和表现同步，职责较集中。
2. `goal`、`phase`、`target`、`path`、`path_index`、`wait_left` 都是公开可写字段，外部可以绕过状态机直接修改；当前仓库中的外部代码只读取它们。
3. 状态变化没有信号，测试和调试 UI 只能轮询 `goal`、`phase` 和 `path`。
4. 资源字段、工作资格、速度和外观都由 `HumanAI` 直接操作，接口边界在 `HumanAI`、`Human`、`BuffSystem`、`WorkStation` 和 `HumanVisual` 之间交叉。
5. `get_water_ticks_left()` 和 `get_food_ticks_left()` 使用每日基础消耗，不使用当前 Buff 消耗倍率；决策权重和实际库存下降速度可能存在偏差。
6. 源码注释描述的水、食物、工作平手优先级与严格大于号比较的实际结果不一致，尤其资源权重恰好等于工作权重时工作仍会胜出。
7. 补水、补食和工作都不做排队、容量检查或目标预约；多个居民可以同时把同一建筑作为目标。
8. 只走到建筑出入口，不规划建筑内部路径；工作站内部状态由 `WorkStation.occupants` 单独记录。
9. `evict_out()` 会临时修改世界网格可走性，虽然随后恢复，但这是 `HumanAI` 对全局网格唯一直接写入的状态。
10. 寻找最近可走格有默认 60 格搜索半径；超限时返回原格，挤出流程会提前结束。
11. 寻路失败时只输出警告并把 AI 置为空闲，不会在此次调用中尝试第二近的建筑。
12. 没有目标建筑时同样置为空闲，下一次决策仍会重新查找同类建筑。

## 13. 外部交互契约摘要

如果重构后仍需兼容当前调用方，至少应保留以下可观察行为：

| 契约 | 当前依赖方 |
| --- | --- |
| 一个居民拥有一个 `Human.ai` 实例 | `Human`、`PlacementController`、测试脚本 |
| `Human.on_tick()` 可以调用 `enforce_work_gate()` 和 `on_tick()` | `Human` |
| 外部可以用 `evict_out()` 启动被建筑挤出流程 | `PlacementController` |
| 外部可以用 `is_relocating()` 判断挤出移动是否进行中 | `TestScene` |
| 外部可以读取 `goal`、`phase`、`path` 做统计和日志 | `TestScene` |
| 外部可以读取 `goal` 判断是否错误出现工作目标 | `BuffSelfTest` |
| 外部可以调用 `get_speed_cells_per_tick()` 读取当前速度 | `BuffSelfTest` |
| `Goal` 必须保留 `NONE/WATER/FOOD/WORK` 语义 | `TestScene`、`BuffSelfTest` |
| `Phase.INSIDE_WORK` 必须能标识站内居民 | `TestScene` |
| 常量 `WALK_CELLS_PER_DAY`、`CHILD_SPEED_SCALE` 可供测试读取 | `BuffSelfTest` |
| 进入工作站时模型隐藏，离开或中止工作时模型显示 | `WorkStation`、测试场景 |
| Buff 禁止工作时不能选择工作目标，已选工作目标要中止 | `BuffSystem`、`BuffSelfTest` |

## 14. 相关源码索引

| 源码 | 与本分析的关系 |
| --- | --- |
| `Scripts/Human/HumanAI.gd` | 被分析的 AI 实现 |
| `Scripts/Human/Human.gd` | 创建并驱动 AI，提供资源和外观入口 |
| `Scripts/Human/HumanVisual.gd` | 接收移动和朝向调用 |
| `Scripts/Core/TickManager.gd` | 每刻调度居民和建筑，提供时间常量和建筑查询 |
| `Scripts/Grid/WorldGridGlobal.gd` | 提供全局网格实例 |
| `Scripts/Grid/WorldGrid.gd` | 坐标转换、寻路和可走性 |
| `Scripts/Building/Building.gd` | 建筑类型、入口和等待时间 |
| `Scripts/Building/WaterStation.gd` | 取水站等待时间 |
| `Scripts/Building/FoodStation.gd` | 取食站等待时间 |
| `Scripts/Building/WorkStation.gd` | 工作站进出和内部人员名单 |
| `Scripts/Buff/BuffSystem.gd` | 工作闸门、权重倍率和速度倍率 |
| `Scripts/Enum/GlobalEnum.gd` | 建筑类型和年龄段枚举 |
| `Scripts/World/PlacementController.gd` | 建筑压住居民时调用 `evict_out()` |
| `Scripts/TestScene.gd` | 读取 AI 状态做放置验证和统计 |
| `Scripts/Debug/BuffSelfTest.gd` | 读取 AI 目标、速度和常量做 Buff 验证 |
