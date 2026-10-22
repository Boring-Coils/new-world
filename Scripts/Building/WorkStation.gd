extends Building
class_name WorkStation

## 工作站：居民只要有空就会来，在出入口停留 [constant WAIT_TICKS] 刻后进入建筑内部。[br]
## 进去以后就站在建筑里的某个格子上（半透明显示，一眼能数出里面有几个人），[br]
## 水和食物照常消耗，直到某一项触发补给需求才从出入口出来。[br]
## 现在是测试用建筑，功能极简。

## 到达出入口后要等几刻才进门
const WAIT_TICKS: int = 1

## 站在里面的居民（按进来的顺序排站位）
var occupants: Array[Human] = []


func _init() -> void:
	building_type = GlobalEnum.BuildingType.WORK
	size_cells = Vector2i(6, 4)
	entrance_offsets = [Vector2i(2, 4), Vector2i(3, -1)]
	body_color = Color(0.45, 0.45, 0.5)
	display_name = "无限工作站"


func get_wait_ticks() -> int:
	return WAIT_TICKS


## 居民进门：登记一下，模型在 [Human] 那边隐藏
func enter(human: Human) -> void:
	if not occupants.has(human):
		occupants.append(human)


## 居民出门：从名单里划掉
func leave(human: Human) -> void:
	occupants.erase(human)


## 现在里面还有几个人（调试面板用）
func get_occupant_count() -> int:
	return occupants.size()
