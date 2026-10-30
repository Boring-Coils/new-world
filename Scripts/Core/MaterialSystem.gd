extends Node

## 场景内唯一的物资账本。所有库存注册、物品锁定、容量预留、
## 周期结算和所有者消失清算都必须经过这里。

signal inventory_changed(inventory: Inventory)
signal cleanup_completed(source_name: String, moved_volume: int, destroyed_volume: int)

var _inventories: Dictionary = {}
var _locks: Dictionary = {}
var _reservations: Dictionary = {}
var _next_inventory_id: int = 1
var _next_lock_id: int = 1
var _next_reservation_id: int = 1
var _scene_shutdown: bool = false


func start_scene() -> void:
	_scene_shutdown = false
	reset()


func begin_scene_shutdown() -> void:
	_scene_shutdown = true


func is_scene_shutdown() -> bool:
	return _scene_shutdown


func reset() -> void:
	for inventory in _inventories.values():
		if inventory is Inventory:
			inventory.is_registered = false
			inventory.reserved_volume = 0
	_inventories.clear()
	_locks.clear()
	_reservations.clear()
	_next_inventory_id = 1
	_next_lock_id = 1
	_next_reservation_id = 1


func register_inventory(inventory: Inventory, owner: Building = null) -> bool:
	if inventory == null:
		return false
	if inventory.inventory_id > 0 and _inventories.has(inventory.inventory_id):
		return true
	if owner != null:
		inventory.owner = owner
	inventory.inventory_id = _next_inventory_id
	_next_inventory_id += 1
	inventory.is_registered = true
	inventory.reserved_volume = 0
	_inventories[inventory.inventory_id] = inventory
	inventory_changed.emit(inventory)
	return true


func unregister_inventory(inventory: Inventory) -> void:
	if inventory == null:
		return
	inventory.is_registered = false
	_inventories.erase(inventory.inventory_id)
	_invalidate_inventory_records(inventory.inventory_id)


func is_inventory_registered(inventory: Inventory) -> bool:
	return (
		inventory != null
		and inventory.is_registered
		and _inventories.get(inventory.inventory_id) == inventory
	)


func get_all_inventories() -> Array[Inventory]:
	var result: Array[Inventory] = []
	for inventory in _inventories.values():
		if inventory is Inventory and is_inventory_registered(inventory):
			result.append(inventory)
	return result


func get_warehouses() -> Array[Inventory]:
	var result: Array[Inventory] = []
	for inventory in get_all_inventories():
		if is_instance_valid(inventory.owner) and inventory.owner.is_warehouse:
			result.append(inventory)
	return result


func get_external_inventories(source_origin: Vector2i, excluded: Inventory = null) -> Array[Inventory]:
	var candidates: Array[Inventory] = []
	for inventory in get_warehouses():
		if inventory == excluded:
			continue
		candidates.append(inventory)
	candidates.sort_custom(
		func(a: Inventory, b: Inventory) -> bool:
			var da := _chebyshev(source_origin, a.owner.origin_cell)
			var db := _chebyshev(source_origin, b.owner.origin_cell)
			if da != db:
				return da < db
			if a.owner.origin_cell.x != b.owner.origin_cell.x:
				return a.owner.origin_cell.x < b.owner.origin_cell.x
			return a.owner.origin_cell.y < b.owner.origin_cell.y
	)
	return candidates


func get_inventory_locked_quantity(
	inventory: Inventory,
	item_type: int,
	except_holder: String = "",
) -> int:
	if inventory == null:
		return 0
	var total := 0
	for lock in _locks.values():
		if not bool(lock["valid"]) or bool(lock["closed"]):
			continue
		if bool(lock["taken"]):
			continue
		if lock["inventory_id"] != inventory.inventory_id:
			continue
		if String(lock["holder"]) == except_holder:
			continue
		if int(lock["item_type"]) == item_type:
			total += int(lock["quantity"])
	return total


func lock_items(
	inventory: Inventory,
	item_type: int,
	quantity: int,
	holder: String,
	source_origin: Vector2i,
) -> String:
	if not is_inventory_registered(inventory) or quantity <= 0:
		return ""
	var available := inventory.get_item_count(item_type) - get_inventory_locked_quantity(
		inventory,
		item_type,
	)
	if available < quantity:
		return ""

	var lock_id := "lock:%d" % _next_lock_id
	_next_lock_id += 1
	_locks[lock_id] = {
		"id": lock_id,
		"holder": holder,
		"inventory_id": inventory.inventory_id,
		"inventory": inventory,
		"source_origin": source_origin,
		"item_type": item_type,
		"quantity": quantity,
		"taken": false,
		"consumed": false,
		"valid": true,
		"closed": false,
	}
	inventory_changed.emit(inventory)
	return lock_id


func take_locked(lock_id: String) -> bool:
	var lock: Dictionary = _locks.get(lock_id, {})
	if lock.is_empty() or not bool(lock["valid"]) or bool(lock["closed"]):
		return false
	if bool(lock["taken"]):
		return true
	var inventory: Inventory = lock["inventory"]
	if not is_inventory_registered(inventory):
		lock["valid"] = false
		return false
	var item_type := int(lock["item_type"])
	var quantity := int(lock["quantity"])
	if inventory.get_item_count(item_type) < quantity:
		lock["valid"] = false
		return false
	inventory.remove_items_unchecked(item_type, quantity)
	lock["taken"] = true
	inventory_changed.emit(inventory)
	return true


func withdraw_items(
	inventory: Inventory,
	item_type: int,
	quantity: int,
	holder: String,
) -> bool:
	if quantity <= 0:
		return quantity == 0
	var origin := inventory.owner.origin_cell if is_instance_valid(inventory.owner) else Vector2i.ZERO
	var lock_id := lock_items(inventory, item_type, quantity, holder, origin)
	if lock_id == "":
		return false
	if not take_locked(lock_id):
		release_lock(lock_id)
		return false
	if not consume_locked(lock_id):
		release_lock(lock_id)
		return false
	return true


func consume_locked(lock_id: String) -> bool:
	var lock: Dictionary = _locks.get(lock_id, {})
	if lock.is_empty() or not bool(lock["valid"]) or bool(lock["closed"]):
		return false
	if not bool(lock["taken"]):
		return false
	lock["consumed"] = true
	lock["closed"] = true
	return true


func release_lock(lock_id: String) -> void:
	var lock: Dictionary = _locks.get(lock_id, {})
	if lock.is_empty() or bool(lock["closed"]):
		return
	lock["closed"] = true
	var source: Inventory = lock["inventory"]
	if bool(lock["taken"]):
		var item_type := int(lock["item_type"])
		var quantity := int(lock["quantity"])
		var returned := false
		if is_inventory_registered(source):
			returned = source.add_items_unchecked({item_type: quantity})
		if returned:
			inventory_changed.emit(source)
		else:
			_route_items(
				{item_type: quantity},
				lock["source_origin"] as Vector2i,
				source.inventory_id if source != null else -1,
			)
	elif is_inventory_registered(source):
		inventory_changed.emit(source)
	return


func release_locks(lock_ids: Array[String]) -> void:
	for lock_id in lock_ids:
		release_lock(lock_id)


func get_lock(lock_id: String) -> Dictionary:
	var lock: Dictionary = _locks.get(lock_id, {})
	return lock.duplicate() if not lock.is_empty() else {}


func is_lock_valid(lock_id: String) -> bool:
	var lock: Dictionary = _locks.get(lock_id, {})
	return not lock.is_empty() and bool(lock["valid"]) and not bool(lock["closed"])


func lock_demand(
	demand: Dictionary,
	primary: Inventory,
	externals: Array[Inventory],
	holder: String,
	source_origin: Vector2i,
) -> Array[String]:
	var lock_ids: Array[String] = []
	var sources := _unique_inventories(primary, externals)
	for item_type in demand:
		var remaining := maxi(int(demand[item_type]), 0)
		for inventory in sources:
			if remaining <= 0:
				break
			var available := inventory.get_available_item_count(int(item_type))
			if available <= 0:
				continue
			var amount := mini(remaining, available)
			var lock_id := lock_items(
				inventory,
				int(item_type),
				amount,
				holder,
				source_origin,
			)
			if lock_id == "":
				continue
			lock_ids.append(lock_id)
			remaining -= amount
		if remaining > 0:
			release_locks(lock_ids)
			return []
	return lock_ids


func reserve_output(
	volume: int,
	primary: Inventory,
	externals: Array[Inventory],
	holder: String,
) -> Array[String]:
	var reservation_ids: Array[String] = []
	if volume <= 0:
		return reservation_ids
	var remaining := volume
	for inventory in _unique_inventories(primary, externals):
		if remaining <= 0:
			break
		var amount := mini(remaining, inventory.get_available_volume())
		if amount <= 0:
			continue
		var reservation_id := _reserve_inventory_space(inventory, amount, holder)
		if reservation_id == "":
			continue
		reservation_ids.append(reservation_id)
		remaining -= amount
	if remaining > 0:
		release_reservations(reservation_ids)
		return []
	return reservation_ids


func release_reservation(reservation_id: String) -> void:
	var reservation: Dictionary = _reservations.get(reservation_id, {})
	if reservation.is_empty() or bool(reservation["closed"]):
		return
	reservation["closed"] = true
	var inventory: Inventory = reservation["inventory"]
	if is_inventory_registered(inventory):
		inventory.reserved_volume = maxi(
			inventory.reserved_volume - int(reservation["volume"]),
			0,
		)
		inventory_changed.emit(inventory)


func release_reservations(reservation_ids: Array[String]) -> void:
	for reservation_id in reservation_ids:
		release_reservation(reservation_id)


func is_reservation_valid(reservation_id: String) -> bool:
	var reservation: Dictionary = _reservations.get(reservation_id, {})
	if reservation.is_empty() or bool(reservation["closed"]):
		return false
	if not bool(reservation["valid"]):
		return false
	return is_inventory_registered(reservation["inventory"])


func get_valid_reserved_volume(reservation_ids: Array[String]) -> int:
	var volume := 0
	for reservation_id in reservation_ids:
		if is_reservation_valid(reservation_id):
			volume += int(_reservations[reservation_id]["volume"])
	return volume


func replace_invalid_reservations(
	cycle: WorkCycle,
	externals: Array[Inventory],
) -> bool:
	var valid_reservations: Array[String] = []
	var valid_volume := 0
	for reservation_id in cycle.output_reservations:
		if is_reservation_valid(reservation_id):
			valid_reservations.append(reservation_id)
			valid_volume += int(_reservations[reservation_id]["volume"])
	cycle.output_reservations = valid_reservations

	var missing := cycle.expected_output_volume - valid_volume
	if missing <= 0:
		return true
	var additional := reserve_output(
		missing,
		cycle.employer.inventory if is_instance_valid(cycle.employer) else null,
		externals,
		cycle.get_holder_id(),
	)
	if additional.is_empty():
		return false
	cycle.output_reservations.append_array(additional)
	return true


func settle_cycle(cycle: WorkCycle) -> bool:
	if cycle == null:
		return false
	for lock_id in cycle.demand_locks:
		var lock := get_lock(lock_id)
		if lock.is_empty() or not bool(lock["valid"]) or not bool(lock["taken"]):
			return false

	var output_volume := cycle.work_type.get_output_volume()
	var reserved_destinations := _get_reservation_destinations(cycle.output_reservations)
	var reserved_volume := 0
	for destination in reserved_destinations:
		reserved_volume += int(destination["volume"])

	var extra_needed := maxi(output_volume - reserved_volume, 0)
	var extra_destinations: Array[Dictionary] = []
	if extra_needed > 0:
		var primary := cycle.employer.inventory if is_instance_valid(cycle.employer) else null
		extra_destinations = _find_unreserved_space(extra_needed, primary)
		if extra_destinations.is_empty():
			return false

	var destinations: Array[Dictionary] = reserved_destinations.duplicate()
	destinations.append_array(extra_destinations)
	if not _can_allocate_items(cycle.work_type.output, destinations):
		return false

	for lock_id in cycle.demand_locks:
		if not consume_locked(lock_id):
			return false
	for reservation_id in cycle.output_reservations:
		release_reservation(reservation_id)

	var remaining_output := _allocate_items(cycle.work_type.output, destinations)
	if not _is_empty_items(remaining_output):
		push_error("MaterialSystem: 已预检的产出仍无法完整写入 %s" % remaining_output)
		return false
	cycle.output_reservations.clear()
	return true


func cancel_cycle(cycle: WorkCycle) -> void:
	if cycle == null:
		return
	release_locks(cycle.demand_locks)
	release_reservations(cycle.output_reservations)
	cycle.demand_locks.clear()
	cycle.output_reservations.clear()
	cycle.status = WorkCycle.Status.CANCELLED


func cleanup_owner_inventory(
	owner: Building,
	source_origin: Vector2i,
	source_name: String = "",
) -> void:
	if owner == null or owner.inventory == null:
		return
	var inventory := owner.inventory
	if not is_inventory_registered(inventory):
		inventory.items.clear()
		return
	var items := inventory.clear_items()
	inventory.reserved_volume = 0
	unregister_inventory(inventory)
	if _scene_shutdown:
		return
	var moved_volume := _route_items(items, source_origin, inventory.inventory_id)
	var initial_volume := MaterialTypes.get_total_volume(items)
	cleanup_completed.emit(
		source_name if source_name != "" else owner.display_name,
		moved_volume,
		maxi(initial_volume - moved_volume, 0),
	)


func route_orphan_items(
	items: Dictionary,
	source_origin: Vector2i,
	source_inventory_id: int = -1,
) -> int:
	if _scene_shutdown:
		return 0
	return _route_items(items, source_origin, source_inventory_id)


func get_snapshot() -> Dictionary:
	var inventories: Array[Dictionary] = []
	for inventory in get_all_inventories():
		inventories.append({
			"id": inventory.inventory_id,
			"owner": inventory.owner.name if is_instance_valid(inventory.owner) else "",
			"capacity": inventory.capacity,
			"used": inventory.get_used_volume(),
			"reserved": inventory.reserved_volume,
			"available": inventory.get_available_volume(),
			"items": inventory.items.duplicate(),
		})
	return {
		"inventories": inventories,
		"open_locks": get_open_lock_count(),
		"open_reservations": get_open_reservation_count(),
	}


func get_open_lock_count() -> int:
	var count := 0
	for lock in _locks.values():
		if bool(lock["valid"]) and not bool(lock["closed"]):
			count += 1
	return count


func get_open_reservation_count() -> int:
	var count := 0
	for reservation in _reservations.values():
		if bool(reservation["valid"]) and not bool(reservation["closed"]):
			count += 1
	return count


func get_holder_open_lock_count(holder: String) -> int:
	var count := 0
	for lock in _locks.values():
		if (
			String(lock["holder"]) == holder
			and bool(lock["valid"])
			and not bool(lock["closed"])
		):
			count += 1
	return count


func get_holder_open_reservation_count(holder: String) -> int:
	var count := 0
	for reservation in _reservations.values():
		if (
			String(reservation["holder"]) == holder
			and bool(reservation["valid"])
			and not bool(reservation["closed"])
		):
			count += 1
	return count


func validate() -> Array[String]:
	var errors: Array[String] = []
	for inventory in get_all_inventories():
		for item_type in inventory.items:
			if int(inventory.items[item_type]) < 0:
				errors.append("库存 %d 的 %s 为负数" % [
					inventory.inventory_id,
					MaterialTypes.get_display_name(int(item_type)),
				])
		if inventory.get_used_volume() + inventory.reserved_volume > inventory.capacity:
			errors.append("库存 %d 超过容量" % inventory.inventory_id)

	var expected_reserved: Dictionary = {}
	for reservation in _reservations.values():
		if not bool(reservation["valid"]) or bool(reservation["closed"]):
			continue
		var inventory_id := int(reservation["inventory_id"])
		expected_reserved[inventory_id] = (
			int(expected_reserved.get(inventory_id, 0))
			+ int(reservation["volume"])
		)
	for inventory in get_all_inventories():
		if int(expected_reserved.get(inventory.inventory_id, 0)) != inventory.reserved_volume:
			errors.append("库存 %d 的预留体积累计不一致" % inventory.inventory_id)
	return errors


func _reserve_inventory_space(inventory: Inventory, volume: int, holder: String) -> String:
	if not is_inventory_registered(inventory) or volume <= 0:
		return ""
	if inventory.get_available_volume() < volume:
		return ""
	var reservation_id := "reservation:%d" % _next_reservation_id
	_next_reservation_id += 1
	inventory.reserved_volume += volume
	_reservations[reservation_id] = {
		"id": reservation_id,
		"holder": holder,
		"inventory_id": inventory.inventory_id,
		"inventory": inventory,
		"volume": volume,
		"valid": true,
		"closed": false,
	}
	inventory_changed.emit(inventory)
	return reservation_id


func _invalidate_inventory_records(inventory_id: int) -> void:
	for lock in _locks.values():
		if int(lock["inventory_id"]) == inventory_id and not bool(lock["closed"]):
			lock["valid"] = false
	for reservation in _reservations.values():
		if int(reservation["inventory_id"]) == inventory_id and not bool(reservation["closed"]):
			reservation["valid"] = false
			reservation["closed"] = true


func _get_reservation_destinations(reservation_ids: Array[String]) -> Array[Dictionary]:
	var destinations: Array[Dictionary] = []
	for reservation_id in reservation_ids:
		if not is_reservation_valid(reservation_id):
			continue
		var reservation: Dictionary = _reservations[reservation_id]
		destinations.append({
			"inventory": reservation["inventory"],
			"volume": int(reservation["volume"]),
			"reservation_id": reservation_id,
		})
	return destinations


func _find_unreserved_space(
	required_volume: int,
	primary: Inventory = null,
) -> Array[Dictionary]:
	var remaining := required_volume
	var result: Array[Dictionary] = []
	var inventories: Array[Inventory] = []
	if is_inventory_registered(primary):
		inventories.append(primary)
	for warehouse in get_warehouses():
		if warehouse != primary:
			inventories.append(warehouse)
	inventories.sort_custom(
		func(a: Inventory, b: Inventory) -> bool:
			var a_origin := a.owner.origin_cell if is_instance_valid(a.owner) else Vector2i.ZERO
			var b_origin := b.owner.origin_cell if is_instance_valid(b.owner) else Vector2i.ZERO
			if a_origin.x != b_origin.x:
				return a_origin.x < b_origin.x
			return a_origin.y < b_origin.y
	)
	for inventory in inventories:
		if remaining <= 0:
			break
		var amount := mini(remaining, inventory.get_available_volume())
		if amount <= 0:
			continue
		result.append({
			"inventory": inventory,
			"volume": amount,
			"reservation_id": "",
		})
		remaining -= amount
	if remaining > 0:
		return []
	return result


func _can_allocate_items(items: Dictionary, destinations: Array[Dictionary]) -> bool:
	var remaining := _positive_items(items)
	return _is_empty_items(_allocate_items_dry_run(remaining, destinations))


func _allocate_items_dry_run(
	items: Dictionary,
	destinations: Array[Dictionary],
) -> Dictionary:
	var remaining := items.duplicate()
	for destination in destinations:
		var allowance := int(destination["volume"])
		for item_type in MaterialTypes.get_item_types():
			var quantity := int(remaining.get(item_type, 0))
			if quantity <= 0 or allowance <= 0:
				continue
			var unit_volume := MaterialTypes.get_unit_volume(item_type)
			var amount := mini(quantity, allowance / maxi(unit_volume, 1))
			if amount <= 0:
				continue
			remaining[item_type] = quantity - amount
			allowance -= amount * unit_volume
	return remaining


func _allocate_items(
	items: Dictionary,
	destinations: Array[Dictionary],
) -> Dictionary:
	var remaining := items.duplicate()
	for destination in destinations:
		var inventory: Inventory = destination["inventory"]
		var allowance := int(destination["volume"])
		if not is_inventory_registered(inventory):
			continue
		for item_type in MaterialTypes.get_item_types():
			var quantity := int(remaining.get(item_type, 0))
			if quantity <= 0 or allowance <= 0:
				continue
			var unit_volume := MaterialTypes.get_unit_volume(item_type)
			var amount := mini(quantity, allowance / maxi(unit_volume, 1))
			if amount <= 0:
				continue
			inventory.items[item_type] = inventory.get_item_count(item_type) + amount
			remaining[item_type] = quantity - amount
			allowance -= amount * unit_volume
			inventory_changed.emit(inventory)
	return remaining


func _route_items(
	items: Dictionary,
	source_origin: Vector2i,
	excluded_inventory_id: int,
) -> int:
	var remaining := _positive_items(items)
	var moved_volume := 0
	for inventory in get_external_inventories(source_origin):
		if inventory.inventory_id == excluded_inventory_id:
			continue
		for item_type in MaterialTypes.get_item_types():
			var quantity := int(remaining.get(item_type, 0))
			if quantity <= 0:
				continue
			var unit_volume := MaterialTypes.get_unit_volume(item_type)
			var fit := mini(quantity, inventory.get_available_volume() / maxi(unit_volume, 1))
			if fit <= 0:
				continue
			inventory.items[item_type] = inventory.get_item_count(item_type) + fit
			remaining[item_type] = quantity - fit
			moved_volume += fit * unit_volume
			inventory_changed.emit(inventory)
		if _is_empty_items(remaining):
			break
	return moved_volume


func _positive_items(items: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for item_type in MaterialTypes.get_item_types():
		var quantity := maxi(int(items.get(item_type, 0)), 0)
		if quantity > 0:
			result[item_type] = quantity
	return result


func _is_empty_items(items: Dictionary) -> bool:
	for item_type in items:
		if int(items[item_type]) > 0:
			return false
	return true


func _unique_inventories(
	primary: Inventory,
	externals: Array[Inventory],
) -> Array[Inventory]:
	var result: Array[Inventory] = []
	if is_inventory_registered(primary):
		result.append(primary)
	for inventory in externals:
		if is_inventory_registered(inventory) and not result.has(inventory):
			result.append(inventory)
	return result


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
