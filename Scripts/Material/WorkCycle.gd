class_name WorkCycle
extends RefCounted

enum Status {
	PREPARING,
	LOCKED,
	PENDING_SETTLEMENT,
	COMPLETED,
	CANCELLED,
}

var cycle_id: int = 0
var employer: Building = null
var human: Human = null
var work_type: WorkType = null
var status: Status = Status.PREPARING
var demand_locks: Array[String] = []
var output_reservations: Array[String] = []
var expected_output_volume: int = 0
var remaining_ticks: int = 0
var elapsed_ticks: int = 0
var started_tick: int = 0


func _init(
	id_value: int,
	employer_value: Building,
	human_value: Human,
	type_value: WorkType,
) -> void:
	cycle_id = id_value
	employer = employer_value
	human = human_value
	work_type = type_value
	expected_output_volume = work_type.get_output_volume()
	remaining_ticks = work_type.duration_ticks


func get_holder_id() -> String:
	return "cycle:%d" % cycle_id


func is_locked() -> bool:
	return status == Status.LOCKED


func is_finished() -> bool:
	return status == Status.COMPLETED or status == Status.CANCELLED
