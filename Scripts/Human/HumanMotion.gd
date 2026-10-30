## 居民的唯一移动实现。[br]
## 负责路径缓存、逐刻连续移动、选择建筑出入口，以及被建筑压住后的脱困移动。[br]
## 本组件不选择目标，也不直接写 AI 状态；由 [HumanAI] 每刻调用一次 [method on_tick]。[br]
## 建筑内路线先从出入口出发，离站时必须完成占用清理、位置更新和显示恢复。
extends Node
class_name HumanMotion

## 开始沿一条新路径移动
signal movement_started(destination: Vector2i)

## 当前路径走完
signal arrived(destination: Vector2i)

## 找不到通往目标格子的路径
signal path_failed(destination: Vector2i)

## 当前是否正在移动发生变化
signal moving_changed(moving: bool)

## 本刻的移动方向发生变化，供外观组件选择朝向
signal facing_changed(direction: Vector2)

## 脱困成功结束（沿路径走完、直接落到安全格或确认无需移动）
signal relocation_finished

## 居民完成离站状态切换
signal building_exited(building: Building, exit_cell: Vector2i)

## 成年人一天能走多少格
const WALK_CELLS_PER_DAY: float = 750.0

## 儿童移动速度倍率
const CHILD_SPEED_SCALE: float = 0.71

## 老年人移动速度倍率
const OLD_SPEED_SCALE: float = 0.86

## 无效格子坐标，用作内部哨兵值
const INVALID_CELL: Vector2i = Vector2i(-1, -1)

## 控制本组件的居民，由 [method bind] 或父节点自动绑定
var human: Human = null

## 当前路径（格子坐标，包含起点）
var path: Array[Vector2i] = []

## 下一个要到达的路径点索引
var path_index: int = 0

## 当前路径终点
var destination_cell: Vector2i = INVALID_CELL

## 最终落点相对目标格中心的偏移，用于等待点等实际位置语义。
var destination_offset: Vector2 = Vector2.ZERO

# 个体移动速度偏移，避免所有居民以完全相同的速度行走。
var _random_speed_offset: float = 1.0

# 当前是否处于被建筑挤出后的特殊移动。
var _is_relocating: bool = false

# 当前移动状态，用于只在开始或结束时发送一次信号。
var _moving: bool = false


## 初始化每个居民独立的随机速度偏移。
func _init() -> void:
	_random_speed_offset = 0.9 + randf() * 0.2


## 未显式绑定时，从父节点自动取得所属居民。
func _ready() -> void:
	if human == null:
		human = get_parent() as Human


## 显式绑定居民。组件作为 [Human] 的子节点时通常不需要手动调用。[br]
## [param host] 是使用本移动组件的居民实例。
func bind(host: Human) -> void:
	human = host


## 当前是否正在沿路径移动[br]
## 返回路径中是否仍有尚未到达的路径点。
func is_moving() -> bool:
	return not path.is_empty() and path_index < path.size()


## 当前是否正在执行脱困移动[br]
## 返回当前移动是否属于被建筑挤出后的安全格转移。
func is_relocating() -> bool:
	return _is_relocating


## 当前路径的格子数量，供测试和调试面板读取[br]
## 返回当前缓存路径包含的路径点数量。
func get_path_size() -> int:
	return path.size()


## 移动到建筑最近的、按实际寻路距离可达的出入口。[br]
## [param building] 是移动目标建筑。[br]
## 返回是否成功开始移动。
func move_to_building(building: Building) -> bool:
	if not _can_move() or not is_instance_valid(building):
		return _fail_move()

	var route := _find_route_to_building(building)
	return _start_route(route, false)


## 移动到某一格。参数是世界格子坐标，不是像素坐标。[br]
## [param cell] 是目标格坐标。[br]
## 返回是否成功找到路径并开始移动。
func move_to_cell(cell: Vector2i) -> bool:
	if not _can_move():
		return _fail_move(cell)

	var route := _find_route_to_cell(cell)
	return _start_route(route, false)


## 移动到世界坐标附近。只允许最终偏移不超过半格；[br]
## [param world_position] 是期望到达的世界像素坐标。[br]
## 寻路仍以格子为单位，HumanMotion 继续是唯一移动实现。[br]
## 返回是否成功找到路径并开始移动。
func move_to_position(world_position: Vector2) -> bool:
	if not _can_move():
		return _fail_move()
	var world := WorldGridGlobal.world
	var cell := world.world_to_cell(world_position)
	var center := world.cell_to_world(cell)
	var offset := world_position - center
	var half_cell := WorldGrid.CELL_SIZE * 0.5
	offset.x = clampf(offset.x, -half_cell + 0.01, half_cell - 0.01)
	offset.y = clampf(offset.y, -half_cell + 0.01, half_cell - 0.01)
	var route := _find_route_to_cell(cell)
	if route.is_empty():
		return _fail_move(cell)
	route["final_offset"] = offset
	return _start_route(route, false)


## 找到某一类建筑中，按实际寻路距离最近的一个。[br]
## [param building_type] 是要搜索的建筑类型。[br]
## 返回最近且可达的建筑；不存在可达建筑时返回 null。
func find_nearest_building(building_type: GlobalEnum.BuildingType) -> Building:
	var route := _find_nearest_route_to_type(building_type)
	if route.is_empty():
		return null
	return route["building"] as Building


## 找到某一类建筑中，按实际寻路距离最近且可达的出入口。[br]
## [param building_type] 是要搜索的建筑类型。[br]
## 返回最近可达的建筑出入口格；不存在时返回 [constant INVALID_CELL]。
func find_nearest_entrance(building_type: GlobalEnum.BuildingType) -> Vector2i:
	var route := _find_nearest_route_to_type(building_type)
	if route.is_empty():
		return INVALID_CELL
	return route["entrance_cell"] as Vector2i


## 移动到某一类建筑中按实际寻路距离最近的建筑。[br]
## [param building_type] 是要搜索并前往的建筑类型。[br]
## 返回是否成功找到路线并开始移动。
func move_to_nearest_building(building_type: GlobalEnum.BuildingType) -> bool:
	if not _can_move():
		return _fail_move()

	var route := _find_nearest_route_to_type(building_type)
	return _start_route(route, false)


## 从当前状态出发，到某一类建筑最近的出入口大约需要多少刻。[br]
## [param building_type] 是要估算行程的建筑类型。[br]
## 找不到可达建筑或居民无效时返回 -1。
func get_ticks_to_building(building_type: GlobalEnum.BuildingType) -> int:
	var route := _find_nearest_route_to_type(building_type)
	if route.is_empty():
		return -1

	return _get_ticks_for_route(route)


## 到指定建筑的预计移动刻数。找不到路线返回 -1。[br]
## [param building] 是要估算行程的目标建筑。
func get_ticks_to_building_instance(building: Building) -> int:
	var route := _find_route_to_building(building)
	if route.is_empty():
		return -1
	return _get_ticks_for_route(route)


## 根据路线世界距离和当前每刻速度估算所需刻数。[br]
## [param route] 是包含 world 距离的路线记录。[br]
## 路线为空或速度无效时返回 -1。
func _get_ticks_for_route(route: Dictionary) -> int:
	if route.is_empty():
		return -1
	var speed_pixels := get_speed_cells_per_tick() * float(WorldGrid.CELL_SIZE)
	if speed_pixels <= 0.0:
		return -1

	return ceili(float(route["distance"]) / speed_pixels)


## 被新建筑压住时调用：走到最近的可走格，并清理可能残留的建筑占用和隐藏状态。[br]
## 如果当前脚下已经是不可走格，会临时放行当前格来计算离开建筑的路径，随后恢复原状态。[br]
## 返回是否成功开始脱困移动或直接完成脱困。
func relocate_to_nearest_walkable() -> bool:
	if not _can_move():
		return false

	var world := WorldGridGlobal.world
	var from_cell := world.world_to_cell(human.position)
	var target_cell := world.find_nearest_walkable(from_cell)
	if not is_instance_valid(human.in_building):
		human.set_world_visibility(true)
	if target_cell == from_cell:
		if world.is_walkable(target_cell):
			if is_instance_valid(human.in_building):
				_commit_building_exit(from_cell)
			_clear_path()
			relocation_finished.emit()
			return true
		push_error("%s 脱困失败：当前格 %s 不可走，附近也没有安全格" % [
			human.name,
			from_cell,
		])
		return false

	var was_walkable := world.is_walkable(from_cell)
	if not was_walkable:
		world.set_walkable(from_cell, true)
	var route := _find_route_to_cell(target_cell)
	if not was_walkable:
		world.set_walkable(from_cell, false)

	if route.is_empty():
		# 没有连续可走的路径时仍要离开不可走格，直接放到最近空地上。
		if not _commit_building_exit(target_cell):
			human.position = world.cell_to_world(target_cell)
		_clear_path()
		arrived.emit(target_cell)
		relocation_finished.emit()
		return true

	return _start_route(route, true)


## 每刻由居民或 AI 调用一次，沿当前路径推进。
func on_tick() -> void:
	if not is_moving():
		return
	if not is_instance_valid(human):
		_clear_path()
		return

	var step := get_speed_cells_per_tick() * float(WorldGrid.CELL_SIZE)
	if step <= 0.0:
		return

	var world := WorldGridGlobal.world
	# 单刻可以跨过多个路径点，循环消耗剩余步长直到停在一个格间位置。
	while step > 0.0 and path_index < path.size():
		var target_position := world.cell_to_world(path[path_index])
		if path_index == path.size() - 1:
			target_position += destination_offset
		var offset := target_position - human.position
		var distance := offset.length()

		if offset.length_squared() > 0.000001:
			facing_changed.emit(offset)

		if distance <= step:
			human.position = target_position
			step -= distance
			path_index += 1
		else:
			human.position += offset / distance * step
			step = 0.0

	if path_index >= path.size():
		_finish_path()


## 每刻能走多少格，包含年龄、个体速度偏移和 Buff 速度倍率。[br]
## 返回当前居民本刻可移动的格数；居民无效时返回 0。
func get_speed_cells_per_tick() -> float:
	if not is_instance_valid(human):
		return 0.0

	# 年龄阶段先给出基础倍率，再叠加个体偏移和 Buff 速度倍率。
	var speed_scale := 1.0
	match human.age_status:
		GlobalEnum.AgeStatus.CHILD:
			speed_scale = CHILD_SPEED_SCALE
		GlobalEnum.AgeStatus.OLD:
			speed_scale = OLD_SPEED_SCALE

	var buff_multiplier := 1.0
	if is_instance_valid(human.buff_system):
		buff_multiplier = human.buff_system.get_speed_multiplier()

	return (
		WALK_CELLS_PER_DAY
		* speed_scale
		/ float(TickManager.TICKS_PER_DAY)
		* _random_speed_offset
		* buff_multiplier
	)


## 立即停止当前移动，不改变居民所在位置。
func stop() -> void:
	_clear_path()
	_is_relocating = false


## 不前往其他目标，只从当前建筑最近的一个出入口离开。[br]
## 用于工作中被 Buff 中断、取消目标等没有移动目的地的场景。[br]
## 离站、位置更新、清空 [member Human.in_building] 和恢复显示会在同一次调用中完成。[br]
## 返回是否实际完成离站；居民不在建筑内部时返回 [code]false[/code]。
func leave_current_building() -> bool:
	if not is_instance_valid(human) or not is_instance_valid(human.in_building):
		return false

	var from_cell := WorldGridGlobal.world.world_to_cell(human.position)
	var exit_cell := human.in_building.get_nearest_entrance_cell(from_cell)
	return _commit_building_exit(exit_cell)


## 计算到某一建筑的最优路线。[br]
## [param building] 是要前往的目标建筑。[br]
## 返回字典包含 building、path、exit_cell、entrance_cell、distance。[br]
## 居民在建筑内部时，会遍历当前建筑的所有出入口，选择“出口到目标入口”路径最短的一条。
func _find_route_to_building(building: Building) -> Dictionary:
	if not is_instance_valid(building):
		return {}

	var world := WorldGridGlobal.world
	var starts := _get_route_starts()
	var best := {}
	# 每个合法起点到每个入口都计算一次，按实际世界距离选出最短组合。
	for start_cell in starts:
		for entrance_cell in building.get_entrance_cells():
			var candidate_path := world.get_path(start_cell, entrance_cell)
			if candidate_path.is_empty():
				continue

			var distance := _get_path_world_length(candidate_path)
			if best.is_empty() or distance < float(best["distance"]):
				best = {
					"building": building,
					"path": candidate_path,
					"exit_cell": start_cell,
					"entrance_cell": entrance_cell,
					"distance": distance,
				}
	return best


## 计算到单个格子的最优路线。[br]
## [param target_cell] 是目标格坐标。[br]
## 返回包含 path、exit_cell、entrance_cell、distance 的路线记录；不可达时返回空字典。
func _find_route_to_cell(target_cell: Vector2i) -> Dictionary:
	var world := WorldGridGlobal.world
	if not world.is_in_bounds(target_cell) or not world.is_walkable(target_cell):
		return {}

	# 从建筑内出发时可能有多个候选出口，因此仍需逐个比较完整路径。
	var best := {}
	for start_cell in _get_route_starts():
		var candidate_path := world.get_path(start_cell, target_cell)
		if candidate_path.is_empty():
			continue

		var distance := _get_path_world_length(candidate_path)
		if best.is_empty() or distance < float(best["distance"]):
			best = {
				"path": candidate_path,
				"exit_cell": start_cell,
				"entrance_cell": target_cell,
				"distance": distance,
			}
	return best


## 在某一类建筑里找实际寻路距离最近的一条路线。[br]
## [param building_type] 是要搜索的建筑类型。[br]
## 返回最短可达路线记录；没有可达建筑时返回空字典。
func _find_nearest_route_to_type(building_type: GlobalEnum.BuildingType) -> Dictionary:
	var best := {}
	for building in TickManager.get_buildings_of_type(building_type):
		var route := _find_route_to_building(building)
		if route.is_empty():
			continue
		if best.is_empty() or float(route["distance"]) < float(best["distance"]):
			best = route
	return best


## 路线的候选起点。[br]
## 在普通状态下就是居民当前格；在建筑内部时则是这栋建筑的所有出入口。[br]
## 返回可用于寻路的候选起点格数组。
func _get_route_starts() -> Array[Vector2i]:
	if is_instance_valid(human) and is_instance_valid(human.in_building):
		return human.in_building.get_entrance_cells()
	if not is_instance_valid(human):
		return []
	return [WorldGridGlobal.world.world_to_cell(human.position)]


## 按格子中心之间的实际世界距离累加整条路径长度。[br]
## [param cell_path] 是需要测量长度的格子路径。[br]
## 返回沿路径逐段累加的世界距离。
func _get_path_world_length(cell_path: Array[Vector2i]) -> float:
	var total := 0.0
	var world := WorldGridGlobal.world
	for i in range(1, cell_path.size()):
		total += world.cell_to_world(cell_path[i - 1]).distance_to(
			world.cell_to_world(cell_path[i])
		)
	return total


## 接受一条路线并开始移动。[br]
## [param route] 是包含路径、离站格和最终偏移的路线记录。[br]
## [param relocating] 指定本次移动是否为脱困移动。[br]
## 返回路线是否有效并已开始执行。
func _start_route(route: Dictionary, relocating: bool) -> bool:
	if route.is_empty():
		return _fail_move()

	var new_path: Array[Vector2i] = route["path"]
	var exit_cell: Vector2i = route["exit_cell"]
	var new_destination: Vector2i = route["entrance_cell"]
	var new_offset: Vector2 = route.get("final_offset", Vector2.ZERO)

	# 路线的 exit_cell 已经过可达性预检，这里在同一调用内完成离站和路径切换。
	_commit_building_exit(exit_cell)

	path = new_path
	path_index = 0
	destination_cell = new_destination
	destination_offset = new_offset
	_is_relocating = relocating
	_set_moving(true)
	movement_started.emit(destination_cell)
	return true


## 原子地完成一次离站。[br]
## [param exit_cell] 是居民离站后应落到的建筑出入口格。[br]
## 顺序固定为先更新占用名单、再传送、清空 in_building，最后恢复显示。[br]
## 整个过程在同一函数调用内完成，Godot 不会在中间状态绘制一帧。[br]
## 返回是否实际完成离站。
func _commit_building_exit(exit_cell: Vector2i) -> bool:
	if not is_instance_valid(human) or not is_instance_valid(human.in_building):
		return false

	var building := human.in_building
	building.leave(human)

	human.position = WorldGridGlobal.world.cell_to_world(exit_cell)
	human.in_building = null
	human.set_world_visibility(true)
	building_exited.emit(building, exit_cell)
	return true


## 路径走完后的统一收尾。
func _finish_path() -> void:
	var reached_cell := destination_cell
	var was_relocating := _is_relocating

	_clear_path()
	arrived.emit(reached_cell)
	if was_relocating:
		relocation_finished.emit()


## 清空路径和本次移动状态。
func _clear_path() -> void:
	path.clear()
	path_index = 0
	destination_cell = INVALID_CELL
	destination_offset = Vector2.ZERO
	_is_relocating = false
	_set_moving(false)


## 开始和结束移动时只发一次信号。[br]
## [param moving] 是新的移动状态。
func _set_moving(moving: bool) -> void:
	if _moving == moving:
		return
	_moving = moving
	moving_changed.emit(moving)


## 公共移动接口的统一前置检查。[br]
## 返回当前居民是否有效、可以接受移动命令。
func _can_move() -> bool:
	return is_instance_valid(human)


## 会创建移动状态的命令统一从这里报告一次失败。[br]
## [param destination] 是失败的目标格，未知目标使用 [constant INVALID_CELL]。[br]
## 返回 [code]false[/code]，便于调用方直接作为移动结果返回。
func _fail_move(destination: Vector2i = INVALID_CELL) -> bool:
	path_failed.emit(destination)
	return false
