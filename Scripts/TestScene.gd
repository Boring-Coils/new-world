extends World

## 测试场景：在 [World] 的空世界（相机 + 网格）之上，摆一个取水站、一个取食站、[br]
## 一个工作站，再放一群人，用来验证网格寻路、每刻消耗、补水补食和上班进站这一整套循环。[br]
## [b]只有调试用的东西[/b]（统计面板、自动放置断言、buff 自检）允许留在这里；[br]
## 真正的游戏规则请放 Colony 那一层。

## 放多少个居民
const HUMAN_COUNT: int = 8

## 建筑摆在世界中心附近（格坐标，左上角）
const WATER_ORIGIN := Vector2i(464, 492)
const FOOD_ORIGIN := Vector2i(469, 492)
const WORK_ORIGIN := Vector2i(474, 492)

## 人散落在这个矩形范围内（格坐标，含两端）
const HUMAN_SPAWN_MIN := Vector2i(466, 496)
const HUMAN_SPAWN_MAX := Vector2i(470, 498)

## 左上角的调试面板
var _debug_ui: DebugUI

## 放置控制器
var _placer: PlacementController

## 调试用：跑到这一刻数就打印统计并退出（0 表示不启用）
var _max_ticks: int = 0

## 调试用：上一次打印统计的刻数
var _last_report_tick: int = 0

## 调试用：截一张图存到这个路径（空表示不截）
var _shot_path: String = ""

## 调试用：是否已经截图
var _shot_done: bool = false

## 调试用：启动后自动放一套建筑和居民，验证放置链路
var _autoplace: bool = false

## 调试用：buff 自检（--bufftest），具体逻辑在 [BuffSelfTest]
var _bufftest: bool = false


func _ready() -> void:
	randomize()
	# 相机和网格由 World 负责，本场景只加自己的东西
	super._ready()

	_setup_buildings()
	_setup_humans()
	_setup_placement()
	_setup_ui()

	if _autoplace:
		_auto_test_placement.call_deferred()
	if _bufftest:
		var self_test := BuffSelfTest.new()
		self_test.name = "BuffSelfTest"
		add_child(self_test)


func _setup_buildings() -> void:
	var world := WorldGridGlobal.world

	var water := WaterStation.new()
	water.name = water.display_name
	add_child(water)
	if not water.place_at(world, WATER_ORIGIN):
		push_error("%s 放不下" % water.display_name)

	var food := FoodStation.new()
	food.name = food.display_name
	add_child(food)
	if not food.place_at(world, FOOD_ORIGIN):
		push_error("%s 放不下" % food.display_name)

	var work := WorkStation.new()
	work.name = work.display_name
	add_child(work)
	if not work.place_at(world, WORK_ORIGIN):
		push_error("%s 放不下" % work.display_name)


func _setup_humans() -> void:
	var world := WorldGridGlobal.world
	var used_cells: Array[Vector2i] = []

	for i in range(HUMAN_COUNT):
		var human := Human.create()
		human.name = "居民%d" % (i + 1)

		# 一人一格，避免两个人叠在同一个位置（画面上会「少人」）
		var cell := _pick_free_cell(used_cells)
		if cell == Vector2i(-1, -1):
			push_warning("出生点不够用了，居民%d 没放出来" % (i + 1))
			human.free()
			break
		used_cells.append(cell)
		human.position = world.cell_to_world(cell)

		# 混合不同年龄段，顺便验证速度和日耗的差异
		match i % 3:
			0:
				human.age_status = GlobalEnum.AgeStatus.CHILD
				human.age = 12
			1:
				human.age_status = GlobalEnum.AgeStatus.ADULT
				human.age = 30
			2:
				human.age_status = GlobalEnum.AgeStatus.OLD
				human.age = 70

		add_child(human)

	print("[SPAWN] %d 个居民放在 %d 个不同格子上" % [TickManager.humans.size(), used_cells.size()])


## 在出生范围里随机挑一格还没被占用的
func _pick_free_cell(used_cells: Array[Vector2i]) -> Vector2i:
	for attempt in range(300):
		var cell := Vector2i(
			randi_range(HUMAN_SPAWN_MIN.x, HUMAN_SPAWN_MAX.x),
			randi_range(HUMAN_SPAWN_MIN.y, HUMAN_SPAWN_MAX.y),
		)
		if not used_cells.has(cell):
			return cell
	return Vector2i(-1, -1)


func _setup_ui() -> void:
	_debug_ui = DebugUI.new()
	_debug_ui.name = "DebugUI"
	add_child(_debug_ui)
	_debug_ui.kind_selected.connect(_on_kind_selected)
	_placer.notice.connect(_debug_ui.set_hint)

	# 调试用：命令行加 `-- --max-ticks=1200` 跑满这么多刻后打印统计并自动退出
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--max-ticks="):
			_max_ticks = arg.trim_prefix("--max-ticks=").to_int()
		elif arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
		elif arg == "--autoplace":
			_autoplace = true
		elif arg == "--bufftest":
			_bufftest = true
		elif arg.begins_with("--ghost="):
			# 调试用：把放置预览钉在某一格，方便截图（参数形如 --ghost=477,500）
			var parts := arg.trim_prefix("--ghost=").split(",")
			if parts.size() == 2:
				_placer.select_kind(PlacementController.Kind.WATER)
				_placer.debug_hover_cell = Vector2i(parts[0].to_int(), parts[1].to_int())


## 调试用：自动放一个取水站、一个居民，再故意重叠放一次，验证「能放 / 不能放」两条路
func _auto_test_placement() -> void:
	var world := WorldGridGlobal.world
	var buildings_before := TickManager.buildings.size()
	var humans_before := TickManager.humans.size()

	# 失败建筑即使已进入场景树，也不应注册到 TickManager
	var failed_building := WaterStation.new()
	add_child(failed_building)
	var buildings_before_failed_place := TickManager.buildings.size()
	var failed_place_ok := failed_building.place_at(world, Vector2i(-100, -100))
	var failed_place_registered := TickManager.buildings.has(failed_building)
	var failed_place_count_ok := TickManager.buildings.size() == buildings_before_failed_place
	print("[AUTOPLACE] 非法放置(应 false)=%s 已注册(应 false)=%s 建筑未增加=%s is_placed=%s" % [
		failed_place_ok,
		failed_place_registered,
		failed_place_count_ok,
		failed_building.is_placed,
	])
	failed_building.free()

	_placer.select_kind(PlacementController.Kind.WATER)
	var water_ok := _placer.place_at_cell(Vector2i(500, 520))

	_placer.select_kind(PlacementController.Kind.HUMAN)
	var human_ok := _placer.place_at_cell(Vector2i(503, 523))

	# 同一格再放一次水站，应当失败
	_placer.select_kind(PlacementController.Kind.WATER)
	var overlap_ok := _placer.place_at_cell(Vector2i(500, 520))

	# 出入口压住建筑，也应当失败
	_placer.select_kind(PlacementController.Kind.FOOD)
	var blocked_ok := _placer.place_at_cell(Vector2i(500, 522))

	# 本体压住已有水站出入口（但不压住水站本体），也应当失败
	var old_entrance := Vector2i(499, 522)
	var entrance_was_walkable := world.is_walkable(old_entrance)
	var buildings_before_entrance_test := TickManager.buildings.size()
	_placer.select_kind(PlacementController.Kind.WATER)
	var entrance_cover_ok := _placer.place_at_cell(Vector2i(499, 523))
	var entrance_still_walkable := world.is_walkable(old_entrance)
	var entrance_test_count_ok := TickManager.buildings.size() == buildings_before_entrance_test
	var entrance_still_reachable := not world.get_path(Vector2i(500, 522), old_entrance).is_empty()
	print("[AUTOPLACE] 本体压已有出入口(应 false)=%s 原出入口仍可走=%s 建筑未增加=%s 仍可达=%s" % [
		entrance_cover_ok,
		entrance_was_walkable and entrance_still_walkable,
		entrance_test_count_ok,
		entrance_still_reachable,
	])

	# 两栋建筑的出入口重合仍然允许
	_placer.select_kind(PlacementController.Kind.FOOD)
	var entrance_overlap_ok := _placer.place_at_cell(Vector2i(499, 524))
	print("[AUTOPLACE] 出入口重叠(应 true)=%s" % entrance_overlap_ok)

	_placer.select_kind(PlacementController.Kind.NONE)

	print("[AUTOPLACE] 水站=%s 居民=%s 重叠(应 false)=%s 压建筑(应 false)=%s" % [
		water_ok, human_ok, overlap_ok, blocked_ok
	])

	# 故意把建筑放在居民站的那一格：建筑应当能放，人被挤出来
	var victim := TickManager.humans[-1]
	var before_pos := victim.position
	var human_cell := WorldGridGlobal.world.world_to_cell(before_pos)
	_placer.select_kind(PlacementController.Kind.WATER)
	var on_human_ok := _placer.place_at_cell(human_cell)
	# StateChart 延迟进入初始状态，pending 脱困请求要到后续 tick 才会派发。
	var moved_ok := false
	for _wait_tick in range(3):
		await TickManager.tick_advanced
		var victim_snapshot := victim.ai.get_debug_snapshot()
		moved_ok = (
			bool(victim_snapshot["relocating"])
			or victim.position != before_pos
		)
		if moved_ok:
			break
	print("[AUTOPLACE] 压着居民放建筑=%s（应 true） 居民被挤出来=%s（应 true）" % [on_human_ok, moved_ok])

	print("[AUTOPLACE] 建筑 %d -> %d，居民 %d -> %d" % [
		buildings_before, TickManager.buildings.size(), humans_before, TickManager.humans.size()
	])


func _setup_placement() -> void:
	_placer = PlacementController.new()
	_placer.name = "Placement"
	add_child(_placer)


func _on_kind_selected(kind: int) -> void:
	_placer.select_kind(kind)


func _process(_delta: float) -> void:
	if _debug_ui == null:
		return

	var day := TickManager.get_day()
	var tick := TickManager.get_tick_of_day()
	var at_water := 0
	var at_food := 0
	var going_work := 0
	var inside_work := 0
	var relocating := 0
	var idle := 0

	for h in TickManager.humans:
		if not is_instance_valid(h):
			continue
		var snapshot := h.ai.get_debug_snapshot()
		match snapshot["state"]:
			&"working":
				inside_work += 1
			&"relocating":
				relocating += 1
			&"idle":
				idle += 1
			_:
				match int(snapshot["goal"]):
					HumanAI.Goal.WATER:
						at_water += 1
					HumanAI.Goal.FOOD:
						at_food += 1
					HumanAI.Goal.WORK:
						going_work += 1
					_:
						idle += 1

	_debug_ui.set_stats("第 %d 天 第 %d 刻\n取水 %d   取食 %d\n上班路上 %d   站内 %d\n脱困 %d   空闲 %d" % [
		day, tick, at_water, at_food, going_work, inside_work, relocating, idle
	])

	# 调试模式：定期打印一份，跑满 _max_ticks 刻就退出

	var ready_for_shot := TickManager.total_ticks >= 12
	if _placer != null and _placer.debug_hover_cell.x >= 0 and TickManager.total_ticks >= 10:
		ready_for_shot = true
	if _shot_path != "" and not _shot_done and ready_for_shot:
		_shot_done = true
		_take_screenshot()

	if _max_ticks <= 0:
		return
	if TickManager.total_ticks - _last_report_tick >= 100:
		_last_report_tick = TickManager.total_ticks
		var line := "[SIM] tick=%d 取水%d 取食%d 上班%d 站内%d 脱困%d 空闲%d |" % [
			TickManager.total_ticks,
			at_water,
			at_food,
			going_work,
			inside_work,
			relocating,
			idle,
		]
		for h in TickManager.humans:
			if not is_instance_valid(h):
				continue
			var snapshot := h.ai.get_debug_snapshot()
			line += " %s(水%.0f,食%.0f,%s/%s,格%s,路%d)" % [
				h.name,
				h.water,
				h.food,
				snapshot["goal_name"],
				snapshot["state"],
				WorldGridGlobal.world.world_to_cell(h.position),
				snapshot["path_size"],
			]
		print(line)

	if TickManager.total_ticks >= _max_ticks:
		print("[SIM] 结束，共 %d 刻（%.1f 天）" % [_max_ticks, _max_ticks / float(TickManager.TICKS_PER_DAY)])
		get_tree().quit()


## 调试用：把当前画面存成 png
func _take_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_shot_path)
	print("[SHOT] %s -> %s" % [_shot_path, "成功" if err == OK else "失败 %d" % err])
