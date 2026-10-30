class_name HumanWorkBehavior
extends RefCounted

## 单个居民自己的工作周期事务。负责取料、路线、锁定周期、
## 原子结算与取消回滚；移动仍全部委托给 HumanMotion。

enum Phase {
	IDLE,
	ACQUIRING,
	RETURNING_TO_WORK,
	LOCKED,
	PENDING_SETTLEMENT,
}

var human: Human = null
var ai: HumanAI = null
var motion: HumanMotion = null
var cycle: WorkCycle = null
var phase: Phase = Phase.IDLE

var _source_inventories: Array[Inventory] = []
var _source_index: int = 0


func bind(host: Human, controller: HumanAI) -> void:
	human = host
	ai = controller
	motion = host.motion


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
	if _source_inventories.is_empty():
		if not _start_locked():
			return false
	else:
		phase = Phase.ACQUIRING
		_source_index = 0
		if not _start_current_source_route():
			return false
	return true


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


func on_path_failed() -> void:
	cancel("取料或返岗路径失败")


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


func is_locked() -> bool:
	return cycle != null and phase == Phase.LOCKED


func is_busy() -> bool:
	return cycle != null and not cycle.is_finished()


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


func _validate_employer(employer: Building) -> bool:
	return (
		is_instance_valid(employer)
		and employer.is_placed
		and employer.is_hireable
		and human.employer == employer
		and employer.employees.has(human)
	)


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


func _route_to_employer() -> void:
	if not _validate_employer(cycle.employer):
		cancel("雇主已失效")
		return
	phase = Phase.RETURNING_TO_WORK
	if not motion.move_to_building(cycle.employer):
		cancel("无法返回雇主")


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
	if cycle.employer is WorkStation:
		var station := cycle.employer as WorkStation
		station.enter(human)
		human.in_building = station
		human.set_world_visibility(false)
	return true


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


func _leave_host_building() -> void:
	if not is_instance_valid(human) or not is_instance_valid(human.in_building):
		return
	var host := human.in_building
	if host is WorkStation:
		(host as WorkStation).leave(human)
	human.in_building = null
	human.set_world_visibility(true)
