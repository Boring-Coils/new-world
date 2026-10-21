extends Building
class_name FoodStation

## 取食站：无限食物。[br]
##
## 居民走到任意一个出入口后原地等待 [constant WAIT_TICKS] 刻，食物补满。
## 现在是测试用建筑，功能极简。

## 到达出入口后要等几刻
const WAIT_TICKS: int = 2


func _init() -> void:
	building_type = GlobalEnum.BuildingType.FOOD
	size_cells = Vector2i(4, 3)
	# 两个出入口：正上方和正下方各一个，用来验证「多出入口」的写法
	entrance_offsets = [Vector2i(1, 3), Vector2i(2, -1)]
	body_color = Color(0.95, 0.65, 0.2)


func get_wait_ticks() -> int:
	return WAIT_TICKS
