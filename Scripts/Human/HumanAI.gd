extends RefCounted
class_name HumanAI

## 居民 AI。[br]
## 每 [constant DECISION_INTERVAL] 刻比较「喝水」「吃东西」「工作」三个权重，[br]
## 选出当前目标并负责寻路、移动、等待和进出建筑。[br]
## 本类只保存 AI 状态；居民的消耗、Buff 和外观仍归 [Human] 管理。

## 居民想干什么
enum Goal {
	NONE,  ## 没目标
	WATER, ## 去取水
	FOOD,  ## 去取食
	WORK,  ## 去上班
}

## 当前处在哪个阶段
enum Phase {
	IDLE,        ## 原地待着
	MOVING,      ## 沿路径走向目标
	WAITING,     ## 到了出入口，原地等待
	INSIDE_WORK, ## 在工作站内部（模型隐藏）
}

## 每多少刻做一次决策
const DECISION_INTERVAL: int = 5

## 工作的权重（暂时恒定）
const WORK_WEIGHT: float = 10.0

## 水 / 食物还剩这么多【游戏内秒】的时候，权重正好等于工作权重。
const URGENT_GAME_SECONDS: float = 36.0 * 60.0

## 成年人一天能走多少格。
const WALK_CELLS_PER_DAY: float = 750.0

## 儿童速度倍率（约为成年人的七成）。
const CHILD_SPEED_SCALE: float = 0.71

## 老年人速度倍率（约为成年人的八成半）。
const OLD_SPEED_SCALE: float = 0.86

## 这个 AI 控制的居民
var human: Human

## 当前目标
var goal: Goal = Goal.NONE

## 当前阶段
var phase: Phase = Phase.IDLE

## 当前目标建筑
var target: Building = null

## 当前路径（格子坐标序列，含起点）
var path: Array[Vector2i] = []

## 路径走到第几个点了
var path_index: int = 0

## 还要在这个出入口等几刻
var wait_left: int = 0

## 是否正在「被新建筑挤出来」，这段时间不做新决策
var _is_relocating: bool = false

## 内部计数：总共经过多少刻
var _tick_count: int = 0

## 决策相位：每个人的决策错开，避免全城同一刻一起涌向水站
var _decision_offset: int = 0

## 随机速度偏移（0.9~1.1），用于模拟不同居民的速度差异
var _random_speed_offset: float = 1.0


func _init(host: Human) -> void:
	human = host
	_decision_offset = randi() % DECISION_INTERVAL
	_random_speed_offset = 0.9 + randf() * 0.2


## Buff 结算后立刻检查工作闸门，不等下一次决策。
func enforce_work_gate() -> void:
	if goal != Goal.WORK or human.buff_system.can_work():
		return

	if phase == Phase.INSIDE_WORK and target is WorkStation:
		target.leave(human)
		human.show()
	_go_idle()


## 是否正在被新建筑挤到附近的空地
func is_relocating() -> bool:
	return _is_relocating


## 消耗结算后执行本刻的决策和行动。
func on_tick() -> void:
	_tick_count += 1

	# 每个人的决策时刻错开：错相位后依然是每 DECISION_INTERVAL 刻一次
	if (_tick_count + _decision_offset) % DECISION_INTERVAL == 0:
		_decide()

	match phase:
		Phase.MOVING:
			_move()
		Phase.WAITING:
			_update_wait()

	# 表现层：在走路就播走路动画，其它时候站着
	human.visual.set_moving(phase == Phase.MOVING)


# ---------------------------------------------------------------------------
# 决策
# ---------------------------------------------------------------------------

## 比较三个权重，决定接下来干什么
func _decide() -> void:
	# 正在被新建筑挤出来，先把路走完
	if _is_relocating:
		return

	# 正在去水 / 去食物的路上（移动或等待中）不改变目标
	if goal in [Goal.WATER, Goal.FOOD] and phase in [Phase.MOVING, Phase.WAITING]:
		return

	# 权重 = (提前量刻数 × 工作权重) ÷ 还能撑几刻，最后再乘 buff 给的倍率
	var urgent_ticks := URGENT_GAME_SECONDS / TickManager.GAME_SECONDS_PER_TICK
	var weight_scale := urgent_ticks * WORK_WEIGHT
	var water_weight := weight_scale / maxf(get_water_ticks_left(), 1.0) * human.buff_system.get_weight_multiplier(Goal.WATER)
	var food_weight := weight_scale / maxf(get_food_ticks_left(), 1.0) * human.buff_system.get_weight_multiplier(Goal.FOOD)

	# 平手时优先级：水 > 食物 > 工作；被 buff 禁掉的工作直接不参加比较
	var best_goal: Goal = Goal.NONE
	var best_weight := 0.0
	if human.buff_system.can_work():
		var work_weight := WORK_WEIGHT * human.buff_system.get_weight_multiplier(Goal.WORK)
		if work_weight > best_weight:
			best_weight = work_weight
			best_goal = Goal.WORK
	if water_weight > best_weight:
		best_weight = water_weight
		best_goal = Goal.WATER
	if food_weight > best_weight:
		best_goal = Goal.FOOD

	# 一个都不想干（比如被 buff 全禁了）：原地待着，别硬塞一个目标
	if best_goal == Goal.NONE:
		if goal != Goal.NONE:
			_go_idle()
		return

	if best_goal == goal:
		return

	_start_goal(best_goal)


## 开始执行新目标
func _start_goal(new_goal: Goal) -> void:
	# 被 buff 禁掉的目标不发车（决策那边已经跳过，这里兜底，防止别处直接调进来）
	if new_goal == Goal.WORK and not human.buff_system.can_work():
		_go_idle()
		return

	var type: GlobalEnum.BuildingType
	match new_goal:
		Goal.WATER:
			type = GlobalEnum.BuildingType.WATER
		Goal.FOOD:
			type = GlobalEnum.BuildingType.FOOD
		Goal.WORK:
			type = GlobalEnum.BuildingType.WORK
		_:
			_go_idle()
			return

	var station := _find_nearest_building(type)
	if station == null:
		# 没有这类建筑，只能干等着（后面应该换成原地等待）
		_go_idle()
		return

	# 从工作站里出来：模型重新出现，人还站在出入口格上
	if phase == Phase.INSIDE_WORK:
		var old_station := target
		if old_station is WorkStation:
			old_station.leave(human)
		human.show()

	goal = new_goal
	target = station

	var from_cell := WorldGridGlobal.world.world_to_cell(human.position)
	var entrance := station.get_nearest_entrance_cell(from_cell)
	var new_path := WorldGridGlobal.world.get_path(from_cell, entrance)

	if new_path.is_empty():
		push_warning("%s 找不到去 %s 的路（起点 %s，终点 %s）" % [human.name, station.name, from_cell, entrance])
		_go_idle()
		return

	path = new_path
	path_index = 0
	phase = Phase.MOVING


## 按切比雪夫距离找最近的一个建筑
func _find_nearest_building(type: GlobalEnum.BuildingType) -> Building:
	var from_cell := WorldGridGlobal.world.world_to_cell(human.position)
	var best: Building = null
	var best_distance := 0x7FFFFFFF
	for b in TickManager.get_buildings_of_type(type):
		var entrance := b.get_nearest_entrance_cell(from_cell)
		var d := maxi(absi(entrance.x - from_cell.x), absi(entrance.y - from_cell.y))
		if d < best_distance:
			best_distance = d
			best = b
	return best


## 按当前消耗速度，这些水还能撑多少刻
func get_water_ticks_left() -> float:
	return human.water / (human.get_daily_water() / float(TickManager.TICKS_PER_DAY))


## 按当前消耗速度，这些食物还能撑多少刻
func get_food_ticks_left() -> float:
	return human.food / (human.get_daily_food() / float(TickManager.TICKS_PER_DAY))


## 每刻能走几格
func get_speed_cells_per_tick() -> float:
	var speed_scale := 1.0
	match human.age_status:
		GlobalEnum.AgeStatus.CHILD:
			speed_scale = CHILD_SPEED_SCALE
		GlobalEnum.AgeStatus.OLD:
			speed_scale = OLD_SPEED_SCALE
	return (WALK_CELLS_PER_DAY * speed_scale / float(TickManager.TICKS_PER_DAY)) * _random_speed_offset * human.buff_system.get_speed_multiplier()


## 什么都不做
func _go_idle() -> void:
	goal = Goal.NONE
	phase = Phase.IDLE
	target = null
	path.clear()
	path_index = 0
	wait_left = 0


## 被新建筑压在下面时由放置控制器调用：走到最近空地，走完再重新决策
func evict_out() -> void:
	var world := WorldGridGlobal.world
	var from_cell := world.world_to_cell(human.position)
	var target_cell := world.find_nearest_walkable(from_cell)
	if target_cell == from_cell:
		return

	# 脚下已经变成建筑格（不可走），寻路前临时放行，才能算出从建筑里面走出来的路径
	var was_walkable := world.is_walkable(from_cell)
	if not was_walkable:
		world.set_walkable(from_cell, true)
	var new_path := world.get_path(from_cell, target_cell)
	if not was_walkable:
		world.set_walkable(from_cell, false)

	# 如果人正在别的工作站里，先退出来
	if phase == Phase.INSIDE_WORK and target is WorkStation:
		target.leave(human)
		human.show()

	if new_path.is_empty():
		# 被建筑整个包住、没有路可走：直接挪到最近的那块空地
		human.position = world.cell_to_world(target_cell)
		_is_relocating = false
		_go_idle()
		_decide()
		return

	goal = Goal.NONE
	target = null
	path = new_path
	path_index = 0
	phase = Phase.MOVING
	_is_relocating = true


# ---------------------------------------------------------------------------
# 移动 / 等待
# ---------------------------------------------------------------------------

## 沿路径往前挪一步。走的是连续坐标，不是整格跳。
func _move() -> void:
	var step := get_speed_cells_per_tick() * float(WorldGrid.CELL_SIZE)

	while step > 0.0 and path_index < path.size():
		var destination := WorldGridGlobal.world.cell_to_world(path[path_index])
		var to_destination := destination - human.position
		var distance := to_destination.length()

		# 朝向跟着移动方向走（三个视角：左右用 side 镜像，上下用另外两套）
		if to_destination.length_squared() > 0.000001:
			human.visual.set_facing(to_destination)

		if distance <= step:
			human.position = destination
			step -= distance
			path_index += 1
		else:
			human.position += to_destination / distance * step
			step = 0.0

	if path_index >= path.size():
		_arrive()


## 走到出入口了
func _arrive() -> void:
	path.clear()
	path_index = 0

	# 被新建筑挤出来，走到空地就算结束，原地重新决策
	if _is_relocating:
		_is_relocating = false
		phase = Phase.IDLE
		goal = Goal.NONE
		_decide()
		return

	phase = Phase.WAITING
	wait_left = 0 if target == null else target.get_wait_ticks()

	if wait_left <= 0:
		_finish_wait()


## 每刻减少等待计数
func _update_wait() -> void:
	wait_left -= 1
	if wait_left <= 0:
		_finish_wait()


## 等待结束：补水 / 补食物 / 进工作站
func _finish_wait() -> void:
	if target == null:
		_go_idle()
		return

	match target.building_type:
		GlobalEnum.BuildingType.WATER:
			human.water = Human.MAX_WATER
		GlobalEnum.BuildingType.FOOD:
			human.food = Human.MAX_FOOD
		GlobalEnum.BuildingType.WORK:
			# 进入建筑内部：模型隐藏（站内的人不画出来，统计里单独算）
			phase = Phase.INSIDE_WORK
			if target is WorkStation:
				target.enter(human)
			human.hide()
			return

	# 补给完了，马上重新决策一次，不干等下一个决策间隔
	target = null
	_go_idle()
	_decide()
