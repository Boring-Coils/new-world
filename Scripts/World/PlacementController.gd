extends Node2D
class_name PlacementController

## 调试用放置工具。[br]
## 选中一种建筑或「居民」之后，鼠标位置会出现一个半透明预览：[br]
## 绿色描边 = 这一格能放，红色 = 不能放。左键放下，右键 / ESC 取消。[br]
## 建筑放置会走 [method Building.can_place_at] 的完整校验；[br]
## 居民只能放在可走的空地上（不能压在建筑或障碍上）。

## 可以放什么
enum Kind {
	NONE,  ## 没在放东西
	WATER, ## 取水站
	FOOD,  ## 取食站
	WORK,  ## 工作站
	HUMAN, ## 居民
}

## 放成功或失败时发一句提示，给 UI 显示
signal notice(text: String)

## 当前选中的类型
var kind: Kind = Kind.NONE

## 当前鼠标下的格子
var _hover_cell: Vector2i = Vector2i.ZERO

## 这一格当前能不能放
var _hover_valid: bool = false

## 建筑预览实例（放人时为 null）
var _ghost: Building = null

## 调试用：把预览钉在某一格（-1 表示跟随鼠标）
var debug_hover_cell: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	# 盖在建筑和居民上面
	z_index = 50


## 每帧刷新预览（不依赖鼠标移动事件，鼠标停在原地也能保持对齐）
func _process(_delta: float) -> void:
	if kind != Kind.NONE:
		_update_hover()


## 切换要放的东西（传 [enum Kind] 里的值）
func select_kind(new_kind: int) -> void:
	kind = new_kind
	_clear_ghost()

	if kind != Kind.NONE and kind != Kind.HUMAN:
		_ghost = _create_building(kind)
		_ghost.is_preview = true
		_ghost.z_index = 0
		_ghost.visible = false
		add_child(_ghost)

	queue_redraw()


## 取消当前放置
func cancel() -> void:
	select_kind(Kind.NONE)


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


## 鼠标所指的格子 → 建筑左上角那一格（让建筑大致以鼠标为中心）
func _origin_for(mouse_cell: Vector2i) -> Vector2i:
	if _ghost == null or not is_instance_valid(_ghost):
		return mouse_cell
	return mouse_cell - Vector2i(_ghost.size_cells.x / 2, _ghost.size_cells.y / 2)


## 更新鼠标所在格子和预览位置
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


## 在当前格子放下东西
func _try_place() -> void:
	place_at_cell(_hover_cell)


## 直接在某格放置（传鼠标所指的格子，建筑会自动以它为中心）。放成功返回 true。
func place_at_cell(mouse_cell: Vector2i) -> bool:
	var world := WorldGridGlobal.world

	if kind == Kind.HUMAN:
		return _place_human(mouse_cell)

	if _ghost == null or not is_instance_valid(_ghost):
		return false

	var origin := _origin_for(mouse_cell)
	if not _ghost.can_place_at(world, origin):
		notice.emit("这一格放不下：建筑或出入口被挡住了")
		return false

	var building := _create_building(kind)
	building.name = building.display_name
	add_child(building)
	if building.place_at(world, origin):
		# 建筑压在原本站着人的格子上时，让人自己走出来
		_evict_humans_in(building)
		notice.emit("%s 已放下（左上角 %s）" % [building.name, origin])
		return true

	building.queue_free()
	notice.emit("放置失败")
	return false


## 把站在新建筑占地范围内的人挤出去（他们自己走到最近的空地）
func _evict_humans_in(building: Building) -> void:
	var cells := building.get_occupied_cells()
	var moved := 0
	for human in TickManager.humans:
		if not is_instance_valid(human):
			continue
		if cells.has(WorldGridGlobal.world.world_to_cell(human.position)):
			human.evict_out()
			moved += 1
	if moved > 0:
		print("[PLACE] 有 %d 个居民被 %s 压住，正在自己走出来" % [moved, building.name])


## 放一个居民
func _place_human(cell: Vector2i) -> bool:
	var world := WorldGridGlobal.world
	if not world.is_walkable(cell):
		notice.emit("这一格是建筑或障碍，人站不进去")
		return false

	# 同一格已经站了人的话不给放，否则两个人会叠在一起（画面看起来「少人」）
	for other in TickManager.humans:
		if is_instance_valid(other) and world.world_to_cell(other.position) == cell:
			notice.emit("这一格已经站了一个人了")
			return false

	var human := Human.create()
	human.name = "居民%d" % (TickManager.humans.size() + 1)
	human.position = world.cell_to_world(cell)

	# 随机年龄，三种年龄段轮着来
	match randi() % 3:
		0:
			human.age_status = GlobalEnum.AgeStatus.CHILD
			human.age = randi_range(6, 17)
		1:
			human.age_status = GlobalEnum.AgeStatus.ADULT
			human.age = randi_range(18, 59)
		2:
			human.age_status = GlobalEnum.AgeStatus.OLD
			human.age = randi_range(60, 85)

	add_child(human)
	notice.emit("%s 已放下（%s）" % [human.name, cell])
	return true


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

func _create_building(kind_value: Kind) -> Building:
	match kind_value:
		Kind.WATER:
			return WaterStation.new()
		Kind.FOOD:
			return FoodStation.new()
		Kind.WORK:
			return WorkStation.new()
		_:
			return Building.new()


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
