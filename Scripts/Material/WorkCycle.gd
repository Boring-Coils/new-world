## 单个居民执行一次工作的运行时状态。[br]
## 记录雇主、工作者、工作配置、物资锁、产出预留和倒计时；生命周期与雇佣关系绑定。[br]
## 账本只通过 [MaterialSystem] 修改该对象持有的锁与预留标识。
class_name WorkCycle
extends RefCounted

## 工作周期在物资账本中的状态。[br]
## 状态按准备、锁定、待结算、完成或取消的单向流程推进。
enum Status {
	## 正在检查工作前置条件并准备需求物资。
	PREPARING,
	## 需求物资已全部锁定，工作可以安全推进。
	LOCKED,
	## 工作耗时已结束，正在等待产出预检和结算。
	PENDING_SETTLEMENT,
	## 产出已成功写入库存，周期正常结束。
	COMPLETED,
	## 周期被取消，相关锁和预留已经或正在释放。
	CANCELLED,
}

## 周期编号，用于生成账本中的持有者标识。
var cycle_id: int = 0

## 发起并接收本次工作结果的建筑。
var employer: Building = null

## 执行本次工作的居民。
var human: Human = null

## 本次工作的固定配置。
var work_type: WorkType = null

## 周期当前状态。
var status: Status = Status.PREPARING

## 已锁定的需求物品标识，键指向 [MaterialSystem] 中的锁记录。
var demand_locks: Array[String] = []

## 已预留的产出空间标识，键指向 [MaterialSystem] 中的预留记录。
var output_reservations: Array[String] = []

## 按工作配置计算出的标准产出总体积。
var expected_output_volume: int = 0

## 距离工作完成还需推进的刻数。
var remaining_ticks: int = 0

## 本次工作已经推进的刻数。
var elapsed_ticks: int = 0

## 本次工作开始时的全局累计刻数。
var started_tick: int = 0


## 创建工作周期并初始化标准耗时与产出体积。[br]
## [param id_value] 是周期编号，[param employer_value] 是雇主，[param human_value] 是工作者，[br]
## [param type_value] 是工作配置；传入前必须保证工作配置有效。
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


## 返回物资账本使用的周期持有者标识。
func get_holder_id() -> String:
	return "cycle:%d" % cycle_id


## 返回周期是否已经锁定全部需求物资并可继续推进。
func is_locked() -> bool:
	return status == Status.LOCKED


## 返回周期是否已经正常完成或被取消。
func is_finished() -> bool:
	return status == Status.COMPLETED or status == Status.CANCELLED
