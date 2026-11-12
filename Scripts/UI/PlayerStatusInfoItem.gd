## 玩家状态栏中的一条通用信息项。[br]
## 摘要和详情都由注册时提供的 [Callable] 决定，状态栏不识别水、人口或时间类型。
extends PanelContainer
class_name PlayerStatusInfoItem

## 鼠标进入该信息项时发出。
signal hovered(item: PlayerStatusInfoItem)

## 鼠标离开该信息项时发出。
signal unhovered(item: PlayerStatusInfoItem)

## 信息项的稳定标识。
var item_id: String = ""

## 信息项固定标题，用于详情和可访问提示。
var title: String = ""

## 固定图标或标题外观数据。
var icon_texture: Texture2D = null

## 是否在摘要旁显示标题文字。
var show_title: bool = false

## 摘要值提供者；每次相关数据变化时由状态栏调用。
var summary_provider: Callable

## 详情提供者；只有详情展开或展开期间收到相关变化时才调用。
var detail_provider: Callable

## 该信息项摘要和详情关心的稳定刷新通道。
var refresh_channels: Array[StringName] = []

# 摘要文本控件。
var _value_label: Label = null

# 固定标题控件。
var _title_label: Label = null

# 图标控件。
var _icon: TextureRect = null

# 普通与悬停背景样式。
var _normal_style: StyleBoxFlat = null
var _hover_style: StyleBoxFlat = null


## 使用状态栏注册定义配置信息项；必须在加入场景树前调用。
func configure(definition: Dictionary) -> void:
	item_id = String(definition.get("id", ""))
	title = String(definition.get("title", ""))
	icon_texture = definition.get("icon") as Texture2D
	show_title = bool(definition.get("show_title", false))
	summary_provider = definition.get("summary_provider", Callable())
	detail_provider = definition.get("detail_provider", Callable())
	refresh_channels.clear()
	for channel in definition.get("refresh_channels", []):
		refresh_channels.append(StringName(channel))
	if is_inside_tree():
		_build()
		refresh_summary()


## 构建图标、可选标题和摘要文本，并连接鼠标悬停事件。
func _ready() -> void:
	_build()
	refresh_summary()


## 重新计算摘要文本；内容完全相同时不触发界面更新。
func refresh_summary() -> void:
	if _value_label == null:
		return
	var new_text := String(summary_provider.call()) if summary_provider.is_valid() else ""
	if _value_label.text != new_text:
		_value_label.text = new_text
		tooltip_text = "%s：%s" % [title, new_text] if title != "" else new_text


## 返回摘要提供者当前给出的文本。
func get_summary_text() -> String:
	return _value_label.text if _value_label != null else ""


## 返回当前信息项使用的图标贴图。
func get_icon_texture() -> Texture2D:
	return _icon.texture if _icon != null else null


## 返回图标是否保持白色调制，用于验收统一白色图标契约。
func has_white_icon() -> bool:
	return _icon != null and _icon.modulate.is_equal_approx(Color.WHITE)


## 返回详情提供者当前给出的通用板块内容。
func get_detail_content() -> Array[Dictionary]:
	if not detail_provider.is_valid():
		return []
	var result: Variant = detail_provider.call()
	if result is Array:
		var normalized: Array[Dictionary] = []
		for section in result:
			if section is Dictionary:
				normalized.append(section)
		return normalized
	return []


## 创建信息项视觉控件。
func _build() -> void:
	if _icon != null:
		return
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(38.0, 28.0)
	_normal_style = _make_style(false)
	_hover_style = _make_style(true)
	add_theme_stylebox_override("panel", _normal_style)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	add_child(row)

	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.texture = icon_texture
	_icon.modulate = Color.WHITE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(20.0, 20.0)
	row.add_child(_icon)

	if show_title:
		_title_label = Label.new()
		_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_title_label.text = title
		_title_label.add_theme_font_size_override("font_size", 14)
		_title_label.add_theme_color_override("font_color", Color(0.76, 0.81, 0.88))
		row.add_child(_title_label)

	_value_label = Label.new()
	_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_value_label.add_theme_font_size_override("font_size", 15)
	_value_label.add_theme_color_override("font_color", Color.WHITE)
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_value_label)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


## 创建信息项可复用的透明和悬停底板样式。
func _make_style(hover: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.09 if hover else 0.0)
	style.set_corner_radius_all(3)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style


## 鼠标进入时切换悬停样式并让状态栏决定是否显示详情。
func _on_mouse_entered() -> void:
	add_theme_stylebox_override("panel", _hover_style)
	hovered.emit(self)


## 鼠标离开时恢复普通样式并通知状态栏关闭详情。
func _on_mouse_exited() -> void:
	add_theme_stylebox_override("panel", _normal_style)
	unhovered.emit(self)
