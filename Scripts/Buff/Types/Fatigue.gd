extends BuffBase
class_name Fatigue

## 疲劳：走得慢。[br]
## 参数：[br]
## - [code]duration[/code]：持续多少刻，缺省 [constant DEFAULT_DURATION][br]
## - [code]intensity[/code]：每层减速比例，0.3 就是每层慢 30%，缺省 [constant DEFAULT_INTENSITY][br]
## 可以叠加：两层 0.5 的疲劳 = 速度 ×0.0，会被 [constant MIN_SPEED_MULTIPLIER] 兜住，不至于原地卡死。

## 没传 duration 时的持续刻数
const DEFAULT_DURATION: int = 60

## 没传 intensity 时每层的减速比例
const DEFAULT_INTENSITY: float = 0.3

## 速度倍率的保底值，避免叠太多层后完全走不动
const MIN_SPEED_MULTIPLIER: float = 0.1

## 每层减速比例
var intensity: float = DEFAULT_INTENSITY


func apply(params: Dictionary) -> void:
	duration = int(params.get("duration", DEFAULT_DURATION))
	intensity = clampf(float(params.get("intensity", DEFAULT_INTENSITY)), 0.0, 1.0)


func reapply(params: Dictionary) -> void:
	super.reapply(params)
	# 重复添加时强度取更高的那个：累加太容易叠成 0，反而不如「取最强」直观
	if params.has("intensity"):
		intensity = maxf(intensity, clampf(float(params["intensity"]), 0.0, 1.0))


func get_speed_multiplier() -> float:
	return maxf(1.0 - intensity * float(stacks), MIN_SPEED_MULTIPLIER)
