## 居民实体及每刻生存结算入口。[br]
## 持有年龄、水分、食物、雇佣关系和建筑占用状态，并绑定 Buff、表现、移动与 AI 组件。[br]
## 每刻固定先推进 Buff、再扣基础消耗、最后推进 AI；场景实体必须通过 [method create] 创建。
extends Node2D
class_name Human

## 居民水分的最大值，补水后恢复到该值。
const MAX_WATER: float = 700.0

## 居民食物的最大值，进食后恢复到该值。
const MAX_FOOD: float = 700.0

## 居民年龄，用于展示和雇佣资格判断。
@export var age: int = 20

## 居民年龄阶段，决定移动速度、日消耗和可雇佣范围。
@export var age_status: GlobalEnum.AgeStatus = GlobalEnum.AgeStatus.ADULT

## 当前水分；降到 0 或以下会触发虚弱。
@export var water: float = MAX_WATER

## 当前食物；降到 0 或以下会触发虚弱。
@export var food: float = MAX_FOOD

## 衣服颜色只能使用已渲染的预设。
@export var outfit: GlobalEnum.Outfit = GlobalEnum.Outfit.BLUE:
	set(value):
		outfit = value
		if is_instance_valid(visual):
			visual.outfit = value

## 管理当前居民全部 Buff 的组件。
@onready var buff_system: BuffSystem = $BuffSystem

## 负责序列帧、朝向和移动动画的外部表现组件。
@onready var visual: HumanVisual = $Visual

## 负责寻路、逐刻移动和离站动作的移动组件。
@onready var motion: HumanMotion = $Motion

## 负责目标选择和状态机推进的行为协调组件。
@onready var ai: HumanAI = $HumanAI

## 当前所在的建筑；进入工作站和原子离站都通过该字段表达占用关系。
var in_building: Building = null

## 当前雇主。一个居民同一时间最多只有一个有效雇主。
var employer: Building = null

## 等待点附近的稳定个人偏移，绝对值不超过半格（5 像素）。
var wait_offset: Vector2 = Vector2.ZERO


## 居民必须从场景实例化，否则会缺少 AI、Motion 和 BuffSystem。[br]
## 返回从居民场景实例化出的完整居民节点。
static func create() -> Human:
	return load("res://Scenes/Human/Human.tscn").instantiate() as Human


## 绑定子组件、连接表现信号并把居民登记到 [TickManager]。
func _ready() -> void:
	_init_wait_offset()
	buff_system.attach(self)
	visual.outfit = outfit
	visual.set_moving(false)

	motion.bind(self)
	motion.moving_changed.connect(visual.set_moving)
	motion.facing_changed.connect(visual.set_facing)

	ai.bind(self)
	TickManager.register_human(self)


## 离开场景时取消工作与雇佣关系，并注销每刻更新。
func _exit_tree() -> void:
	if is_instance_valid(ai):
		ai.cleanup_before_removal()
	if is_instance_valid(employer):
		employer.dismiss_employee(self, "居民离开场景")
		employer = null
	TickManager.unregister_human(self)


## 建立与 [param building] 的雇佣关系；调用方负责同步建筑的雇员名单。
func bind_employer(building: Building) -> void:
	employer = building


## 接收雇佣结束通知，清理雇主引用并让 AI 取消相关工作状态。[br]
## [param building] 是结束雇佣关系的建筑。[br]
## [param reason] 是取消工作周期时记录的结束原因。
func notify_employment_ended(building: Building, reason: String) -> void:
	if employer == building:
		employer = null
	if is_instance_valid(ai):
		ai.on_employment_ended(building, reason)


## 返回当前是否存在有效雇主。
func has_employer() -> bool:
	return is_instance_valid(employer)


## 返回所有 Buff 工作闸门汇总后的工作许可。
func can_work() -> bool:
	return is_instance_valid(buff_system) and buff_system.can_work()


## 根据实例编号生成稳定、确定性的等待点小幅偏移。
func _init_wait_offset() -> void:
	var seed_value := absi(hash(get_instance_id()))
	var x_ratio := float(seed_value % 1001) / 1000.0
	var y_ratio := float((seed_value / 1001) % 1001) / 1000.0
	wait_offset = Vector2(x_ratio * 8.0 - 4.0, y_ratio * 8.0 - 4.0)


## 每刻固定顺序：Buff 结算、基础消耗、AI 决策与行动。
func on_tick() -> void:
	buff_system.on_tick()
	_consume()
	ai.on_tick()


## 按年龄对应的日消耗、刻数和 Buff 倍率扣除水与食物。[br]
## 任一资源降到 0 或以下时尝试添加虚弱 Buff。
func _consume() -> void:
	var consume_scale := buff_system.get_consume_multiplier()
	water -= get_daily_water() / float(TickManager.TICKS_PER_DAY) * consume_scale
	food -= get_daily_food() / float(TickManager.TICKS_PER_DAY) * consume_scale
	if water <= 0.0 or food <= 0.0:
		buff_system.add_buff(GlobalEnum.BuffType.WEAKNESS)


## 返回当前年龄阶段对应的每日基础水分消耗。
func get_daily_water() -> float:
	match age_status:
		GlobalEnum.AgeStatus.CHILD:
			return 500.0
		GlobalEnum.AgeStatus.OLD:
			return 1500.0
		_:
			return 1700.0


## 返回当前年龄阶段对应的每日基础食物消耗。
func get_daily_food() -> float:
	match age_status:
		GlobalEnum.AgeStatus.CHILD:
			return 800.0
		GlobalEnum.AgeStatus.OLD:
			return 1500.0
		_:
			return 1900.0


## 放置系统请求脱困的唯一入口。
func relocate_out() -> void:
	ai.request_relocation()


## 工作站等系统通过语义接口控制居民显隐，不直接操作 HumanVisual 内部节点。[br]
## [param is_visible] 指定居民模型是否应在世界中显示。
func set_world_visibility(is_visible: bool) -> void:
	visual.visible = is_visible


## 立即安排居民离开场景；相关清理由场景树退出流程完成。
func die() -> void:
	queue_free()
