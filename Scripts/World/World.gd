extends Node2D
class_name World

## 所有世界场景的根节点骨架：负责「看得见但摸不着」的那层基础设施。[br]
## 现在只有相机和网格，以后世界级的东西（光照、天气、全局着色）也挂这里。[br]
## [b]不要往本类塞任何游戏规则[/b]——建筑、居民、资源一律属于 Colony / TestScene 那一层，[br]
## 否则空场景也会莫名其妙地摆出东西来。

## 相机对着哪里（格坐标）
const CAMERA_CELL := Vector2(471.0, 496.0)

## 相机缩放倍数（1 格 = [constant WorldGrid.CELL_SIZE] 像素，放大 4 倍才看得清小人）
const CAMERA_ZOOM := Vector2(4.0, 4.0)


func _ready() -> void:
	_setup_camera()
	_setup_grid()


func _setup_camera() -> void:
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.position = CAMERA_CELL * WorldGrid.CELL_SIZE
	camera.zoom = CAMERA_ZOOM
	add_child(camera)
	camera.make_current()


func _setup_grid() -> void:
	var grid := GridDisplay.new()
	grid.name = "GridDisplay"
	# 画在人和建筑下面
	grid.z_index = -10
	add_child(grid)
