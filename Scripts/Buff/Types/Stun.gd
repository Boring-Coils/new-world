## 眩晕 Buff：禁止居民工作，同时按层数和减速比例降低移动速度。[br]
## 默认持续 [constant DEFAULT_DURATION] 刻，每层默认减速 [constant DEFAULT_SLOW]；[br]
## 工作闸门由 [method can_work] 提供，速度效果由父类 [SlowBuff] 汇总。
extends SlowBuff
class_name Stun

## 没传 duration 时的持续刻数
const DEFAULT_DURATION: int = 30

## 没传 slow 时每层的减速比例
const DEFAULT_SLOW: float = 0.5


## 读取首次添加时的持续刻数和每层减速比例。[br]
## [param params] 支持 [code]duration[/code] 与 [code]slow[/code]；缺省时使用本类常量。
func apply(params: Dictionary) -> void:
	duration = int(params.get("duration", DEFAULT_DURATION))
	read_slow(params, DEFAULT_SLOW)


## 眩晕期间始终禁止工作。
func can_work() -> bool:
	return false
