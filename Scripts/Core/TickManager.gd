extends Node

## 游戏时钟与每刻更新调度。[br]
## 时间换算：[br]
## - 现实 1 秒 = [constant TICKS_PER_SECOND] 刻[br]
## - 游戏内 1 天 = [constant TICKS_PER_DAY] 刻 = 6 小时[br]
## - 所以游戏内 1 刻 = 21600 ÷ 1800 = [constant GAME_SECONDS_PER_TICK] 游戏秒（12 秒）[br]
## [b]所有和「人」有关的速度、消耗都要按游戏内时间算，不是现实时间。[/b][br]
## 例如成年人走路 1.4 米/秒、1 格 = 1 米，那么每刻能走 1.4 × 12 ≈ 17 格（17 米），[br]
## 一天走三十公里。一天分多少刻直接决定「一刻走多远」，改这里要连补给提前量一起看。[br]
## 每个刻按固定顺序更新一次：先建筑、再人物，最后广播 [signal tick_advanced]。[br]
## 所有需要「每刻更新」的东西都通过 [method register_building] / [method register_human] 登记，[br]
## 不要自己再连 _process，否则更新顺序不可控。

## 一天有多少刻
const TICKS_PER_DAY: int = 1800

## 现实一秒钟有多少刻（只影响游戏跑多快，不影响游戏内的时间换算）[br]
## 6 刻/秒 → 一天 1800 刻 = 现实 300 秒（5 分钟）
const TICKS_PER_SECOND: float = 6.0

## 一刻等于多少现实秒
const SECONDS_PER_TICK: float = 1.0 / TICKS_PER_SECOND

## 一个游戏日有多少【游戏内】秒（现在是 6 小时）
const GAME_SECONDS_PER_DAY: float = 6.0 * 3600.0

## 一刻等于多少【游戏内】秒（一天 6 小时 ÷ 300 刻 = 72 秒）
const GAME_SECONDS_PER_TICK: float = GAME_SECONDS_PER_DAY / float(TICKS_PER_DAY)

## 每推进一刻发出一次；参数依次为：累计刻数、第几天（从 0 开始）、当天第几刻（0 ~ 299）
signal tick_advanced(total_ticks: int, day: int, tick_of_day: int)

## 有新建筑登记时发出（放下的建筑，不含预览虚影）[br]
## 详情页这类「想认识所有建筑」的东西连这个，就不用自己轮询。
signal building_registered(building: Building)

## 每天第一刻发出一次
signal day_advanced(day: int)

## 累计经过了多少刻
var total_ticks: int = 0

## 是否自动走时（关掉后只能手动 [method advance_tick]）
var auto_run: bool = true

## 走时倍速
var speed_multiplier: float = 1.0

## 已登记的建筑（每刻先更新这些）
var buildings: Array[Building] = []

## 已登记的居民（每刻后更新这些）
var humans: Array[Human] = []

## 内部的时间累加器
var _accumulator: float = 0.0


func _ready() -> void:
	# 调试用：命令行加 `-- --speed=100` 可以让时间快进，方便观察群体行为
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--speed="):
			speed_multiplier = maxf(arg.trim_prefix("--speed=").to_float(), 0.0)


func _process(delta: float) -> void:
	if not auto_run:
		return
	_accumulator += delta * speed_multiplier
	# 用 while 而不是 if：万一掉帧、一帧跨了好几刻，也要把这几个刻补齐
	while _accumulator >= SECONDS_PER_TICK:
		_accumulator -= SECONDS_PER_TICK
		advance_tick()


## 手动推进一刻。自动走时的时候由 [method _process] 调用，测试时可以自己循环调用。
func advance_tick() -> void:
	total_ticks += 1

	# 先建筑、再人物：建筑在这一刻更新自己的状态（比如出入口占用），
	# 人物随后读取到的就是最新状态
	for b in buildings:
		if is_instance_valid(b):
			b.on_tick()
	for h in humans:
		if is_instance_valid(h):
			h.on_tick()

	tick_advanced.emit(total_ticks, get_day(), get_tick_of_day())
	if get_tick_of_day() == 0:
		day_advanced.emit(get_day())


## 当前是第几天（从 0 开始）
func get_day() -> int:
	#显式忽略警告
	@warning_ignore("integer_division")
	return total_ticks / TICKS_PER_DAY


## 当前是当天的第几刻（0 ~ 299）
func get_tick_of_day() -> int:
	return total_ticks % TICKS_PER_DAY


## 登记一个建筑
func register_building(building: Building) -> void:
	if not buildings.has(building):
		buildings.append(building)
		building_registered.emit(building)


## 注销一个建筑
func unregister_building(building: Building) -> void:
	buildings.erase(building)


## 登记一个居民
func register_human(human: Human) -> void:
	if not humans.has(human):
		humans.append(human)


## 注销一个居民
func unregister_human(human: Human) -> void:
	humans.erase(human)


## 按类型找出所有还活着的建筑
func get_buildings_of_type(type: GlobalEnum.BuildingType) -> Array[Building]:
	var result: Array[Building] = []
	for b in buildings:
		if is_instance_valid(b) and b.building_type == type:
			result.append(b)
	return result
