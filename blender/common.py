"""Shared helpers for the Space Captains bpy generator scripts."""
import math
import os

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PREVIEW_DIR = os.path.join(ROOT, "blender", "previews")


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material(name, color, roughness=0.8, metallic=0.0, emission=None,
                  emission_strength=0.0, use_vertex_color=False):
    """Principled BSDF only. Optional vertex color multiplies base color."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (-300, 0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    mat.use_backface_culling = True  # exports doubleSided=false
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    if use_vertex_color:
        # glTF exporter maps a Color Attribute node straight into Base Color as COLOR_0.
        # Godot multiplies vertex color into albedo. Base color factor stays white-ish
        # and the actual tint lives in the vertex colors.
        # Multiply keeps the real tint in baseColorFactor, so the asset still reads
        # right if the importer ignores COLOR_0. Vertex colors are near-1 multipliers.
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        attr.location = (-800, 0)
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.location = (-550, 0)
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs[7].default_value = (*color, 1.0)  # B (RGBA)
        nt.links.new(attr.outputs["Color"], mix.inputs[6])  # A (RGBA)
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    return mat


def export_glb(obj_or_root, path, extras=False, **gltf_kw):
    """extras=True writes object custom properties as glTF extras (Godot: node metadata).
    gltf_kw: extra export_scene.gltf options (e.g. export_image_format)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    objs = [obj_or_root] + list(obj_or_root.children_recursive)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obj_or_root
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_vertex_color="MATERIAL",
        export_animations=False,
        export_cameras=False,
        export_lights=False,
        export_extras=extras,
        **gltf_kw,
    )
    print("EXPORTED", path)


def setup_preview(cam_loc, cam_target, ortho_scale=None, res=(1600, 900),
                  key_dir=(-0.6, -0.4, 0.7), key_energy=4.0, bloom=True):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("preview_world")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.006, 0.008, 0.015, 1)
    bg.inputs["Strength"].default_value = 1.0

    import mathutils
    sun = bpy.data.lights.new("key", "SUN")
    sun.energy = key_energy
    sun.angle = math.radians(2)
    sun_obj = bpy.data.objects.new("key", sun)
    scene.collection.objects.link(sun_obj)
    d = mathutils.Vector(key_dir).normalized()
    sun_obj.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()

    cam = bpy.data.cameras.new("cam")
    cam_obj = bpy.data.objects.new("cam", cam)
    scene.collection.objects.link(cam_obj)
    cam_obj.location = cam_loc
    direction = mathutils.Vector(cam_target) - mathutils.Vector(cam_loc)
    cam_obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    if ortho_scale:
        cam.type = "ORTHO"
        cam.ortho_scale = ortho_scale
    cam.clip_end = 5000
    scene.camera = cam_obj

    if bloom:
        try:
            ng = bpy.data.node_groups.new("preview_comp", "CompositorNodeTree")
            scene.compositing_node_group = ng
            rl = ng.nodes.new("CompositorNodeRLayers")
            glare = ng.nodes.new("CompositorNodeGlare")
            out = ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
            gout = ng.nodes.new("NodeGroupOutput")
            for k, v in (("Type", "Bloom"), ("Quality", "High")):
                if k in glare.inputs:
                    glare.inputs[k].default_value = v
            if "Threshold" in glare.inputs:
                glare.inputs["Threshold"].default_value = 1.0
            if "Size" in glare.inputs:
                glare.inputs["Size"].default_value = 0.6
            ng.links.new(rl.outputs["Image"], glare.inputs["Image"])
            ng.links.new(glare.outputs["Image"], gout.inputs[0])
        except Exception as e:  # preview only, never fatal
            print("bloom setup skipped:", e)


def render(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)
