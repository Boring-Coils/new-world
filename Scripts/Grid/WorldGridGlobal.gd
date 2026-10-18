extends Node

## 全局世界网格。[br]
##
## 本节点本身只是个「外壳」，作用是让全项目共享同一个 [WorldGrid] 实例。


## 世界被切成多少格（横向 × 纵向）。想改世界大小，改这里即可。[br]
##
## 注意：修改后需重启项目才生效（网格在构造时一次性建立）。
const WORLD_CELLS := Vector2i(200, 150)


## 全局唯一的网格对象。[br]
##
## 用成员初始化写法，保证节点一被创建（早于任何场景的 [code]_ready[/code]）就已就绪，[br]
## 其它脚本无论何时访问它，拿到的都是同一个可用实例。
var world := WorldGrid.new(WORLD_CELLS)
