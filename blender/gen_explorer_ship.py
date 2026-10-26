"""Generate the explorer (scout / survey) ship .glb and previews.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_explorer_ship.py
  Args after `--`:
    --no-preview      skip the PNG renders
    --out-dir DIR     also write ship_preview.png (3/4 + side) and fleet_lineup.png there

Design: long-range survey ship, functional hard sci-fi. Long and lean: a slim chamfered
command module with a wraparound flight-deck window band, a long forward sensor boom
(lidar/optics pod at the tip, scan_point), two swept-back whisker antennas, a narrow
open spine truss carrying two slim propellant tanks and a survey sensor dish on a mast
(its own object, sensor_dish, origin on the mast pivot so Godot can turn it), then the
drive section: a jump drive coil ring with cyan emitter band, a reactor drum with
vertical (edge-on) radiators, and one long slim engine bell with a blue-white glow.
White hull with navy panels and cyan survey lights. Top-down: a long needle with a disc
(the dish) and a ring (the drive), about 20 m long and 3 m across the hull.

Layout (Blender Z up, exported +Y up). Ship centre at origin on the play plane z=0.
The nose points along Blender +Y, which the exporter turns into Godot -Z (forward).
Hierarchy: explorer (empty root) -> explorer_hull, explorer_drive, sensor_dish,
  engine_glow, scan_point (empty).
engine_glow has its origin on the bell exit plane (Blender y = NOZZLE_Y) and its plume
extends along Godot local +Z, so scaling it on Z lengthens the glow backwards.
scan_point is unrotated, so its Godot -Z points forward out of the sensor boom.
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
from parts import ALONG_Y, V, rot  # noqa: E402

OUT = os.path.join(common.ROOT, "assets", "models", "ships", "explorer.glb")
SCAN_Y = 11.0          # sensor boom tip
NOSE_Y = 7.4           # front of the command module
CMD_Y0 = 3.2           # rear of the command module
SPINE_Y0 = -3.6        # spine truss runs SPINE_Y0..CMD_Y0
RING_Y = -4.3          # jump drive coil ring
NOZZLE_Y = -8.6
BELL_R = 0.78
BELL_LEN = 1.5
DISH_PIVOT = (0.0, -0.4, 1.0)   # top of the spine, where the dish mast turns
DISH_R = 1.55

MATS = {}


def build_materials():
    m = common.make_material
    MATS["hull"] = m("expl_hull_white", (0.80, 0.82, 0.84), roughness=0.42, metallic=0.1)
    MATS["hull2"] = m("expl_hull_grey", (0.46, 0.49, 0.53), roughness=0.5, metallic=0.2)
    MATS["navy"] = m("expl_panel_navy", (0.035, 0.08, 0.2), roughness=0.4, metallic=0.25)
    MATS["dark"] = m("expl_structure_dark", (0.06, 0.065, 0.07), roughness=0.55, metallic=0.5)
    MATS["steel"] = m("expl_steel", (0.30, 0.32, 0.35), roughness=0.45, metallic=0.55)
    MATS["gold"] = m("expl_foil_gold", (0.72, 0.52, 0.16), roughness=0.3, metallic=0.9)
    MATS["window"] = m("expl_window_cool", (0.75, 0.9, 1.0), roughness=0.25,
                       emission=(0.55, 0.82, 1.0), emission_strength=3.0)
    MATS["cyan"] = m("expl_light_cyan", (0.2, 0.9, 1.0), roughness=0.3,
                     emission=(0.15, 0.85, 1.0), emission_strength=6.0)
    MATS["drive"] = m("expl_drive_band", (0.2, 0.7, 1.0), roughness=0.3,
                      emission=(0.1, 0.6, 1.0), emission_strength=3.5)
    MATS["nav_r"] = m("expl_nav_red", (1.0, 0.05, 0.03), roughness=0.3,
                      emission=(1.0, 0.05, 0.03), emission_strength=5.0)
    MATS["nav_g"] = m("expl_nav_green", (0.1, 1.0, 0.25), roughness=0.3,
                      emission=(0.1, 1.0, 0.25), emission_strength=5.0)
    MATS["glow"] = m("expl_engine_glow", (0.75, 0.92, 1.0), roughness=0.2,
                     emission=(0.6, 0.88, 1.0), emission_strength=5.0)


def cmd_mat(i, j):
    """Command module loft: navy belly and lower flanks, white top."""
    return "navy" if j in (5, 6, 7, 0) else "hull"


def build_hull():
    p = parts.Part("explorer_hull", MATS)
    # --- Command module: slim chamfered hull tapering to a wedge nose
    rings = [parts.oct_ring(CMD_Y0, 1.5, 1.4, 0.4),
             parts.oct_ring(CMD_Y0 + 1.6, 1.7, 1.6, 0.45),
             parts.oct_ring(NOSE_Y - 1.4, 1.6, 1.5, 0.45, z0=0.0),
             parts.oct_ring(NOSE_Y - 0.4, 1.1, 1.0, 0.3, z0=-0.1),
             parts.oct_ring(NOSE_Y, 0.7, 0.6, 0.18, z0=-0.15)]
    p.loft(rings, "hull", mat_fn=cmd_mat)
    # Wraparound flight-deck window band on the nose taper
    for k in range(3):
        p.box(V((-0.32 + k * 0.32, NOSE_Y - 0.75, 0.48)), (0.24, 0.42, 0.06), "window",
              r=rot(rx=-0.55), bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 0.66, NOSE_Y - 0.85, 0.2)), (0.06, 0.5, 0.22), "window",
              r=rot(rz=sx * 0.45), bevel=0.0)
        for k in range(3):  # cabin portholes
            p.box(V((sx * 0.86, CMD_Y0 + 1.2 + k * 0.45, 0.25)), (0.05, 0.2, 0.16), "window",
                  bevel=0.0)
    # Navy identity stripe on the roof and a docking collar behind the cockpit
    p.box(V((0, CMD_Y0 + 2.0, 0.8)), (0.5, 3.0, 0.04), "navy", bevel=0.0)
    p.cyl(V((0, CMD_Y0 + 0.9, 0.78)), 0.36, 0.36, 0.14, "steel", segs=12)
    p.cyl(V((0, CMD_Y0 + 0.9, 0.85)), 0.25, 0.25, 0.06, "hull2", segs=12)
    # Rear bulkhead of the command module
    p.cyl(V((0, CMD_Y0 - 0.05, 0)), 0.65, 0.65, 0.2, "steel", segs=12, axis_rot=ALONG_Y)
    # --- Forward sensor boom: tapered mast, ring braces, optics pod with cyan lens
    p.tube(V((0, NOSE_Y - 0.1, -0.15)), V((0, SCAN_Y - 0.6, -0.15)), 0.16, 0.08, "hull2", segs=8)
    for y in (NOSE_Y + 0.9, NOSE_Y + 2.0):
        p.cyl(V((0, y, -0.15)), 0.17, 0.17, 0.1, "dark", segs=8, axis_rot=ALONG_Y)
    p.cyl(V((0, SCAN_Y - 0.55, -0.15)), 0.22, 0.26, 0.35, "navy", segs=10, axis_rot=ALONG_Y)
    p.sphere(V((0, SCAN_Y - 0.3, -0.15)), 0.24, "hull", segs=12, rings=6)
    p.sphere(V((0, SCAN_Y - 0.12, -0.15)), 0.12, "cyan", segs=8, rings=4)
    # Small side spikes on the pod (passive sensors)
    for sx in (-1, 1):
        p.tube(V((sx * 0.2, SCAN_Y - 0.5, -0.15)), V((sx * 0.55, SCAN_Y - 0.9, -0.15)),
               0.03, 0.015, "dark", segs=4)
    # --- Whisker antennas: swept back and out from the command module flanks
    for sx in (-1, 1):
        root = V((sx * 0.8, CMD_Y0 + 2.4, 0.1))
        tip = V((sx * 2.2, CMD_Y0 - 1.6, 0.25))
        p.box(root, (0.22, 0.5, 0.3), "steel", bevel=0.1)
        p.tube(root, tip, 0.06, 0.03, "hull2", segs=6)
        p.box(tip, (0.12, 0.12, 0.12), "nav_g" if sx > 0 else "nav_r", bevel=0.0)
        # RCS quads on the cabin chamfers
        for sz in (-1, 1):
            parts.rcs_quad(p, V((sx * 0.68, CMD_Y0 + 3.0, sz * 0.62)), (sx, 0, sz), "steel",
                           "dark", s=0.2)
    # --- Spine: narrow open truss from the command module back to the drive
    parts.box_truss(p, SPINE_Y0, CMD_Y0, 0.42, 0.42, 5, "hull2", "dark", chord=0.14,
                    brace=0.07)
    p.cyl(V((0, (SPINE_Y0 + CMD_Y0) / 2, 0)), 0.22, 0.22, CMD_Y0 - SPINE_Y0, "steel", segs=8,
          axis_rot=ALONG_Y)  # coolant / power conduit through the truss
    # Two slim propellant tanks strapped low on the spine flanks
    for sx in (-1, 1):
        parts.capsule(p, SPINE_Y0 + 0.4, CMD_Y0 - 0.5, 0.36,
                      lambda i, j: "gold" if j in (0, 7) else "hull", segs=12,
                      x=sx * 0.82, z=-0.2, dome0=0.6, dome1=0.6, steps=2)
        for y in (SPINE_Y0 + 1.4, CMD_Y0 - 1.5):
            p.beam(V((sx * 0.42, y, -0.2)), V((sx * 0.82, y, -0.2)), 0.08, 0.08, "dark")
            p.cyl(V((sx * 0.82, y, -0.2)), 0.38, 0.38, 0.08, "navy", segs=12, axis_rot=ALONG_Y)
    # Dish mast base on top of the spine
    p.cyl(V((DISH_PIVOT[0], DISH_PIVOT[1], DISH_PIVOT[2] - 0.38)), 0.32, 0.26, 0.2, "steel",
          segs=10)
    # Survey lights along the spine roof
    for y in (SPINE_Y0 + 0.3, 2.4):
        p.box(V((0, y, 0.5)), (0.12, 0.12, 0.1), "cyan", bevel=0.0)
    return p


def build_drive():
    p = parts.Part("explorer_drive", MATS)
    # Jump drive coil: a big ring around the spine, cyan emitter band on the inner face
    rmat = parts.rot(rx=math.pi / 2)
    p.torus(V((0, RING_Y, 0)), 1.5, 0.26, "navy", segs=28, minor_segs=8, matrix=rmat)
    p.torus(V((0, RING_Y + 0.42, 0)), 1.42, 0.09, "steel", segs=28, minor_segs=4, matrix=rmat)
    p.torus(V((0, RING_Y, 0)), 1.3, 0.07, "drive", segs=28, minor_segs=4, matrix=rmat)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        d = V((math.cos(a), 0, math.sin(a)))
        p.beam(d * 0.5 + V((0, RING_Y, 0)), d * 1.35 + V((0, RING_Y, 0)), 0.14, 0.12, "steel")
        p.box(d * 1.5 + V((0, RING_Y, 0)), (0.3, 0.5, 0.3), "hull2", r=rot(ry=-a), bevel=0.1)
    # Drive core drum inside the ring
    p.cyl(V((0, RING_Y, 0)), 0.55, 0.55, 1.2, "hull", segs=12, axis_rot=ALONG_Y)
    p.cyl(V((0, RING_Y, 0)), 0.58, 0.58, 0.25, "drive", segs=12, axis_rot=ALONG_Y)
    # Reactor drum and vertical radiators (edge-on from above, keeps the needle silhouette)
    p.cyl(V((0, -5.6, 0)), 0.7, 0.7, 1.0, "hull", segs=12, axis_rot=ALONG_Y)
    p.cyl(V((0, -5.15, 0)), 0.73, 0.73, 0.12, "navy", segs=12, axis_rot=ALONG_Y)
    for sz in (-1, 1):
        parts.radiator(p, V((0, -6.0, sz * 1.15)), 2.2, 1.0, (1, 0, 0), "dark", "steel",
                       ribs=6, t=0.05)
        p.box(V((0, -6.0, sz * 0.6)), (0.12, 1.6, 0.25), "steel", bevel=0.0)
        p.box(V((0, -5.1, sz * 1.65)), (0.1, 0.1, 0.1), "cyan", bevel=0.0)
    for sx in (-1, 1):
        parts.rcs_quad(p, V((sx * 0.72, -5.6, 0)), (sx, 0, 0), "steel", "dark", s=0.2)
    # Thrust frame and the long slim bell
    p.tube(V((0, -6.1, 0)), V((0, NOZZLE_Y + BELL_LEN, 0)), 0.55, 0.38, "steel", segs=12)
    parts.bell(p, NOZZLE_Y, BELL_R, BELL_LEN, "hull2", "dark", segs=16, throat=0.45)
    p.torus(V((0, NOZZLE_Y + 0.4, 0)), BELL_R * 0.86, 0.04, "dark", segs=16, minor_segs=4,
            matrix=rmat)
    return p


def build_dish():
    """Survey dish on a short mast. Built around DISH_PIVOT (object origin) so Godot can
    rotate the object about its local Y (up) to sweep the dish."""
    p = parts.Part("sensor_dish", MATS)
    p.cyl(V((0, 0, 0.2)), 0.1, 0.08, 0.6, "steel", segs=8)          # mast
    p.cyl(V((0, 0, 0.55)), 0.18, 0.18, 0.2, "dark", segs=8, axis_rot=parts.ALONG_X)  # yoke
    c = V((0, 0.05, 0.75))
    parts.dish(p, c, DISH_R, (0, 0.55, 1), "hull", "dark", depth=0.38, segs=20)
    # Navy back plate and gold feed so the dish reads from above
    n = V((0, 0.55, 1)).normalized()
    p.cyl(c - n * 0.02, 0.45, 0.45, 0.06, "navy", segs=12,
          axis_rot=n.to_track_quat("Z", "Y").to_matrix().to_4x4())
    p.sphere(c + n * (0.38 + DISH_R * 0.6), 0.1, "cyan", segs=8, rings=4)
    return p


def build_glow():
    p = parts.Part("engine_glow", MATS)
    # Built around the bell exit plane at y = 0 (object origin moved to NOZZLE_Y below).
    parts.exhaust_glow(p, BELL_R * 0.85, 1.1, "glow", segs=16)
    return p


def build_ship():
    build_materials()
    root = parts.make_root("explorer")
    objs = [b().finish(root) for b in (build_hull, build_drive, build_dish, build_glow)]
    objs[2].location = DISH_PIVOT
    objs[3].location = (0, NOZZLE_Y, 0)
    parts.add_empty("scan_point", root, (0, SCAN_Y, -0.15), size=1.0)
    return root, objs


# --- Previews ------------------------------------------------------------------------

def _combine(paths, out):
    """Stack PNGs side by side (same height) into one image."""
    imgs = [bpy.data.images.load(pth) for pth in paths]
    h = imgs[0].size[1]
    w = sum(i.size[0] for i in imgs)
    out_img = bpy.data.images.new("combo", w, h, alpha=False)
    px = [0.0] * (w * h * 4)
    x0 = 0
    for im in imgs:
        iw, ih = im.size
        src = list(im.pixels)
        for row in range(min(h, ih)):
            px[(row * w + x0) * 4:(row * w + x0 + iw) * 4] = src[row * iw * 4:(row + 1) * iw * 4]
        x0 += iw
    out_img.pixels = px
    out_img.filepath_raw = out
    out_img.file_format = "PNG"
    out_img.save()
    print("RENDERED", out)


def out_dir_previews(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    scene = bpy.context.scene
    from mathutils import Vector
    cam = scene.camera  # reuse the camera and lights from ship_previews
    cam.location = (-17, 14, 19)
    cam.rotation_euler = (Vector((0, 1.0, 0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.ortho_scale = 24
    scene.render.resolution_x, scene.render.resolution_y = 1000, 900
    a = os.path.join(out_dir, "_q.png")
    common.render(a)
    cam.location = (40, 1.2, 0.5)
    cam.rotation_euler = (math.pi / 2, 0, math.pi / 2)
    cam.data.ortho_scale = 24
    b = os.path.join(out_dir, "_s.png")
    common.render(b)
    _combine([a, b], os.path.join(out_dir, "ship_preview.png"))
    os.remove(a)
    os.remove(b)


def lineup(out_dir):
    """Explorer next to the existing ships (true scale), 3/4 and top-down."""
    common.reset_scene()
    ships = (("merc_fighter", -16.0), ("miner", -8.0), ("salvager", 0.0), ("explorer", 8.0),
             ("scavenger", 15.0))
    for name, x in ships:
        path = os.path.join(common.ROOT, "assets", "models", "ships", name + ".glb")
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        for r in [o for o in set(bpy.data.objects) - before if o.parent is None]:
            r.location.x += x
    common.setup_preview(cam_loc=(-27, 28, 30), cam_target=(1.5, -1.5, 0), ortho_scale=46,
                         res=(1800, 1000), key_dir=(-0.5, 0.4, 0.75), key_energy=3.5)
    common.render(os.path.join(out_dir, "fleet_lineup.png"))
    scene = bpy.context.scene
    cam = scene.camera
    cam.location = (-0.5, 0.8, 60)
    cam.rotation_euler = (0, 0, 0)
    cam.data.ortho_scale = 44
    scene.render.resolution_x, scene.render.resolution_y = 600, 340
    common.render(os.path.join(out_dir, "fleet_lineup_top.png"))


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_ship()
    parts.print_stats(objs)
    parts.save_blend(os.path.join(common.ROOT, "blender", "explorer_ship.blend"))
    common.export_glb(root, OUT)
    if "--no-preview" in argv:
        return
    parts.ship_previews("explorer", 21.0, target=(0, 1.0, 0))
    if "--out-dir" in argv:
        out_dir = argv[argv.index("--out-dir") + 1]
        out_dir_previews(out_dir)
        lineup(out_dir)


main()
