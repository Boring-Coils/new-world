## 单个仓库或建筑自带库存的物资账本。[br]
## 本类只保存数量、容量和预留体积事实；锁定、预留记录及持有者生命周期由 [MaterialSystem] 管理。[br]
## 未被账本登记的库存不会被其他系统视为有效库存。
class_name Inventory
extends RefCounted

## 账本分配的库存编号；未登记时为 -1。
var inventory_id: int = -1

## 库存所属建筑；虚拟测试库存可为 null。
var owner: Building = null

## 库存可容纳的总体积。
var capacity: int = 0

## 物资类型到当前数量的映射。
var items: Dictionary = {}

## 已被产出预留占用、不可再次分配的体积。
var reserved_volume: int = 0

## 是否已成功登记到 [MaterialSystem]。
var is_registered: bool = false


## 创建库存并把所有已知物资数量初始化为 0。[br]
## [param capacity_value] 是总体积容量，负数会被夹到 0。
func _init(capacity_value: int = 0) -> void:
	capacity = maxi(capacity_value, 0)
	for item_type in MaterialTypes.get_item_types():
		items[item_type] = 0


## 返回 [param item_type] 的当前库存数量，负数按 0 处理。
func get_item_count(item_type: int) -> int:
	return maxi(int(items.get(item_type, 0)), 0)


## 返回账本中已被其他持有者锁定的物资数量。[br]
## [param except_holder] 指定需要排除的持有者，便于其重新评估自身锁。
func get_locked_quantity(item_type: int, except_holder: String = "") -> int:
	if not is_registered:
		return 0
	return MaterialSystem.get_inventory_locked_quantity(self, item_type, except_holder)


## 返回当前库存中全部物品占用的体积。
func get_used_volume() -> int:
	return MaterialTypes.get_total_volume(items)


## 返回扣除已用体积和预留体积后的可分配空间。
func get_available_volume() -> int:
	return maxi(capacity - get_used_volume() - reserved_volume, 0)


## 返回未被其他持有者锁定、可供 [param holder] 取用的物品数量。
func get_available_item_count(item_type: int, holder: String = "") -> int:
	return maxi(
		get_item_count(item_type) - get_locked_quantity(item_type, holder),
		0,
	)


## 判断 [param items_to_add] 是否为正体积且不超过当前可用容量。[br]
## 本方法只预检空间，不检查物品类型是否合法，也不修改库存。
func can_add_items(items_to_add: Dictionary) -> bool:
	var add_volume := MaterialTypes.get_total_volume(items_to_add)
	return add_volume > 0 and add_volume <= get_available_volume()


## 在调用方已确认容量后直接写入物资。[br]
## 会忽略非正数量；成功写入返回 [code]true[/code]，空间不足返回 [code]false[/code]。
func add_items_unchecked(items_to_add: Dictionary) -> bool:
	if not can_add_items(items_to_add):
		return false
	for item_type in items_to_add:
		var quantity := maxi(int(items_to_add[item_type]), 0)
		if quantity <= 0:
			continue
		items[int(item_type)] = get_item_count(int(item_type)) + quantity
	return true


## 直接移除最多 [param quantity] 个指定物资，并返回实际移除数量。
func remove_items_unchecked(item_type: int, quantity: int) -> int:
	var removed := mini(maxi(quantity, 0), get_item_count(item_type))
	items[item_type] = get_item_count(item_type) - removed
	return removed


## 清空所有物资并返回清空前的数量快照。
func clear_items() -> Dictionary:
	var snapshot := items.duplicate()
	for item_type in items:
		items[item_type] = 0
	return snapshot
