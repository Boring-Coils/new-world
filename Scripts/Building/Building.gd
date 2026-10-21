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


func _ready() -> void:
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
	# 让节点的原点落在左上角格子的中心，绘制时以这个点为基准
	position = world.cell_to_world(origin) - Vector2(WorldGrid.CELL_SIZE, WorldGrid.CELL_SIZE) * 0.5

	# 本体占的格子设成不可走
	for cell in get_occupied_cells():
		world.set_walkable(cell, false)

	queue_redraw()
	return true


# ---------------------------------------------------------------------------
# 绘制（测试用：没有贴图，直接画色块）
# ---------------------------------------------------------------------------

func _draw() -> void:
	var cell := float(WorldGrid.CELL_SIZE)
	var size_px := Vector2(size_cells) * cell
	var rect := Rect2(Vector2.ZERO, size_px)

	# 建筑主体
	draw_rect(rect, body_color, true)
	# 边框
	draw_rect(rect, body_color.darkened(0.4), false, 2.0)

	# 出入口：亮色小方块
	for offset in entrance_offsets:
		var origin_world := Vector2(offset) * cell
		draw_rect(Rect2(origin_world, Vector2(cell, cell)), Color(1.0, 1.0, 0.4), true)


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
