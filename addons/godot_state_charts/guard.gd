@icon("guard.svg")
class_name Guard
extends Resource

## Returns true if the guard is satisfied, false otherwise.
func is_satisfied(_context_transition:Transition, _context_state:StateChartState) -> bool:
	push_error("未实现 Guard.is_satisfied()。是否忘记重写该方法？")
	return false

## Returns the triggers which should trigger the guard's evaluation. This is a bit mask of [StateChart.TriggerType].
func get_supported_trigger_types() -> int:
	push_error("未实现 Guard._get_supported_trigger_types()。是否忘记重写该方法？")
	return StateChart.TriggerType.NONE
