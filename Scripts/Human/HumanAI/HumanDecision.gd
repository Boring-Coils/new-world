## 居民目标评分与工作中断判断的纯函数集合。[br]
## 只读取 [HumanAIContext] 并返回排序或判断结果，不扫描建筑、不修改目标、不发送事件。
extends RefCounted
class_name HumanDecision

## 工作目标的基础权重，用于与生存需求的紧迫度比较。
const WORK_WEIGHT: float = 10.0

## 被视为紧急生存需求的游戏内时间阈值，当前为 36 分钟。
const URGENT_GAME_SECONDS: float = 36.0 * 60.0

## 中断工作所需超过当前工作评分的倍率，避免需求在边界附近反复切换。
const WORK_INTERRUPT_MARGIN: float = 1.15


## 按生存紧迫度和工作权重返回从高到低排序的目标数组。[br]
## [param context] 是当前决策刻的居民状态快照。
static func rank_goals(context: HumanAIContext) -> Array[int]:
	var urgent_ticks := URGENT_GAME_SECONDS / TickManager.GAME_SECONDS_PER_TICK
	var scale := urgent_ticks * WORK_WEIGHT
	var candidates: Array[Dictionary] = []

	# 生存目标按剩余刻数倒数评分，剩余时间越短优先级越高。
	candidates.append({
		"goal": HumanAI.Goal.WATER,
		"score": (
			scale
			/ maxf(context.water_ticks_left, 1.0)
			* context.water_weight_multiplier
		),
		"priority": 0,
	})
	candidates.append({
		"goal": HumanAI.Goal.FOOD,
		"score": (
			scale
			/ maxf(context.food_ticks_left, 1.0)
			* context.food_weight_multiplier
		),
		"priority": 1,
	})

	if context.can_work:
		candidates.append({
			"goal": HumanAI.Goal.WORK,
			"score": WORK_WEIGHT * context.work_weight_multiplier,
			"priority": 2,
		})

	# 分数相同时使用固定优先级，保证行为结果可复现。
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var score_a: float = a["score"]
			var score_b: float = b["score"]
			if not is_equal_approx(score_a, score_b):
				return score_a > score_b
			return int(a["priority"]) < int(b["priority"])
	)

	var ranked: Array[int] = []
	for candidate in candidates:
		ranked.append(int(candidate["goal"]))
	return ranked


## 判断 [param goal] 是否已超过当前工作评分，足以请求立即中断工作。[br]
## [param context] 是当前决策刻的居民状态快照。[br]
## 只支持取水和取食目标；其他目标始终返回 [code]false[/code]。
static func should_interrupt_work_for_goal(
	context: HumanAIContext,
	goal: int,
) -> bool:
	var urgent_ticks := URGENT_GAME_SECONDS / TickManager.GAME_SECONDS_PER_TICK
	var scale := urgent_ticks * WORK_WEIGHT
	var candidate_score := 0.0

	if goal == HumanAI.Goal.WATER:
		candidate_score = (
			scale
			/ maxf(context.water_ticks_left, 1.0)
			* context.water_weight_multiplier
		)
	elif goal == HumanAI.Goal.FOOD:
		candidate_score = (
			scale
			/ maxf(context.food_ticks_left, 1.0)
			* context.food_weight_multiplier
		)
	else:
		return false

	# 工作中断需要超过当前工作评分一定余量，避免临界值附近反复切换状态。
	var current_work_score := WORK_WEIGHT * context.work_weight_multiplier
	return candidate_score >= current_work_score * WORK_INTERRUPT_MARGIN
