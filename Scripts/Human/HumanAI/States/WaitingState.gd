extends HumanStateBase

## 等待状态：按游戏刻递减建筑服务时间。

var _wait_left: int = 0


func _state_key() -> StringName:
	return &"waiting"


func _on_enter() -> void:
	var target := _controller.get_target()
	if not is_instance_valid(target):
		_send(HumanAI.EVENT_TARGET_INVALID)
		return
	if (
		_controller.get_goal() == HumanAI.Goal.WORK
		and not _controller.is_work_allowed()
	):
		_send(HumanAI.EVENT_WORK_CANCELLED)
		return

	_wait_left = target.get_wait_ticks()
	if _wait_left <= 0:
		_finish_wait()


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
			return

	_wait_left -= 1
	if _wait_left <= 0:
		_finish_wait()


func _finish_wait() -> void:
	_send(_controller.complete_current_wait())


func get_debug_data() -> Dictionary:
	return {"wait_left": maxi(_wait_left, 0)}
