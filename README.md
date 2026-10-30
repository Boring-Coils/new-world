# New World

使用 Godot 4.7 和 GDScript 开发的 2D 殖民地模拟原型，当前版本为 `0.0.1.4`。

游戏按“刻”推进。居民在生存需求、雇佣关系和班次之间做决策，通过状态机移动，
在建筑入口完成取水、取食或工作准备；工作周期使用全局物资账本完成锁定、预留和结算。

## 运行

需要 Godot 4.7。仓库根目录执行：

```powershell
godot --editor --path .
```

主场景是 `Scenes/Colony.tscn`。集成检查使用 `Scenes/TestScene.tscn`：

```powershell
godot --headless --path . --scene res://Scenes/TestScene.tscn -- --speed=20 --max-ticks=600
```

`--max-ticks` 不是游戏规则，只用于让无头测试自动退出。

## v0.0.1.4 功能

- 可雇佣建筑维护目标人数、最大人数、年龄资格和雇员名单，每刻复检并补齐或随机解雇。
- 居民同一时间最多有一个雇主；未就业和下班居民前往 `WAIT_PLACE` 附近的稳定个人偏移点。
- 默认班次为当前游戏日的 `600..1499` 刻；班次内开始的周期可以跨过下班时刻完成。
- 工作周期先锁定需求、预留产出空间并补齐路线，锁定后才开始计时和结算。
- 眩晕、虚弱、解雇、雇主删除等硬中断会取消周期并归还需求和空间。
- 物资系统支持废料、金属、塑料、线四种物品，以及数量锁定、容量预留、跨仓拆分和原子结算。
- 独立仓库默认容量 2000，可工作建筑默认自带库存 1000。
- 建筑和居民退出时会清理雇佣、工作、锁定、预留和库存，不留下悬空引用。
- 建筑详情页支持目标人数输入，以及库存容量、已用、预留、可用体积和各物品数量。

详细规则见
[v0.0.1.4 设计目录](Docs/v0.0.1.4(物质系统与雇佣工作机制)/README.md)。

## 操作

| 操作 | 用途 |
| --- | --- |
| 空格 | 暂停 / 继续 |
| `1` 到 `4` | 切换 1、2、5、20 倍速 |
| 鼠标中键拖动 | 平移视角 |
| `WASD` 或方向键 | 平移视角 |
| 滚轮 | 缩放 |
| 单击建筑 | 打开详情页 |
| 左键 | 放置模式下放下建筑或居民 |
| 右键 / `Esc` | 取消放置 |

放置按钮在左上角调试面板中。放下一个后不会自动退出放置模式，可以连续放置。

## 时间与地图

- 游戏内一天是 `1800` 刻。
- 默认现实 `6` 刻/秒，因此一天约现实 300 秒。
- 一天按游戏内 6 小时换算，一刻约 12 游戏秒。
- 地图为 `1000 × 1000` 格，`1 格 = 1 米`，每格 10 像素。

## 代码位置

| 目录 | 内容 |
| --- | --- |
| `Scripts/Core/` | 游戏时钟、物资账本和全局服务 |
| `Scripts/World/` | 世界骨架、殖民地、相机、放置控制 |
| `Scripts/Grid/` | 网格、A* 寻路和坐标换算 |
| `Scripts/Building/` | 建筑基类、取水站、取食站、工作站、仓库 |
| `Scripts/Human/` | 居民、移动、外观、AI、状态机和工作行为 |
| `Scripts/Material/` | 物品、库存、工作类型和工作周期模型 |
| `Scripts/Buff/` | Buff 系统、基类和具体效果 |
| `Scripts/Debug/` | 调试面板、放置自检、Buff 自检和完整验收自检 |
| `Scripts/UI/` | 建筑详情页 |
| `Scenes/` | 主场景、测试场景和居民场景 |
| `Assets/` | 图标与居民序列帧 |
| `Docs/` | 需求、设计和验收记录 |

常用调参位置：

- 一天刻数、现实走时速度：`Scripts/Core/TickManager.gd`
- 居民日消耗：`Scripts/Human/Human.gd`
- 年龄速度、寻路和等待点偏移：`Scripts/Human/HumanMotion.gd`
- 目标权重和状态转换：`Scripts/Human/HumanAI/`
- 工作需求、产出和周期耗时：`Scripts/Building/WorkStation.gd`
- 物品体积和显示名：`Scripts/Material/MaterialTypes.gd`

## 测试

项目没有单元测试框架，以 Godot 无头场景、日志断言和编辑器检查为主。

```powershell
# 资源导入和脚本解析
godot --headless --path . --import

# v0.0.1.4 完整验收，逐项输出 [ACCEPT] PASS/FAIL
godot --headless --path . --log-file .godot/v014_acceptance.log --scene res://Scenes/TestScene.tscn -- --acceptance

# 常规模拟
godot --headless --path . --scene res://Scenes/TestScene.tscn -- --speed=20 --max-ticks=600

# 放置、重叠和挤出
godot --headless --path . --scene res://Scenes/TestScene.tscn -- --autoplace --speed=20 --max-ticks=60

# Buff 数值、工作闸门和到期
godot --headless --path . --scene res://Scenes/TestScene.tscn -- --bufftest --speed=20 --max-ticks=140
```

完整验收覆盖 15 个雇佣、7 个班次/等待、16 个工作周期、19 个库存、10 个清算
和 7 个 UI 契约检查。命令退出码为 0 只代表进程结束，仍需确认
`[ACCEPT] SUMMARY` 的失败数为 0，并检查 `SCRIPT ERROR`、未预期警告和日志中的不变量。

UI 截图可用：

```powershell
godot --path . --windowed --resolution 800x600 --scene res://Scenes/TestScene.tscn -- --ui-demo=work --speed=20 --max-ticks=20 --shot=ui_work.png
godot --path . --windowed --resolution 800x600 --scene res://Scenes/TestScene.tscn -- --ui-demo=warehouse --speed=20 --max-ticks=20 --shot=ui_warehouse.png
```

开发前请阅读 [AGENTS.md](AGENTS.md) 中的代码边界、每刻顺序和验证要求。
