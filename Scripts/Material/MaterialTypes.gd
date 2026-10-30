class_name MaterialTypes

## v0.0.1.4 只定义四种物品。数量为整数，容量统一按体积计算。
enum ItemType {
	WASTE,
	METAL,
	PLASTIC,
	WIRE,
}

const UNIT_VOLUMES: Dictionary = {
	ItemType.WASTE: 2,
	ItemType.METAL: 1,
	ItemType.PLASTIC: 1,
	ItemType.WIRE: 1,
}

const DISPLAY_NAMES: Dictionary = {
	ItemType.WASTE: "废料",
	ItemType.METAL: "金属",
	ItemType.PLASTIC: "塑料",
	ItemType.WIRE: "线",
}


static func get_unit_volume(item_type: int) -> int:
	return int(UNIT_VOLUMES.get(item_type, 0))


static func get_display_name(item_type: int) -> String:
	return String(DISPLAY_NAMES.get(item_type, "未知物品"))


static func get_total_volume(items: Dictionary) -> int:
	var total := 0
	for item_type in items:
		total += maxi(int(items[item_type]), 0) * get_unit_volume(int(item_type))
	return total


static func get_item_types() -> Array[int]:
	return [
		ItemType.WASTE,
		ItemType.METAL,
		ItemType.PLASTIC,
		ItemType.WIRE,
	]
