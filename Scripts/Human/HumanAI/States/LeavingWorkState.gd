extends HumanStateBase

## 离站状态：先确认新路线并原子离站，再切换到旅程状态。


func _state_key() -> StringName:
	return &"leaving_work"


func _on_enter() -> void:
	if _controller.start_travel_to_current_target():
		_send(HumanAI.EVENT_EXIT_ROUTE_STARTED)


func _on_step() -> void:
	if not _controller.is_target_valid():
		_send(HumanAI.EVENT_TARGET_INVALID)


func _on_exit() -> void:
	if is_instance_valid(_human.in_building):
		_controller.motion.leave_current_building()
