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
	WEAKNESS,## 虚弱
}

## 衣服颜色预设。[br]
## 只允许用这里列出的几种，不能随便指定 RGB——每多一种颜色就得在 Blender 里
## 重新渲染一整套序列帧，所以颜色必须是「一张表」而不是一个自由变量。[br]
## 新增颜色：这里加一项 → 到 HumanVisual.PRESETS 里登记素材目录。
enum Outfit{
	BLUE,## 蓝色（目前唯一）
}

