"""Generate the miner ship .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_miner_ship.py
  Add `-- --no-preview` to skip the PNG renders.

Design: belter mining tug, functional hard sci-fi. A pressurised crew cab (cylinder
with domed ends, bridge cupola with forward windows, side portholes, docking ring) at
the front carries a rotary core-drill head on the centre line (tip at y = DRILL_Y,
matches MinerShip.nose_offset 7.6). Behind it an open box truss holds an ore hopper
and four ore containers, then two spherical propellant tanks, a reactor drum with
flush radiators, and one engine bell with a short blue-white glow at the stern.
White/grey with orange and yellow work markings. Top-down: a compact rectangle.

Layout (Blender Z up, exported +Y up). Ship centre at origin on the play plane z=0.
The nose points along Blender +Y, which the exporter turns into Godot -Z (forward).
Hierarchy: miner (empty root) -> miner_hull, miner_hold, engine_glow, drill_point.
engine_glow has its origin on the bell exit plane (Blender y = NOZZLE_Y) and its plume
extends along Godot local +Z, so scaling it on Z lengthens the glow backwards.
drill_point (empty, unrotated) marks the drill tip; Godot uses nose_offset.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
from parts import ALONG_Y, V, rot  # noqa: E402

OUT = os.path.join(common.ROOT, "assets", "models", "ships", "miner.glb")
DRILL_Y = 7.6
NOZZLE_Y = -6.7
BELL_R = 1.0
BELL_LEN = 1.3
CAB_Y0, CAB_Y1, CAB_R = 2.9, 6.0, 1.45
TRUSS_Y0, TRUSS_Y1 = -3.7, 2.9
TRUSS_HW, TRUSS_HH = 2.0, 1.25

MATS = {}


def build_materials():
    m = common.make_material
    MATS["hull"] = m("miner_hull_white", (0.78, 0.78, 0.76), roughness=0.45, metallic=0.1)
    MATS["hull2"] = m("miner_hull_grey", (0.50, 0.52, 0.55), roughness=0.5, metallic=0.15)
    MATS["dark"] = m("miner_structure_dark", (0.06, 0.065, 0.07), roughness=0.55, metallic=0.5)
    MATS["orange"] = m("miner_accent_orange", (0.85, 0.28, 0.03), roughness=0.45, metallic=0.0)
    MATS["yellow"] = m("miner_accent_yellow", (0.95, 0.62, 0.02), roughness=0.45, metallic=0.0)
    MATS["window"] = m("miner_window_warm", (1.0, 0.85, 0.6), roughness=0.3,
                       emission=(1.0, 0.78, 0.5), emission_strength=3.5)
    MATS["light"] = m("miner_light_orange", (1.0, 0.45, 0.1), roughness=0.3,
                      emission=(1.0, 0.42, 0.08), emission_strength=5.0)
    MATS["work"] = m("miner_work_light", (1.0, 0.95, 0.85), roughness=0.3,
                     emission=(1.0, 0.95, 0.85), emission_strength=6.0)
    MATS["ore"] = m("miner_ore_rock", (0.30, 0.25, 0.21), roughness=0.9, metallic=0.0)
    MATS["ore_hi"] = m("miner_ore_vein", (0.75, 0.5, 0.2), roughness=0.4, metallic=0.6)
    MATS["glow"] = m("miner_engine_glow", (0.75, 0.92, 1.0), roughness=0.2,
                     emission=(0.6, 0.88, 1.0), emission_strength=5.0)


def build_hull(rng):
    p = parts.Part("miner_hull", MATS)
    # --- Crew cab: pressure cylinder with an orange band, flat-ish front dome
    def cab_mat(i, j):
        return "hull2" if j in (0, 6) else "hull"
    parts.capsule(p, CAB_Y0, CAB_Y1, CAB_R, cab_mat, segs=16, dome0=0.25, dome1=0.3)
    p.cyl(V((0, 4.05, 0)), CAB_R + 0.04, CAB_R + 0.04, 0.25, "orange", segs=16, axis_rot=ALONG_Y)
    # Bridge cupola on the roof, windows facing forward and to the sides
    p.box(V((0, 4.9, 1.45)), (1.7, 1.5, 0.75), "hull2", bevel=0.2)
    p.box(V((0, 5.66, 1.5)), (1.3, 0.05, 0.36), "window", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 0.86, 5.1, 1.5)), (0.05, 0.8, 0.3), "window", bevel=0.0)
        for k in range(3):  # side portholes
            q = V((sx * CAB_R * 0.97, 3.5 + k * 0.6, 0.35))
            p.tube(q, q + V((sx * 0.08, 0, 0)), 0.14, 0.14, "window", segs=8)
    # Docking ring on the cab belly, antenna and beacon on the cupola
    p.cyl(V((0, 3.6, -CAB_R - 0.05)), 0.55, 0.55, 0.2, "hull2", segs=12)
    p.cyl(V((-0.55, 4.6, 2.2)), 0.05, 0.04, 0.8, "dark", segs=4)
    p.box(V((-0.55, 4.6, 2.65)), (0.18, 0.18, 0.18), "light", bevel=0.0)
    parts.dish(p, V((0.55, 4.5, 1.85)), 0.38, (0, 0.6, 1), "hull", "dark", depth=0.18)
    # RCS quads on the cab shoulders
    for sx in (-1, 1):
        for sz in (-1, 1):
            n = V((sx, 0, sz)).normalized()
            parts.rcs_quad(p, V((0, 5.2, 0)) + n * (CAB_R + 0.05), n, "hull2", "dark", s=0.26)
    # --- Drill: mount ring on the cab front, motor drum, rotary cutter head, core bit
    p.cyl(V((0, 6.05, 0)), 1.05, 1.05, 0.3, "dark", segs=14, axis_rot=ALONG_Y)
    p.cyl(V((0, 6.45, 0)), 0.85, 0.85, 0.55, "yellow", segs=14, axis_rot=ALONG_Y)
    p.hazard(-0.85, 0.85, 0.22, -0.02, 0.02,
             matrix=parts.Matrix.Translation((0, 6.06, -1.15)) @ rot(rx=math.pi / 2), pitch=0.3)
    p.cyl(V((0, 6.88, 0)), 0.95, 0.95, 0.3, "hull2", segs=14, axis_rot=ALONG_Y)
    for k in range(8):  # cutter teeth around the head rim
        a = k * math.pi / 4 + 0.2
        p.box(V((0.82 * math.cos(a), 7.12, 0.82 * math.sin(a))), (0.22, 0.25, 0.22), "dark",
              r=rot(ry=-a), bevel=0.0)
    p.cyl(V((0, 7.3, 0)), 0.45, 0.12, 0.5, "dark", segs=10, axis_rot=ALONG_Y)
    p.cyl(V((0, DRILL_Y - 0.04, 0)), 0.12, 0.12, 0.08, "light", segs=6, axis_rot=ALONG_Y)
    for sx in (-1, 1):  # work lights flanking the drill
        p.box(V((sx * 1.1, 6.0, 0.95)), (0.35, 0.2, 0.25), "dark", bevel=0.0)
        p.box(V((sx * 1.1, 6.11, 0.95)), (0.27, 0.04, 0.17), "work", bevel=0.0)
    # --- Open box truss between the cab and the tank section
    parts.box_truss(p, TRUSS_Y0, TRUSS_Y1, TRUSS_HW, TRUSS_HH, 3, "hull2", "dark",
                    chord=0.24, brace=0.11)
    p.beam(V((0, TRUSS_Y0, 0)), V((0, TRUSS_Y1, 0)), 0.5, 0.5, "hull2")  # central spine
    for sx in (-1, 1):  # yellow marker rails on the top longerons
        p.box(V((sx * TRUSS_HW, (TRUSS_Y0 + TRUSS_Y1) / 2, TRUSS_HH + 0.13)),
              (0.26, TRUSS_Y1 - TRUSS_Y0 - 0.6, 0.04), "yellow", bevel=0.0)
        for y in (TRUSS_Y1 - 0.15, TRUSS_Y0 + 0.15):
            p.box(V((sx * TRUSS_HW, y, TRUSS_HH + 0.2)), (0.22, 0.22, 0.14), "light", bevel=0.0)
    # --- Propellant tanks: two spheres on a cross frame
    for sx in (-1, 1):
        c = V((sx * 1.2, -4.65, 0.0))
        p.sphere(c, 1.1, "hull", segs=14, rings=7)
        p.torus(c, 1.11, 0.07, "orange", segs=16, minor_segs=4)
        p.beam(c + V((0, 0.9, -0.6)), V((sx * 1.6, TRUSS_Y0, -TRUSS_HH)), 0.15, 0.15, "dark")
        p.beam(c + V((0, 0.9, 0.6)), V((sx * 1.6, TRUSS_Y0, TRUSS_HH)), 0.15, 0.15, "dark")
    p.beam(V((0, TRUSS_Y0, 0)), V((0, -5.3, 0)), 0.6, 0.6, "hull2")
    # --- Reactor drum with flush radiator panels, thrust plate and bell
    p.cyl(V((0, -5.55, 0)), 1.0, 1.0, 0.9, "hull2", segs=12, axis_rot=ALONG_Y)
    for sx in (-1, 1):
        parts.radiator(p, V((sx * 1.0, -5.55, 0)), 0.8, 1.1, (sx, 0, 0), "dark", "hull2", ribs=4)
        parts.rcs_quad(p, V((sx * 0.7, -5.6, 0.85)), (sx, 0, 1), "hull2", "dark", s=0.22)
    p.box(V((0, -5.55, 1.02)), (0.7, 0.7, 0.06), "yellow", bevel=0.0)
    p.cyl(V((0, -6.05, 0)), 0.75, 0.55, 0.2, "dark", segs=12, axis_rot=ALONG_Y)
    parts.bell(p, NOZZLE_Y, BELL_R, BELL_LEN, "hull2", "dark", segs=16)
    p.box(V((-1.2, -5.6, 1.0)), (0.16, 0.16, 0.16), "light", bevel=0.0)
    return p


def container(p, c, size, mat, stripe):
    """Ribbed ore container with a coloured end band."""
    w, ln, h = size
    p.box(c, size, mat, bevel=0.06)
    for k in range(4):
        y = -ln / 2 + ln * (k + 0.5) / 4
        p.box(c + V((0, y, 0)), (w + 0.06, 0.08, h + 0.06), "hull2", bevel=0.0)
    p.box(c + V((0, ln / 2 - 0.2, 0)), (w + 0.04, 0.22, h + 0.04), stripe, bevel=0.0)


def build_hold(rng):
    p = parts.Part("miner_hold", MATS)
    # Front bay: open ore hopper with a yellow rim, heaped with rocks
    y0, y1 = 0.85, 2.75
    w = 3.6
    p.box(V((0, (y0 + y1) / 2, -0.9)), (w, y1 - y0, 0.15), "dark", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * (w / 2 - 0.08), (y0 + y1) / 2, 0.0)), (0.15, y1 - y0, 1.8), "hull", bevel=0.0)
    for y in (y0, y1):
        p.box(V((0, y, 0.0)), (w, 0.15, 1.8), "hull", bevel=0.0)
        p.hazard(-w / 2, w / 2, 0.16, 0.9, 0.96, matrix=parts.Matrix.Translation((0, y, 0)),
                 pitch=0.45)
    for i in range(9):
        x = rng.uniform(-1.2, 1.2)
        y = rng.uniform(y0 + 0.5, y1 - 0.5)
        p.rock(V((x, y, rng.uniform(0.1, 0.5))), rng.uniform(0.45, 0.7),
               "ore_hi" if i % 4 == 0 else "ore", rng)
    # Rear bays: four ore containers clamped either side of the spine
    for sx in (-1, 1):
        for yc, stripe in ((-0.35, "orange"), (-2.55, "yellow")):
            container(p, V((sx * 1.0, yc, 0.0)), (1.45, 1.9, 2.2), "hull", stripe)
    return p


def build_glow(rng):
    p = parts.Part("engine_glow", MATS)
    # Built around the bell exit plane at y = 0 (object origin moved to NOZZLE_Y below).
    parts.exhaust_glow(p, BELL_R * 0.85, 0.9, "glow", segs=16)
    return p


def build_ship():
    rng = random.Random(9902)
    build_materials()
    root = parts.make_root("miner")
    objs = [b(rng).finish(root) for b in (build_hull, build_hold, build_glow)]
    objs[-1].location = (0, NOZZLE_Y, 0)
    parts.add_empty("drill_point", root, (0, DRILL_Y, 0), size=1.0)
    return root, objs


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_ship()
    parts.print_stats(objs)
    parts.save_blend(os.path.join(common.ROOT, "blender", "miner.blend"))
    common.export_glb(root, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews("miner", 16.0, target=(0, 0.3, 0))


main()
