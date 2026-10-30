## 无限取食站。[br]
## 居民到达任意出入口后等待 [constant WAIT_TICKS] 刻，随后食物补满。[br]
## 当前实现没有容量上限和排队机制，并通过两个出入口验证多入口寻路。
extends Building
class_name FoodStation

## 到达出入口后需要等待的刻数。
const WAIT_TICKS: int = 2


## 初始化取食站类型、尺寸、颜色、显示名和双出入口。
func _init() -> void:
	building_type = GlobalEnum.BuildingType.FOOD
	size_cells = Vector2i(4, 3)
	# 两个出入口：一个在正下方偏左，一个在正上方偏右（用来验证多出入口的写法）
	entrance_offsets = [Vector2i(1, 3), Vector2i(2, -1)]
	body_color = Color(0.95, 0.65, 0.2)
	display_name = "无限取食站"


## 返回居民在出入口取食前需要等待的刻数。
func get_wait_ticks() -> int:
	return WAIT_TICKS

## 在建筑详情页添加无限食物储量状态行。
func build_detail() -> void:
	super.build_detail()
	add_row("status", "食物储量", "%d" %-1, "food")
