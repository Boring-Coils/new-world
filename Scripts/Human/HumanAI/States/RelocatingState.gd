extends HumanStateBase

## 脱困状态：暂停普通目标，等待 Motion 给出成功或失败结果。


func _state_key() -> StringName:
	return &"relocating"


func _on_enter() -> void:
	if not _controller.begin_relocation():
		_controller.leave_work_now()
		_controller.report_relocation_failure()
		_send(HumanAI.EVENT_RELOCATION_FAILED)


func _on_step() -> void:
	if not _controller.is_relocating():
		_controller.report_relocation_failure()
		_send(HumanAI.EVENT_RELOCATION_FAILED)
