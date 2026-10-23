extends SlowBuff
class_name Fatigue

## 疲劳：走得慢。[br]
## 参数：[br]
## - [code]duration[/code]：持续多少刻，缺省 [constant DEFAULT_DURATION][br]
## - [code]slow[/code]：每层减速比例，0.3 就是每层慢 30%，缺省 [constant DEFAULT_SLOW][br]
## 「按层衰减 + 保底」的算法在 [SlowBuff] 里，本类只负责读参数。

## 没传 duration 时的持续刻数
const DEFAULT_DURATION: int = 60

## 没传 slow 时每层的减速比例
const DEFAULT_SLOW: float = 0.3


func apply(params: Dictionary) -> void:
	duration = int(params.get("duration", DEFAULT_DURATION))
	read_slow(params, DEFAULT_SLOW)
