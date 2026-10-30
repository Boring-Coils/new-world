## 单个居民的工作周期事务。[br]
## 负责创建周期、锁定需求、跨仓库取料、返岗、推进、原子结算与取消回滚。[br]
## 所有移动仍委托给 [HumanMotion]，本类只决定何时前往哪个建筑。
class_name HumanWorkBehavior
extends RefCounted

## 工作事务的阶段。[br]
## 阶段决定本刻应推进路线、锁定工作还是等待结算重试。
enum Phase {
	## 当前没有进行中的工作周期。
	IDLE,
	## 已锁定需求，正在依次前往外部仓库取料。
	ACQUIRING,
	## 物资已取齐，正在返回雇主建筑。
	RETURNING_TO_WORK,
	## 已进入工作站，正在按刻推进工作耗时。
	LOCKED,
	## 工作耗时已结束，但产出尚未成功结算。
	PENDING_SETTLEMENT,
}

## 本事务所属的居民。
var human: Human = null

## 拥有本事务的居民 AI 控制器。
var ai: HumanAI = null

## 执行全部路线的移动组件。
var motion: HumanMotion = null

## 当前工作周期；空闲时为 null。
var cycle: WorkCycle = null

## 当前工作事务阶段。
var phase: Phase = Phase.IDLE

# 需要依次前往取料的外部库存列表。
var _source_inventories: Array[Inventory] = []

# 当前取料路线对应的外部库存索引。
var _source_index: int = 0


## 绑定居民、AI 控制器并缓存移动组件。[br]
## [param host] 是执行工作事务的居民。[br]
## [param controller] 是拥有该事务并负责决策的居民 AI。
func bind(host: Human, controller: HumanAI) -> void:
	human = host
	ai = controller
	motion = host.motion


## 尝试为 [param employer] 创建并启动一次工作周期。[br]
## 会校验雇佣、班次和工作类型，锁定需求与产出空间，再选择站内开工或跨仓库取料路线。[br]
## 返回工作周期是否成功创建并进入执行阶段。
func begin(employer: Building) -> bool:
	if cycle != null and not cycle.is_finished():
		return false
	if not _validate_employer(employer) or not employer.is_work_time():
		return false
	if employer.work_type == null:
		return false
	if not employer.is_work_time(TickManager.get_tick_of_day()):
		return false

	var work_type := employer.work_type
	var new_cycle := WorkCycle.new(
		Time.get_ticks_usec(),
		employer,
		human,
		work_type,
	)
	var holder := new_cycle.get_holder_id()
	var external_inventories := ai.get_reachable_warehouse_inventories()

	# 先锁定需求，再预留产出空间；任一阶段失败都必须释放已获取的记录。
	var demand_locks: Array[String] = []
	if not work_type.demand.is_empty():
		demand_locks = MaterialSystem.lock_demand(
			work_type.demand,
			employer.inventory,
			external_inventories,
			holder,
			employer.origin_cell,
		)
		if demand_locks.is_empty():
			return false
	new_cycle.demand_locks = demand_locks

	new_cycle.output_reservations = MaterialSystem.reserve_output(
		new_cycle.expected_output_volume,
		employer.inventory,
		external_inventories,
		holder,
	)
	if (
		new_cycle.expected_output_volume > 0
		and new_cycle.output_reservations.is_empty()
	):
		MaterialSystem.release_locks(new_cycle.demand_locks)
		new_cycle.demand_locks.clear()
		return false

	cycle = new_cycle
	_take_locks_at(employer.inventory)
	_collect_external_sources()
	# 站内已有全部需求时直接开工，否则按距离依次前往外部仓库取料。
	if _source_inventories.is_empty():
		if not _start_locked():
			return false
	else:
		phase = Phase.ACQUIRING
		_source_index = 0
		if not _start_current_source_route():
			return false
	return true


## 推进当前工作周期一刻。[br]
## 锁定阶段会重新验证需求与产出空间并递减倒计时；当刻结束或待结算时返回状态名。
func tick() -> StringName:
	if cycle == null:
		return &""
	if phase == Phase.LOCKED:
		if not _validate_locked_cycle():
			cancel("工作需求或产出空间失效")
			return &"cancelled"
		cycle.elapsed_ticks += 1
		cycle.remaining_ticks = maxi(cycle.remaining_ticks - 1, 0)
		if cycle.remaining_ticks <= 0:
			return _settle()
	elif phase == Phase.PENDING_SETTLEMENT:
		return _settle()
	return &""


## 响应移动到达事件，推进取料仓库序列或开始返岗/工作。
func on_motion_arrived() -> void:
	if cycle == null:
		return
	if phase == Phase.ACQUIRING:
		if _source_index >= _source_inventories.size():
			_route_to_employer()
			return
		_take_locks_at(_source_inventories[_source_index])
		_source_index += 1
		if _source_index < _source_inventories.size():
			_start_current_source_route()
		else:
			_route_to_employer()
	elif phase == Phase.RETURNING_TO_WORK:
		_start_locked()


## 取料或返岗路线失败时取消当前工作周期。
func on_path_failed() -> void:
	cancel("取料或返岗路径失败")


## 取消当前周期并回滚全部需求锁和产出预留。[br]
## [param reason] 用于日志；场景关闭时静默清理，不输出业务取消日志。
func cancel(reason: String = "工作周期取消") -> void:
	if cycle == null:
		phase = Phase.IDLE
		return
	if not cycle.is_finished():
		MaterialSystem.cancel_cycle(cycle)
	_leave_host_building()
	cycle.status = WorkCycle.Status.CANCELLED
	phase = Phase.IDLE
	cycle = null
	_source_inventories.clear()
	_source_index = 0
	if reason != "" and not MaterialSystem.is_scene_shutdown():
		print("[WORK] %s 周期取消：%s" % [human.name if human != null else "居民", reason])


## 返回周期是否已进入不可被普通生存需求打断的锁定阶段。
func is_locked() -> bool:
	return cycle != null and phase == Phase.LOCKED


## 返回是否仍有一个尚未完成或取消的工作周期。
func is_busy() -> bool:
	return cycle != null and not cycle.is_finished()


## 返回当前阶段的稳定调试名称。
func get_phase_name() -> StringName:
	match phase:
		Phase.ACQUIRING:
			return &"acquiring"
		Phase.RETURNING_TO_WORK:
			return &"returning"
		Phase.LOCKED:
			return &"locked"
		Phase.PENDING_SETTLEMENT:
			return &"pending_settlement"
		_:
			return &"idle"


## 返回工作阶段、周期、倒计时和账本记录数量的调试快照。
func get_debug_snapshot() -> Dictionary:
	if cycle == null:
		return {
			"phase": get_phase_name(),
			"cycle_id": 0,
			"remaining_ticks": 0,
		}
	return {
		"phase": get_phase_name(),
		"cycle_id": cycle.cycle_id,
		"remaining_ticks": cycle.remaining_ticks,
		"demand_locks": cycle.demand_locks.size(),
		"output_reservations": cycle.output_reservations.size(),
	}


## 验证 [param employer] 仍是有效、已放置且与本居民保持雇佣关系的工作站。[br]
## 返回该建筑是否仍可作为当前工作周期的雇主。
func _validate_employer(employer: Building) -> bool:
	return (
		is_instance_valid(employer)
		and employer.is_placed
		and employer.is_hireable
		and human.employer == employer
		and employer.employees.has(human)
	)


## 从当前周期的需求锁中收集需要前往取料的外部库存，并按锁顺序去重。
func _collect_external_sources() -> void:
	_source_inventories.clear()
	for lock_id in cycle.demand_locks:
		var lock := MaterialSystem.get_lock(lock_id)
		if lock.is_empty():
			continue
		var inventory: Inventory = lock["inventory"]
		if inventory == cycle.employer.inventory:
			continue
		if not _source_inventories.has(inventory):
			_source_inventories.append(inventory)


## 前往当前索引入口对应的外部仓库；索引耗尽时改为返回雇主。
func _start_current_source_route() -> bool:
	if _source_index >= _source_inventories.size():
		_route_to_employer()
		return true
	var source := _source_inventories[_source_index]
	if (
		not MaterialSystem.is_inventory_registered(source)
		or not is_instance_valid(source.owner)
	):
		cancel("取料库存已消失")
		return false
	if not motion.move_to_building(source.owner):
		cancel("无法前往取料仓库")
		return false
	return true


## 切换为返岗阶段并开始前往雇主建筑的路线。
func _route_to_employer() -> void:
	if not _validate_employer(cycle.employer):
		cancel("雇主已失效")
		return
	phase = Phase.RETURNING_TO_WORK
	if not motion.move_to_building(cycle.employer):
		cancel("无法返回雇主")


## 在 [param inventory] 对应的仓库入口实际取走尚未取出的需求锁。
func _take_locks_at(inventory: Inventory) -> void:
	if cycle == null or inventory == null:
		return
	for lock_id in cycle.demand_locks:
		var lock := MaterialSystem.get_lock(lock_id)
		if lock.is_empty():
			continue
		var lock_inventory: Inventory = lock["inventory"]
		if lock_inventory == inventory and not bool(lock["taken"]):
			MaterialSystem.take_locked(lock_id)


## 完成全部前置校验后进入锁定阶段并尝试进入工作站内部。[br]
## 返回工作是否成功进入锁定阶段。
func _start_locked() -> bool:
	if cycle == null or not _validate_employer(cycle.employer):
		cancel("雇主已失效")
		return false
	if not cycle.employer.is_work_time():
		cancel("锁定需求后已下班")
		return false
	if not _validate_locked_cycle():
		cancel("工作需求或产出空间失效")
		return false

	phase = Phase.LOCKED
	cycle.status = WorkCycle.Status.LOCKED
	cycle.started_tick = TickManager.total_ticks
	cycle.remaining_ticks = cycle.work_type.duration_ticks
	if cycle.employer.enter(human):
		human.in_building = cycle.employer
		human.set_world_visibility(false)
	return true


## 验证锁定周期仍满足雇佣、需求锁和产出预留要求。[br]
## 产出预留失效时会尝试用当前可达仓库补足。[br]
## 返回周期是否仍满足继续工作的全部条件。
func _validate_locked_cycle() -> bool:
	if cycle == null or not _validate_employer(cycle.employer):
		return false
	for lock_id in cycle.demand_locks:
		var lock := MaterialSystem.get_lock(lock_id)
		if lock.is_empty() or not bool(lock["valid"]) or not bool(lock["taken"]):
			return false
	if MaterialSystem.get_valid_reserved_volume(cycle.output_reservations) < cycle.expected_output_volume:
		if not MaterialSystem.replace_invalid_reservations(
			cycle,
			ai.get_reachable_warehouse_inventories(),
		):
			return false
	return true


## 尝试原子结算工作周期；空间或锁失效时进入待结算阶段。[br]
## 返回工作状态的稳定结果名：完成时返回 [code]&"completed"[/code]，其他情况返回空字符串。
func _settle() -> StringName:
	if not MaterialSystem.settle_cycle(cycle):
		phase = Phase.PENDING_SETTLEMENT
		cycle.status = WorkCycle.Status.PENDING_SETTLEMENT
		return &""

	var result := {
		"employer": cycle.employer,
		"cycle_id": cycle.cycle_id,
		"demand": cycle.work_type.demand.duplicate(),
		"output": cycle.work_type.output.duplicate(),
		"settled_tick": TickManager.total_ticks,
	}
	if not cycle.employer.accept_work_result(result):
		push_error("HumanWorkBehavior: 工作结果提交失败")
	cycle.status = WorkCycle.Status.COMPLETED
	_leave_host_building()
	phase = Phase.IDLE
	cycle = null
	_source_inventories.clear()
	_source_index = 0
	return &"completed"


## 清理居民当前站内占用并恢复世界显示。
func _leave_host_building() -> void:
	if not is_instance_valid(human) or not is_instance_valid(human.in_building):
		return
	var host := human.in_building
	host.leave(human)
	human.in_building = null
	human.set_world_visibility(true)
