"""用 Blender 生成居民的小人序列帧（侧面，朝 +X）。

跑法：
    blender --background --python Tools/Blender/make_human.py

产物：
    Assets/Human/blue/idle_0.png      站立（1 帧）
    Assets/Human/blue/walk_0..7.png   走路循环（8 帧）

相机在 -Y 方向、正交投影，所以看到的是角色的侧面。角色朝 +X（画面右边），
游戏里往左走时用 flip_h 水平镜像。

模型是「方块拼的」低模：身体、四肢分开，各自以肩/髋为原点旋转，
不做骨骼蒙皮——这个精度下蒙皮没有收益，反而容易出诡异变形。
"""

import math
import os

import bpy
from mathutils import Matrix

# ---------------------------------------------------------------------------
# 输出与渲染设置
# ---------------------------------------------------------------------------

PROJECT = r"H:\Projects\new-world"
OUT_DIR = os.path.join(PROJECT, "Assets", "Human", "blue")

RES = 128          # 每帧边长（像素）
SAMPLES = 32       # Cycles 采样
FPS = 12           # 走路一个循环 8 帧 ≈ 0.67 秒

WALK_FRAMES = 8
LEG_SWING = 26.0   # 腿摆幅（度）
ARM_SWING = 20.0   # 手臂摆幅（度）

## 三个视角。镜头固定在 -Y 方向，靠转动角色本身来换朝向：
##   side = 朝 +X（画面右；游戏里往左走用镜像）
##   down = 朝 -Y（面向镜头 = 游戏里往下走）
##   up   = 朝 +Y（背对镜头 = 游戏里往上走）
VIEWS = {
    "side": 0.0,
    "down": -90.0,
    "up": 90.0,
}


def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = False
    scene.render.resolution_x = RES
    scene.render.resolution_y = RES
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.fps = FPS

    # 环境光：让背光面不至于全黑，但别太亮把颜色冲淡
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    background = world.node_tree.nodes["Background"]
    background.inputs[0].default_value = (0.75, 0.80, 0.90, 1.0)
    background.inputs[1].default_value = 0.55
    scene.world = world

    # 主光：斜前上方
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 3.5
    sun_data.angle = math.radians(15)
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(55), 0.0, math.radians(-35))
    scene.collection.objects.link(sun)

    return scene


def setup_camera(scene):
    """正交相机放在 -Y 侧，看向 +Y：看到的是角色侧面。

    ortho_scale = 2.0 表示画面竖着覆盖 2 个世界单位，
    角色高约 1.7，正好上下留一点边。
    """
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.0
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = (0.0, -6.0, 0.80)
    cam.rotation_euler = (math.radians(90), 0.0, 0.0)
    scene.collection.objects.link(cam)
    scene.camera = cam


# ---------------------------------------------------------------------------
# 材质
# ---------------------------------------------------------------------------

def make_material(name, rgb, roughness=0.85):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return material


# ---------------------------------------------------------------------------
# 几何
# ---------------------------------------------------------------------------

def box(name, size, center, material, pivot="center"):
    """造一个长方体。

    pivot="top" 时把原点挪到顶面中心——手臂/腿这样旋转才是绕肩/髋摆动。
    """
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)

    if pivot == "top":
        # 原点要挪到顶面：物体位置抬到 +h/2，网格相对原点往下挪 h/2，
        # 两边必须一正一负，否则模型会整体上移一个身高（第一次就踩了这个坑）
        offset = size[2] * 0.5
        obj.data.transform(Matrix.Translation((0.0, 0.0, -offset)))
        obj.location = (center[0], center[1], center[2] + offset)
    return obj


def sphere(name, radius, center, material, scale=(1.0, 1.0, 1.0)):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=16, ring_count=8, radius=radius, location=center
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    bpy.ops.object.shade_flat()
    return obj


def build_character():
    """拼一个小人，面朝 +X（画面右）。

    比例走「矮胖」路线：头约占总高 30%，腿 33%，身体 33%。
    精灵最终在屏幕上只有 30 来个像素高，头大一点才认得出来是人。
    """
    skin = make_material("Skin", (0.96, 0.90, 0.83))
    cloth = make_material("Cloth", (0.30, 0.65, 0.95))   # 蓝色（唯一的预设）
    trousers = make_material("Trousers", (0.20, 0.22, 0.28))
    hair_mat = make_material("Hair", (0.26, 0.21, 0.18))

    parts = {}

    # 腿：原点在髋部（z=0.55）
    parts["leg_far"] = box("LegFar", (0.16, 0.16, 0.55), (0.0, 0.10, 0.275), trousers, "top")
    parts["leg_near"] = box("LegNear", (0.16, 0.16, 0.55), (0.0, -0.10, 0.275), trousers, "top")

    # 身体：0.55 ~ 1.10
    parts["body"] = box("Body", (0.30, 0.36, 0.55), (0.0, 0.0, 0.825), cloth)

    # 手臂：原点在肩部（z=1.05）
    parts["arm_far"] = box("ArmFar", (0.14, 0.14, 0.45), (0.0, 0.24, 0.825), cloth, "top")
    parts["arm_near"] = box("ArmNear", (0.14, 0.14, 0.45), (0.0, -0.24, 0.825), cloth, "top")

    # 头 + 头发：头直径 0.5，占总高约三成。
    # 头发是「扣在头顶的帽子」：往后偏一点、压扁，脸（+X 那面）要露出来，
    # 否则从侧面看整个头都是头发颜色，像戴了个头盔。
    parts["head"] = sphere("Head", 0.25, (0.0, 0.0, 1.35), skin)
    parts["hair"] = sphere("Hair", 0.26, (-0.03, 0.0, 1.48), hair_mat, (1.0, 1.0, 0.70))

    # 鼻子：侧面能一眼看出朝哪边（小方块，朝 +X 凸出去）
    parts["nose"] = box("Nose", (0.07, 0.07, 0.07), (0.25, 0.0, 1.33), skin)

    # 眼睛：两只都做。侧面看时远的那只被头挡住，正面看时两只都在
    eye_mat = make_material("Eye", (0.12, 0.12, 0.15), 0.5)
    parts["eye_near"] = box("EyeNear", (0.05, 0.06, 0.06), (0.20, -0.14, 1.36), eye_mat)
    parts["eye_far"] = box("EyeFar", (0.05, 0.06, 0.06), (0.20, 0.14, 1.36), eye_mat)

    return parts


def build_rig(scene, parts):
    """把所有部件挂到一个空物体下。

    这样转动这个空物体就能让角色整体转向，而四肢的关键帧仍然是「相对身体」的角度，
    三个视角共用同一套走路动画，不用重做。
    """
    rig = bpy.data.objects.new("Rig", None)
    scene.collection.objects.link(rig)
    for obj in parts.values():
        obj.parent = rig
        obj.matrix_parent_inverse = rig.matrix_world.inverted()
    return rig


# ---------------------------------------------------------------------------
# 动画
# ---------------------------------------------------------------------------

def set_pose(parts, phase):
    """按相位摆姿势。phase 是 0~1 的循环位置。

    腿和手臂反相：左腿向前时左臂向后，看起来才像走路。
    """
    swing = math.sin(phase * math.tau)
    parts["leg_near"].rotation_euler = (0.0, math.radians(LEG_SWING) * swing, 0.0)
    parts["leg_far"].rotation_euler = (0.0, -math.radians(LEG_SWING) * swing, 0.0)
    parts["arm_near"].rotation_euler = (0.0, -math.radians(ARM_SWING) * swing, 0.0)
    parts["arm_far"].rotation_euler = (0.0, math.radians(ARM_SWING) * swing, 0.0)

    # 身体上下颠一点，走路才有重量感
    parts["body"].location.z = 0.825 + abs(math.cos(phase * math.tau)) * 0.018


def key_pose(parts, frame):
    for key in ("leg_near", "leg_far", "arm_near", "arm_far"):
        parts[key].keyframe_insert("rotation_euler", frame=frame)
    parts["body"].keyframe_insert("location", frame=frame)


# ---------------------------------------------------------------------------
# 渲染
# ---------------------------------------------------------------------------

def render_frames(scene, out_root, view_name):
    out_dir = os.path.join(out_root, view_name)
    os.makedirs(out_dir, exist_ok=True)
    scene.render.filepath = os.path.join(out_dir, "idle_0.png")
    bpy.ops.render.render(write_still=True)

    for i in range(WALK_FRAMES):
        scene.frame_set(i + 1)
        scene.render.filepath = os.path.join(out_dir, "walk_%d.png" % i)
        bpy.ops.render.render(write_still=True)
    print("[BLENDER] %s：idle 1 帧 + walk %d 帧" % (view_name, WALK_FRAMES))


def main():
    scene = setup_scene()
    setup_camera(scene)
    parts = build_character()
    rig = build_rig(scene, parts)

    # 建关键帧：1~9 帧，第 9 帧等于第 1 帧，循环回来不会抖
    for i in range(WALK_FRAMES + 1):
        set_pose(parts, float(i) / float(WALK_FRAMES))
        key_pose(parts, i + 1)

    # 站立帧：所有角度归零
    set_pose(parts, 0.0)
    for key in ("leg_near", "leg_far", "arm_near", "arm_far"):
        parts[key].rotation_euler = (0.0, 0.0, 0.0)

    for view_name, angle in VIEWS.items():
        rig.rotation_euler = (0.0, 0.0, math.radians(angle))
        scene.frame_set(1)
        render_frames(scene, OUT_DIR, view_name)

    print("[BLENDER] 完成，输出目录：", OUT_DIR)


if __name__ == "__main__":
    main()
