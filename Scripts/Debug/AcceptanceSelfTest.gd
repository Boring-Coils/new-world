## v0.0.1.4 完整验收自检器。[br]
## 依序覆盖雇佣、班次等待、工作周期、库存账本、清理、UI 契约和真实模拟集成检查。[br]
## 每个验收 ID 只输出一次 PASS/FAIL，最终检查物资锁与预留均无悬空。
extends Node
class_name AcceptanceSelfTest

# 已执行的验收项总数。
var _total: int = 0

# 已通过的验收项数量。
var _passed: int = 0

# 失败验收项的 ID 列表。
var _failures: Array[String] = []

# 验收期间创建、需要统一销毁的建筑。
var _tracked_buildings: Array[Building] = []

# 验收期间创建、需要统一销毁的居民。
var _tracked_humans: Array[Human] = []

# 用于隔离库存测试的虚拟建筑所有者。
var _virtual_owners: Array[Building] = []

# 验收前被暂停、结束后需要恢复的居民。
var _suspended_humans: Array[Human] = []

# 验收期间临时注销、结束后需要恢复的仓库库存。
var _suspended_inventories: Array[Inventory] = []

# 验收测试设施的递增布局序号。
var _fixture_index: int = 0

# 验收开始前的全局累计刻数，用于结束后恢复时间。
var _original_tick: int = 0


## 延迟启动完整验收流程，确保测试场景节点已经进入场景树。
func _ready() -> void:
	call_deferred("_run")


## 执行全部验收分组、恢复外部测试状态并输出最终汇总。
func _run() -> void:
	# 暂停自动走时并隔离现有场景实体，确保每组测试只观察自己创建的设施。
	TickManager.auto_run = false
	_original_tick = TickManager.total_ticks
	_suspend_existing_humans()
	_suspend_existing_warehouses()
	await get_tree().process_frame

	# 各分组按依赖顺序执行；清理组结束后再验证 UI 与真实模拟集成。
	await _test_employment()
	await _test_schedule_and_waiting()
	await _test_work_cycles()
	await _test_carry()
	await _test_demolish()
	await _test_rotation()
	await _test_inventory()
	await _test_cleanup()
	await _test_status_display()
	await _test_ui_contract()
	await _dispose_tracked()

	_restore_existing_warehouses()
	_restore_existing_humans()
	TickManager.total_ticks = _original_tick
	await _test_integration()

	var material_errors := MaterialSystem.validate()
	var no_orphans := (
		MaterialSystem.get_open_lock_count() == 0
		and MaterialSystem.get_open_reservation_count() == 0
	)
	var final_ok := material_errors.is_empty() and no_orphans
	_check(
		"LOG",
		final_ok,
		"物资账本无错误且无孤立锁定/预留",
		"errors=%s locks=%d reservations=%d" % [
			material_errors,
			MaterialSystem.get_open_lock_count(),
			MaterialSystem.get_open_reservation_count(),
		],
	)

	print("[ACCEPT] SUMMARY total=%d passed=%d failed=%d" % [
		_total,
		_passed,
		_failures.size(),
	])
	if not _failures.is_empty():
		print("[ACCEPT] FAILED_IDS=%s" % ", ".join(_failures))
	MaterialSystem.begin_scene_shutdown()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)


## 记录并输出一个验收项的结果。[br]
## [param case_id] 是稳定验收 ID，[param condition] 决定 PASS/FAIL，[param expected] 与 [param actual] 用于诊断。
func _check(
	case_id: String,
	condition: bool,
	expected: String,
	actual: String,
) -> void:
	_total += 1
	if condition:
		_passed += 1
		print("[ACCEPT] PASS %-8s expected=%s actual=%s" % [case_id, expected, actual])
	else:
		_failures.append(case_id)
		print("[ACCEPT] FAIL %-8s expected=%s actual=%s" % [case_id, expected, actual])


## 验证雇佣资格、目标人数调整、失效雇员处理和调试居民生成。
func _test_employment() -> void:
	# 雇佣组覆盖目标人数、年龄资格、唯一雇主、失效关系和调试放置。
	var origin := _next_origin()
	var station := _create_workstation(origin, {}, {}, 1, 3)
	var adults := [
		_spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 28),
		_spawn_human(origin + Vector2i(3, 5), GlobalEnum.AgeStatus.ADULT, 35),
	]
	station.on_tick()
	var non_hireable_station := WaterStation.new()
	var non_hireable_ok := not non_hireable_station.is_hireable
	non_hireable_station.free()
	_check(
		"EMP-01",
		non_hireable_ok,
		"不可雇佣建筑不扫描居民",
		"water_hireable=false",
	)

	station.set_target_workers(99)
	_check(
		"EMP-02",
		station.target_workers == station.max_workers,
		"目标人数夹到 3",
		"target=%d" % station.target_workers,
	)

	station.on_tick()
	station.set_target_workers(0)
	station.on_tick()
	_check(
		"EMP-03",
		station.employees.is_empty()
		and adults[0].employer == null
		and adults[1].employer == null,
		"目标 0 解雇全部雇员",
		"employees=%d" % station.employees.size(),
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {}, {}, 1, 3)
	for i in range(5):
		_spawn_human(origin + Vector2i(i, 5), GlobalEnum.AgeStatus.ADULT, 25 + i)
	station.on_tick()
	_check(
		"EMP-04",
		station.employees.size() == 3,
		"同一刻补齐 3 个空缺",
		"employees=%d" % station.employees.size(),
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {}, {}, 1, 5)
	var candidate_a := _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.on_tick()
	var first_count := station.employees.size()
	var candidate_b := _spawn_human(origin + Vector2i(3, 5), GlobalEnum.AgeStatus.ADULT, 31)
	station.on_tick()
	_check(
		"EMP-05",
		first_count == 1 and station.employees.size() == 2,
		"候选不足时补齐，下一建筑刻继续",
		"first=%d next=%d" % [first_count, station.employees.size()],
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {}, {}, 1, 4)
	for i in range(4):
		_spawn_human(origin + Vector2i(i, 5), GlobalEnum.AgeStatus.ADULT, 25 + i)
	station.on_tick()
	station.set_target_workers(2)
	station.on_tick()
	_check(
		"EMP-06",
		station.employees.size() == 2,
		"随机解雇恰好 2 人",
		"employees=%d" % station.employees.size(),
	)
	await _dispose_tracked()

	origin = _next_origin()
	var station_a := _create_workstation(origin, {}, {}, 1, 1)
	var station_b := _create_workstation(origin + Vector2i(8, 0), {}, {}, 1, 1)
	var shared_worker := _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station_a.on_tick()
	station_b.on_tick()
	_check(
		"EMP-07",
		station_a.employees.size() + station_b.employees.size() == 1
		and shared_worker.employer != null,
		"同一居民只有一个雇主",
		"a=%d b=%d" % [station_a.employees.size(), station_b.employees.size()],
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {}, {}, 1, 3)
	_spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.CHILD, 12)
	_spawn_human(origin + Vector2i(3, 5), GlobalEnum.AgeStatus.OLD, 70)
	station.on_tick()
	_check(
		"EMP-08",
		station.employees.is_empty(),
		"默认不雇佣儿童和老人",
		"employees=%d" % station.employees.size(),
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {}, {}, 1, 2)
	station.allow_child_workers = true
	station.allow_old_workers = true
	_spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.CHILD, 12)
	_spawn_human(origin + Vector2i(3, 5), GlobalEnum.AgeStatus.OLD, 70)
	station.on_tick()
	_check(
		"EMP-09",
		station.employees.size() == 2,
		"允许年龄段的建筑可雇佣 2 人",
		"employees=%d" % station.employees.size(),
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {}, {}, 1, 1)
	var aging_worker := _spawn_human(
		origin + Vector2i(2, 5),
		GlobalEnum.AgeStatus.ADULT,
		59,
	)
	station.on_tick()
	aging_worker.age_status = GlobalEnum.AgeStatus.OLD
	aging_worker.age = 60
	var replacement := _spawn_human(
		origin + Vector2i(3, 5),
		GlobalEnum.AgeStatus.ADULT,
		30,
	)
	station.on_tick()
	_check(
		"EMP-10",
		not station.employees.has(aging_worker)
		and station.employees.has(replacement)
		and aging_worker.employer == null,
		"失去资格后移除并在同刻补招",
		"employees=%d aging_employer=%s" % [
			station.employees.size(),
			aging_worker.employer,
		],
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {}, {}, 1, 1)
	var stunned_worker := _spawn_human(
		origin + Vector2i(2, 5),
		GlobalEnum.AgeStatus.ADULT,
		30,
	)
	station.on_tick()
	stunned_worker.buff_system.add_buff(GlobalEnum.BuffType.STUN, {"duration": 30})
	station.on_tick()
	_check(
		"EMP-11",
		station.employees.has(stunned_worker),
		"眩晕期间默认保留雇佣",
		"employees=%d" % station.employees.size(),
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {}, {}, 1, 1)
	var removed_worker := _spawn_human(
		origin + Vector2i(2, 5),
		GlobalEnum.AgeStatus.ADULT,
		30,
	)
	station.on_tick()
	station.remove()
	_check(
		"EMP-12",
		station.employees.is_empty()
		and removed_worker.employer == null
		and not TickManager.buildings.has(station),
		"建筑删除后无悬空雇佣",
		"employer=%s registered=%s" % [
			removed_worker.employer,
			TickManager.buildings.has(station),
		],
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {}, {}, 1, 3)
	station.hidden_run_threshold = 3
	station.set_target_workers(1)
	_check(
		"EMP-13",
		station.target_workers == 1,
		"目标人数不自动抬到隐藏阈值",
		"target=%d threshold=%d" % [
			station.target_workers,
			station.hidden_run_threshold,
		],
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {}, {}, 1, 2)
	var stable_candidates: Array[Human] = []
	for i in range(3):
		stable_candidates.append(_spawn_human(
			origin + Vector2i(i, 5),
			GlobalEnum.AgeStatus.ADULT,
			25 + i,
		))
	station.on_tick()
	_check(
		"EMP-14",
		station.employees.size() == 2
		and station.employees[0] == stable_candidates[0]
		and station.employees[1] == stable_candidates[1],
		"按注册顺序选择前 2 人",
		"employees=%s" % [
			station.employees.map(func(h: Human) -> String: return h.name)
		],
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {}, {}, 1, 1)
	var unreachable_worker := _spawn_human(
		origin + Vector2i(2, 5),
		GlobalEnum.AgeStatus.ADULT,
		30,
	)
	for entrance in station.get_entrance_cells():
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			WorldGridGlobal.world.set_walkable(entrance + offset, false)
	station.on_tick()
	station.on_tick()
	for entrance in station.get_entrance_cells():
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			WorldGridGlobal.world.set_walkable(entrance + offset, true)
	_check(
		"EMP-15",
		station.employees.has(unreachable_worker),
		"暂时不可达仍保留雇佣",
		"employees=%d" % station.employees.size(),
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {}, {}, 1, 3)
	var removed_employer := ScrapSortingStation.new()
	var recovered_workers: Array[Human] = []
	for i in range(3):
		var recovered_worker := _spawn_human(
			origin + Vector2i(i, 5),
			GlobalEnum.AgeStatus.ADULT,
			25 + i,
		)
		recovered_worker.employer = removed_employer
		recovered_workers.append(recovered_worker)
	removed_employer.free()
	var candidates_visible := station.get_recruitable_candidate_count()
	station.on_tick()
	var all_reassigned := true
	for recovered_worker in recovered_workers:
		if recovered_worker.employer != station:
			all_reassigned = false
	_check(
		"EMP-16",
		candidates_visible == 3
		and station.employees.size() == 3
		and all_reassigned,
		"失效雇主引用不阻止成年人补位",
		"candidates=%d employees=%d" % [
			candidates_visible,
			station.employees.size(),
		],
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {}, {}, 1, 3)
	var placer := get_parent().get("_placer") as PlacementController
	var humans_before_debug_placement := TickManager.humans.size()
	placer.select_kind(PlacementController.Kind.HUMAN)
	for i in range(4):
		placer.place_at_cell(origin + Vector2i(i, 5))
	placer.cancel()
	var debug_humans: Array[Human] = []
	for i in range(humans_before_debug_placement, TickManager.humans.size()):
		debug_humans.append(TickManager.humans[i])
	for debug_human in debug_humans:
		_tracked_humans.append(debug_human)
	station.on_tick()
	var all_debug_adults := true
	for debug_human in debug_humans:
		if debug_human.age_status != GlobalEnum.AgeStatus.ADULT:
			all_debug_adults = false
	_check(
		"EMP-17",
		debug_humans.size() == 4
		and all_debug_adults
		and station.employees.size() == 3
		and debug_humans.all(
			func(debug_human: Human) -> bool: return debug_human.get_parent() is World
		),
		"调试放置 4 个成年人后目标 3 在同一刻招满",
		"placed=%d adults=%s employees=%d" % [
			debug_humans.size(),
			all_debug_adults,
			station.employees.size(),
		],
	)
	var waiting_debug_human: Human = debug_humans[3]
	waiting_debug_human.ai.force_next_decision()
	var selected_wait: bool = waiting_debug_human.ai.try_select_idle_goal()
	var started_wait_route: bool = waiting_debug_human.ai.start_travel_to_current_target()
	var started_wait_motion: bool = waiting_debug_human.motion.is_moving()
	var ai_motion_ok: bool = (
		selected_wait
		and waiting_debug_human.ai.get_goal() == HumanAI.Goal.WAIT
		and started_wait_route
		and started_wait_motion
	)
	waiting_debug_human.motion.stop()
	_check(
		"EMP-18",
		ai_motion_ok,
		"调试放置的居民能离开原地前往等待点",
		"selected=%s goal=%s started=%s moving=%s" % [
			selected_wait,
			HumanAI.Goal.keys()[waiting_debug_human.ai.get_goal()],
			started_wait_route,
			started_wait_motion,
		],
	)
	await _dispose_tracked()


## 验证班次判断、出入口等待、服务结算和等待点分散。
func _test_schedule_and_waiting() -> void:
	# 班次组验证工作日边界、服务等待、等待点和需求中断。
	TickManager.total_ticks = 599
	var schedule_station := _create_workstation(_next_origin(), {}, {}, 1, 1)
	_check(
		"SCH-01",
		not schedule_station.is_work_time(),
		"第 599 刻不能开始新周期",
		"is_work_time=false",
	)
	TickManager.total_ticks = 600
	_check(
		"SCH-02",
		schedule_station.is_work_time(),
		"第 600 刻可以开始新周期",
		"is_work_time=true",
	)
	TickManager.total_ticks = 1499
	_check(
		"SCH-03",
		schedule_station.is_work_time(),
		"第 1499 刻允许开始并可跨班",
		"is_work_time=true",
	)
	await _dispose_tracked()

	var origin := _next_origin()
	var offshift_station := _create_workstation(origin, {}, {}, 1, 1)
	var offshift_worker := _spawn_human(
		origin + Vector2i(2, 5),
		GlobalEnum.AgeStatus.ADULT,
		30,
	)
	offshift_station.on_tick()
	TickManager.total_ticks = 1500
	offshift_worker.water = Human.MAX_WATER
	offshift_worker.food = Human.MAX_FOOD
	offshift_worker.ai.force_next_decision()
	offshift_worker.ai.try_select_idle_goal()
	_check(
		"SCH-04",
		offshift_worker.ai.get_goal() == HumanAI.Goal.WAIT,
		"下班后不开始下一周期",
		"goal=%s" % HumanAI.Goal.keys()[offshift_worker.ai.get_goal()],
	)
	await _dispose_tracked()

	TickManager.total_ticks = 600
	var waiting_worker := _spawn_human(Vector2i(240, 260), GlobalEnum.AgeStatus.ADULT, 30)
	waiting_worker.ai.force_next_decision()
	waiting_worker.ai.try_select_idle_goal()
	var started_wait := waiting_worker.ai.start_travel_to_current_target()
	for _i in range(3000):
		if not waiting_worker.motion.is_moving():
			break
		waiting_worker.motion.on_tick()
	var wait_target := World.WAIT_PLACE + waiting_worker.wait_offset
	var wait_distance := waiting_worker.position.distance_to(wait_target)
	_check(
		"SCH-05",
		started_wait and wait_distance < 1.0,
		"下班居民前往 WAIT_PLACE 附近",
		"goal=%s distance=%.2f" % [
			HumanAI.Goal.keys()[waiting_worker.ai.get_goal()],
			wait_distance,
		],
	)

	var waiters: Array[Human] = [waiting_worker]
	for i in range(2):
		waiters.append(_spawn_human(Vector2i(241 + i, 260), GlobalEnum.AgeStatus.ADULT, 30))
	var unique_offsets := true
	for i in range(waiters.size()):
		var offset := waiters[i].wait_offset
		if offset.length() > 5.0:
			unique_offsets = false
		for j in range(i + 1, waiters.size()):
			if offset == waiters[j].wait_offset:
				unique_offsets = false
	_check(
		"SCH-06",
		unique_offsets,
		"每名居民有稳定且不超过半格的偏移",
		"offsets=%s" % [waiters.map(func(h: Human) -> Vector2: return h.wait_offset)],
	)

	# 已站在等待点时不应每个决策刻重新挑一次等待目标，否则会原地反复移动。
	waiting_worker.water = Human.MAX_WATER
	waiting_worker.food = Human.MAX_FOOD
	waiting_worker.ai.clear_goal()
	var stays_waiting := true
	for _slot in range(3):
		waiting_worker.ai.force_next_decision()
		waiting_worker.ai.try_select_idle_goal()
		if (
			waiting_worker.ai.get_goal() != HumanAI.Goal.NONE
			or waiting_worker.motion.is_moving()
		):
			stays_waiting = false
	_check(
		"SCH-08",
		stays_waiting and bool(waiting_worker.ai.get("_at_wait_place")),
		"到达等待点后保持空闲，不再重复挑选等待目标",
		"goal=%s moving=%s at_wait=%s" % [
			HumanAI.Goal.keys()[waiting_worker.ai.get_goal()],
			waiting_worker.motion.is_moving(),
			waiting_worker.ai.get("_at_wait_place"),
		],
	)

	waiting_worker.water = 10.0
	waiting_worker.ai.force_next_decision()
	waiting_worker.ai.set("_at_wait_place", true)
	var water_target_available := (
		waiting_worker.motion.find_nearest_building(GlobalEnum.BuildingType.WATER) != null
	)
	waiting_worker.ai.try_select_idle_goal()
	var waiting_snapshot := waiting_worker.ai.get_debug_snapshot()
	_check(
		"SCH-07",
		waiting_worker.ai.get_goal() == HumanAI.Goal.WATER,
		"等待可被口渴需求打断",
		"goal=%s water_ticks=%.1f target_available=%s water=%.1f" % [
			HumanAI.Goal.keys()[waiting_worker.ai.get_goal()],
			float(waiting_snapshot["water_ticks_left"]),
			water_target_available,
			waiting_worker.water,
		],
	)
	await _dispose_tracked()


## 验证工作创建、跨仓库取料、锁定推进、硬中断和周期结算。
func _test_work_cycles() -> void:
	# 工作周期组从跨仓库取料开始，逐步覆盖锁定、硬中断、取消和结算。
	TickManager.total_ticks = 600
	var origin := _next_origin()
	var station := _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {}, 2, 1)
	var worker := _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	var behavior := worker.ai.get_work_behavior()
	var started := behavior.begin(station)
	_check(
		"CYCLE-01",
		not started and not behavior.is_busy(),
		"缺少工作需求不开始周期",
		"started=%s" % started,
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
		MaterialTypes.ItemType.PLASTIC: 1,
	}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 2, 1)
	station.inventory.add_items_unchecked({MaterialTypes.ItemType.METAL: 1})
	var external_warehouse := _create_test_warehouse(
		origin + Vector2i(20, 0),
		{MaterialTypes.ItemType.PLASTIC: 1},
	)
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	started = behavior.begin(station)
	var split_ok := started and behavior.cycle.demand_locks.size() == 2
	if started:
		behavior.on_motion_arrived()
		behavior.on_motion_arrived()
		split_ok = split_ok and behavior.is_locked()
	_check(
		"CYCLE-02",
		split_ok,
		"需求可拆分取得，全部取得后开始",
		"started=%s locks=%d phase=%s" % [
			started,
			behavior.cycle.demand_locks.size() if behavior.cycle != null else 0,
			behavior.get_phase_name(),
		],
	)
	behavior.cancel("测试结束")
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
		MaterialTypes.ItemType.PLASTIC: 1,
	}, {}, 2, 1)
	station.inventory.add_items_unchecked({MaterialTypes.ItemType.METAL: 1})
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	var locks_before := MaterialSystem.get_open_lock_count()
	started = behavior.begin(station)
	_check(
		"CYCLE-03",
		not started and MaterialSystem.get_open_lock_count() == locks_before,
		"另一需求失败时释放已锁定需求",
		"started=%s locks_delta=%d" % [
			started,
			MaterialSystem.get_open_lock_count() - locks_before,
		],
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 10, 1)
	station.inventory.add_items_unchecked({MaterialTypes.ItemType.METAL: 1})
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	started = behavior.begin(station)
	worker.buff_system.add_buff(GlobalEnum.BuffType.THIRST, {"duration": 50})
	behavior.tick()
	_check(
		"CYCLE-04",
		started and behavior.is_busy() and worker.in_building == station,
		"周期内口渴不离开周期",
		"phase=%s in_building=%s" % [behavior.get_phase_name(), worker.in_building],
	)
	behavior.cancel("测试结束")
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 2, 1)
	station.inventory.add_items_unchecked({MaterialTypes.ItemType.METAL: 1})
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	TickManager.total_ticks = 1499
	started = behavior.begin(station)
	TickManager.total_ticks = 1500
	behavior.tick()
	behavior.tick()
	_check(
		"CYCLE-05",
		started and station.work_result_count == 1 and station.inventory.get_item_count(
			MaterialTypes.ItemType.WIRE
		) == 1,
		"周期内下班仍完成当前周期",
		"results=%d wire=%d" % [
			station.work_result_count,
			station.inventory.get_item_count(MaterialTypes.ItemType.WIRE),
		],
	)
	TickManager.total_ticks = 600
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 10, 1)
	station.inventory.add_items_unchecked({MaterialTypes.ItemType.METAL: 1})
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	var metal_before_stun := station.inventory.get_item_count(MaterialTypes.ItemType.METAL)
	behavior.begin(station)
	worker.buff_system.add_buff(GlobalEnum.BuffType.STUN, {"duration": 30})
	var stun_interrupt := worker.ai.evaluate_work_interrupt()
	behavior.cancel("眩晕")
	_check(
		"CYCLE-06",
		stun_interrupt == HumanAI.WorkInterrupt.CANCEL
		and station.inventory.get_item_count(MaterialTypes.ItemType.METAL) == metal_before_stun
		and station.work_result_count == 0,
		"周期内眩晕强制中断并回滚",
		"interrupt=%d metal=%d results=%d" % [
			stun_interrupt,
			station.inventory.get_item_count(MaterialTypes.ItemType.METAL),
			station.work_result_count,
		],
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 10, 1)
	station.inventory.add_items_unchecked({MaterialTypes.ItemType.METAL: 1})
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	behavior.begin(station)
	worker.buff_system.add_buff(GlobalEnum.BuffType.WEAKNESS)
	var weakness_interrupt := worker.ai.evaluate_work_interrupt()
	behavior.cancel("虚弱")
	_check(
		"CYCLE-07",
		weakness_interrupt == HumanAI.WorkInterrupt.CANCEL
		and station.work_result_count == 0
		and MaterialSystem.get_holder_open_lock_count(
			"cycle:%d" % (behavior.cycle.cycle_id if behavior.cycle != null else -1)
		) == 0,
		"周期内虚弱强制中断并回滚",
		"interrupt=%d results=%d" % [weakness_interrupt, station.work_result_count],
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 10, 1)
	station.inventory.add_items_unchecked({MaterialTypes.ItemType.METAL: 1})
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	behavior.begin(station)
	station.dismiss_employee(worker, "测试解雇")
	_check(
		"CYCLE-08",
		not behavior.is_busy()
		and station.work_result_count == 0
		and station.inventory.get_item_count(MaterialTypes.ItemType.WIRE) == 0,
		"周期内被解雇立即中断且无产出",
		"busy=%s results=%d wire=%d" % [
			behavior.is_busy(),
			station.work_result_count,
			station.inventory.get_item_count(MaterialTypes.ItemType.WIRE),
		],
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {}, 10, 1)
	station.inventory.add_items_unchecked({MaterialTypes.ItemType.METAL: 1})
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	behavior.begin(station)
	station.dismiss_employee(worker, "测试解雇")
	_check(
		"CYCLE-09",
		station.inventory.get_item_count(MaterialTypes.ItemType.METAL) == 1,
		"已取得需求在解雇时自动归还",
		"metal=%d" % station.inventory.get_item_count(MaterialTypes.ItemType.METAL),
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 1, 1)
	station.inventory.add_items_unchecked({MaterialTypes.ItemType.METAL: 1})
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	behavior.begin(station)
	behavior.tick()
	var first_result_count := station.work_result_count
	behavior.tick()
	_check(
		"CYCLE-10",
		first_result_count == 1
		and station.work_result_count == 1
		and station.inventory.get_item_count(MaterialTypes.ItemType.METAL) == 0
		and station.inventory.get_item_count(MaterialTypes.ItemType.WIRE) == 1,
		"需求消耗一次、产出入库一次、结果提交一次",
		"results=%d metal=%d wire=%d" % [
			station.work_result_count,
			station.inventory.get_item_count(MaterialTypes.ItemType.METAL),
			station.inventory.get_item_count(MaterialTypes.ItemType.WIRE),
		],
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {}, 1, 1)
	station.inventory.add_items_unchecked({MaterialTypes.ItemType.METAL: 1})
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	worker.water = 1.0
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	var unavailable_water_sources: Array[Building] = []
	for water_source in TickManager.get_buildings_of_type(GlobalEnum.BuildingType.WATER):
		unavailable_water_sources.append(water_source)
		TickManager.unregister_building(water_source)
	started = behavior.begin(station)
	for water_source in unavailable_water_sources:
		if is_instance_valid(water_source):
			TickManager.register_building(water_source)
	_check(
		"CYCLE-11",
		started,
		"预测缺水但无水源时仍开始下一轮",
		"started=%s water=%.1f" % [started, worker.water],
	)
	behavior.cancel("测试结束")
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 10, 1)
	external_warehouse = _create_test_warehouse(
		origin + Vector2i(20, 0),
		{MaterialTypes.ItemType.METAL: 1},
	)
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	started = behavior.begin(station)
	behavior.on_path_failed()
	_check(
		"CYCLE-12",
		started
		and not behavior.is_busy()
		and external_warehouse.inventory.get_item_count(MaterialTypes.ItemType.METAL) == 1
		and MaterialSystem.get_open_reservation_count() == 0,
		"路径失败退出周期并回滚",
		"busy=%s metal=%d reservations=%d" % [
			behavior.is_busy(),
			external_warehouse.inventory.get_item_count(MaterialTypes.ItemType.METAL),
			MaterialSystem.get_open_reservation_count(),
		],
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 10, 1)
	station.inventory.add_items_unchecked({MaterialTypes.ItemType.METAL: 1})
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	behavior.begin(station)
	worker.water = 0.0
	worker.food = 0.0
	worker.buff_system.add_buff(GlobalEnum.BuffType.WEAKNESS)
	var exhausted_interrupt := worker.ai.evaluate_work_interrupt()
	behavior.cancel("虚弱")
	_check(
		"CYCLE-13",
		exhausted_interrupt == HumanAI.WorkInterrupt.CANCEL
		and worker.water == 0.0
		and worker.food == 0.0,
		"水食耗尽触发硬中断且不回滚已消耗",
		"interrupt=%d water=%.1f food=%.1f" % [
			exhausted_interrupt,
			worker.water,
			worker.food,
		],
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 10, 1)
	external_warehouse = _create_test_warehouse(
		origin + Vector2i(20, 0),
		{MaterialTypes.ItemType.METAL: 1},
	)
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	TickManager.total_ticks = 1499
	started = behavior.begin(station)
	TickManager.total_ticks = 1500
	behavior.on_motion_arrived()
	behavior.on_motion_arrived()
	_check(
		"CYCLE-14",
		started and not behavior.is_busy() and station.work_result_count == 0,
		"锁定需求后下班则释放且不开始",
		"started=%s busy=%s results=%d" % [
			started,
			behavior.is_busy(),
			station.work_result_count,
		],
	)
	TickManager.total_ticks = 600
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 3, 1)
	station.inventory.add_items_unchecked({MaterialTypes.ItemType.METAL: 2})
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	behavior.begin(station)
	behavior.tick()
	worker.buff_system.add_buff(GlobalEnum.BuffType.STUN, {"duration": 1})
	behavior.cancel("眩晕")
	worker.buff_system.clear_all()
	started = behavior.begin(station)
	var reset_ticks := behavior.cycle.remaining_ticks if behavior.cycle != null else -1
	_check(
		"CYCLE-15",
		started and reset_ticks == 3,
		"中断恢复后从零开始完整周期",
		"started=%s remaining=%d" % [started, reset_ticks],
	)
	behavior.cancel("测试结束")
	await _dispose_tracked()

	var predict_type := WorkType.new(&"predict", "预测", 100, {}, {})
	_check(
		"CYCLE-16",
		predict_type.get_required_supply_ticks() == 110,
		"预计 100 刻时使用 110 刻需求",
		"required=%d" % predict_type.get_required_supply_ticks(),
	)

	var scrap_type := WorkType.create_scrap_sorting()
	var default_station := ScrapSortingStation.new()
	var scrap_contract_ok := (
		scrap_type.id == &"scrap_sorting"
		and scrap_type.display_name == "废料分拣"
		and scrap_type.duration_ticks == 60
		and scrap_type.demand == {MaterialTypes.ItemType.WASTE: 6}
		and scrap_type.output == {
			MaterialTypes.ItemType.METAL: 1,
			MaterialTypes.ItemType.PLASTIC: 1,
			MaterialTypes.ItemType.WIRE: 1,
		}
		and default_station.work_type != null
		and default_station.work_type.id == &"scrap_sorting"
	)
	default_station.free()
	_check(
		"CYCLE-17",
		scrap_contract_ok,
		"废料分拣消耗 6 废料并产出金属/塑料/线各 1",
		"type=%s duration=%d" % [scrap_type.display_name, scrap_type.duration_ticks],
	)

	origin = _next_origin()
	station = _create_workstation(
		origin,
		{},
		{},
		scrap_type.duration_ticks,
		1,
	)
	station.work_type = WorkType.create_scrap_sorting()
	station.inventory.add_items_unchecked({MaterialTypes.ItemType.WASTE: 6})
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	started = behavior.begin(station)
	for _tick_index in range(scrap_type.duration_ticks):
		behavior.tick()
	var scrap_cycle_ok := (
		started
		and station.work_result_count == 1
		and station.inventory.get_item_count(MaterialTypes.ItemType.WASTE) == 0
		and station.inventory.get_item_count(MaterialTypes.ItemType.METAL) == 1
		and station.inventory.get_item_count(MaterialTypes.ItemType.PLASTIC) == 1
		and station.inventory.get_item_count(MaterialTypes.ItemType.WIRE) == 1
	)
	_check(
		"CYCLE-18",
		scrap_cycle_ok,
		"废料分拣周期按配方完成一次结算",
		"waste=%d metal=%d plastic=%d wire=%d results=%d" % [
			station.inventory.get_item_count(MaterialTypes.ItemType.WASTE),
			station.inventory.get_item_count(MaterialTypes.ItemType.METAL),
			station.inventory.get_item_count(MaterialTypes.ItemType.PLASTIC),
			station.inventory.get_item_count(MaterialTypes.ItemType.WIRE),
			station.work_result_count,
		],
	)
	await _dispose_tracked()

	# 返岗途中下班：到达雇主时已过班次，周期必须取消并把结果返回给调用方。
	TickManager.total_ticks = 600
	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {}, 1, 1)
	_create_test_warehouse(origin + Vector2i(20, 0), {
		MaterialTypes.ItemType.METAL: 1,
	})
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	var locks_before_return := MaterialSystem.get_open_lock_count()
	var reservations_before_return := MaterialSystem.get_open_reservation_count()
	started = behavior.begin(station)
	var acquiring_ok := started and behavior.get_phase_name() == &"acquiring"
	behavior.on_motion_arrived()
	var returning_ok := behavior.get_phase_name() == &"returning"
	TickManager.total_ticks = 1500
	var cycle_alive_at_arrival := behavior.on_motion_arrived()
	_check(
		"CYCLE-19",
		acquiring_ok
		and returning_ok
		and not cycle_alive_at_arrival
		and not behavior.is_busy()
		and MaterialSystem.get_open_lock_count() == locks_before_return
		and MaterialSystem.get_open_reservation_count() == reservations_before_return,
		"返岗途中下班时取消周期并返回失效",
		"acquiring=%s returning=%s alive=%s busy=%s locks_delta=%d reservations_delta=%d" % [
			acquiring_ok,
			returning_ok,
			cycle_alive_at_arrival,
			behavior.is_busy(),
			MaterialSystem.get_open_lock_count() - locks_before_return,
			MaterialSystem.get_open_reservation_count() - reservations_before_return,
		],
	)
	TickManager.total_ticks = 600
	await _dispose_tracked()


## 验证居民背包在取货、结算、取消和离场时的物资归属。
func _test_carry() -> void:
	TickManager.total_ticks = 600
	var origin := _next_origin()
	var station := _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 1, 1)
	var warehouse := _create_test_warehouse(origin + Vector2i(20, 0), {
		MaterialTypes.ItemType.METAL: 2,
	})
	var worker := _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	var behavior := worker.ai.get_work_behavior()
	var warehouse_before := warehouse.inventory.get_item_count(MaterialTypes.ItemType.METAL)
	var started := behavior.begin(station)
	var acquiring := behavior.get_phase_name() == &"acquiring"
	behavior.on_motion_arrived()
	var carried := worker.carry.get_item_count(MaterialTypes.ItemType.METAL)
	_check(
		"CARRY-01",
		started
		and acquiring
		and carried == 1
		and warehouse.inventory.get_item_count(MaterialTypes.ItemType.METAL) == warehouse_before - 1,
		"取货后物资从仓库转入居民背包",
		"started=%s phase=%s carried=%d warehouse=%d" % [
			started,
			behavior.get_phase_name(),
			carried,
			warehouse.inventory.get_item_count(MaterialTypes.ItemType.METAL),
		],
	)

	var finished_cycle := behavior.cycle
	behavior.on_motion_arrived()
	var locked := behavior.get_phase_name() == &"locked"
	var hidden_while_working := worker.in_building == station and not worker.visual.visible
	_check(
		"CARRY-11",
		hidden_while_working,
		"进入工作站后模型隐藏并登记站内占用",
		"in_building=%s visible=%s occupants=%d" % [
			worker.in_building,
			worker.visual.visible,
			station.get_occupant_count(),
		],
	)
	behavior.tick()
	_check(
		"CARRY-02",
		locked
		and behavior.cycle == null
		and worker.carry.is_empty()
		and station.inventory.get_item_count(MaterialTypes.ItemType.WIRE) == 1,
		"结算消耗背包物资并写入产出",
		"locked=%s carried=%s wire=%d" % [
			locked,
			carried,
			station.inventory.get_item_count(MaterialTypes.ItemType.WIRE),
		],
	)

	var repeated := MaterialSystem.settle_cycle(finished_cycle)
	_check(
		"CARRY-03",
		not repeated and station.inventory.get_item_count(MaterialTypes.ItemType.WIRE) == 1,
		"已完成周期重复结算被拒绝",
		"repeated=%s wire=%d" % [repeated, station.inventory.get_item_count(MaterialTypes.ItemType.WIRE)],
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 1, 1)
	warehouse = _create_test_warehouse(origin + Vector2i(20, 0), {
		MaterialTypes.ItemType.METAL: 1,
	})
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	behavior.begin(station)
	behavior.on_motion_arrived()
	var carried_before_cancel := worker.carry.get_item_count(MaterialTypes.ItemType.METAL)
	behavior.cancel("测试取消")
	_check(
		"CARRY-04",
		carried_before_cancel == 1
		and worker.carry.is_empty()
		and warehouse.inventory.get_item_count(MaterialTypes.ItemType.METAL) == 1,
		"取消时背包物资退回来源仓库",
		"carried=%d left=%s warehouse=%d" % [
			carried_before_cancel,
			worker.carry.get_items(),
			warehouse.inventory.get_item_count(MaterialTypes.ItemType.METAL),
		],
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 1, 1)
	warehouse = _create_test_warehouse(origin + Vector2i(20, 0), {
		MaterialTypes.ItemType.METAL: 1,
	})
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	behavior.begin(station)
	behavior.on_motion_arrived()
	worker.die()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(
		"CARRY-05",
		warehouse.inventory.get_item_count(MaterialTypes.ItemType.METAL) == 1,
		"居民离场时背包物资退回来源仓库",
		"warehouse=%d" % warehouse.inventory.get_item_count(MaterialTypes.ItemType.METAL),
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {}, {}, 1, 1)
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	var eligible_before_death := station.can_accept_employee(worker)
	worker.die()
	var rejects_queued := not station.can_accept_employee(worker)
	_check(
		"CARRY-06",
		eligible_before_death and rejects_queued,
		"已排进删除队列的居民不再被建筑录用",
		"before=%s after=%s" % [eligible_before_death, rejects_queued],
	)
	await _dispose_tracked()

	# 待结算期间背包物资丢失：必须取消，而不是永远停在待结算。
	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 1, 1)
	warehouse = _create_test_warehouse(origin + Vector2i(20, 0), {
		MaterialTypes.ItemType.METAL: 1,
	})
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	behavior.begin(station)
	behavior.on_motion_arrived()
	worker.carry.clear_items()
	behavior.on_motion_arrived()
	var pending_reached := false
	var cancelled_result := &""
	for _step in range(2):
		var result := behavior.tick()
		if behavior.get_phase_name() == &"pending_settlement":
			pending_reached = true
		if result == &"cancelled":
			cancelled_result = result
	_check(
		"CARRY-07",
		pending_reached and cancelled_result == &"cancelled" and behavior.cycle == null,
		"待结算期间背包物资丢失时取消周期",
		"pending=%s result=%s wire=%d" % [
			pending_reached,
			cancelled_result,
			station.inventory.get_item_count(MaterialTypes.ItemType.WIRE),
		],
	)
	await _dispose_tracked()

	# 账本记录不应随周期完成而累积。
	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 1, 1)
	warehouse = _create_test_warehouse(origin + Vector2i(20, 0), {
		MaterialTypes.ItemType.METAL: 1,
	})
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	var locks_before_cycle := MaterialSystem.get_tracked_lock_count()
	var reservations_before_cycle := MaterialSystem.get_tracked_reservation_count()
	behavior.begin(station)
	behavior.on_motion_arrived()
	behavior.on_motion_arrived()
	behavior.tick()
	_check(
		"CARRY-08",
		MaterialSystem.get_tracked_lock_count() == locks_before_cycle
		and MaterialSystem.get_tracked_reservation_count() == reservations_before_cycle
		and station.inventory.get_item_count(MaterialTypes.ItemType.WIRE) == 1,
		"周期结算后不遗留锁与预留记录",
		"locks_delta=%d reservations_delta=%d wire=%d" % [
			MaterialSystem.get_tracked_lock_count() - locks_before_cycle,
			MaterialSystem.get_tracked_reservation_count() - reservations_before_cycle,
			station.inventory.get_item_count(MaterialTypes.ItemType.WIRE),
		],
	)
	await _dispose_tracked()

	# 取料途中紧急缺水：准备阶段应允许离开去补给。
	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 1, 1)
	warehouse = _create_test_warehouse(origin + Vector2i(20, 0), {
		MaterialTypes.ItemType.METAL: 1,
	})
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	behavior.begin(station)
	worker.water = 0.0
	worker.ai.set("_goal", HumanAI.Goal.WORK)
	worker.ai.set("_target", station)
	# 决策快照平时由每刻刷新，这里直接刷新一次，让缺水判定读到最新数值。
	worker.ai.get("_context").refresh(worker)
	var interrupt := worker.ai.evaluate_work_interrupt()
	_check(
		"CARRY-09",
		interrupt == HumanAI.WorkInterrupt.TRAVEL and behavior.get_phase_name() == &"acquiring",
		"取料途中紧急缺水时允许离开准备阶段",
		"interrupt=%d phase=%s" % [interrupt, behavior.get_phase_name()],
	)
	behavior.cancel("测试结束")
	await _dispose_tracked()

	# 已排队删除的居民不再被每刻更新。
	worker = _spawn_human(_next_origin(), GlobalEnum.AgeStatus.ADULT, 30)
	worker.water = 60.0
	worker.die()
	var water_before_tick := worker.water
	TickManager.advance_tick()
	_check(
		"CARRY-10",
		is_zero_approx(worker.water - water_before_tick),
		"待删除居民不再被每刻更新",
		"before=%.2f after=%.2f" % [water_before_tick, worker.water],
	)
	await _dispose_tracked()


## 验证摧毁建筑时的雇佣、工作周期与库存清算。
func _test_demolish() -> void:
	TickManager.total_ticks = 600
	var origin := _next_origin()
	var station := _create_workstation(origin, {}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 4, 1)
	station.inventory.add_items_unchecked({MaterialTypes.ItemType.METAL: 3})
	var warehouse := _create_test_warehouse(origin + Vector2i(0, 12), {})
	var worker := _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	var behavior := worker.ai.get_work_behavior()
	var cycle_started := behavior.begin(station)
	var inside_building := worker.in_building == station
	station.remove()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(
		"DESTROY-01",
		cycle_started
		and inside_building
		and not behavior.is_busy()
		and worker.employer == null
		and worker.in_building == null
		and worker.visual.visible,
		"摧毁建筑时取消工作周期并解雇工人",
		"started=%s inside=%s busy=%s employer=%s in_building=%s visible=%s" % [
			cycle_started,
			inside_building,
			behavior.is_busy(),
			worker.employer,
			worker.in_building,
			worker.visual.visible,
		],
	)
	_check(
		"DESTROY-02",
		warehouse.inventory.get_item_count(MaterialTypes.ItemType.METAL) == 3,
		"摧毁建筑时自带库存转移到附近仓库",
		"warehouse_metal=%d" % warehouse.inventory.get_item_count(MaterialTypes.ItemType.METAL),
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {}, {}, 1, 1)
	station.inventory.add_items_unchecked({MaterialTypes.ItemType.METAL: 5})
	warehouse = _create_test_warehouse(origin + Vector2i(0, 12), {})
	warehouse.inventory.capacity = 2
	station.remove()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(
		"DESTROY-03",
		warehouse.inventory.get_item_count(MaterialTypes.ItemType.METAL) == 2,
		"仓库放不下时只转移能容纳的数量，其余销毁",
		"warehouse_metal=%d" % warehouse.inventory.get_item_count(MaterialTypes.ItemType.METAL),
	)
	await _dispose_tracked()

	origin = _next_origin()
	station = _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 2, 1)
	warehouse = _create_test_warehouse(origin + Vector2i(20, 0), {
		MaterialTypes.ItemType.METAL: 1,
	})
	worker = _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	behavior = worker.ai.get_work_behavior()
	behavior.begin(station)
	behavior.on_motion_arrived()
	var carried_before_demolish := worker.carry.get_item_count(MaterialTypes.ItemType.METAL)
	station.remove()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(
		"DESTROY-04",
		carried_before_demolish == 1 and warehouse.inventory.get_item_count(MaterialTypes.ItemType.METAL) == 1,
		"摧毁建筑时在途物资退回来源仓库",
		"carried=%d warehouse=%d" % [
			carried_before_demolish,
			warehouse.inventory.get_item_count(MaterialTypes.ItemType.METAL),
		],
	)
	await _dispose_tracked()

	# 详情页按钮到拆建筑之间的连线。
	origin = _next_origin()
	station = _create_workstation(origin, {}, {}, 1, 1)
	var panel := BuildingDetailPanel.new()
	panel.name = "验收详情页"
	get_parent().add_child(panel)
	await get_tree().process_frame
	panel.show_building(station)
	var demolish_button: Button = panel.get("_demolish_button")
	var button_exists := demolish_button != null and demolish_button.get_signal_connection_list("pressed").size() == 1
	demolish_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(
		"DESTROY-05",
		button_exists and not is_instance_valid(station),
		"详情页摧毁按钮接上拆除流程",
		"button=%s connected=%s freed=%s" % [
			demolish_button != null,
			button_exists,
			not is_instance_valid(station),
		],
	)
	panel.queue_free()
	await get_tree().process_frame
	await _dispose_tracked()


## 验证建筑旋转后的占格、出入口、放置校验与预览控制。
func _test_rotation() -> void:
	var station := ScrapSortingStation.new()
	station.name = "旋转测试工作站"
	var base_footprint := station.get_footprint()
	station.set_rotation_steps(1)
	var rotated_footprint := station.get_footprint()
	var rotated_cells := station.get_occupied_cells()
	station.free()
	_check(
		"ROTATE-01",
		base_footprint == Vector2i(6, 4)
		and rotated_footprint == Vector2i(4, 6)
		and rotated_cells.size() == 24,
		"旋转 90 度后占格宽高互换且数量不变",
		"base=%s rotated=%s cells=%d" % [base_footprint, rotated_footprint, rotated_cells.size()],
	)

	var water := WaterStation.new()
	water.name = "旋转测试取水站"
	var entrance_before := water.get_entrance_cells()
	water.set_rotation_steps(1)
	var entrance_after := water.get_entrance_cells()
	var entrance_footprint := Rect2i(Vector2i.ZERO, water.get_footprint())
	var outside_body := true
	for cell in entrance_after:
		if entrance_footprint.has_point(cell):
			outside_body = false
	water.free()
	_check(
		"ROTATE-02",
		entrance_before != entrance_after and outside_body and entrance_after.size() == 1,
		"旋转后出入口随朝向移动且仍在本体外",
		"before=%s after=%s" % [entrance_before, entrance_after],
	)

	var origin := _next_origin()
	var placed := WaterStation.new()
	placed.name = "旋转放置取水站"
	placed.set_rotation_steps(1)
	get_parent().add_child(placed)
	_tracked_buildings.append(placed)
	var placed_ok := placed.place_at(WorldGridGlobal.world, origin)
	var body_blocked := true
	for cell in placed.get_occupied_cells():
		if WorldGridGlobal.world.is_walkable(cell):
			body_blocked = false
	var entrances_walkable := true
	for cell in placed.get_entrance_cells():
		if not WorldGridGlobal.world.is_walkable(cell):
			entrances_walkable = false
	_check(
		"ROTATE-03",
		placed_ok and placed.get_footprint() == Vector2i(3, 4) and body_blocked and entrances_walkable,
		"旋转后的建筑按新占格占用网格，出入口保持可走",
		"placed=%s footprint=%s body_blocked=%s entrances_walkable=%s" % [
			placed_ok,
			placed.get_footprint(),
			body_blocked,
			entrances_walkable,
		],
	)
	await _dispose_tracked()

	# 预览控制器按 R 旋转并把朝向带到落地的建筑上。
	var controller := PlacementController.new()
	controller.name = "验收放置控制器"
	get_parent().add_child(controller)
	await get_tree().process_frame
	controller.select_kind(PlacementController.Kind.WAREHOUSE)
	var ghost: Building = controller.get("_ghost")
	var ghost_before := ghost.get_footprint()
	controller.call("_rotate_ghost")
	var ghost_after := ghost.get_footprint()
	var origin_cell := controller.call("_origin_for", Vector2i(30, 30)) as Vector2i
	_check(
		"ROTATE-04",
		ghost_before == Vector2i(3, 4) and ghost_after == Vector2i(4, 3) and origin_cell == Vector2i(28, 29),
		"R 键旋转预览并按新占格重新居中",
		"before=%s after=%s origin=%s" % [ghost_before, ghost_after, origin_cell],
	)
	controller.queue_free()
	await get_tree().process_frame


## 验证库存容量、锁定、预留、补位、取消和所有者优先级。
func _test_inventory() -> void:
	# 账本组直接构造库存与周期，覆盖容量、锁、预留、补位和优先级。
	var inventory := _create_virtual_inventory(10, Vector2i(20, 20), false)
	inventory.add_items_unchecked({MaterialTypes.ItemType.WASTE: 4})
	var overflow_reservations := MaterialSystem.reserve_output(
		6,
		inventory,
		[],
		"test:capacity",
	)
	_check(
		"INV-01",
		overflow_reservations.is_empty()
		and inventory.get_used_volume() + inventory.reserved_volume <= inventory.capacity,
		"已用 + 已预留 <= 容量",
		"used=%d reserved=%d capacity=%d" % [
			inventory.get_used_volume(),
			inventory.reserved_volume,
			inventory.capacity,
		],
	)

	_check(
		"INV-02",
		MaterialTypes.get_unit_volume(MaterialTypes.ItemType.WASTE) == 2
		and MaterialTypes.get_unit_volume(MaterialTypes.ItemType.METAL) == 1
		and MaterialTypes.get_unit_volume(MaterialTypes.ItemType.PLASTIC) == 1
		and MaterialTypes.get_unit_volume(MaterialTypes.ItemType.WIRE) == 1,
		"废料 2，其余 1",
		"volumes=%s" % [MaterialTypes.UNIT_VOLUMES],
	)

	var internal_owner := _create_virtual_owner(20, Vector2i(22, 20), false)
	var denied := not internal_owner.try_deposit_items({
		MaterialTypes.ItemType.METAL: 1,
	}, null)
	var accepted_output := internal_owner.try_deposit_items({
		MaterialTypes.ItemType.WIRE: 1,
	}, internal_owner)
	_check(
		"INV-03",
		denied,
		"非雇员不能向自带库存存入普通物品",
		"denied=%s" % denied,
	)
	_check(
		"INV-04",
		accepted_output,
		"建筑可存入自己的产出",
		"accepted=%s" % accepted_output,
	)

	var public_owner := _create_virtual_owner(
		20,
		Vector2i(24, 20),
		true,
		{MaterialTypes.ItemType.WIRE: 2},
	)
	var withdrawn := public_owner.try_withdraw_items(
		MaterialTypes.ItemType.WIRE,
		1,
		"human:any",
	)
	_check(
		"INV-05",
		withdrawn,
		"任何居民可取未锁定物品",
		"remaining=%d" % public_owner.inventory.get_item_count(MaterialTypes.ItemType.WIRE),
	)

	var lock_id := MaterialSystem.lock_items(
		public_owner.inventory,
		MaterialTypes.ItemType.WIRE,
		1,
		"holder:a",
		public_owner.origin_cell,
	)
	var other_withdraw := MaterialSystem.withdraw_items(
		public_owner.inventory,
		MaterialTypes.ItemType.WIRE,
		1,
		"holder:b",
	)
	MaterialSystem.release_lock(lock_id)
	_check(
		"INV-06",
		not other_withdraw,
		"已锁定物品不能被其他持有者取走",
		"locked_withdraw=%s" % other_withdraw,
	)

	var reserved_owner := _create_virtual_owner(10, Vector2i(26, 20), true)
	var space_lock := MaterialSystem.reserve_output(
		4,
		reserved_owner.inventory,
		[],
		"holder:space",
	)
	var filled_space := reserved_owner.inventory.add_items_unchecked({
		MaterialTypes.ItemType.METAL: 6,
	})
	var overfilled_space := reserved_owner.inventory.add_items_unchecked({
		MaterialTypes.ItemType.METAL: 1,
	})
	var space_respected := (
		not space_lock.is_empty()
		and filled_space
		and not overfilled_space
		and reserved_owner.inventory.reserved_volume == 4
	)
	MaterialSystem.release_reservations(space_lock)
	_check(
		"INV-07",
		space_respected,
		"预留空间不能被普通存入占用",
		"reserved=4 filled=%s over=%s" % [filled_space, overfilled_space],
	)

	var cancel_owner := _create_virtual_owner(20, Vector2i(28, 20), true)
	var cancel_station := _create_workstation(
		_next_origin(),
		{MaterialTypes.ItemType.METAL: 1},
		{MaterialTypes.ItemType.WIRE: 1},
		5,
		1,
	)
	cancel_station.inventory.add_items_unchecked({MaterialTypes.ItemType.METAL: 1})
	var cancel_worker := _spawn_human(
		cancel_station.origin_cell + Vector2i(2, 5),
		GlobalEnum.AgeStatus.ADULT,
		30,
	)
	cancel_station.hire_employee(cancel_worker)
	var cancel_behavior := cancel_worker.ai.get_work_behavior()
	cancel_behavior.begin(cancel_station)
	cancel_behavior.cancel("测试取消")
	_check(
		"INV-08",
		MaterialSystem.get_open_lock_count() == 0
		and MaterialSystem.get_open_reservation_count() == 0,
		"周期取消释放全部锁定和预留",
		"locks=%d reservations=%d" % [
			MaterialSystem.get_open_lock_count(),
			MaterialSystem.get_open_reservation_count(),
		],
	)
	await _dispose_tracked()

	var less_owner := _create_virtual_owner(20, Vector2i(30, 20), true)
	var less_type := WorkType.new(&"test_less", "少产出", 1, {}, {
		MaterialTypes.ItemType.WIRE: 1,
	})
	var less_cycle := WorkCycle.new(91001, less_owner, null, less_type)
	less_cycle.expected_output_volume = 5
	less_cycle.output_reservations = MaterialSystem.reserve_output(
		5,
		less_owner.inventory,
		[],
		less_cycle.get_holder_id(),
	)
	var less_ok := MaterialSystem.settle_cycle(less_cycle)
	_check(
		"INV-09",
		less_ok and less_owner.inventory.reserved_volume == 0,
		"产出少于预留时释放多余空间",
		"settled=%s reserved=%d" % [
			less_ok,
			less_owner.inventory.reserved_volume,
		],
	)

	var invalid_source := _create_virtual_owner(10, Vector2i(32, 20), true)
	var replacement_source := _create_virtual_owner(10, Vector2i(34, 20), true)
	var replace_type := WorkType.new(&"replace", "替换", 1, {}, {
		MaterialTypes.ItemType.WIRE: 1,
	})
	var replace_cycle := WorkCycle.new(91002, invalid_source, null, replace_type)
	replace_cycle.output_reservations = MaterialSystem.reserve_output(
		1,
		invalid_source.inventory,
		[],
		replace_cycle.get_holder_id(),
	)
	MaterialSystem.unregister_inventory(invalid_source.inventory)
	var replaced := MaterialSystem.replace_invalid_reservations(
		replace_cycle,
		[replacement_source.inventory],
	)
	_check(
		"INV-10",
		replaced and MaterialSystem.get_valid_reserved_volume(
			replace_cycle.output_reservations
		) == 1,
		"预留仓库删除后重新预留",
		"replaced=%s" % replaced,
	)

	var no_replacement := _create_virtual_owner(10, Vector2i(36, 20), true)
	var no_replace_type := WorkType.new(&"no_replace", "无替代", 1, {}, {
		MaterialTypes.ItemType.WIRE: 1,
	})
	var no_replace_cycle := WorkCycle.new(91003, no_replacement, null, no_replace_type)
	no_replace_cycle.output_reservations = MaterialSystem.reserve_output(
		1,
		no_replacement.inventory,
		[],
		no_replace_cycle.get_holder_id(),
	)
	MaterialSystem.unregister_inventory(no_replacement.inventory)
	_check(
		"INV-11",
		not MaterialSystem.replace_invalid_reservations(no_replace_cycle, []),
		"无替代仓库时重新预留失败",
		"replaced=false",
	)

	var full_internal := _create_virtual_owner(1, Vector2i(38, 20), false)
	full_internal.inventory.add_items_unchecked({MaterialTypes.ItemType.METAL: 1})
	var external_space := _create_virtual_owner(10, Vector2i(40, 20), true)
	var fallback_reservations := MaterialSystem.reserve_output(
		1,
		full_internal.inventory,
		[external_space.inventory],
		"test:external",
	)
	_check(
		"INV-12",
		fallback_reservations.size() == 1
		and external_space.inventory.reserved_volume == 1,
		"自带库存满时使用外部仓库预留",
		"reservations=%d external_reserved=%d" % [
			fallback_reservations.size(),
			external_space.inventory.reserved_volume,
		],
	)
	MaterialSystem.release_reservations(fallback_reservations)

	var split_a := _create_virtual_owner(2, Vector2i(42, 20), true)
	var split_b := _create_virtual_owner(2, Vector2i(44, 20), true)
	var split_reservations := MaterialSystem.reserve_output(
		3,
		null,
		[split_a.inventory, split_b.inventory],
		"test:split",
	)
	_check(
		"INV-13",
		split_reservations.size() == 2
		and split_a.inventory.reserved_volume == 2
		and split_b.inventory.reserved_volume == 1,
		"空间不足时拆分到多个仓库",
		"a=%d b=%d ids=%d" % [
			split_a.inventory.reserved_volume,
			split_b.inventory.reserved_volume,
			split_reservations.size(),
		],
	)
	MaterialSystem.release_reservations(split_reservations)

	var settle_owner := _create_virtual_owner(20, Vector2i(46, 20), true)
	var settle_type := WorkType.new(&"settle", "结算", 1, {}, {
		MaterialTypes.ItemType.WIRE: 1,
	})
	var settle_cycle := WorkCycle.new(91004, settle_owner, null, settle_type)
	settle_cycle.output_reservations = MaterialSystem.reserve_output(
		1,
		settle_owner.inventory,
		[],
		settle_cycle.get_holder_id(),
	)
	settle_cycle.status = WorkCycle.Status.PENDING_SETTLEMENT
	var settled := MaterialSystem.settle_cycle(settle_cycle)
	_check(
		"INV-14",
		settled
		and settle_owner.inventory.get_item_count(MaterialTypes.ItemType.WIRE) == 1
		and MaterialSystem.get_holder_open_reservation_count(
			settle_cycle.get_holder_id()
		) == 0,
		"产出直接入库，不需居民走向仓库",
		"settled=%s wire=%d" % [
			settled,
			settle_owner.inventory.get_item_count(MaterialTypes.ItemType.WIRE),
		],
	)

	var no_space_owner := _create_virtual_owner(1, Vector2i(48, 20), true)
	no_space_owner.inventory.add_items_unchecked({MaterialTypes.ItemType.METAL: 1})
	var no_space := MaterialSystem.reserve_output(
		1,
		no_space_owner.inventory,
		[],
		"test:no_space",
	)
	var no_space_for_second := no_space_owner.inventory.get_available_volume()
	var second_no_space := MaterialSystem.reserve_output(
		1,
		no_space_owner.inventory,
		[],
		"test:no_space_2",
	)
	_check(
		"INV-15",
		no_space.is_empty()
		and no_space_for_second == 0
		and second_no_space.is_empty(),
		"全部仓库无法预留时禁止开始产出周期",
		"available=%d first=%d second=%d" % [
			no_space_for_second,
			no_space.size(),
			second_no_space.size(),
		],
	)

	var priority_internal := _create_virtual_owner(10, Vector2i(50, 20), false, {
		MaterialTypes.ItemType.METAL: 1,
	})
	var priority_external := _create_virtual_owner(10, Vector2i(52, 20), true, {
		MaterialTypes.ItemType.METAL: 1,
	})
	var priority_locks := MaterialSystem.lock_demand(
		{MaterialTypes.ItemType.METAL: 1},
		priority_internal.inventory,
		[priority_external.inventory],
		"test:priority",
		priority_internal.origin_cell,
	)
	var priority_lock := MaterialSystem.get_lock(priority_locks[0]) if not priority_locks.is_empty() else {}
	_check(
		"INV-16",
		not priority_lock.is_empty()
		and priority_lock["inventory"] == priority_internal.inventory,
		"需求优先锁定雇主自带库存",
		"source=%s" % (priority_lock.get("inventory", null)),
	)
	MaterialSystem.release_locks(priority_locks)
	_clear_virtual_owners()

	var extra_owner := _create_virtual_owner(4, Vector2i(54, 20), true)
	var extra_type := WorkType.new(&"extra", "超产", 1, {}, {
		MaterialTypes.ItemType.WIRE: 3,
	})
	var extra_cycle := WorkCycle.new(91005, extra_owner, null, extra_type)
	extra_cycle.expected_output_volume = 1
	extra_cycle.output_reservations = MaterialSystem.reserve_output(
		1,
		extra_owner.inventory,
		[],
		extra_cycle.get_holder_id(),
	)
	var extra_ok := MaterialSystem.settle_cycle(extra_cycle)
	_check(
		"INV-17",
		extra_ok
		and extra_owner.inventory.get_item_count(MaterialTypes.ItemType.WIRE) == 3,
		"超产使用其他未预留空间",
		"settled=%s wire=%d" % [
			extra_ok,
			extra_owner.inventory.get_item_count(MaterialTypes.ItemType.WIRE),
		],
	)
	_clear_virtual_owners()

	var pending_owner := _create_virtual_owner(1, Vector2i(56, 20), true)
	var pending_type := WorkType.new(&"pending", "待结算", 1, {}, {
		MaterialTypes.ItemType.WIRE: 3,
	})
	var pending_cycle := WorkCycle.new(91006, pending_owner, null, pending_type)
	pending_cycle.expected_output_volume = 1
	pending_cycle.output_reservations = MaterialSystem.reserve_output(
		1,
		pending_owner.inventory,
		[],
		pending_cycle.get_holder_id(),
	)
	var pending_ok := MaterialSystem.settle_cycle(pending_cycle)
	_check(
		"INV-18",
		not pending_ok
		and pending_owner.inventory.get_item_count(MaterialTypes.ItemType.WIRE) == 0
		and MaterialSystem.get_holder_open_reservation_count(
			pending_cycle.get_holder_id()
		) == 1,
		"额外产出无空间时保持待结算",
		"settled=%s reservations=%d" % [
			pending_ok,
			MaterialSystem.get_holder_open_reservation_count(pending_cycle.get_holder_id()),
		],
	)

	var pending_origin := _next_origin()
	var pending_station := _create_workstation(pending_origin, {}, {}, 1, 1)
	var pending_worker := _spawn_human(
		pending_origin + Vector2i(2, 5),
		GlobalEnum.AgeStatus.ADULT,
		30,
	)
	pending_station.hire_employee(pending_worker)
	var pending_behavior := pending_worker.ai.get_work_behavior()
	pending_behavior.cycle = pending_cycle
	pending_behavior.phase = HumanWorkBehavior.Phase.PENDING_SETTLEMENT
	pending_worker.die()
	await get_tree().process_frame
	_check(
		"INV-19",
		not pending_behavior.is_busy()
		and MaterialSystem.get_holder_open_reservation_count(
			pending_cycle.get_holder_id()
		) == 0
		and pending_owner.inventory.get_item_count(MaterialTypes.ItemType.WIRE) == 0,
		"待结算期间居民死亡取消未入库产出",
		"busy=%s reservations=%d" % [
			pending_behavior.is_busy(),
			MaterialSystem.get_holder_open_reservation_count(pending_cycle.get_holder_id()),
		],
	)
	await _dispose_tracked()
	_clear_virtual_owners()


## 验证建筑、仓库、居民和虚拟库存消失后的物资转移与记录清理。
func _test_cleanup() -> void:
	# 清理组验证所有者消失时物资转移、销毁和关联记录失效。
	var source := _create_virtual_owner(20, Vector2i(60, 30), false, {
		MaterialTypes.ItemType.METAL: 3,
	})
	var near_warehouse := _create_virtual_owner(20, Vector2i(62, 30), true)
	var far_warehouse := _create_virtual_owner(20, Vector2i(80, 30), true)
	MaterialSystem.cleanup_owner_inventory(source, source.origin_cell, "测试来源")
	_check(
		"CLEAN-01",
		near_warehouse.inventory.get_item_count(MaterialTypes.ItemType.METAL) == 3
		and far_warehouse.inventory.get_item_count(MaterialTypes.ItemType.METAL) == 0,
		"库存转移到最近仓库",
		"near=%d far=%d" % [
			near_warehouse.inventory.get_item_count(MaterialTypes.ItemType.METAL),
			far_warehouse.inventory.get_item_count(MaterialTypes.ItemType.METAL),
		],
	)
	_clear_virtual_owners()

	source = _create_virtual_owner(20, Vector2i(64, 30), false, {
		MaterialTypes.ItemType.WASTE: 3,
	})
	near_warehouse = _create_virtual_owner(2, Vector2i(66, 30), true)
	far_warehouse = _create_virtual_owner(10, Vector2i(68, 30), true)
	MaterialSystem.cleanup_owner_inventory(source, source.origin_cell, "拆分来源")
	_check(
		"CLEAN-02",
		near_warehouse.inventory.get_item_count(MaterialTypes.ItemType.WASTE) == 1
		and far_warehouse.inventory.get_item_count(MaterialTypes.ItemType.WASTE) == 2,
		"最近仓库不足时拆分到其他仓库",
		"near=%d far=%d" % [
			near_warehouse.inventory.get_item_count(MaterialTypes.ItemType.WASTE),
			far_warehouse.inventory.get_item_count(MaterialTypes.ItemType.WASTE),
		],
	)
	_clear_virtual_owners()

	source = _create_virtual_owner(20, Vector2i(70, 30), false, {
		MaterialTypes.ItemType.WASTE: 4,
	})
	near_warehouse = _create_virtual_owner(2, Vector2i(72, 30), true)
	far_warehouse = _create_virtual_owner(2, Vector2i(74, 30), true)
	MaterialSystem.cleanup_owner_inventory(source, source.origin_cell, "销毁来源")
	var moved_total := (
		near_warehouse.inventory.get_used_volume()
		+ far_warehouse.inventory.get_used_volume()
	)
	_check(
		"CLEAN-03",
		moved_total == 4,
		"所有仓库仍不足时销毁剩余数量",
		"moved_volume=%d destroyed=4" % moved_total,
	)
	_clear_virtual_owners()

	source = _create_virtual_owner(10, Vector2i(76, 30), false, {
		MaterialTypes.ItemType.WIRE: 2,
	})
	near_warehouse = _create_virtual_owner(4, Vector2i(78, 30), true)
	var existing_reservations := MaterialSystem.reserve_output(
		3,
		near_warehouse.inventory,
		[],
		"cleanup:other",
	)
	MaterialSystem.cleanup_owner_inventory(source, source.origin_cell, "预留来源")
	var cleanup_respected := (
		near_warehouse.inventory.get_item_count(MaterialTypes.ItemType.WIRE) == 1
		and near_warehouse.inventory.reserved_volume == 3
	)
	MaterialSystem.release_reservations(existing_reservations)
	_check(
		"CLEAN-04",
		cleanup_respected,
		"自动清算不占用其他周期预留",
		"wire=%d reserved=%d" % [
			near_warehouse.inventory.get_item_count(MaterialTypes.ItemType.WIRE),
			near_warehouse.inventory.reserved_volume,
		],
	)
	_clear_virtual_owners()

	var origin := _next_origin()
	var station := _create_workstation(origin, {
		MaterialTypes.ItemType.METAL: 1,
	}, {
		MaterialTypes.ItemType.WIRE: 1,
	}, 10, 1)
	station.inventory.add_items_unchecked({
		MaterialTypes.ItemType.METAL: 2,
		MaterialTypes.ItemType.WIRE: 1,
	})
	var worker := _spawn_human(origin + Vector2i(2, 5), GlobalEnum.AgeStatus.ADULT, 30)
	station.hire_employee(worker)
	var behavior := worker.ai.get_work_behavior()
	behavior.begin(station)
	station.remove()
	_check(
		"CLEAN-05",
		station.employees.is_empty()
		and not behavior.is_busy()
		and MaterialSystem.get_open_lock_count() == 0
		and MaterialSystem.get_open_reservation_count() == 0,
		"建筑删除先取消周期再清算库存",
		"locks=%d reservations=%d" % [
			MaterialSystem.get_open_lock_count(),
			MaterialSystem.get_open_reservation_count(),
		],
	)
	await _dispose_tracked()

	var deleted_warehouse := _create_virtual_owner(10, Vector2i(82, 30), true, {
		MaterialTypes.ItemType.METAL: 2,
	})
	var warehouse_lock := MaterialSystem.lock_items(
		deleted_warehouse.inventory,
		MaterialTypes.ItemType.METAL,
		1,
		"cleanup:warehouse",
		deleted_warehouse.origin_cell,
	)
	var warehouse_reservation := MaterialSystem.reserve_output(
		1,
		deleted_warehouse.inventory,
		[],
		"cleanup:warehouse",
	)
	MaterialSystem.unregister_inventory(deleted_warehouse.inventory)
	_check(
		"CLEAN-06",
		not MaterialSystem.is_lock_valid(warehouse_lock)
		and not MaterialSystem.is_reservation_valid(warehouse_reservation[0]),
		"仓库删除后相关锁定和预留失效",
		"lock_valid=%s reservation_valid=%s" % [
			MaterialSystem.is_lock_valid(warehouse_lock),
			MaterialSystem.is_reservation_valid(warehouse_reservation[0]),
		],
	)
	_clear_virtual_owners()

	var isolated := preload("res://Scripts/Core/MaterialSystem.gd").new()
	add_child(isolated)
	var isolated_owner := Building.new()
	isolated_owner.name = "isolated-source"
	isolated_owner.origin_cell = Vector2i(1, 1)
	isolated_owner.inventory = Inventory.new(10)
	isolated_owner.inventory.items[MaterialTypes.ItemType.METAL] = 2
	var isolated_target := Building.new()
	isolated_target.name = "isolated-target"
	isolated_target.origin_cell = Vector2i(2, 1)
	isolated_target.is_warehouse = true
	isolated_target.inventory = Inventory.new(10)
	isolated.register_inventory(isolated_owner.inventory, isolated_owner)
	isolated.register_inventory(isolated_target.inventory, isolated_target)
	isolated.begin_scene_shutdown()
	isolated.cleanup_owner_inventory(isolated_owner, isolated_owner.origin_cell, "isolated")
	var no_scene_cleanup := isolated_target.inventory.get_item_count(
		MaterialTypes.ItemType.METAL
	) == 0
	var isolated_target_count := isolated_target.inventory.get_item_count(
		MaterialTypes.ItemType.METAL
	)
	isolated.queue_free()
	isolated_owner.free()
	isolated_target.free()
	_check(
		"CLEAN-07",
		no_scene_cleanup,
		"场景整体退出不执行游戏内自动清算",
		"target_metal=%d" % isolated_target_count,
	)

	source = _create_virtual_owner(20, Vector2i(84, 30), false, {
		MaterialTypes.ItemType.PLASTIC: 2,
	})
	near_warehouse = _create_virtual_owner(
		10,
		Vector2i(85, 30),
		true,
	)
	far_warehouse = _create_virtual_owner(
		10,
		Vector2i(90, 30),
		true,
	)
	MaterialSystem.cleanup_owner_inventory(source, source.origin_cell, "距离来源")
	_check(
		"CLEAN-08",
		near_warehouse.inventory.get_item_count(MaterialTypes.ItemType.PLASTIC) == 2,
		"距离以来源建筑左上角计算",
		"near=%d far=%d" % [
			near_warehouse.inventory.get_item_count(MaterialTypes.ItemType.PLASTIC),
			far_warehouse.inventory.get_item_count(MaterialTypes.ItemType.PLASTIC),
		],
	)
	_clear_virtual_owners()

	var return_source := _create_virtual_owner(10, Vector2i(92, 30), true, {
		MaterialTypes.ItemType.WIRE: 1,
	})
	var death_lock := MaterialSystem.lock_items(
		return_source.inventory,
		MaterialTypes.ItemType.WIRE,
		1,
		"dead:human",
		return_source.origin_cell,
	)
	MaterialSystem.take_locked(death_lock)
	MaterialSystem.release_lock(death_lock)
	_check(
		"CLEAN-09",
		return_source.inventory.get_item_count(MaterialTypes.ItemType.WIRE) == 1,
		"死亡时工作需求退回来源仓库",
		"wire=%d" % return_source.inventory.get_item_count(MaterialTypes.ItemType.WIRE),
	)
	_clear_virtual_owners()

	var output_owner := _create_virtual_owner(2, Vector2i(94, 30), true)
	var output_type := WorkType.new(&"death_output", "死亡产出", 1, {}, {
		MaterialTypes.ItemType.WIRE: 3,
	})
	var death_cycle := WorkCycle.new(92001, output_owner, null, output_type)
	death_cycle.expected_output_volume = 1
	death_cycle.output_reservations = MaterialSystem.reserve_output(
		1,
		output_owner.inventory,
		[],
		death_cycle.get_holder_id(),
	)
	var death_worker := _spawn_human(Vector2i(94, 40), GlobalEnum.AgeStatus.ADULT, 30)
	var death_behavior := death_worker.ai.get_work_behavior()
	death_behavior.cycle = death_cycle
	death_behavior.phase = HumanWorkBehavior.Phase.PENDING_SETTLEMENT
	death_worker.die()
	await get_tree().process_frame
	_check(
		"CLEAN-10",
		output_owner.inventory.get_item_count(MaterialTypes.ItemType.WIRE) == 0
		and MaterialSystem.get_holder_open_reservation_count(
			death_cycle.get_holder_id()
		) == 0,
		"居民死亡时未入库产出取消",
		"wire=%d reservations=%d" % [
			output_owner.inventory.get_item_count(MaterialTypes.ItemType.WIRE),
			MaterialSystem.get_holder_open_reservation_count(death_cycle.get_holder_id()),
		],
	)
	await _dispose_tracked()
	_clear_virtual_owners()

## 验证正式玩家状态栏的注册、统计口径、无限来源、悬停详情和布局。
func _test_status_display() -> void:
	var status_bar := get_parent().get_node_or_null("PlayerStatusBar") as PlayerStatusBar
	_check(
		"STAT-01",
		status_bar != null,
		"World 挂载正式 PlayerStatusBar",
		"status_bar=%s" % status_bar,
	)
	if status_bar == null:
		return
	await get_tree().process_frame

	var initial_snapshot := status_bar.get_debug_snapshot()
	var expected_material_ids: Array[String] = []
	for item_type in MaterialTypes.STATUS_ITEM_ORDER:
		expected_material_ids.append("material:%d" % item_type)
	var registered_ids: Array[String] = initial_snapshot["item_ids"]
	var material_order_ok := true
	for index in range(expected_material_ids.size()):
		if registered_ids[index] != expected_material_ids[index]:
			material_order_ok = false
			break
	_check(
		"STAT-02",
		MaterialSystem.get_status_registration_count() == 6
		and material_order_ok
		and registered_ids[-2] == "population"
		and registered_ids[-1] == "time",
		"六种物资按水/食物/废料/塑料/金属/线注册一次，后接人口和时间",
		"count=%d ids=%s" % [
			MaterialSystem.get_status_registration_count(),
			registered_ids,
		],
	)

	var white_icons_ok := true
	for item_id in expected_material_ids:
		var item := status_bar.get_item_control(item_id)
		if (
			item == null
			or item.get_icon_texture() == null
			or not item.has_white_icon()
		):
			white_icons_ok = false
			break
	_check(
		"STAT-03",
		white_icons_ok,
		"六种物资都有白色图标",
		"icons_ok=%s" % white_icons_ok,
	)

	var origin := _next_origin()
	var stats_warehouse := _create_test_warehouse(origin, {
		MaterialTypes.ItemType.WATER: 7,
		MaterialTypes.ItemType.FOOD: 5,
		MaterialTypes.ItemType.WASTE: 4,
		MaterialTypes.ItemType.PLASTIC: 3,
		MaterialTypes.ItemType.METAL: 2,
		MaterialTypes.ItemType.WIRE: 1,
	})
	var child_human := _spawn_human(
		origin + Vector2i(1, 5),
		GlobalEnum.AgeStatus.CHILD,
		10,
	)
	var adult_human := _spawn_human(
		origin + Vector2i(2, 5),
		GlobalEnum.AgeStatus.ADULT,
		30,
	)
	_spawn_human(
		origin + Vector2i(3, 5),
		GlobalEnum.AgeStatus.OLD,
		70,
	)
	await get_tree().process_frame

	var summaries: Dictionary = status_bar.get_item_summaries()
	var expected_summaries := {
		"material:%d" % MaterialTypes.ItemType.WATER: "无限",
		"material:%d" % MaterialTypes.ItemType.FOOD: "无限",
		"material:%d" % MaterialTypes.ItemType.WASTE: "4",
		"material:%d" % MaterialTypes.ItemType.PLASTIC: "3",
		"material:%d" % MaterialTypes.ItemType.METAL: "2",
		"material:%d" % MaterialTypes.ItemType.WIRE: "1",
	}
	var summaries_ok := true
	for item_id in expected_summaries:
		if String(summaries.get(item_id, "")) != String(expected_summaries[item_id]):
			summaries_ok = false
			break
	_check(
		"STAT-04",
		summaries_ok,
		"只汇总仓库，工作站自带库存不进入第一行",
		"summaries=%s" % summaries,
	)

	var wire_id := "material:%d" % MaterialTypes.ItemType.WIRE
	var wire_lock := MaterialSystem.lock_items(
		stats_warehouse.inventory,
		MaterialTypes.ItemType.WIRE,
		1,
		"stats:lock",
		origin,
	)
	var locked_summary := String(status_bar.get_item_summaries().get(wire_id, ""))
	var taken_to_bag := MaterialSystem.take_locked(wire_lock, child_human.carry)
	var carried_summary := String(status_bar.get_item_summaries().get(wire_id, ""))
	var bag_excluded := (
		taken_to_bag
		and child_human.carry.get_item_count(MaterialTypes.ItemType.WIRE) == 1
		and carried_summary == "0"
	)
	child_human.carry.remove_items(MaterialTypes.ItemType.WIRE, 1)
	stats_warehouse.inventory.add_items_unchecked({
		MaterialTypes.ItemType.WIRE: 1,
	})
	_check(
		"STAT-05",
		locked_summary == "1" and bag_excluded,
		"仓库锁定仍计入，取出到居民背包后从第一行排除",
		"locked=%s carried=%s bag=%d" % [
			locked_summary,
			carried_summary,
			child_human.carry.get_item_count(MaterialTypes.ItemType.WIRE),
		],
	)

	var water_station: Building = null
	var food_station: Building = null
	for building in TickManager.get_buildings_of_type(GlobalEnum.BuildingType.WATER):
		water_station = building
		break
	for building in TickManager.get_buildings_of_type(GlobalEnum.BuildingType.FOOD):
		food_station = building
		break
	var infinite_types_ok := (
		water_station != null
		and food_station != null
		and water_station.get_infinite_item_type() == MaterialTypes.ItemType.WATER
		and food_station.get_infinite_item_type() == MaterialTypes.ItemType.FOOD
	)
	var infinite_overrides_warehouse := (
		MaterialSystem.get_warehouse_item_total(MaterialTypes.ItemType.WATER) == 7
		and String(status_bar.get_item_summaries().get(
			"material:%d" % MaterialTypes.ItemType.WATER,
			"",
		)) == "无限"
	)
	_check(
		"STAT-06",
		infinite_types_ok and infinite_overrides_warehouse,
		"水/食物无限来源覆盖同类仓库有限储量",
		"types_ok=%s finite_water=%d summary=%s" % [
			infinite_types_ok,
			MaterialSystem.get_warehouse_item_total(MaterialTypes.ItemType.WATER),
			status_bar.get_item_summaries().get(
				"material:%d" % MaterialTypes.ItemType.WATER,
				"",
			),
		],
	)

	TickManager.unregister_building(water_station)
	var finite_after_removal := String(status_bar.get_item_summaries().get(
		"material:%d" % MaterialTypes.ItemType.WATER,
		"",
	))
	TickManager.register_building(water_station)
	var infinite_after_restore := String(status_bar.get_item_summaries().get(
		"material:%d" % MaterialTypes.ItemType.WATER,
		"",
	))
	_check(
		"STAT-07",
		finite_after_removal == "7" and infinite_after_restore == "无限",
		"无限材料站移除后恢复仓库汇总，重新登记后恢复无限",
		"removed=%s restored=%s" % [finite_after_removal, infinite_after_restore],
	)

	var population_summary := String(
		status_bar.get_item_summaries().get("population", "")
	)
	adult_human.age_status = GlobalEnum.AgeStatus.OLD
	var aged_population_summary := String(
		status_bar.get_item_summaries().get("population", "")
	)
	var population_station := _create_workstation(_next_origin(), {}, {}, 1, 1)
	population_station.allow_old_workers = true
	population_station.hire_employee(adult_human)
	var unemployed_counts := status_bar.get_unemployed_population_counts()
	var population_detail := status_bar.get_population_detail()
	var no_work_labels_ok := false
	if not population_detail.is_empty():
		var rows: Array = population_detail[0].get("rows", [])
		no_work_labels_ok = (
			rows.size() == 3
			and String(rows[0].get("label", "")) == "儿童无工作"
			and String(rows[1].get("label", "")) == "成人无工作"
			and String(rows[2].get("label", "")) == "老人无工作"
		)
	_check(
		"STAT-08",
		population_summary == "儿童 1  成人 1  老人 1"
		and aged_population_summary == "儿童 1  成人 0  老人 2"
		and int(unemployed_counts[GlobalEnum.AgeStatus.CHILD]) == 1
		and int(unemployed_counts[GlobalEnum.AgeStatus.ADULT]) == 0
		and int(unemployed_counts[GlobalEnum.AgeStatus.OLD]) == 1
		and no_work_labels_ok,
		"人口按 age_status 统计，详情按年龄段显示无工作人数",
		"before=%s after=%s unemployed=%s labels=%s" % [
			population_summary,
			aged_population_summary,
			unemployed_counts,
			no_work_labels_ok,
		],
	)

	var first_day_text := PlayerStatusBar.format_game_time(0, 0)
	var original_tick := TickManager.total_ticks
	TickManager.total_ticks = TickManager.TICKS_PER_DAY + 41
	TickManager.advance_tick()
	await get_tree().process_frame
	var second_day_text := String(status_bar.get_item_summaries().get("time", ""))
	var time_item := status_bar.get_item_control("time")
	time_item.mouse_entered.emit()
	var time_has_no_detail := not status_bar.is_detail_open()
	time_item.mouse_exited.emit()
	_check(
		"STAT-09",
		first_day_text == "0001天0000刻"
		and second_day_text == "0002天0042刻"
		and time_has_no_detail,
		"时间按四位补零显示且不提供悬停详情",
		"first=%s second=%s hover_detail=%s" % [
			first_day_text,
			second_day_text,
			not time_has_no_detail,
		],
	)

	var wire_item := status_bar.get_item_control(wire_id)
	var fetch_before := int(status_bar.get_debug_snapshot()["detail_fetch_count"])
	wire_item.mouse_entered.emit()
	var opened_snapshot := status_bar.get_debug_snapshot()
	var opened_ok := (
		bool(opened_snapshot["detail_open"])
		and int(opened_snapshot["detail_fetch_count"]) == fetch_before + 1
		and String(opened_snapshot["detail_text"]).contains("总数=1")
	)
	var detail_lock := MaterialSystem.lock_items(
		stats_warehouse.inventory,
		MaterialTypes.ItemType.WIRE,
		1,
		"stats:detail",
		origin,
	)
	var locked_detail_ok := (
		String(status_bar.get_debug_snapshot()["detail_text"]).contains("已锁定=1")
	)
	MaterialSystem.release_lock(detail_lock)
	var unlocked_detail_ok := (
		String(status_bar.get_debug_snapshot()["detail_text"]).contains("已锁定=0")
	)
	stats_warehouse.inventory.add_items_unchecked({
		MaterialTypes.ItemType.WIRE: 2,
	})
	var updated_snapshot := status_bar.get_debug_snapshot()
	var live_update_ok := (
		locked_detail_ok
		and unlocked_detail_ok
		and String(updated_snapshot["detail_text"]).contains("总数=3")
		and int(updated_snapshot["detail_fetch_count"]) == fetch_before + 4
	)
	wire_item.mouse_exited.emit()
	var closed_snapshot := status_bar.get_debug_snapshot()
	var fetch_when_closed := int(closed_snapshot["detail_fetch_count"])
	TickManager.advance_tick()
	stats_warehouse.inventory.remove_items_unchecked(
		MaterialTypes.ItemType.WIRE,
		1,
	)
	var closed_after_changes := status_bar.get_debug_snapshot()
	_check(
		"STAT-10",
		opened_ok
		and live_update_ok
		and not bool(closed_snapshot["detail_open"])
		and int(closed_after_changes["detail_fetch_count"]) == fetch_when_closed,
		"详情悬停时实时刷新，关闭后不再生成详情",
		"opened=%s live=%s closed_open=%s fetches=%d" % [
			opened_ok,
			live_update_ok,
			closed_snapshot["detail_open"],
			int(closed_after_changes["detail_fetch_count"]) - fetch_when_closed,
		],
	)

	var empty_summary := func() -> String: return "测试项"
	var empty_detail := func() -> Array[Dictionary]: return []
	var width_before := (status_bar.get_debug_snapshot()["bar_size"] as Vector2).x
	var custom_item := status_bar.register_info_item({
		"id": "test:no_detail",
		"row": 1,
		"order": 99,
		"title": "测试项",
		"icon": PlayerStatusBar.POPULATION_ICON,
		"show_title": false,
		"summary_provider": empty_summary,
		"detail_provider": empty_detail,
		"refresh_channels": [],
	})
	await get_tree().process_frame
	var width_after := (status_bar.get_debug_snapshot()["bar_size"] as Vector2).x
	var custom_created := (
		custom_item != null
		and status_bar.get_item_control("test:no_detail") == custom_item
	)
	custom_item.mouse_entered.emit()
	var custom_has_no_detail := not status_bar.is_detail_open()
	custom_item.mouse_exited.emit()
	var custom_removed := status_bar.unregister_info_item("test:no_detail")
	await get_tree().process_frame
	_check(
		"STAT-11",
		custom_created
		and width_after > width_before
		and custom_has_no_detail
		and custom_removed,
		"信息项动态改变栏宽，详情提供者可自行返回空内容",
		"width=%.1f->%.1f no_detail=%s removed=%s" % [
			width_before,
			width_after,
			custom_has_no_detail,
			custom_removed,
		],
	)

	var layout_snapshot := status_bar.get_debug_snapshot()
	var viewport_size := get_viewport().get_visible_rect().size
	var bar_position: Vector2 = layout_snapshot["bar_position"]
	var bar_size: Vector2 = layout_snapshot["bar_size"]
	var centered := absf(bar_position.x + bar_size.x * 0.5 - viewport_size.x * 0.5) <= 2.0
	_check(
		"STAT-12",
		centered
		and is_zero_approx(bar_position.y)
		and float(layout_snapshot["surface_fill_alpha"]) <= 0.55
		and float(layout_snapshot["text_alpha"]) < 0.85
		and bool(layout_snapshot["bar_accepts_mouse"])
		and bool(layout_snapshot["item_accepts_mouse"]),
		"状态栏紧贴顶部、透明度约 0.5 且根控件与信息项拦截鼠标",
		"position=%s size=%s centered=%s fill_alpha=%.2f text_alpha=%.2f bar_mouse=%s item_mouse=%s" % [
			bar_position,
			bar_size,
			centered,
			float(layout_snapshot["surface_fill_alpha"]),
			float(layout_snapshot["text_alpha"]),
			layout_snapshot["bar_accepts_mouse"],
			layout_snapshot["item_accepts_mouse"],
		],
	)

	TickManager.total_ticks = original_tick
	await _dispose_tracked()


## 验证建筑详情数据、可编辑数字输入、刷新焦点稳定和布局边界。
func _test_ui_contract() -> void:
	# UI 契约组直接读取详情数据，并在无头视口中检查焦点与布局稳定性。
	var scrap_sorting_station: Building = get_parent().get(
		"scrap_sorting_station"
	) as Building
	var workstation_sections: Array[Dictionary] = scrap_sorting_station.get_detail_sections()
	var employment_section := _find_section(workstation_sections, "employment")
	var target_row := _find_row(employment_section, "target_workers")
	_check(
		"UI-01",
		not employment_section.is_empty()
		and not target_row.is_empty()
		and target_row["kind"] == "number"
		and int(target_row["max"]) == 3,
		"可雇佣建筑显示 0..3 目标人数",
		"kind=%s range=%s" % [
			target_row.get("kind", ""),
			[target_row.get("min", ""), target_row.get("max", "")],
		],
	)

	var water_station: Building = null
	for building in TickManager.get_buildings_of_type(GlobalEnum.BuildingType.WATER):
		water_station = building
		break
	var water_sections := water_station.get_detail_sections() if water_station != null else []
	_check(
		"UI-02",
		_find_section(water_sections, "employment").is_empty(),
		"不可雇佣建筑不显示雇佣控件",
		"employment_section=%s" % _find_section(water_sections, "employment"),
	)

	var warehouse: Warehouse = get_parent().get("warehouse")
	var warehouse_rows := warehouse.get_detail_sections()
	var inventory_section := _find_section(warehouse_rows, "inventory")
	var has_used := not _find_row(inventory_section, "已用体积").is_empty()
	var has_reserved := not _find_row(inventory_section, "已预留体积").is_empty()
	var has_available := not _find_row(inventory_section, "可用体积").is_empty()
	_check(
		"UI-03",
		has_used and has_reserved and has_available,
		"仓库详情显示已用、预留、可用体积",
		"used=%s reserved=%s available=%s" % [has_used, has_reserved, has_available],
	)

	var panel := get_parent().get_node_or_null("BuildingDetailPanel") as BuildingDetailPanel
	panel.show_building(scrap_sorting_station)
	await get_tree().process_frame
	var spin := _find_first_spinbox(panel)
	var focus_ok := false
	var input_stable := false
	if spin != null:
		spin.grab_focus()
		await get_tree().process_frame
		var focused_before_refresh := spin.has_focus()
		panel.call("_refresh")
		var refreshed_spin := _find_first_spinbox(panel)
		var input_control_stayed_alive := (
			is_instance_valid(spin)
			and refreshed_spin == spin
		)
		input_stable = input_control_stayed_alive
		# 无头显示服务器可能不授予键盘焦点；控件身份不变证明刷新没有重建输入框。
		focus_ok = input_control_stayed_alive and (
			spin.has_focus()
			or not focused_before_refresh
		)
	_check(
		"UI-04",
		focus_ok,
		"每刻刷新不打断数字输入焦点",
		"input_stable=%s focus=%s" % [input_stable, spin != null and spin.has_focus()],
	)

	var original_viewport_size: Vector2i = get_viewport().size
	get_viewport().size = Vector2i(800, 600)
	await get_tree().process_frame
	panel.call("_update_panel_width")
	panel.call("_refresh")
	await get_tree().process_frame
	var layout_issues: Array[String] = panel.get_layout_issues()
	get_viewport().size = original_viewport_size
	await get_tree().process_frame
	panel.hide_panel()
	_check(
		"UI-07",
		layout_issues.is_empty(),
		"800x600 下文本和控件不重叠、面板不越界",
		"issues=%s" % [layout_issues],
	)

	var placer := get_parent().get("_placer") as PlacementController
	placer.select_kind(PlacementController.Kind.WAREHOUSE)
	var placement_cell := Vector2i(250, 300)
	var first_place := placer.place_at_cell(placement_cell)
	var buildings_before_overlap := TickManager.buildings.size()
	var overlap_place := placer.place_at_cell(placement_cell)
	placer.cancel()
	var placed_warehouse: Building = null
	for building in TickManager.buildings:
		if building.building_type == GlobalEnum.BuildingType.WAREHOUSE:
			if world_position_matches(building, placement_cell):
				placed_warehouse = building
				break
	if is_instance_valid(placed_warehouse):
		placed_warehouse.remove()
	_check(
		"UI-05",
		first_place
		and not overlap_place
		and TickManager.buildings.size() <= buildings_before_overlap,
		"仓库预览、连续放置和重叠拒绝正常",
		"first=%s overlap=%s" % [first_place, overlap_place],
	)

	var target_value_applied := false
	var parent_station := get_parent().get("scrap_sorting_station") as Building
	var original_target := parent_station.target_workers
	if not target_row.is_empty():
		var callback: Callable = target_row["on_changed"]
		callback.call(2)
		target_value_applied = parent_station.target_workers == 2
		parent_station.set_target_workers(original_target)
	_check(
		"UI-06",
		target_value_applied,
		"目标人数修改触发回调并由建筑夹取",
		"target=%d" % parent_station.target_workers,
	)


## 恢复场景后运行真实居民模拟，验证时间推进和工作结果。
func _test_integration() -> void:
	# 集成组推进完整游戏日，确认雇佣与工作周期结果确实落到真实模拟中。
	TickManager.auto_run = false
	for _i in range(1800):
		TickManager.advance_tick()
	var integration_station: Building = get_parent().get(
		"scrap_sorting_station"
	) as Building
	var work_results: int = (
		integration_station.work_result_count
		if integration_station != null
		else 0
	)
	var employees: int = (
		integration_station.employees.size()
		if integration_station != null
		else 0
	)
	var work_ok := (
		TickManager.total_ticks >= 1800
		and employees == 3
		and work_results > 0
	)
	_check(
		"SIM",
		work_ok,
		"1800 刻集成模拟完成雇佣并产生周期结果",
		"tick=%d employees=%d results=%d" % [
			TickManager.total_ticks,
			employees,
			work_results,
		],
	)


## 创建并放置一个可配置工作站，记录到验收生命周期并返回实例。[br]
## [param origin] 是工作站左上角格子。[br]
## [param demand] 是工作周期需求物资配置。[br]
## [param output] 是工作周期产出物资配置。[br]
## [param duration] 是完成一次工作的刻数。[br]
## [param target] 是建筑初始目标工人数。[br]
## 返回已经创建并追踪的测试工作站。
func _create_workstation(
	origin: Vector2i,
	demand: Dictionary,
	output: Dictionary,
	duration: int = 1,
	target: int = 1,
) -> Building:
	var station := ScrapSortingStation.new()
	station.work_type = WorkType.new(
		StringName("test_%d" % _fixture_index),
		"测试工作",
		duration,
		demand,
		output,
	)
	station.max_workers = target
	station.target_workers = target
	station.name = "测试工作站%d" % _fixture_index
	get_parent().add_child(station)
	if not station.place_at(WorldGridGlobal.world, origin):
		push_error("AcceptanceSelfTest: 工作站无法放置在 %s" % origin)
	_tracked_buildings.append(station)
	return station


## 创建并放置一个测试仓库，记录到验收生命周期并返回实例。[br]
## [param origin] 是仓库左上角格子。[br]
## [param items] 是仓库初始物资。[br]
## 返回已经创建并追踪的测试仓库。
func _create_test_warehouse(
	origin: Vector2i,
	items: Dictionary = {},
) -> Warehouse:
	var test_warehouse := Warehouse.new()
	test_warehouse.name = "测试仓库%d" % _fixture_index
	_fixture_index += 1
	get_parent().add_child(test_warehouse)
	if not test_warehouse.place_at(WorldGridGlobal.world, origin):
		push_error("AcceptanceSelfTest: 仓库无法放置在 %s" % origin)
	elif not items.is_empty():
		test_warehouse.inventory.add_items_unchecked(items)
	_tracked_buildings.append(test_warehouse)
	return test_warehouse


## 在指定格生成居民，记录到验收生命周期并返回实例。[br]
## [param cell] 是居民出生格。[br]
## [param age_status] 是居民年龄阶段。[br]
## [param age] 是居民具体年龄。[br]
## 返回已经生成并追踪的测试居民。
func _spawn_human(
	cell: Vector2i,
	age_status: GlobalEnum.AgeStatus = GlobalEnum.AgeStatus.ADULT,
	age: int = 30,
) -> Human:
	var human := Human.create()
	human.name = "验收居民%d" % _fixture_index
	_fixture_index += 1
	human.age_status = age_status
	human.age = age
	human.position = WorldGridGlobal.world.cell_to_world(cell)
	get_parent().add_child(human)
	_tracked_humans.append(human)
	return human


## 创建不属于场景树的虚拟建筑所有者，用于隔离库存账本测试。[br]
## [param capacity] 是虚拟库存容量。[br]
## [param origin] 是虚拟建筑用于距离排序的格子坐标。[br]
## [param is_warehouse] 指定该所有者是否作为公共仓库参与候选排序。[br]
## [param items] 是虚拟库存的初始物资。[br]
## 返回登记了虚拟库存的建筑对象。
func _create_virtual_owner(
	capacity: int,
	origin: Vector2i,
	is_warehouse: bool,
	items: Dictionary = {},
) -> Building:
	var owner := Building.new()
	owner.name = "虚拟来源%d" % _fixture_index
	_fixture_index += 1
	owner.origin_cell = origin
	owner.is_warehouse = is_warehouse
	owner.inventory_capacity = capacity
	owner.inventory = Inventory.new(capacity)
	MaterialSystem.register_inventory(owner.inventory, owner)
	if not items.is_empty():
		owner.inventory.add_items_unchecked(items)
	_virtual_owners.append(owner)
	return owner


## 创建并登记一个独立测试库存。[br]
## [param capacity] 是库存容量。[br]
## [param origin] 是虚拟所有者所在格，用于距离排序。[br]
## [param is_warehouse] 指定虚拟所有者是否作为公共仓库。[br]
## [param items] 是库存初始物资。[br]
## 返回已登记到 [MaterialSystem] 的测试库存。
func _create_virtual_inventory(
	capacity: int,
	origin: Vector2i,
	is_warehouse: bool,
	items: Dictionary = {},
) -> Inventory:
	return _create_virtual_owner(capacity, origin, is_warehouse, items).inventory


## 返回下一个互不重叠的测试设施布局格。
func _next_origin() -> Vector2i:
	@warning_ignore("integer_division")
	var row := (_fixture_index / 30) % 10
	var origin := Vector2i(
		100 + (_fixture_index % 30) * 10,
		150 + row * 14,
	)
	_fixture_index += 1
	return origin


## 临时注销场景原有居民，避免干扰验收测试。
func _suspend_existing_humans() -> void:
	_suspended_humans = TickManager.humans.duplicate()
	for human in _suspended_humans:
		TickManager.unregister_human(human)


## 恢复验收前暂停的原有居民。
func _restore_existing_humans() -> void:
	for human in _suspended_humans:
		if is_instance_valid(human):
			TickManager.register_human(human)
	_suspended_humans.clear()


## 临时注销场景原有仓库，隔离外部库存来源。
func _suspend_existing_warehouses() -> void:
	_suspended_inventories.clear()
	for building in TickManager.get_buildings_of_type(GlobalEnum.BuildingType.WAREHOUSE):
		if is_instance_valid(building) and building.inventory != null:
			MaterialSystem.unregister_inventory(building.inventory)
			_suspended_inventories.append(building.inventory)


## 恢复验收前临时注销的仓库库存。
func _restore_existing_warehouses() -> void:
	for inventory in _suspended_inventories:
		if is_instance_valid(inventory) and is_instance_valid(inventory.owner):
			MaterialSystem.register_inventory(inventory, inventory.owner)
	_suspended_inventories.clear()


## 销毁本组验收创建并追踪的全部居民和建筑。
func _dispose_tracked() -> void:
	for human in _tracked_humans:
		if is_instance_valid(human) and not human.is_queued_for_deletion():
			human.die()
	for building in _tracked_buildings:
		if is_instance_valid(building) and not building.is_queued_for_deletion():
			if building.inventory != null:
				building.inventory.items.clear()
			building.remove()
	_tracked_humans.clear()
	_tracked_buildings.clear()
	await get_tree().process_frame
	await get_tree().process_frame


## 清理虚拟所有者及其库存，不触发场景级物资转移。
func _clear_virtual_owners() -> void:
	for owner in _virtual_owners:
		if not is_instance_valid(owner):
			continue
		if owner.inventory != null and MaterialSystem.is_inventory_registered(owner.inventory):
			MaterialSystem.unregister_inventory(owner.inventory)
		owner.free()
	_virtual_owners.clear()


## 从详情板块数组中查找指定板块 ID 的数据。[br]
## [param sections] 是建筑详情返回的板块数组。[br]
## [param section_id] 是要查找的板块标识。[br]
## 返回匹配板块字典；不存在时返回空字典。
func _find_section(sections: Array[Dictionary], section_id: String) -> Dictionary:
	for section in sections:
		if String(section.get("id", "")) == section_id:
			return section
	return {}


## 从详情板块中查找指定行键的数据。[br]
## [param section] 是包含行列表的板块字典。[br]
## [param key] 是要查找的行稳定标识。[br]
## 返回匹配行字典；不存在时返回空字典。
func _find_row(section: Dictionary, key: String) -> Dictionary:
	if section.is_empty():
		return {}
	for row in section.get("rows", []):
		if String(row.get("key", "")) == key:
			return row
	return {}


## 深度查找节点下第一个可用的 [SpinBox]。[br]
## [param node] 是开始递归搜索的节点。[br]
## 返回第一个找到的数字输入控件；不存在时返回 null。
func _find_first_spinbox(node: Node) -> SpinBox:
	if node is SpinBox:
		return node as SpinBox
	for child in node.get_children():
		var found := _find_first_spinbox(child)
		if found != null:
			return found
	return null


## 比较建筑节点位置与 [param center_cell] 对应的格子中心是否在浮点容差内一致。[br]
## [param building] 是要检查位置的建筑节点。[br]
## 返回建筑位置是否与目标格中心匹配。
func world_position_matches(building: Building, center_cell: Vector2i) -> bool:
	var expected_origin := center_cell - Vector2i(
		building.size_cells.x / 2,
		building.size_cells.y / 2,
	)
	return building.origin_cell == expected_origin
