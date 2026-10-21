extends Building
class_name WorkStation

## 工作站：居民只要有空就会来，在出入口停留 [constant WAIT_TICKS] 刻后进入建筑内部（模型消失）。[br]
##
## 进去以后水和食物照常消耗，直到某一项触发补给需求才会出来。
## 现在是测试用建筑，功能极简。

## 到达出入口后要等几刻才进门
const WAIT_TICKS: int = 1


func _init() -> void:
	building_type = GlobalEnum.BuildingType.WORK
	size_cells = Vector2i(6, 4)
	entrance_offsets = [Vector2i(2, 4), Vector2i(3, -1)]
	body_color = Color(0.45, 0.45, 0.5)


func get_wait_ticks() -> int:
	return WAIT_TICKS
