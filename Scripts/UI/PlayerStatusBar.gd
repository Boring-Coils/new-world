## 正式玩家状态栏。[br]
## 顶部常驻显示物资与人口/时间摘要，并为允许详情的项目提供统一悬停面板。[br]
## 摘要只响应库存、居民、建筑和时间事件，详情只在展开期间按相关事件刷新。
extends CanvasLayer
class_name PlayerStatusBar

## 状态栏与视口顶部的距离。
const TOP_MARGIN: float = 0.0

## 无内容时状态栏仍保留的最小宽度。
const MIN_BAR_WIDTH: float = 220.0

## 倒置梯形左右为内容预留的边距。
const SIDE_PADDING: float = 30.0

## 上下内容边距。
const VERTICAL_PADDING: float = 8.0

## 人口信息项图标。
const POPULATION_ICON: Texture2D = preload("res://Assets/Icons/Status/population.svg")

## 时间信息项图标。
const TIME_ICON: Texture2D = preload("res://Assets/Icons/Status/time.svg")

# 状态栏底板。
var _surface: StatusBarSurface = null

# 底板内的两行内容容器。
var _rows: Array[HBoxContainer] = []

# 信息项定义，按稳定标识保存。
var _definitions: Dictionary = {}

# 信息项控件，按稳定标识保存。
var _items: Dictionary = {}

# 物资行分隔线，按后一个信息项标识保存。
var _separators: Dictionary = {}

# 当前展开详情的截图统一面板。
var _detail_panel: PanelContainer = null

# 详情面板内容容器。
var _detail_body: VBoxContainer = null

# 当前鼠标悬停的信息项。
var _hovered_item: PlayerStatusInfoItem = null

# 当前详情内容，用于避免完全相同时重建控件。
var _detail_content: Array[Dictionary] = []

# 详情提供者被调用的次数，用于验收“关闭后停止刷新”。
var _detail_fetch_count: int = 0

# 是否已经排队一次布局，避免同一帧重复排队。
var _layout_queued: bool = false


## 创建状态栏控件、连接事件源并注册人口与时间信息项。
func _ready() -> void:
	layer = 20
	_build()
	_connect_event_sources()
	_register_status_items()
	for definition in MaterialSystem.get_status_item_registrations():
		register_info_item(definition)
	get_viewport().size_changed.connect(_queue_layout)
	_queue_layout()


## 返回指定稳定标识的信息项控件。
func get_item_control(item_id: String) -> PlayerStatusInfoItem:
	return _items.get(item_id) as PlayerStatusInfoItem


## 返回当前注册顺序中全部信息项的稳定标识。
func get_registered_item_ids() -> Array[String]:
	var entries: Array[Dictionary] = []
	for definition in _definitions.values():
		entries.append(definition)
	entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var row_a := int(a["row"])
			var row_b := int(b["row"])
			if row_a != row_b:
				return row_a < row_b
			return int(a["order"]) < int(b["order"])
	)
	var result: Array[String] = []
	for entry in entries:
		result.append(String(entry["id"]))
	return result


## 动态注册一条通用信息项；相同标识不会重复创建。
func register_info_item(definition: Dictionary) -> PlayerStatusInfoItem:
	var item_id := String(definition.get("id", ""))
	if item_id == "":
		return null
	if _items.has(item_id):
		return _items[item_id] as PlayerStatusInfoItem
	var row_index := clampi(int(definition.get("row", 1)), 0, _rows.size() - 1)
	var item := PlayerStatusInfoItem.new()
	item.name = "Item_%s" % item_id.replace(":", "_")
	item.configure(definition)
	if row_index == 0 and _rows[row_index].get_child_count() > 0:
		var separator := ColorRect.new()
		separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		separator.color = Color(0.86, 0.89, 0.94, 0.36)
		separator.custom_minimum_size = Vector2(1.0, 18.0)
		separator.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_rows[row_index].add_child(separator)
		_separators[item_id] = separator
	_rows[row_index].add_child(item)
	item.hovered.connect(_on_item_hovered)
	item.unhovered.connect(_on_item_unhovered)
	item.minimum_size_changed.connect(_queue_layout)
	item.refresh_summary()
	_items[item_id] = item
	_definitions[item_id] = definition.duplicate()
	_queue_layout()
	return item


## 注销并移除一条通用信息项；物资默认注册项不会在正式场景中注销。
func unregister_info_item(item_id: String) -> bool:
	var item := _items.get(item_id) as PlayerStatusInfoItem
	if item == null:
		return false
	if _hovered_item == item:
		_close_detail()
	var separator := _separators.get(item_id) as ColorRect
	if separator != null:
		separator.get_parent().remove_child(separator)
		separator.queue_free()
		_separators.erase(item_id)
	var parent := item.get_parent()
	if parent != null:
		parent.remove_child(item)
	item.queue_free()
	_items.erase(item_id)
	_definitions.erase(item_id)
	_queue_layout()
	return true


## 返回第一条材料、第二条状态行的当前摘要快照。
func get_item_summaries() -> Dictionary:
	var summaries: Dictionary = {}
	for item_id in _items:
		var item := _items[item_id] as PlayerStatusInfoItem
		summaries[item_id] = item.get_summary_text()
	return summaries


## 返回供无头验收读取的布局、注册、悬停和详情状态。
func get_debug_snapshot() -> Dictionary:
	var item_accepts_mouse := true
	for item in _items.values():
		if (item as PlayerStatusInfoItem).mouse_filter != Control.MOUSE_FILTER_STOP:
			item_accepts_mouse = false
			break
	return {
		"item_ids": get_registered_item_ids(),
		"summaries": get_item_summaries(),
		"bar_position": _surface.position,
		"bar_size": _surface.size,
		"bar_accepts_mouse": _surface.mouse_filter == Control.MOUSE_FILTER_STOP,
		"item_accepts_mouse": item_accepts_mouse,
		"surface_fill_alpha": StatusBarSurface.FILL_COLOR.a,
		"text_alpha": (_items.values()[0] as PlayerStatusInfoItem).get_text_alpha(),
		"detail_open": is_detail_open(),
		"detail_fetch_count": _detail_fetch_count,
		"detail_text": _get_detail_plain_text(),
	}


## 返回当前详情面板是否可见。
func is_detail_open() -> bool:
	return _detail_panel != null and _detail_panel.visible


## 按 dd天tt刻 格式返回四位补零的游戏时间。
static func format_game_time(day: int, tick_of_day: int) -> String:
	var display_day := maxi(day, 0) + 1
	var display_tick := clampi(tick_of_day, 0, TickManager.TICKS_PER_DAY - 1)
	return "%04d天%04d刻" % [display_day, display_tick]


## 按当前 [member TickManager.humans] 统计儿童、成人和老人。[br]
## 只包含仍在场景树、有效且未排进删除队列的居民。
func get_population_counts() -> Dictionary:
	var counts := {
		GlobalEnum.AgeStatus.CHILD: 0,
		GlobalEnum.AgeStatus.ADULT: 0,
		GlobalEnum.AgeStatus.OLD: 0,
	}
	for human in TickManager.humans:
		if (
			not is_instance_valid(human)
			or not human.is_inside_tree()
			or human.is_queued_for_deletion()
		):
			continue
		if counts.has(human.age_status):
			counts[human.age_status] = int(counts[human.age_status]) + 1
	return counts


## 按年龄阶段统计当前没有有效雇主的居民人数。[br]
## “无工作”以是否拥有有效雇主为准，不随当刻是否在班或是否正在动作变化。
func get_unemployed_population_counts() -> Dictionary:
	var counts := {
		GlobalEnum.AgeStatus.CHILD: 0,
		GlobalEnum.AgeStatus.ADULT: 0,
		GlobalEnum.AgeStatus.OLD: 0,
	}
	for human in TickManager.humans:
		if (
			not is_instance_valid(human)
			or not human.is_inside_tree()
			or human.is_queued_for_deletion()
			or human.has_employer()
		):
			continue
		if counts.has(human.age_status):
			counts[human.age_status] = int(counts[human.age_status]) + 1
	return counts


## 返回人口摘要文本。
func get_population_summary() -> String:
	var counts := get_population_counts()
	return "儿童 %d  成人 %d  老人 %d" % [
		int(counts[GlobalEnum.AgeStatus.CHILD]),
		int(counts[GlobalEnum.AgeStatus.ADULT]),
		int(counts[GlobalEnum.AgeStatus.OLD]),
	]


## 返回人口悬停详情。
func get_population_detail() -> Array[Dictionary]:
	var counts := get_unemployed_population_counts()
	var rows: Array[Dictionary] = [
		{"label": "儿童无工作", "value": str(int(counts[GlobalEnum.AgeStatus.CHILD]))},
		{"label": "成人无工作", "value": str(int(counts[GlobalEnum.AgeStatus.ADULT]))},
		{"label": "老人无工作", "value": str(int(counts[GlobalEnum.AgeStatus.OLD]))},
	]
	return [{"title": "无工作人口", "rows": rows}]


## 返回当前时间摘要。
func get_time_summary() -> String:
	return format_game_time(TickManager.get_day(), TickManager.get_tick_of_day())


## 创建倒置梯形底板、两行内容容器和统一详情面板。
func _build() -> void:
	_surface = StatusBarSurface.new()
	_surface.name = "Surface"
	add_child(_surface)

	var content_margin := MarginContainer.new()
	content_margin.name = "ContentMargin"
	content_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_margin.add_theme_constant_override("margin_left", int(SIDE_PADDING))
	content_margin.add_theme_constant_override("margin_right", int(SIDE_PADDING))
	content_margin.add_theme_constant_override("margin_top", int(VERTICAL_PADDING))
	content_margin.add_theme_constant_override("margin_bottom", int(VERTICAL_PADDING))
	_surface.add_child(content_margin)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 4)
	content.minimum_size_changed.connect(_queue_layout)
	content_margin.add_child(content)

	for _row_index in range(2):
		var row := HBoxContainer.new()
		row.name = "Row%d" % _row_index
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		content.add_child(row)
		_rows.append(row)

	_build_detail_panel()


## 创建统一详情面板和其中的纵向内容容器。
func _build_detail_panel() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.065, 0.075, 0.095, 0.96)
	style.border_color = Color(0.88, 0.91, 0.96, 0.26)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)

	_detail_panel = PanelContainer.new()
	_detail_panel.name = "DetailPanel"
	_detail_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_detail_panel.add_theme_stylebox_override("panel", style)
	_detail_panel.custom_minimum_size = Vector2(220.0, 0.0)
	_detail_panel.visible = false
	add_child(_detail_panel)

	_detail_body = VBoxContainer.new()
	_detail_body.name = "DetailBody"
	_detail_body.add_theme_constant_override("separation", 6)
	_detail_panel.add_child(_detail_body)


## 连接库存、建筑、居民和时间事件；不建立逐帧轮询。
func _connect_event_sources() -> void:
	MaterialSystem.status_item_registered.connect(_on_status_item_registered)
	MaterialSystem.inventory_changed.connect(_on_material_data_changed)
	MaterialSystem.status_sources_changed.connect(_on_material_data_changed)
	TickManager.tick_advanced.connect(_on_tick_advanced)
	TickManager.human_registered.connect(_on_population_data_changed)
	TickManager.human_unregistered.connect(_on_population_data_changed)
	TickManager.human_changed.connect(_on_population_data_changed)


## 注册人口和时间两条正式状态信息项。
func _register_status_items() -> void:
	register_info_item({
		"id": "population",
		"row": 1,
		"order": 0,
		"title": "人口",
		"icon": POPULATION_ICON,
		"show_title": false,
		"summary_provider": Callable(self, "get_population_summary"),
		"detail_provider": Callable(self, "get_population_detail"),
		"refresh_channels": [&"population"],
	})
	register_info_item({
		"id": "time",
		"row": 1,
		"order": 1,
		"title": "时间",
		"icon": TIME_ICON,
		"show_title": false,
		"summary_provider": Callable(self, "get_time_summary"),
		# 时间只保留摘要，不参与悬停详情。
		"detail_provider": Callable(),
		"refresh_channels": [&"time"],
	})


## 物资脚本完成一次显示注册后，按事件动态创建对应信息项。
func _on_status_item_registered(definition: Dictionary) -> void:
	register_info_item(definition)


## 仓库数量、锁定量、预留量或无限来源发生变化时刷新物资通道。
func _on_material_data_changed(_data: Variant = null) -> void:
	_refresh_channel(&"materials")


## 居民登记、离场或年龄阶段变化时刷新人口通道。
func _on_population_data_changed(_human: Human) -> void:
	_refresh_channel(&"population")


## 时间推进时只刷新时间摘要和已打开的时间详情。
func _on_tick_advanced(_total_ticks: int, _day: int, _tick_of_day: int) -> void:
	_refresh_channel(&"time")


## 刷新关心 [param channel] 的信息项；详情关闭时不会调用任何详情提供者。
func _refresh_channel(channel: StringName) -> void:
	for item_id in _items:
		var item := _items[item_id] as PlayerStatusInfoItem
		if not item.refresh_channels.has(channel):
			continue
		item.refresh_summary()
		if _hovered_item == item and is_detail_open():
			_refresh_detail(item)


## 鼠标进入信息项时立即获取一次最新详情。
func _on_item_hovered(item: PlayerStatusInfoItem) -> void:
	_hovered_item = item
	_refresh_detail(item)


## 鼠标离开信息项时关闭详情并停止后续详情刷新。
func _on_item_unhovered(item: PlayerStatusInfoItem) -> void:
	if _hovered_item == item:
		_close_detail()


## 向当前信息项获取详情；空内容由信息项自身决定为“不显示”。
func _refresh_detail(item: PlayerStatusInfoItem) -> void:
	_detail_fetch_count += 1
	var content := item.get_detail_content()
	if content.is_empty():
		_detail_content.clear()
		_detail_panel.visible = false
		return
	if content == _detail_content and _detail_panel.visible:
		_layout_detail_panel()
		return
	_detail_content = content.duplicate(true)
	_rebuild_detail_content()
	_detail_panel.visible = true
	_layout_detail_panel()


## 关闭并清空详情面板；关闭后不再保留内容生成来源。
func _close_detail() -> void:
	_hovered_item = null
	_detail_content.clear()
	if _detail_panel != null:
		_detail_panel.visible = false


## 使用通用板块、标题和文本行重建详情内容。
func _rebuild_detail_content() -> void:
	for child in _detail_body.get_children():
		_detail_body.remove_child(child)
		child.queue_free()
	var first_section := true
	for section in _detail_content:
		if not first_section:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0.0, 4.0)
			_detail_body.add_child(gap)
		first_section = false
		var heading := Label.new()
		heading.text = String(section.get("title", "详情"))
		heading.add_theme_font_size_override("font_size", 15)
		heading.add_theme_color_override("font_color", Color(1.0, 0.86, 0.46))
		_detail_body.add_child(heading)
		for row in section.get("rows", []):
			if not row is Dictionary:
				continue
			var row_box := HBoxContainer.new()
			row_box.add_theme_constant_override("separation", 18)
			_detail_body.add_child(row_box)
			var label := Label.new()
			label.text = String(row.get("label", ""))
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.add_theme_font_size_override("font_size", 13)
			label.add_theme_color_override("font_color", Color(0.76, 0.81, 0.88))
			row_box.add_child(label)
			var value := Label.new()
			value.text = String(row.get("value", ""))
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			value.add_theme_font_size_override("font_size", 13)
			value.add_theme_color_override("font_color", Color.WHITE)
			row_box.add_child(value)


## 让状态栏宽度随信息项动态变化，并始终在视口顶部居中。
func _queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	call_deferred("_layout_status_bar")


## 根据当前内容最小尺寸重排状态栏底板。
func _layout_status_bar() -> void:
	_layout_queued = false
	if _surface == null or _rows.is_empty():
		return
	var content_margin := _surface.get_node_or_null("ContentMargin") as MarginContainer
	var content := content_margin.get_node_or_null("Content") as VBoxContainer
	if content == null:
		return
	var content_size := content.get_combined_minimum_size()
	var bar_width := maxf(content_size.x + SIDE_PADDING * 2.0, MIN_BAR_WIDTH)
	var bar_height := content_size.y + VERTICAL_PADDING * 2.0
	var viewport_size := get_viewport().get_visible_rect().size
	_surface.position = Vector2(
		roundf((viewport_size.x - bar_width) * 0.5),
		TOP_MARGIN,
	)
	_surface.size = Vector2(roundf(bar_width), roundf(bar_height))
	if is_detail_open():
		_layout_detail_panel()


## 将详情面板放在悬停信息项下方，并限制在视口范围内。
func _layout_detail_panel() -> void:
	if not is_detail_open() or _hovered_item == null:
		return
	var minimum := _detail_panel.get_combined_minimum_size()
	_detail_panel.size = Vector2(
		maxf(minimum.x, 220.0),
		minimum.y,
	)
	var viewport_size := get_viewport().get_visible_rect().size
	var item_rect := _hovered_item.get_global_rect()
	var x := item_rect.get_center().x - _detail_panel.size.x * 0.5
	x = clampf(x, 8.0, maxf(viewport_size.x - _detail_panel.size.x - 8.0, 8.0))
	var y := _surface.position.y + _surface.size.y + 8.0
	_detail_panel.position = Vector2(roundf(x), roundf(y))


## 返回当前详情内容的纯文本，供无头验收确认动态刷新。
func _get_detail_plain_text() -> String:
	var parts: Array[String] = []
	for section in _detail_content:
		parts.append(String(section.get("title", "")))
		for row in section.get("rows", []):
			if row is Dictionary:
				parts.append("%s=%s" % [
					String(row.get("label", "")),
					String(row.get("value", "")),
				])
	return " | ".join(parts)
