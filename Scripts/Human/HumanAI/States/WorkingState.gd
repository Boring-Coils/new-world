extends HumanStateBase

## 工作站内状态：进入时登记占用，每刻检查工作闸门和生存中断。


func _state_key() -> StringName:
	return &"working"


func _on_enter() -> void:
	if not _controller.is_work_allowed():
		_send(HumanAI.EVENT_WORK_CANCELLED)
		return
	if not _controller.enter_current_workstation():
		_send(HumanAI.EVENT_WORK_CANCELLED)


func _on_step() -> void:
	match _controller.evaluate_work_interrupt():
		HumanAI.WorkInterrupt.NONE:
			return
		HumanAI.WorkInterrupt.CANCEL:
			_controller.leave_work_now()
			_send(HumanAI.EVENT_WORK_CANCELLED)
		HumanAI.WorkInterrupt.TRAVEL:
			_send(HumanAI.EVENT_WORK_INTERRUPTED)
