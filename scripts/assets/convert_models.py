"""既製の 3D モデル (OpenGameArt の CC0) を、Godot が Blender 無しで読める glb に書き出す Blender のスクリプト。
.github/workflows/convert-models.yml が GitHub Actions のランナーで実行する (開発マシンでは 3D のアプリを起動しないため。
AGENTS.md「検証方法」)。書き出した glb は assets/models/ に commit し、ゲームはこのスクリプトを実行しない。

使い方: blender -b [<.blend>] -P scripts/assets/convert_models.py -- <種類> <出力の glb> [<入力>...]
  種類 arms:  入力は FBX と肌のテクスチャ (fps arms (rigged only) の FPS ARMS RIG 1.fbx と new_diff.png)。
              骨は残す (ゲームが親指と人差し指の骨を回してつまむ形にするため)
  種類 buyer: <.blend> に NPC male Steve の steve_npc1.blend を渡し、入力に同じ zip を展開したディレクトリを渡す。
              顔と頭の写真のテクスチャを、写真でない単色に差し替える (Steam で売る物に実在の人の顔を出さないため。
              issue #15 で決めた)。立ち姿の動き (idol) の最初の形でメッシュを固め、骨を外す (動かさない置き物のため)
どちらも、読んだモデルの骨・メッシュ・材質・画像の一覧を標準出力に出す (ゲーム側の骨の名前・大きさを決める材料)。
"""
import os
import sys

import bpy

# 写真から作られた顔と頭の画像の名前の始まり (steve_npc1.blend が参照する画像の名前)。単色の肌に差し替える
FACE_IMAGE_PREFIXES = ("headHDmale", "2014-12-31", "Untitled")
# 写真から作られた目の画像の名前の始まり。単色の暗い色に差し替える
EYE_IMAGE_PREFIXES = ("myeye",)
# 差し替える肌の色 (RGBA。sRGB の 0〜1)。同じ zip の arms2.png の腕の肌に近い明るさの見当
FACE_SKIN_COLOR = (0.80, 0.62, 0.52, 1.0)
# 差し替える目の色 (RGBA)。黒に近い焦げ茶で、肌の上で目の位置が見える色
EYE_COLOR = (0.10, 0.08, 0.07, 1.0)
# 差し替えの単色の画像の大きさ (px)。単色なので小さくてよい
FLAT_IMAGE_SIZE_PX = 4
# 立ち姿として固める動きの名前と、その動きの中の時刻 (frame)。steve_npc1.blend の動きの一覧 (ACTION の行) の、
# 立って待つ動き idol の最初の形
STANDING_ACTION_NAME = "idol"
STANDING_FRAME = 1


def dump_scene() -> None:
    """読み込んだ場面の物・骨・材質・画像の一覧を出す"""
    for obj in bpy.data.objects:
        print("OBJECT", obj.name, obj.type, "dims", tuple(round(v, 4) for v in obj.dimensions), "loc",
              tuple(round(v, 4) for v in obj.location), "parent", obj.parent.name if obj.parent else None)
        if obj.type == "MESH":
            print("  MESH verts", len(obj.data.vertices), "polys", len(obj.data.polygons),
                  "groups", len(obj.vertex_groups), "materials", [m.name if m else None for m in obj.data.materials])
        if obj.type == "ARMATURE":
            for bone in obj.data.bones:
                print("  BONE", bone.name, "parent", bone.parent.name if bone.parent else None,
                      "head", tuple(round(v, 4) for v in bone.head_local),
                      "tail", tuple(round(v, 4) for v in bone.tail_local))
    for image in bpy.data.images:
        print("IMAGE", image.name, image.filepath, tuple(image.size))
    for action in bpy.data.actions:
        print("ACTION", action.name, tuple(action.frame_range))


def flat_image(name: str, color: tuple) -> bpy.types.Image:
    """単色の画像を作り、blend の中に入れる"""
    image = bpy.data.images.new(name, FLAT_IMAGE_SIZE_PX, FLAT_IMAGE_SIZE_PX)
    image.pixels = list(color) * (FLAT_IMAGE_SIZE_PX * FLAT_IMAGE_SIZE_PX)
    image.pack()
    return image


def relink_images(source_dir: str) -> None:
    """blend が作者の手元のパスで参照している画像を、zip を展開したディレクトリの同じ名前 (拡張子は問わない) の
    ファイルに付け替える。見つからない画像はそのまま残す (顔の画像は後で差し替えるため)"""
    files = {os.path.splitext(name)[0]: os.path.join(source_dir, name) for name in os.listdir(source_dir)}
    for image in bpy.data.images:
        stem = os.path.splitext(os.path.basename(image.filepath))[0]
        if stem in files:
            image.filepath = files[stem]
            image.reload()
            image.pack()
            print("RELINK", image.name, files[stem], tuple(image.size))


def replace_photo_images() -> None:
    """顔・頭・目の写真の画像を、材質のノードから単色の画像へ差し替える"""
    skin = flat_image("buyer_face_skin", FACE_SKIN_COLOR)
    eye = flat_image("buyer_eye", EYE_COLOR)
    for material in bpy.data.materials:
        if not material.use_nodes:
            continue
        for node in material.node_tree.nodes:
            if node.type != "TEX_IMAGE" or node.image is None:
                continue
            if node.image.name.startswith(FACE_IMAGE_PREFIXES):
                print("REPLACE", material.name, node.image.name, "-> skin")
                node.image = skin
            elif node.image.name.startswith(EYE_IMAGE_PREFIXES):
                print("REPLACE", material.name, node.image.name, "-> eye")
                node.image = eye
    for image in list(bpy.data.images):
        if image.users == 0:
            bpy.data.images.remove(image)


def bake_standing_pose() -> None:
    """骨を立ち姿の形にし、メッシュに骨の変形を固めてから骨を消す"""
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    rig.animation_data_create()
    rig.animation_data.action = bpy.data.actions[STANDING_ACTION_NAME]
    bpy.context.scene.frame_set(STANDING_FRAME)
    for obj in [o for o in bpy.data.objects if o.type == "MESH"]:
        bpy.context.view_layer.objects.active = obj
        for modifier in [m for m in obj.modifiers if m.type == "ARMATURE"]:
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = world
        obj.vertex_groups.clear()
    bpy.data.objects.remove(rig)


def attach_skin_texture(texture_path: str) -> None:
    """FBX が画像を相対パスで見つけられなかった材質に、肌のテクスチャを貼る"""
    image = bpy.data.images.load(texture_path)
    image.pack()
    for material in bpy.data.materials:
        material.use_nodes = True
        nodes = material.node_tree.nodes
        bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None or bsdf.inputs["Base Color"].is_linked:
            continue
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = image
        material.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        print("ATTACH", material.name, image.name)


def export_glb(out_path: str) -> None:
    """場面を glb に書き出す (画像は glb の中に入れる。動きは入れない)"""
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        export_animations=False,
        export_skins=True,
    )


def main() -> None:
    """引数の種類に合わせて読み込み・加工・書き出しを行う"""
    args = sys.argv[sys.argv.index("--") + 1:]
    kind, out_path = args[0], args[1]
    if kind == "arms":
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.fbx(filepath=args[2])
        attach_skin_texture(args[3])
    elif kind == "buyer":
        dump_scene()
        relink_images(args[2])
        replace_photo_images()
        bake_standing_pose()
    else:
        raise SystemExit("unknown kind: " + kind)
    dump_scene()
    export_glb(out_path)
    print("EXPORTED", out_path)


main()
