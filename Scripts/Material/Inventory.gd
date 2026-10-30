class_name Inventory
extends RefCounted

## 单个仓库或建筑自带库存。这里只保存数量和容量事实；
## 锁定、预留及所有者生命周期统一由 MaterialSystem 管理。

var inventory_id: int = -1
var owner: Building = null
var capacity: int = 0
var items: Dictionary = {}
var reserved_volume: int = 0
var is_registered: bool = false


func _init(capacity_value: int = 0) -> void:
	capacity = maxi(capacity_value, 0)
	for item_type in MaterialTypes.get_item_types():
		items[item_type] = 0


func get_item_count(item_type: int) -> int:
	return maxi(int(items.get(item_type, 0)), 0)


func get_locked_quantity(item_type: int, except_holder: String = "") -> int:
	if not is_registered:
		return 0
	return MaterialSystem.get_inventory_locked_quantity(self, item_type, except_holder)


func get_used_volume() -> int:
	return MaterialTypes.get_total_volume(items)


func get_available_volume() -> int:
	return maxi(capacity - get_used_volume() - reserved_volume, 0)


func get_available_item_count(item_type: int, holder: String = "") -> int:
	return maxi(
		get_item_count(item_type) - get_locked_quantity(item_type, holder),
		0,
	)


func can_add_items(items_to_add: Dictionary) -> bool:
	var add_volume := MaterialTypes.get_total_volume(items_to_add)
	return add_volume > 0 and add_volume <= get_available_volume()


func add_items_unchecked(items_to_add: Dictionary) -> bool:
	if not can_add_items(items_to_add):
		return false
	for item_type in items_to_add:
		var quantity := maxi(int(items_to_add[item_type]), 0)
		if quantity <= 0:
			continue
		items[int(item_type)] = get_item_count(int(item_type)) + quantity
	return true


func remove_items_unchecked(item_type: int, quantity: int) -> int:
	var removed := mini(maxi(quantity, 0), get_item_count(item_type))
	items[item_type] = get_item_count(item_type) - removed
	return removed


func clear_items() -> Dictionary:
	var snapshot := items.duplicate()
	for item_type in items:
		items[item_type] = 0
	return snapshot
