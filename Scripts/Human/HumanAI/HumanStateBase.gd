## 居民动作状态的公共基类。[br]
## 把 [code]godot_state_charts[/code] 的原子状态信号转换为 AI 控制器可调用的进入、步进和退出钩子。[br]
## 子类通过 [method _state_key] 提供状态标识，并覆盖 [method _on_enter]、[method _on_step] 或 [method _on_exit]。
extends AtomicState
class_name HumanStateBase

# 拥有该状态的居民 AI 控制器。
var _controller: HumanAI

# 该状态当前服务的居民实例。
var _human: Human

# 是否已完成控制器与居民绑定。
var _bound: bool = false


## 调用插件基类初始化，并连接状态的进入、步进和退出信号。
func _ready() -> void:
	super._ready()
	state_entered.connect(_handle_state_entered)
	state_stepped.connect(_handle_state_stepped)
	state_exited.connect(_handle_state_exited)


## 绑定状态所属的 [param controller] 和 [param host] 居民。
func bind(controller: HumanAI, host: Human) -> void:
	_controller = controller
	_human = host
	_bound = true


## 插件进入信号适配：通知控制器当前状态，再执行子类进入逻辑。
func _handle_state_entered() -> void:
	if not _bound or not is_instance_valid(_controller):
		push_error("%s 在绑定前被激活" % name)
		return
	_controller.notify_state_entered(_state_key(), self)
	_on_enter()


## 插件步进信号适配：仅在已绑定时执行子类步进逻辑。
func _handle_state_stepped() -> void:
	if _bound and is_instance_valid(_controller):
		_on_step()


## 插件退出信号适配：仅在已绑定时执行子类退出清理。
func _handle_state_exited() -> void:
	if _bound and is_instance_valid(_controller):
		_on_exit()


## 向所属 AI 状态机发送 [param event]；未绑定时安全忽略。
func _send(event: StringName) -> void:
	if _bound and is_instance_valid(_controller):
		_controller.send_event(event)


## 返回状态的调试附加数据；基类默认为空，子类可按需覆盖。
func get_debug_data() -> Dictionary:
	return {}


## 返回状态在状态机中的稳定键；默认由节点名转换为 snake_case。
func _state_key() -> StringName:
	return StringName(name.to_snake_case())


## 状态进入时的子类扩展点，默认不执行操作。
func _on_enter() -> void:
	pass


## 状态每刻步进时的子类扩展点，默认不执行操作。
func _on_step() -> void:
	pass


## 状态退出时的子类扩展点，默认不执行操作。
func _on_exit() -> void:
	pass
