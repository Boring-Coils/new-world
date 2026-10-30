## 独立公共仓库。[br]
## 占用 3×4 格，默认容量 2000，可接收所有合法物资，不参与雇佣和生产。
extends Building
class_name Warehouse

## 初始化仓库类型、尺寸、入口、显示名和库存容量。
func _init() -> void:
	building_type = GlobalEnum.BuildingType.WAREHOUSE
	size_cells = Vector2i(3, 4)
	entrance_offsets = [Vector2i(1, 4)]
	body_color = Color(0.55, 0.42, 0.28)
	display_name = "仓库"
	is_warehouse = true
	inventory_capacity = 2000


## 返回居民访问仓库时在入口等待的刻数。
func get_wait_ticks() -> int:
	return 1
