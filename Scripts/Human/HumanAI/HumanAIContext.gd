## 当前决策刻所需的居民状态快照。[br]
## 由 [method refresh] 从居民与 Buff 系统重新计算，不持有建筑或路径引用。[br]
## 决策器只读取该对象，因此评分过程不会改变世界状态。
extends RefCounted
class_name HumanAIContext

## 按当前水消耗速度估算的剩余生存刻数；无消耗时为无穷大。
var water_ticks_left: float = 0.0

## 按当前食物消耗速度估算的剩余生存刻数；无消耗时为无穷大。
var food_ticks_left: float = 0.0

## 所有 Buff 工作闸门汇总后的工作许可。
var can_work: bool = false

## 取水目标的决策权重倍率。
var water_weight_multiplier: float = 1.0

## 取食目标的决策权重倍率。
var food_weight_multiplier: float = 1.0

## 工作目标的决策权重倍率。
var work_weight_multiplier: float = 1.0


## 根据 [param human] 当前水分、食物和 Buff 重算全部决策快照。
func refresh(human: Human) -> void:
	# 基础日耗先乘消耗倍率，再叠加 Buff 的直接逐刻扣减。
	var consume_multiplier := maxf(
		human.buff_system.get_consume_multiplier(),
		0.0,
	)
	var water_per_tick := (
		human.get_daily_water()
		/ float(TickManager.TICKS_PER_DAY)
		* consume_multiplier
		+ human.buff_system.get_water_drain_per_tick()
	)
	var food_per_tick := (
		human.get_daily_food()
		/ float(TickManager.TICKS_PER_DAY)
		* consume_multiplier
		+ human.buff_system.get_food_drain_per_tick()
	)

	water_ticks_left = _get_ticks_left(human.water, water_per_tick)
	food_ticks_left = _get_ticks_left(human.food, food_per_tick)

	# 工作闸门和目标权重都来自 BuffSystem，决策器不直接读取具体 Buff 类型。
	can_work = human.buff_system.can_work()
	water_weight_multiplier = human.buff_system.get_weight_multiplier(
		HumanAI.Goal.WATER
	)
	food_weight_multiplier = human.buff_system.get_weight_multiplier(
		HumanAI.Goal.FOOD
	)
	work_weight_multiplier = human.buff_system.get_weight_multiplier(
		HumanAI.Goal.WORK
	)


## 返回当前资源在 [param per_tick] 消耗速度下还能维持的刻数。[br]
## 消耗速度非正时返回无穷大，资源为负时按 0 处理。
func _get_ticks_left(amount: float, per_tick: float) -> float:
	if per_tick <= 0.0:
		return INF
	return maxf(amount, 0.0) / per_tick
