"""Generate the mercenary outpost .glb and a 45 degree preview.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python /Users/hannesalm/code/games/space-majesty/blender/gen_mercenary_outpost.py
  Add `-- --no-preview` to skip the PNG render.

Layout (Blender Z up, exported +Y up). Building centre at origin, play plane z=0.
Same family as the mining outpost: the hangar mouth faces Blender -Y = Godot +Z.
  hangar   armoured bunker x -10.5..10.5, y -13..10, sloped gunmetal armour,
           bay floor z=-3, bay ceiling z=6 (ships at z=0 fit inside)
  apron    in front of the mouth, y -14.6..-23, red/dark hazard edges
  rail     launch rail with catapult arches on +X (x ~16.5), y 7..-29
  turrets  2 defence turrets: front-left and front-right, barrels facing out (-Y)
  racks    missile + ammo racks on -X, sensor mast back-left, command block + radiators
           at the back (+Y)
Hierarchy: mercenary_outpost (empty root)
  -> merc_hangar, merc_rail, merc_turrets, merc_structure, dock_point (empty),
     spawn_point (empty).
dock_point / spawn_point are rotated 180 deg about up, so their Godot -Z (forward)
points out of the hangar mouth (Godot world +Z). A ship given their transform faces out.
"""
import math
import os
import random
import sys

from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
from parts import ALONG_Y, FRONT, V, rot  # noqa: E402

OUT = os.path.join(common.ROOT, "assets", "models", "buildings", "mercenary_outpost.glb")
MOUTH_Y = -13.0                  # hangar mouth plane (Blender y)
BACK_Y = 10.0
DOCK_POS = (0.0, -12.0, 0.0)     # Blender coords, just inside the mouth, on the play plane
SPAWN_POS = (0.0, -31.0, 0.0)    # Blender coords, past the apron
RAIL_X = 16.5
TURRETS = ((-14.0, -17.5), (10.5, -20.5))
RED = ("red", "dark")
# local (x, y, z) -> world (x, z, y): cross-sections drawn in XZ, extruded along world Y
XZ = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))

MATS = {}


def build_materials():
    m = common.make_material
    MATS["hull"] = m("merc_hull_white", (0.78, 0.78, 0.76), roughness=0.45, metallic=0.1)
    MATS["hull2"] = m("merc_hull_grey", (0.50, 0.52, 0.55), roughness=0.5, metallic=0.15)
    MATS["gun"] = m("merc_gunmetal", (0.13, 0.14, 0.16), roughness=0.38, metallic=0.7)
    MATS["dark"] = m("merc_structure_dark", (0.06, 0.065, 0.07), roughness=0.55, metallic=0.5)
    MATS["red"] = m("merc_accent_red", (0.42, 0.02, 0.025), roughness=0.4, metallic=0.1)
    MATS["orange"] = m("merc_accent_orange", (0.85, 0.28, 0.03), roughness=0.45, metallic=0.0)
    MATS["window"] = m("merc_window_warm", (1.0, 0.85, 0.6), roughness=0.3,
                       emission=(1.0, 0.78, 0.5), emission_strength=3.5)
    MATS["light"] = m("merc_light_orange", (1.0, 0.45, 0.1), roughness=0.3,
                      emission=(1.0, 0.42, 0.08), emission_strength=5.0)
    MATS["redlight"] = m("merc_light_red", (1.0, 0.1, 0.05), roughness=0.3,
                         emission=(1.0, 0.08, 0.04), emission_strength=5.0)


def plate(p, a, b, y0, y1, t, mat, sign=1, inset=0.0):
    """Armour plate lying on the XZ segment a->b, spanning world y0..y1, t thick,
    pushed out along the segment normal (sign picks the side)."""
    a, b = V((a[0], 0, a[1])), V((b[0], 0, b[1]))
    d = b - a
    x = d.normalized()
    n = V((-d.z, 0, d.x)).normalized() * sign
    y = V((0, 1, 0))
    r = Matrix((x, y, n)).transposed().to_4x4()
    c = (a + b) / 2 + n * (t / 2) + V((0, (y0 + y1) / 2, 0))
    p.box(c, (d.length - inset, y1 - y0, t), mat, r=r, bevel=0.1)


# ---------------------------------------------------------------- hangar
def build_hangar(rng):
    p = parts.Part("merc_hangar", MATS)
    y0, y1 = MOUTH_Y, BACK_Y
    cy, ln = (y0 + y1) / 2, y1 - y0
    # Armoured bunker shell: chamfered side walls, roof, floor, back wall
    for sx in (-1, 1):
        sec = [(-10.5, -4.5), (-6.5, -4.5), (-6.5, 8.5), (-7.5, 8.5), (-10.5, 1.5)]
        sec = [(sx * x, z) for x, z in sec]
        if sx > 0:
            sec.reverse()
        p.slab(sec, y0, y1, "hull", matrix=XZ)
    p.box(V((0, cy, 7.3)), (13.4, ln, 2.4), "hull")
    p.box(V((0, cy, -4.0)), (13.4, ln, 2.0), "hull2")
    p.box(V((0, y1 - 1.0, 1.5)), (13.0, 2.0, 9.0), "dark", bevel=0.0)
    # Gunmetal armour plates on the slopes and the walls, in segments with gaps
    segs = 5
    sl = (ln - 1.0) / segs
    for k in range(segs):
        a0 = y0 + 0.5 + k * sl + 0.15
        a1 = a0 + sl - 0.3
        plate(p, (-10.5, 1.5), (-7.5, 8.5), a0, a1, 0.35, "gun", sign=1)
        plate(p, (10.5, 1.5), (7.5, 8.5), a0, a1, 0.35, "gun", sign=-1)
        for sx in (-1, 1):
            p.box(V((sx * 10.7, (a0 + a1) / 2, -1.6)), (0.4, a1 - a0, 5.2), "gun", bevel=0.08)
    # Red faction band along the slope tops, window strips under them
    for sx in (-1, 1):
        p.box(V((sx * 7.6, cy + 0.5, 8.75)), (0.9, ln - 2.0, 0.2), "red", bevel=0.0)
        p.box(V((sx * 10.93, cy + 1.5, 0.8)), (0.1, ln - 8.0, 0.4), "window", bevel=0.0)
    # Bay interior: warm back panel, ceiling light strips, floor guide lights
    p.box(V((0, y1 - 2.1, 1.5)), (12.0, 0.2, 7.6), "window", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 6.45, cy + 1, 5.2)), (0.12, ln - 4, 0.5), "window", bevel=0.0)
        p.box(V((sx * 6.45, cy + 1, -1.5)), (0.12, ln - 4, 0.3), "redlight", bevel=0.0)
        for k in range(6):
            p.box(V((sx * 3.2, y0 + 2 + k * 3.4, -2.95)), (0.7, 1.4, 0.1), "light", bevel=0.0)
    p.box(V((0, cy + 1, 6.05)), (2.0, ln - 4, 0.1), "window", bevel=0.0)

    # Mouth: heavy gunmetal frame, red/dark hazard bands, warm inner lip
    fy = y0 - 0.8
    p.box(V((0, fy, 7.6)), (16.0, 1.6, 3.2), "gun")
    p.box(V((0, fy, -4.2)), (16.0, 1.6, 2.4), "gun")
    for sx in (-1, 1):
        p.slab([(sx * 6.5, -5.4), (sx * 11.2, -5.4), (sx * 11.2, 1.5), (sx * 8.0, 9.2),
                (sx * 6.5, 9.2)][::sx], fy - 0.8, fy + 0.8, "gun", matrix=XZ)
    m = Matrix.Translation(V((0, fy - 0.8, 0))) @ FRONT
    p.hazard(-7.8, 7.8, 1.4, 0.0, 0.08, matrix=m @ Matrix.Translation((0, 8.1, 0)), cols=RED)
    p.hazard(-7.8, 7.8, 1.2, 0.0, 0.08, matrix=m @ Matrix.Translation((0, -4.3, 0)), cols=RED)
    p.box(V((0, fy - 0.75, 6.0)), (13.0, 0.2, 0.3), "window", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 6.55, fy - 0.75, 1.4)), (0.3, 0.2, 9.0), "window", bevel=0.0)
        p.box(V((sx * 10.6, fy - 0.6, 2.2)), (0.7, 0.7, 0.7), "light", bevel=0.0)
        p.box(V((sx * 10.6, fy - 0.6, -5.0)), (0.7, 0.7, 0.7), "redlight", bevel=0.0)
        # Armoured blast-door leaves parked open beside the mouth
        p.box(V((sx * 9.0, fy - 1.3, 1.6)), (3.2, 0.5, 9.4), "hull2")
        p.box(V((sx * 9.0, fy - 1.6, 1.6)), (0.5, 0.12, 8.0), "red", bevel=0.0)

    # Roof: dark ribs, orange spine stripes, command bridge with windows, lights
    rz = 8.5
    for k in range(5):
        p.box(V((0, y0 + 3.0 + k * 4.4, rz + 0.25)), (14.6, 0.9, 0.5), "dark", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 3.6, cy - 2.0, rz + 0.06)), (0.9, ln - 10, 0.14), "orange", bevel=0.0)
    p.hazard(-7.5, 7.5, 1.6, rz + 0.5, rz + 0.62, matrix=Matrix.Translation((0, fy, 0)),
             cols=RED)
    bc = V((0, y1 - 5.5, rz))
    p.box(bc + V((0, 0, 1.4)), (7.0, 6.0, 2.8), "hull")
    p.box(bc + V((0, -3.0, 1.9)), (6.0, 0.15, 0.8), "window", bevel=0.0)
    for sx in (-1, 1):
        p.box(bc + V((sx * 3.53, 0, 1.9)), (0.1, 4.0, 0.6), "window", bevel=0.0)
    p.box(bc + V((0, 0, 3.0)), (7.4, 6.4, 0.5), "gun", bevel=0.0)
    p.box(bc + V((0, -1.0, 3.3)), (7.4, 1.0, 0.12), "red", bevel=0.0)
    for sx in (-1, 1):
        for yy in (y0 + 1.0, y1 - 0.6):
            p.box(V((sx * 7.0, yy, rz + 0.3)), (0.6, 0.6, 0.6), "light", bevel=0.0)

    # Apron: landing deck in front of the mouth, red hazard edges, guide lights
    ay0, ay1 = y0 - 1.6, y0 - 10.0
    acy = (ay0 + ay1) / 2
    p.box(V((0, acy, -4.3)), (15.0, ay0 - ay1, 1.4), "hull2")
    p.box(V((0, acy, -5.4)), (11.0, ay0 - ay1 - 1.0, 1.0), "dark", bevel=0.0)
    for sx in (-1, 1):
        r90 = Matrix.Translation((sx * 6.8, acy, 0)) @ Matrix.Rotation(math.pi / 2, 4, "Z")
        p.hazard(ay1 - acy + 0.2, ay0 - acy, 1.2, -3.6, -3.45, matrix=r90, cols=RED)
    p.hazard(-7.5, 7.5, 1.0, -3.6, -3.45, matrix=Matrix.Translation((0, ay1 + 0.6, 0)), cols=RED)
    for k in range(4):
        p.box(V((0, ay1 + 1.8 + k * 1.9, -3.55)), (1.4, 0.6, 0.12), "light", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 7.3, ay1 + 0.2, -3.2)), (0.7, 0.7, 0.7), "light", bevel=0.0)
    return p


# ---------------------------------------------------------------- launch rail
def build_rail(rng):
    p = parts.Part("merc_rail", MATS)
    x = RAIL_X
    r0, r1 = 7.0, -29.0
    rc, rl = (r0 + r1) / 2, r0 - r1
    # Deck + spine girder tied into the hangar wall
    p.box(V((x, rc, -3.4)), (5.0, rl, 1.0), "hull2")
    p.box(V((x, rc, -4.6)), (2.4, rl - 2, 1.4), "dark", bevel=0.0)
    for yy in (4.0, -6.0):
        p.beam(V((10.9, yy, -3.4)), V((x - 2.5, yy, -3.4)), 1.2, 1.0, "gun")
    # Twin rails with red stripe between, orange guide lights
    for sx in (-1, 1):
        p.box(V((x + sx * 1.4, rc, -2.7)), (0.5, rl, 0.4), "dark", bevel=0.0)
    p.box(V((x, rc, -2.86)), (0.6, rl - 1, 0.08), "red", bevel=0.0)
    for k in range(9):
        p.box(V((x, r1 + 1.5 + k * 4.0, -2.8)), (1.0, 0.5, 0.1), "light", bevel=0.0)
    # Catapult arches: gunmetal half-octagons over the rail, red caps
    for k in range(5):
        yy = r0 - 3.0 - k * 6.5
        pts = [V((x - 2.6, yy, -3.0)), V((x - 2.6, yy, 0.6)), V((x - 1.4, yy, 2.4)),
               V((x + 1.4, yy, 2.4)), V((x + 2.6, yy, 0.6)), V((x + 2.6, yy, -3.0))]
        for a, b in zip(pts, pts[1:]):
            p.beam(a, b, 0.9, 0.8, "gun", up=V((0, 1, 0)))
        p.box(V((x, yy, 2.85)), (2.4, 1.0, 0.25), "red", bevel=0.0)
        for sx in (-1, 1):
            p.box(V((x + sx * 2.35, yy, 0.6)), (0.25, 0.7, 0.6), "light", bevel=0.0)
    # Launch end: hazard band, red end lights
    p.hazard(-2.5, 2.5, 1.0, -2.9, -2.75,
             matrix=Matrix.Translation((x, r1 + 0.6, 0)), cols=RED, pitch=1.0)
    for sx in (-1, 1):
        p.box(V((x + sx * 2.2, r1 + 0.3, -2.4)), (0.6, 0.6, 0.6), "redlight", bevel=0.0)
    # Rail control hut at the back end
    p.box(V((x, r0 + 1.6, -1.0)), (5.0, 3.2, 5.0), "hull")
    p.box(V((x, r0 - 0.02, 0.4)), (3.6, 0.1, 0.7), "window", bevel=0.0)
    p.box(V((x, r0 + 1.6, 1.6)), (5.2, 3.4, 0.3), "gun", bevel=0.0)
    return p


# ---------------------------------------------------------------- turrets
def turret(p, cx, cy):
    c = V((cx, cy, 0))
    # Pylon from below the deck plane, armoured ring, turret head
    p.cyl(c + V((0, 0, -3.2)), 1.4, 1.0, 5.6, "hull2", segs=10)
    p.cyl(c + V((0, 0, -6.2)), 2.6, 1.6, 1.0, "dark", segs=10)
    p.cyl(c + V((0, 0, 0.1)), 2.1, 2.1, 1.0, "gun", segs=12)
    p.cyl(c + V((0, 0, 0.65)), 2.15, 2.15, 0.12, "red", segs=12)
    # Head: slanted armour wedge (side profile), barrels toward -Y
    head = Matrix.Translation(c + V((0, 0, 0.6))) @ parts.SIDE
    p.slab([(1.6, 0.0), (1.6, 1.2), (0.2, 2.0), (-1.8, 1.7), (-1.8, 0.0)][::-1],
           -1.5, 1.5, "hull", matrix=head)
    p.slab([(1.65, 0.1), (1.65, 1.1), (0.25, 1.9), (0.0, 1.85)][::-1], -1.55, -1.45, "red",
           matrix=head)
    p.slab([(1.65, 0.1), (1.65, 1.1), (0.25, 1.9), (0.0, 1.85)][::-1], 1.45, 1.55, "red",
           matrix=head)
    for sx in (-1, 1):
        p.cyl(c + V((sx * 0.55, -2.4, 1.3)), 0.32, 0.32, 1.4, "gun", segs=8, axis_rot=ALONG_Y)
        p.cyl(c + V((sx * 0.55, -4.4, 1.3)), 0.16, 0.16, 3.4, "dark", segs=8, axis_rot=ALONG_Y)
        p.cyl(c + V((sx * 0.55, -6.15, 1.3)), 0.24, 0.24, 0.3, "dark", segs=8, axis_rot=ALONG_Y)
    p.box(c + V((0, 0.9, 2.7)), (0.8, 0.8, 0.5), "gun", bevel=0.0)
    p.box(c + V((0, 0.5, 2.7)), (0.5, 0.12, 0.25), "redlight", bevel=0.0)
    p.box(c + V((0, 1.8, 1.6)), (0.4, 0.4, 0.4), "light", bevel=0.0)


def build_turrets(rng):
    p = parts.Part("merc_turrets", MATS)
    for cx, cy in TURRETS:
        turret(p, cx, cy)
    # Struts tying the turret pylons to the base
    p.beam(V((TURRETS[0][0], TURRETS[0][1], -5.0)), V((-10.5, -10.0, -4.5)), 1.0, 1.0, "dark")
    p.beam(V((TURRETS[1][0], TURRETS[1][1], -5.0)), V((7.5, -18.5, -4.6)), 1.0, 1.0, "dark")
    p.beam(V((TURRETS[1][0], TURRETS[1][1], -5.0)), V((RAIL_X, -20.5, -4.6)), 1.0, 1.0, "dark")
    return p


# ---------------------------------------------------------------- structure
def build_structure(rng):
    p = parts.Part("merc_structure", MATS)
    # Spine deck on -X under racks, mast and turret strut
    p.box(V((-16.5, -1.0, -5.6)), (11.0, 26.0, 1.2), "dark", bevel=0.0)
    p.box(V((-11.5, -1.0, -4.6)), (2.0, 20.0, 1.6), "hull2")
    # Missile + ammo racks: two-tier dark frame, white missiles with red noses
    rx0, rx1, ry0, ry1 = -21.0, -13.0, -9.0, 3.0
    for xx in (rx0, rx1):
        for yy in (ry0, ry1):
            p.box(V((xx, yy, -1.6)), (0.5, 0.5, 7.0), "dark", bevel=0.0)
    for z in (-4.6, -0.6, 1.9):
        for xx in (rx0, rx1):
            p.beam(V((xx, ry0, z)), V((xx, ry1, z)), 0.4, 0.4, "dark")
        for yy in (ry0, ry1, (ry0 + ry1) / 2):
            p.beam(V((rx0, yy, z)), V((rx1, yy, z)), 0.4, 0.4, "dark")
    for tier, z in enumerate((-3.8, 0.2)):
        for k in range(6):
            xx = rx0 + 0.8 + k * 1.3
            p.cyl(V((xx, -2.6, z)), 0.42, 0.42, 9.0, "hull", segs=8, axis_rot=ALONG_Y)
            p.cyl(V((xx, -7.6, z)), 0.42, 0.04, 1.0, "red", segs=8, axis_rot=ALONG_Y)
            p.cyl(V((xx, 1.95, z)), 0.46, 0.46, 0.4, "orange", segs=8, axis_rot=ALONG_Y)
    # Ammo crate stacks next to the racks
    for i, (xx, yy, zz) in enumerate(((-18.5, 6.0, -4.0), (-15.5, 6.0, -4.0), (-17.0, 6.0, -1.6),
                                      (-20.0, -12.0, -4.0), (-17.0, -12.0, -4.0))):
        p.box(V((xx, yy, zz)), (2.8, 2.4, 2.2), "gun", bevel=0.06)
        p.box(V((xx, yy, zz + 1.12)), (2.4, 0.5, 0.06), "red" if i % 2 else "orange", bevel=0.0)
    # Sensor mast back-left: lattice tower, radar bar, dish, red beacons
    mb = V((-17.0, 12.0, 0))
    top = 22.0
    for dx in (-1, 1):
        for dy in (-1, 1):
            p.beam(mb + V((dx * 1.6, dy * 1.6, -5.5)), mb + V((dx * 0.6, dy * 0.6, top)), 0.4, 0.4,
                   "dark")
    for k in range(5):
        z0, z1 = -5.0 + k * 5.2, 0.2 + k * 5.2
        w0, w1 = 1.6 - k * 0.2, 1.4 - k * 0.2
        for s in range(4):
            a = s * math.pi / 2
            n = V((math.cos(a), math.sin(a), 0))
            t = V((-math.sin(a), math.cos(a), 0))
            p.beam(mb + n * w0 - t * w0 + V((0, 0, z0)), mb + n * w1 + t * w1 + V((0, 0, z1)),
                   0.2, 0.2, "dark")
    p.box(mb + V((0, 0, -5.0)), (5.0, 5.0, 1.4), "hull2")
    p.box(mb + V((0, 0, top + 0.6)), (2.2, 2.2, 1.4), "hull")
    p.box(mb + V((0, 0, top + 1.6)), (9.0, 1.0, 0.6), "gun", rot_z=0.5)
    p.box(mb + V((0, 0, top + 1.95)), (8.6, 0.4, 0.12), "red", rot_z=0.5, bevel=0.0)
    p.cyl(mb + V((0, 0, top + 3.4)), 0.12, 0.05, 3.2, "dark", segs=5)
    p.box(mb + V((0, 0, top + 5.1)), (0.6, 0.6, 0.6), "redlight", bevel=0.0)
    for s in (-1, 1):
        p.box(mb + V((math.cos(0.5) * 4.4 * s, math.sin(0.5) * 4.4 * s, top + 1.6)),
              (0.5, 0.5, 0.5), "redlight", bevel=0.0)
    dish = (Matrix.Translation(mb + V((0, 0, 12.0))) @ Matrix.Rotation(math.radians(70), 4, "X")
            @ Matrix.Translation((0, 0, 1.8)))
    p.lathe([(0, 0), (1.2, 0.25), (2.4, 0.9), (2.6, 1.05), (2.6, 0.85), (2.2, 0.6), (0, -0.15)],
            14, lambda i, j: ("hull", "hull", "red", "dark", "dark", "dark")[j], matrix=dish)
    # Walkway mast -> hangar
    p.box(V((-12.5, 9.0, 1.0)), (6.0, 2.2, 2.0), "hull2")
    p.box(V((-12.5, 7.88, 1.0)), (4.6, 0.08, 0.4), "window", bevel=0.0)

    # Command / reactor block behind the hangar, radiator fins out the back
    pb = V((0, 14.0, 0))
    p.box(pb + V((0, 0, -0.5)), (14.0, 8.0, 8.0), "hull2")
    p.box(pb + V((0, 0, 3.7)), (12.0, 6.4, 0.6), "gun", bevel=0.0)
    p.box(pb + V((0, 0, 4.05)), (12.4, 0.9, 0.12), "red", bevel=0.0)
    for sx in (-1, 1):
        p.cyl(pb + V((sx * 3.4, 0.6, 5.0)), 1.6, 1.6, 2.4, "hull", segs=12)
        p.cyl(pb + V((sx * 3.4, 0.6, 6.4)), 1.6, 1.0, 0.4, "hull", segs=12)
        p.cyl(pb + V((sx * 3.4, 0.6, 6.7)), 0.45, 0.45, 0.3, "light", segs=6)
        p.box(pb + V((sx * 7.03, 0, 0.5)), (0.08, 5.6, 0.4), "window", bevel=0.0)
    p.hazard(-7.0, 7.0, 1.0, 0.0, 0.08,
             matrix=Matrix.Translation(pb + V((0, 4.05, -2.6))) @
             Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1))), cols=RED)
    for sx in (-1, 1):
        p.box(pb + V((sx * 4.0, 8.0, -0.5)), (0.8, 8.0, 0.8), "dark", bevel=0.0)
        for k in range(3):
            p.box(pb + V((sx * 6.6, 5.4 + k * 2.4, -0.5)), (4.6, 2.0, 0.2), "dark", bevel=0.0)
            p.box(pb + V((sx * 6.6, 5.4 + k * 2.4, -0.35)), (4.2, 0.25, 0.1), "red", bevel=0.0)
        p.box(pb + V((sx * 4.0, 12.2, -0.5)), (0.9, 0.9, 0.9), "light", bevel=0.0)
    return p


def build_outpost():
    rng = random.Random(4417)
    build_materials()
    root = parts.make_root("mercenary_outpost", size=10)
    objs = [b(rng).finish(root) for b in (build_hangar, build_rail, build_turrets,
                                          build_structure)]
    for name, pos in (("dock_point", DOCK_POS), ("spawn_point", SPAWN_POS)):
        parts.add_empty(name, root, pos, rot_z=math.pi, size=4)
    return root, objs


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_outpost()
    parts.print_stats(objs)
    parts.save_blend(os.path.join(common.ROOT, "blender", "mercenary_outpost.blend"))
    common.export_glb(root, OUT)
    if "--no-preview" not in argv:
        common.setup_preview(cam_loc=(-45, -75, 80), cam_target=(0, -3, 0), ortho_scale=74,
                             res=(1600, 1200), key_dir=(-0.6, -0.35, 0.7), key_energy=3.5)
        common.render(os.path.join(common.PREVIEW_DIR, "mercenary_outpost_preview.png"))


main()
