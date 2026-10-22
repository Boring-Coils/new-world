class_name GlobalEnum

## 居民年龄的枚举量
enum AgeStatus{
	CHILD,## 儿童,18岁以下
	ADULT,## 成年,18岁及以上,60岁以下
	OLD,## 老年,60岁及以上
}

## 建筑类型
enum BuildingType{
	WATER,## 取水站
	FOOD,## 取食站
	WORK,## 工作站
}

## buff 类型。[br]
## 新增一种 buff 要在这里加一项，再到 [member BuffSystem.REGISTRY] 里登记它的脚本，[br]
## 漏了任何一处，[method BuffSystem.add_buff] 都会报「没有登记」。
enum BuffType{
	FATIGUE,## 疲劳：移动变慢，可叠加
	STUN,## 眩晕：不能工作，移动变慢
	THIRST,## 口渴：每刻额外扣水
}
