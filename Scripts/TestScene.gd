## 集成测试场景。[br]
## 在 [World] 基础设施上创建取水、取食、工作站和仓库，并生成不同年龄居民验证完整模拟循环。[br]
## 自动放置、Buff 自检、完整验收、截图和 UI 演示等调试入口只允许保留在测试场景。
extends World

## 放多少个居民
const HUMAN_COUNT: int = 8

## 建筑摆在世界中心附近（格坐标，左上角）
const WATER_ORIGIN := Vector2i(464, 492)

## 取食站初始左上角格子。
const FOOD_ORIGIN := Vector2i(469, 492)

## 废料分拣站初始左上角格子。
const WORK_ORIGIN := Vector2i(474, 492)

## 仓库初始左上角格子。
const WAREHOUSE_ORIGIN := Vector2i(481, 492)

## 人散落在这个矩形范围内（格坐标，含两端）
const HUMAN_SPAWN_MIN := Vector2i(466, 496)

## 居民出生范围右下角（含），与 [constant HUMAN_SPAWN_MIN] 共同定义闭区间。
const HUMAN_SPAWN_MAX := Vector2i(470, 498)

# 左上角的调试面板实例。
var _debug_ui: DebugUI

# 测试场景的放置控制器实例。
var _placer: PlacementController

# 自动退出前运行的模拟刻数；0 表示不启用。
var _max_ticks: int = 0

# 上一次打印模拟统计时的累计刻数。
var _last_report_tick: int = 0

# 截图输出路径；空字符串表示不截图。
var _shot_path: String = ""

# 本次运行是否已经执行截图。
var _shot_done: bool = false

# 是否启用自动放置链路检查。
var _autoplace: bool = false

# 是否启用 [BuffSelfTest]。
var _bufftest: bool = false

# 是否启用完整验收自检。
var _acceptance: bool = false

# UI 演示目标；空字符串表示关闭。
var _ui_demo: String = ""

## 集成场景中的废料分拣站，供验收和详情演示使用。
var scrap_sorting_station: ScrapSortingStation = null

## 集成场景中的公共仓库，供验收和详情演示使用。
var warehouse: Warehouse = null


## 解析测试参数、初始化世界与测试设施，并按参数挂载调试自检节点。
func _ready() -> void:
	_parse_early_args()
	randomize()
	if _acceptance:
		TickManager.auto_run = false
	# 相机和网格由 World 负责，本场景只加自己的东西
	super._ready()

	_setup_buildings()
	_setup_humans()
	_setup_placement()
	_setup_ui()

	if _ui_demo != "":
		_open_ui_demo.call_deferred()
	if _autoplace:
		_auto_test_placement.call_deferred()
	if _bufftest:
		var self_test := BuffSelfTest.new()
		self_test.name = "BuffSelfTest"
		add_child(self_test)
	if _acceptance:
		var acceptance := AcceptanceSelfTest.new()
		acceptance.name = "AcceptanceSelfTest"
		add_child(acceptance)


## 在创建测试设施前解析必须提前生效的验收参数。
func _parse_early_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--acceptance":
			_acceptance = true


## 放置测试用取水站、取食站、工作站和仓库，并填充初始物资。
func _setup_buildings() -> void:
	var world := WorldGridGlobal.world

	# 先创建补给站，保证居民后续能够形成取水和取食行为。
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

	# 工作站和仓库保留为字段，供验收、统计和 UI 演示重复读取。
	scrap_sorting_station = ScrapSortingStation.new()
	scrap_sorting_station.name = scrap_sorting_station.display_name
	add_child(scrap_sorting_station)
	if not scrap_sorting_station.place_at(world, WORK_ORIGIN):
		push_error("%s 放不下" % scrap_sorting_station.display_name)
	else:
		scrap_sorting_station.inventory.add_items_unchecked({
			MaterialTypes.ItemType.METAL: 30,
			MaterialTypes.ItemType.PLASTIC: 30,
		})

	warehouse = Warehouse.new()
	warehouse.name = warehouse.display_name
	add_child(warehouse)
	if not warehouse.place_at(world, WAREHOUSE_ORIGIN):
		push_error("%s 放不下" % warehouse.display_name)
	else:
		warehouse.inventory.add_items_unchecked({
			MaterialTypes.ItemType.WASTE: 20,
			MaterialTypes.ItemType.METAL: 30,
			MaterialTypes.ItemType.PLASTIC: 30,
			MaterialTypes.ItemType.WIRE: 10,
		})


## 在出生范围内生成不同年龄阶段的居民，并避免重复占用同一格。
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


## 在出生范围里随机挑一格还没被占用的[br]
## [param used_cells] 是本次生成过程中已经被占用的格子列表。[br]
## 返回未使用的出生格；尝试次数耗尽时返回 [code](-1, -1)[/code]。
func _pick_free_cell(used_cells: Array[Vector2i]) -> Vector2i:
	for attempt in range(300):
		var cell := Vector2i(
			randi_range(HUMAN_SPAWN_MIN.x, HUMAN_SPAWN_MAX.x),
			randi_range(HUMAN_SPAWN_MIN.y, HUMAN_SPAWN_MAX.y),
		)
		if not used_cells.has(cell):
			return cell
	return Vector2i(-1, -1)


## 创建调试 UI 与放置控制器之间的信号连接，并解析剩余测试参数。
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
		elif arg == "--acceptance":
			_acceptance = true
		elif arg.begins_with("--ui-demo="):
			_ui_demo = arg.trim_prefix("--ui-demo=")
		elif arg.begins_with("--ghost="):
			# 调试用：把放置预览钉在某一格，方便截图（参数形如 --ghost=477,500）
			var parts := arg.trim_prefix("--ghost=").split(",")
			if parts.size() == 2:
				_placer.select_kind(PlacementController.Kind.WATER)
				_placer.debug_hover_cell = Vector2i(parts[0].to_int(), parts[1].to_int())


## 打开参数指定的建筑详情页，并把建筑预览固定到截图位置。
func _open_ui_demo() -> void:
	var panel := get_node_or_null("BuildingDetailPanel") as BuildingDetailPanel
	if panel == null:
		return
	match _ui_demo:
		"warehouse":
			panel.show_building(warehouse)
		_:
			panel.show_building(scrap_sorting_station)
	_placer.select_kind(PlacementController.Kind.WAREHOUSE)
	_placer.debug_hover_cell = Vector2i(490, 510)


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


## 创建测试场景使用的放置控制器。
func _setup_placement() -> void:
	_placer = PlacementController.new()
	_placer.name = "Placement"
	add_child(_placer)


## 把调试 UI 的建造选择转发给放置控制器。[br]
## [param kind] 是 [enum PlacementController.Kind] 中的放置类型。
func _on_kind_selected(kind: int) -> void:
	_placer.select_kind(kind)


## 每帧刷新居民状态统计，处理截图、周期日志和自动退出。[br]
## [param _delta] 是当前帧间隔；统计按模拟刻读取，因此本方法不使用该值。
func _process(_delta: float) -> void:
	if _debug_ui == null:
		return

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

	# 调试面板按动作状态和目标共同归类，工作与脱困状态优先于目标类别。
	_debug_ui.set_stats("取水 %d   取食 %d\n上班路上 %d   站内 %d\n脱困 %d   空闲 %d" % [
		at_water, at_food, going_work, inside_work, relocating, idle
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
		MaterialSystem.begin_scene_shutdown()
		get_tree().quit()


## 调试用：把当前画面存成 png
func _take_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_shot_path)
	print("[SHOT] %s -> %s" % [_shot_path, "成功" if err == OK else "失败 %d" % err])
