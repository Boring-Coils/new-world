extends BuffBase
class_name Weakness

var heal_time: int = TickManager.TICKS_PER_DAY * 5

func apply(_params: Dictionary) -> void:
	duration = TickManager.TICKS_PER_DAY * 10


## 多次应用没用
func reapply(params: Dictionary) -> void:
	pass

func on_tick() -> void:
	if human.water > 200 && human.food > 200:
		heal_time -= 1
	if heal_time <= 0:
		duration = 0

func on_remove() -> void:
	if heal_time > 0:
		human.die()

func can_work() -> bool:
	return false

## 水 / 食物的消耗倍率。默认 1.0，[BuffSystem] 把所有 buff 的结果相乘
func get_consume_multiplier() -> float:
	return 0.5
