## Buff 链路的无头自检节点。[br]
## 在固定刻数添加疲劳、眩晕和口渴，检查层数、倍率、工作闸门、逐刻扣水与自动到期。[br]
## 自检只输出期望值与实际值，通过测试场景的 [code]--bufftest[/code] 参数启用。
extends Node
class_name BuffSelfTest

# 是否已经执行初始 Buff 添加。
var _applied: bool = false

# 是否已经执行口渴到期检查。
var _expiry_checked: bool = false

# 是否已经执行最终倍率与闸门检查。
var _final_checked: bool = false

# 口渴 Buff 的临时引用，用于在移除前后读取累计扣水量。
var _thirst_buff: Thirst = null

# 口渴 Buff 最后记录到的累计额外扣水量。
var _thirst_total: float = 0.0

# 眩晕期间是否检测到居民仍选择工作目标。
var _stun_violation: bool = false


## 订阅每刻完成信号，等待固定刻数执行自检。
func _ready() -> void:
	TickManager.tick_advanced.connect(_on_tick_advanced)


## 每刻走完之后由 signal 触发（此时所有居民都已经结算过）[br]
## [param total_ticks] 是当前全局累计刻数，用于触发固定阶段检查。[br]
## [param _day] 是当前游戏日；自检按累计刻判断，因此不使用该值。[br]
## [param _tick_of_day] 是当前日内刻；自检按累计刻判断，因此不使用该值。
func _on_tick_advanced(total_ticks: int, _day: int, _tick_of_day: int) -> void:
	# 口渴到期那一刻节点就被移除了，先趁它还活着把累计值抄出来
	if _thirst_buff != null and is_instance_valid(_thirst_buff):
		_thirst_total = _thirst_buff.drained_total

	# 眩晕期间不该出现「去上班」这个目标
	if _applied:
		var watched := _get_human(1)
		if (
			watched != null
			and watched.ai.get_debug_snapshot()["goal"] == HumanAI.Goal.WORK
		):
			_stun_violation = true

	if not _applied and total_ticks >= 10:
		_apply_buffs()

	if _applied and not _expiry_checked and total_ticks >= 60:
		_check_expiry()

	if _applied and not _final_checked and total_ticks >= 100:
		_check_final()


## 给居民 1 / 2 / 3 分别上疲劳、眩晕、口渴
func _apply_buffs() -> void:
	_applied = true
	var tired := _get_human(0)
	var stunned := _get_human(1)
	var thirsty := _get_human(2)
	if tired == null or stunned == null or thirsty == null:
		print("[BUFF] 居民数量不足，跳过自检")
		return

	# 顺便挂上到期日志：BuffSystem 自己不再打印，谁想看谁连
	for host in [tired, stunned, thirsty]:
		host.buff_system.buff_expired.connect(_on_buff_expired.bind(host))

	# 疲劳加两次：第一次新建，第二次走 reapply（层数 +1、时长刷满）
	tired.buff_system.add_buff(GlobalEnum.BuffType.FATIGUE, {"duration": 120, "slow": 0.5})
	var fatigue := tired.buff_system.add_buff(GlobalEnum.BuffType.FATIGUE, {"duration": 120, "slow": 0.5})
	stunned.buff_system.add_buff(GlobalEnum.BuffType.STUN, {"duration": 120})
	_thirst_buff = thirsty.buff_system.add_buff(GlobalEnum.BuffType.THIRST, {"duration": 40, "drain": 5.0}) as Thirst

	print("[BUFF] 疲劳 层数=%d（期望 2）速度倍率=%.2f（期望 0.10）" % [
		fatigue.stacks, tired.buff_system.get_speed_multiplier()
	])
	print("[BUFF] 眩晕 can_work=%s（期望 false）速度倍率=%.2f（期望 0.50）" % [
		stunned.buff_system.can_work(), stunned.buff_system.get_speed_multiplier()
	])
	print("[BUFF] 口渴 每刻扣水=%.1f（期望 5.0）时长=%d（期望 40）" % [
		_thirst_buff.get_water_drain_per_tick(), _thirst_buff.duration
	])


## 口渴应该已经到期并自动移除
func _check_expiry() -> void:
	_expiry_checked = true
	var thirsty := _get_human(2)
	print("[BUFF] 口渴已自动移除=%s（期望 true）累计额外扣水=%.1f（期望 200.0）" % [
		not thirsty.buff_system.has_buff(GlobalEnum.BuffType.THIRST), _thirst_total
	])


## 疲劳 / 眩晕还在，且倍率确实乘进了速度
func _check_final() -> void:
	_final_checked = true
	var tired := _get_human(0)
	var stunned := _get_human(1)
	var normal := _get_human(3)
	var base_child := (
		HumanMotion.WALK_CELLS_PER_DAY
		* HumanMotion.CHILD_SPEED_SCALE
		/ float(TickManager.TICKS_PER_DAY)
	)
	var tired_speed := tired.motion.get_speed_cells_per_tick()
	var normal_speed := normal.motion.get_speed_cells_per_tick()

	print("[BUFF] 疲劳仍在=%s 眩晕仍在=%s（都期望 true）" % [
		tired.buff_system.has_buff(GlobalEnum.BuffType.FATIGUE),
		stunned.buff_system.has_buff(GlobalEnum.BuffType.STUN),
	])
	print("[BUFF] 每刻格数 居民1(疲劳×2)=%.4f 反推随机偏移=%.3f（应 0.900~1.100）" % [
		tired_speed, tired_speed / (base_child * 0.1)
	])
	print("[BUFF] 每刻格数 居民4(无buff)=%.4f 反推随机偏移=%.3f（应 0.900~1.100）" % [
		normal_speed, normal_speed / base_child
	])
	print("[BUFF] 眩晕期间跑去上班=%s（期望 false）" % _stun_violation)


## 打印 [param host] 的 [param buff_type] 到期日志。
func _on_buff_expired(buff_type: GlobalEnum.BuffType, host: Human) -> void:
	print("[BUFF] %s 的 %s 到期" % [host.name, GlobalEnum.BuffType.keys()[buff_type]])


## 取第几个居民，越界返回 null[br]
## [param index] 是居民注册表中的零基索引。[br]
## 返回对应居民实例；越界或实例已失效时返回 null。
func _get_human(index: int) -> Human:
	if index < 0 or index >= TickManager.humans.size():
		return null
	var h := TickManager.humans[index]
	if not is_instance_valid(h):
		return null
	return h
