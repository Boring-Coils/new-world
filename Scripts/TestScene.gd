extends Node2D

## 测试场景：摆一个取水站、一个取食站、一个工作站，再放一群人，[br]
## 用来验证网格寻路、每刻消耗、补水补食和上班进站这一整套循环。

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

## 调试用：buff 自检，跑到几个固定刻数时加 buff 并打印期望值对照（--bufftest）
var _bufftest: bool = false

## 调试用：buff 自检的阶段性标记
var _buff_applied: bool = false
var _buff_expiry_checked: bool = false
var _buff_final_checked: bool = false

## 调试用：口渴 buff 的引用，用来在它被移除后还能读到累积扣水量
var _thirst_buff: Thirst = null

## 调试用：口渴 buff 最后一次读到的累计扣水量
var _thirst_total: float = 0.0

## 调试用：眩晕期间有没有人还跑去上班（应该始终 false）
var _buff_stun_violation: bool = false


func _ready() -> void:
	randomize()

	_setup_camera()
	_setup_grid()
	_setup_buildings()
	_setup_humans()
	_setup_placement()
	_setup_ui()

	if _autoplace:
		_auto_test_placement.call_deferred()


func _setup_camera() -> void:
	var camera := Camera2D.new()
	camera.name = "Camera"
	# 对着建筑群中心
	camera.position = Vector2(471.0, 496.0) * WorldGrid.CELL_SIZE
	camera.zoom = Vector2(4.0, 4.0)
	add_child(camera)
	camera.make_current()


func _setup_grid() -> void:
	var grid := GridDisplay.new()
	grid.name = "GridDisplay"
	# 画在人和建筑下面
	grid.z_index = -10
	add_child(grid)


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
	var buildings_before := TickManager.buildings.size()
	var humans_before := TickManager.humans.size()

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
	var moved_ok: bool = victim._is_relocating or victim.position != before_pos
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
	var idle := 0

	for h in TickManager.humans:
		if not is_instance_valid(h):
			continue
		if h.phase == Human.Phase.INSIDE_WORK:
			# 已经进门了，模型是隐藏的，单独列出来
			inside_work += 1
		elif h.goal == Human.Goal.WATER:
			at_water += 1
		elif h.goal == Human.Goal.FOOD:
			at_food += 1
		elif h.goal == Human.Goal.WORK:
			going_work += 1
		else:
			idle += 1

	_debug_ui.set_stats("第 %d 天 第 %d 刻\n取水 %d   取食 %d\n上班路上 %d   站内 %d\n空闲 %d" % [
		day, tick, at_water, at_food, going_work, inside_work, idle
	])

	# 调试模式：定期打印一份，跑满 _max_ticks 刻就退出
	_run_buff_test()

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
		var line := "[SIM] tick=%d 取水%d 取食%d 上班%d 站内%d 空闲%d |" % [
			TickManager.total_ticks, at_water, at_food, going_work, inside_work, idle
		]
		for h in TickManager.humans:
			if not is_instance_valid(h):
				continue
			line += " %s(水%.0f,食%.0f,%s/%s,格%s,路%d)" % [
				h.name,
				h.water,
				h.food,
				Human.Goal.keys()[h.goal],
				Human.Phase.keys()[h.phase],
				WorldGridGlobal.world.world_to_cell(h.position),
				h.path.size(),
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


## 调试快捷键：空格暂停/继续，数字 1~4 切倍速
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		TickManager.auto_run = not TickManager.auto_run
		print("[SIM] 时间%s" % ("继续" if TickManager.auto_run else "暂停"))
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				TickManager.speed_multiplier = 1.0
			KEY_2:
				TickManager.speed_multiplier = 2.0
			KEY_3:
				TickManager.speed_multiplier = 5.0
			KEY_4:
				TickManager.speed_multiplier = 20.0
			_:
				return
		print("[SIM] 倍速 x%.0f" % TickManager.speed_multiplier)


# ---------------------------------------------------------------------------
# buff 自检（--bufftest，测完连同下面几个函数一起删）
# ---------------------------------------------------------------------------

## 取第几个居民，越界返回 null
func _get_human(index: int) -> Human:
	if index < 0 or index >= TickManager.humans.size():
		return null
	var h := TickManager.humans[index]
	if not is_instance_valid(h):
		return null
	return h


## buff 自检：加三种 buff，在三个时间点打印「期望 vs 实际」。[br]
## 用法：[code]-- --speed=20 --bufftest --max-ticks=140[/code][br]
## 覆盖四件事：数值倍率（疲劳）、行为闸门（眩晕）、每刻逻辑（口渴）、重复添加与自动到期。[br]
## 速度那里用「反推随机偏移」来验倍率：居民 1 是儿童，基础速度算得出来，[br]
## 反推值落回 0.9~1.1 就说明倍率确实乘上去了。
func _run_buff_test() -> void:
	if not _bufftest:
		return
	var tick := TickManager.total_ticks

	# 口渴到期那一刻节点就被移除了，先趁它还活着把累计值抄出来
	if _thirst_buff != null and is_instance_valid(_thirst_buff):
		_thirst_total = _thirst_buff.drained_total

	# 眩晕期间不该出现「去上班」这个目标
	if _buff_applied:
		var watched := _get_human(1)
		if watched != null and watched.goal == Human.Goal.WORK:
			_buff_stun_violation = true

	if not _buff_applied and tick >= 10:
		_buff_applied = true
		var tired := _get_human(0)
		var stunned := _get_human(1)
		var thirsty := _get_human(2)
		if tired == null or stunned == null or thirsty == null:
			print("[BUFF] 居民数量不足，跳过自检")
			return

		# 疲劳加两次：第一次新建，第二次走 reapply（层数 +1、时长刷满）
		tired.buff_system.add_buff(GlobalEnum.BuffType.FATIGUE, {"duration": 120, "intensity": 0.5})
		var fatigue := tired.buff_system.add_buff(GlobalEnum.BuffType.FATIGUE, {"duration": 120, "intensity": 0.5})
		stunned.buff_system.add_buff(GlobalEnum.BuffType.STUN, {"duration": 120})
		_thirst_buff = thirsty.buff_system.add_buff(GlobalEnum.BuffType.THIRST, {"duration": 40, "drain": 5.0}) as Thirst

		print("[BUFF] 疲劳 层数=%d（期望 2）速度倍率=%.2f（期望 0.10）" % [
			fatigue.stacks, tired.buff_system.get_speed_multiplier()
		])
		print("[BUFF] 眩晕 can_work=%s（期望 false）速度倍率=%.2f（期望 0.50）" % [
			stunned.buff_system.can_work(), stunned.buff_system.get_speed_multiplier()
		])
		print("[BUFF] 口渴 每刻扣水=%.1f（期望 5.0）时长=%d（期望 40）" % [
			_thirst_buff.drain, _thirst_buff.duration
		])

	if _buff_applied and not _buff_expiry_checked and tick >= 60:
		_buff_expiry_checked = true
		var thirsty := _get_human(2)
		print("[BUFF] 口渴已自动移除=%s（期望 true）累计额外扣水=%.1f（期望 200.0）" % [
			not thirsty.buff_system.has_buff(GlobalEnum.BuffType.THIRST), _thirst_total
		])

	if _buff_applied and not _buff_final_checked and tick >= 100:
		_buff_final_checked = true
		var tired := _get_human(0)
		var stunned := _get_human(1)
		var normal := _get_human(3)
		var base_child := Human.WALK_CELLS_PER_DAY * Human.CHILD_SPEED_SCALE / float(TickManager.TICKS_PER_DAY)
		var tired_speed := tired.get_speed_cells_per_tick()
		var normal_speed := normal.get_speed_cells_per_tick()

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
		print("[BUFF] 眩晕期间跑去上班=%s（期望 false）" % _buff_stun_violation)
