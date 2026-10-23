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
	_setup_detail_panel()


## 右侧详情页：属于世界级 UI，所以放这里，Colony 和 TestScene 都有
func _setup_detail_panel() -> void:
	var panel := BuildingDetailPanel.new()
	panel.name = "BuildingDetailPanel"
	add_child(panel)


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


## 全局调试快捷键：空格暂停/继续，数字 1~4 切倍速。[br]
## 放在 World 而不是某个具体场景里，这样 Colony 和 TestScene 都自带这套操作。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		TickManager.auto_run = not TickManager.auto_run
		print("[SIM] 时间%s" % ("继续" if TickManager.auto_run else "暂停"))
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				TickManager.speed_multiplier = 1.0
			KEY_2:
				TickManager.speed_multiplier = 2.0
			KEY_3:
				TickManager.speed_multiplier = 5.0
			KEY_4:
				TickManager.speed_multiplier = 20.0
			_:
				return
		print("[SIM] 倍速 x%.0f" % TickManager.speed_multiplier)
