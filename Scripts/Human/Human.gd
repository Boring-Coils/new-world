extends Node2D
class_name Human

## 居民。[br]
## 每刻扣水和食物，每 [constant DECISION_INTERVAL] 刻重新决策一次：[br]
## 比较「喝水」「吃东西」「工作」三个权重，最高的那个就是当前目标。[br]
## - 水 / 食物权重 = 权重系数 ÷ 还能撑多少刻（反比例，越快见底越高）[br]
## - 工作权重固定 [constant WORK_WEIGHT][br]
## - 已经在去水 / 去食物的路上（移动或等待中）时，不改变目标[br]
## 权重用「还剩多少刻」而不是「还剩多少毫升」来算，这样儿童（日耗小）和成人[br]
## 会在各自「还剩同样久」的时候动身，不会因为总量一样就一起跑水站。[br]
## 水或食物掉到 0 以下本身不会立刻发生什么——虚弱、受伤这类状态统一由 [BuffSystem] 管理，[br]
## 本类只管「怎么走、怎么消耗、怎么决策」，具体状态效果一律问 [member buff_system]。

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
## 36 分钟 = 0.6 个游戏小时。这个提前量跟「一天分多少刻」无关：[br]
## 改 [constant TickManager.TICKS_PER_DAY] 之后会自动换算成对应的刻数，不用手动改。
const URGENT_GAME_SECONDS: float = 36.0 * 60.0

## 成年人一天能走多少格。[br]
## 这个是观感基准，等价于「现实每秒 2.5 格」：一天现实 300 秒 × 2.5 = 750 格。[br]
## 每刻格数由它除以 [constant TickManager.TICKS_PER_DAY] 得出，所以改每天刻数会自动跟随。
const WALK_CELLS_PER_DAY: float = 750.0

## 儿童速度倍率（约为成年人的七成）。
const CHILD_SPEED_SCALE: float = 0.71

## 老年人速度倍率（约为成年人的八成半）。
const OLD_SPEED_SCALE: float = 0.86

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

## 挂在身上的状态效果，子节点，见 [BuffSystem]
@onready var buff_system: BuffSystem = $BuffSystem

## 是否正在「被新建筑挤出来」，这段时间不做新决策
var _is_relocating: bool = false

## 内部计数：总共经过多少刻
var _tick_count: int = 0

## 决策相位：每个人的决策错开，避免全城同一刻一起涌向水站
var _decision_offset: int = 0

## 随机速度偏移（0.9~1.1），用于模拟不同居民的速度差异
var _random_speed_offset: float = 1.0


## 创建一个居民节点。[br]
## 居民身上的子节点（比如 [BuffSystem]）都写在 Human.tscn 里，所以别直接 [code]Human.new()[/code]——[br]
## 那样建出来的节点没有子节点，[member buff_system] 会是 null（踩过一次）。
static func create() -> Human:
	return load("res://Scenes/Human/Human.tscn").instantiate() as Human


func _ready() -> void:
	_decision_offset = randi() % DECISION_INTERVAL
	_random_speed_offset = 0.9 + randf() * 0.2
	TickManager.register_human(self)
	queue_redraw()


func _exit_tree() -> void:
	TickManager.unregister_human(self)


## 每刻由 [TickManager] 调用。顺序：先扣消耗，再决策，最后按阶段行动。
func on_tick() -> void:
	_tick_count += 1

	# buff 先结算：它在这一刻造成的影响（额外掉水、状态推进）要在下面扣消耗和做决策之前生效
	buff_system.on_tick()

	# 正在上班 / 去上班的路上被 buff 禁了工作（比如刚眩晕）：立刻停下。
	# 不能等到下一次决策——那要最多 DECISION_INTERVAL 刻，人会照常上完这一趟班
	if goal == Goal.WORK and not buff_system.can_work():
		if phase == Phase.INSIDE_WORK and target is WorkStation:
			target.leave(self)
			show()
		_go_idle()

	_consume()

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

## 每刻扣水扣食物，倍率由 buff 汇总（比如口渴会让水掉得更快）
func _consume() -> void:
	var consume_scale := buff_system.get_consume_multiplier()
	water -= get_daily_water() / float(TickManager.TICKS_PER_DAY) * consume_scale
	food -= get_daily_food() / float(TickManager.TICKS_PER_DAY) * consume_scale


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
## 由 [constant WALK_CELLS_PER_DAY] 除以 [constant TickManager.TICKS_PER_DAY] 得出，改每天刻数会自动跟随。
func get_speed_cells_per_tick() -> float:
	var scale := 1.0
	match age_status:
		GlobalEnum.AgeStatus.CHILD:
			scale = CHILD_SPEED_SCALE
		GlobalEnum.AgeStatus.OLD:
			scale = OLD_SPEED_SCALE
	return (WALK_CELLS_PER_DAY * scale / float(TickManager.TICKS_PER_DAY)) * _random_speed_offset * buff_system.get_speed_multiplier()


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
	# 正在被新建筑挤出来，先把路走完
	if _is_relocating:
		return

	# 正在去水 / 去食物的路上（移动或等待中）不改变目标
	if goal in [Goal.WATER, Goal.FOOD] and phase in [Phase.MOVING, Phase.WAITING]:
		return

	# 权重 = (提前量刻数 × 工作权重) ÷ 还能撑几刻，最后再乘 buff 给的倍率
	var urgent_ticks := URGENT_GAME_SECONDS / TickManager.GAME_SECONDS_PER_TICK
	var weight_scale := urgent_ticks * WORK_WEIGHT
	var water_weight := weight_scale / maxf(get_water_ticks_left(), 1.0) * buff_system.get_weight_multiplier(Goal.WATER)
	var food_weight := weight_scale / maxf(get_food_ticks_left(), 1.0) * buff_system.get_weight_multiplier(Goal.FOOD)

	# 平手时优先级：水 > 食物 > 工作；被 buff 禁掉的工作直接不参加比较
	var best_goal: Goal = Goal.NONE
	var best_weight := 0.0
	if buff_system.can_work():
		var work_weight := WORK_WEIGHT * buff_system.get_weight_multiplier(Goal.WORK)
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
	if new_goal == Goal.WORK and not buff_system.can_work():
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
		# 没有这类建筑，只能干等着（后面应该换成「去最近的同类型建筑或原地等待」）
		_go_idle()
		return

	# 从工作站里出来：模型重新出现，人还站在出入口格上
	if phase == Phase.INSIDE_WORK:
		var old_station := target
		if old_station is WorkStation:
			old_station.leave(self)
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


## 被新建筑压在下面时由建筑那边调用：自己走到最近的空地，走完再重新决策
func evict_out() -> void:
	var world := WorldGridGlobal.world
	var from_cell := world.world_to_cell(position)
	var target_cell := world.find_nearest_walkable(from_cell)
	if target_cell == from_cell:
		return

	# 脚下已经变成建筑格（不可走），寻路前临时放行，才能算出「从建筑里面走出来」的路径
	var was_walkable := world.is_walkable(from_cell)
	if not was_walkable:
		world.set_walkable(from_cell, true)
	var new_path := world.get_path(from_cell, target_cell)
	if not was_walkable:
		world.set_walkable(from_cell, false)

	# 如果人正在别的工作站里，先退出来
	if phase == Phase.INSIDE_WORK and target is WorkStation:
		target.leave(self)
		show()

	if new_path.is_empty():
		# 被建筑整个包住、没有路可走：直接挪到最近的那块空地
		position = world.cell_to_world(target_cell)
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

	# 被新建筑挤出来，走到空地就算结束，原地重新决策
	if _is_relocating:
		_is_relocating = false
		phase = Phase.IDLE
		goal = Goal.NONE
		queue_redraw()
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
			water = MAX_WATER
		GlobalEnum.BuildingType.FOOD:
			food = MAX_FOOD
		GlobalEnum.BuildingType.WORK:
			# 进入建筑内部：模型隐藏（站内的人不画出来，统计里单独算）
			phase = Phase.INSIDE_WORK
			if target is WorkStation:
				target.enter(self)
			hide()
			queue_redraw()
			return

	# 补给完了，马上重新决策一次，不干等下一个 5 刻
	target = null
	_go_idle()
	_decide()


# ---------------------------------------------------------------------------
# 绘制（测试用：一个色点）
# ---------------------------------------------------------------------------

func _draw() -> void:
	# 白模小人：头 + 身体 + 四肢。衣服颜色表示当前在干什么。
	var outfit := _get_outfit_color()
	var skin := Color(0.96, 0.90, 0.83)
	var outline := Color(0.13, 0.13, 0.17)

	# 脚下的影子
	draw_circle(Vector2(0.0, 4.2), 2.2, Color(0.0, 0.0, 0.0, 0.18))
	# 腿
	draw_line(Vector2(-1.0, 1.6), Vector2(-1.3, 4.0), outline, 0.9)
	draw_line(Vector2(1.0, 1.6), Vector2(1.3, 4.0), outline, 0.9)
	# 身体
	draw_rect(Rect2(-1.6, -0.6, 3.2, 2.4), outfit, true)
	draw_rect(Rect2(-1.6, -0.6, 3.2, 2.4), outline, false, 0.5)
	# 手臂
	draw_line(Vector2(-1.6, 0.0), Vector2(-2.4, 1.2), outline, 0.8)
	draw_line(Vector2(1.6, 0.0), Vector2(2.4, 1.2), outline, 0.8)
	# 头
	draw_circle(Vector2(0.0, -2.1), 1.7, skin)
	draw_arc(Vector2(0.0, -2.1), 1.7, 0.0, TAU, 14, outline, 0.5)
	# 头发
	draw_arc(Vector2(0.0, -2.2), 1.7, PI * 1.02, PI * 1.98, 10, Color(0.26, 0.21, 0.18), 0.9)


## 衣服颜色 = 当前状态
func _get_outfit_color() -> Color:
	match goal:
		Goal.WATER:
			return Color(0.30, 0.65, 0.95)  # 去取水：蓝
		Goal.FOOD:
			return Color(0.95, 0.65, 0.20)  # 去取食：橙
		Goal.WORK:
			return Color(0.55, 0.45, 0.85)  # 上班：紫
		_:
			return Color(0.35, 0.75, 0.45)  # 空闲：绿
