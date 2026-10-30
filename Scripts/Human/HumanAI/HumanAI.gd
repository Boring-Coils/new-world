## 居民行为协调器。[br]
## 维护当前目标、刷新决策快照、驱动动作状态机，并把移动与建筑交互委托给对应组件。[br]
## 状态机是动作状态事实来源，移动只由 [HumanMotion] 执行，工作事务由 [HumanWorkBehavior] 管理。
extends Node
class_name HumanAI

## 当前动作状态发生变化时发出，参数依次为旧状态键和新状态键。
signal state_changed(old_state: StringName, new_state: StringName)

## 当前决策目标发生变化时发出，参数依次为旧目标和新目标。
signal goal_changed(old_goal: int, new_goal: int)

## 居民当前选择的行为目标。
enum Goal {
	## 没有目标。
	NONE,
	## 前往取水站补充水分。
	WATER,
	## 前往取食站补充食物。
	FOOD,
	## 前往雇主工作站执行工作周期。
	WORK,
	## 前往世界等待锚点。
	WAIT,
}

## 工作目标的硬中断处理方式。
enum WorkInterrupt {
	## 继续当前工作，不需要中断。
	NONE,
	## 立即取消周期并离开工作状态。
	CANCEL,
	## 中止当前工作并前往新的生存目标。
	TRAVEL,
}

## 两次常规目标决策之间的模拟刻数。
const DECISION_INTERVAL: int = 5

## 状态机事件：空闲状态已选择新目标。
const EVENT_GOAL_SELECTED: StringName = &"goal_selected"

## 状态机事件：移动已到达目标。
const EVENT_ARRIVED: StringName = &"arrived"

## 状态机事件：移动路径失败。
const EVENT_PATH_FAILED: StringName = &"path_failed"

## 状态机事件：当前目标失效。
const EVENT_TARGET_INVALID: StringName = &"target_invalid"

## 状态机事件：取水或取食服务完成。
const EVENT_SERVICE_COMPLETED: StringName = &"service_completed"

## 状态机事件：工作站服务完成并开始工作周期。
const EVENT_WORK_STARTED: StringName = &"work_started"

## 状态机事件：工作进行中被新的生存目标中断。
const EVENT_WORK_INTERRUPTED: StringName = &"work_interrupted"

## 状态机事件：工作周期已完成或被取消。
const EVENT_WORK_CANCELLED: StringName = &"work_cancelled"

## 状态机事件：新路线已确认并完成离站。
const EVENT_EXIT_ROUTE_STARTED: StringName = &"exit_route_started"

## 状态机事件：请求暂停普通目标并进入脱困状态。
const EVENT_RELOCATION_REQUESTED: StringName = &"relocation_requested"

## 状态机事件：脱困移动成功结束。
const EVENT_RELOCATION_FINISHED: StringName = &"relocation_finished"

## 状态机事件：脱困移动失败。
const EVENT_RELOCATION_FAILED: StringName = &"relocation_failed"

## 控制居民动作的 Godot 状态图节点。
@onready var state_chart: StateChart = $StateChart

## 当前 AI 服务的居民。
var human: Human

## 当前居民使用的移动组件。
var motion: HumanMotion

# 当前决策刻的居民状态快照。
var _context := HumanAIContext.new()

# 当前居民的工作周期事务。
var _work_behavior := HumanWorkBehavior.new()

# 当前选择的决策目标。
var _goal: int = Goal.NONE

# 当前目标建筑；等待和无目标状态为 null。
var _target: Building = null

# 当前活动的动作状态实例。
var _active_state: HumanStateBase = null

# 当前活动状态的稳定键。
var _active_state_key: StringName = &""

# 当前 AI 已经过的模拟刻数。
var _tick_count: int = 0

# 决策周期的随机相位，避免所有居民同刻决策。
var _decision_offset: int = 0

# 是否在下一个决策槽立即重新选择目标。
var _force_decision: bool = true

# 是否在状态机就绪后补发脱困请求。
var _pending_relocation: bool = false

# 居民是否已经到达世界等待锚点。
var _at_wait_place: bool = false


## 绑定 [param host] 居民、工作事务和移动信号，并递归绑定全部状态节点。
func bind(host: Human) -> void:
	if human == host:
		return

	human = host
	motion = human.motion
	_work_behavior.bind(human, self)
	_decision_offset = randi() % DECISION_INTERVAL

	_bind_state_nodes(state_chart)
	_connect_motion_signals()


## 递归查找并绑定 [param node] 下所有 [HumanStateBase] 子节点。
func _bind_state_nodes(node: Node) -> void:
	for child in node.get_children():
		if child is HumanStateBase:
			child.bind(self, human)
		_bind_state_nodes(child)


## 连接移动到达、路径失败和脱困完成信号，重复调用不会重复连接。
func _connect_motion_signals() -> void:
	if not motion.arrived.is_connected(_on_motion_arrived):
		motion.arrived.connect(_on_motion_arrived)
	if not motion.path_failed.is_connected(_on_motion_path_failed):
		motion.path_failed.connect(_on_motion_path_failed)
	if not motion.relocation_finished.is_connected(_on_relocation_finished):
		motion.relocation_finished.connect(_on_relocation_finished)


## 刷新决策快照、推进状态机，并在存在移动时推进 [HumanMotion]。
func on_tick() -> void:
	if not is_instance_valid(human):
		return

	_tick_count += 1
	_context.refresh(human)

	if not state_chart.is_node_ready() or _active_state_key == &"":
		return

	# 脱困请求可能早于状态图初始状态到达，因此延迟到状态机可用后再派发。
	if _pending_relocation:
		_pending_relocation = false
		state_chart.send_event(EVENT_RELOCATION_REQUESTED)

	state_chart.step()

	if motion.is_moving() or motion.is_relocating():
		motion.on_tick()


## 响应移动到达：工作事务优先处理，等待目标到达后转入等待状态。
func _on_motion_arrived(_destination: Vector2i) -> void:
	if _active_state_key == &"working" and _work_behavior.is_busy():
		_work_behavior.on_motion_arrived()
		return
	if _goal == Goal.WAIT:
		_at_wait_place = true
		send_event(EVENT_TARGET_INVALID)
		return
	send_event(EVENT_ARRIVED)


## 响应路径失败：工作事务自行取消，其余状态发送通用路径失败事件。
func _on_motion_path_failed(_destination: Vector2i) -> void:
	if _active_state_key == &"working" and _work_behavior.is_busy():
		_work_behavior.on_path_failed()
		send_event(EVENT_WORK_CANCELLED)
		return
	send_event(EVENT_PATH_FAILED)


## 脱困移动成功后向状态机发送完成事件。
func _on_relocation_finished() -> void:
	send_event(EVENT_RELOCATION_FINISHED)


## 进入空闲状态时清理目标、停止移动并强制下一次立即决策。
func on_idle_entered() -> void:
	_force_decision = true
	clear_goal()
	motion.stop()


## 尝试按评分选择当前可执行目标。[br]
## 成功选择返回 [code]true[/code]；尚未到决策刻、目标不可用或已在等待点返回 [code]false[/code]。
func try_select_idle_goal() -> bool:
	_context.refresh(human)
	if not _consume_decision_slot():
		return false

	# 评分只提供候选顺序，实际选择还要过滤当前不紧迫或条件不满足的目标。
	for goal in HumanDecision.rank_goals(_context):
		if goal == Goal.WATER and not _is_water_urgent():
			continue
		if goal == Goal.FOOD and not _is_food_urgent():
			continue
		if goal == Goal.WORK and not _is_work_goal_available():
			continue

		var building := _find_target_for_goal(goal)
		if building == null:
			continue

		_set_goal(goal, building)
		return true

	if not _at_wait_place:
		_set_goal(Goal.WAIT, null)
		return true
	return false


## 允许下一次空闲步进立即进入决策。
func force_next_decision() -> void:
	_force_decision = true


## 判断本刻是否允许决策；强制决策优先于周期相位。
func _consume_decision_slot() -> bool:
	if _force_decision:
		_force_decision = false
		return true

	if (_tick_count + _decision_offset) % DECISION_INTERVAL != 0:
		return false
	return true


## 返回水分是否已低于紧急生存阈值。
func _is_water_urgent() -> bool:
	var urgent_ticks := HumanDecision.URGENT_GAME_SECONDS / TickManager.GAME_SECONDS_PER_TICK
	return _context.water_ticks_left <= urgent_ticks


## 返回食物是否已低于紧急生存阈值。
func _is_food_urgent() -> bool:
	var urgent_ticks := HumanDecision.URGENT_GAME_SECONDS / TickManager.GAME_SECONDS_PER_TICK
	return _context.food_ticks_left <= urgent_ticks


## 返回当前是否具备前往雇主工作的完整条件。
func _is_work_goal_available() -> bool:
	return (
		_context.can_work
		and is_instance_valid(human.employer)
		and human.employer.is_placed
		and human.employer.is_hireable
		and human.employer.employees.has(human)
		and human.employer.work_type != null
		and human.employer.is_work_time()
	)


## 前往世界等待锚点并叠加居民的个人偏移。
func _start_wait_travel() -> bool:
	var world_node := _find_world_ancestor()
	if world_node == null:
		push_error("%s 找不到 World，无法前往等待点" % human.name)
		send_event(EVENT_PATH_FAILED)
		return false
	var wait_position: Vector2 = world_node.WAIT_PLACE + human.wait_offset
	return motion.move_to_position(wait_position)


## 从居民父节点向上查找最近的 [World]。
func _find_world_ancestor() -> World:
	var node: Node = human.get_parent()
	while node != null:
		if node is World:
			return node as World
		node = node.get_parent()
	return null


## 为 [param goal] 查找当前可达的目标建筑；等待或无目标返回 null。
func _find_target_for_goal(goal: int) -> Building:
	match goal:
		Goal.WATER:
			return motion.find_nearest_building(GlobalEnum.BuildingType.WATER)
		Goal.FOOD:
			return motion.find_nearest_building(GlobalEnum.BuildingType.FOOD)
		Goal.WORK:
			if (
				_is_work_goal_available()
				and is_instance_valid(human.employer)
			):
				return human.employer
			return null
		_:
			return null


## 原子更新当前目标与目标建筑，并在目标变化时发出 [signal goal_changed]。
func _set_goal(new_goal: int, new_target: Building) -> void:
	var old_goal := _goal
	_goal = new_goal
	_target = new_target
	if new_goal != Goal.WAIT:
		_at_wait_place = false
	if old_goal != new_goal:
		goal_changed.emit(old_goal, new_goal)


## 清除当前目标及其建筑引用。
func clear_goal() -> void:
	_set_goal(Goal.NONE, null)


## 返回当前决策目标。
func get_goal() -> int:
	return _goal


## 返回当前目标建筑；等待或无目标时为 null。
func get_target() -> Building:
	return _target


## 验证当前目标是否仍与目标类型、放置状态和雇佣关系一致。
func is_target_valid() -> bool:
	if _goal == Goal.WAIT:
		return true
	if not is_instance_valid(_target) or _target.is_queued_for_deletion():
		return false
	if not _target.is_placed or not TickManager.buildings.has(_target):
		return false

	# 每种目标都验证建筑类型和关系，避免沿用已被替换或解雇的旧引用。
	match _goal:
		Goal.WATER:
			return _target.building_type == GlobalEnum.BuildingType.WATER
		Goal.FOOD:
			return _target.building_type == GlobalEnum.BuildingType.FOOD
		Goal.WORK:
			return (
				_target == human.employer
				and _target.is_hireable
				and _target.employees.has(human)
			)
		_:
			return false


## 返回 Buff 汇总后的当前工作许可。
func is_work_allowed() -> bool:
	return _context.can_work


## 为当前目标启动移动；等待目标前往等待点，其他目标前往目标建筑。
func start_travel_to_current_target() -> bool:
	if _goal == Goal.WAIT:
		return _start_wait_travel()
	if not is_target_valid():
		send_event(EVENT_TARGET_INVALID)
		return false

	if motion.is_moving():
		return true

	return motion.move_to_building(_target)


## 结算当前建筑服务并返回状态机应发送的事件。[br]
## 取水与取食会补满对应资源；工作站返回开工事件，失效目标返回取消或无效事件。
func complete_current_wait() -> StringName:
	if not is_target_valid():
		return EVENT_TARGET_INVALID

	# 服务完成只处理当前目标类型，随后清空目标让状态机重新决策。
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
			if not _is_work_goal_available() or _target.work_type == null:
				return EVENT_WORK_CANCELLED
			return EVENT_WORK_STARTED
		_:
			clear_goal()
			return EVENT_TARGET_INVALID


## 在当前目标有效时启动居民的工作周期。
func begin_work_cycle() -> bool:
	if not is_target_valid() or not is_instance_valid(human.employer):
		return false
	return _work_behavior.begin(human.employer)


## 推进当前工作周期一刻并返回阶段结果。
func tick_work_cycle() -> StringName:
	return _work_behavior.tick()


## 返回当前工作周期是否已锁定且不可被普通需求打断。
func is_work_cycle_locked() -> bool:
	return _work_behavior.is_locked()


## 取消当前工作周期，并使用 [param reason] 记录原因。
func cancel_work_cycle(reason: String = "工作周期取消") -> void:
	_work_behavior.cancel(reason)


## 返回当前工作事务阶段的稳定名称。
func get_work_phase_name() -> StringName:
	return _work_behavior.get_phase_name()


## 返回当前居民使用的工作事务对象，供测试和状态读取。
func get_work_behavior() -> HumanWorkBehavior:
	return _work_behavior


## 返回当前居民可达的仓库库存，并按预计移动刻数和位置稳定排序。
func get_reachable_warehouse_inventories() -> Array[Inventory]:
	var candidates: Array[Dictionary] = []
	for warehouse in TickManager.get_buildings_of_type(GlobalEnum.BuildingType.WAREHOUSE):
		if not is_instance_valid(warehouse) or warehouse.inventory == null:
			continue
		var ticks := motion.get_ticks_to_building_instance(warehouse)
		if ticks >= 0:
			candidates.append({
				"inventory": warehouse.inventory,
				"ticks": ticks,
				"origin": warehouse.origin_cell,
			})
	# 先按实际移动刻数排序，再以坐标打破平局，确保取料顺序稳定。
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["ticks"]) != int(b["ticks"]):
				return int(a["ticks"]) < int(b["ticks"])
			var a_origin: Vector2i = a["origin"]
			var b_origin: Vector2i = b["origin"]
			if a_origin.x != b_origin.x:
				return a_origin.x < b_origin.x
			return a_origin.y < b_origin.y
	)
	var result: Array[Inventory] = []
	for candidate in candidates:
		result.append(candidate["inventory"])
	return result


## 检查紧急生存需求是否足以中断当前工作目标。[br]
## 找到可执行的新目标时更新目标并返回 [code]true[/code]。
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


## 评估工作状态当前应执行的中断类型。
func evaluate_work_interrupt() -> int:
	if not is_target_valid() or not is_instance_valid(human.employer):
		return WorkInterrupt.CANCEL
	if not is_work_allowed():
		return WorkInterrupt.CANCEL

	# 锁定周期内口渴、饥饿和下班都不能打断；只有 Buff 工作闸门等硬中断生效。
	if _work_behavior.is_locked():
		return WorkInterrupt.NONE
	return WorkInterrupt.NONE


## 取消工作周期并立即离开当前建筑；不在建筑内时仅停止工作。
func leave_work_now() -> bool:
	cancel_work_cycle("居民离开工作")
	if is_instance_valid(human.in_building):
		return motion.leave_current_building()

	human.in_building = null
	human.set_world_visibility(true)
	return false


## 处理 [param building] 的雇佣结束，清理目标、移动与工作状态。
func on_employment_ended(building: Building, reason: String) -> void:
	if human.employer == building:
		human.employer = null
	cancel_work_cycle(reason)
	clear_goal()
	motion.stop()
	send_event(EVENT_WORK_CANCELLED)


## 居民离开场景前取消工作周期并清理目标。
func cleanup_before_removal() -> void:
	cancel_work_cycle("居民离开场景")
	clear_goal()


## 请求进入脱困状态；状态机尚未就绪时延迟到下一次刻推进。
func request_relocation() -> void:
	if not state_chart.is_node_ready() or _active_state_key == &"":
		_pending_relocation = true
		return
	state_chart.send_event(EVENT_RELOCATION_REQUESTED)


## 清除普通目标并请求 [HumanMotion] 前往最近安全格。
func begin_relocation() -> bool:
	clear_goal()
	return motion.relocate_to_nearest_walkable()


## 输出包含居民名称的脱困失败错误。
func report_relocation_failure() -> void:
	push_error("%s 脱困命令失败，检查 HumanMotion 的格坐标日志" % human.name)


## 返回居民当前是否正在执行脱困移动。
func is_relocating() -> bool:
	return motion.is_relocating()


## 返回目标、状态、生存倒计时、移动与工作阶段的调试快照。
func get_debug_snapshot() -> Dictionary:
	var target_name := ""
	if is_instance_valid(_target):
		target_name = String(_target.name)

	return {
		"goal": _goal,
		"goal_name": Goal.keys()[_goal],
		"state": _active_state_key,
		"target": target_name,
		"employer": human.employer.name if is_instance_valid(human.employer) else "",
		"target_valid": is_target_valid(),
		"water_ticks_left": _context.water_ticks_left,
		"food_ticks_left": _context.food_ticks_left,
		"can_work": _context.can_work,
		"moving": motion.is_moving(),
		"path_size": motion.get_path_size(),
		"relocating": motion.is_relocating(),
		"work_phase": get_work_phase_name(),
		"work_locked": _work_behavior.is_locked(),
		"wait_left": (
			_active_state.get_debug_data().get("wait_left", 0)
			if is_instance_valid(_active_state)
			else 0
		),
	}


## 由状态基类通知当前状态进入，并更新活动状态引用与变化信号。[br]
## [param state_key] 是稳定状态键，[param state] 是状态实例。
func notify_state_entered(
	state_key: StringName,
	state: HumanStateBase,
) -> void:
	var old_key := _active_state_key
	_active_state = state
	_active_state_key = state_key
	if old_key != state_key:
		state_changed.emit(old_key, state_key)


## 在状态机就绪时转发 [param event]；未就绪时安全忽略。
func send_event(event: StringName) -> void:
	if state_chart.is_node_ready():
		state_chart.send_event(event)
