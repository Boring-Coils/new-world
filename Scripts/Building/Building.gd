extends Node2D
class_name Building

## 建筑基类。[br]
## 建筑一定是矩形，占 [member size_cells] 个格子（横向 × 纵向），[br]
## 放置时左上角必须正好落在某一格的左上角（也就是 [member origin_cell] 是格子坐标，天然对齐）。[br]
## [b]出入口：[/b]用相对坐标 [member entrance_offsets] 描述，是相对建筑左上角格子的偏移。[br]
## 规则：出入口必须落在建筑矩形[b]外面[/b]、并且和建筑边相邻（只碰到角不算），[br]
## 这一格本身必须是空地（不能压别的建筑或遮挡物），但可以和别的建筑的出入口重合。[br]
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

## 预览状态下当前格子能不能放，决定描边是绿还是红
var preview_valid: bool = true


## 点一下建筑时发出（预览用的虚影不发）[br]
## 谁需要「选中建筑」就接这个信号，建筑本身不认识详情页。
signal clicked(building: Building)

## 建筑类型 → 图标贴图（放在 Assets/Icons/ 下，改图标只要换图）
const GLYPH_TEXTURES: Dictionary = {
	GlobalEnum.BuildingType.WATER: preload("res://Assets/Icons/water.png"),
	GlobalEnum.BuildingType.FOOD: preload("res://Assets/Icons/food.png"),
	GlobalEnum.BuildingType.WORK: preload("res://Assets/Icons/work.png"),
}

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


func _ready() -> void:
	_build_visuals()
	if not is_preview:
		TickManager.register_building(self)


func _exit_tree() -> void:
	TickManager.unregister_building(self)


## 每刻由 [TickManager] 调用。基类什么都不做，子类按需要覆盖。
func on_tick() -> void:
	pass


## 居民到达出入口后要在这个建筑里等几刻。基类返回 0，子类覆盖。
func get_wait_ticks() -> int:
	return 0


# ---------------------------------------------------------------------------
# 占地 / 出入口
# ---------------------------------------------------------------------------

## 建筑本体占的所有格子（绝对坐标）
func get_occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(origin_cell.x, origin_cell.x + size_cells.x):
		for y in range(origin_cell.y, origin_cell.y + size_cells.y):
			cells.append(Vector2i(x, y))
	return cells


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
## 每个出入口在界内且是空地、且与建筑边相邻。
func can_place_at(world: WorldGrid, origin: Vector2i) -> bool:
	if size_cells.x <= 0 or size_cells.y <= 0:
		return false

	# 1. 整个矩形必须在世界范围内
	if origin.x < 0 or origin.y < 0:
		return false
	var world_cells := world.get_cells()
	if origin.x + size_cells.x > world_cells.x or origin.y + size_cells.y > world_cells.y:
		return false

	# 2. 本体内每一格都必须是空地
	for x in range(origin.x, origin.x + size_cells.x):
		for y in range(origin.y, origin.y + size_cells.y):
			if not world.is_walkable(Vector2i(x, y)):
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
## 放好之后，建筑本体占的格子会被设成不可走，出入口保持可走。
func place_at(world: WorldGrid, origin: Vector2i) -> bool:
	if not can_place_at(world, origin):
		push_warning("Building.place_at: %s 无法放在 %s" % [name, origin])
		return false

	origin_cell = origin
	set_cell_origin(origin)

	# 本体占的格子设成不可走
	for cell in get_occupied_cells():
		world.set_walkable(cell, false)

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

	# 出入口：黄色小广场
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


func _on_body_pressed() -> void:
	clicked.emit(self)


# ---------------------------------------------------------------------------
# 详情页内容（子类通过下面几个函数加内容 / 藏内容）
# ---------------------------------------------------------------------------

## 每次刷新前重建内容。子类覆盖时先 [code]super.build_detail()[/code] 再往里加。[br]
## 默认给三个通用行，外加一个空的「状态」板块留给子类填；
## 子类一行不加的话，空板块不会显示。
func build_detail() -> void:
	_detail_sections.clear()
	add_section("basic", "基本信息")
	add_row("basic", "名称", display_name, "name")
	add_row("basic", "占地", "%d × %d 格" % [size_cells.x, size_cells.y], "size")
	add_row("basic", "出入口", "%d 个" % entrance_offsets.size(), "entrance")
	add_section("status", "状态")


## 给外面（详情页）取一份当前内容
func get_detail_sections() -> Array[Dictionary]:
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
				"hidden": false,
			})
			return
	push_warning("add_row：没有 %s 这个板块" % section_id)


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
