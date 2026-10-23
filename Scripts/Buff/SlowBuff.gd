extends BuffBase
class_name SlowBuff

## 减速型 buff 的共用基类：「每层线性衰减 + 保底倍率」这一条规则只写在这里。[br]
## 子类只需要在 [method apply] 里把参数读进 [member slow]，效果就自动有了，[br]
## 想再改「走多慢」的算法（比如改成指数衰减），改本类一处即可。

## 速度倍率的保底值：叠太多层也不至于原地卡死
const MIN_SPEED_MULTIPLIER: float = 0.1

## 每层减速比例，0.3 就是每层慢 30%
var slow: float = 0.0


## 从参数字典里读 [code]slow[/code]；没传就沿用上次的值，第一次则用 [param fallback]
func read_slow(params: Dictionary, fallback: float) -> void:
	if params.has("slow"):
		slow = clampf(float(params["slow"]), 0.0, 1.0)
	elif slow <= 0.0:
		slow = clampf(fallback, 0.0, 1.0)


## 重复添加时强度取更高的那个：累加太容易叠成 0，不如「取最强」直观
func reapply(params: Dictionary) -> void:
	super.reapply(params)
	if params.has("slow"):
		slow = maxf(slow, clampf(float(params["slow"]), 0.0, 1.0))


func get_speed_multiplier() -> float:
	return maxf(1.0 - slow * float(stacks), MIN_SPEED_MULTIPLIER)
