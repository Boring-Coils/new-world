extends Node2D
class_name CameraRig

## 相机支架：创建 [Camera2D]，并负责平移。[br]
## 独立成一个节点，而不是把逻辑塞进 [World] 的 [_process]——因为子类（比如 TestScene）[br]
## 一旦自己写了 [_process]，父类的 [_process] 就不会再被调用，键盘平移会莫名其妙失灵。[br]
## 本节点是 [World] 的子节点，有自己的 [_process]，不跟任何人抢。[br]
## 操作：[br]
## - 中键按住拖动：鼠标往哪拖，画面就往哪走[br]
## - [code]WASD[/code] / 方向键：持续平移（触控板没有中键时用这个）[br]
## 平移速度按「屏幕像素/秒」算，再除以缩放，所以放大以后拖起来手感不变。

## 相机初始对着哪里（格坐标）
const START_CELL := Vector2(471.0, 496.0)

## 初始缩放倍数（1 格 = [constant WorldGrid.CELL_SIZE] 像素，放大 4 倍才看得清小人）
const START_ZOOM := Vector2(4.0, 4.0)

## 方向键平移速度（屏幕像素 / 秒）
const KEY_PAN_SPEED: float = 900.0

## 相机本体
var _camera: Camera2D

## 中键是不是正按着
var _dragging: bool = false


func _ready() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera"
	_camera.position = START_CELL * WorldGrid.CELL_SIZE
	_camera.zoom = START_ZOOM
	add_child(_camera)
	_camera.make_current()


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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_dragging = event.pressed
		return

	if event is InputEventMouseMotion and _dragging:
		# 屏幕位移 ÷ 缩放 = 世界位移；减号表示「画面跟着鼠标走」
		_camera.position -= event.relative / _camera.zoom


## 当前相机，给需要知道视野范围的代码用
func get_camera() -> Camera2D:
	return _camera
