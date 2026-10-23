"""Generate the cargo shuttle .glb and previews (3/4, top-down, and a scale shot next to the miner).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python /Users/hannesalm/code/games/space-majesty/blender/gen_cargo_shuttle.py
  Add `-- --no-preview` to skip the PNG renders.
  Add `-- --scale-png /abs/out.png` to also render a tilted top-down shot beside miner.glb.

Design: short-haul freight shuttle, functional hard sci-fi, ~8.2 m long, 5 m wide. A small
pressurised crew module (domed cylinder, cupola with forward windows, portholes, docking
ring) at the front. Behind it an open box-truss rack on a central spine carries four
standard cargo containers (two per side, 2 along the length). A thrust block at the stern
holds two small engine bells with blue-white glows. RCS quads on the cab and rack corners.
Light grey hull with teal accents. Top-down: a compact rectangle.

Layout (Blender Z up, exported +Y up). Ship centre at origin on the play plane z=0.
The nose points along Blender +Y, which the exporter turns into Godot -Z (forward), same as
miner/salvager. Materials are flat Principled (no atlas), same as the other ship glbs.
Hierarchy: cargo_shuttle (empty root) -> cargo_shuttle_hull, cargo_containers, engine_glow.
cargo_containers is its own node so Godot can hide it when the shuttle flies empty.
engine_glow holds both glows; its origin is on the bell exit plane (Blender y = NOZZLE_Y)
and plumes extend along Godot local +Z, so scaling it on Z lengthens both glows backwards.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
from parts import ALONG_Y, V, rot  # noqa: E402

OUT = os.path.join(common.ROOT, "assets", "models", "ships", "cargo_shuttle.glb")
NOZZLE_Y = -4.3
BELL_R = 0.55
BELL_LEN = 0.95
BELL_X = 1.0
CAB_Y0, CAB_Y1, CAB_R = 1.5, 3.9, 1.1
RACK_Y0, RACK_Y1 = -3.0, 1.5
RACK_HW, RACK_HH = 2.3, 1.1
CONT = (1.9, 1.9, 1.9)   # w, len, h
CONT_X = 1.25
CONT_Y = (0.5, -1.5)

MATS = {}


def build_materials():
    m = common.make_material
    MATS["hull"] = m("shuttle_hull_grey", (0.72, 0.74, 0.75), roughness=0.45, metallic=0.1)
    MATS["hull2"] = m("shuttle_hull_dark_grey", (0.40, 0.42, 0.45), roughness=0.5, metallic=0.2)
    MATS["dark"] = m("shuttle_structure_dark", (0.06, 0.065, 0.07), roughness=0.55, metallic=0.5)
    MATS["teal"] = m("shuttle_accent_teal", (0.05, 0.50, 0.52), roughness=0.45)
    MATS["yellow"] = m("shuttle_accent_yellow", (0.95, 0.62, 0.02), roughness=0.45)
    MATS["window"] = m("shuttle_window_warm", (1.0, 0.85, 0.6), roughness=0.3,
                       emission=(1.0, 0.78, 0.5), emission_strength=2.0)
    MATS["light"] = m("shuttle_light_amber", (1.0, 0.5, 0.1), roughness=0.3,
                      emission=(1.0, 0.45, 0.08), emission_strength=3.0)
    MATS["glow"] = m("shuttle_engine_glow", (0.75, 0.92, 1.0), roughness=0.2,
                     emission=(0.6, 0.88, 1.0), emission_strength=3.5)
    MATS["c_blue"] = m("shuttle_cont_blue", (0.12, 0.25, 0.55), roughness=0.55, metallic=0.2)
    MATS["c_rust"] = m("shuttle_cont_rust", (0.55, 0.20, 0.10), roughness=0.6, metallic=0.2)
    MATS["c_green"] = m("shuttle_cont_green", (0.15, 0.40, 0.22), roughness=0.55, metallic=0.2)
    MATS["c_sand"] = m("shuttle_cont_sand", (0.70, 0.58, 0.32), roughness=0.55, metallic=0.2)
    MATS["rib"] = m("shuttle_cont_rib", (0.30, 0.31, 0.33), roughness=0.5, metallic=0.4)


def build_hull(rng):
    p = parts.Part("cargo_shuttle_hull", MATS)
    # --- Crew module
    def cab_mat(i, j):
        return "hull2" if j in (0, 6) else "hull"
    parts.capsule(p, CAB_Y0, CAB_Y1, CAB_R, cab_mat, segs=16, dome0=0.25, dome1=0.4)
    p.cyl(V((0, 2.4, 0)), CAB_R + 0.04, CAB_R + 0.04, 0.2, "teal", segs=16, axis_rot=ALONG_Y)
    p.box(V((0, 3.0, 0.95)), (1.4, 1.2, 0.6), "hull2", bevel=0.2)
    p.box(V((0, 3.62, 1.0)), (1.05, 0.05, 0.28), "window", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 0.71, 3.15, 1.0)), (0.05, 0.6, 0.24), "window", bevel=0.0)
        for k in range(2):
            q = V((sx * CAB_R * 0.97, 2.7 + k * 0.55, 0.2))
            p.tube(q, q + V((sx * 0.08, 0, 0)), 0.12, 0.12, "window", segs=8)
    p.cyl(V((0, 2.6, -CAB_R - 0.05)), 0.45, 0.45, 0.18, "hull2", segs=12)   # docking ring
    p.cyl(V((-0.4, 2.8, 1.5)), 0.04, 0.03, 0.6, "dark", segs=4)             # antenna
    p.box(V((-0.4, 2.8, 1.85)), (0.14, 0.14, 0.14), "light", bevel=0.0)
    for sx in (-1, 1):
        for sz in (-1, 1):
            n = V((sx, 0, sz)).normalized()
            parts.rcs_quad(p, V((0, 3.3, 0)) + n * (CAB_R + 0.04), n, "hull2", "dark", s=0.22)
    # --- Rack: open truss on a central spine, tie-down clamps, rails
    parts.box_truss(p, RACK_Y0, RACK_Y1, RACK_HW, RACK_HH, 3, "hull2", "dark",
                    chord=0.2, brace=0.1)
    p.beam(V((0, RACK_Y0, 0)), V((0, RACK_Y1, 0)), 0.5, 0.5, "hull2")
    p.beam(V((0, CAB_Y0 + 0.2, 0)), V((0, RACK_Y1, 0)), 0.6, 0.6, "hull2")
    for sx in (-1, 1):
        p.box(V((sx * RACK_HW, (RACK_Y0 + RACK_Y1) / 2, RACK_HH + 0.12)),
              (0.24, RACK_Y1 - RACK_Y0 - 0.6, 0.04), "yellow", bevel=0.0)
        for y in (RACK_Y1 - 0.15, RACK_Y0 + 0.15):
            p.box(V((sx * RACK_HW, y, RACK_HH + 0.18)), (0.2, 0.2, 0.12), "light", bevel=0.0)
        for y in (-0.5, 0.5, -1.5):   # lower cradle arms under each container
            p.beam(V((0, y, -RACK_HH)), V((sx * RACK_HW, y, -RACK_HH)), 0.14, 0.14, "dark")
        for sy in (-1, 1):
            parts.rcs_quad(p, V((sx * (RACK_HW + 0.1), (RACK_Y0 + RACK_Y1) / 2 + sy * 2.0, 0.9)),
                           (sx, 0, 0.4), "hull2", "dark", s=0.22)
    # --- Stern: thrust block, two engine bells, small tank
    p.box(V((0, -3.4, 0)), (3.4, 0.9, 1.6), "hull2", bevel=0.1)
    p.box(V((0, -3.4, 0.81)), (2.0, 0.8, 0.04), "teal", bevel=0.0)
    p.cyl(V((0, -3.0, 0)), 0.5, 0.5, 0.4, "hull", segs=12, axis_rot=ALONG_Y)
    for sx in (-1, 1):
        p.cyl(V((sx * BELL_X, -3.9, 0)), 0.65, 0.6, 0.2, "dark", segs=12, axis_rot=ALONG_Y)
        parts.bell(p, NOZZLE_Y, BELL_R, BELL_LEN, "hull2", "dark", x=sx * BELL_X, segs=14)
        parts.radiator(p, V((sx * 1.72, -3.4, 0.0)), 0.8, 1.2, (sx, 0, 0), "dark", "hull2", ribs=4)
    return p


def container(p, c, mat):
    w, ln, h = CONT
    p.box(c, CONT, mat, bevel=0.04)
    for k in range(5):   # corrugation ribs on the long sides and top
        y = -ln / 2 + ln * (k + 0.5) / 5
        p.box(c + V((0, y, 0)), (w + 0.05, 0.06, h + 0.05), "rib", bevel=0.0)
    for sx in (-1, 1):   # corner castings
        for sy in (-1, 1):
            for sz in (-1, 1):
                p.box(c + V((sx * w / 2, sy * ln / 2, sz * h / 2)), (0.18, 0.18, 0.18),
                      "dark", bevel=0.0)


def build_containers(rng):
    p = parts.Part("cargo_containers", MATS)
    mats = ["c_blue", "c_rust", "c_green", "c_sand"]
    rng.shuffle(mats)
    i = 0
    for sx in (-1, 1):
        for y in CONT_Y:
            container(p, V((sx * CONT_X, y, 0.0)), mats[i])
            i += 1
    return p


def build_glow(rng):
    p = parts.Part("engine_glow", MATS)
    for sx in (-1, 1):
        parts.exhaust_glow(p, BELL_R * 0.85, 0.7, "glow", x=sx * BELL_X, segs=14)
    return p


def build_ship():
    rng = random.Random(7731)
    build_materials()
    root = parts.make_root("cargo_shuttle")
    objs = [b(rng).finish(root) for b in (build_hull, build_containers, build_glow)]
    objs[-1].location = (0, NOZZLE_Y, 0)
    return root, objs


def scale_preview(path):
    import bpy
    sys.path.insert(0, os.path.dirname(__file__))
    miner = os.path.join(common.ROOT, "assets", "models", "ships", "miner.glb")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=miner)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.parent is None:
            o.location.x += 9.0
    common.setup_preview(cam_loc=(-4, -14, 22), cam_target=(4.5, 0, 0), res=(1600, 1000),
                         key_dir=(-0.5, 0.4, 0.75), key_energy=3.5)
    common.render(path)


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_ship()
    parts.print_stats(objs)
    parts.save_blend(os.path.join(common.ROOT, "blender", "cargo_shuttle.blend"))
    common.export_glb(root, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews("cargo_shuttle", 10.0, target=(0, 0, 0))
    if "--scale-png" in argv:
        scale_preview(argv[argv.index("--scale-png") + 1])


main()
