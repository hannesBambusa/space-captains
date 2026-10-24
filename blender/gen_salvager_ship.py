"""Generate the salvager ship .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_salvager_ship.py
  Add `-- --no-preview` to skip the PNG renders.

Design: salvage tug, functional hard sci-fi. A pressurised crew module (cylinder with
domed ends, bridge cupola looking forward, portholes) ends in a heavy tool frame. Two
articulated manipulator arms with three-finger grabbers reach forward from the frame,
and a cutting-torch boom runs down the centre line between them (tip = tool_point at
y = TOOL_Y, matches SalvagerShip nose_offset 7.6). Behind the module an open cargo
cradle holds a strapped-down wreck section, then two crosswise propellant tanks, a
reactor drum with flush radiators, and one engine bell with a short blue-white glow.
Orange hull, hazard yellow tooling. Top-down: a rectangle with two short forward arms.

Layout (Blender Z up, exported +Y up). Ship centre at origin on the play plane z=0.
The nose points along Blender +Y, which the exporter turns into Godot -Z (forward).
Hierarchy: salvager (empty root) -> salvager_hull, salvager_rig, salvager_scrap,
  engine_glow, tool_point (empty).
engine_glow has its origin on the bell exit plane (Blender y = NOZZLE_Y) and its plume
extends along Godot local +Z, so scaling it on Z lengthens the glow backwards.
tool_point is unrotated, so its Godot -Z points forward out of the torch.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
from parts import ALONG_X, ALONG_Y, V, rot  # noqa: E402

OUT = os.path.join(common.ROOT, "assets", "models", "ships", "salvager.glb")
TOOL_Y = 7.6
NOZZLE_Y = -7.4
BELL_R = 1.05
BELL_LEN = 1.4
MOD_Y0, MOD_Y1, MOD_R, MOD_Z = 0.7, 4.0, 1.35, 0.35
FRAME_Y = 4.25
CRADLE_Y0, CRADLE_Y1 = -3.7, 0.6

MATS = {}


def build_materials():
    m = common.make_material
    MATS["rust"] = m("salv_hull_orange", (0.62, 0.24, 0.06), roughness=0.6, metallic=0.25)
    MATS["rust2"] = m("salv_hull_rust", (0.32, 0.13, 0.05), roughness=0.7, metallic=0.35)
    MATS["yellow"] = m("salv_hazard_yellow", (0.95, 0.66, 0.03), roughness=0.5, metallic=0.0)
    MATS["dark"] = m("salv_frame_dark", (0.06, 0.06, 0.065), roughness=0.55, metallic=0.5)
    MATS["steel"] = m("salv_steel_grey", (0.38, 0.39, 0.40), roughness=0.5, metallic=0.4)
    MATS["scrap"] = m("salv_scrap_metal", (0.22, 0.21, 0.2), roughness=0.75, metallic=0.5)
    MATS["scrap_paint"] = m("salv_scrap_paint_teal", (0.08, 0.22, 0.24), roughness=0.7,
                            metallic=0.2)
    MATS["window"] = m("salv_window_warm", (1.0, 0.85, 0.6), roughness=0.3,
                       emission=(1.0, 0.78, 0.5), emission_strength=3.5)
    MATS["light"] = m("salv_light_amber", (1.0, 0.6, 0.1), roughness=0.3,
                      emission=(1.0, 0.55, 0.08), emission_strength=5.0)
    MATS["torch"] = m("salv_torch_glow", (0.7, 0.9, 1.0), roughness=0.2,
                      emission=(0.55, 0.85, 1.0), emission_strength=9.0)
    MATS["glow"] = m("salv_engine_glow", (0.75, 0.92, 1.0), roughness=0.2,
                     emission=(0.6, 0.88, 1.0), emission_strength=5.0)


def build_hull(rng):
    p = parts.Part("salvager_hull", MATS)
    # --- Crew module: orange pressure cylinder, steel end caps, yellow band
    parts.capsule(p, MOD_Y0, MOD_Y1, MOD_R, lambda i, j: "steel" if j in (0, 6) else "rust",
                  segs=16, z=MOD_Z, dome0=0.3, dome1=0.25)
    p.cyl(V((0, 1.6, MOD_Z)), MOD_R + 0.04, MOD_R + 0.04, 0.3, "yellow", segs=16,
          axis_rot=ALONG_Y)
    # Bridge cupola, forward windows looking down over the tools
    p.box(V((0, 3.2, MOD_Z + 1.35)), (1.6, 1.4, 0.7), "steel", bevel=0.2)
    p.box(V((0, 3.92, MOD_Z + 1.38)), (1.2, 0.05, 0.34), "window", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 0.81, 3.4, MOD_Z + 1.4)), (0.05, 0.7, 0.28), "window", bevel=0.0)
        for k in range(2):
            q = V((sx * MOD_R * 0.97, 1.3 + k * 0.6 + 0.6, MOD_Z + 0.3))
            p.tube(q, q + V((sx * 0.08, 0, 0)), 0.14, 0.14, "window", segs=8)
    p.cyl(V((-0.5, 2.6, MOD_Z + 1.9)), 0.05, 0.04, 0.9, "dark", segs=4)
    p.box(V((-0.5, 2.6, MOD_Z + 2.4)), (0.18, 0.18, 0.18), "light", bevel=0.0)
    parts.dish(p, V((0.5, 1.5, MOD_Z + 1.4)), 0.4, (0, -0.3, 1), "steel", "dark", depth=0.18)
    # Docking ring on top, aft of the cupola
    p.cyl(V((0, 1.4, MOD_Z + MOD_R)), 0.5, 0.5, 0.2, "steel", segs=12)
    for sx in (-1, 1):
        for sz in (-1, 1):
            n = V((sx, 0, sz)).normalized()
            parts.rcs_quad(p, V((0, 1.2, MOD_Z)) + n * (MOD_R + 0.05), n, "steel", "dark", s=0.26)
    # --- Spine from the module back through the cradle to the engine
    p.beam(V((0, MOD_Y0 + 0.2, -0.75)), V((0, -5.3, -0.75)), 0.7, 0.55, "rust2")
    p.beam(V((0, MOD_Y0 + 0.2, 0.0)), V((0, CRADLE_Y1, 0.0)), 0.6, 0.6, "rust2")
    # --- Propellant: two crosswise tanks with domed ends, strapped to the spine
    for z in (-0.65, 0.65):
        c = V((0, -4.45, z))
        p.cyl(c, 0.6, 0.6, 2.8, "steel", segs=12, axis_rot=ALONG_X)
        for sx in (-1, 1):
            p.sphere(c + V((sx * 1.4, 0, 0)), 0.6, "steel", segs=12, rings=6,
                     scale=(0.5, 1.0, 1.0))
            p.cyl(c + V((sx * 0.8, 0, 0)), 0.63, 0.63, 0.15, "yellow", segs=12, axis_rot=ALONG_X)
    p.box(V((0, -4.45, 0)), (0.6, 1.4, 2.6), "rust2", bevel=0.05)
    # --- Reactor drum, radiators, bell
    p.cyl(V((0, -5.7, 0)), 1.05, 1.05, 0.9, "rust", segs=12, axis_rot=ALONG_Y)
    p.cyl(V((0, -5.7, 0)), 1.08, 1.08, 0.2, "yellow", segs=12, axis_rot=ALONG_Y)
    for sx in (-1, 1):
        parts.radiator(p, V((sx * 1.05, -5.7, 0)), 0.8, 1.1, (sx, 0, 0), "dark", "steel", ribs=4)
        parts.rcs_quad(p, V((sx * 0.75, -5.8, 0.85)), (sx, 0, 1), "steel", "dark", s=0.22)
    p.cyl(V((0, -6.2, 0)), 0.8, 0.6, 0.2, "dark", segs=12, axis_rot=ALONG_Y)
    parts.bell(p, NOZZLE_Y, BELL_R, BELL_LEN, "steel", "dark", segs=16)
    for sx in (-1, 1):
        p.box(V((sx * 1.6, -4.45, 1.2)), (0.16, 0.16, 0.16), "light", bevel=0.0)
    return p


def grabber(p, wrist, sx):
    """Three-finger grabber at the wrist, pointing forward (+Y)."""
    p.cyl(wrist, 0.32, 0.32, 0.4, "dark", segs=10, axis_rot=ALONG_Y)
    p.cyl(wrist + V((0, 0.3, 0)), 0.38, 0.3, 0.25, "steel", segs=10, axis_rot=ALONG_Y)
    for k in range(3):
        a = k * 2 * math.pi / 3 + math.pi / 2
        d = V((math.cos(a), 0, math.sin(a)))
        b = wrist + V((0, 0.45, 0)) + d * 0.22
        mid = b + V((0, 0.4, 0)) + d * 0.22
        tip = mid + V((0, 0.35, 0)) - d * 0.18
        p.beam(b, mid, 0.13, 0.13, "yellow")
        p.beam(mid, tip, 0.11, 0.11, "dark")


def build_rig(rng):
    p = parts.Part("salvager_rig", MATS)
    # Tool frame bolted to the module front
    p.box(V((0, FRAME_Y, 0.0)), (3.4, 0.5, 1.5), "rust2", bevel=0.08)
    p.hazard(-1.6, 1.6, 0.3, -0.02, 0.02,
             matrix=parts.Matrix.Translation((0, FRAME_Y + 0.26, -0.45)) @ rot(rx=math.pi / 2),
             pitch=0.35)
    for sx in (-1, 1):
        x = sx * 1.35
        sh = V((x, FRAME_Y + 0.35, 0.1))
        elbow = V((sx * 1.75, 5.6, 0.35))
        wrist = V((sx * 1.15, 6.55, 0.05))
        # Shoulder yoke, upper arm, elbow drum, forearm
        p.cyl(sh, 0.4, 0.4, 0.9, "dark", segs=10, axis_rot=ALONG_X)
        p.beam(sh, elbow, 0.42, 0.5, "yellow")
        p.cyl(elbow, 0.3, 0.3, 0.65, "dark", segs=10, axis_rot=ALONG_X)
        p.beam(elbow, wrist, 0.34, 0.4, "yellow")
        # Hydraulic ram on the upper arm
        p.beam(sh + V((0, 0.1, 0.4)), elbow.lerp(sh, 0.3) + V((0, 0, 0.35)), 0.1, 0.1, "steel")
        grabber(p, wrist, sx)
        p.box(V((sx * 1.6, FRAME_Y + 0.27, 0.6)), (0.3, 0.06, 0.2), "light", bevel=0.0)
    # Cutting-torch boom on the centre line, under the frame
    p.box(V((0, FRAME_Y + 0.45, -0.35)), (0.6, 0.5, 0.6), "dark", bevel=0.05)
    p.beam(V((0, FRAME_Y + 0.6, -0.35)), V((0, 6.6, -0.1)), 0.32, 0.32, "steel")
    p.cyl(V((0, 6.55, -0.1)), 0.22, 0.22, 0.35, "dark", segs=8, axis_rot=parts.ALONG_X)
    p.beam(V((0, 6.55, -0.1)), V((0, 7.05, 0.0)), 0.26, 0.26, "steel")
    p.tube(V((0, 7.0, 0.0)), V((0, 7.45, 0.0)), 0.22, 0.1, "dark", segs=10)
    p.sphere(V((0, TOOL_Y - 0.1, 0.0)), 0.12, "torch", segs=8, rings=4)
    # Gas lines from the frame to the torch
    p.beam(V((0.22, FRAME_Y + 0.5, -0.1)), V((0.15, 6.9, 0.08)), 0.06, 0.06, "yellow")
    # --- Cargo cradle behind the module: cross beams and U ribs
    for y in (CRADLE_Y0 + 0.2, (CRADLE_Y0 + CRADLE_Y1) / 2, CRADLE_Y1 - 0.2):
        p.beam(V((-1.8, y, -0.75)), V((1.8, y, -0.75)), 0.3, 0.3, "rust2")
        for sx in (-1, 1):
            p.beam(V((sx * 1.8, y, -0.75)), V((sx * 1.8, y, 1.1)), 0.26, 0.26, "rust2")
            p.box(V((sx * 1.8, y, 1.2)), (0.32, 0.32, 0.2), "yellow", bevel=0.0)
    for sx in (-1, 1):
        p.beam(V((sx * 1.8, CRADLE_Y0, 1.1)), V((sx * 1.8, CRADLE_Y1, 1.1)), 0.2, 0.2, "rust")
        p.beam(V((sx * 1.8, CRADLE_Y0, -0.75)), V((sx * 1.8, CRADLE_Y1, -0.75)), 0.22, 0.22, "rust")
    return p


def build_scrap(rng):
    """Wreck section strapped into the cradle: torn hull drum, girder stubs, tie-down straps."""
    p = parts.Part("salvager_scrap", MATS)
    c = V((0.0, (CRADLE_Y0 + CRADLE_Y1) / 2, 0.25))
    p.cyl(c, 1.35, 1.35, 3.6, "scrap_paint", segs=8, axis_rot=ALONG_Y @ rot(rz=0.2))
    p.cyl(c + V((0, 1.85, 0)), 1.15, 1.15, 0.15, "scrap", segs=8, axis_rot=ALONG_Y)
    p.cyl(c + V((0, -1.85, 0)), 1.1, 1.0, 0.2, "scrap", segs=8, axis_rot=ALONG_Y)
    for k in range(3):
        a = c + V((rng.uniform(-0.6, 0.6), rng.uniform(-1.2, 1.2), 1.1))
        p.box(a, (rng.uniform(0.6, 1.0), rng.uniform(0.5, 0.8), 0.1), "scrap",
              r=rot(rx=rng.uniform(-0.3, 0.3), ry=rng.uniform(-0.3, 0.3)), bevel=0.0)
    p.beam(c + V((0.5, 1.6, 0.6)), c + V((0.8, 2.5, 0.9)), 0.16, 0.16, "scrap")
    for y in (-1.0, 1.0):  # yellow tie-down straps over the wreck
        p.beam(c + V((-1.8, y, 0.85)), c + V((1.8, y, 0.85)), 0.1, 0.12, "yellow")
    p.box(c + V((-0.6, 1.8, 0.7)), (0.5, 0.06, 0.3), "light", bevel=0.0)  # hot cut edge
    return p


def build_glow(rng):
    p = parts.Part("engine_glow", MATS)
    # Built around the bell exit plane at y = 0 (object origin moved to NOZZLE_Y below).
    parts.exhaust_glow(p, BELL_R * 0.85, 0.95, "glow", segs=16)
    return p


def build_ship():
    rng = random.Random(4417)
    build_materials()
    root = parts.make_root("salvager")
    objs = [b(rng).finish(root) for b in (build_hull, build_rig, build_scrap, build_glow)]
    objs[-1].location = (0, NOZZLE_Y, 0)
    parts.add_empty("tool_point", root, (0, TOOL_Y, 0), size=1.0)
    return root, objs


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_ship()
    parts.print_stats(objs)
    parts.save_blend(os.path.join(common.ROOT, "blender", "salvager.blend"))
    common.export_glb(root, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews("salvager", 17.0, target=(0, 0.1, 0))


main()
