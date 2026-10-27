extends AtomicState
class_name HumanStateBase

## 居民状态脚本的公共绑定与插件信号适配层。

var _controller: HumanAI
var _human: Human
var _bound: bool = false


func _ready() -> void:
	super._ready()
	state_entered.connect(_handle_state_entered)
	state_stepped.connect(_handle_state_stepped)
	state_exited.connect(_handle_state_exited)


func bind(controller: HumanAI, host: Human) -> void:
	_controller = controller
	_human = host
	_bound = true


func _handle_state_entered() -> void:
	if not _bound or not is_instance_valid(_controller):
		push_error("%s 在绑定前被激活" % name)
		return
	_controller.notify_state_entered(_state_key(), self)
	_on_enter()


func _handle_state_stepped() -> void:
	if _bound and is_instance_valid(_controller):
		_on_step()


func _handle_state_exited() -> void:
	if _bound and is_instance_valid(_controller):
		_on_exit()


func _send(event: StringName) -> void:
	if _bound and is_instance_valid(_controller):
		_controller.send_event(event)


func get_debug_data() -> Dictionary:
	return {}


func _state_key() -> StringName:
	return StringName(name.to_snake_case())


func _on_enter() -> void:
	pass


func _on_step() -> void:
	pass


func _on_exit() -> void:
	pass
