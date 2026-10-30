## 废料分拣工作站。[br]
## 居民在出入口等待 [constant WAIT_TICKS] 刻后进入建筑内部，站内占用由 [member occupants] 管理。[br]
## 默认执行废料分拣工作：消耗 6 份废料，产出金属、塑料和线材各 1 份。
extends Building
class_name ScrapSortingStation

## 到达出入口后要等几刻才进门
const WAIT_TICKS: int = 1

## 当前位于建筑内部、按进入顺序排列的居民。
var occupants: Array[Human] = []


## 初始化工作站类型、尺寸、入口、雇佣参数、库存和工作配置。
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


## 返回居民进入工作站内部前需要等待的刻数。
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


## 在通用详情内容上追加废料分拣站状态。
func build_detail() -> void:
	super.build_detail()
