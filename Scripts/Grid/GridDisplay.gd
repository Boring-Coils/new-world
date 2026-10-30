## 世界网格的帧级可视层。[br]
## 根据当前相机的可见矩形只绘制屏幕范围内的网格线，避免遍历整个世界。[br]
## 本类只负责表现，不修改格子的通行状态或寻路数据。
extends Node2D
class_name GridDisplay

## 是否显示网格（默认开）
@export var show_grid: bool = true

## 线的颜色
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.35)

## 线的粗细（屏幕像素）
@export var line_width: float = 1.0


## 网格开启时请求每帧重绘，以跟随相机移动和缩放。[br]
## [param _delta] 是当前帧间隔；重绘由相机状态驱动，因此本方法不使用该值。
func _process(_delta: float) -> void:
	if show_grid:
		queue_redraw()


## 绘制当前视口覆盖范围内的网格线，并按相机缩放补偿线宽。
func _draw() -> void:
	if not show_grid:
		return

	var world := WorldGridGlobal.world
	var cells := world.get_cells()
	var cell_size := float(WorldGrid.CELL_SIZE)

	# 算出摄像机当前看得到的世界矩形
	var to_world := get_viewport().get_canvas_transform().affine_inverse()
	var top_left := to_world * Vector2.ZERO
	var bottom_right := to_world * get_viewport_rect().size
	var view := Rect2(top_left, bottom_right - top_left).abs()

	# 换成格子范围，并夹到世界边界内
	var x_from := clampi(floori(view.position.x / cell_size), 0, cells.x)
	var x_to := clampi(ceili(view.end.x / cell_size), 0, cells.x)
	var y_from := clampi(floori(view.position.y / cell_size), 0, cells.y)
	var y_to := clampi(ceili(view.end.y / cell_size), 0, cells.y)

	# 线宽要除以缩放，否则 zoom 放大会变粗
	var zoom := get_viewport().get_canvas_transform().get_scale().x
	var width := line_width / maxf(zoom, 0.0001)

	# 竖线
	for x in range(x_from, x_to + 1):
		var px := float(x) * cell_size
		draw_line(Vector2(px, view.position.y), Vector2(px, view.end.y), line_color, width)
	# 横线
	for y in range(y_from, y_to + 1):
		var py := float(y) * cell_size
		draw_line(Vector2(view.position.x, py), Vector2(view.end.x, py), line_color, width)
