extends Building
class_name WaterStation

## 取水站：无限水。[br]
##
## 居民走到任意一个出入口后原地等待 [constant WAIT_TICKS] 刻，水补满。
## 现在是测试用建筑，功能极简。

## 到达出入口后要等几刻
const WAIT_TICKS: int = 2


func _init() -> void:
	building_type = GlobalEnum.BuildingType.WATER
	size_cells = Vector2i(4, 3)
	# 默认一个出入口，在建筑正上方中间那一格
	entrance_offsets = [Vector2i(1, 3)]
	body_color = Color(0.25, 0.55, 0.95)
	display_name = "无限取水站"


func get_wait_ticks() -> int:
	return WAIT_TICKS
