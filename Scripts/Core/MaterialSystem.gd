## 场景内唯一的物资账本。[br]
## 所有库存注册、物品锁定、容量预留、周期结算和所有者消失清算都必须经过这里。[br]
## 账本用稳定标识保存锁和预留，使参与者被删除后仍能追踪并回收资源。
extends Node

## 某个库存的物品数量、锁定量或预留量发生变化时发出。
signal inventory_changed(inventory: Inventory)

## 所有者库存清算完成时发出，报告来源、成功转移体积和最终销毁体积。
signal cleanup_completed(source_name: String, moved_volume: int, destroyed_volume: int)

# 已登记库存编号到库存实例的映射。
var _inventories: Dictionary = {}

# 进行中的物品锁记录，键为锁标识。
var _locks: Dictionary = {}

# 进行中的容量预留记录，键为预留标识。
var _reservations: Dictionary = {}

# 下一个可分配的库存编号。
var _next_inventory_id: int = 1

# 下一个可分配的锁标识序号。
var _next_lock_id: int = 1

# 下一个可分配的预留标识序号。
var _next_reservation_id: int = 1

# 场景是否正在关闭；关闭期间不再尝试把物资转移到其他库存。
var _scene_shutdown: bool = false


## 开始新场景的物资账本生命周期，结束旧场景状态并清空全部记录。
func start_scene() -> void:
	_scene_shutdown = false
	reset()


## 标记场景进入关闭阶段，阻止清理流程继续向其他库存分配物资。
func begin_scene_shutdown() -> void:
	_scene_shutdown = true


## 返回场景当前是否处于关闭阶段。
func is_scene_shutdown() -> bool:
	return _scene_shutdown


## 清空所有库存登记、锁、预留和编号计数器。[br]
## 已登记库存会被标记为未登记，并清除其预留体积。
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


## 将一个库存登记到当前场景账本。[br]
## [param inventory] 为空时返回 [code]false[/code]；重复登记同一编号视为成功。[br]
## [param owner] 非空时会覆盖库存所有者，成功登记后发出 [signal inventory_changed]。
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


## 注销库存并使其关联的锁和预留立即失效。
func unregister_inventory(inventory: Inventory) -> void:
	if inventory == null:
		return
	inventory.is_registered = false
	_inventories.erase(inventory.inventory_id)
	_invalidate_inventory_records(inventory.inventory_id)


## 返回库存是否仍属于当前账本且标记为已登记。
func is_inventory_registered(inventory: Inventory) -> bool:
	return (
		inventory != null
		and inventory.is_registered
		and _inventories.get(inventory.inventory_id) == inventory
	)


## 返回当前账本中全部有效库存的副本数组。
func get_all_inventories() -> Array[Inventory]:
	var result: Array[Inventory] = []
	for inventory in _inventories.values():
		if inventory is Inventory and is_inventory_registered(inventory):
			result.append(inventory)
	return result


## 返回所有属于有效仓库建筑的外部库存。
func get_warehouses() -> Array[Inventory]:
	var result: Array[Inventory] = []
	for inventory in get_all_inventories():
		if is_instance_valid(inventory.owner) and inventory.owner.is_warehouse:
			result.append(inventory)
	return result


## 按距离 [param source_origin] 的远近返回可选外部仓库。[br]
## 排序先比较切比雪夫距离，再以坐标稳定打破平局；[param excluded] 不会出现在结果中。
func get_external_inventories(source_origin: Vector2i, excluded: Inventory = null) -> Array[Inventory]:
	var candidates: Array[Inventory] = []
	for inventory in get_warehouses():
		if inventory == excluded:
			continue
		candidates.append(inventory)
	# 稳定排序让相同输入在模拟和验收中得到确定的目标仓库顺序。
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


## 汇总指定库存中某类物品被其他持有者锁定的数量。[br]
## [param except_holder] 对应的锁不计入；无效、已关闭或已取走的锁也会跳过。
func get_inventory_locked_quantity(
	inventory: Inventory,
	item_type: int,
	except_holder: String = "",
) -> int:
	if inventory == null:
		return 0
	var total := 0
	for lock in _locks.values():
		# 只有仍然有效、尚未关闭且尚未取走的锁才继续占用物品数量。
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


## 在指定库存中锁定可用物品并返回锁标识。[br]
## 数量非正、库存无效或可用数量不足时返回空字符串；成功后立即发出库存变化信号。
func lock_items(
	inventory: Inventory,
	item_type: int,
	quantity: int,
	holder: String,
	source_origin: Vector2i,
) -> String:
	if not is_inventory_registered(inventory) or quantity <= 0:
		return ""
	# 锁定量必须从当前可用数中扣除，避免同一物品被多个周期重复承诺。
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


## 从库存实际取出先前锁定的物品。[br]
## 同一锁重复调用会幂等返回 [code]true[/code]；库存失效或数量不足时标记锁无效并返回 [code]false[/code]。
func take_locked(lock_id: String) -> bool:
	var lock: Dictionary = _locks.get(lock_id, {})
	if lock.is_empty() or not bool(lock["valid"]) or bool(lock["closed"]):
		return false
	if bool(lock["taken"]):
		return true
	var inventory: Inventory = lock["inventory"]
	# 库存注销或数量被外部改动后，旧锁必须失效，不能继续取走不存在的物资。
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


## 以“锁定、取出、消耗”三步直接取走库存物品。[br]
## 任一步失败都会释放临时锁，避免留下悬空锁定记录。
func withdraw_items(
	inventory: Inventory,
	item_type: int,
	quantity: int,
	holder: String,
) -> bool:
	if quantity <= 0:
		return quantity == 0
	var origin := inventory.owner.origin_cell if is_instance_valid(inventory.owner) else Vector2i.ZERO
	# 直接取用也走同一套锁协议，失败路径负责回滚临时锁。
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


## 把已经取出的锁标记为已消耗并关闭。[br]
## 锁无效、已关闭或尚未取出物品时返回 [code]false[/code]。
func consume_locked(lock_id: String) -> bool:
	var lock: Dictionary = _locks.get(lock_id, {})
	if lock.is_empty() or not bool(lock["valid"]) or bool(lock["closed"]):
		return false
	if not bool(lock["taken"]):
		return false
	lock["consumed"] = true
	lock["closed"] = true
	return true


## 关闭一个锁；若物品已经取出，则尝试退回原库存，失败时按来源距离转移。[br]
## 关闭操作幂等，重复调用不会再次修改库存。
func release_lock(lock_id: String) -> void:
	var lock: Dictionary = _locks.get(lock_id, {})
	if lock.is_empty() or bool(lock["closed"]):
		return
	lock["closed"] = true
	var source: Inventory = lock["inventory"]
	if bool(lock["taken"]):
		# 已取出的物资优先退回原库存；原库存不可用时再按距离转移。
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


## 依次释放一组锁，忽略不存在的标识。
func release_locks(lock_ids: Array[String]) -> void:
	for lock_id in lock_ids:
		release_lock(lock_id)


## 返回锁记录的副本；不存在时返回空字典。
func get_lock(lock_id: String) -> Dictionary:
	var lock: Dictionary = _locks.get(lock_id, {})
	return lock.duplicate() if not lock.is_empty() else {}


## 返回锁是否存在、仍有效且尚未关闭。
func is_lock_valid(lock_id: String) -> bool:
	var lock: Dictionary = _locks.get(lock_id, {})
	return not lock.is_empty() and bool(lock["valid"]) and not bool(lock["closed"])


## 按需求和来源顺序为 [param demand] 建立物品锁。[br]
## 优先使用 [param primary]，再使用 [param externals]；任何物品无法足额锁定时回滚本次全部锁并返回空数组。
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
		# 任一物品无法足额锁定都回滚整次请求，保证需求要么全满足要么全不满足。
		if remaining > 0:
			release_locks(lock_ids)
			return []
	return lock_ids


## 为指定体积的产出预留库存空间并返回预留标识。[br]
## 空间按 [param primary]、[param externals] 的顺序分配；无法足额预留时回滚并返回空数组。
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
	# 产出空间同样要求一次性足额预留，避免结算阶段才发现无法写入。
	if remaining > 0:
		release_reservations(reservation_ids)
		return []
	return reservation_ids


## 关闭一个产出预留并归还对应库存的预留体积。
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


## 依次释放一组预留，忽略不存在或已关闭的标识。
func release_reservations(reservation_ids: Array[String]) -> void:
	for reservation_id in reservation_ids:
		release_reservation(reservation_id)


## 返回预留是否仍有效、未关闭且对应库存仍已登记。
func is_reservation_valid(reservation_id: String) -> bool:
	var reservation: Dictionary = _reservations.get(reservation_id, {})
	if reservation.is_empty() or bool(reservation["closed"]):
		return false
	if not bool(reservation["valid"]):
		return false
	return is_inventory_registered(reservation["inventory"])


## 汇总一组预留中仍然有效的体积。
func get_valid_reserved_volume(reservation_ids: Array[String]) -> int:
	var volume := 0
	for reservation_id in reservation_ids:
		if is_reservation_valid(reservation_id):
			volume += int(_reservations[reservation_id]["volume"])
	return volume


## 清理 [param cycle] 已失效的产出预留，并尝试补足缺失空间。[br]
## 成功返回 [code]true[/code]；无法补足时周期保留已有效预留并返回 [code]false[/code]。
func replace_invalid_reservations(
	cycle: WorkCycle,
	externals: Array[Inventory],
) -> bool:
	var valid_reservations: Array[String] = []
	var valid_volume := 0
	# 先剔除已关闭或库存已消失的预留，再只补足剩余空间。
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


## 原子结算一个已锁定工作周期：验证需求、补齐产出空间并写入产出。[br]
## 成功时消耗需求锁、释放产出预留并返回 [code]true[/code]；任一预检失败则不改动物资。
func settle_cycle(cycle: WorkCycle) -> bool:
	if cycle == null:
		return false
	for lock_id in cycle.demand_locks:
		var lock := get_lock(lock_id)
		if lock.is_empty() or not bool(lock["valid"]) or not bool(lock["taken"]):
			return false

	# 先检查所有需求锁，避免部分消耗后才发现周期无法结算。
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

	# 合并预留与临时空间后先做完整试分配，确保产出能一次性落库。
	var destinations: Array[Dictionary] = reserved_destinations.duplicate()
	destinations.append_array(extra_destinations)
	if not _can_allocate_items(cycle.work_type.output, destinations):
		return false

	# 通过最终预检后才真正消耗需求并释放预留。
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


## 取消工作周期，释放全部需求锁和产出预留并标记为已取消。
func cancel_cycle(cycle: WorkCycle) -> void:
	if cycle == null:
		return
	release_locks(cycle.demand_locks)
	release_reservations(cycle.output_reservations)
	cycle.demand_locks.clear()
	cycle.output_reservations.clear()
	cycle.status = WorkCycle.Status.CANCELLED


## 清空并注销某个所有者库存，再把其中物资转移到其他仓库。[br]
## 场景关闭期间只清空数据，不尝试跨场景转移；完成后报告转移与销毁体积。
func cleanup_owner_inventory(
	owner: Building,
	source_origin: Vector2i,
	source_name: String = "",
) -> void:
	if owner == null or owner.inventory == null:
		return
	var inventory := owner.inventory
	if not is_inventory_registered(inventory):
		# 未登记库存没有账本锁记录，只需丢弃本地残留内容。
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


## 尝试把无主物资按来源位置转移到附近外部仓库，并返回成功转移的总体积。
func route_orphan_items(
	items: Dictionary,
	source_origin: Vector2i,
	source_inventory_id: int = -1,
) -> int:
	if _scene_shutdown:
		return 0
	return _route_items(items, source_origin, source_inventory_id)


## 返回当前库存、开口锁和开口预留的调试快照。
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


## 返回当前有效且未关闭的锁数量。
func get_open_lock_count() -> int:
	var count := 0
	for lock in _locks.values():
		if bool(lock["valid"]) and not bool(lock["closed"]):
			count += 1
	return count


## 返回当前有效且未关闭的预留数量。
func get_open_reservation_count() -> int:
	var count := 0
	for reservation in _reservations.values():
		if bool(reservation["valid"]) and not bool(reservation["closed"]):
			count += 1
	return count


## 返回指定持有者当前有效且未关闭的锁数量。
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


## 返回指定持有者当前有效且未关闭的预留数量。
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


## 校验库存数量、容量和预留累计是否一致，并返回全部错误说明。
func validate() -> Array[String]:
	var errors: Array[String] = []
	# 第一遍检查每个库存自身的数量与容量约束。
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
	# 第二遍从有效预留重算预留体积，检出账本与库存字段不一致。
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


## 在已登记库存中创建一条产出预留记录并增加其预留体积。
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


## 使某个库存关联的全部未关闭锁和预留失效。
func _invalidate_inventory_records(inventory_id: int) -> void:
	for lock in _locks.values():
		if int(lock["inventory_id"]) == inventory_id and not bool(lock["closed"]):
			lock["valid"] = false
	for reservation in _reservations.values():
		if int(reservation["inventory_id"]) == inventory_id and not bool(reservation["closed"]):
			reservation["valid"] = false
			reservation["closed"] = true


## 把有效预留标识转换为结算用的目标库存与体积记录。
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


## 从主库存和仓库中寻找无需预留的可用产出空间。[br]
## 优先 [param primary]，其余仓库按坐标稳定排序；空间不足时返回空数组。
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
	# 试分配只有在所有目标空间都凑齐时才算成功。
	if remaining > 0:
		return []
	return result


## 在不修改库存的前提下验证物品能否完整分配到目标空间。
func _can_allocate_items(items: Dictionary, destinations: Array[Dictionary]) -> bool:
	var remaining := _positive_items(items)
	return _is_empty_items(_allocate_items_dry_run(remaining, destinations))


## 执行一次不写库存的空间分配试算，并返回未分配物品。
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


## 将物品依次写入目标库存，并返回未能分配的剩余物品。
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
		# 按物资顺序逐项贪心写入，单件体积决定该目标还能容纳多少数量。
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


## 按来源距离把物品写入外部仓库，并返回成功转移的总体积。
func _route_items(
	items: Dictionary,
	source_origin: Vector2i,
	excluded_inventory_id: int,
) -> int:
	var remaining := _positive_items(items)
	var moved_volume := 0
	# 外部仓库已按来源距离排序，物资会优先进入最近且仍有空间的库存。
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


## 过滤出数量为正的物品，形成新的分配字典。
func _positive_items(items: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for item_type in MaterialTypes.get_item_types():
		var quantity := maxi(int(items.get(item_type, 0)), 0)
		if quantity > 0:
			result[item_type] = quantity
	return result


## 判断物品字典中是否不再包含正数量。
func _is_empty_items(items: Dictionary) -> bool:
	for item_type in items:
		if int(items[item_type]) > 0:
			return false
	return true


## 合并主库存与外部库存，过滤无效项并按首次出现顺序去重。
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


## 计算两个格子之间的切比雪夫距离，用于八方向移动和距离排序。
func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
