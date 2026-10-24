@icon("state_chart.svg")
@tool
## This is statechart. It contains a root state (commonly a compound or parallel state) and is the entry point for
## the state machine.
class_name StateChart
extends Node

## The the remote debugger
const DebuggerRemote = preload("utilities/editor_debugger/editor_debugger_remote.gd")

## The state chart utility class.
const StateChartUtil = preload("utilities/state_chart_util.gd")

## Emitted when the state chart receives an event. This will be
## emitted no matter which state is currently active and can be
## useful to trigger additional logic elsewhere in the game
## without having to create a custom event bus. It is also used
## by the state chart debugger. Note that this will emit the
## events in the order in which they are processed, which may
## be different from the order in which they were received. This is
## because the state chart will always finish processing one event
## fully before processing the next. If an event is received
## while another is still processing, it will be enqueued.
signal event_received(event:StringName)

@export_group("调试")
## Flag indicating if this state chart should be tracked by the
## state chart debugger in the editor.
@export var track_in_editor:bool = false

## If set, the state chart will issue a warning when trying to
## send an event that is not configured for any transition of
## the state chart. It is usually a good idea to leave this
## enabled, but in certain cases this may get in the way so
## you can disable it here.
@export var warn_on_sending_unknown_events:bool = true

@export_group("")
## Initial values for the expression properties. These properties can be used in expressions, e.g
## for guards or transition delays. It is recommended to set an initial value for each property
## you use in an expression to ensure that this expression is always valid. If you don't set
## an initial value, some expressions may fail to be evaluated if they use a property that has
## not been set yet.
@export var initial_expression_properties:Dictionary = {}

## The root state of the state chart.
var _state:StateChartState = null

## This dictonary contains known properties used in expression guards. Use the
## [method set_expression_property] to add properties to this dictionary.
var _expression_properties:Dictionary = {
}

## A list of pending events
var _queued_events:Array[StringName] = []

## Whether or not a property change is pending.
var _property_change_pending:bool = false

## Whether or not a state change occured during processing and we need to re-run
## automatic transitions that may have been triggered by the state change.
var _state_change_pending:bool = false

## Flag indicating if the state chart is currently processing.
## Until a change is fully processed, no further changes can
## be introduced from the outside.
var _locked_down:bool = false

## Flag indicating if the state chart is frozen.
## If the state chart is frozen, new events and transitions will be discarded.
var _frozen:bool = false

var _queued_transitions:Array[Dictionary] = []
var _transitions_processing_active:bool = false

var _debugger_remote:DebuggerRemote = null
var _valid_event_names:Array[StringName] = []

## A trigger type that defines events that can trigger a transition.
enum TriggerType {
	## No trigger type. This usually should not happen and is used as a default value.
	NONE = 0,
	## The transition will be triggered by an event.
	EVENT = 1,
	## The transition is automatic and thus will be triggered when the state is entered.
	STATE_ENTER = 2,
	## The transition is automatic and will be triggered by a property change.
	PROPERTY_CHANGE = 4,
	## The transition is automatic and will be triggered by a state change.
	STATE_CHANGE = 8,
}

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	# check if we have exactly one child that is a state
	if get_child_count() != 1:
		push_error("StateChart 必须且只能有一个子节点。")
		return

	# check if the child is a state
	var child:Node = get_child(0)
	if not child is StateChartState:
		push_error("StateChart 的子节点必须是状态。")
		return

	# in debug builds, collect a list of valid event names
	# to warn the developer when using an event that doesn't
	# exist.
	if OS.is_debug_build():
		_valid_event_names = StateChartUtil.events_of(self)

	# set the initial expression properties
	if initial_expression_properties != null:
		for key in initial_expression_properties.keys():
			if not key is String and not key is StringName:
				push_error("表达式属性名必须是字符串。正在忽略键为 ", key, " 的初始表达式属性。")
				continue
			_expression_properties[key] = initial_expression_properties[key]

	# initialize the state machine
	_state = child as StateChartState
	_state._state_init()

	# We wait one frame before entering initial state, so
	# parents of the state chart have a chance to run their
	# _ready methods first and not get events from the state
	# chart while they have not yet been initialized
	_enter_initial_state.call_deferred()

	# if we are in an editor build and this chart should be tracked
	# by the debugger, create a debugger remote
	if track_in_editor and OS.has_feature("editor") and not Engine.is_editor_hint():
		_debugger_remote = DebuggerRemote.new(self)
		# add the remote as a child, so it gets cleaned up when the state
		# chart is deleted
		add_child(_debugger_remote)


func _enter_initial_state() -> void:
	# https://github.com/derkork/godot-statecharts/issues/143
	# make sure that transitions resulting from state_enter handlers still
	# adhere our transactional processing
	_transitions_processing_active = true
	_locked_down = true

	# enter the state
	_state._state_enter(null)

	# run any queued transitions that may have come up during the enter
	_run_queued_transitions()

	# run any queued external events that may have come up during the enter
	_run_changes()


## Sends an event to this state chart. The event will be passed to the innermost active state first and
## is then moving up in the tree until it is consumed. Events will trigger transitions and actions via emitted
## signals. There is no guarantee when the event will be processed. The state chart
## will process the event as soon as possible but there is no guarantee that the
## event will be fully processed when this method returns.
func send_event(event:StringName) -> void:
	if _frozen:
		push_error("状态图当前已冻结，无法发送事件。")

		return

	if not is_node_ready():
		push_error("状态图尚未就绪。如果在 _ready 中调用 `send_event`，请延迟调用，例如 `state_chart.send_event.call_deferred(\"my_event\")`。")
		return

	if not is_instance_valid(_state):
		push_error("状态图没有根状态，正在忽略对 `send_event` 的调用。")
		return

	if warn_on_sending_unknown_events and event != "" and OS.is_debug_build() and not _valid_event_names.has(event):
		push_warning("状态图未定义事件“", event, "”。发送此事件不会产生任何效果。")

	_queued_events.append(event)
	if _locked_down:
		return

	_run_changes()


## Sets a property that can be used in expression guards. The property will be available as a global variable
## with the same name. E.g. if you set the property "foo" to 42, you can use the expression "foo == 42" in
## an expression guard.
func set_expression_property(property_name:StringName, value) -> void:
	if _frozen:
		push_error("状态图当前已冻结，无法设置表达式属性。")
		return

	if not is_node_ready():
		push_error("状态图尚未就绪。如果在 `_ready` 中调用 `set_expression_property`，请延迟调用，例如 `state_chart.set_expression_property.call_deferred(\"my_property\", 5)`。")
		return

	if not is_instance_valid(_state):
		push_error("状态图没有根状态，正在忽略对 `set_expression_property` 的调用。")
		return

	_expression_properties[property_name] = value
	_property_change_pending = true

	if not _locked_down:
		_run_changes()


## Returns the value of a previously set expression property. If the property does not exist, the default value
## will be returned.
func get_expression_property(property_name:StringName, default:Variant = null) -> Variant:
	return _expression_properties.get(property_name, default)


func _run_changes() -> void:
	# enable the reentrance lock
	_locked_down = true

	while (not _queued_events.is_empty()) or _property_change_pending or _state_change_pending:
		# We process stuff in this order:
		# 1. State changes
		if _state_change_pending:
			_state_change_pending = false
			_state._process_transitions(TriggerType.STATE_CHANGE)

		# 2. Property changes
		if _property_change_pending:
			_property_change_pending = false
			_state._process_transitions(TriggerType.PROPERTY_CHANGE)

		# 3. Events
		if not _queued_events.is_empty():
			# process the next event
			var next_event = _queued_events.pop_front()
			event_received.emit(next_event)
			_state._process_transitions(TriggerType.EVENT, next_event)

	_locked_down = false


## Allows states to queue a transition for running. This will eventually run the transition
## once all currently running transitions have finished. States should call this method
## when they want to transition away from themselves.
func _run_transition(transition:Transition, source:StateChartState) -> void:
	# Queue up the transition for running
	_queued_transitions.append({transition : source})

	# if we are currently inside of a transition, finish processing the queue so we
	# get a predictable order. Queing can happen a state has an automatic transition on enter,
	# or when a transition is triggered as part of a signal handler. In these cases, we want to
	# finish the current transition before starting a new one because otherwise the transitions
	# see really unpredictable state changes. In a sense, every transition is also a
	# transaction that needs to be fully processed before the next one can start.
	if _transitions_processing_active:
		return

	_run_queued_transitions()


## Runs all queued transitions until none are left. This also checks for infinite loops in transitions and
## ensures triggering guards on state changes.
func _run_queued_transitions() -> void:

	_transitions_processing_active = true

	var execution_count := 1

	# if we still have transitions
	while _queued_transitions.size() > 0:
		var next_transition_entry = _queued_transitions.pop_front()
		var next_transition = next_transition_entry.keys()[0]
		var next_transition_source = next_transition_entry[next_transition]
		_do_run_transition(next_transition, next_transition_source)
		execution_count += 1

		if execution_count > 100:
			push_error("检测到转换存在无限循环。正在中止，状态图现已处于无效状态且无法继续使用。")
			break

	_transitions_processing_active = false

	# transitions trigger a state change which can in turn activate
	# other transitions, so we need to handle these
	if not _locked_down:
		_run_changes()


## Runs the transition. Used internally by the state chart, do not call this directly.
func _do_run_transition(transition:Transition, source:StateChartState) -> void:
	if source.active:
		# Notify interested parties that the transition is about to be taken
		transition.taken.emit()
		source._handle_transition(transition, source)
		_state_change_pending = true
	else:
		_warn_not_active(transition, source)


func _warn_not_active(transition:Transition, source:StateChartState) -> void:
	push_warning("源状态已不再活动，正在忽略从 ", source.name, " 到 ", transition.to, " 的转换请求。请检查是否在同一帧内触发了多次状态变更。")



## Calls the `step` function in all active states. Used for situations where `state_processing` and
## `state_physics_processing` don't make sense (e.g. turn-based games, or games with a fixed timestep).
func step() -> void:
	if _frozen:
		push_error("状态图当前已冻结，无法步进。")
		return

	if not is_node_ready():
		push_error("状态图尚未就绪。如果在 `_ready` 中调用 `step`，请延迟调用，例如 `state_chart.step.call_deferred()`。")
		return

	if not is_instance_valid(_state):
		push_error("状态图没有根状态，正在忽略对 `step` 的调用。")
		return
	_state._state_step()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings:PackedStringArray = []
	if get_child_count() != 1:
		warnings.append("StateChart 必须且只能有一个子节点。")
	else:
		var child:Node = get_child(0)
		if not child is StateChartState:
			warnings.append("StateChart 的子节点必须是状态。")
	return warnings


## Freezes the state chart and all states. While frozen, no changes can be made to a state chart.
func freeze() -> void:
	_frozen = true
	var to_freeze:Array[StateChartState] = [_state]
	while not to_freeze.is_empty():
		var next:StateChartState = to_freeze.pop_back()
		next._toggle_processing(true)
		for child in next.get_children():
			if child is StateChartState:
				to_freeze.append(child)

## Thaws the state chart and all states. After being thawed, changes can again be made to the state chart.
func thaw() -> void:
	var to_thaw:Array[StateChartState] = [_state]
	while not to_thaw.is_empty():
		var next:StateChartState = to_thaw.pop_back()
		next._toggle_processing(false)
		for child in next.get_children():
			if child is StateChartState:
				to_thaw.append(child)

	_frozen = false
