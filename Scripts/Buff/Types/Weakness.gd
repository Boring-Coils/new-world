## 虚弱 Buff：虚弱期间禁止工作，并在持续时间内等待饥饿和口渴恢复。[br]
## 当水分与食物都高于 200 时累计恢复时间；恢复计时结束正常移除，[br]
## 若持续时间先结束则通过 [method on_remove] 让居民死亡。
extends BuffBase
class_name Weakness

## 满足恢复条件后仍需累计的恢复刻数，初始为五个游戏日。
var heal_time: int = TickManager.TICKS_PER_DAY * 5

## 初始化虚弱总持续时间，并保留默认恢复倒计时。[br]
## 当前不支持通过 [param _params] 覆盖时长。
func apply(_params: Dictionary) -> void:
	duration = TickManager.TICKS_PER_DAY * 10


## 重复添加时不叠加层数、不刷新持续时间和恢复计时。
func reapply(params: Dictionary) -> void:
	pass

## 在水和食物均充足时推进恢复计时；恢复完成时将持续时间归零以触发移除。
func on_tick() -> void:
	if human.water > 200 && human.food > 200:
		heal_time -= 1
	if heal_time <= 0:
		duration = 0

## 到期移除时若恢复计时尚未完成，则判定居民死亡。
func on_remove() -> void:
	if heal_time > 0:
		human.die()

## 虚弱期间始终禁止工作。
func can_work() -> bool:
	return false

## 虚弱状态下的水和食物消耗倍率，降低为正常速度的一半。
func get_consume_multiplier() -> float:
	return 0.5
