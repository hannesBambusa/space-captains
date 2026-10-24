"""Generate the syndicate gunship .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_syndicate_ship.py
  Add `-- --no-preview` to skip the PNG renders.

Design: organised, heavy, military-industrial. A blocky gunmetal brick with a wedge
prow, layered armour plates, two armoured side sponsons with hazard-yellow chevrons,
a raised bridge with amber vision slits at the rear, a square engine block with four
bells and amber-white glows, and a big twin-barrel turret on the forward deck
(muzzle_l / muzzle_r at the barrel tips). About 19.5 m long and 7 m wide, so about
1.4x the scavenger. From above: a wide rectangle with a round turret on the nose.

Layout (Blender Z up, exported +Y up). Ship centre at origin on the play plane z=0.
The nose points along Blender +Y, which the exporter turns into Godot -Z (forward).
Hierarchy: syndicate_gunship (empty root) -> syn_hull, syn_turret, engine_glow,
  muzzle_l (empty), muzzle_r (empty).
syn_turret has its origin on the turret ring axis (TURRET), unrotated, so Godot could
yaw it about local Y (the muzzle empties are children of the root, as in scavenger.glb,
so they do not follow a yaw).
engine_glow has its origin on the bell exit plane (Blender y = NOZZLE_Y, x = 0) and its
four plumes extend along Godot local +Z, so scaling it on Z lengthens the glow backwards.
Muzzle empties are unrotated, so their Godot -Z points forward along the barrels.
Same node contract as scavenger.glb (gen_scavenger_ship.py).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
from parts import ALONG_Y, SIDE, V, rot  # noqa: E402

OUT = os.path.join(common.ROOT, "assets", "models", "ships", "syndicate_gunship.glb")
NOZZLE_Y = -10.0
BELL_R = 0.72
BELL_LEN = 1.0
ENG = [(-1.0, -0.55), (1.0, -0.55), (-1.0, 0.75), (1.0, 0.75)]   # (x, z) of the four bells
TURRET = V((0.0, 3.6, 1.55))        # turret ring centre on the deck
BARREL_DX = 0.48
BARREL_Z = 0.95                     # barrel height above the ring
MUZZLE_Y = 9.6

MATS = {}


def build_materials():
    m = common.make_material
    MATS["gun"] = m("syn_hull_gunmetal", (0.14, 0.15, 0.16), roughness=0.5, metallic=0.75)
    MATS["armour"] = m("syn_armour_dark", (0.075, 0.08, 0.085), roughness=0.55, metallic=0.7)
    MATS["dark"] = m("syn_frame_dark", (0.03, 0.03, 0.032), roughness=0.6, metallic=0.6)
    MATS["yellow"] = m("syn_hazard_yellow", (0.6, 0.42, 0.02), roughness=0.55, metallic=0.2)
    MATS["metal"] = m("syn_bare_metal", (0.22, 0.22, 0.22), roughness=0.35, metallic=0.9)
    MATS["window"] = m("syn_window_amber", (1.0, 0.65, 0.2), roughness=0.3,
                       emission=(1.0, 0.55, 0.12), emission_strength=3.5)
    MATS["light"] = m("syn_light_amber", (1.0, 0.6, 0.1), roughness=0.3,
                      emission=(1.0, 0.5, 0.05), emission_strength=5.0)
    MATS["glow"] = m("syn_engine_glow", (1.0, 0.85, 0.55), roughness=0.2,
                     emission=(1.0, 0.72, 0.35), emission_strength=5.5)


def side_slab(p, pts, x0, x1, mat):
    """Side-profile polygon (world y, world z) extruded across world x0..x1."""
    p.slab(pts, x0, x1, mat, matrix=SIDE)


def build_hull(rng):
    p = parts.Part("syn_hull", MATS)
    # --- Main hull: wedge prow brick, side profile (y, z)
    side_slab(p, [(-8.4, -1.5), (6.2, -1.5), (9.2, -0.5), (9.2, 0.35), (6.6, 1.3), (-8.4, 1.3)],
              -2.2, 2.2, "gun")
    # Chamfered upper deck plate (narrower, sits on top)
    side_slab(p, [(-7.6, 1.25), (5.8, 1.25), (5.4, 1.6), (-7.2, 1.6)], -1.9, 1.9, "armour")
    # Armour belt plates along the hull sides, gaps between them read as seams
    for sx in (-1, 1):
        for k in range(4):
            y0 = -7.6 + k * 3.4
            p.box(V((sx * 2.3, y0 + 1.55, 0.1)), (0.25, 3.1, 2.0), "armour", bevel=0.06)
    # --- Side sponsons: armoured gun/fuel pods with hazard chevrons
    for sx in (-1, 1):
        c = V((sx * 3.15, -1.6, -0.25))
        p.box(c, (1.7, 9.0, 1.9), "gun", bevel=0.08)
        p.box(c + V((sx * 0.1, 4.75, -0.1)), (1.5, 0.6, 1.5), "armour", bevel=0.1)
        p.box(c + V((0, 0, 1.0)), (1.5, 8.4, 0.12), "armour", bevel=0.0)
        m = parts.Matrix.Translation((c.x, c.y + 5.08, c.z - 0.1)) @ parts.FRONT
        p.hazard(-0.7, 0.7, 1.1, -0.02, 0.04, matrix=m, pitch=0.45, cols=("yellow", "dark"))
        m = parts.Matrix.Translation((c.x, c.y + 2.6, c.z + 1.07))
        p.hazard(-0.75, 0.75, 1.0, 0.0, 0.05, matrix=m, pitch=0.5, cols=("yellow", "dark"))
        for k in range(3):  # struts tying the pod to the hull
            p.box(V((sx * 2.45, -4.6 + k * 3.0, -0.3)), (0.6, 0.8, 0.9), "dark", bevel=0.0)
        p.box(c + V((sx * 0.86, 3.8, 0.4)), (0.06, 0.4, 0.2), "light", bevel=0.0)
        p.box(c + V((sx * 0.86, -4.2, 0.4)), (0.06, 0.4, 0.2), "light", bevel=0.0)
    # --- Hazard band across the prow deck and the stern deck
    p.hazard(-2.1, 2.1, 0.9, 0.0, 0.05, matrix=parts.Matrix.Translation((0, 7.6, 0.95))
             @ rot(rx=-0.33), pitch=0.6, cols=("yellow", "dark"))
    p.hazard(-1.8, 1.8, 0.7, 0.0, 0.05, matrix=parts.Matrix.Translation((0, -6.9, 1.6)),
             pitch=0.6, cols=("yellow", "dark"))
    # --- Bridge tower at the rear: stepped block, amber slits
    b = V((0, -4.4, 2.25))
    p.box(b, (2.6, 3.2, 1.3), "armour", bevel=0.08)
    p.box(b + V((0, 0.3, 0.95)), (1.8, 2.0, 0.7), "gun", bevel=0.1)
    p.box(b + V((0, 1.63, 0.15)), (2.0, 0.05, 0.22), "window", bevel=0.0)
    p.box(b + V((0, 1.33, 1.0)), (1.3, 0.05, 0.16), "window", bevel=0.0)
    for sx in (-1, 1):
        p.box(b + V((sx * 1.31, 0.3, 0.15)), (0.05, 1.6, 0.16), "window", bevel=0.0)
    p.cyl(b + V((0.6, -0.6, 2.1)), 0.06, 0.04, 1.6, "dark", segs=4)
    p.box(b + V((0.6, -0.6, 2.95)), (0.2, 0.2, 0.2), "light", bevel=0.0)
    parts.dish(p, b + V((-0.65, -0.7, 1.4)), 0.45, (0, -0.4, 1), "metal", "dark", depth=0.15,
               segs=10)
    # --- Engine block: square housing, four bells in a frame
    p.box(V((0, -8.9, 0.1)), (4.4, 1.4, 3.0), "armour", bevel=0.05)
    for x, z in ENG:
        p.box(V((x, -9.55, z)), (1.7, 0.2, 1.2), "dark", bevel=0.0)
        parts.bell(p, NOZZLE_Y, BELL_R, BELL_LEN, "metal", "dark", x=x, z=z, segs=14,
                   throat=0.55)
    m = parts.Matrix.Translation((0, -9.62, -1.3)) @ parts.FRONT
    p.hazard(-2.2, 2.2, 0.35, 0.0, 0.04, matrix=m, pitch=0.5, cols=("yellow", "dark"))
    # Heat-sink fins on the engine block
    for sx in (-1, 1):
        for k in range(3):
            p.box(V((sx * 2.35, -8.4 - k * 0.45, 0.4)), (0.6, 0.12, 1.8), "dark", bevel=0.0)
    # --- Prow details: sensor block, ram plate, lights
    p.box(V((0, 8.6, -0.6)), (3.4, 1.0, 0.7), "armour", bevel=0.1)
    p.box(V((0, 9.25, 0.0)), (1.0, 0.05, 0.25), "window", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 1.9, 8.2, 0.0)), (0.25, 0.25, 0.25), "light", bevel=0.0)
    for k in range(5):  # deck hatches
        p.box(V((-1.2 + (k % 2) * 2.4, -1.4 - k * 0.9, 1.62)), (0.7, 0.6, 0.05), "dark",
              bevel=0.0)
    parts.rcs_quad(p, V((2.25, 6.2, 0.9)), (1, 0, 0), "armour", "dark", s=0.3)
    parts.rcs_quad(p, V((-2.25, 6.2, 0.9)), (-1, 0, 0), "armour", "dark", s=0.3)
    # Turret barbette (fixed armoured ring the turret sits on)
    p.cyl(V((TURRET.x, TURRET.y, TURRET.z - 0.05)), 1.85, 1.95, 0.3, "armour", segs=16)
    return p


def build_turret(rng):
    """Twin heavy cannon turret, built around its ring centre (object origin = TURRET)."""
    p = parts.Part("syn_turret", MATS)
    p.cyl(V((0, 0, 0.18)), 1.6, 1.6, 0.36, "dark", segs=16)
    # Turret house: sloped front, flat back, side profile (y, z) across x
    p.slab([(-1.6, 0.3), (1.0, 0.3), (1.75, 0.75), (1.4, 1.45), (-1.4, 1.45), (-1.7, 1.1)],
           -1.35, 1.35, "gun", matrix=SIDE)
    p.box(V((0, -0.1, 1.5)), (2.2, 2.2, 0.14), "armour", bevel=0.0)
    p.hazard(-1.3, 1.3, 0.4, 0.0, 0.04, matrix=parts.Matrix.Translation((0, -0.25, 1.58)),
             pitch=0.45, cols=("yellow", "dark"))
    p.box(V((0, -1.71, 0.75)), (2.2, 0.06, 0.5), "dark", bevel=0.0)
    p.box(V((0.75, 0.9, 1.5)), (0.5, 0.4, 0.25), "armour", bevel=0.1)   # sight block
    p.box(V((0.75, 1.11, 1.5)), (0.36, 0.04, 0.1), "window", bevel=0.0)
    for sx in (-1, 1):
        x = sx * BARREL_DX
        p.cyl(V((x, 1.75, BARREL_Z)), 0.34, 0.34, 0.5, "armour", segs=10, axis_rot=ALONG_Y)
        y0 = 2.0
        y1 = MUZZLE_Y - TURRET.y
        p.cyl(V((x, (y0 + y1) / 2, BARREL_Z)), 0.18, 0.15, y1 - y0, "gun", segs=10,
              axis_rot=ALONG_Y)
        p.cyl(V((x, 2.6, BARREL_Z)), 0.24, 0.24, 1.0, "dark", segs=10, axis_rot=ALONG_Y)
        p.cyl(V((x, y1 - 0.3, BARREL_Z)), 0.23, 0.23, 0.6, "dark", segs=8, axis_rot=ALONG_Y)
        p.cyl(V((x, 3.7, BARREL_Z)), 0.2, 0.2, 0.25, "yellow", segs=10, axis_rot=ALONG_Y)
    return p


def build_glow(rng):
    p = parts.Part("engine_glow", MATS)
    # Built around the bell exit plane at y = 0; the object origin is moved to NOZZLE_Y.
    for x, z in ENG:
        parts.exhaust_glow(p, BELL_R * 0.85, 1.2, "glow", x=x, z=z, segs=14)
    return p


def build_ship():
    rng = random.Random(9902)
    build_materials()
    root = parts.make_root("syndicate_gunship")
    objs = [b(rng).finish(root) for b in (build_hull, build_turret, build_glow)]
    objs[1].location = TURRET
    objs[2].location = (0, NOZZLE_Y, 0)
    for name, sx in (("muzzle_l", -1), ("muzzle_r", 1)):
        parts.add_empty(name, root, (TURRET.x + sx * BARREL_DX, MUZZLE_Y + 0.03,
                                     TURRET.z + BARREL_Z))
    return root, objs


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_ship()
    parts.print_stats(objs)
    parts.save_blend(os.path.join(common.ROOT, "blender", "syndicate_gunship.blend"))
    common.export_glb(root, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews("syndicate_gunship", 22.0, target=(0, -0.3, 0))


if __name__ == "__main__":
    main()
