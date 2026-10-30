extends Node2D
class_name Building

## 建筑基类。[br]
## 建筑一定是矩形，占 [member size_cells] 个格子（横向 × 纵向），[br]
## 放置时左上角必须正好落在某一格的左上角（也就是 [member origin_cell] 是格子坐标，天然对齐）。[br]
## [b]出入口：[/b]用相对坐标 [member entrance_offsets] 描述，是相对建筑左上角格子的偏移。[br]
## 规则：出入口必须落在建筑矩形[b]外面[/b]、并且和建筑边相邻（只碰到角不算），[br]
## 这一格本身必须是空地（不能压别的建筑或遮挡物），但可以和别的建筑的出入口重合。[br]
## 建筑本体不能覆盖任何已有建筑的出入口。[br]
## [b]典型用法：[/b][br]
## [codeblock]
## var station := WaterStation.new()
## station.entrance_offsets = [Vector2i(2, -1)]   # 建筑正上方那一格
## if station.place_at(WorldGridGlobal.world, Vector2i(100, 80)):
##     add_child(station)
## [/codeblock]

## 建筑占多少格（横向 × 纵向）
@export var size_cells: Vector2i = Vector2i(4, 3)

## 建筑类型
@export var building_type: GlobalEnum.BuildingType = GlobalEnum.BuildingType.WATER

## 出入口相对坐标（相对左上角格子）
@export var entrance_offsets: Array[Vector2i] = [Vector2i(0, -1)]

## 建筑左上角所在的格子
var origin_cell: Vector2i = Vector2i.ZERO

## 主体颜色（子类里覆盖，用于测试场景里区分）
var body_color: Color = Color(0.6, 0.6, 0.6)

## 显示用的名字（子类里覆盖，放下去时节点名就是它）
var display_name: String = "建筑"

## 是否是「放置预览」（半透明、不注册到 TickManager、不占格子）
var is_preview: bool = false

## 是否已完成放置并占用世界网格（只有成功放置的建筑才注册到 TickManager）
var is_placed: bool = false

## 预览状态下当前格子能不能放，决定描边是绿还是红
var preview_valid: bool = true


## 点一下建筑时发出（预览用的虚影不发）[br]
## 谁需要「选中建筑」就接这个信号，建筑本身不认识详情页。
signal clicked(building: Building)

## 雇佣名单或目标人数发生变化。
signal employment_changed(building: Building)

## 工作周期成功结算后，建筑只在这里接收一次结果。
signal work_result_received(building: Building, result: Dictionary)

## 建筑类型 → 图标贴图（放在 Assets/Icons/ 下，改图标只要换图）
const GLYPH_TEXTURES: Dictionary = {
	GlobalEnum.BuildingType.WATER: preload("res://Assets/Icons/water.png"),
	GlobalEnum.BuildingType.FOOD: preload("res://Assets/Icons/food.png"),
	GlobalEnum.BuildingType.WORK: preload("res://Assets/Icons/work.png"),
	GlobalEnum.BuildingType.WAREHOUSE: preload("res://Assets/Icons/work.png"),
}

## 可选的库存容量。0 表示没有库存能力。
@export var inventory_capacity: int = 0

## 是否为外部公共仓库。
@export var is_warehouse: bool = false

## 是否为可雇佣建筑。
@export var is_hireable: bool = false

## 可设置的目标人数上限。
@export var max_workers: int = 0

## 目标人数。设置时会立即夹到合法范围，实际补招/解雇在下一建筑刻完成。
@export var target_workers: int = 0:
	set(value):
		target_workers = clampi(value, 0, max_workers)

## 默认只雇佣成年人；具体建筑可放宽。
@export var allow_child_workers: bool = false
@export var allow_old_workers: bool = false

## 眩晕、虚弱等临时不能工作是否直接解除雇佣。默认保留关系。
@export var release_on_temporary_disability: bool = false

## 隐藏运行阈值。它不是目标人数下限，也不显示在详情页。
@export var hidden_run_threshold: int = 0

## 当前有效的雇员名单。
var employees: Array[Human] = []

## 可选自带库存。
var inventory: Inventory = null

## 当前建筑使用的正式工作类型；没有工作类型时不开始周期。
var work_type: WorkType = null

## 最近一次成功结算结果和累计次数，供建筑自身或调试面板查询。
var last_work_result: Dictionary = {}
var work_result_count: int = 0

## 主体按钮：既是外观，也是点击区
var _body_button: Button = null

## 顶部深色檐口
var _cornice: ColorRect = null

## 类型图标
var _glyph: TextureRect = null

## 出入口的黄色小广场
var _entrance_marks: Array[ColorRect] = []

## 详情页的板块列表，见 [method build_detail]
var _detail_sections: Array[Dictionary] = []

## 防止 remove() 与 _exit_tree() 重复清算。
var _lifecycle_cleaned: bool = false


func _ready() -> void:
	_ensure_inventory()
	_build_visuals()
	_register_if_placed()


func _exit_tree() -> void:
	if not _lifecycle_cleaned:
		_prepare_for_removal()


## 成功放置且已进入场景树后才登记。失败建筑和预览都不会走到这里。
func _register_if_placed() -> void:
	if not is_placed or is_preview or not is_inside_tree():
		return
	TickManager.register_building(self)


## 每刻由 [TickManager] 调用。基类什么都不做，子类按需要覆盖。
func on_tick() -> void:
	if is_hireable:
		_recheck_employees()
		_adjust_worker_count()


## 居民到达出入口后要在这个建筑里等几刻。基类返回 0，子类覆盖。
func get_wait_ticks() -> int:
	return 0


# ---------------------------------------------------------------------------
# 占地 / 出入口
# ---------------------------------------------------------------------------

## 建筑本体占的所有格子（绝对坐标）
func get_occupied_cells() -> Array[Vector2i]:
	return _get_occupied_cells_at(origin_cell)


## 按指定左上角算出建筑本体会占用的所有格子（不修改状态）。
func _get_occupied_cells_at(origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(origin.x, origin.x + size_cells.x):
		for y in range(origin.y, origin.y + size_cells.y):
			cells.append(Vector2i(x, y))
	return cells


## 候选建筑的占格是否压住了任何已有建筑的出入口。
func _overlaps_existing_entrance(footprint: Dictionary) -> bool:
	for other in TickManager.buildings:
		if not is_instance_valid(other) or other == self:
			continue
		for entrance in other.get_entrance_cells():
			if footprint.has(entrance):
				return true
	return false


## 所有出入口的格子坐标（绝对坐标）
func get_entrance_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset in entrance_offsets:
		cells.append(origin_cell + offset)
	return cells


## 出入口格子的世界坐标（格子中心）
func get_entrance_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for cell in get_entrance_cells():
		positions.append(WorldGridGlobal.world.cell_to_world(cell))
	return positions


## 找一个离 [param from_cell] 最近的出入口，返回它的格子坐标。[br]
## 没有出入口时返回 [param from_cell] 本身（调用方应当判空，这里只是兜底）。
func get_nearest_entrance_cell(from_cell: Vector2i) -> Vector2i:
	var entrances := get_entrance_cells()
	if entrances.is_empty():
		return from_cell

	var best := entrances[0]
	var best_distance := _chebyshev(entrances[0], from_cell)
	for i in range(1, entrances.size()):
		var d := _chebyshev(entrances[i], from_cell)
		if d < best_distance:
			best_distance = d
			best = entrances[i]
	return best


## 判断这一格是不是本建筑的出入口
func is_entrance_cell(cell: Vector2i) -> bool:
	return get_entrance_cells().has(cell)


# ---------------------------------------------------------------------------
# 放置
# ---------------------------------------------------------------------------

## 判断能不能放在 [param origin] 这个格子。不会修改任何状态。[br]
## 检查项：矩形在界内、本体内每格都是空的（没被别的建筑或遮挡物占）、[br]
## 本体不覆盖已有建筑的出入口，且每个自己的出入口在界内、是空地并与建筑边相邻。
func can_place_at(world: WorldGrid, origin: Vector2i) -> bool:
	if size_cells.x <= 0 or size_cells.y <= 0:
		return false

	# 1. 整个矩形必须在世界范围内
	if origin.x < 0 or origin.y < 0:
		return false
	var world_cells := world.get_cells()
	if origin.x + size_cells.x > world_cells.x or origin.y + size_cells.y > world_cells.y:
		return false

	# 2. 本体内每一格都必须是空地，且不能覆盖已有建筑的出入口
	var candidate_cells := _get_occupied_cells_at(origin)
	var footprint: Dictionary = {}
	for cell in candidate_cells:
		if not world.is_walkable(cell):
			return false
		footprint[cell] = true

	if _overlaps_existing_entrance(footprint):
		return false

	# 3. 出入口：界内、在矩形外、和矩形边相邻、本身是空地
	var rect := Rect2i(origin, size_cells)
	for offset in entrance_offsets:
		var cell := origin + offset
		if not world.is_in_bounds(cell):
			return false
		if rect.has_point(cell):
			return false
		if not _is_edge_adjacent(cell, rect):
			return false
		if not world.is_walkable(cell):
			return false

	return true


## 把建筑放到 [param origin] 这一格上。成功返回 [code]true[/code]。[br]
## 放好之后，建筑本体占的格子会被设成不可走，出入口保持可走。[br]
## 只有放置成功后才登记到 [TickManager]。
func place_at(world: WorldGrid, origin: Vector2i) -> bool:
	if not can_place_at(world, origin):
		print_verbose("Building.place_at: %s 无法放在 %s" % [name, origin])
		return false

	origin_cell = origin
	set_cell_origin(origin)

	# 本体占的格子设成不可走
	for cell in get_occupied_cells():
		world.set_walkable(cell, false)

	is_placed = true
	_ensure_inventory()
	if inventory != null:
		MaterialSystem.register_inventory(inventory, self)
	_register_if_placed()
	queue_redraw()
	return true


## 把节点摆到「左上角格子 = [param cell]」的位置（不校验、不占格子，预览也用这个）
func set_cell_origin(cell: Vector2i) -> void:
	origin_cell = cell
	# 节点原点落在左上角格子的左上角，绘制以这个点为基准
	position = WorldGridGlobal.world.cell_to_world(cell) - Vector2(WorldGrid.CELL_SIZE, WorldGrid.CELL_SIZE) * 0.5


# ---------------------------------------------------------------------------
# 外观：用节点堆出来（按钮主体 + 檐口 + 图标 + 出入口）
# ---------------------------------------------------------------------------

## 按 [member size_cells] 生成所有子节点。只在 [method _ready] 里调一次。[br]
## 用节点而不是 [_draw] 画，是为了让主体本身就是一个 [Button]——点击区天然等于建筑大小，[br]
## hover/pressed 状态和以后换贴图也都不用自己算。
func _build_visuals() -> void:
	var cell := float(WorldGrid.CELL_SIZE)
	var size_px := Vector2(size_cells) * cell

	# 投影：稍微往右下错一点，看起来像浮在地上
	var shadow := ColorRect.new()
	shadow.name = "Shadow"
	shadow.color = Color(0.0, 0.0, 0.0, 0.15)
	shadow.position = Vector2(1.4, 2.0)
	shadow.size = size_px
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shadow)

	# 主体：一个铺满整块地的按钮
	var body := Button.new()
	body.name = "Body"
	body.position = Vector2.ZERO
	body.size = size_px
	body.focus_mode = Control.FOCUS_NONE
	body.add_theme_stylebox_override("normal", _make_body_style(Color(0.94, 0.94, 0.91)))
	body.add_theme_stylebox_override("hover", _make_body_style(Color(1.0, 1.0, 0.97)))
	body.add_theme_stylebox_override("pressed", _make_body_style(Color(0.86, 0.88, 0.94)))
	body.pressed.connect(_on_body_pressed)
	add_child(body)
	_body_button = body

	# 檐口：顶部一条深色，让方块看起来像建筑
	var cornice := ColorRect.new()
	cornice.name = "Cornice"
	cornice.color = Color(0.36, 0.37, 0.41)
	cornice.position = Vector2.ZERO
	cornice.size = Vector2(size_px.x, size_px.y * 0.18)
	cornice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(cornice)
	_cornice = cornice

	# 类型图标：从 Assets/Icons 读，按建筑大小等比缩放
	# 注意：size / position 必须在 add_child 之后设——挂上去那一刻 Control 会按贴图原始尺寸
	# 重算一次 size，先设会被盖掉（踩过一次，图标变成 128 像素糊满全屏）
	var symbol_size := minf(size_px.x, size_px.y) * 0.34
	var glyph := TextureRect.new()
	glyph.name = "Glyph"
	glyph.texture = GLYPH_TEXTURES.get(building_type)
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(glyph)
	glyph.size = Vector2(symbol_size, symbol_size)
	glyph.position = Vector2(size_px.x * 0.5 - symbol_size * 0.5, size_px.y * 0.6 - symbol_size * 0.5)
	_glyph = glyph

	# 出入口：黄色格子
	for offset in entrance_offsets:
		var mark := ColorRect.new()
		mark.color = Color(1.0, 0.85, 0.30, 0.75)
		mark.position = Vector2(offset) * cell
		mark.size = Vector2(cell, cell)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(mark)
		_entrance_marks.append(mark)

	_apply_preview_style()


## 生成一份主体样式：纯色底 + 深色描边
func _make_body_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(0.12, 0.13, 0.16)
	style.set_border_width_all(2)
	style.set_corner_radius_all(1)
	return style


## 预览模式：整体半透明，并且不接收鼠标（否则会把点击吃掉，放不下去东西）
func _apply_preview_style() -> void:
	if not is_preview:
		return
	modulate = Color(1.0, 1.0, 1.0, 0.45)
	if _body_button != null:
		_body_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_preview_outline()


## 预览时按「能不能放」换描边颜色：绿 / 红
func _update_preview_outline() -> void:
	if not is_preview or _body_button == null:
		return
	var style := _make_body_style(Color(0.94, 0.94, 0.91, 0.35))
	style.border_color = Color(0.35, 1.0, 0.45) if preview_valid else Color(1.0, 0.35, 0.35)
	style.set_border_width_all(2)
	_body_button.add_theme_stylebox_override("normal", style)
	_body_button.add_theme_stylebox_override("hover", style)
	_body_button.add_theme_stylebox_override("pressed", style)


## 由 [PlacementController] 每帧调用，告诉预览「这一格现在能不能放」
func set_preview_valid(valid: bool) -> void:
	if preview_valid == valid:
		return
	preview_valid = valid
	_update_preview_outline()


## 开关这栋建筑的点选。[br]
## 放置模式下必须关掉：Body 是 Button，会把左键点击吃掉，[br]
## 结果就是「想在这一格放东西」变成「点开了这栋建筑的详情页」，放置也失败。
func set_click_enabled(enabled: bool) -> void:
	if _body_button == null:
		return
	_body_button.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE


func _on_body_pressed() -> void:
	clicked.emit(self)


# ---------------------------------------------------------------------------
# 详情页内容（子类通过下面几个函数加内容 / 藏内容）
# ---------------------------------------------------------------------------

## 每次刷新前由 [method get_detail_sections] 调用，往列表里加内容，子类覆盖它即可。[br]
## [b]这里不要清空[/b]：清空由 [method get_detail_sections] 负责，所以子类先加后加、
## 调不调 [code]super.build_detail()[/code] 都不会把自己的内容清掉。
func build_detail() -> void:
	add_section("status", "状态")
	add_row("status", "建筑类型", GlobalEnum.BuildingType.keys()[building_type])

	if is_hireable:
		add_section("employment", "雇佣")
		add_row("employment", "当前雇员", "%d / %d" % [employees.size(), max_workers])
		add_number_input(
			"employment",
			"目标人数",
			"target_workers",
			0,
			max_workers,
			target_workers,
			set_target_workers,
		)
		add_row(
			"employment",
			"当前班次",
			"工作时间内" if is_work_time() else "下班",
		)

	if inventory != null:
		add_section("inventory", "库存")
		add_row("inventory", "容量", "%d" % inventory.capacity)
		add_row("inventory", "已用体积", "%d" % inventory.get_used_volume())
		add_row("inventory", "已预留体积", "%d" % inventory.reserved_volume)
		add_row("inventory", "可用体积", "%d" % inventory.get_available_volume())
		for item_type in MaterialTypes.get_item_types():
			add_row(
				"inventory",
				MaterialTypes.get_display_name(item_type),
				"%d（锁定 %d）" % [
					inventory.get_item_count(item_type),
					inventory.get_locked_quantity(item_type),
				],
			)


## 给外面（详情页）取一份当前内容。[br]
## 每次调用都重建一遍（建筑数据每刻在变，缓存反而要处理失效），清空动作在这里做。
func get_detail_sections() -> Array[Dictionary]:
	_detail_sections.clear()
	build_detail()
	return _detail_sections


## 加一个板块（板块 id 自己定，用来往里面加行 / 隐藏）
func add_section(id: String, title: String) -> void:
	_detail_sections.append({"id": id, "title": title, "hidden": false, "rows": []})


## 往某个板块里加一行。[param key] 是给 [method hide_row] 用的标识，不填就用 label。
func add_row(section_id: String, label: String, value: String, key: String = "") -> void:
	for section in _detail_sections:
		if section["id"] == section_id:
			section["rows"].append({
				"key": key if key != "" else label,
				"label": label,
				"value": value,
				"kind": "text",
				"hidden": false,
			})
			return
	push_warning("add_row：没有 %s 这个板块" % section_id)


## 添加一行通用数字输入控件。UI 不识别具体建筑，只读取范围、当前值和写入回调。
func add_number_input(
	section_id: String,
	label: String,
	key: String,
	minimum: int,
	maximum: int,
	value: int,
	on_changed: Callable,
) -> void:
	for section in _detail_sections:
		if section["id"] == section_id:
			section["rows"].append({
				"key": key,
				"label": label,
				"value": "",
				"kind": "number",
				"min": minimum,
				"max": maximum,
				"current": value,
				"on_changed": on_changed,
				"hidden": false,
			})
			return
	push_warning("add_number_input：没有 %s 这个板块" % section_id)


## 整个板块不显示
func hide_section(id: String) -> void:
	for section in _detail_sections:
		if section["id"] == id:
			section["hidden"] = true


## 某一行不显示（板块里其它行照常）
func hide_row(section_id: String, key: String) -> void:
	for section in _detail_sections:
		if section["id"] != section_id:
			continue
		for row in section["rows"]:
			if row["key"] == key:
				row["hidden"] = true


# ---------------------------------------------------------------------------
# 内部工具
# ---------------------------------------------------------------------------

## 切比雪夫距离（八方向步子数），用来比较「哪个出入口更近」
func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## [param cell] 是否和矩形 [param rect] 边相邻（四邻域，不含斜角）
func _is_edge_adjacent(cell: Vector2i, rect: Rect2i) -> bool:
	return (
		rect.has_point(cell + Vector2i.LEFT)
		or rect.has_point(cell + Vector2i.RIGHT)
		or rect.has_point(cell + Vector2i.UP)
		or rect.has_point(cell + Vector2i.DOWN)
	)

## 逻辑等待补全！！！
func remove() -> void:
	_prepare_for_removal()
	queue_free()


# ---------------------------------------------------------------------------
# 可选能力：雇佣、班次、库存与工作结果
# ---------------------------------------------------------------------------

func _ensure_inventory() -> void:
	if inventory_capacity <= 0:
		inventory = null
		return
	if inventory == null:
		inventory = Inventory.new(inventory_capacity)
	else:
		inventory.capacity = inventory_capacity


func can_accept_employee(human: Human) -> bool:
	if not is_hireable or not is_placed:
		return false
	if not is_instance_valid(human) or not human.is_inside_tree():
		return false
	if human.employer != null and human.employer != self:
		return false
	if employees.has(human):
		return false
	return can_accept_age(human)


func is_employee_eligible(human: Human) -> bool:
	if not is_instance_valid(human) or not human.is_inside_tree():
		return false
	if human.employer != self:
		return false
	if release_on_temporary_disability and not human.buff_system.can_work():
		return false
	return can_accept_age(human)


func can_accept_age(human: Human) -> bool:
	if not is_instance_valid(human):
		return false
	match human.age_status:
		GlobalEnum.AgeStatus.CHILD:
			return allow_child_workers
		GlobalEnum.AgeStatus.OLD:
			return allow_old_workers
		_:
			return true


func hire_employee(human: Human) -> bool:
	if not can_accept_employee(human):
		return false
	employees.append(human)
	human.bind_employer(self)
	employment_changed.emit(self)
	return true


func dismiss_employee(human: Human, reason: String = "雇佣结束") -> bool:
	if not employees.has(human):
		return false
	employees.erase(human)
	if is_instance_valid(human):
		human.notify_employment_ended(self, reason)
	employment_changed.emit(self)
	return true


func set_target_workers(value: int) -> void:
	target_workers = value
	employment_changed.emit(self)


func get_employee_count() -> int:
	return employees.size()


func is_work_time(tick_of_day: int = -1) -> bool:
	var tick := TickManager.get_tick_of_day() if tick_of_day < 0 else tick_of_day
	@warning_ignore("integer_division")
	var start_tick := TickManager.TICKS_PER_DAY / 3
	@warning_ignore("integer_division")
	var end_tick := (TickManager.TICKS_PER_DAY * 5) / 6
	return tick >= start_tick and tick < end_tick


func accept_work_result(result: Dictionary) -> bool:
	if not is_placed or result.is_empty():
		return false
	last_work_result = result.duplicate(true)
	work_result_count += 1
	work_result_received.emit(self, result)
	return true


## 普通存入。仓库接受任何合法物品；自带库存只接受本建筑自己的产出。
func try_deposit_items(
	items_to_add: Dictionary,
	producer: Building = null,
) -> bool:
	_ensure_inventory()
	if inventory == null:
		return false
	if not is_warehouse and producer != self:
		return false
	return inventory.add_items_unchecked(items_to_add)


## 任何居民都可以取用未锁定物品；被锁定数量会由 MaterialSystem 排除。
func try_withdraw_items(
	item_type: int,
	quantity: int,
	holder: String,
) -> bool:
	_ensure_inventory()
	if inventory == null:
		return false
	return MaterialSystem.withdraw_items(inventory, item_type, quantity, holder)


func _recheck_employees() -> void:
	var invalid: Array[Human] = []
	for human in employees:
		if not is_employee_eligible(human):
			invalid.append(human)
	for human in invalid:
		dismiss_employee(human, "永久雇佣资格失效")


func _adjust_worker_count() -> void:
	var target := clampi(target_workers, 0, max_workers)
	if employees.size() > target:
		_dismiss_excess(employees.size() - target)
	elif employees.size() < target:
		_fill_vacancies(target - employees.size())


func _fill_vacancies(vacancy_count: int) -> void:
	for human in TickManager.humans:
		if vacancy_count <= 0:
			break
		if hire_employee(human):
			vacancy_count -= 1


func _dismiss_excess(excess_count: int) -> void:
	while excess_count > 0 and not employees.is_empty():
		var index := randi_range(0, employees.size() - 1)
		dismiss_employee(employees[index], "目标人数降低")
		excess_count -= 1


func _prepare_for_removal() -> void:
	if _lifecycle_cleaned:
		return
	_lifecycle_cleaned = true

	if not MaterialSystem.is_scene_shutdown():
		var current_employees := employees.duplicate()
		for human in current_employees:
			dismiss_employee(human, "雇主建筑已删除")

	TickManager.unregister_building(self)

	if is_placed:
		var world := WorldGridGlobal.world
		for cell in get_occupied_cells():
			if world.is_in_bounds(cell):
				world.set_walkable(cell, true)

	_ensure_inventory()
	if inventory != null:
		MaterialSystem.cleanup_owner_inventory(self, origin_cell, display_name)
	is_placed = false
	employees.clear()
