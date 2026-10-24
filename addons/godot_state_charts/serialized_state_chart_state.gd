# This class is used to serialize a state chart state to a resource. It is intended 
# to make it easier to save and load state charts, as well as to transfer them
# over the network if needed. See also SerializedStateChartResource.
class_name SerializedStateChartState
extends Resource

@export var name: StringName = ""
@export var state_type: int = -1
@export var active: bool = false
@export var pending_transition_name: String = ""
@export var pending_transition_remaining_delay: float = 0.0
@export var pending_transition_initial_delay: float = 0.0
@export var children: Array[SerializedStateChartState] = []

# Only used for history states
@export var history: SavedState = null


func _to_string() -> String:
	return """SerializedStateChartState(
		名称: %s
		状态类型: %s
		活动: %s
		待执行转换名称: %s
		待执行转换剩余延迟: %s
		待执行转换初始延迟: %s
		子状态: %s
		历史记录: %s
	)""" % [
		name,
		state_type,
		active,
		pending_transition_name,
		pending_transition_remaining_delay,
		pending_transition_initial_delay,
		JSON.stringify(children, "\t"),
		history.debug_string() if history != null else "null"
	]
