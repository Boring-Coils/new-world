extends Node2D
class_name Human

## 居民。[br]
##
## 每刻扣水和食物，每 [constant DECISION_INTERVAL] 刻重新决策一次：
## 比较「喝水」「吃东西」「工作」三个权重，最高的那个就是当前目标。[br]
##
## - 水 / 食物权重 = 权重系数 ÷ 还能撑多少刻（反比例，越快见底越高）
## - 工作权重固定 [constant WORK_WEIGHT]
## - 已经在去水 / 去食物的路上（移动或等待中）时，不改变目标
##
## 权重用「还剩多少刻」而不是「还剩多少毫升」来算，这样儿童（日耗小）和成人
## 会在各自「还剩同样久」的时候动身，不会因为总量一样就一起跑水站。
##
## 水或食物掉到 0 以下会进入虚弱状态，暂时只会停在原地。

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

## 水 / 食物储量上限（每个人固定）
const MAX_WATER: float = 700.0
const MAX_FOOD: float = 700.0

## 每多少刻做一次决策
const DECISION_INTERVAL: int = 5

## 工作的权重（暂时恒定）
const WORK_WEIGHT: float = 10.0

## 水 / 食物还剩这么多【游戏内秒】的时候，权重正好等于工作权重 —— 也就是该动身了。[br]
##
## 36 分钟 = 0.6 个游戏小时。这个提前量跟「一天分多少刻」无关：
## 改 [constant TickManager.TICKS_PER_DAY] 之后会自动换算成对应的刻数，不用手动改。
const URGENT_GAME_SECONDS: float = 36.0 * 60.0

## 年龄
@export var age: int = 20

## 年龄段（决定日耗和移动速度）
@export var age_status: GlobalEnum.AgeStatus = GlobalEnum.AgeStatus.ADULT

## 当前储水量（ml）
@export var water: float = MAX_WATER

## 当前储食物量（g）
@export var food: float = MAX_FOOD

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

## 是否虚弱
var is_weak: bool = false

## 内部计数：总共经过多少刻
var _tick_count: int = 0

## 决策相位：每个人的决策错开，避免全城同一刻一起涌向水站
var _decision_offset: int = 0


func _ready() -> void:
	_decision_offset = randi() % DECISION_INTERVAL
	TickManager.register_human(self)
	queue_redraw()


func _exit_tree() -> void:
	TickManager.unregister_human(self)


## 每刻由 [TickManager] 调用。顺序：先扣消耗，再决策，最后按阶段行动。
func on_tick() -> void:
	_tick_count += 1

	_consume()

	if is_weak:
		return

	# 每个人的决策时刻错开：错相位后依然是每 5 刻一次
	if (_tick_count + _decision_offset) % DECISION_INTERVAL == 0:
		_decide()

	match phase:
		Phase.MOVING:
			_move()
		Phase.WAITING:
			_update_wait()


# ---------------------------------------------------------------------------
# 消耗
# ---------------------------------------------------------------------------

## 每刻扣水扣食物
func _consume() -> void:
	water -= get_daily_water() / float(TickManager.TICKS_PER_DAY)
	food -= get_daily_food() / float(TickManager.TICKS_PER_DAY)

	if not is_weak and (water < 0.0 or food < 0.0):
		is_weak = true
		goal = Goal.NONE
		phase = Phase.IDLE
		path.clear()
		target = null
		show()
		push_warning("%s 进入虚弱状态（水 %.1f / 食物 %.1f）" % [name, water, food])
		queue_redraw()


## 每日耗水量（ml）
func get_daily_water() -> float:
	match age_status:
		GlobalEnum.AgeStatus.CHILD:
			return 500.0
		GlobalEnum.AgeStatus.OLD:
			return 1500.0
		_:
			return 1700.0


## 每日耗食物量（g）
func get_daily_food() -> float:
	match age_status:
		GlobalEnum.AgeStatus.CHILD:
			return 800.0
		GlobalEnum.AgeStatus.OLD:
			return 1500.0
		_:
			return 1900.0


## 每刻能走几格。[br]
## 换算：米/秒 × 每刻的游戏秒数 = 米/刻 = 格/刻（1 格 = 1 米）。
func get_speed_cells_per_tick() -> float:
	var meters_per_second := 1.4  # 成年人正常步行
	match age_status:
		GlobalEnum.AgeStatus.CHILD:
			meters_per_second = 1.0
		GlobalEnum.AgeStatus.OLD:
			meters_per_second = 1.2
	return meters_per_second * TickManager.GAME_SECONDS_PER_TICK


## 按当前的消耗速度，这些水还能撑多少刻
func get_water_ticks_left() -> float:
	return water / (get_daily_water() / float(TickManager.TICKS_PER_DAY))


## 按当前的消耗速度，这些食物还能撑多少刻
func get_food_ticks_left() -> float:
	return food / (get_daily_food() / float(TickManager.TICKS_PER_DAY))


# ---------------------------------------------------------------------------
# 决策
# ---------------------------------------------------------------------------

## 比较三个权重，决定接下来干什么
func _decide() -> void:
	if is_weak:
		return

	# 正在去水 / 去食物的路上（移动或等待中）不改变目标
	if goal in [Goal.WATER, Goal.FOOD] and phase in [Phase.MOVING, Phase.WAITING]:
		return

	# 权重 = (提前量刻数 × 工作权重) ÷ 还能撑几刻
	var urgent_ticks := URGENT_GAME_SECONDS / TickManager.GAME_SECONDS_PER_TICK
	var weight_scale := urgent_ticks * WORK_WEIGHT
	var water_weight := weight_scale / maxf(get_water_ticks_left(), 1.0)
	var food_weight := weight_scale / maxf(get_food_ticks_left(), 1.0)

	# 平手时优先级：水 > 食物 > 工作
	var best_goal: Goal = Goal.WORK
	var best_weight := WORK_WEIGHT
	if water_weight > best_weight:
		best_weight = water_weight
		best_goal = Goal.WATER
	if food_weight > best_weight:
		best_goal = Goal.FOOD

	if best_goal == goal:
		return

	_start_goal(best_goal)


## 开始执行新目标
func _start_goal(new_goal: Goal) -> void:
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
		# 没有这类建筑，只能干等着（后面应该换成「去最近的同类型建筑或原地等待」）
		_go_idle()
		return

	# 从工作站里出来：模型重新出现，人站在出入口格上
	if phase == Phase.INSIDE_WORK:
		show()

	goal = new_goal
	target = station

	var from_cell := WorldGridGlobal.world.world_to_cell(position)
	var entrance := station.get_nearest_entrance_cell(from_cell)
	var new_path := WorldGridGlobal.world.get_path(from_cell, entrance)

	if new_path.is_empty():
		push_warning("%s 找不到去 %s 的路（起点 %s，终点 %s）" % [name, station.name, from_cell, entrance])
		_go_idle()
		return

	path = new_path
	path_index = 0
	phase = Phase.MOVING
	queue_redraw()


## 按切比雪夫距离找最近的一个建筑
func _find_nearest_building(type: GlobalEnum.BuildingType) -> Building:
	var from_cell := WorldGridGlobal.world.world_to_cell(position)
	var best: Building = null
	var best_distance := 0x7FFFFFFF
	for b in TickManager.get_buildings_of_type(type):
		var entrance := b.get_nearest_entrance_cell(from_cell)
		var d := maxi(absi(entrance.x - from_cell.x), absi(entrance.y - from_cell.y))
		if d < best_distance:
			best_distance = d
			best = b
	return best


## 什么都不做
func _go_idle() -> void:
	goal = Goal.NONE
	phase = Phase.IDLE
	target = null
	path.clear()
	path_index = 0
	wait_left = 0
	queue_redraw()


# ---------------------------------------------------------------------------
# 移动 / 等待
# ---------------------------------------------------------------------------

## 沿路径往前挪一步。走的是连续坐标，不是整格跳。
func _move() -> void:
	var step := get_speed_cells_per_tick() * float(WorldGrid.CELL_SIZE)

	while step > 0.0 and path_index < path.size():
		var destination := WorldGridGlobal.world.cell_to_world(path[path_index])
		var to_destination := destination - position
		var distance := to_destination.length()

		if distance <= step:
			position = destination
			step -= distance
			path_index += 1
		else:
			position += to_destination / distance * step
			step = 0.0

	if path_index >= path.size():
		_arrive()


## 走到出入口了
func _arrive() -> void:
	path.clear()
	path_index = 0
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
			water = MAX_WATER
		GlobalEnum.BuildingType.FOOD:
			food = MAX_FOOD
		GlobalEnum.BuildingType.WORK:
			# 进入建筑内部：模型消失，原地（出入口格）藏起来
			phase = Phase.INSIDE_WORK
			hide()
			queue_redraw()
			return

	# 补给完了，马上重新决策一次，不干等下一个 5 刻
	target = null
	_go_idle()
	if not is_weak:
		_decide()


# ---------------------------------------------------------------------------
# 绘制（测试用：一个色点）
# ---------------------------------------------------------------------------

func _draw() -> void:
	var color := Color(0.35, 0.85, 0.45)  # 空闲：绿
	if is_weak:
		color = Color(0.4, 0.4, 0.4)  # 虚弱：灰
	elif phase == Phase.INSIDE_WORK:
		color = Color(0.45, 0.45, 0.5)
	else:
		match goal:
			Goal.WATER:
				color = Color(0.3, 0.7, 1.0)
			Goal.FOOD:
				color = Color(1.0, 0.7, 0.2)
			Goal.WORK:
				color = Color(0.85, 0.35, 0.85)

	draw_circle(Vector2.ZERO, 3.0, color)
