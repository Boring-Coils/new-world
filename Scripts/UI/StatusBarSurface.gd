## 玩家状态栏的倒置梯形底板。[br]
## 控件本身按矩形拦截鼠标，绘制时上边宽、下边窄，避免透明角落把事件传给世界。
extends Control
class_name StatusBarSurface

## 下边左右各向内收进的像素数。
const BOTTOM_INSET: float = 24.0

## 底板主色。
const FILL_COLOR: Color = Color(0.075, 0.085, 0.105, 0.94)

## 底板描边色。
const BORDER_COLOR: Color = Color(0.88, 0.91, 0.96, 0.24)


## 初始化鼠标拦截和重绘连接。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


## 绘制倒置梯形阴影、底板和清晰描边。
func _draw() -> void:
	var width := size.x
	var height := size.y
	if width <= 0.0 or height <= 0.0:
		return
	var shape := PackedVector2Array([
		Vector2.ZERO,
		Vector2(width, 0.0),
		Vector2(width - BOTTOM_INSET, height),
		Vector2(BOTTOM_INSET, height),
	])
	var shadow := PackedVector2Array()
	for point in shape:
		shadow.append(point + Vector2(0.0, 4.0))
	draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.28))
	draw_colored_polygon(shape, FILL_COLOR)
	var outline := shape.duplicate()
	outline.append(shape[0])
	draw_polyline(outline, BORDER_COLOR, 1.25, true)
