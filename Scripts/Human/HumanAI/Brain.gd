extends Node
class_name Brain

var human_motion: HumanMotion
var human: Human

## 状态 -> 处理该状态的节点 的映射表
var status_map: Dictionary[GlobalEnum.HumanStatus, StatusBase] = {}

## 被建筑压住了，走到旁边的空格子上
func evict_out() -> void:
    human_motion.relocate_to_nearest_walkable()

## 注册一个状态[br]
## 给对应的状态的节点用的，用于注册节点对应的状态。状态节点初始化的时候需要调用这个[br][br]
## 参数：[br]
## -[param status]： 状态[br]
## -[param status_base]： 处理该状态的节点，一般是调用者自身[br]
## [br]
## 返回值：[br]
## -是否注册成功[br]
## 当传入null或所注册的状态已经存在时会失败
func register_status(status: GlobalEnum.HumanStatus, status_base: StatusBase) -> bool:
    if status == null or status_base == null:# 应该不用判断status_base有没有被释放，因为在设计中表示单个状态的节点应该不可能比这个节点提前释放
        return false
    if status in status_map:
        return false
    status_map[status] = status_base
    return true
