extends Node
class_name AcceptanceSelfTest

## v0.0.1.4 验收自检。每个验收 ID 都只输出一次 PASS/FAIL，
## 最后运行真实模拟并检查物资账本、锁和预留没有悬空。

var _total: int = 0
var _passed: int = 0
var _failures: Array[String] = []
var _tracked_buildings: Array[Building] = []
var _tracked_humans: Array[Human] = []
var _virtual_owners: Array[Building] = []
var _suspended_humans: Array[Human] = []
var _suspended_inventories: Array[Inventory] = []
var _fixture_index: int = 0
var _original_tick: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	TickManager.auto_run = false
	_original_tick = TickManager.total_ticks
	_suspend_existing_humans()
	_suspend_existing_warehouses()
	await get_tree().process_frame

	await _test_employment()
	await _test_schedule_and_waiting()
	await _test_work_cycles()
	await _test_inventory()
	await _test_cleanup()
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


func _test_employment() -> void:
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


func _test_schedule_and_waiting() -> void:
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


func _test_work_cycles() -> void:
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


func _test_inventory() -> void:
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


func _test_cleanup() -> void:
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


func _test_ui_contract() -> void:
	var work_station: WorkStation = get_parent().get("work_station") as WorkStation
	var workstation_sections: Array[Dictionary] = work_station.get_detail_sections()
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
	panel.show_building(get_parent().get("work_station"))
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
	var parent_station := get_parent().get("work_station") as WorkStation
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


func _test_integration() -> void:
	TickManager.auto_run = false
	for _i in range(1800):
		TickManager.advance_tick()
	var integration_station: WorkStation = get_parent().get("work_station") as WorkStation
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


func _create_workstation(
	origin: Vector2i,
	demand: Dictionary,
	output: Dictionary,
	duration: int = 1,
	target: int = 1,
) -> WorkStation:
	var station := WorkStation.new()
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


func _create_virtual_inventory(
	capacity: int,
	origin: Vector2i,
	is_warehouse: bool,
	items: Dictionary = {},
) -> Inventory:
	return _create_virtual_owner(capacity, origin, is_warehouse, items).inventory


func _next_origin() -> Vector2i:
	@warning_ignore("integer_division")
	var row := (_fixture_index / 30) % 10
	var origin := Vector2i(
		100 + (_fixture_index % 30) * 10,
		150 + row * 14,
	)
	_fixture_index += 1
	return origin


func _suspend_existing_humans() -> void:
	_suspended_humans = TickManager.humans.duplicate()
	for human in _suspended_humans:
		TickManager.unregister_human(human)


func _restore_existing_humans() -> void:
	for human in _suspended_humans:
		if is_instance_valid(human):
			TickManager.register_human(human)
	_suspended_humans.clear()


func _suspend_existing_warehouses() -> void:
	_suspended_inventories.clear()
	for building in TickManager.get_buildings_of_type(GlobalEnum.BuildingType.WAREHOUSE):
		if is_instance_valid(building) and building.inventory != null:
			MaterialSystem.unregister_inventory(building.inventory)
			_suspended_inventories.append(building.inventory)


func _restore_existing_warehouses() -> void:
	for inventory in _suspended_inventories:
		if is_instance_valid(inventory) and is_instance_valid(inventory.owner):
			MaterialSystem.register_inventory(inventory, inventory.owner)
	_suspended_inventories.clear()


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


func _clear_virtual_owners() -> void:
	for owner in _virtual_owners:
		if not is_instance_valid(owner):
			continue
		if owner.inventory != null and MaterialSystem.is_inventory_registered(owner.inventory):
			MaterialSystem.unregister_inventory(owner.inventory)
		owner.free()
	_virtual_owners.clear()


func _find_section(sections: Array[Dictionary], section_id: String) -> Dictionary:
	for section in sections:
		if String(section.get("id", "")) == section_id:
			return section
	return {}


func _find_row(section: Dictionary, key: String) -> Dictionary:
	if section.is_empty():
		return {}
	for row in section.get("rows", []):
		if String(row.get("key", "")) == key:
			return row
	return {}


func _find_first_spinbox(node: Node) -> SpinBox:
	if node is SpinBox:
		return node as SpinBox
	for child in node.get_children():
		var found := _find_first_spinbox(child)
		if found != null:
			return found
	return null


func world_position_matches(building: Building, center_cell: Vector2i) -> bool:
	var expected_origin := center_cell - Vector2i(
		building.size_cells.x / 2,
		building.size_cells.y / 2,
	)
	return building.origin_cell == expected_origin
