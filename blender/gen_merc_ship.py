"""Generate the mercenary gunship .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python /Users/hannesalm/code/games/space-majesty/blender/gen_merc_ship.py
  Add `-- --no-preview` to skip the PNG renders.

Design: functional hard sci-fi gunship in the Rocinante mould. A tall, blunt,
stacked-deck hull with chamfered corners (nose cap with the flight deck windows,
command deck, armoured mid deck, reactor deck), twin spinal railguns running through
the lower hull and out of the flat nose face, two point-defense turrets on the top
shoulders, bolt-on armour plates, flush radiator panels on the reactor deck, RCS quads
on the corners, a docking ring, sensor mast and comms dish on top, and one big main
engine bell at the stern with a short blue-white glow. No wings, no fins, no point.

Layout (Blender Z up, exported +Y up). Ship centre at origin on the play plane z=0.
The nose points along Blender +Y, which the exporter turns into Godot -Z (forward).
Hierarchy: merc_fighter (empty root) -> merc_hull, merc_weapons, engine_glow,
  muzzle_l (empty), muzzle_r (empty).
engine_glow has its origin on the bell exit plane (Blender y = NOZZLE_Y) and its plume
extends along Godot local +Z, so scaling it on Z lengthens the glow backwards.
Muzzle empties are unrotated, so their Godot -Z points forward along the barrels.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
from parts import ALONG_Y, V  # noqa: E402

OUT = os.path.join(common.ROOT, "assets", "models", "ships", "merc_fighter.glb")
NOZZLE_Y = -7.4
BELL_R = 1.45
BELL_LEN = 1.9
RAIL_X = 0.55
RAIL_Z = -1.0
MUZZLE_Y = 7.6
PDC = ((-1.25, 0.9, 2.05), (1.25, 0.9, 2.05))

# Deck sections: (y_rear, y_front, (w, h, chamfer) rear, (w, h, chamfer) front, material)
DECKS = (
    (-4.9, -1.75, (3.1, 3.6, 0.85), (3.6, 4.2, 1.0), "steel"),     # reactor deck
    (-1.75, -1.5, (3.3, 3.9, 0.95), (3.3, 3.9, 0.95), "dark"),     # seam
    (-1.5, 2.3, (3.8, 4.4, 1.05), (3.8, 4.4, 1.05), "steel"),      # armoured mid deck
    (2.3, 2.55, (3.3, 3.9, 0.95), (3.3, 3.9, 0.95), "dark"),       # seam
    (2.55, 4.9, (3.4, 4.0, 0.95), (3.4, 4.0, 0.95), "steel2"),     # command deck
    (4.9, 6.35, (3.2, 3.8, 0.9), (2.5, 2.9, 0.75), "steel"),       # nose cap
)

MATS = {}


def build_materials():
    m = common.make_material
    MATS["steel"] = m("merc_hull_steel", (0.17, 0.19, 0.22), roughness=0.5, metallic=0.5)
    MATS["steel2"] = m("merc_plate_steel_light", (0.31, 0.33, 0.37), roughness=0.5, metallic=0.35)
    MATS["gun"] = m("merc_gunmetal", (0.13, 0.14, 0.16), roughness=0.38, metallic=0.7)
    MATS["dark"] = m("merc_structure_dark", (0.06, 0.065, 0.07), roughness=0.55, metallic=0.5)
    MATS["red"] = m("merc_accent_red", (0.42, 0.02, 0.025), roughness=0.4, metallic=0.1)
    MATS["orange"] = m("merc_accent_orange", (0.85, 0.28, 0.03), roughness=0.45, metallic=0.0)
    MATS["window"] = m("merc_window_warm", (1.0, 0.85, 0.6), roughness=0.3,
                       emission=(1.0, 0.78, 0.5), emission_strength=3.5)
    MATS["light"] = m("merc_light_orange", (1.0, 0.45, 0.1), roughness=0.3,
                      emission=(1.0, 0.42, 0.08), emission_strength=5.0)
    MATS["nav_r"] = m("merc_nav_red", (1.0, 0.05, 0.03), roughness=0.3,
                      emission=(1.0, 0.05, 0.03), emission_strength=6.0)
    MATS["nav_g"] = m("merc_nav_green", (0.1, 1.0, 0.25), roughness=0.3,
                      emission=(0.1, 1.0, 0.25), emission_strength=6.0)
    MATS["glow"] = m("merc_engine_glow", (0.8, 0.95, 1.0), roughness=0.2,
                     emission=(0.65, 0.92, 1.0), emission_strength=6.0)


def deck_mat(base):
    """Face material per loft edge: top and bottom faces get the lighter plate tone."""
    def fn(i, j):
        if base == "steel" and j in (2, 6):
            return "steel2"
        return base
    return fn


def build_hull():
    p = parts.Part("merc_hull", MATS)
    for y0, y1, d0, d1, mat in DECKS:
        parts.prism(p, y0, y1, d0, d1, mat, mat_fn=deck_mat(mat))
    # Red identity band around the command deck, just behind the nose cap
    parts.prism(p, 4.45, 4.75, (3.46, 4.06, 0.97), (3.46, 4.06, 0.97), "red")
    # Flat nose face: flight deck windows (a row of small panes) and a dark plate below
    nf = 6.36
    for k in range(4):
        p.box(V((-0.75 + k * 0.5, nf, 0.75)), (0.36, 0.06, 0.32), "window", bevel=0.0)
    p.box(V((0, nf, -0.55)), (1.9, 0.05, 1.1), "dark", bevel=0.0)
    # Small side windows on the command deck
    for sx in (-1, 1):
        for k in range(3):
            p.box(V((sx * 1.71, 3.2 + k * 0.45, 0.9)), (0.05, 0.22, 0.16), "window", bevel=0.0)
    # Bolt-on armour plates on the mid deck flanks and roof
    for sx in (-1, 1):
        for y in (-0.6, 1.35):
            p.box(V((sx * 1.96, y, 0.0)), (0.14, 1.7, 2.0), "steel2", bevel=0.08)
            p.box(V((sx * 2.04, y, 0.75)), (0.04, 1.4, 0.14), "red", bevel=0.0)
        p.box(V((sx * 0.75, 0.4, 2.27)), (1.0, 3.2, 0.14), "steel2", bevel=0.08)
    # Flush radiator panels along the reactor deck flanks (edge-on to the ship, not wings)
    for sx in (-1, 1):
        parts.radiator(p, V((sx * 1.72, -3.3, 0.0)), 2.6, 1.7, (sx, 0, 0), "dark", "gun", ribs=7)
    # Docking ring and hatch on the command deck roof
    p.cyl(V((0, 3.6, 2.05)), 0.62, 0.62, 0.2, "gun", segs=16)
    p.cyl(V((0, 3.6, 2.15)), 0.45, 0.45, 0.1, "steel2", segs=16)
    # Sensor mast and comms dish on the reactor deck roof
    p.cyl(V((0.7, -2.6, 2.3)), 0.07, 0.05, 1.1, "dark", segs=6)
    p.box(V((0.7, -2.6, 2.9)), (0.16, 0.16, 0.16), "light", bevel=0.0)
    p.cyl(V((-0.6, -3.6, 1.95)), 0.22, 0.28, 0.35, "dark", segs=8)
    parts.dish(p, V((-0.6, -3.6, 2.15)), 0.6, (0, 0.5, 1), "steel2", "dark")
    # RCS quads on the chamfered corners, fore and aft
    for y, (w, h, c) in ((5.4, (2.96, 3.49, 0.87)), (-4.2, (3.21, 3.73, 0.88))):
        for sx in (-1, 1):
            for sz in (-1, 1):
                pos = V((sx * (w / 2 - c / 2 + 0.1), y, sz * (h / 2 - c / 2 + 0.1)))
                parts.rcs_quad(p, pos, (sx, 0, sz), "gun", "dark", s=0.3)
    # Engine section: thrust frame, reactor collar, gimbal ring, main bell
    p.tube(V((0, -4.9, 0)), V((0, -5.35, 0)), 1.35, 1.2, "gun", segs=16)
    p.cyl(V((0, -5.45, 0)), 1.05, 1.05, 0.2, "red", segs=16, axis_rot=ALONG_Y)
    for k in range(6):  # gimbal struts
        a = k * math.pi / 3 + math.pi / 6
        p.beam(V((1.2 * math.cos(a), -5.0, 1.2 * math.sin(a))),
               V((0.75 * math.cos(a), -5.65, 0.75 * math.sin(a))), 0.12, 0.12, "dark")
    parts.bell(p, NOZZLE_Y, BELL_R, BELL_LEN, "gun", "dark", segs=20)
    p.torus(V((0, NOZZLE_Y + 0.55, 0)), BELL_R * 0.86, 0.06, "dark", segs=20, minor_segs=4,
            matrix=parts.rot(rx=math.pi / 2))
    # Hazard stripes on the stern plate around the engine
    p.hazard(-1.3, 1.3, 0.3, -0.03, 0.03,
             matrix=parts.Matrix.Translation((0, -4.92, 1.55)) @ parts.rot(rx=math.pi / 2),
             pitch=0.35, cols=("orange", "dark"))
    # Nav lights: red port, green starboard, orange top and stern
    for sx, mat in ((-1, "nav_r"), (1, "nav_g")):
        p.box(V((sx * 1.95, 2.0, 1.4)), (0.16, 0.25, 0.16), mat, bevel=0.0)
        p.box(V((sx * 1.6, -4.7, 1.2)), (0.14, 0.2, 0.14), mat, bevel=0.0)
    p.box(V((0, 6.1, 1.5)), (0.2, 0.2, 0.15), "light", bevel=0.0)
    return p


def pdc_turret(p, base):
    """Point-defense turret: armoured ring, low dome, twin short barrels forward."""
    b = V(base)
    p.cyl(b + V((0, 0, 0.1)), 0.5, 0.55, 0.2, "gun", segs=12)
    p.sphere(b + V((0, 0, 0.3)), 0.42, "steel2", segs=12, rings=6, scale=(1.0, 1.0, 0.7))
    for dx in (-0.12, 0.12):
        p.cyl(b + V((dx, 0.75, 0.33)), 0.06, 0.06, 0.9, "dark", segs=6, axis_rot=ALONG_Y)
    p.box(b + V((0, 0.3, 0.33)), (0.4, 0.3, 0.22), "gun", bevel=0.1)
    p.box(b + V((0, -0.1, 0.56)), (0.18, 0.18, 0.06), "red", bevel=0.0)


def build_weapons():
    p = parts.Part("merc_weapons", MATS)
    # Twin spinal railguns: armoured housings proud of the lower nose face, long rails
    for sx in (-1, 1):
        x = sx * RAIL_X
        p.box(V((x, 6.55, RAIL_Z)), (0.62, 0.5, 0.62), "gun", bevel=0.12)
        p.box(V((x, 7.05, RAIL_Z)), (0.34, 1.1, 0.44), "dark", bevel=0.05)
        for dz in (-0.17, 0.17):  # rail pair
            p.box(V((x, 7.0, RAIL_Z + dz)), (0.26, 1.2, 0.07), "steel2", bevel=0.0)
        p.box(V((x, MUZZLE_Y - 0.08, RAIL_Z)), (0.42, 0.16, 0.5), "gun", bevel=0.1)
        p.box(V((x, MUZZLE_Y, RAIL_Z)), (0.12, 0.04, 0.12), "light", bevel=0.0)
        # Capacitor banks on the keel
        p.box(V((x, 3.6, -2.25)), (0.7, 3.0, 0.3), "gun", bevel=0.1)
        for k in range(4):
            p.box(V((x, 2.5 + k * 0.7, -2.42)), (0.5, 0.3, 0.06), "red" if k % 2 else "dark",
                  bevel=0.0)
    p.hazard(-1.0, 1.0, 0.22, -0.02, 0.02,
             matrix=parts.Matrix.Translation((0, 6.37, -1.6)) @ parts.rot(rx=math.pi / 2),
             pitch=0.3, cols=("orange", "dark"))
    for pos in PDC:
        pdc_turret(p, pos)
    return p


def build_glow():
    p = parts.Part("engine_glow", MATS)
    # Built around the bell exit plane at y = 0 (object origin moved to NOZZLE_Y below).
    parts.exhaust_glow(p, BELL_R * 0.85, 1.2, "glow", segs=20)
    return p


def build_ship():
    build_materials()
    root = parts.make_root("merc_fighter")
    objs = [b().finish(root) for b in (build_hull, build_weapons, build_glow)]
    objs[-1].location = (0, NOZZLE_Y, 0)
    for name, sx in (("muzzle_l", -1), ("muzzle_r", 1)):
        parts.add_empty(name, root, (sx * RAIL_X, MUZZLE_Y + 0.03, RAIL_Z), size=1.0)
    return root, objs


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_ship()
    parts.print_stats(objs)
    parts.save_blend(os.path.join(common.ROOT, "blender", "merc_fighter.blend"))
    common.export_glb(root, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews("merc_fighter", 17.0, target=(0, -0.2, 0))


main()
