extends Node
class_name HumanAI

## 居民行为协调器：维护目标、驱动状态机，并把动作交给 Motion 或建筑执行。

signal state_changed(old_state: StringName, new_state: StringName)
signal goal_changed(old_goal: int, new_goal: int)

enum Goal {
	NONE,
	WATER,
	FOOD,
	WORK,
}

enum WorkInterrupt {
	NONE,
	CANCEL,
	TRAVEL,
}

const DECISION_INTERVAL: int = 5

const EVENT_GOAL_SELECTED: StringName = &"goal_selected"
const EVENT_ARRIVED: StringName = &"arrived"
const EVENT_PATH_FAILED: StringName = &"path_failed"
const EVENT_TARGET_INVALID: StringName = &"target_invalid"
const EVENT_SERVICE_COMPLETED: StringName = &"service_completed"
const EVENT_WORK_STARTED: StringName = &"work_started"
const EVENT_WORK_INTERRUPTED: StringName = &"work_interrupted"
const EVENT_WORK_CANCELLED: StringName = &"work_cancelled"
const EVENT_EXIT_ROUTE_STARTED: StringName = &"exit_route_started"
const EVENT_RELOCATION_REQUESTED: StringName = &"relocation_requested"
const EVENT_RELOCATION_FINISHED: StringName = &"relocation_finished"
const EVENT_RELOCATION_FAILED: StringName = &"relocation_failed"

@onready var state_chart: StateChart = $StateChart

var human: Human
var motion: HumanMotion

var _context := HumanAIContext.new()
var _goal: int = Goal.NONE
var _target: Building = null
var _active_state: HumanStateBase = null
var _active_state_key: StringName = &""

var _tick_count: int = 0
var _decision_offset: int = 0
var _force_decision: bool = true
var _pending_relocation: bool = false


func bind(host: Human) -> void:
	if human == host:
		return

	human = host
	motion = human.motion
	_decision_offset = randi() % DECISION_INTERVAL

	_bind_state_nodes(state_chart)
	_connect_motion_signals()


func _bind_state_nodes(node: Node) -> void:
	for child in node.get_children():
		if child is HumanStateBase:
			child.bind(self, human)
		_bind_state_nodes(child)


func _connect_motion_signals() -> void:
	if not motion.arrived.is_connected(_on_motion_arrived):
		motion.arrived.connect(_on_motion_arrived)
	if not motion.path_failed.is_connected(_on_motion_path_failed):
		motion.path_failed.connect(_on_motion_path_failed)
	if not motion.relocation_finished.is_connected(_on_relocation_finished):
		motion.relocation_finished.connect(_on_relocation_finished)


func on_tick() -> void:
	if not is_instance_valid(human):
		return

	_tick_count += 1
	_context.refresh(human)

	if not state_chart.is_node_ready() or _active_state_key == &"":
		return

	if _pending_relocation:
		_pending_relocation = false
		state_chart.send_event(EVENT_RELOCATION_REQUESTED)

	state_chart.step()

	if motion.is_moving() or motion.is_relocating():
		motion.on_tick()


func _on_motion_arrived(_destination: Vector2i) -> void:
	send_event(EVENT_ARRIVED)


func _on_motion_path_failed(_destination: Vector2i) -> void:
	send_event(EVENT_PATH_FAILED)


func _on_relocation_finished() -> void:
	send_event(EVENT_RELOCATION_FINISHED)


func on_idle_entered() -> void:
	_force_decision = true
	clear_goal()
	motion.stop()


func try_select_idle_goal() -> bool:
	if not _consume_decision_slot():
		return false

	for goal in HumanDecision.rank_goals(_context):
		if goal == Goal.WORK and not _context.can_work:
			continue

		var building := _find_target_for_goal(goal)
		if building == null:
			continue

		_set_goal(goal, building)
		return true

	return false


func _consume_decision_slot() -> bool:
	if _force_decision:
		_force_decision = false
		return true

	if (_tick_count + _decision_offset) % DECISION_INTERVAL != 0:
		return false
	return true


func _find_target_for_goal(goal: int) -> Building:
	match goal:
		Goal.WATER:
			return motion.find_nearest_building(GlobalEnum.BuildingType.WATER)
		Goal.FOOD:
			return motion.find_nearest_building(GlobalEnum.BuildingType.FOOD)
		Goal.WORK:
			var building := motion.find_nearest_building(GlobalEnum.BuildingType.WORK)
			if building is WorkStation:
				return building
			return null
		_:
			return null


func _set_goal(new_goal: int, new_target: Building) -> void:
	var old_goal := _goal
	_goal = new_goal
	_target = new_target
	if old_goal != new_goal:
		goal_changed.emit(old_goal, new_goal)


func clear_goal() -> void:
	_set_goal(Goal.NONE, null)


func get_goal() -> int:
	return _goal


func get_target() -> Building:
	return _target


func is_target_valid() -> bool:
	if not is_instance_valid(_target) or _target.is_queued_for_deletion():
		return false
	if not _target.is_placed or not TickManager.buildings.has(_target):
		return false

	match _goal:
		Goal.WATER:
			return _target.building_type == GlobalEnum.BuildingType.WATER
		Goal.FOOD:
			return _target.building_type == GlobalEnum.BuildingType.FOOD
		Goal.WORK:
			return _target is WorkStation
		_:
			return false


func is_work_allowed() -> bool:
	return _context.can_work


func start_travel_to_current_target() -> bool:
	if not is_target_valid():
		send_event(EVENT_TARGET_INVALID)
		return false

	if motion.is_moving():
		return true

	return motion.move_to_building(_target)


func complete_current_wait() -> StringName:
	if not is_target_valid():
		return EVENT_TARGET_INVALID

	match _target.building_type:
		GlobalEnum.BuildingType.WATER:
			human.water = Human.MAX_WATER
			clear_goal()
			return EVENT_SERVICE_COMPLETED
		GlobalEnum.BuildingType.FOOD:
			human.food = Human.MAX_FOOD
			clear_goal()
			return EVENT_SERVICE_COMPLETED
		GlobalEnum.BuildingType.WORK:
			return EVENT_WORK_STARTED
		_:
			clear_goal()
			return EVENT_TARGET_INVALID


func enter_current_workstation() -> bool:
	if not is_target_valid() or not (_target is WorkStation):
		return false

	var station := _target as WorkStation
	station.enter(human)
	human.in_building = station
	human.set_world_visibility(false)
	return true


func try_interrupt_work_goal() -> bool:
	if not _consume_decision_slot():
		return false

	for next_goal in HumanDecision.rank_goals(_context):
		if not HumanDecision.should_interrupt_work_for_goal(_context, next_goal):
			continue

		var next_target := _find_target_for_goal(next_goal)
		if next_target == null:
			continue

		_set_goal(next_goal, next_target)
		return true

	return false


func evaluate_work_interrupt() -> int:
	if not is_target_valid():
		return WorkInterrupt.CANCEL
	if human.in_building != _target:
		return WorkInterrupt.CANCEL
	if not is_work_allowed():
		return WorkInterrupt.CANCEL

	if try_interrupt_work_goal():
		return WorkInterrupt.TRAVEL

	return WorkInterrupt.NONE


func leave_work_now() -> bool:
	if is_instance_valid(human.in_building):
		return motion.leave_current_building()

	human.in_building = null
	human.set_world_visibility(true)
	return false


func request_relocation() -> void:
	if not state_chart.is_node_ready() or _active_state_key == &"":
		_pending_relocation = true
		return
	state_chart.send_event(EVENT_RELOCATION_REQUESTED)


func begin_relocation() -> bool:
	clear_goal()
	return motion.relocate_to_nearest_walkable()


func report_relocation_failure() -> void:
	push_error("%s 脱困命令失败，检查 HumanMotion 的格坐标日志" % human.name)


func is_relocating() -> bool:
	return motion.is_relocating()


func get_debug_snapshot() -> Dictionary:
	var target_name := ""
	if is_instance_valid(_target):
		target_name = String(_target.name)

	return {
		"goal": _goal,
		"goal_name": Goal.keys()[_goal],
		"state": _active_state_key,
		"target": target_name,
		"target_valid": is_target_valid(),
		"water_ticks_left": _context.water_ticks_left,
		"food_ticks_left": _context.food_ticks_left,
		"can_work": _context.can_work,
		"moving": motion.is_moving(),
		"path_size": motion.get_path_size(),
		"relocating": motion.is_relocating(),
		"wait_left": (
			_active_state.get_debug_data().get("wait_left", 0)
			if is_instance_valid(_active_state)
			else 0
		),
	}


func notify_state_entered(
	state_key: StringName,
	state: HumanStateBase,
) -> void:
	var old_key := _active_state_key
	_active_state = state
	_active_state_key = state_key
	if old_key != state_key:
		state_changed.emit(old_key, state_key)


func send_event(event: StringName) -> void:
	if state_chart.is_node_ready():
		state_chart.send_event(event)
