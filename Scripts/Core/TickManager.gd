## 游戏时钟、实体注册表和每刻更新的唯一调度入口。[br]
## 自动走时按现实时间累积，但建筑、居民、消耗和 Buff 都只在实际模拟刻推进。[br]
## 每刻固定先更新建筑、再更新居民，最后广播 [signal tick_advanced] 与跨天信号。[br]
## 周期逻辑必须通过注册接口或实体自身的 [code]on_tick()[/code] 接入，不能另建 [code]_process[/code] 循环。
extends Node

## 一天有多少刻
const TICKS_PER_DAY: int = 1800

## 现实一秒钟有多少刻（只影响游戏跑多快，不影响游戏内的时间换算）[br]
## 6 刻/秒 → 一天 1800 刻 = 现实 300 秒（5 分钟）
const TICKS_PER_SECOND: float = 6.0

## 一刻等于多少现实秒
const SECONDS_PER_TICK: float = 1.0 / TICKS_PER_SECOND

## 一个游戏日有多少【游戏内】秒（现在是 6 小时）
const GAME_SECONDS_PER_DAY: float = 6.0 * 3600.0

## 一刻等于多少【游戏内】秒（一天 6 小时 ÷ 1800 刻 = 12 秒）
const GAME_SECONDS_PER_TICK: float = GAME_SECONDS_PER_DAY / float(TICKS_PER_DAY)

## 每推进一刻发出一次；参数依次为：累计刻数、第几天（从 0 开始）、当天第几刻（0 ~ 1799）
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

# 内部现实时间累加器，用于补齐跨帧的模拟刻。
var _accumulator: float = 0.0


## 在自动加载节点就绪时读取可选的 [code]--speed=[/code] 用户参数。
func _ready() -> void:
	# 调试用：命令行加 `-- --speed=100` 可以让时间快进，方便观察群体行为
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--speed="):
			speed_multiplier = maxf(arg.trim_prefix("--speed=").to_float(), 0.0)


## 积累现实时间并在达到一刻的间隔时推进模拟；关闭自动走时后直接返回。
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

	# 先建筑、再人物：居民读取到的就是建筑本刻更新后的最新状态。
	for b in buildings:
		if is_instance_valid(b):
			b.on_tick()
	for h in humans:
		if is_instance_valid(h):
			h.on_tick()

	tick_advanced.emit(total_ticks, get_day(), get_tick_of_day())
	if get_tick_of_day() == 0:
		day_advanced.emit(get_day())


## 返回当前游戏日序号，从 0 开始。
func get_day() -> int:
	# 整数除法是刻数换算游戏日的预期行为。
	@warning_ignore("integer_division")
	return total_ticks / TICKS_PER_DAY


## 返回当前游戏日内的刻序号，范围为 0 至 [constant TICKS_PER_DAY] - 1。
func get_tick_of_day() -> int:
	return total_ticks % TICKS_PER_DAY


## 登记建筑并发出一次 [signal building_registered]；重复登记不会重复加入。
func register_building(building: Building) -> void:
	if not buildings.has(building):
		buildings.append(building)
		building_registered.emit(building)


## 从每刻建筑列表移除指定建筑；未登记时安全忽略。
func unregister_building(building: Building) -> void:
	buildings.erase(building)


## 登记居民；重复登记不会重复加入。
func register_human(human: Human) -> void:
	if not humans.has(human):
		humans.append(human)


## 从每刻居民列表移除指定居民；未登记时安全忽略。
func unregister_human(human: Human) -> void:
	humans.erase(human)


## 返回指定建筑类型下仍有效且已登记的全部建筑。
func get_buildings_of_type(type: GlobalEnum.BuildingType) -> Array[Building]:
	var result: Array[Building] = []
	for b in buildings:
		if is_instance_valid(b) and b.building_type == type:
			result.append(b)
	return result
