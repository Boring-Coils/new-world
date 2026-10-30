extends Building
class_name ScrapSortingStation

## 废料分拣站：居民只要有空就会来，在出入口停留 [constant WAIT_TICKS] 刻后进入建筑内部。[br]
## 进去以后居民模型隐藏，站内人数由占用名单统计，[br]
## 水和食物照常消耗，直到某一项触发补给需求才从出入口出来。[br]
## 默认执行废料分拣：6 废料 -> 1 金属 + 1 塑料 + 1 线。

## 到达出入口后要等几刻才进门
const WAIT_TICKS: int = 1

## 站在里面的居民（按进来的顺序排站位）
var occupants: Array[Human] = []


func _init() -> void:
	building_type = GlobalEnum.BuildingType.WORK
	size_cells = Vector2i(6, 4)
	entrance_offsets = [Vector2i(2, 4), Vector2i(3, -1)]
	body_color = Color(0.45, 0.45, 0.5)
	display_name = "废料分拣站"
	is_hireable = true
	max_workers = 3
	target_workers = 3
	inventory_capacity = 1000
	work_type = WorkType.create_scrap_sorting()


func get_wait_ticks() -> int:
	return WAIT_TICKS


## 居民进门：登记占用；显隐由 [Human] 的语义接口执行。
func enter(human: Human) -> bool:
	if not occupants.has(human):
		occupants.append(human)
	return true


## 居民出门：从名单里移除。
func leave(human: Human) -> void:
	occupants.erase(human)


## 现在里面还有几个人（调试面板用）
func get_occupant_count() -> int:
	return occupants.size()


## 详情页
func build_detail() -> void:
	super.build_detail()
