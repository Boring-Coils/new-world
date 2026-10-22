extends Node
class_name BuffSystem

## 每个居民身上挂一个，负责 buff 的「增删查」和「汇总」。[br]
## 它自己不知道任何 buff 的具体逻辑：类型 → 脚本的对应关系全在 [member REGISTRY] 里，[br]
## 效果一律问各个 buff，本类只做三件事：[br]
## - 添加：没有就实例化，有就交给那个 buff 自己决定怎么叠（[method BuffBase.reapply]）[br]
## - 倒计时：每刻扣 [member BuffBase.duration]，扣到 0 自动移除[br]
## - 汇总：闸门取「与」、倍率相乘，供 [Human] 直接读[br]
## 本节点必须是 [Human] 的直接子节点——[method add_buff] 靠 [method Node.get_parent] 找主人。

## 类型 → buff 脚本的映射表。[br]
## 新增 buff 时在这里加一行，脚本要求 [code]extends BuffBase[/code]。[br]
## 映射不到会直接 push_error，不会静默失败（否则加了 buff 没效果最难查）。
const REGISTRY: Dictionary = {
	GlobalEnum.BuffType.FATIGUE: preload("res://Scripts/Buff/Types/Fatigue.gd"),
	GlobalEnum.BuffType.STUN: preload("res://Scripts/Buff/Types/Stun.gd"),
	GlobalEnum.BuffType.THIRST: preload("res://Scripts/Buff/Types/Thirst.gd"),
}

## 当前挂着的 buff，顺序就是添加顺序（同顺序参与每刻结算）
var buffs: Array[BuffBase] = []


## 添加一个 buff。[br]
## [param params] 是可选的参数字典，键名由各个 buff 自己约定，[br]
## 例如疲劳认 [code]duration[/code] / [code]intensity[/code]。[br]
## 返回实际生效的那个 buff 节点：新建的和复用的都是它，方便测试时直接读状态。
func add_buff(type: GlobalEnum.BuffType, params: Dictionary = {}) -> BuffBase:
	var exist := get_buff(type)
	if exist != null:
		exist.reapply(params)
		return exist

	var script: Script = REGISTRY.get(type)
	if script == null:
		push_error("[BuffSystem] 没有登记 %s 的脚本，检查 GlobalEnum.BuffType 和 REGISTRY" % type)
		return null

	var buff := script.new() as BuffBase
	if buff == null:
		push_error("[BuffSystem] %s 的脚本没有 extends BuffBase" % type)
		return null

	var host := get_parent()
	if not host is Human:
		push_error("[BuffSystem] 父节点不是 Human，buff 没有效果")
		buff.free()
		return null

	buff.setup(type, host)
	add_child(buff)
	buff.apply(params)
	buffs.append(buff)
	return buff


## 移除一个 buff（不存在的类型直接忽略，不报错）
func remove_buff(type: GlobalEnum.BuffType) -> void:
	var buff := get_buff(type)
	if buff == null:
		return
	buff.on_remove()
	buffs.erase(buff)
	buff.queue_free()


## 清空所有 buff（换地图、重置居民时用）
func clear_all() -> void:
	for buff in buffs.duplicate():
		remove_buff(buff.buff_type)


## 有没有这个 buff
func has_buff(type: GlobalEnum.BuffType) -> bool:
	return get_buff(type) != null


## 取出这个 buff，没有返回 null
func get_buff(type: GlobalEnum.BuffType) -> BuffBase:
	for buff in buffs:
		if is_instance_valid(buff) and buff.buff_type == type:
			return buff
	return null


## 每游戏刻由 [Human.on_tick] 调用：[br]
## 先让每个 buff 自己推进一刻，再扣时长，扣到 0 的在这一刻结束后移除。[br]
## 先 on_tick 再扣时长，是为了让 [code]duration = 30[/code] 的 buff 正好生效 30 刻，不多不少。
func on_tick() -> void:
	var expired: Array[BuffBase] = []
	for buff in buffs:
		if not is_instance_valid(buff):
			continue
		buff.on_tick()
		if buff.duration > 0:
			buff.duration -= 1
			if buff.duration <= 0:
				expired.append(buff)
	for buff in expired:
		print("[BUFF] %s 的 %s 到期" % [get_parent().name, GlobalEnum.BuffType.keys()[buff.buff_type]])
		remove_buff(buff.buff_type)


## 汇总：只要有一个 buff 说不能工作，就是不能工作
func can_work() -> bool:
	for buff in buffs:
		if is_instance_valid(buff) and not buff.can_work():
			return false
	return true


## 汇总：所有 buff 的速度倍率相乘
func get_speed_multiplier() -> float:
	var result := 1.0
	for buff in buffs:
		if is_instance_valid(buff):
			result *= buff.get_speed_multiplier()
	return result


## 汇总：所有 buff 的消耗倍率相乘
func get_consume_multiplier() -> float:
	var result := 1.0
	for buff in buffs:
		if is_instance_valid(buff):
			result *= buff.get_consume_multiplier()
	return result


## 汇总：所有 buff 对这类目标的权重倍率相乘
func get_weight_multiplier(goal: int) -> float:
	var result := 1.0
	for buff in buffs:
		if is_instance_valid(buff):
			result *= buff.get_weight_multiplier(goal)
	return result
