## 居民空闲状态。[br]
## 进入时清理残留目标和移动，每刻按决策间隔尝试选择下一个生存或工作目标。
extends HumanStateBase


## 返回空闲状态的稳定键。
func _state_key() -> StringName:
	return &"idle"


## 进入空闲状态时通知控制器执行清理。
func _on_enter() -> void:
	_controller.on_idle_entered()


## 每刻尝试选择目标，成功时发送目标已选择事件。
func _on_step() -> void:
	if _controller.try_select_idle_goal():
		_send(HumanAI.EVENT_GOAL_SELECTED)
