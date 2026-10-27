extends HumanStateBase

## 空闲状态：清理残留目标，并按决策周期选择下一项。


func _state_key() -> StringName:
	return &"idle"


func _on_enter() -> void:
	_controller.on_idle_entered()


func _on_step() -> void:
	if _controller.try_select_idle_goal():
		_send(HumanAI.EVENT_GOAL_SELECTED)
