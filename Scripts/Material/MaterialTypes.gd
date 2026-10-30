## 物资类型及其体积、显示名称的统一查询入口。[br]
## 库存数量以整数保存，容量消耗统一按 [member UNIT_VOLUMES] 换算为体积单位。[br]
## 本类无运行时状态，所有查询方法均可由库存、周期和调试系统直接调用。
class_name MaterialTypes

## 当前版本支持的物资类型。[br]
## 枚举值会作为库存字典和周期需求字典的键，新增后需同步体积、名称和物品顺序。
enum ItemType {
	## 可被分拣为金属、塑料和线材的废料。
	WASTE,
	## 用于制造和建造的金属材料。
	METAL,
	## 用于制造和建造的塑料材料。
	PLASTIC,
	## 由金属与塑料加工得到的线材。
	WIRE,
}

## 每种物资单件占用的体积。[br]
## 库存容量、锁定数量校验和产出预留都使用这份映射。
const UNIT_VOLUMES: Dictionary = {
	ItemType.WASTE: 2,
	ItemType.METAL: 1,
	ItemType.PLASTIC: 1,
	ItemType.WIRE: 1,
}

## 每种物资面向玩家显示的中文名称。
const DISPLAY_NAMES: Dictionary = {
	ItemType.WASTE: "废料",
	ItemType.METAL: "金属",
	ItemType.PLASTIC: "塑料",
	ItemType.WIRE: "线",
}


## 返回 [param item_type] 单件占用的体积；未知类型返回 0。
static func get_unit_volume(item_type: int) -> int:
	return int(UNIT_VOLUMES.get(item_type, 0))


## 返回 [param item_type] 的显示名称；未知类型返回“未知物品”。
static func get_display_name(item_type: int) -> String:
	return String(DISPLAY_NAMES.get(item_type, "未知物品"))


## 汇总 [param items] 中所有非负数量对应的总体积。[br]
## 未知物品按 0 体积处理，负数数量不会抵扣其他物品的体积。[br]
## 返回 [param items] 表示的全部物资体积总和。
static func get_total_volume(items: Dictionary) -> int:
	var total := 0
	for item_type in items:
		total += maxi(int(items[item_type]), 0) * get_unit_volume(int(item_type))
	return total


## 按稳定顺序返回当前所有物资类型，供库存初始化和遍历分配使用。
static func get_item_types() -> Array[int]:
	return [
		ItemType.WASTE,
		ItemType.METAL,
		ItemType.PLASTIC,
		ItemType.WIRE,
	]
