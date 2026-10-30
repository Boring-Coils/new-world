extends CanvasLayer
class_name BuildingDetailPanel

## 右侧建筑详情页：占屏幕宽度的 [constant WIDTH_RATIO]，铺满整个高度。[br]
## 本类[b]不认识任何具体建筑[/b]：内容一律问 [method Building.get_detail_sections]，[br]
## 所以以后加医院、仓库、农田都不用改这里——只要子类在自己的 [method Building.build_detail] 里加行。[br]
## 打开方式：点建筑（[signal Building.clicked]）；关闭方式：点空地，或再点一次同一栋。[br]
## 刷新时机：每游戏刻重建一次，暂停时自然停更。

## 面板占屏幕宽度的比例（1/5）
const WIDTH_RATIO: float = 0.2

## 窄窗口下保持可用行宽的最小面板宽度。
const MIN_PANEL_WIDTH: float = 280.0

## 外层面板
var _panel: PanelContainer

## 标题（建筑名）
var _title: Label

## 所有板块和行都塞在这个容器里，每次刷新清空重建
var _body: VBoxContainer

## 当前选中的建筑（null = 没选中）
var _current: Building = null

## 当前结构签名和可原位更新的行控件。
var _structure_signature: String = ""
var _row_widgets: Dictionary = {}

## 底部「摧毁」按钮。固定不滚，所以单独存一份引用
var _demolish_button: Button = null


func _ready() -> void:
	# 盖在调试面板上面一点，避免被建筑挡住
	layer = 10
	_build()
	hide_panel()

	# 想知道「有哪些建筑」：先补一批已经存在的，再连信号等以后放下的
	for building in TickManager.buildings:
		_connect_building(building)
	TickManager.building_registered.connect(_connect_building)

	# 每刻刷新内容（建筑里的人数、产量这类会变）
	TickManager.tick_advanced.connect(_on_tick_advanced)


func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.92)
	style.border_color = Color(1.0, 1.0, 1.0, 0.14)
	style.set_border_width_all(1)
	style.set_content_margin_all(14)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override("panel", style)
	# 用锚点定宽度：左边锚在 80%，右边锚在 100%，窗口怎么拉都正好五分之一
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_update_panel_width()
	get_viewport().size_changed.connect(_update_panel_width)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_title)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_body)

	# 底部固定区：放在 scroll 后面（同级兄弟）
	vbox.add_child(HSeparator.new())

	_demolish_button = Button.new()
	_demolish_button.text = "摧毁建筑"
	_demolish_button.focus_mode = Control.FOCUS_NONE
	# 横向铺满，和面板其它控件对齐
	_demolish_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 用红色文字提示「这是个破坏性操作」，不额外换整套按钮样式，保持和项目风格一致
	_demolish_button.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	_demolish_button.pressed.connect(_on_demolish_pressed)
	vbox.add_child(_demolish_button)


func _update_panel_width() -> void:
	if _panel == null:
		return
	var viewport_width: float = get_viewport().get_visible_rect().size.x
	var panel_width := minf(
		maxf(viewport_width * WIDTH_RATIO, MIN_PANEL_WIDTH),
		viewport_width,
	)
	_panel.offset_left = -panel_width
	_panel.offset_right = 0.0


## 让某一栋建筑的点击都连到这里
func _connect_building(building: Building) -> void:
	if building == null or not is_instance_valid(building):
		return
	if not building.clicked.is_connected(show_building):
		building.clicked.connect(show_building)


## 显示某一栋建筑的详情（同一栋再点一次就收起）
func show_building(building: Building) -> void:
	if _current == building:
		hide_panel()
		return
	_current = building
	_panel.visible = true
	_refresh()


## 收起面板
func hide_panel() -> void:
	_current = null
	if _panel != null:
		_panel.visible = false


## 面板开着没有
func is_open() -> bool:
	return _panel != null and _panel.visible


## 点「摧毁」：先收起面板，再拆建筑。[br]
## 顺序不能反：[member _current] 持有建筑引用，建筑被 free 后它就失效，[br]
## 先 hide_panel() 把它置空，后续刷新就不会碰到已释放的对象。
func _on_demolish_pressed() -> void:
	if _current == null or not is_instance_valid(_current):
		hide_panel()
		return

	var building := _current
	hide_panel()
	building.remove()


## 点空地收起：点建筑的那一下会被建筑自己的按钮吃掉，走不到这里
func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hide_panel()


func _on_tick_advanced(_total_ticks: int, _day: int, _tick_of_day: int) -> void:
	if is_open():
		_refresh()


## 把当前建筑的内容整个重建一遍
func _refresh() -> void:
	if _current == null or not is_instance_valid(_current):
		hide_panel()
		return

	_title.text = _current.display_name
	var visible_sections: Array[Dictionary] = []
	var signature_parts: Array[String] = [str(_current.get_instance_id())]
	for section in _current.get_detail_sections():
		if section["hidden"]:
			continue
		var rows: Array = []
		for row in section["rows"]:
			if not row["hidden"]:
				rows.append(row)
		if rows.is_empty():
			continue
		visible_sections.append({
			"section": section,
			"rows": rows,
		})
		signature_parts.append("%s|%s" % [section["id"], section["title"]])
		for row in rows:
			signature_parts.append("%s|%s|%s" % [
				row["key"],
				row["label"],
				row.get("kind", "text"),
			])

	var new_signature := "||".join(signature_parts)
	if new_signature != _structure_signature:
		if _has_focused_control(_body):
			return
		_rebuild_rows(visible_sections)
		_structure_signature = new_signature
		return

	_update_rows(visible_sections)


func _rebuild_rows(visible_sections: Array[Dictionary]) -> void:

	# 先清空旧的控件
	for child in _body.get_children():
		child.queue_free()
	_row_widgets.clear()

	var first_section := true

	for wrapper in visible_sections:
		var section: Dictionary = wrapper["section"]
		var rows: Array = wrapper["rows"]

		# 第二个板块起，前面留一点空，免得标题贴着上一板块的行
		if not first_section:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 8)
			_body.add_child(gap)
		first_section = false

		var header := Label.new()
		header.text = section["title"]
		header.add_theme_font_size_override("font_size", 15)
		header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		_body.add_child(header)

		for row in rows:
			var row_key := "%s/%s" % [section["id"], row["key"]]
			var row_widget := _make_row(row, row_key)
			_body.add_child(row_widget)


func _update_rows(visible_sections: Array[Dictionary]) -> void:
	for wrapper in visible_sections:
		var section: Dictionary = wrapper["section"]
		for row in wrapper["rows"]:
			var row_key := "%s/%s" % [section["id"], row["key"]]
			var widgets: Dictionary = _row_widgets.get(row_key, {})
			if widgets.is_empty():
				continue
			if String(row.get("kind", "text")) == "number":
				var input: SpinBox = widgets["input"]
				if is_instance_valid(input) and not input.has_focus():
					input.set_value_no_signal(float(row.get("current", 0)))
			else:
				var value_label: Label = widgets["value"]
				if is_instance_valid(value_label):
					value_label.text = String(row["value"])


## 一行 = 左边标签 + 右边数值
func _make_row(row_data: Dictionary, row_key: String) -> HBoxContainer:
	var row := HBoxContainer.new()

	var label := Label.new()
	label.text = String(row_data["label"])
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.6))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	if String(row_data.get("kind", "text")) == "number":
		var input := SpinBox.new()
		input.min_value = float(row_data.get("min", 0))
		input.max_value = float(row_data.get("max", 0))
		input.step = 1.0
		input.value = float(row_data.get("current", 0))
		input.allow_greater = false
		input.allow_lesser = false
		input.focus_mode = Control.FOCUS_ALL
		input.update_on_text_changed = false
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		input.custom_minimum_size = Vector2(82, 0)
		var on_changed: Callable = row_data.get("on_changed", Callable())
		if on_changed.is_valid():
			input.value_changed.connect(
				func(value: float) -> void:
					on_changed.call(int(value))
			)
		row.add_child(input)
		_row_widgets[row_key] = {
			"row": row,
			"input": input,
			"value": null,
		}
		return row

	var value := Label.new()
	value.text = String(row_data["value"])
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	_row_widgets[row_key] = {
		"row": row,
		"input": null,
		"value": value,
	}

	return row


func _has_focused_control(node: Node) -> bool:
	var control := node as Control
	if control != null and control.has_focus():
		return true
	for child in node.get_children():
		if _has_focused_control(child):
			return true
	return false


## 供 UI 自检使用：检查面板是否越界、文本是否超出控件、行内控件是否重叠。
func get_layout_issues() -> Array[String]:
	var issues: Array[String] = []
	if _panel == null or not _panel.visible:
		return issues
	if not get_viewport().get_visible_rect().encloses(_panel.get_global_rect()):
		issues.append("详情页超出视口")
	_collect_layout_issues(_body, issues)
	return issues


func _collect_layout_issues(node: Node, issues: Array[String]) -> void:
	var control := node as Control
	if control != null and control.visible:
		if control.size.x + 0.5 < control.get_combined_minimum_size().x:
			issues.append("%s 横向空间不足" % control.name)
		if control is Label:
			var label := control as Label
			var font := label.get_theme_font("font")
			var font_size := label.get_theme_font_size("font_size")
			var text_size := font.get_string_size(
				label.text,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				font_size,
			)
			if text_size.x > label.size.x + 0.5:
				issues.append("文本超出控件：%s" % label.text)
		if control is HBoxContainer:
			var previous_right := -1.0
			for child in control.get_children():
				var child_control := child as Control
				if child_control == null or not child_control.visible:
					continue
				var child_rect := child_control.get_global_rect()
				if previous_right >= 0.0 and child_rect.position.x + 0.5 < previous_right:
					issues.append("行内控件重叠：%s" % control.name)
					break
				previous_right = child_rect.end.x
	for child in node.get_children():
		_collect_layout_issues(child, issues)
