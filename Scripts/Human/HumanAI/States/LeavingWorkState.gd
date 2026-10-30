## 居民从工作站内部离开到新目标的过渡状态。[br]
## 进入时先确认新路线可达，由 [HumanMotion] 原子完成离站；退出时兜底清理残留占用。
extends HumanStateBase


## 返回离站状态的稳定键。
func _state_key() -> StringName:
	return &"leaving_work"


## 进入离站状态时启动当前目标路线，成功后才发送离站路线事件。
func _on_enter() -> void:
	if _controller.start_travel_to_current_target():
		_send(HumanAI.EVENT_EXIT_ROUTE_STARTED)


## 每刻验证目标是否仍然有效。
func _on_step() -> void:
	if not _controller.is_target_valid():
		_send(HumanAI.EVENT_TARGET_INVALID)


## 离开该状态时若仍在建筑内，兜底执行离站。
func _on_exit() -> void:
	if is_instance_valid(_human.in_building):
		_controller.motion.leave_current_building()
