## 居民被建筑压住后的脱困状态。[br]
## 暂停普通目标，委托 Motion 寻找安全格，并等待成功或失败结果驱动状态机。
extends HumanStateBase


## 返回脱困状态的稳定键。
func _state_key() -> StringName:
	return &"relocating"


## 进入脱困时启动移动；无法开始则离站并报告失败。
func _on_enter() -> void:
	if not _controller.begin_relocation():
		_controller.leave_work_now()
		_controller.report_relocation_failure()
		_send(HumanAI.EVENT_RELOCATION_FAILED)


## 每刻确认脱困移动仍在进行，否则报告失败。
func _on_step() -> void:
	if not _controller.is_relocating():
		_controller.report_relocation_failure()
		_send(HumanAI.EVENT_RELOCATION_FAILED)
