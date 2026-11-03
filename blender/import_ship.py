"""Helpers for ships made from bought or downloaded models (assets/models/new/).

The source file is imported, joined into one mesh, turned so the nose points along
Blender +Y, scaled to a set length, centred on the origin (ship centre on the play
plane z=0) and optionally decimated. The generator then adds the named nodes the game
needs (engine_glow, points) like the hand-built ships do.
"""
import math

import bpy
from mathutils import Matrix, Vector


def import_source(path):
    """Imports `path` (.obj, .gltf or .glb) and returns its mesh objects. The empties
    the importer made are kept in `_junk` for join() to delete."""
    before = set(bpy.data.objects)
    if path.endswith(".obj"):
        bpy.ops.wm.obj_import(filepath=path)
    else:
        bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    _junk.extend(o for o in new if o.type != "MESH")
    return [o for o in new if o.type == "MESH"]


_junk = []


def join(objs, name):
    """Joins `objs` into one mesh object called `name`, transforms applied, no parent."""
    for o in objs:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # Drop the empties the importer left behind.
    for o in _junk:
        bpy.data.objects.remove(o)
    _junk.clear()
    return obj


def bounds(obj):
    vs = [v.co for v in obj.data.vertices]
    lo = Vector([min(v[i] for v in vs) for i in range(3)])
    hi = Vector([max(v[i] for v in vs) for i in range(3)])
    return lo, hi


def fit(obj, yaw_deg, length):
    """Turns `obj` by `yaw_deg` about Z, scales its Y extent to `length` metres and
    centres its bounding box on the origin. Returns the scale factor."""
    obj.data.transform(Matrix.Rotation(math.radians(yaw_deg), 4, "Z"))
    lo, hi = bounds(obj)
    k = length / (hi.y - lo.y)
    c = (lo + hi) * 0.5
    obj.data.transform(Matrix.Scale(k, 4) @ Matrix.Translation(-c))
    obj.data.update()
    return k


def decimate(obj, target_tris):
    """Collapse-decimates `obj` to about `target_tris` triangles (no-op when already under)."""
    tris = tris_of(obj)
    if tris <= target_tris:
        return tris
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new("decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = target_tris / tris
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return tris_of(obj)


def tris_of(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def decimate_pieces(objs, ratio_of, angle_deg=1.0):
    """Cuts the separate source pieces down before join(): a planar dissolve first (flat
    panels lose their extra loops), then a collapse at `ratio_of(obj, tris)` (1.0 keeps
    the piece). Decimating piece by piece with a ratio per kind keeps the hard-surface
    hull intact while smooth, overly dense parts lose most of their triangles; one
    collapse over the joined mesh tears the panels apart. Returns the new total."""
    for o in objs:
        merge_close(o, 1e-4)  # split vertices at UV/normal seams block the collapse
        bpy.context.view_layer.objects.active = o
        mod = o.modifiers.new("planar", "DECIMATE")
        mod.decimate_type = "DISSOLVE"
        mod.angle_limit = math.radians(angle_deg)
        mod.delimit = {"MATERIAL"}
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for o in objs:
        r = ratio_of(o, tris_of(o))
        if r >= 1.0:
            continue
        bpy.context.view_layer.objects.active = o
        # Collapse counts faces, so triangulate the dissolved n-gons first to make
        # the ratio a triangle ratio.
        tri = o.modifiers.new("triangulate", "TRIANGULATE")
        bpy.ops.object.modifier_apply(modifier=tri.name)
        mod = o.modifiers.new("collapse", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = r
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return sum(tris_of(o) for o in objs)


def merge_close(obj, dist):
    """Welds vertices closer than `dist` (seams between the source's separate pieces)."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
    bm.to_mesh(obj.data)
    bm.free()


def set_materials(obj, mapping):
    """Replaces each material slot whose source name starts with a key of `mapping`
    by the mapped material. Unmatched slots keep their source material."""
    for slot in obj.material_slots:
        if slot.material is None:
            continue
        for prefix, mat in mapping.items():
            if slot.material.name.startswith(prefix):
                slot.material = mat
                break


def faces_with(obj, mat_names):
    """Centres of the faces using any material named in `mat_names`."""
    idx = {i for i, s in enumerate(obj.material_slots) if s.material and s.material.name in mat_names}
    return [p.center.copy() for p in obj.data.polygons if p.material_index in idx]
