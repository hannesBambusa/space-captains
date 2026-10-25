"""Render build-bar icons (256x256 RGBA, transparent) for every buildable.

Run: Blender -b --python blender/render_icons.py [-- id1 id2 ...]
Output: assets/ui/icons/build/<id>.png
"""
import bpy, sys, os, math
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets/ui/icons/build")
M = "assets/models/"
# id -> glb (None = procedural defence zone)
ICONS = {
    "mining_outpost": M + "buildings/mining_outpost.glb",
    "mercenary_outpost": M + "buildings/mercenary_outpost.glb",
    "salvage_yard": M + "ships/salvager.glb",  # stand-in: buildings/salvage_yard.glb does not exist yet
    "defense_turret": M + "buildings/defense_turret.glb",
    "shield_generator": M + "buildings/shield_generator.glb",
    "factory": M + "station/addons/addon_factory.glb",
    "outfitter": M + "station/addons/addon_outfitter.glb",
    "science_lab": M + "station/addons/addon_science.glb",
    "defense_zone": None,
}
SIZE = 256
FILL = 0.97          # fraction of frame the silhouette may occupy
ELEV = 38            # camera elevation, degrees
AZIM = 35            # camera azimuth, degrees


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def emissive_mat(name, color, strength, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    n = m.node_tree.nodes
    n.clear()
    out = n.new("ShaderNodeOutputMaterial")
    em = n.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = color
    em.inputs["Strength"].default_value = strength
    if alpha < 1:
        tr = n.new("ShaderNodeBsdfTransparent")
        mix = n.new("ShaderNodeMixShader")
        mix.inputs[0].default_value = alpha
        m.node_tree.links.new(tr.outputs[0], mix.inputs[1])
        m.node_tree.links.new(em.outputs[0], mix.inputs[2])
        m.node_tree.links.new(mix.outputs[0], out.inputs[0])
    else:
        m.node_tree.links.new(em.outputs[0], out.inputs[0])
    return m


def build_defense_zone():
    """Flat disc + rim ring + dome lattice + a bright sector wedge."""
    objs = []
    amber = (1.0, 0.55, 0.12, 1)
    # rim ring
    bpy.ops.mesh.primitive_torus_add(major_radius=10, minor_radius=0.35, major_segments=96, minor_segments=12)
    ring = bpy.context.object
    ring.data.materials.append(emissive_mat("ring", (1.0, 0.38, 0.04, 1), 2.5))
    objs.append(ring)
    # translucent disc
    bpy.ops.mesh.primitive_circle_add(radius=10, vertices=96, fill_type="NGON")
    disc = bpy.context.object
    disc.data.materials.append(emissive_mat("disc", (1.0, 0.3, 0.03, 1), 1.0, 0.30))
    objs.append(disc)
    # dome lattice
    bpy.ops.mesh.primitive_uv_sphere_add(radius=10, segments=24, ring_count=8)
    dome = bpy.context.object
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.bisect(plane_co=(0, 0, 0), plane_no=(0, 0, 1), clear_inner=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    wf = dome.modifiers.new("wf", "WIREFRAME")
    wf.thickness = 0.22
    dome.data.materials.append(emissive_mat("dome", (1.0, 0.45, 0.08, 1), 1.6))
    objs.append(dome)
    # sector wedge (solid, brighter) as a pie of the disc, slightly raised
    bpy.ops.mesh.primitive_circle_add(radius=10, vertices=96, fill_type="TRIFAN")
    wedge = bpy.context.object
    bpy.ops.object.mode_set(mode="EDIT")
    import bmesh
    bm = bmesh.from_edit_mesh(wedge.data)
    for f in list(bm.faces):
        c = f.calc_center_median()
        a = math.degrees(math.atan2(c.y, c.x)) % 360
        if not (20 <= a <= 110):
            bmesh.ops.delete(bm, geom=[f], context="FACES")
    bmesh.update_edit_mesh(wedge.data)
    bpy.ops.object.mode_set(mode="OBJECT")
    wedge.location.z = 0.05
    wedge.data.materials.append(emissive_mat("wedge", (1.0, 0.33, 0.04, 1), 1.6, 0.65))
    objs.append(wedge)
    # glTF-style Y-up: rotate whole group so Z-up scene stays consistent (scene is Z-up in Blender)
    return objs


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def world_bbox(objs):
    pts = []
    for o in objs:
        if o.type != "MESH":
            continue
        pts += [o.matrix_world @ Vector(c) for c in o.bound_box]
    return pts


def setup_world_and_render():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = SIZE
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    try:
        sc.eevee.use_raytracing = False
    except Exception:
        pass
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.30, 0.33, 0.40, 1)  # cool ambient fill
    bg.inputs[1].default_value = 0.9
    sc.world = w


def add_light(name, kind, energy, color, loc, target=Vector((0, 0, 0)), size=6):
    ld = bpy.data.lights.new(name, kind)
    ld.energy = energy
    ld.color = color
    if kind == "AREA":
        ld.size = size
    ob = bpy.data.objects.new(name, ld)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    d = target - Vector(loc)
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    return ob


def render_one(icon_id, path):
    clear()
    setup_world_and_render()
    sc = bpy.context.scene
    objs = build_defense_zone() if path is None else import_glb(os.path.join(ROOT, path))
    # drop non-render helpers: empties/colliders
    for o in list(objs):
        if o.type == "MESH" and ("col" in o.name.lower().split("-")[-1] or "navmesh" in o.name.lower()):
            o.hide_render = True
    vis = [o for o in objs if not o.hide_render]
    pts = world_bbox(vis)
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    ctr = (mn + mx) / 2
    # camera
    cam_d = bpy.data.cameras.new("cam")
    cam_d.type = "ORTHO"
    cam = bpy.data.objects.new("cam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    e, a = math.radians(ELEV), math.radians(AZIM)
    dirv = Vector((math.cos(e) * math.sin(a), -math.cos(e) * math.cos(a), math.sin(e)))
    cam.location = ctr + dirv * 200
    cam.rotation_euler = (-dirv).to_track_quat("-Z", "Y").to_euler()
    bpy.context.view_layer.update()
    # fit: project bbox points into camera space
    inv = cam.matrix_world.inverted()
    cp = [inv @ p for p in pts]
    minx, maxx = min(p.x for p in cp), max(p.x for p in cp)
    miny, maxy = min(p.y for p in cp), max(p.y for p in cp)
    cam_d.ortho_scale = max(maxx - minx, maxy - miny) / FILL
    # shift so projected bbox is centred
    cam.location += cam.matrix_world.to_3x3() @ Vector(((minx + maxx) / 2, (miny + maxy) / 2, 0))
    cam_d.clip_start, cam_d.clip_end = 1, 1000
    # three-point lights, relative to camera azimuth; scene scale-independent (sun lights)
    def sun(name, energy, color, az, el):
        L = bpy.data.lights.new(name, "SUN")
        L.energy, L.color = energy, color
        L.angle = math.radians(20)
        o = bpy.data.objects.new(name, L)
        sc.collection.objects.link(o)
        aa, ee = math.radians(AZIM + az), math.radians(el)
        v = Vector((math.cos(ee) * math.sin(aa), -math.cos(ee) * math.cos(aa), math.sin(ee)))
        o.rotation_euler = (-v).to_track_quat("-Z", "Y").to_euler()
    sun("key", 4.5, (1.0, 0.96, 0.9), -50, 50)
    sun("fill", 1.6, (0.7, 0.8, 1.0), 60, 25)
    sun("rim", 6.0, (1.0, 0.55, 0.15), 160, 25)   # warm amber rim from behind
    out = os.path.join(OUT, icon_id + ".png")
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("rendered", icon_id, "->", out)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    os.makedirs(OUT, exist_ok=True)
    for icon_id, path in ICONS.items():
        if argv and icon_id not in argv:
            continue
        if path and not os.path.exists(os.path.join(ROOT, path)):
            print("MISSING model for", icon_id, path)
            continue
        render_one(icon_id, path)


main()
