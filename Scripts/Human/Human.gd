extends Node2D
class_name Human

## 居民实体。[br]
## 负责年龄、水 / 食物储量、每天消耗量、Buff 和外观；[br]
## 决策、寻路、移动与等待统一交给 [HumanAI]。

## 水 / 食物储量上限（每个人固定）
const MAX_WATER: float = 700.0
const MAX_FOOD: float = 700.0

## 年龄
@export var age: int = 20

## 年龄段（决定日耗）
@export var age_status: GlobalEnum.AgeStatus = GlobalEnum.AgeStatus.ADULT

## 当前储水量（ml）
@export var water: float = MAX_WATER

## 当前储食物量（g）
@export var food: float = MAX_FOOD

## 衣服颜色。只能从预设里选（见 [enum GlobalEnum.Outfit]），不给自由 RGB。
@export var outfit: GlobalEnum.Outfit = GlobalEnum.Outfit.BLUE:
	set(value):
		outfit = value
		if is_instance_valid(visual):
			visual.outfit = value

## 行为决策、路径与移动状态
var ai: HumanAI

## 挂在身上的状态效果，子节点，见 [BuffSystem]
@onready var buff_system: BuffSystem = $BuffSystem

## 外观节点，子节点，见 [HumanVisual]
@onready var visual: HumanVisual = $Visual


## 创建一个居民节点。[br]
## 居民身上的子节点（比如 [BuffSystem]）都写在 Human.tscn 里，所以别直接 [code]Human.new()[/code]。
static func create() -> Human:
	return load("res://Scenes/Human/Human.tscn").instantiate() as Human


func _ready() -> void:
	buff_system.attach(self)
	visual.outfit = outfit
	visual.set_moving(false)
	ai = HumanAI.new(self)
	TickManager.register_human(self)


func _exit_tree() -> void:
	TickManager.unregister_human(self)


## 每刻由 [TickManager] 调用。顺序保持为：Buff 结算、消耗、AI 决策与行动。
func on_tick() -> void:
	buff_system.on_tick()
	ai.enforce_work_gate()
	_consume()
	ai.on_tick()


## 每刻扣水扣食物，倍率由 buff 汇总（比如口渴会让水掉得更快）
func _consume() -> void:
	var consume_scale := buff_system.get_consume_multiplier()
	water -= get_daily_water() / float(TickManager.TICKS_PER_DAY) * consume_scale
	food -= get_daily_food() / float(TickManager.TICKS_PER_DAY) * consume_scale
	if water <= 0 or food <= 0:
		buff_system.add_buff(GlobalEnum.BuffType.WEAKNESS)


## 每日耗水量（ml）
func get_daily_water() -> float:
	match age_status:
		GlobalEnum.AgeStatus.CHILD:
			return 500.0
		GlobalEnum.AgeStatus.OLD:
			return 1500.0
		_:
			return 1700.0


## 每日耗食物量（g）
func get_daily_food() -> float:
	match age_status:
		GlobalEnum.AgeStatus.CHILD:
			return 800.0
		GlobalEnum.AgeStatus.OLD:
			return 1500.0
		_:
			return 1900.0


func die() -> void:
	queue_free()
