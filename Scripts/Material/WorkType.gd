## 一类固定工作的不可变配置。[br]
## 描述工作标识、需求物资、标准产出和基础耗时；运行时进度与锁定状态保存在 [WorkCycle]。[br]
## 构造时会复制需求和产出字典，避免调用方后续修改共享配置。
class_name WorkType
extends RefCounted

## 工作的稳定标识，用于存档、日志和类型区分。
var id: StringName = &""

## 面向玩家显示的工作名称。
var display_name: String = ""

## 完成一次工作所需的模拟刻数，最小值为 1。
var duration_ticks: int = 60

## 每次工作开始时需要锁定的物资数量，键为物资类型。
var demand: Dictionary = {}

## 工作成功结算时产出的标准物资数量，键为物资类型。
var output: Dictionary = {}


## 创建一份工作配置。[br]
## [param work_id] 是稳定标识，[param work_display_name] 是显示名称，[param work_duration_ticks] 是基础耗时，[br]
## [param work_demand] 是需求物资，[param work_output] 是标准产出；两个字典都会被复制。
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


## 返回完成一次工作所需物资的总体积。
func get_demand_volume() -> int:
	return MaterialTypes.get_total_volume(demand)


## 返回完成一次工作标准产出的总体积。
func get_output_volume() -> int:
	return MaterialTypes.get_total_volume(output)


## 返回为工作准备物资所需的供给提前量。[br]
## [param path_ticks] 是预计路程耗时；结果包含工作耗时并额外保留约 10% 的安全余量。
func get_required_supply_ticks(path_ticks: int = 0) -> int:
	# 固定工作耗时与预计路程之和，再留 10% 安全余量。
	var total_ticks := maxi(path_ticks, 0) + duration_ticks
	@warning_ignore("integer_division")
	return (total_ticks * 110 + 99) / 100


## 创建默认的线材加工工作配置：消耗金属和塑料，产出线材。[br]
## 返回新建的线材加工配置。
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


## 创建废料分拣工作配置：消耗废料，产出金属、塑料和线材。[br]
## 返回新建的废料分拣配置。
static func create_scrap_sorting() -> WorkType:
	return WorkType.new(
		&"scrap_sorting",
		"废料分拣",
		60,
		{
			MaterialTypes.ItemType.WASTE: 6,
		},
		{
			MaterialTypes.ItemType.METAL: 1,
			MaterialTypes.ItemType.PLASTIC: 1,
			MaterialTypes.ItemType.WIRE: 1,
		},
	)
