extends Node2D
class_name HumanVisual

## 居民外观：Blender 渲染出来的 2D 序列帧。[br]
## 每个颜色预设下有 [b]三个视角[/b]：side（朝右）、down（朝下/面向镜头）、up（朝上/背面）。[br]
## 「朝左」不是单独渲染的，用 [member AnimatedSprite2D.flip_h] 把 side 镜像过去。[br]
## [b]颜色只能是预设里的几种[/b]：每多一种颜色就要在 Blender 里重渲三套图，[br]
## 所以这里用 [member outfit] 指定「哪一套」，而不是让外面传一个 RGB 进来。

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

## 128 px 的贴图缩到 0.08，正好让小人约 8 个世界单位高（和原来的白模一致，
## 脚底落在 y ≈ +4 的位置）
const SPRITE_SCALE: float = 0.08

## 走路动画的播放速度（帧/秒），和 Blender 里 12 fps 对齐
const WALK_FPS: float = 12.0

## 朝向
enum Facing {
	RIGHT, ## 朝右（side 不镜像）
	LEFT,  ## 朝左（side 镜像）
	DOWN,  ## 朝下（down 视角）
	UP,    ## 朝上（up 视角）
}

## 当前用的是哪一套颜色
@export var outfit: GlobalEnum.Outfit = GlobalEnum.Outfit.BLUE:
	set(value):
		outfit = value
		if _sprite != null:
			_apply_outfit()

## 精灵本体
var _sprite: AnimatedSprite2D

## 视角名 → 已经装好的帧。换朝向时只是换一份引用，不重新加载贴图
var _frames: Dictionary = {}

## 当前朝向，默认朝右
var _facing: Facing = Facing.RIGHT

## 当前是不是在走路，避免每刻重复 play
var _moving: bool = false


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

	_frames.clear()
	for view in VIEWS:
		_frames[view] = _build_frames(preset["dir"] + view + "/", preset["walk_frames"])
	_apply_view()


## 按当前朝向换帧、换镜像，并保持「在走 / 站着」的状态
func _apply_view() -> void:
	var view := "side"
	var flip := false
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
## 没做成 .tres 是为了少一个要手工维护的资源文件：目录里有什么帧就播什么。
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
	for i in range(walk_frames):
		var texture := load("%swalk_%d.png" % [dir, i]) as Texture2D
		if texture != null:
			frames.add_frame("walk", texture)

	return frames


## 由 [HumanAI] 每刻调用：走路播 walk，站着播 idle
func set_moving(moving: bool) -> void:
	if moving == _moving:
		return
	_moving = moving
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var animation_name := "walk" if moving else "idle"
	if _sprite.sprite_frames.has_animation(animation_name):
		_sprite.play(animation_name)


## 由 [HumanAI] 在移动时调用：按位移方向选朝向。[br]
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
