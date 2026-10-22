extends BuffBase
class_name Stun

## 眩晕：不能工作，而且走得慢。[br]
## 用来验证「行为闸门」这条链路：buff 不改居民的字段，只让 [method BuffBase.can_work] 返回 false，[br]
## [Human] 决策时就用不到工作这个目标。[br]
## 参数：[br]
## - [code]duration[/code]：持续多少刻，缺省 [constant DEFAULT_DURATION][br]
## - [code]slow[/code]：每层减速比例，缺省 [constant DEFAULT_SLOW]

## 没传 duration 时的持续刻数
const DEFAULT_DURATION: int = 30

## 没传 slow 时每层的减速比例
const DEFAULT_SLOW: float = 0.5

## 速度倍率的保底值
const MIN_SPEED_MULTIPLIER: float = 0.1

## 每层减速比例
var slow: float = DEFAULT_SLOW


func apply(params: Dictionary) -> void:
	duration = int(params.get("duration", DEFAULT_DURATION))
	slow = clampf(float(params.get("slow", DEFAULT_SLOW)), 0.0, 1.0)


func reapply(params: Dictionary) -> void:
	super.reapply(params)
	if params.has("slow"):
		slow = maxf(slow, clampf(float(params["slow"]), 0.0, 1.0))


func can_work() -> bool:
	return false


func get_speed_multiplier() -> float:
	return maxf(1.0 - slow * float(stacks), MIN_SPEED_MULTIPLIER)
