## 居民序列帧表现组件。[br]
## 每个颜色预设包含 side、down、up 三个视角；朝左通过水平镜像 side 视角得到。[br]
## 组件只处理素材、动画与朝向，不参与寻路或行为决策。
extends Node2D
class_name HumanVisual

## 预设表：枚举 → 素材根目录 + 走路帧数。[br]
## 目录结构：<根目录>/side/、down/、up/，每个里面是 idle_0.png + walk_0..7.png。[br]
## 新增颜色：先在 [enum GlobalEnum.Outfit] 加一项，再在这里登记目录。
const PRESETS := {
	GlobalEnum.Outfit.BLUE: {
		"dir": "res://Assets/Human/blue/",
		"walk_frames": 8,
	},
}

## 素材里固定有三个视角，顺序无所谓，名字必须对上目录名
const VIEWS: Array[String] = ["side", "down", "up"]

## 序列帧缩放比例，使 128 像素贴图约为 8 个世界单位高。[br]
## 该比例同时保持脚底靠近节点原点下方约 4 像素的位置。
const SPRITE_SCALE: float = 0.08

## 走路动画的播放速度（帧/秒），和 Blender 里 12 fps 对齐
const WALK_FPS: float = 12.0

## 朝向
enum Facing {
	## 朝右，使用不镜像的 side 视角。
	RIGHT,
	## 朝左，使用水平镜像的 side 视角。
	LEFT,
	## 朝下，使用 down 视角。
	DOWN,
	## 朝上，使用 up 视角。
	UP,
}

## 当前用的是哪一套颜色
@export var outfit: GlobalEnum.Outfit = GlobalEnum.Outfit.BLUE:
	set(value):
		outfit = value
		if _sprite != null:
			_apply_outfit()

# 当前运行时创建的动画精灵。
var _sprite: AnimatedSprite2D

# 视角名到已构建帧资源的映射，切换朝向时只替换引用。
var _frames: Dictionary = {}

# 当前朝向，默认朝右。
var _facing: Facing = Facing.RIGHT

# 当前是否正在播放走路动画，用于避免重复启动动画。
var _moving: bool = false


## 创建动画精灵并加载当前服装预设的全部视角帧。
func _ready() -> void:
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	# 128 px 的贴图在屏幕上只剩 30 来像素，必须走 mipmap，否则缩小后会闪
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_sprite)
	_apply_outfit()


## 按当前预设，把三个视角的帧全部装好
func _apply_outfit() -> void:
	var preset: Dictionary = PRESETS.get(outfit, {})
	if preset.is_empty():
		push_warning("HumanVisual：没有登记这个颜色的素材 %s" % outfit)
		return

	# 三个视角共享同一套服装预设，只在切换朝向时替换 SpriteFrames 引用。
	_frames.clear()
	for view in VIEWS:
		_frames[view] = _build_frames(preset["dir"] + view + "/", preset["walk_frames"])
	_apply_view()


## 按当前朝向换帧、换镜像，并保持「在走 / 站着」的状态
func _apply_view() -> void:
	var view := "side"
	var flip := false
	# 左向没有单独素材，复用 side 并开启水平镜像。
	match _facing:
		Facing.LEFT:
			view = "side"
			flip = true
		Facing.RIGHT:
			view = "side"
		Facing.DOWN:
			view = "down"
		Facing.UP:
			view = "up"

	if _frames.has(view):
		_sprite.sprite_frames = _frames[view]
	_sprite.flip_h = flip
	_sprite.play("walk" if _moving else "idle")


## 从目录里把 idle 和 walk 的帧装进 [SpriteFrames]。[br]
## [param dir] 是包含 idle 与 walk 序列帧的素材目录。[br]
## [param walk_frames] 是期望加载的走路帧数量。[br]
## 没做成 .tres 是为了少一个要手工维护的资源文件：目录里有什么帧就播什么。[br]
## 返回构建完成的待机与走路动画资源。
func _build_frames(dir: String, walk_frames: int) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.set_animation_speed("idle", 1.0)
	var idle_texture := load(dir + "idle_0.png") as Texture2D
	if idle_texture != null:
		frames.add_frame("idle", idle_texture)

	frames.add_animation("walk")
	frames.set_animation_loop("walk", true)
	frames.set_animation_speed("walk", WALK_FPS)
	# 目录中缺失的帧直接跳过，允许素材按实际文件数量逐步补齐。
	for i in range(walk_frames):
		var texture := load("%swalk_%d.png" % [dir, i]) as Texture2D
		if texture != null:
			frames.add_frame("walk", texture)

	return frames


## 由 [Human] 连接 [signal HumanMotion.moving_changed] 后调用。[br]
## [param moving] 指定当前是否应播放走路动画。
func set_moving(moving: bool) -> void:
	if moving == _moving:
		return
	_moving = moving
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var animation_name := "walk" if moving else "idle"
	if _sprite.sprite_frames.has_animation(animation_name):
		_sprite.play(animation_name)


## 由 [Human] 连接 [signal HumanMotion.facing_changed] 后调用。[br]
## [param direction] 是当前移动方向向量，用于选择视角和镜像。[br]
## 斜着走时取「偏得多的那个轴」，和大多数像素游戏的习惯一致。
func set_facing(direction: Vector2) -> void:
	if direction.length_squared() < 0.000001:
		return

	var new_facing: Facing
	if absf(direction.x) >= absf(direction.y):
		new_facing = Facing.RIGHT if direction.x > 0.0 else Facing.LEFT
	else:
		new_facing = Facing.DOWN if direction.y > 0.0 else Facing.UP

	if new_facing == _facing:
		return
	_facing = new_facing
	_apply_view()
