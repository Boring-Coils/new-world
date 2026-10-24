static func evaluate_expression(context:String, state_chart: StateChart, expression: String, default_value:Variant) -> Variant:
	var the_expression := Expression.new()
	var input_names := state_chart._expression_properties.keys()

	var parse_result:int = the_expression.parse(expression, input_names)

	if parse_result != OK:
		push_error("（" + context + "）表达式解析错误。尝试解析表达式：“" \
			+ expression \
			+ "”，但收到错误：“" + the_expression.get_error_text() + "”。")
		return default_value

	# input values need to be in the same order as the input names, so we build an array
	# of values
	var input_values:Array = []
	for input_name in input_names:
		input_values.append(state_chart._expression_properties[input_name])

	var result = the_expression.execute(input_values, null, false)
	if the_expression.has_execute_failed():
		push_error("（" + context + "）表达式执行错误。尝试运行表达式：“" \
			+ expression \
			+ "”，但收到错误：“" + the_expression.get_error_text() + "”。")
		return default_value

	return result
