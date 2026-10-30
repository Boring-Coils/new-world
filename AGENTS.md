# 仓库协作指南（AGENTS.md）

本文件适用于整个仓库。开始修改前先阅读本指南，再结合相邻脚本和
`project.godot` 确认真实行为。文档、代码注释和旧版设计稿可能落后于实现；
遇到冲突时，以当前代码和最新的专项设计文档为准，并在相关改动中顺手修正明显失效的说明。

## 1. 项目定位

这是一个使用 Godot 4.7 开发的 2D 殖民地模拟原型，当前项目版本为 `0.0.1.4`。

- 主场景是 `Scenes/Colony.tscn`，集成检查场景是 `Scenes/TestScene.tscn`。
- 游戏按“刻”推进，不是按帧推进；建筑、居民、Buff 和资源结算都与 `TickManager` 对齐。
- 世界按正方形网格组织，`1 格 = 1 米`，`WorldGrid.CELL_SIZE = 10` 像素。
- 当前核心循环是居民取水、取食、按雇佣关系上班、完成工作周期、消耗、Buff、物资结算和建筑放置。
- 项目没有自动化测试框架、格式化工具或静态检查工具，验证主要依赖 Godot
  无头运行、日志断言和编辑器人工检查。

## 2. 快速开始

在仓库根目录执行命令。要求 Godot 4.7 已加入 `PATH`；如果本机命令名不是
`godot`，改用实际可执行文件即可。

```powershell
# 打开编辑器
godot --editor --path .

# 刷新资源导入并检查脚本/场景解析问题
godot --headless --path . --import

# 常规集成检查
godot --headless --path . Scenes/TestScene.tscn -- --speed=20 --max-ticks=600

# 放置链路检查
godot --headless --path . Scenes/TestScene.tscn -- --autoplace --speed=20 --max-ticks=60

# Buff 链路检查
godot --headless --path . Scenes/TestScene.tscn -- --bufftest --speed=20 --max-ticks=140

# v0.0.1.4 完整验收（逐项输出 PASS/FAIL）
godot --headless --path . --log-file .godot/v014_acceptance.log --scene res://Scenes/TestScene.tscn -- --acceptance

# 导出调试版，输出目录被 .gitignore 忽略
godot --headless --path . --export-debug "Windows Desktop" build/0.0.1.4/new_world.exe
```

`Scenes/TestScene.tscn` 的测试参数位于引擎参数分隔符 `--` 之后。常用的用户参数有：

| 参数 | 作用 |
| --- | --- |
| `--speed=20` | 设置走时倍速；只影响现实时间中的推进速度 |
| `--max-ticks=600` | 跑满指定刻数后退出；无头测试必须提供，避免进程不退出 |
| `--autoplace` | 自动放置建筑和居民，检查合法放置、非法放置、重叠和挤出逻辑 |
| `--bufftest` | 在固定刻数添加疲劳、眩晕和口渴，检查倍率、工作闸门和到期 |
| `--acceptance` | 运行 v0.0.1.4 全部雇佣、班次、周期、库存、清算和 UI 契约自检 |
| `--shot=路径.png` | 在满足条件时截取当前画面；视觉检查仍优先使用编辑器窗口 |

运行后不要只看退出码。Godot 可能出现脚本错误但进程仍然结束的情况，必须检查输出里是否含有
`SCRIPT ERROR`、`ERROR`、未预期的 `push_warning`，以及各测试标记是否符合预期。

## 3. 仓库结构

```text
project.godot              Godot 项目配置、主场景、Autoload、渲染和物理设置
export_presets.cfg         Windows Desktop 导出预设
Scenes/
  Colony.tscn              主场景
  TestScene.tscn           放置、模拟和 Buff 集成检查场景
  Human/Human.tscn         居民场景，挂 BuffSystem、Visual、Motion 和 HumanAI 状态图
Scripts/
  Core/                    刻调度和全局时间规则
  World/                   世界骨架、殖民地、相机和放置控制
  Grid/                    全局网格、寻路、格子坐标换算和网格显示
  Building/                建筑基类、取水站、取食站、工作站、仓库
  Human/                   居民实体、移动、表现、AI、状态基类、工作行为
  Buff/                    Buff 系统、基类和具体 Buff
  Material/                物品、库存、工作类型和工作周期数据模型
  UI/                      建筑详情页
  Debug/                   调试面板、放置检查和 Buff 自检
  Enum/                    全局枚举
Assets/                    导入资源，例如建筑图标和居民序列帧
Tools/Blender/             生成居民序列帧的 Blender 脚本
Docs/                      通用设计、版本需求、接口说明和审查报告
build/                     本地导出目录，不提交
```

新增文件时遵循现有职责边界。脚本放在对应功能目录中，文件使用 `PascalCase.gd`；
场景、资源和设计文档也放在与其职责一致的位置。

## 4. 核心运行时契约

### 4.1 Autoload 与场景职责

项目有两个 Autoload：

- `WorldGridGlobal`：全局唯一的 `WorldGrid`，在节点初始化时创建，供所有场景共享。
- `TickManager`：游戏时钟、建筑和居民注册表、每刻更新入口。

`World` 只负责所有世界场景都需要的基础设施，例如相机、网格显示和世界级建筑详情页。
具体游戏规则、初始建筑和居民属于 `Colony` 或 `TestScene`，不要塞回 `World`。
调试专用逻辑应留在 `TestScene`、`Scripts/Debug/` 或明确的调试工具中。

### 4.2 每刻更新顺序

`TickManager.advance_tick()` 的固定顺序是：

1. 遍历已登记建筑，调用 `on_tick()`。
2. 遍历已登记居民，调用 `on_tick()`。
3. 发出 `tick_advanced(total_ticks, day, tick_of_day)`。
4. 跨天时发出 `day_advanced(day)`。

新增周期性模拟逻辑时，应接入 `TickManager.register_building()` 或
`TickManager.register_human()`，或在已有实体的 `on_tick()` 中执行，并保证节点退出时注销。
不要为同一个模拟行为再开一条独立的 `_process` 循环，否则更新顺序会不可控。

相机、输入、鼠标预览、UI 重绘等帧级表现可以使用 `_process`，但不能借它绕过刻调度。

### 4.3 时间与数值

时间常量集中在 `Scripts/Core/TickManager.gd`：

- 游戏内一天是 `1800` 刻。
- 默认现实 `6` 刻/秒，所以一天约现实 `300` 秒。
- 游戏内一天按 `6` 小时换算，一刻约为 `12` 游戏秒。

移动速度、日消耗和补给提前量都应按 `TICKS_PER_DAY` 和游戏内秒计算，而不是按帧率或现实时间。
改 `TICKS_PER_DAY` 会影响多个系统；改 `TICKS_PER_SECOND` 只应影响现实中的播放速度。
修改时间逻辑时同时核对源码注释，避免重新引入旧的 `300` 刻或 `0~299` 说法。

### 4.4 坐标与寻路

- 不带 `world` 字样的公开网格接口通常接收和返回格子坐标 `Vector2i`。
- `cell_to_world()` 返回格子中心像素坐标，`world_to_cell()` 返回所在格子。
- 建筑左上角、建筑入口和 AI 路径都使用格子坐标。
- 寻路起点或终点不可走时返回空数组。
- 斜向移动只有在两侧都不被阻挡时才允许，避免角色穿墙角。

修改移动、放置或 UI 点击逻辑时，先确认当前变量是格子坐标还是像素坐标，禁止混用。

### 4.5 建筑放置与注册

放置分为“校验”和“提交”两步：

- `Building.can_place_at()` 只校验，不修改世界。
- `Building.place_at()` 校验成功后设置 `origin_cell`、占用网格并尝试注册到 `TickManager`。

建筑必须在世界范围内，本体每格可走，本体不能覆盖已有建筑入口。自己的入口必须在建筑外、
与建筑边相邻、在世界内且可走；不同建筑的入口可以重叠。只有 `is_placed == true`
且已经进入场景树的建筑才注册；预览和失败建筑不注册。节点离开场景树时自动注销。

不要在放置流程之外手工向 `TickManager.buildings` 追加建筑。新增或修改放置流程时要覆盖：

- 非法位置不注册、不占格。
- 重叠建筑和覆盖入口的放置失败。
- 入口重叠仍可放置。
- 新建筑压住居民时，居民能离开并继续行为。
- 已放置建筑退出场景树后不再参与每刻更新。

`Building.remove()` 会先结束雇佣和周期，再注销建筑、恢复占格并清算自带库存。
修改拆除流程时仍必须保证 UI 引用、居民占用和物资锁定不产生悬空关系。

### 4.6 居民、AI 与移动

居民必须通过 `Human.create()` 从 `Scenes/Human/Human.tscn` 创建，不要直接 `Human.new()`，
否则会缺少 `BuffSystem`、`Visual` 和场景中配置的 AI 节点。

`Human.on_tick()` 的当前顺序是：

1. 推进 Buff。
2. 扣水和食物。
3. 推进 AI；工作闸门由 AI 在 `Traveling`、`Waiting`、`Working` 状态内检查。

`Docs/v0.0.1.3(居民ai重构)/设计/README.md` 和 `HumanAI职责与接口.md` 描述当前边界：
`HumanAI` 负责决策和行动状态，`HumanMotion` 负责寻路、移动和离站，`HumanVisual`
负责表现，`BuffSystem` 负责状态效果。`HumanAI` 下的 `StateChart` 是动作状态事实来源，
`HumanMotion` 是唯一移动实现。

修改 AI、移动或建筑进出站逻辑时尤其遵守以下约束：

- 同一刻只允许一个所有者推进居民移动。
- 路径失败必须退出对应的 `Traveling` / `LeavingWork` 状态，不能永久停留。
- 从工作站内部出发时，先确认新路线可达，再原子地离站、清除 `in_building`、更新位置和恢复显示。
- 被建筑挤出时暂停普通决策，脱困结束后重新决策。
- Buff 禁止工作时，不能新选工作，也不能继续前往、等待或留在工作站。
- 当前测试和调试面板通过 `get_debug_snapshot()` 和 `HumanMotion` 读取状态，不直接访问 AI 私有字段。

### 4.7 Buff

新增 Buff 至少涉及三处：

1. 在 `GlobalEnum.BuffType` 增加枚举。
2. 在 `Scripts/Buff/Types/` 增加继承 `BuffBase` 的脚本。
3. 在 `BuffSystem.REGISTRY` 登记类型到脚本的映射。

`BuffSystem` 统一管理添加、重复添加、每刻计时、到期移除和效果汇总。Buff 自己不负责倒计时，
时长通过 `duration` 配置。清理临时状态或恢复被修改的数据应放在 `on_remove()`。
多个 Buff 的工作闸门取逻辑与，速度、消耗和各目标权重倍率相乘。

修改 Buff 后必须更新或扩展 `BuffSelfTest`，检查实际倍率、闸门、持续刻数和到期清理。

### 4.8 UI 与输入

- `BuildingDetailPanel` 不识别具体建筑，内容由各建筑的 `build_detail()` 和 `add_row()` 提供。
- 建筑详情页每刻刷新；不要在面板里为每种建筑写类型分支。
- 放置模式下必须禁用已有建筑的点击区，否则建筑按钮会吞掉左键事件。
- `DebugUI` 只负责显示和发出选择信号，实际放置由 `PlacementController` 完成。

## 5. 编码规范

- 使用 UTF-8 编码和 LF 换行，配置见 `.editorconfig` 与 `.gitattributes`。
- GDScript 使用 Tab 缩进。仓库里少数旧文件使用空格，不要为此做无关联的全文件格式化。
- 变量、函数、参数和信号使用 `snake_case`；类和脚本文件使用 `PascalCase`；
  常量使用 `UPPER_SNAKE_CASE`；枚举值与现有项目保持一致。
- 尽量为变量、参数、返回值、数组元素和信号参数声明静态类型。
- 优先复用现有基类、信号、注册接口和状态接口，不为单个调用点新增通用框架。
- 数值规则优先放进有名字的常量或现有调参位置，不要在多个脚本里复制魔法数字。
- 注释和文档使用中文，解释职责、约束和不易看出的原因；避免逐行复述代码。
- 对可能失效的节点引用使用 `is_instance_valid()`；遍历可删除集合时先 `duplicate()`。
- 不要把测试专用逻辑、日志刷屏或临时断言带进正式规则层。

新增建筑的一般路径：

1. 新建继承 `Building` 的脚本并设置 `building_type`、尺寸、入口、名称和颜色。
2. 需要新类型时更新 `GlobalEnum.BuildingType`、`Building.GLYPH_TEXTURES` 和资源。
3. 需要玩家放置时更新 `PlacementController.Kind`、创建分支和 `DebugUI` 按钮。
4. 需要详情时覆盖 `build_detail()`，通过 `add_section()` / `add_row()` 提供内容。
5. 用 `--autoplace` 和普通模拟检查放置、寻路、等待和注销行为。

## 6. 场景、资源与 UID

- 场景和资源优先在 Godot 编辑器中修改，避免手工破坏序列化格式和节点引用。
- 新增或重命名脚本后，同时提交 Godot 生成的同名 `.gd.uid` 文件。
- 移动场景、脚本或资源时同步修复 `uid://` 和 `res://` 引用，再执行无头导入检查。
- `.tscn`、`.tres`、Autoload、导出预设和输入映射属于共享接口；修改时说明影响范围。
- `Assets/` 中同时保留源资源和 Godot 生成的 `.import` 文件。
- 不提交 `.godot/`、`.idea/`、`build/` 或本机缓存。`build/` 只用于本地导出。

## 7. 测试与验证

项目没有单元测试框架，以下检查是当前交付标准。

### 7.1 每次代码或场景改动

```powershell
godot --headless --path . --import
git diff --check
```

导入通过只说明资源能够解析，仍需运行与改动相关的场景测试。

### 7.2 常规模拟

```powershell
godot --headless --path . Scenes/TestScene.tscn -- --speed=20 --max-ticks=600
```

重点检查是否存在脚本错误，以及居民能否取水、取食、上班、等待和持续消耗。
涉及跨天或长期状态时，可把 `--max-ticks` 提升到 `5400` 或按需求设置，但必须保留上限。

### 7.3 放置与寻路

```powershell
godot --headless --path . Scenes/TestScene.tscn -- --autoplace --speed=20 --max-ticks=60
```

读取 `[AUTOPLACE]` 日志并核对“应 true / 应 false”的结果。日志不是自动断言，不能只看进程退出。

### 7.4 Buff

```powershell
godot --headless --path . Scenes/TestScene.tscn -- --bufftest --speed=20 --max-ticks=140
```

核对疲劳层数与速度倍率、眩晕工作闸门、口渴逐刻扣水和自动到期。新增 Buff 时同步扩展自检。

### 7.5 人工验证

以下改动还必须在编辑器中或可交互运行中检查：

- 相机拖动、缩放和快捷键。
- UI 布局、窗口缩放、文本截断、按钮点击区和层级遮挡。
- 建筑预览、连续放置、右键或 ESC 取消。
- 居民动画、朝向、进出工作站时的显示状态。
- 截图和实际画面是否与逻辑状态一致。

视觉改动应附截图或在最终说明中明确尚未人工验证。

## 8. 提交与合并请求

提交信息使用 Conventional Commits，格式为“类型前缀 + 简短中文祈使句”。可用前缀包括
`feat:`、`fix:`、`refactor:`、`docs:`、`style:`、`build:` 和 `chore:`。

```text
fix: 放置建筑时点已有建筑不再被其点击区吞掉
refactor: 将居民移动逻辑迁移到 HumanMotion
```

合并请求应包含：

- 行为变化和设计取舍。
- 关联 Issue（如有）。
- 实际执行的验证命令和结果。
- UI 或视觉变化截图。
- 对场景、资源、Autoload、导出预设等共享配置的特别说明。

保持改动范围聚焦。不要顺带重排无关场景、批量改写旧文件缩进，或回退工作区中他人已有的修改。

## 9. 已知陷阱

- 主场景是 `Colony`，但自动化检查通常显式加载 `TestScene`；不要假设主场景包含测试设施。
- `TestScene` 的 `--max-ticks` 是测试自动退出机制，不是游戏规则。
- 拆除建筑会取消相关工作和周期；不要把直接 `queue_free()` 当作完整拆除流程。
- `TICKS_PER_DAY` 是 `1800`，`TickManager` 的一天刻数、倍速和游戏内秒换算必须一起核对。
- 状态脚本覆盖插件回调时先调用 `super._ready()`，否则 `godot_state_charts` 的内部状态引用不会建立。
- 建筑放置不检查是否站着居民；压住人时要靠脱困流程处理，不是放置失败。
- `WorldGrid.world_to_cell()` 会把世界外坐标夹到边界格，做严格范围校验时应先用 `is_in_bounds()`。
- 预览建筑不能注册、不能占格，也不能接收会吞掉放置点击的鼠标事件。
- 居民必须从场景实例化；直接构造会丢失组件。
- 无头运行没有人工画面判断，UI、相机、动画和输入仍需单独验证。
