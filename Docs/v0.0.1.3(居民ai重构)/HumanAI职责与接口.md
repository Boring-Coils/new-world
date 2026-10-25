# HumanAI 职责与接口

本文定义居民 AI 重构后的职责边界、对外接口和现有调用方的迁移要求。
`HumanAI` 不再负责寻路、移动和表现，只负责决策和行动状态。

## 1. 设计结论

`HumanAI` 是居民的“决策与行动协调器”，不是整个居民的调度中心。

它的核心职责是：

1. 每游戏刻收集一次决策上下文。
2. 通过决策树决定当前想做什么。
3. 通过状态机决定是否接受新目标、继续当前动作、完成动作或中断动作。
4. 将高层动作交给 `HumanMotion`、建筑和居民数据接口执行。
5. 处理动作成功、失败、中断和特殊移动。

可以概括为：

> `Human` 管时钟和居民数据，`HumanMotion` 管怎么走，
> `HumanVisual` 管怎么显示，`BuffSystem` 管状态效果；
> `HumanAI` 只负责决定做什么、什么时候改变决定，以及派发高层动作。

## 2. 组件边界

| 组件 | 职责 | 不属于该组件的职责 |
| --- | --- | --- |
| `Human` | 居民实体、生存数据、每刻调度、组件组合 | 决策树、状态转换、具体移动 |
| `HumanAI` | 决策、状态机、目标管理、动作中断和结果处理 | 路径计算、位置更新、动画、Buff 计时 |
| `HumanMotion` | 寻路、路径推进、连续移动、出入口选择、脱困移动、原子离站 | 选择目标、判断是否工作、播放动画 |
| `HumanVisual` | 动画、朝向、服装、显示和隐藏 | 决策、寻路、Buff 效果 |
| `BuffSystem` | Buff 增加、计时、到期和效果汇总 | 选择居民目标、控制居民移动 |
| `TickManager` | 全局刻调度、建筑列表和时间常量 | 单个居民的决策 |
| `Building` / `WorkStation` | 建筑状态、等待时间、工作站占用名单 | 居民 AI 状态 |

## 3. 对外接口

重写后应尽量只暴露以下内容。

### 必须提供

| 接口 | 说明 |
| --- | --- |
| `on_tick()` | `Human` 每游戏刻调用的唯一入口，内部完成决策和状态推进 |
| 居民绑定入口 | 由 `Human._ready()` 注入居民，或从父节点取得，不使用带参 `_init()` |
| 调试状态查询 | 提供当前 Goal、State、Target 等只读信息，供测试和调试面板使用 |

### 建议提供

| 接口 | 说明 |
| --- | --- |
| `request_relocation()` | 被新建筑压住时请求脱困；由 `Human.relocate_out()` 转发 |
| `get_debug_snapshot()` | 一次返回决策、状态、目标和重定位信息，避免外部直接读字段 |
| `leave_current_building()` | 没有移动目标时，从当前建筑最近出入口原子离站 |
| `state_changed(old_state, new_state)` | 状态切换通知，供 UI、测试和调试日志使用 |
| `goal_changed(old_goal, new_goal)` | 目标切换通知 |

`Goal` 如果需要继续配合 Buff 的目标权重倍率，应保留
`NONE / WATER / FOOD / WORK` 的整数语义。`BuffSystem.get_weight_multiplier()`
接收的是 `int`，并不静态依赖 `HumanAI` 类型。

## 4. 内部职责

### 4.1 决策上下文

每刻构建一次只读或短期复用的上下文，至少包含：

- 当前 Goal 和 State。
- 当前水、食物及按消耗速度计算的剩余可支撑刻数。
- `BuffSystem.can_work()`。
- 水、食物、工作的 Buff 权重倍率。
- 当前目标建筑是否仍有效。
- 水站、食物站、工作站是否可用。
- 居民是否在建筑内、是否正在脱困。

建筑扫描和寻路不应每刻执行。建筑可用性可以缓存，路径只在状态切换时计算。

### 4.2 决策树

决策树只回答“现在想做什么”，不产生副作用。

建议结构：

1. 硬性条件：脱困期间暂停普通目标、没有建筑时排除该目标、Buff 禁止工作时排除工作。
2. 生存评分：水、食物的紧张程度。
3. 工作评分：工作经验或固定权重。
4. Buff 权重倍率。
5. 无有效目标时返回空闲。

平手优先级必须显式定义，不能依赖字段比较顺序形成隐式规则。

### 4.3 状态机

建议至少包含以下状态：

| 状态 | 职责 |
| --- | --- |
| `IDLE` | 每刻正常接受决策结果 |
| `MOVING` | 移动中，保存目标并等待到达或失败 |
| `WAITING` | 在建筑入口等待服务 |
| `WORKING` | 位于工作站内部，每刻检查需求和 Buff 闸门 |
| `RELOCATING` | 被新建筑压住，暂停普通决策直到脱困完成 |

决策树每刻都会运行，但不代表每刻都要改变状态。状态机必须负责目标承诺和中断：

- 空闲时允许自由改目标。
- 前往和等待水站、食物站时保持当前目标，目标失效除外。
- 工作期间每刻检查工作资格和生存需求，满足条件时中断。
- 脱困期间忽略普通目标。
- 必要时增加重试间隔或进入/退出阈值，避免目标振荡。

## 5. 每刻调用顺序

推荐由 `Human.on_tick()` 控制固定顺序：

1. `BuffSystem.on_tick()`。
2. `Human` 扣除水和食物。
3. `HumanAI.on_tick()`。
4. AI 更新上下文、运行决策树并推进状态机。
5. 当前状态需要移动时，由 AI 调用一次 `HumanMotion.on_tick()`。
6. 移动和状态信号更新外观与调试状态。

`HumanMotion.on_tick()` 只能有一个所有者。推荐由 AI 在动作执行阶段调用，
`Human` 不要再次调用，否则同一刻会移动两次。

AI 必须响应以下移动信号：

| 信号 | AI 处理 |
| --- | --- |
| `arrived` | 从 `MOVING` 进入 `WAITING` 或完成脱困 |
| `path_failed` | 放弃目标、进入空闲或安排重试 |
| `relocation_finished` | 结束 `RELOCATING` 并恢复普通决策 |
| `building_exited` | 更新 AI 状态、调试信息或后续动作 |

## 6. 动作流程

### 取水

1. 决策树返回 `WATER`。
2. AI 找到可达的水站并保存目标。
3. 调用 `HumanMotion.move_to_building()`。
4. 收到 `arrived` 后进入 `WAITING`。
5. 等待结束后补满水。
6. 清空目标并重新决策。

### 取食

流程与取水一致，等待结束后补满食物。

### 工作

1. 决策树返回 `WORK`，同时确认 `BuffSystem.can_work()`。
2. 前往工作站并等待。
3. 等待完成后调用 `WorkStation.enter()`。
4. 进入 `WORKING`。
5. 每刻检查工作资格和生存需求。
6. 中断时调用 `HumanMotion.leave_current_building()`，由移动组件统一完成离站和显示，AI 随后重新决策。

### 被建筑挤出

1. `PlacementController` 调用 `Human.relocate_out()`。
2. `Human` 将请求转给 AI。
3. AI 进入 `RELOCATING`，此时不要提前调用 `leave()` 或恢复显示。
4. AI 调用 `HumanMotion.relocate_to_nearest_walkable()`。
5. 收到 `relocation_finished` 后回到 `IDLE` 并重新决策。

### 离站原子性

居民从工作站内部前往另一个目标时，必须先确认路线可达，再完成离站。
`HumanMotion` 的处理顺序固定为：

1. 以当前建筑的所有出入口为起点寻找通往目标的最短路径。
2. 没有可达路径时返回失败，建筑占用、`Human.in_building`、位置和显示状态全部不变。
3. 找到路径后，从 `WorkStation.occupants` 移除居民。
4. 把居民位置直接设置到选中的出口格。
5. 清空 `Human.in_building`。
6. 恢复显示并开始沿路径移动。

第 3 到第 6 步必须在同一个同步函数调用中完成。Godot 不会在函数中途绘制帧，
因此不会出现“居民已经显示，但仍站在建筑内部 A 格”的一 tick 中间画面。

AI 不应在调用 `move_to_building()` 前自行执行 `leave()` 或 `show()`。如果 AI
提前离站，即使随后寻路失败，居民也会错误地出现在 A 格。

## 7. AI 可以使用的依赖

| 模块 | AI 使用的接口 |
| --- | --- |
| `Human` | 水、食物、年龄段、每日消耗、补给接口、位置 |
| `BuffSystem` | `can_work()`、`get_weight_multiplier()` |
| `HumanMotion` | 移动命令、最近建筑查询、预计 tick、`on_tick()` 和移动信号 |
| `TickManager` | 建筑列表、游戏时间常量 |
| `Building` | 建筑类型、等待刻数、出入口 |
| `WorkStation` | `enter()`、`leave()` |
| 决策树 | 读取上下文并返回 Goal |
| 状态机 | 保存状态、目标、等待时间和转换规则 |

`HumanMotion` 在确认离站时会调用 `WorkStation.leave()`，但工作站的进入、占用名单
结构和等待时间仍归 `WorkStation` 管理。

AI 不应直接访问 `WorldGrid`、修改 `Human.position`、维护路径索引或调用
`HumanVisual.set_facing()`。

## 8. 现有调用方迁移

| 现有调用方 | 当前依赖 | 重构后 |
| --- | --- | --- |
| `Human` | `HumanAI.new(self)` | 使用场景中的 `HumanAI` 子节点 |
| `Human` | `ai.enforce_work_gate()` | 删除外部闸门调用，由 AI 每刻内部检查 |
| `Human` | `ai.on_tick()` | 保留 |
| `PlacementController` | `human.ai.evict_out()` | 改为 `human.relocate_out()` |
| `TestScene` | `ai.phase`、`ai.goal`、`ai.path` | 使用 AI 调试快照和 `HumanMotion` |
| `BuffSelfTest` | `ai.goal` | 使用 AI 调试快照 |
| `BuffSelfTest` | AI 的速度常量和速度函数 | 改从 `HumanMotion` 获取 |

当前 `Human.tscn` 已经挂载了 `HumanAI` 节点，但 `Human.gd` 仍会额外创建一份
AI，并且旧 `_init(host)` 与场景无参实例化冲突。重写时需要统一为一个场景实例。

## 9. 不应再提供的接口

以下内容应从 AI 的公共接口中移除，或降为内部状态：

- `path` 和 `path_index`。
- `get_speed_cells_per_tick()` 和移动速度常量。
- `set_moving()`、`set_facing()` 等表现控制。
- `wait_left`、`_tick_count`、决策相位等内部计时。
- 可直接修改的 `goal`、`phase`、`target` 字段。
- `evict_out()` 这种由放置系统直接驱动的移动实现。

## 10. 完成标准

重写完成后应确认：

- 每个居民只有一个 AI 实例，并且是 `Human.tscn` 的子节点。
- `Human.on_tick()` 只调用一次 `HumanAI.on_tick()`。
- AI 不读取或修改路径索引，不直接写居民坐标。
- 取水、取食、工作、等待、脱困都有明确状态和退出条件。
- Buff 禁止工作时不会选择或继续工作目标。
- 寻路失败不会让居民卡在 `MOVING`。
- 从建筑内部出发时，只有路线可达才执行 `leave()`、清空 `in_building` 和恢复显示。
- 离站过程中不会出现居民短暂显示在建筑内部原格子的情况。
- 被建筑压住后能恢复普通决策。
- `TestScene` 和 `BuffSelfTest` 不再读取 AI 的私有实现字段。
- `Godot --headless` 测试中不再出现 AI 构造、脚本解析或信号连接错误。
