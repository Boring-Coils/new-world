@tool
@icon("expression_guard.svg")
class_name ExpressionGuard
extends Guard

const ExpressionUtil = preload("expression_util.gd")
const DebugUtil = preload("debug_util.gd")

var expression:String = ""


func is_satisfied(context_transition:Transition, context_state:StateChartState) -> bool:
	var root:StateChart = context_state._chart

	if not is_instance_valid(root):
		push_error("找不到根状态图节点，无法计算表达式。")
		return false

	var result:Variant = ExpressionUtil.evaluate_expression("“" + DebugUtil.path_of(context_transition) + "”中的守卫", root, expression, false)

	if typeof(result) != TYPE_BOOL:
		push_error("表达式“", expression, "”的结果“", result, "”不是布尔值，将返回 false。")
		return false

	return result

func get_supported_trigger_types() -> int:
	return StateChart.TriggerType.PROPERTY_CHANGE

func _get_property_list() -> Array[Dictionary]:
	var properties:Array[Dictionary] = []
	properties.append({
		"name": "expression",
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_EXPRESSION
	})

	return properties
