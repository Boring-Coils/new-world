extends Building
class_name WorkStation

## 工作站：居民只要有空就会来，在出入口停留 [constant WAIT_TICKS] 刻后进入建筑内部。[br]
##
## 进去以后就站在建筑里的某个格子上（半透明显示，一眼能数出里面有几个人），
## 水和食物照常消耗，直到某一项触发补给需求才从出入口出来。
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


func get_wait_ticks() -> int:
	return WAIT_TICKS


## 居民进门：给他安排一个内部站位
func enter(human: Human) -> void:
	occupants.append(human)
	human.position = _slot_position(occupants.size() - 1)


## 居民出门：后面的人往前补一个位置，避免中间空一格
func leave(human: Human) -> void:
	occupants.erase(human)
	for i in range(occupants.size()):
		occupants[i].position = _slot_position(i)


## 第 [param index] 个内部站位（从建筑内部左上角开始按格排开）
func _slot_position(index: int) -> Vector2:
	var cols := maxi(size_cells.x - 1, 1)
	var col := index % cols
	var row := index / cols
	var cell := origin_cell + Vector2i(1 + col, 1 + row)
	# 人多到排不下时，挤在最后一行
	cell.x = clampi(cell.x, origin_cell.x, origin_cell.x + size_cells.x - 1)
	cell.y = clampi(cell.y, origin_cell.y, origin_cell.y + size_cells.y - 1)
	return WorldGridGlobal.world.cell_to_world(cell)
