## 居民前往目标建筑的旅程状态。[br]
## 普通目标保持既定承诺；工作行程会响应工作闸门和紧急生存需求。[br]
## 状态退出时停止当前移动，路径失败由 Motion 信号另行投递。
extends HumanStateBase


## 返回旅程状态的稳定键。
func _state_key() -> StringName:
	return &"traveling"


## 进入旅程时启动当前目标路线；工作目标先检查工作闸门。
func _on_enter() -> void:
	if (
		_controller.get_goal() == HumanAI.Goal.WORK
		and not _controller.is_work_allowed()
	):
		_send(HumanAI.EVENT_WORK_CANCELLED)
		return
	_controller.start_travel_to_current_target()


## 每刻验证目标，并对工作行程执行硬闸门与紧急中断检查。
func _on_step() -> void:
	if not _controller.is_target_valid():
		_send(HumanAI.EVENT_TARGET_INVALID)
		return

	if _controller.get_goal() == HumanAI.Goal.WORK:
		if not _controller.is_work_allowed():
			_send(HumanAI.EVENT_WORK_CANCELLED)
			return
		if _controller.try_interrupt_work_goal():
			_send(HumanAI.EVENT_WORK_INTERRUPTED)


## 离开旅程状态时停止残留路径。
func _on_exit() -> void:
	_controller.motion.stop()
