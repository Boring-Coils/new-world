extends Node
class_name BuffBase

## 所有 buff 的基类。[br]
## 新增一种 buff：继承本类 → 覆盖自己关心的钩子 → 在 [member BuffSystem.REGISTRY] 里登记脚本。[br]
## [b]时长不归 buff 自己管[/b]：[member duration] 由 [BuffSystem] 每刻扣减，扣到 0 自动移除，[br]
## 所以写 buff 的时候只关心「效果」和「到期时要不要收尾」，不用自己数刻。[br]
## 所有影响居民的接口默认都是「不生效」：闸门返回 [code]true[/code]，倍率返回 [code]1.0[/code]。[br]
## 只有确实要改的那一个才覆盖，这样 [BuffSystem] 汇总时不用按类型分支。

## 这个 buff 的类型，由 [method setup] 写入
var buff_type: GlobalEnum.BuffType = GlobalEnum.BuffType.FATIGUE

## 挂在哪个居民身上，由 [method setup] 写入
var human: Human = null

## 剩余刻数。[br]
## -1 表示永久 buff，不会被倒计时移除；[br]
## 正数表示还能生效多少刻，每刻由 [BuffSystem] 扣 1。
var duration: int = -1

## 层数。重复添加时默认 +1，效果怎么随层数变化由各 buff 自己决定
var stacks: int = 1


## 由 [BuffSystem] 实例化后立刻调用，绑定类型和主人。[br]
## 子类一般不用覆盖；要初始化自己的字段请覆盖 [method apply]。
func setup(p_type: GlobalEnum.BuffType, p_human: Human) -> void:
	buff_type = p_type
	human = p_human
	name = GlobalEnum.BuffType.keys()[p_type]## name是节点名


## 第一次添加时调用，[param params] 是 [method BuffSystem.add_buff] 收到的参数字典。[br]
## 时长要在这里写进 [member duration]，缺省值自己定；不写就是永久。
func apply(_params: Dictionary) -> void:
	pass


## 已经存在时再次添加调用。[br]
## 默认行为是「层数 +1，并且如果这次带了 duration 就把时长刷满」，[br]
## 想让重复添加变成别的意思（比如只刷新时长、不叠层），覆盖它。
func reapply(params: Dictionary) -> void:
	stacks += 1
	if params.has("duration"):
		duration = int(params["duration"])


## 每游戏刻调用一次。[br]
## 需要按刻推进的状态放这里（持续掉血、读条、定期检查条件都算）。
func on_tick() -> void:
	pass


## 移除前调用，用来收尾：把改过的状态复原、清掉目标、取消任务等
func on_remove() -> void:
	pass


## 这个 buff 允不允许居民工作。默认允许，[BuffSystem] 把所有 buff 的结果取「与」
func can_work() -> bool:
	return true


## 移动速度倍率。默认 1.0，[BuffSystem] 把所有 buff 的结果相乘
func get_speed_multiplier() -> float:
	return 1.0


## 水 / 食物的消耗倍率。默认 1.0，[BuffSystem] 把所有 buff 的结果相乘
func get_consume_multiplier() -> float:
	return 1.0


## 每刻额外直接扣水量，默认 0.0；固定扣减不用乘到基础消耗倍率里。
func get_water_drain_per_tick() -> float:
	return 0.0


## 每刻额外直接扣食物量，默认 0.0。
func get_food_drain_per_tick() -> float:
	return 0.0


## 某类目标的决策权重倍率（0.0 = 完全不想去）。默认 1.0，[BuffSystem] 把所有 buff 的结果相乘
func get_weight_multiplier(_goal: int) -> float:
	return 1.0
