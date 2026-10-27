extends HumanStateBase

## 旅程状态：普通目标保持承诺，工作行程仍响应工作闸门和紧急生存需求。


func _state_key() -> StringName:
	return &"traveling"


func _on_enter() -> void:
	if (
		_controller.get_goal() == HumanAI.Goal.WORK
		and not _controller.is_work_allowed()
	):
		_send(HumanAI.EVENT_WORK_CANCELLED)
		return
	_controller.start_travel_to_current_target()


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


func _on_exit() -> void:
	_controller.motion.stop()
