extends Building
class_name FoodStation

## 无限取食站。[br]
## 居民走到任意一个出入口后原地等待 [constant WAIT_TICKS] 刻，随后储食补满。[br]
## 当前为测试用建筑，行为极简：没有容量上限，也不排队。

## 到达出入口后需要等待的刻数。
const WAIT_TICKS: int = 2


func _init() -> void:
	building_type = GlobalEnum.BuildingType.FOOD
	size_cells = Vector2i(4, 3)
	# 两个出入口：一个在正下方偏左，一个在正上方偏右（用来验证多出入口的写法）
	entrance_offsets = [Vector2i(1, 3), Vector2i(2, -1)]
	body_color = Color(0.95, 0.65, 0.2)
	display_name = "无限取食站"


func get_wait_ticks() -> int:
	return WAIT_TICKS
