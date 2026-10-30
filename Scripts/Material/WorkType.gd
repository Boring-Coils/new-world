class_name WorkType
extends RefCounted

## 一次工作周期所需物品、标准产出和固定工作时长。

var id: StringName = &""
var display_name: String = ""
var duration_ticks: int = 60
var demand: Dictionary = {}
var output: Dictionary = {}


func _init(
	work_id: StringName = &"",
	work_display_name: String = "",
	work_duration_ticks: int = 60,
	work_demand: Dictionary = {},
	work_output: Dictionary = {},
) -> void:
	id = work_id
	display_name = work_display_name
	duration_ticks = maxi(work_duration_ticks, 1)
	demand = work_demand.duplicate()
	output = work_output.duplicate()


func get_demand_volume() -> int:
	return MaterialTypes.get_total_volume(demand)


func get_output_volume() -> int:
	return MaterialTypes.get_total_volume(output)


func get_required_supply_ticks(path_ticks: int = 0) -> int:
	# 固定工作耗时与预计路程之和，再留 10% 安全余量。
	var total_ticks := maxi(path_ticks, 0) + duration_ticks
	@warning_ignore("integer_division")
	return (total_ticks * 110 + 99) / 100


static func create_fabrication() -> WorkType:
	return WorkType.new(
		&"fabrication",
		"线材加工",
		60,
		{
			MaterialTypes.ItemType.METAL: 1,
			MaterialTypes.ItemType.PLASTIC: 1,
		},
		{
			MaterialTypes.ItemType.WIRE: 1,
		},
	)
