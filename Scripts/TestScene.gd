extends Node2D

## 测试场景：摆一个取水站、一个取食站、一个工作站，再放一群人，
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

## 左上角的状态文字
var _status_label: Label

## 调试用：跑到这一刻数就打印统计并退出（0 表示不启用）
var _max_ticks: int = 0

## 调试用：上一次打印统计的刻数
var _last_report_tick: int = 0

## 调试用：截一张图存到这个路径（空表示不截）
var _shot_path: String = ""

## 调试用：是否已经截图
var _shot_done: bool = false


func _ready() -> void:
	randomize()

	_setup_camera()
	_setup_grid()
	_setup_buildings()
	_setup_humans()
	_setup_ui()


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
	water.name = "取水站"
	add_child(water)
	if not water.place_at(world, WATER_ORIGIN):
		push_error("取水站放不下")

	var food := FoodStation.new()
	food.name = "取食站"
	add_child(food)
	if not food.place_at(world, FOOD_ORIGIN):
		push_error("取食站放不下")

	var work := WorkStation.new()
	work.name = "工作站"
	add_child(work)
	if not work.place_at(world, WORK_ORIGIN):
		push_error("工作站放不下")


func _setup_humans() -> void:
	var world := WorldGridGlobal.world
	for i in range(HUMAN_COUNT):
		var human := Human.new()
		human.name = "居民%d" % (i + 1)

		var cell := Vector2i(
			randi_range(HUMAN_SPAWN_MIN.x, HUMAN_SPAWN_MAX.x),
			randi_range(HUMAN_SPAWN_MIN.y, HUMAN_SPAWN_MAX.y),
		)
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


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)

	_status_label = Label.new()
	_status_label.position = Vector2(12, 8)
	_status_label.add_theme_font_size_override("font_size", 16)
	layer.add_child(_status_label)

	# 调试用：命令行加 `-- --max-ticks=1200` 跑满这么多刻后打印统计并自动退出
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--max-ticks="):
			_max_ticks = arg.trim_prefix("--max-ticks=").to_int()
		elif arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")


func _process(_delta: float) -> void:
	if _status_label == null:
		return

	var day := TickManager.get_day()
	var tick := TickManager.get_tick_of_day()
	var weak := 0
	var at_water := 0
	var at_food := 0
	var working := 0
	var idle := 0

	for h in TickManager.humans:
		if not is_instance_valid(h):
			continue
		if h.is_weak:
			weak += 1
		elif h.goal == Human.Goal.WATER:
			at_water += 1
		elif h.goal == Human.Goal.FOOD:
			at_food += 1
		elif h.goal == Human.Goal.WORK:
			working += 1
		else:
			idle += 1

	_status_label.text = "第 %d 天 第 %d 刻    取水 %d  取食 %d  工作 %d  空闲 %d  虚弱 %d" % [
		day, tick, at_water, at_food, working, idle, weak
	]

	# 调试模式：定期打印一份，跑满 _max_ticks 刻就退出
	if _shot_path != "" and not _shot_done and TickManager.total_ticks >= 60:
		_shot_done = true
		_take_screenshot()

	if _max_ticks <= 0:
		return
	if TickManager.total_ticks - _last_report_tick >= 100:
		_last_report_tick = TickManager.total_ticks
		var line := "[SIM] tick=%d 取水%d 取食%d 工作%d 空闲%d 虚弱%d |" % [
			TickManager.total_ticks, at_water, at_food, working, idle, weak
		]
		for h in TickManager.humans:
			if not is_instance_valid(h):
				continue
			line += " %s(水%.0f,食%.0f,%s/%s,格%s,路%d)%s" % [
				h.name,
				h.water,
				h.food,
				Human.Goal.keys()[h.goal],
				Human.Phase.keys()[h.phase],
				WorldGridGlobal.world.world_to_cell(h.position),
				h.path.size(),
				"虚弱" if h.is_weak else "",
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
