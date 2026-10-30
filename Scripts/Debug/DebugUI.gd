extends CanvasLayer
class_name DebugUI

## 调试面板：显示时间 / 居民状态，并提供放置和调试补给操作。[br]
## 真正放东西的是 [PlacementController]；随机补给只修改独立仓库库存。

## 选中了要放什么（值是 [enum PlacementController.Kind]）
signal kind_selected(kind: int)

## 每次调试补给向随机独立仓库添加的废料数量
const WAREHOUSE_WASTE_BATCH: int = 100

## 时间文字（第几天、当天第几刻、累计刻数）
var _time_label: Label

## 居民状态文字（各状态人数）
var _stats_label: Label

## 当前放置模式的说明
var _mode_label: Label

## 放下 / 失败的提示
var _hint_label: Label

## 当前选中的类型
var _current_kind: int = PlacementController.Kind.NONE


func _ready() -> void:
	_build()
	TickManager.tick_advanced.connect(_on_tick_advanced)
	_update_time(TickManager.total_ticks, TickManager.get_day(), TickManager.get_tick_of_day())


func _build() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(224, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.82)
	style.border_color = Color(1.0, 1.0, 1.0, 0.16)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "调试面板"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 14)
	_time_label.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0, 1.0))
	vbox.add_child(_time_label)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 13)
	_stats_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.9))
	vbox.add_child(_stats_label)

	vbox.add_child(HSeparator.new())

	_mode_label = Label.new()
	_mode_label.text = "放置：无"
	_mode_label.add_theme_font_size_override("font_size", 13)
	_mode_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	vbox.add_child(_mode_label)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)

	_add_button(grid, "无限取水站", PlacementController.Kind.WATER)
	_add_button(grid, "无限取食站", PlacementController.Kind.FOOD)
	_add_button(grid, "废料分拣站", PlacementController.Kind.WORK)
	_add_button(grid, "仓库", PlacementController.Kind.WAREHOUSE)
	_add_button(grid, "居民", PlacementController.Kind.HUMAN)
	_add_button(grid, "取消", PlacementController.Kind.NONE)

	vbox.add_child(HSeparator.new())

	var add_waste_button := Button.new()
	add_waste_button.text = "随机仓库 +100 废料"
	add_waste_button.tooltip_text = "向随机独立仓库添加 100 废料"
	add_waste_button.focus_mode = Control.FOCUS_NONE
	add_waste_button.custom_minimum_size = Vector2(0, 30)
	add_waste_button.pressed.connect(_on_add_waste_pressed)
	vbox.add_child(add_waste_button)

	_hint_label = Label.new()
	_hint_label.text = "左键放下（可连续放）\n右键 / ESC 取消"
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(186, 0)
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.65))
	vbox.add_child(_hint_label)

	vbox.add_child(HSeparator.new())

	var help := Label.new()
	help.text = "空格 暂停\n1~4 倍速\n中键拖动 / WASD 移动视角\n滚轮 缩放"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.5))
	vbox.add_child(help)


func _add_button(parent: GridContainer, text: String, kind: int) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(98, 30)
	button.pressed.connect(func() -> void: _on_button(kind))
	parent.add_child(button)


func _on_button(kind: int) -> void:
	_current_kind = kind
	match kind:
		PlacementController.Kind.WATER:
			_mode_label.text = "放置：无限取水站"
		PlacementController.Kind.FOOD:
			_mode_label.text = "放置：无限取食站"
		PlacementController.Kind.WORK:
			_mode_label.text = "放置：废料分拣站"
		PlacementController.Kind.WAREHOUSE:
			_mode_label.text = "放置：仓库"
		PlacementController.Kind.HUMAN:
			_mode_label.text = "放置：居民"
		_:
			_mode_label.text = "放置：无"
	kind_selected.emit(kind)


func _on_add_waste_pressed() -> void:
	var items := {MaterialTypes.ItemType.WASTE: WAREHOUSE_WASTE_BATCH}
	var candidates: Array[Building] = []
	for building in TickManager.get_buildings_of_type(GlobalEnum.BuildingType.WAREHOUSE):
		if (
			is_instance_valid(building)
			and building.is_placed
			and building.inventory != null
			and building.inventory.can_add_items(items)
		):
			candidates.append(building)

	if candidates.is_empty():
		set_hint("没有可容纳 %d 废料的独立仓库" % WAREHOUSE_WASTE_BATCH)
		return

	var target := candidates[randi_range(0, candidates.size() - 1)]
	if target.try_deposit_items(items):
		set_hint("已向随机仓库添加废料 +%d" % WAREHOUSE_WASTE_BATCH)
	else:
		set_hint("废料添加失败：仓库空间不足")


func _on_tick_advanced(total_ticks: int, day: int, tick_of_day: int) -> void:
	_update_time(total_ticks, day, tick_of_day)


func _update_time(total_ticks: int, day: int, tick_of_day: int) -> void:
	if _time_label == null:
		return
	_time_label.text = "时间：第 %d 天 · 第 %d 刻\n累计：%d 刻" % [
		day, tick_of_day, total_ticks
	]


## 更新左上角的状态文字
func set_stats(text: String) -> void:
	if _stats_label != null:
		_stats_label.text = text


## 显示一条提示（放置成功 / 失败的原因）
func set_hint(text: String) -> void:
	if _hint_label != null:
		_hint_label.text = text
