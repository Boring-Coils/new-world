## 减速型 Buff 的共用基类。[br]
## 按“每层减速比例 × 层数”计算线性衰减，并用 [constant MIN_SPEED_MULTIPLIER] 保底；[br]
## 子类只需读取 [member slow] 参数，即可通过 [method get_speed_multiplier] 获得统一效果。
extends BuffBase
class_name SlowBuff

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


## 返回按当前层数计算并经过保底限制的移动速度倍率。
func get_speed_multiplier() -> float:
	return maxf(1.0 - slow * float(stacks), MIN_SPEED_MULTIPLIER)
