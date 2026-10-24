extends CanvasLayer
class_name BuildingDetailPanel

## 右侧建筑详情页：占屏幕宽度的 [constant WIDTH_RATIO]，铺满整个高度。[br]
## 本类[b]不认识任何具体建筑[/b]：内容一律问 [method Building.get_detail_sections]，[br]
## 所以以后加医院、仓库、农田都不用改这里——只要子类在自己的 [method Building.build_detail] 里加行。[br]
## 打开方式：点建筑（[signal Building.clicked]）；关闭方式：点空地，或再点一次同一栋。[br]
## 刷新时机：每游戏刻重建一次，暂停时自然停更。

## 面板占屏幕宽度的比例（1/5）
const WIDTH_RATIO: float = 0.2

## 外层面板
var _panel: PanelContainer

## 标题（建筑名）
var _title: Label

## 所有板块和行都塞在这个容器里，每次刷新清空重建
var _body: VBoxContainer

## 当前选中的建筑（null = 没选中）
var _current: Building = null

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
	_panel.anchor_left = 1.0 - WIDTH_RATIO
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
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

	# 先清空旧的控件
	for child in _body.get_children():
		child.queue_free()

	var first_section := true

	for section in _current.get_detail_sections():
		if section["hidden"]:
			continue

		# 板块里一行有效内容都没有就不画（避免出现只有标题的空板块）
		var rows: Array = []
		for row in section["rows"]:
			if not row["hidden"]:
				rows.append(row)
		if rows.is_empty():
			continue

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
			_body.add_child(_make_row(row["label"], row["value"]))


## 一行 = 左边标签 + 右边数值
func _make_row(label_text: String, value_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.6))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)

	return row
