extends Node2D
class_name Building

## 建筑基类。[br]
##
## 建筑一定是矩形，占 [member size_cells] 个格子（横向 × 纵向），
## 放置时左上角必须正好落在某一格的左上角（也就是 [member origin_cell] 是格子坐标，天然对齐）。[br]
##
## [b]出入口：[/b]用相对坐标 [member entrance_offsets] 描述，是相对建筑左上角格子的偏移。[br]
## 规则：出入口必须落在建筑矩形[b]外面[/b]、并且和建筑边相邻（只碰到角不算），
## 这一格本身必须是空地（不能压别的建筑或遮挡物），但可以和别的建筑的出入口重合。
##
## [b]典型用法：[/b]
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

## 是否是「放置预览」（半透明、不注册到 TickManager、不占格子）
var is_preview: bool = false

## 预览状态下当前格子能不能放，决定描边是绿还是红
var preview_valid: bool = true


func _ready() -> void:
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
##
## 检查项：矩形在界内、本体内每格都是空的（没被别的建筑或遮挡物占）、
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
# 绘制（白模：没有贴图，全部用几何图形画）
# ---------------------------------------------------------------------------

func _draw() -> void:
	var cell := float(WorldGrid.CELL_SIZE)
	var size_px := Vector2(size_cells) * cell
	var rect := Rect2(Vector2.ZERO, size_px)

	var alpha := 0.45 if is_preview else 1.0
	var outline := Color(0.12, 0.13, 0.16, alpha)
	if is_preview:
		outline = Color(0.35, 1.0, 0.45, 0.95) if preview_valid else Color(1.0, 0.35, 0.35, 0.95)

	# 投影
	draw_rect(Rect2(Vector2(1.4, 2.0), size_px), Color(0.0, 0.0, 0.0, 0.15 * alpha), true)
	# 白色主体
	draw_rect(rect, Color(0.94, 0.94, 0.91, alpha), true)
	# 顶部一条深色檐口，看起来像建筑而不是一块板
	draw_rect(Rect2(Vector2.ZERO, Vector2(size_px.x, size_px.y * 0.18)), Color(0.36, 0.37, 0.41, alpha), true)
	# 描边
	draw_rect(rect, outline, false, 1.6)

	# 类型符号
	_draw_type_symbol(Vector2(size_px.x * 0.5, size_px.y * 0.6), alpha)

	# 出入口：黄色小广场
	for offset in entrance_offsets:
		var entrance_rect := Rect2(Vector2(offset) * cell, Vector2(cell, cell))
		draw_rect(entrance_rect, Color(1.0, 0.85, 0.30, 0.75 * alpha), true)
		draw_rect(entrance_rect, Color(0.45, 0.35, 0.05, alpha), false, 0.8)


## 画建筑类型的小符号（水滴 / 碗 / 齿轮）
func _draw_type_symbol(center: Vector2, alpha: float) -> void:
	var color := Color(body_color.r, body_color.g, body_color.b, alpha)
	var radius := minf(size_cells.x, size_cells.y) * float(WorldGrid.CELL_SIZE) * 0.17

	match building_type:
		GlobalEnum.BuildingType.WATER:
			# 水滴：下面一个圆，上面一个三角
			draw_circle(center + Vector2(0.0, radius * 0.55), radius * 0.8, color)
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(-radius * 0.62, radius * 0.35),
				center + Vector2(radius * 0.62, radius * 0.35),
				center + Vector2(0.0, -radius * 1.45),
			]), color)
		GlobalEnum.BuildingType.FOOD:
			# 碗：一条横线 + 下半圆
			draw_line(center + Vector2(-radius, -radius * 0.15), center + Vector2(radius, -radius * 0.15), color, 1.6)
			draw_arc(center + Vector2(0.0, -radius * 0.15), radius, 0.0, PI, 18, color, 1.6)
		GlobalEnum.BuildingType.WORK:
			# 齿轮：一个圆环 + 四根齿
			draw_arc(center, radius * 0.72, 0.0, TAU, 20, color, 1.6)
			for i in range(4):
				var angle := TAU * float(i) / 4.0
				var direction := Vector2(cos(angle), sin(angle))
				draw_line(center + direction * radius * 0.72, center + direction * radius * 1.15, color, 1.6)


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
