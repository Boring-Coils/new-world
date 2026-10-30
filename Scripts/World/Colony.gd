## 正式殖民地场景的根节点。[br]
## 在 [World] 基础设施之上连接调试面板与放置控制器，并提供主场景所需的最小交互入口。
extends World

## 左上角调试与建造面板。
@onready
var debug_UI: DebugUI = $DebugUI

## 处理建筑和居民预览、校验与提交的放置控制器。
@onready
var placer: PlacementController = $PlacementController


## 初始化世界基础设施，并连接建造选择与放置结果提示。
func _ready() -> void:
	super._ready()
	debug_UI.kind_selected.connect(placer.select_kind)
	placer.notice.connect(debug_UI.set_hint)
