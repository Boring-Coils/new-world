## 调试与建造场景共用的放置控制器。[br]
## 负责预览建筑、校验目标格、提交放置，以及检查居民出生格是否合法。[br]
## 建筑放置复用 [method Building.can_place_at] 与 [method Building.place_at] 的完整流程；[br]
## 左键提交、右键或 Escape 取消，放置期间禁用已有建筑的点击区。
extends Node2D
class_name PlacementController

## 可以放什么
enum Kind {
	## 未选择任何放置内容。
	NONE,
	## 放置取水站。
	WATER,
	## 放置取食站。
	FOOD,
	## 放置废料分拣工作站。
	WORK,
	## 放置仓库。
	WAREHOUSE,
	## 放置成年居民。
	HUMAN,
}

## 放成功或失败时发一句提示，给 UI 显示
signal notice(text: String)

## 调试菜单放置的居民统一使用成年年龄段
const DEBUG_HUMAN_AGE_MIN: int = 18

## 调试菜单随机生成居民年龄的上限（含）。
const DEBUG_HUMAN_AGE_MAX: int = 59

## 当前选中的类型
var kind: Kind = Kind.NONE

# 当前鼠标对应的格子坐标。
var _hover_cell: Vector2i = Vector2i.ZERO

# 当前预览格是否通过放置校验。
var _hover_valid: bool = false

# 建筑预览实例；放置居民或未选择建筑时为 null。
var _ghost: Building = null

## 调试用：把预览钉在某一格（-1 表示跟随鼠标）
var debug_hover_cell: Vector2i = Vector2i(-1, -1)


## 把放置高亮层放到建筑和居民上方。
func _ready() -> void:
	# 盖在建筑和居民上面
	z_index = 50


## 每帧刷新预览（不依赖鼠标移动事件，鼠标停在原地也能保持对齐）
func _process(_delta: float) -> void:
	if kind != Kind.NONE:
		_update_hover()


## 切换当前放置类型并重建对应预览。[br]
## [param new_kind] 应使用 [enum Kind] 中的值；进入建筑放置模式时会禁用已有建筑点击。
func select_kind(new_kind: int) -> void:
	kind = new_kind
	_clear_ghost()

	if kind != Kind.NONE and kind != Kind.HUMAN:
		_ghost = _create_building(kind)
		_ghost.is_preview = true
		_ghost.z_index = 0
		_ghost.visible = false
		add_child(_ghost)

	# 进了放置模式就把已有建筑的点选关掉，退出时再打开
	_set_buildings_clickable(kind == Kind.NONE)
	queue_redraw()


## 启用或禁用所有已登记建筑的点击区，防止放置点击被建筑按钮吞掉。
func _set_buildings_clickable(enabled: bool) -> void:
	for building in TickManager.buildings:
		if is_instance_valid(building):
			building.set_click_enabled(enabled)


## 取消当前放置模式并清理预览。
func cancel() -> void:
	select_kind(Kind.NONE)


## 处理放置模式下的左键提交、右键取消和 Escape 取消。
func _unhandled_input(event: InputEvent) -> void:
	if kind == Kind.NONE:
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_place()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
			get_viewport().set_input_as_handled()


## 根据当前预览尺寸计算建筑左上角，使建筑尽量以 [param mouse_cell] 为中心。
func _origin_for(mouse_cell: Vector2i) -> Vector2i:
	if _ghost == null or not is_instance_valid(_ghost):
		return mouse_cell
	return mouse_cell - Vector2i(_ghost.size_cells.x / 2, _ghost.size_cells.y / 2)


## 刷新当前目标格、建筑预览位置和可放置状态。
func _update_hover() -> void:
	var world := WorldGridGlobal.world
	if debug_hover_cell.x >= 0:
		_hover_cell = debug_hover_cell
	else:
		_hover_cell = world.world_to_cell(get_global_mouse_position())

	if _ghost != null and is_instance_valid(_ghost):
		var origin := _origin_for(_hover_cell)
		_hover_valid = _ghost.can_place_at(world, origin)
		_ghost.set_cell_origin(origin)
		_ghost.set_preview_valid(_hover_valid)
		# 鼠标停在 UI 按钮上时先不显示，免得虚影跑到面板底下
		_ghost.visible = get_viewport().gui_get_hovered_control() == null
	elif kind == Kind.HUMAN:
		_hover_valid = world.is_walkable(_hover_cell)

	queue_redraw()


## 尝试在当前鼠标格提交放置。
func _try_place() -> void:
	place_at_cell(_hover_cell)


## 直接在 [param mouse_cell] 放置当前类型，建筑会自动以该格为中心。[br]
## 成功返回 [code]true[/code]，失败时通过 [signal notice] 给出原因。
func place_at_cell(mouse_cell: Vector2i) -> bool:
	var world := WorldGridGlobal.world

	if kind == Kind.HUMAN:
		return _place_human(mouse_cell)

	if _ghost == null or not is_instance_valid(_ghost):
		return false

	var origin := _origin_for(mouse_cell)
	if not _ghost.can_place_at(world, origin):
		notice.emit("这一格放不下：建筑、出入口或已有建筑的出入口被挡住了")
		return false

	var building := _create_building(kind)
	if not building.place_at(world, origin):
		building.free()
		notice.emit("放置失败")
		return false

	# 放置成功后再进入场景树，失败建筑不会短暂出现在 TickManager 中
	building.name = building.display_name
	add_child(building)
	# 还停在这个模式里的话，新建筑同样不能被点开
	building.set_click_enabled(kind == Kind.NONE)
	# 建筑压在原本站着人的格子上时，让人自己走出来
	_evict_humans_in(building)
	notice.emit("%s 已放下（左上角 %s）" % [building.name, origin])
	return true


## 让站在 [param building] 占地范围内的居民执行脱困移动。
func _evict_humans_in(building: Building) -> void:
	var cells := building.get_occupied_cells()
	var moved := 0
	for human in TickManager.humans:
		if not is_instance_valid(human):
			continue
		if cells.has(WorldGridGlobal.world.world_to_cell(human.position)):
			human.relocate_out()
			moved += 1
	if moved > 0:
		print("[PLACE] 有 %d 个居民被 %s 压住，正在自己走出来" % [moved, building.name])


## 在可走且无其他居民的 [param cell] 创建一个成年居民。
func _place_human(cell: Vector2i) -> bool:
	var world := WorldGridGlobal.world
	if not world.is_walkable(cell):
		notice.emit("这一格是建筑或障碍，人站不进去")
		return false
	var world_parent := _find_world_parent()
	if world_parent == null:
		notice.emit("找不到世界根节点，无法放置居民")
		return false

	# 同一格已经站了人的话不给放，否则两个人会叠在一起（画面看起来「少人」）
	for other in TickManager.humans:
		if is_instance_valid(other) and world.world_to_cell(other.position) == cell:
			notice.emit("这一格已经站了一个人了")
			return false

	var human := Human.create()
	human.name = "居民%d" % (TickManager.humans.size() + 1)
	human.position = world.cell_to_world(cell)

	# 调试放置用于稳定验证雇佣和工作链路，统一生成成年人。
	human.age_status = GlobalEnum.AgeStatus.ADULT
	human.age = randi_range(DEBUG_HUMAN_AGE_MIN, DEBUG_HUMAN_AGE_MAX)

	world_parent.add_child(human)
	notice.emit("%s 已放下（成年，%s）" % [human.name, cell])
	return true


## 向上查找最近的 [World] 根节点，用作新居民的父节点。
func _find_world_parent() -> World:
	var node: Node = get_parent()
	while node != null:
		if node is World:
			return node as World
		node = node.get_parent()
	return null


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

## 根据 [param kind_value] 创建对应建筑类型；未知类型返回基础 [Building]。
func _create_building(kind_value: Kind) -> Building:
	match kind_value:
		Kind.WATER:
			return WaterStation.new()
		Kind.FOOD:
			return FoodStation.new()
		Kind.WORK:
			return ScrapSortingStation.new()
		Kind.WAREHOUSE:
			return Warehouse.new()
		_:
			return Building.new()


## 释放并清空当前建筑预览实例。
func _clear_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null


## 画出鼠标所在格子的高亮框
func _draw() -> void:
	if kind == Kind.NONE:
		return

	var cell_size := float(WorldGrid.CELL_SIZE)
	var center := WorldGridGlobal.world.cell_to_world(_hover_cell)
	var rect := Rect2(center - Vector2(cell_size, cell_size) * 0.5, Vector2(cell_size, cell_size))
	var color := Color(0.35, 1.0, 0.45, 0.9) if _hover_valid else Color(1.0, 0.35, 0.35, 0.9)

	draw_rect(rect, Color(color.r, color.g, color.b, 0.12), true)
	draw_rect(rect, color, false, 1.2)
