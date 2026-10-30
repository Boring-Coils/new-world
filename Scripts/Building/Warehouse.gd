extends Building
class_name Warehouse

## 独立公共仓库：3x4，默认容量 2000，不参与雇佣。

func _init() -> void:
	building_type = GlobalEnum.BuildingType.WAREHOUSE
	size_cells = Vector2i(3, 4)
	entrance_offsets = [Vector2i(1, 4)]
	body_color = Color(0.55, 0.42, 0.28)
	display_name = "仓库"
	is_warehouse = true
	inventory_capacity = 2000


func get_wait_ticks() -> int:
	return 1
