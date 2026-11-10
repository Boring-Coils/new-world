## 居民随身携带的物资。[br]
## 只记录数量与体积，不做容量限制；谁能在什么时候取用由工作周期决定。[br]
## 与 [Inventory] 不同，背包不参与账本锁定，也不提供空间预留。
class_name CarryBag
extends RefCounted

## 背包内容发生变化时发出，参数是当前全部物品的副本。
signal items_changed(items: Dictionary)

## 物资类型到携带数量的映射。
var items: Dictionary = {}


## 创建背包并把所有已知物资数量初始化为 0。
func _init() -> void:
	for item_type in MaterialTypes.get_item_types():
		items[item_type] = 0


## 返回 [param item_type] 的携带数量，负数按 0 处理。
func get_item_count(item_type: int) -> int:
	return maxi(int(items.get(item_type, 0)), 0)


## 返回全部携带物品的副本，数量为 0 的条目已被剔除。
func get_items() -> Dictionary:
	var snapshot: Dictionary = {}
	for item_type in items:
		var quantity := get_item_count(int(item_type))
		if quantity > 0:
			snapshot[int(item_type)] = quantity
	return snapshot


## 返回全部携带物占用的总体积。
func get_used_volume() -> int:
	return MaterialTypes.get_total_volume(get_items())


## 返回背包是否没有任何物品。
func is_empty() -> bool:
	return get_items().is_empty()


## 判断背包是否满足 [param demand] 中的每种物品数量。[br]
## [param demand] 是物资类型到需求数量的字典；空需求视为满足。
func has_at_least(demand: Dictionary) -> bool:
	for item_type in demand:
		if get_item_count(int(item_type)) < maxi(int(demand[item_type]), 0):
			return false
	return true


## 向背包加入物资并发出变更信号。[br]
## [param items_to_add] 是物资类型到新增数量的字典；非正数量会被忽略。
func add_items(items_to_add: Dictionary) -> void:
	var changed := false
	for item_type in items_to_add:
		var quantity := maxi(int(items_to_add[item_type]), 0)
		if quantity <= 0:
			continue
		items[int(item_type)] = get_item_count(int(item_type)) + quantity
		changed = true
	if changed:
		items_changed.emit(get_items())


## 从背包移除最多 [param quantity] 个指定物资，返回实际移除数量。[br]
## [param item_type] 是要移除的物资类型。
func remove_items(item_type: int, quantity: int) -> int:
	var removed := mini(maxi(quantity, 0), get_item_count(item_type))
	if removed <= 0:
		return 0
	items[item_type] = get_item_count(item_type) - removed
	items_changed.emit(get_items())
	return removed


## 清空背包并返回清空前的数量快照。
func clear_items() -> Dictionary:
	var snapshot := get_items()
	if snapshot.is_empty():
		return snapshot
	for item_type in items:
		items[int(item_type)] = 0
	items_changed.emit({})
	return snapshot
