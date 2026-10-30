## 疲劳 Buff：按层数线性降低移动速度，层数越高减速越明显。[br]
## 默认持续 [constant DEFAULT_DURATION] 刻，每层默认减速 [constant DEFAULT_SLOW]，[br]
## 具体倍率计算和保底规则由父类 [SlowBuff] 负责。
extends SlowBuff
class_name Fatigue

## 没传 duration 时的持续刻数
const DEFAULT_DURATION: int = 60

## 没传 slow 时每层的减速比例
const DEFAULT_SLOW: float = 0.3


## 读取首次添加时的持续刻数和每层减速比例。[br]
## [param params] 支持 [code]duration[/code] 与 [code]slow[/code]；缺省时使用本类常量。
func apply(params: Dictionary) -> void:
	duration = int(params.get("duration", DEFAULT_DURATION))
	read_slow(params, DEFAULT_SLOW)
