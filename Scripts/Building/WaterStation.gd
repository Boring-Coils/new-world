## 无限取水站。[br]
## 居民到达任意出入口后等待 [constant WAIT_TICKS] 刻，随后水分补满。[br]
## 当前实现没有容量上限和排队机制，主要用于生存循环与寻路验证。
extends Building
class_name WaterStation

## 到达出入口后需要等待的刻数。
const WAIT_TICKS: int = 2


## 初始化取水站类型、尺寸、颜色、显示名和出入口。
func _init() -> void:
	building_type = GlobalEnum.BuildingType.WATER
	size_cells = Vector2i(4, 3)
	# 一个出入口，在建筑正下方偏左一格（y + size_cells.y 才落在底边下方）
	entrance_offsets = [Vector2i(1, 3)]
	body_color = Color(0.25, 0.55, 0.95)
	display_name = "无限取水站"


## 返回居民在出入口补水前需要等待的刻数。
func get_wait_ticks() -> int:
	return WAIT_TICKS

## 在建筑详情页添加无限水储量状态行。
func build_detail() -> void:
	super.build_detail()
	add_row("status", "水储量", "%d" %-1, "water")
