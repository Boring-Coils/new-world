@tool
@icon("atomic_state.svg")
## This is a state that has no sub-states.
class_name AtomicState
extends StateChartState

func _handle_transition(transition:Transition, source:StateChartState) -> void:
	# resolve the target state
	var target := transition.resolve_target()
	if target == null:
		push_error("从“" + source.name + "”发起的转换，其目标状态“" + str(transition.to) + "”不是状态。")
		return
	# atomic states cannot transition, so we need to ask the parent
	# ask the parent
	get_parent()._handle_transition(transition, source)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := super._get_configuration_warnings()
	# check if we have any child nodes which are not transitions
	for child in get_children():
		if child is StateChartState:
			warnings.append("原子状态不能包含子状态；这些子状态将被忽略。")
			break
	return warnings
