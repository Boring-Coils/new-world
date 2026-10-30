extends Node2D
class_name Human

## 居民实体：持有生存数据、绑定场景组件，并按固定顺序调度每刻结算。

const MAX_WATER: float = 700.0
const MAX_FOOD: float = 700.0

@export var age: int = 20
@export var age_status: GlobalEnum.AgeStatus = GlobalEnum.AgeStatus.ADULT
@export var water: float = MAX_WATER
@export var food: float = MAX_FOOD

## 衣服颜色只能使用已渲染的预设。
@export var outfit: GlobalEnum.Outfit = GlobalEnum.Outfit.BLUE:
	set(value):
		outfit = value
		if is_instance_valid(visual):
			visual.outfit = value

@onready var buff_system: BuffSystem = $BuffSystem
@onready var visual: HumanVisual = $Visual
@onready var motion: HumanMotion = $Motion
@onready var ai: HumanAI = $HumanAI

## 当前所在的建筑；进入工作站和原子离站都通过该字段表达占用关系。
var in_building: Building = null

## 当前雇主。一个居民同一时间最多只有一个有效雇主。
var employer: Building = null

## 等待点附近的稳定个人偏移，绝对值不超过半格（5 像素）。
var wait_offset: Vector2 = Vector2.ZERO


## 居民必须从场景实例化，否则会缺少 AI、Motion 和 BuffSystem。
static func create() -> Human:
	return load("res://Scenes/Human/Human.tscn").instantiate() as Human


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


func _exit_tree() -> void:
	if is_instance_valid(ai):
		ai.cleanup_before_removal()
	if is_instance_valid(employer):
		employer.dismiss_employee(self, "居民离开场景")
		employer = null
	TickManager.unregister_human(self)


func bind_employer(building: Building) -> void:
	employer = building


func notify_employment_ended(building: Building, reason: String) -> void:
	if employer == building:
		employer = null
	if is_instance_valid(ai):
		ai.on_employment_ended(building, reason)


func has_employer() -> bool:
	return is_instance_valid(employer)


func can_work() -> bool:
	return is_instance_valid(buff_system) and buff_system.can_work()


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


func _consume() -> void:
	var consume_scale := buff_system.get_consume_multiplier()
	water -= get_daily_water() / float(TickManager.TICKS_PER_DAY) * consume_scale
	food -= get_daily_food() / float(TickManager.TICKS_PER_DAY) * consume_scale
	if water <= 0.0 or food <= 0.0:
		buff_system.add_buff(GlobalEnum.BuffType.WEAKNESS)


func get_daily_water() -> float:
	match age_status:
		GlobalEnum.AgeStatus.CHILD:
			return 500.0
		GlobalEnum.AgeStatus.OLD:
			return 1500.0
		_:
			return 1700.0


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


## 工作站等系统通过语义接口控制居民显隐，不直接操作 HumanVisual 内部节点。
func set_world_visibility(is_visible: bool) -> void:
	visual.visible = is_visible


func die() -> void:
	queue_free()
