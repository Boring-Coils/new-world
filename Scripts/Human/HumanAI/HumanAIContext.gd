extends RefCounted
class_name HumanAIContext

## 当前决策刻所需的短期快照，不持有建筑或路径引用。

var water_ticks_left: float = 0.0
var food_ticks_left: float = 0.0
var can_work: bool = false

var water_weight_multiplier: float = 1.0
var food_weight_multiplier: float = 1.0
var work_weight_multiplier: float = 1.0


func refresh(human: Human) -> void:
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


func _get_ticks_left(amount: float, per_tick: float) -> float:
	if per_tick <= 0.0:
		return INF
	return maxf(amount, 0.0) / per_tick
