"""既製の 3D モデル (OpenGameArt の CC0) を、Godot が Blender 無しで読める glb に書き出す Blender のスクリプト。
.github/workflows/convert-models.yml が GitHub Actions のランナーで実行する (開発マシンでは 3D のアプリを起動しないため。
AGENTS.md「検証方法」)。書き出した glb は assets/models/ に commit し、ゲームはこのスクリプトを実行しない。

使い方: blender -b [<.blend>] -P scripts/assets/convert_models.py -- <種類> <出力の glb> [<入力>...]
  種類 arms:  入力は FBX と肌のテクスチャ (fps arms (rigged only) の FPS ARMS RIG 1.fbx と new_diff.png)
  種類 buyer: <.blend> に NPC male Steve の steve_npc1.blend を渡す。顔と頭の写真のテクスチャを、写真でない単色の肌に差し替える
              (Steam で売る物に実在の人の顔を出さないため。issue #15 で決めた)
どちらも、読んだモデルの骨・メッシュ・材質・画像の一覧を標準出力に出す (ゲーム側の骨の名前・大きさを決める材料)。
"""
import sys

import bpy

# 写真から作られた顔と頭の画像 (steve_npc1.blend が参照するファイル名)。単色の肌に差し替える
FACE_IMAGE_NAMES = ("headHDmale512", "2014-12-31 22.17.24", "myeye", "mouth SUPER!")
# 差し替える肌の色 (sRGB)。同じ zip の arms2.png の肌の平均に近い明るさの見当
FACE_SKIN_COLOR = (0.80, 0.62, 0.52, 1.0)
# 差し替えの単色の画像の大きさ (px)。単色なので小さくてよい
FLAT_IMAGE_SIZE_PX = 4


def dump_scene() -> None:
    """読み込んだ場面の物・骨・材質・画像の一覧を出す"""
    for obj in bpy.data.objects:
        print("OBJECT", obj.name, obj.type, "dims", tuple(round(v, 4) for v in obj.dimensions), "loc", tuple(round(v, 4) for v in obj.location),
              "parent", obj.parent.name if obj.parent else None)
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
    """単色の画像を作る"""
    image = bpy.data.images.new(name, FLAT_IMAGE_SIZE_PX, FLAT_IMAGE_SIZE_PX)
    image.pixels = list(color) * (FLAT_IMAGE_SIZE_PX * FLAT_IMAGE_SIZE_PX)
    image.pack()
    return image


def replace_face_images() -> None:
    """顔と頭の写真の画像を、材質のノードから単色の肌の画像へ差し替える"""
    flat = flat_image("buyer_face_skin", FACE_SKIN_COLOR)
    for material in bpy.data.materials:
        if not material.use_nodes:
            continue
        for node in material.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image is not None:
                if any(node.image.name.startswith(n) for n in FACE_IMAGE_NAMES):
                    print("REPLACE", material.name, node.image.name)
                    node.image = flat
    for image in list(bpy.data.images):
        if image.users == 0:
            bpy.data.images.remove(image)


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
    """場面を glb に書き出す (画像は glb の中に入れる)"""
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        export_animations=False,
        export_apply=False,
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
        replace_face_images()
    else:
        raise SystemExit("unknown kind: " + kind)
    dump_scene()
    export_glb(out_path)
    print("EXPORTED", out_path)


main()
