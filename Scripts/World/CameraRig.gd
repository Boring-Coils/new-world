## 世界场景的相机创建、平移和缩放控制器。[br]
## 使用独立的 [code]_process[/code] 处理键盘平移，避免与场景根节点的帧循环互相覆盖。[br]
## 中键拖动移动画面，WASD 或方向键持续平移，滚轮以屏幕中心为锚点缩放。
extends Node2D
class_name CameraRig

## 相机初始对着哪里（格坐标）
const START_CELL := Vector2(471.0, 496.0)

## 初始缩放倍数（1 格 = [constant WorldGrid.CELL_SIZE] 像素，放大 4 倍才看得清小人）
const START_ZOOM := Vector2(4.0, 4.0)

## 方向键平移速度（屏幕像素 / 秒）
const KEY_PAN_SPEED: float = 900.0

## 滚轮每一格的缩放倍数
const ZOOM_STEP: float = 1.1

## 缩放上下限：太小看不清格子，太大全糊
const ZOOM_MIN: float = 0.8

## 最大缩放倍数，超过后画面细节不再增加。
const ZOOM_MAX: float = 16.0

# 相机本体。
var _camera: Camera2D

# 中键是否正被按住。
var _dragging: bool = false


## 创建当前场景使用的 [Camera2D]，设置初始位置与缩放并启用相机。
func _ready() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera"
	_camera.position = START_CELL * WorldGrid.CELL_SIZE
	_camera.zoom = START_ZOOM
	add_child(_camera)
	_camera.make_current()


## 处理每帧键盘平移，并在中键意外松开时结束拖动状态。
func _process(delta: float) -> void:
	# 拖到一半在中键之外松开、或者窗口失焦，别让相机一直粘着鼠标
	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_dragging = false

	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y += 1.0

	if direction != Vector2.ZERO:
		# 除以 zoom：屏幕上的 900 像素，在放大 4 倍时只对应世界的 225 像素
		_camera.position += direction.normalized() * KEY_PAN_SPEED * delta / _camera.zoom.x


## 处理中键拖动、滚轮缩放和拖动时的鼠标位移。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_dragging = event.pressed
		return

	# 滚轮缩放，以屏幕中心为锚点（相机本来就盯着屏幕正中，所以只改 zoom 就行）
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(ZOOM_STEP)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0 / ZOOM_STEP)
			return

	if event is InputEventMouseMotion and _dragging:
		# 屏幕位移 ÷ 缩放 = 世界位移；减号表示「画面跟着鼠标走」
		_camera.position -= event.relative / _camera.zoom


## 缩放 [param factor] 倍，[b]以屏幕中心为锚点[/b]。[br]
## 相机永远盯着屏幕正中（Camera2D 默认的 drag center 模式），所以「中心不动」在这里[br]
## 就等于「只改 zoom、不动 position」——不用算鼠标底下的世界点。
func _zoom(factor: float) -> void:
	if _camera == null:
		return

	var zoom_new := clampf(_camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(_camera.zoom.x, zoom_new):
		return

	_camera.zoom = Vector2(zoom_new, zoom_new)


## 当前相机，给需要知道视野范围的代码用
func get_camera() -> Camera2D:
	return _camera
