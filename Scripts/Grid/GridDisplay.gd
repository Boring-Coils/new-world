extends Node2D
class_name GridDisplay

## 网格显示：在地图上画出和 [WorldGrid] 完全对齐的白色细线。[br]
##
## 只画摄像机看得到的那一块，不然 1000 × 1000 格全画出来会糊成一片白。

## 是否显示网格（默认开）
@export var show_grid: bool = true

## 线的颜色
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.35)

## 线的粗细（屏幕像素）
@export var line_width: float = 1.0


func _process(_delta: float) -> void:
	if show_grid:
		queue_redraw()


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
