extends SlowBuff
class_name Stun

## 眩晕：不能工作，而且走得慢。[br]
## 用来验证「行为闸门」这条链路：buff 不改居民的字段，只让 [method BuffBase.can_work] 返回 false，[br]
## [HumanAI] 决策时就用不到工作这个目标。[br]
## 参数：[br]
## - [code]duration[/code]：持续多少刻，缺省 [constant DEFAULT_DURATION][br]
## - [code]slow[/code]：每层减速比例，缺省 [constant DEFAULT_SLOW]

## 没传 duration 时的持续刻数
const DEFAULT_DURATION: int = 30

## 没传 slow 时每层的减速比例
const DEFAULT_SLOW: float = 0.5


func apply(params: Dictionary) -> void:
	duration = int(params.get("duration", DEFAULT_DURATION))
	read_slow(params, DEFAULT_SLOW)


func can_work() -> bool:
	return false
