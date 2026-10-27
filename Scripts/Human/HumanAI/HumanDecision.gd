extends RefCounted
class_name HumanDecision

## 纯目标评分与排序，不扫描建筑、不修改目标、不发送事件。

const WORK_WEIGHT: float = 10.0
const URGENT_GAME_SECONDS: float = 36.0 * 60.0
const WORK_INTERRUPT_MARGIN: float = 1.15


static func rank_goals(context: HumanAIContext) -> Array[int]:
	var urgent_ticks := URGENT_GAME_SECONDS / TickManager.GAME_SECONDS_PER_TICK
	var scale := urgent_ticks * WORK_WEIGHT
	var candidates: Array[Dictionary] = []

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

	var current_work_score := WORK_WEIGHT * context.work_weight_multiplier
	return candidate_score >= current_work_score * WORK_INTERRUPT_MARGIN
