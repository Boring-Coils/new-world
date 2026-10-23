extends Building
class_name WaterStation

## 无限取水站。[br]
## 居民走到任意一个出入口后原地等待 [constant WAIT_TICKS] 刻，随后储水补满。[br]
## 当前为测试用建筑，行为极简：没有容量上限，也不排队。

## 到达出入口后需要等待的刻数。
const WAIT_TICKS: int = 2


func _init() -> void:
	building_type = GlobalEnum.BuildingType.WATER
	size_cells = Vector2i(4, 3)
	# 一个出入口，在建筑正下方偏左一格（y + size_cells.y 才落在底边下方）
	entrance_offsets = [Vector2i(1, 3)]
	body_color = Color(0.25, 0.55, 0.95)
	display_name = "无限取水站"


func get_wait_ticks() -> int:
	return WAIT_TICKS

## 详情页：加一行「水储量」
func build_detail() -> void:
	super.build_detail()
	add_row("status", "水储量", "%d" %-1, "water")
