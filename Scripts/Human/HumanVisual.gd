extends Node2D
class_name HumanVisual

## 居民外观：Blender 渲染出来的 2D 序列帧，侧面朝右。[br]
## 往左走时用 [member AnimatedSprite2D.flip_h] 水平镜像，所以只需要渲染一个朝向。[br]
## [b]颜色只能是预设里的几种[/b]：每多一种颜色就要在 Blender 里重渲一整套图，[br]
## 所以这里用 [member outfit] 指定「哪一套」，而不是让外面传一个 RGB 进来。

## 预设表：枚举 → 素材目录 + 走路帧数。[br]
## 新增颜色：先在 [enum GlobalEnum.Outfit] 加一项，再在这里登记目录。
const PRESETS := {
	GlobalEnum.Outfit.BLUE: {
		"dir": "res://Assets/Human/blue/",
		"walk_frames": 8,
	},
}

## 128 px 的贴图缩到 0.08，正好让小人约 8 个世界单位高（和原来的白模一致，
## 脚底落在 y ≈ +4 的位置）
const SPRITE_SCALE: float = 0.08

## 走路动画的播放速度（帧/秒），和 Blender 里 12 fps 对齐
const WALK_FPS: float = 12.0

## 当前用的是哪一套颜色
@export var outfit: GlobalEnum.Outfit = GlobalEnum.Outfit.BLUE:
	set(value):
		outfit = value
		if _sprite != null:
			_apply_outfit()

## 精灵本体
var _sprite: AnimatedSprite2D

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


## 按当前预设换一套序列帧
func _apply_outfit() -> void:
	var preset: Dictionary = PRESETS.get(outfit, {})
	if preset.is_empty():
		push_warning("HumanVisual：没有登记这个颜色的素材 %s" % outfit)
		return
	_sprite.sprite_frames = _build_frames(preset["dir"], preset["walk_frames"])
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


## 由 [Human] 每刻调用：走路播 walk，站着播 idle
func set_moving(moving: bool) -> void:
	if moving == _moving:
		return
	_moving = moving
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var animation_name := "walk" if moving else "idle"
	if _sprite.sprite_frames.has_animation(animation_name):
		_sprite.play(animation_name)


## 朝右走传 true，朝左走传 false（贴图本身朝右，往左靠镜像）
func set_facing(right: bool) -> void:
	if _sprite == null:
		return
	_sprite.flip_h = not right
