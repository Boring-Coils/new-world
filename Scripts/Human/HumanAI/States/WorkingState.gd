## 居民在工作站内部执行工作周期的状态。[br]
## 进入时登记站内占用并启动工作周期，每刻处理硬中断和周期结算结果。
extends HumanStateBase


## 返回工作状态的稳定键。
func _state_key() -> StringName:
	return &"working"


## 进入工作时检查工作许可并启动周期，失败则取消。
func _on_enter() -> void:
	if not _controller.is_work_allowed() or not _controller.begin_work_cycle():
		_send(HumanAI.EVENT_WORK_CANCELLED)


## 每刻处理工作中断，再推进工作周期直到完成或取消。
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
