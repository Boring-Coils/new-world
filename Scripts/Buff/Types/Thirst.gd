## 口渴 Buff：每个模拟刻按层数额外扣除居民水分。[br]
## 默认持续 [constant DEFAULT_DURATION] 刻、每层每刻扣除 [constant DEFAULT_DRAIN]；[br]
## 它不修改消耗倍率，仅通过 [method on_tick] 直接影响水分状态。
extends BuffBase
class_name Thirst

## 没传 duration 时的持续刻数
const DEFAULT_DURATION: int = 40

## 没传 drain 时每层每刻扣多少毫升
const DEFAULT_DRAIN: float = 5.0

## 每层每刻额外扣多少毫升
var drain: float = DEFAULT_DRAIN

## 该 Buff 累计额外扣除的水量，供自检和调试核对每刻效果。
var drained_total: float = 0.0


## 读取首次添加时的持续刻数和每层扣水量。[br]
## [param params] 支持 [code]duration[/code] 与 [code]drain[/code]；缺省时使用本类常量。
func apply(params: Dictionary) -> void:
	duration = int(params.get("duration", DEFAULT_DURATION))
	drain = float(params.get("drain", DEFAULT_DRAIN))


## 每刻直接扣除居民水分，并累计实际扣除量。[br]
## 未绑定居民时安全返回；扣水量会按当前层数放大。
func on_tick() -> void:
	if human == null:
		return
	var amount := get_water_drain_per_tick()
	human.water -= amount
	drained_total += amount


## 返回当前层数下每刻应直接扣除的水量，最小为 0。
func get_water_drain_per_tick() -> float:
	return maxf(drain, 0.0) * float(stacks)
