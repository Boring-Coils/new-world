extends CanvasLayer
class_name DebugUI

## 调试面板：显示时间 / 居民状态，并提供「放置建筑和居民」的按钮。[br]
## 只负责界面，真正放东西的是 [PlacementController]。

## 选中了要放什么（值是 [enum PlacementController.Kind]）
signal kind_selected(kind: int)

## 状态文字（天、刻、各状态人数）
var _stats_label: Label

## 当前放置模式的说明
var _mode_label: Label

## 放下 / 失败的提示
var _hint_label: Label

## 当前选中的类型
var _current_kind: int = PlacementController.Kind.NONE


func _ready() -> void:
	_build()


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
	_add_button(grid, "无限工作站", PlacementController.Kind.WORK)
	_add_button(grid, "居民", PlacementController.Kind.HUMAN)
	_add_button(grid, "取消", PlacementController.Kind.NONE)

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
			_mode_label.text = "放置：无限工作站"
		PlacementController.Kind.HUMAN:
			_mode_label.text = "放置：居民"
		_:
			_mode_label.text = "放置：无"
	kind_selected.emit(kind)


## 更新左上角的状态文字
func set_stats(text: String) -> void:
	if _stats_label != null:
		_stats_label.text = text


## 显示一条提示（放置成功 / 失败的原因）
func set_hint(text: String) -> void:
	if _hint_label != null:
		_hint_label.text = text
