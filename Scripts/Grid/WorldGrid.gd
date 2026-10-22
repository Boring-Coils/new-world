extends RefCounted
class_name WorldGrid

## 世界网格寻路工具。[br]
## 把整个游戏世界均匀切成固定大小的正方形格子，并基于 [AStarGrid2D] 提供 A* 寻路能力。[br]
## [b]坐标约定（非常重要）：[/b][br]
## - 世界每格边长为 [constant CELL_SIZE] 像素，[code](0, 0)[/code] 表示左上角第一格。[br]
## - 本类所有对外函数接收 / 返回的坐标，除名字里带 "world" 的以外，[br]
##   一律为格子坐标（[code]Vector2i[/code]，即第几列、第几行），而不是像素坐标。[br]
## [b]典型用法：[/b][br]
## [codeblock]
## var grid := WorldGrid.new(Vector2i(200, 150))   # 世界共 200 列 × 150 行
## grid.set_walkable(Vector2i(3, 4), false)        # 把 (3, 4) 设为墙，不可走
## grid.set_walk_cost(Vector2i(4, 4), 0.5)         # 把 (4, 4) 设为「更好走」
## var path := grid.get_path(Vector2i(0, 0), Vector2i(20, 10))
## [/codeblock]


## 每个格子的边长（像素）。世界就是被切成这种大小的方块。
const CELL_SIZE: float = 10.0

## 默认的通行代价，[code]1.0[/code] 表示普通地面。
const DEFAULT_WALK_COST: float = 1.0

## 底层使用的 A* 网格
var _astar: AStarGrid2D

## 世界共有多少格（横向 × 纵向）
var _cells: Vector2i


## 构造函数。[br]
## [param cells] 为世界被切成的格子数（横向 × 纵向），默认 [code](100, 100)[/code]，[br]
## 即世界大小为 [code]1000 × 1000[/code] 像素。
func _init(cells: Vector2i = Vector2i(100, 100)) -> void:
    # 至少要有一格，否则 AStarGrid2D 的 region 为空会报错
    _cells = Vector2i(maxi(cells.x, 1), maxi(cells.y, 1))

    _astar = AStarGrid2D.new()
    # 网格覆盖范围：从格子 (0,0) 到 (_cells.x-1, _cells.y-1)
    _astar.region = Rect2i(Vector2i.ZERO, _cells)
    # 每格边长 = CELL_SIZE 像素（用 Vector2 是为了兼容可能出现的非正方形格子）
    _astar.cell_size = Vector2(CELL_SIZE, CELL_SIZE)
    # 让 AStarGrid2D 自带的 get_point_position() 返回格子【正中心】而不是左上角。
    # 注意：本类的 cell_to_world() 已自行做同样换算，这里只影响引擎自带的坐标查询
    _astar.offset = Vector2(CELL_SIZE, CELL_SIZE) * 0.5
    # 斜向移动：仅当两侧都不被阻挡时才允许斜着走，避免贴着墙角「穿过去」
    _astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
    # 启发式必须与「允许斜走」匹配：八方向用对角距离（octile）估算，
    # 用默认的欧氏距离会高估代价，导致多探索大量无用格子
    _astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
    _astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
    # 以上都是「结构参数」，设置完毕后必须调用一次 update() 才会生效
    _astar.update()


# ---------------------------------------------------------------------------
# 查询辅助
# ---------------------------------------------------------------------------

## 判断一个格子坐标是否落在世界范围内（0 <= x < 列数 且 0 <= y < 行数）。
func is_in_bounds(cell: Vector2i) -> bool:
    return cell.x >= 0 and cell.y >= 0 and cell.x < _cells.x and cell.y < _cells.y


## 返回世界一共有多少格（横向 × 纵向）。
func get_cells() -> Vector2i:
    return _cells


# ---------------------------------------------------------------------------
# 能不能走
# ---------------------------------------------------------------------------

## 设置某一格能不能走。[br]
## [param cell] 为格子坐标；[param walkable] 为 [code]true[/code] 表示可走，[br]
## [code]false[/code] 表示不可走（相当于一堵墙）。
func set_walkable(cell: Vector2i, walkable: bool) -> void:
    if not is_in_bounds(cell):
        push_warning("WorldGrid.set_walkable: 格子 %s 超出世界范围 %s" % [cell, _cells])
        return
    # AStarGrid2D 里的 "solid"（实心）与我们的「不可走」正好相反，故取反
    _astar.set_point_solid(cell, not walkable)


## 查询某一格能不能走。超出范围的格子一律视为不可走。
func is_walkable(cell: Vector2i) -> bool:
    if not is_in_bounds(cell):
        return false
    return not _astar.is_point_solid(cell)


# ---------------------------------------------------------------------------
# 好不好走（通行代价）
# ---------------------------------------------------------------------------

## 设置某一格的「通行代价」——也就是好不好走。[br]
## [param cost] 是一个相对倍率：[br]
## - [code]1.0[/code]：普通地面（默认）。[br]
## - 小于 [code]1.0[/code]：更好走，例如 [code]0.5[/code] 表示只需一半代价，寻路会优先选择这些格子。[br]
## - 大于 [code]1.0[/code]：更难走，例如 [code]3.0[/code] 表示三倍代价，寻路会尽量绕开这些格子。[br]
## 注意：代价再大也只是「不划算」，格子依然能走；[br]
## 要让格子彻底无法通行，请改用 [method set_walkable]。
func set_walk_cost(cell: Vector2i, cost: float) -> void:
    if not is_in_bounds(cell):
        push_warning("WorldGrid.set_walk_cost: 格子 %s 超出世界范围 %s" % [cell, _cells])
        return
    # 负代价没有意义，这里兜底夹到 0
    _astar.set_point_weight_scale(cell, maxf(cost, 0.0))


## 查询某一格的通行代价。超出范围返回 [code]INF[/code]（视为无穷大代价）。
func get_walk_cost(cell: Vector2i) -> float:
    if not is_in_bounds(cell):
        return INF
    return _astar.get_point_weight_scale(cell)


# ---------------------------------------------------------------------------
# 寻路
# ---------------------------------------------------------------------------

## 计算从格子 [param from] 到格子 [param to] 的最优路径。[br]
## 返回值为途径的格子坐标序列（[code]Array[Vector2i][/code]，含起点与终点）。[br]
## 若无法到达（被墙完全隔开，或起点 / 终点本身不可走），返回空数组。
func get_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
    var empty: Array[Vector2i] = []

    if not is_in_bounds(from) or not is_in_bounds(to):
        push_warning("WorldGrid.get_path: 起点 %s 或终点 %s 超出世界范围 %s" % [from, to, _cells])
        return empty

    # 起点或终点自身就在墙里，自然无路可走
    if not is_walkable(from) or not is_walkable(to):
        return empty

    # 起点与终点重合时路径就是这一个格子本身。
    # AStarGrid2D 在这种情况下会返回空数组，直接透传会被误判成「无路可走」
    if from == to:
        var same: Array[Vector2i] = [from]
        return same

    var result: Array[Vector2i] = _astar.get_id_path(from, to)
    return result


## 找离 [param cell] 最近的一格可走地面（按一圈圈外扩找，只找方形范围内）。[br]
## 用来把「被新建筑压住的人」挤到空地上去。找不到就返回原格子。
func find_nearest_walkable(cell: Vector2i, max_radius: int = 60) -> Vector2i:
    if is_in_bounds(cell) and is_walkable(cell):
        return cell

    for radius in range(1, max_radius + 1):
        for dx in range(-radius, radius + 1):
            for dy in range(-radius, radius + 1):
                # 只看这一圈的外框
                if maxi(absi(dx), absi(dy)) != radius:
                    continue
                var candidate := Vector2i(cell.x + dx, cell.y + dy)
                if is_in_bounds(candidate) and is_walkable(candidate):
                    return candidate

    return cell


# ---------------------------------------------------------------------------
# 格子坐标 <-> 世界（像素）坐标 换算
# ---------------------------------------------------------------------------

## 把格子坐标换算成该格子【中心】的像素坐标（世界坐标）。
func cell_to_world(cell: Vector2i) -> Vector2:
    return Vector2(cell) * CELL_SIZE + Vector2(CELL_SIZE, CELL_SIZE) * 0.5


## 把像素坐标（世界坐标）换算成它所在的格子坐标。[br]
## 世界外的像素坐标会被夹到最边上的那一格，保证返回值永远合法。
func world_to_cell(world: Vector2) -> Vector2i:
    var cell := Vector2i((world / CELL_SIZE).floor())
    return Vector2i(
        clampi(cell.x, 0, _cells.x - 1),
        clampi(cell.y, 0, _cells.y - 1),
    )


## 把一整条格子路径换算成像素坐标（各格子中心）序列，方便角色依次移动过去。
func path_to_world(cell_path: Array[Vector2i]) -> PackedVector2Array:
    var result := PackedVector2Array()
    for cell in cell_path:
        result.append(cell_to_world(cell))
    return result
