extends HumanStateBase

## 工作站内状态：进入时登记占用，每刻检查工作闸门和生存中断。


func _state_key() -> StringName:
	return &"working"


func _on_enter() -> void:
	if not _controller.is_work_allowed() or not _controller.begin_work_cycle():
		_send(HumanAI.EVENT_WORK_CANCELLED)


func _on_step() -> void:
	match _controller.evaluate_work_interrupt():
		HumanAI.WorkInterrupt.NONE:
			pass
		HumanAI.WorkInterrupt.CANCEL:
			_controller.cancel_work_cycle("硬中断")
			_send(HumanAI.EVENT_WORK_CANCELLED)
			return
		HumanAI.WorkInterrupt.TRAVEL:
			_send(HumanAI.EVENT_WORK_INTERRUPTED)
			return

	var result := _controller.tick_work_cycle()
	if result == &"completed" or result == &"cancelled":
		_send(HumanAI.EVENT_WORK_CANCELLED)
