## 居民在建筑出入口等待服务的状态。[br]
## 进入时读取建筑服务耗时，每刻递减并处理工作闸门、紧急中断和完成事件。
extends HumanStateBase

# 当前服务剩余刻数。
var _wait_left: int = 0


## 返回等待状态的稳定键。
func _state_key() -> StringName:
	return &"waiting"


## 进入等待时验证目标并初始化建筑提供的等待刻数。
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


## 每刻处理目标失效、工作中断，并推进服务倒计时。
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


## 等待结束时向控制器询问完成事件并发送给状态机。
func _finish_wait() -> void:
	_send(_controller.complete_current_wait())


## 返回等待状态用于调试面板的剩余刻数。
func get_debug_data() -> Dictionary:
	return {"wait_left": maxi(_wait_left, 0)}
