# 仓库贡献指南

## 项目结构与模块组织

本项目使用 Godot 4.7，主场景为 `Scenes/Colony.tscn`，项目配置位于
`project.godot`。

- `Scripts/` 存放带静态类型的 GDScript，按职责划分为 `Core/`（刻调度）、
  `World/`、`Grid/`、`Building/`、`Human/`、`Buff/`、`UI/`、`Debug/` 和
  `Enum/`。
- `Scenes/` 存放可复用场景，`TestScene.tscn` 用于集成检查。
- `Assets/` 存放导入资源，例如 `Assets/Human/blue/{down,side,up}/`。
- `Tools/Blender/make_human.py` 用于生成居民序列帧。
- `Docs/` 存放按通用主题和版本整理的策划、设计与实现文档。
- `build/` 是本地导出目录，不应提交到仓库。

新增脚本应放在对应功能目录中。脚本文件使用 `PascalCase.gd` 命名，并同时提交
Godot 生成的同名 `.gd.uid` 文件。

## 构建、测试与开发命令

请从仓库根目录执行以下命令，并确保 Godot 已加入 `PATH`：

```powershell
godot --editor --path .
godot --headless --path . --import
godot --headless --path . Scenes/TestScene.tscn -- --speed=20 --max-ticks=600
godot --headless --path . --export-debug "Windows Desktop" build/0.0.1a/new_world.exe
```

第一条命令启动编辑器，第二条刷新导入资源，第三条运行限定时长的模拟测试。可追加
`--autoplace` 或 `--bufftest` 验证放置与 Buff 逻辑；最后一条使用仓库中的
Windows Desktop 导出预设生成调试版本。

## 代码风格与命名规范

- 使用 UTF-8 编码和 LF 换行，配置见 `.editorconfig` 与 `.gitattributes`。
- GDScript 使用 Tab 缩进，优先为变量、参数和返回值声明静态类型。
- 变量、函数和信号使用 `snake_case`；类与脚本文件使用 `PascalCase`；常量使用
  `UPPER_SNAKE_CASE`。
- 遵循现有按功能组合的结构。周期性逻辑应注册到 `TickManager`，不要新增独立的
  `_process` 循环。
- 项目未配置格式化或静态检查工具。修改应与相邻代码保持一致，并通过编辑器或
  无头导入检查语法错误。

## 测试规范

项目尚未引入自动化测试框架，也没有覆盖率要求。应使用主场景并针对
`Scenes/TestScene.tscn` 执行无头测试；测试必须设置 `--max-ticks`，确保进程自动
退出。现有测试参数无法覆盖行为变更时，可在 `Scripts/Debug/` 下添加简短诊断。
相机、放置和 UI 相关修改还应在编辑器中人工验证。

## 提交与合并请求规范

提交信息沿用 Conventional Commits，格式为“类型前缀 + 简短中文祈使句”，可使用的
前缀包括 `feat:`、`fix:`、`refactor:`、`docs:`、`style:`、`build:` 和
`chore:`。例如：

```text
fix: 放置建筑时点已有建筑不再被其点击区吞掉
```

合并请求应说明行为变化、关联相关 Issue、列出验证命令；涉及视觉或 UI 变化时
附截图。修改场景、资源、Autoload 或导出预设时需特别说明。不要提交生成的
`.godot/`、`.idea/` 或 `build/` 内容。
