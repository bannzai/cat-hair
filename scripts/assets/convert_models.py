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

# steve_npc1.blend の材質ごとに貼る画像 (zip の中のファイル名)。この blend は古い Blender の材質の形式で画像を
# 持つため、今の Blender で開くと画像のつながりが失われる (2 回目の変換の glb に画像が 0 枚だった)。そのため材質の
# 名前で貼り直す。写真から作られた顔・頭・耳・口・目 (headHDmale512.jpg・2014-12-31 22.17.24.jpg・mouth SUPER!.png・
# myeye.jpg) は貼らず、下の単色にする (Steam で売る物に実在の人の顔を出さないため。issue #15 で決めた)
BUYER_TEXTURE_FILES = {
    "shirt": "shirt.jpg",
    "manpants": "cargopantsuv.jpg",
    "super arms 2": "arms2.png",
    "black fancy shoes.000": "shoes!.png",
}
# 写真の代わりに単色にする材質と色 (RGBA。sRGB の 0〜1)。肌は同じ zip の arms2.png の腕の肌に近い明るさの見当、
# 目は肌の上で目の位置が見える黒に近い焦げ茶
FACE_SKIN_COLOR = (0.80, 0.62, 0.52, 1.0)
EYE_COLOR = (0.10, 0.08, 0.07, 1.0)
BUYER_FLAT_COLORS = {
    "headHDmale.000": FACE_SKIN_COLOR,
    "ear": FACE_SKIN_COLOR,
    "mouth2.000": FACE_SKIN_COLOR,
    "eye.000": EYE_COLOR,
}
# 腕の肌の粗さ。人の肌は薄く艶があり、布 (0.8) より少しだけ光を返す見当
SKIN_ROUGHNESS = 0.65
# 立ち姿として固める動きの名前と、その動きの中の時刻 (frame)。steve_npc1.blend の動きの一覧 (ACTION の行) の、
# 立って待つ動き idol の最初の形
STANDING_ACTION_NAME = "idol"
STANDING_FRAME = 1


def dump_scene() -> None:
    """読み込んだ場面の物・骨・材質・画像の一覧を出す"""
    for obj in bpy.data.objects:
        print("OBJECT", obj.name, obj.type, "dims", tuple(round(component, 4) for component in obj.dimensions), "loc",
              tuple(round(component, 4) for component in obj.location), "parent", obj.parent.name if obj.parent else None)
        if obj.type == "MESH":
            print("  MESH verts", len(obj.data.vertices), "polys", len(obj.data.polygons),
                  "groups", len(obj.vertex_groups), "materials", [slot.name if slot else None for slot in obj.data.materials])
        if obj.type == "ARMATURE":
            for bone in obj.data.bones:
                print("  BONE", bone.name, "parent", bone.parent.name if bone.parent else None,
                      "head", tuple(round(component, 4) for component in bone.head_local),
                      "tail", tuple(round(component, 4) for component in bone.tail_local))
    for image in bpy.data.images:
        print("IMAGE", image.name, image.filepath, tuple(image.size))
    for action in bpy.data.actions:
        print("ACTION", action.name, tuple(action.frame_range))


def principled_material(material: bpy.types.Material) -> bpy.types.Node:
    """材質のノードを、Principled BSDF が出力につながっただけの形に作り直し、その BSDF を返す"""
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    material.node_tree.links.new(bsdf.outputs["BSDF"], nodes.new("ShaderNodeOutputMaterial").inputs["Surface"])
    return bsdf


def assign_buyer_materials(source_dir: str) -> None:
    """買取業者の材質を、服・腕・靴は zip の画像、顔・耳・口・目は単色にする。どちらの一覧にも無い材質があれば
    止める (写真の画像が残ったまま書き出さないため)"""
    for material in bpy.data.materials:
        if material.users == 0:
            continue
        bsdf = principled_material(material)
        # 布と肌は光沢が少ないため、既定の 0.5 より艶を消す
        bsdf.inputs["Roughness"].default_value = 0.8
        if material.name in BUYER_TEXTURE_FILES:
            image = bpy.data.images.load(os.path.join(source_dir, BUYER_TEXTURE_FILES[material.name]))
            image.pack()
            texture_node = material.node_tree.nodes.new("ShaderNodeTexImage")
            texture_node.image = image
            material.node_tree.links.new(texture_node.outputs["Color"], bsdf.inputs["Base Color"])
            print("TEXTURE", material.name, image.name)
        elif material.name in BUYER_FLAT_COLORS:
            bsdf.inputs["Base Color"].default_value = BUYER_FLAT_COLORS[material.name]
            print("FLAT", material.name, BUYER_FLAT_COLORS[material.name])
        else:
            raise SystemExit("material without assignment: " + material.name)


def bake_standing_pose() -> None:
    """骨を立ち姿の形にし、メッシュに骨の変形を固めてから骨を消す"""
    rig = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
    rig.animation_data_create()
    rig.animation_data.action = bpy.data.actions[STANDING_ACTION_NAME]
    bpy.context.scene.frame_set(STANDING_FRAME)
    for obj in [candidate for candidate in bpy.data.objects if candidate.type == "MESH"]:
        bpy.context.view_layer.objects.active = obj
        for modifier in [candidate for candidate in obj.modifiers if candidate.type == "ARMATURE"]:
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
        bsdf = next((node for node in nodes if node.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None or bsdf.inputs["Base Color"].is_linked:
            continue
        texture_node = nodes.new("ShaderNodeTexImage")
        texture_node.image = image
        material.node_tree.links.new(texture_node.outputs["Color"], bsdf.inputs["Base Color"])
        # FBX の材質は金属の値を持ち込み、肌が銅のように光った (PR #69 の最初の撮影)。肌は金属でなく、艶の少ない値にする
        bsdf.inputs["Metallic"].default_value = 0.0
        bsdf.inputs["Roughness"].default_value = SKIN_ROUGHNESS
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
        bake_standing_pose()
        assign_buyer_materials(args[2])
    else:
        raise SystemExit("unknown kind: " + kind)
    dump_scene()
    export_glb(out_path)
    print("EXPORTED", out_path)


main()
