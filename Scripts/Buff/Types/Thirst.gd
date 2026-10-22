extends BuffBase
class_name Thirst

## 口渴：每刻额外扣水。用来验证 [method BuffBase.on_tick] 这条链路——[br]
## 它不改任何倍率，纯粹靠在每刻多扣一点水来起作用。[br]
## 参数：[br]
## - [code]duration[/code]：持续多少刻，缺省 [constant DEFAULT_DURATION][br]
## - [code]drain[/code]：每层每刻额外扣多少毫升，缺省 [constant DEFAULT_DRAIN]

## 没传 duration 时的持续刻数
const DEFAULT_DURATION: int = 40

## 没传 drain 时每层每刻扣多少毫升
const DEFAULT_DRAIN: float = 5.0

## 每层每刻额外扣多少毫升
var drain: float = DEFAULT_DRAIN

## 这个 buff 累计扣掉了多少水（测试用，方便核对 on_tick 到底跑了几次）
var drained_total: float = 0.0


func apply(params: Dictionary) -> void:
	duration = int(params.get("duration", DEFAULT_DURATION))
	drain = float(params.get("drain", DEFAULT_DRAIN))


func on_tick() -> void:
	if human == null:
		return
	var amount := drain * float(stacks)
	human.water -= amount
	drained_total += amount
