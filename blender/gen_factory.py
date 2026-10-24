"""Generate the Factory (orbital manufacturing plant) .glb and previews.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_factory.py
  Add `-- --no-preview` to skip the PNG renders, `-- --no-textures` for flat materials.
Textures: one 2048 atlas baked with the station_textures surface kinds (plus "ore" and
"radiator"), saved as blender/textures/factory_*.{jpg,png} and embedded as JPEG.

Layout (Blender Z up, exported +Y up; Blender -Y = Godot +Z). Centre at origin, plane z=0.
  receiving dock   x -10..10, y -30..-6, bay floor z=-3, ceiling z=9.5, mouth at y=-30
  ore hoppers      two funnels front right (+X), crushers + conveyors into the smelter
  smelter          x 13..33, y -13..13, z -6..14; furnace vent on the roof, glowing slot
                   on the front, stack at (29, -8) to z 26, radiator fin bank on the roof
  fabrication hall x -32..10, y 8..26, z -5..15, two roof gantry cranes
  container yard   x -33..-12, y -21..6, racks of finished parts + a yard gantry crane
  tanks            back right, pipes into smelter and hall
  link port        back of the hall, flange at y = 29.8, z = 12 (corridor height)
Hierarchy: factory (empty root) -> factory_hull, factory_radiators, factory_furnace_glow,
  factory_lights, dock_point, spawn_point, link_point (empties).
dock_point / spawn_point are rotated 180 deg about up (mining outpost convention): their
Godot -Z points out of the dock mouth (Godot +Z). link_point is unrotated: its Godot -Z
points out of the back (Godot -Z), where the corridor collar attaches.
"""
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
import station_textures as st  # noqa: E402

V = Vector
OUT = os.path.join(common.ROOT, "assets", "models", "buildings", "factory.glb")
BLEND = os.path.join(common.ROOT, "blender", "factory.blend")
MOUTH_Y = -30.0
DOCK_POS = (0.0, -28.0, 0.0)
SPAWN_POS = (0.0, -48.0, 0.0)
LINK_POS = (0.0, 29.8, 12.0)
ATLAS_RES = 2048
ALONG_Y = parts.ALONG_Y
ALONG_X = parts.ALONG_X

MATS = {}


def build_materials():
    m = common.make_material
    MATS["hull"] = m("factory_hull_white", (0.78, 0.78, 0.76), roughness=0.45, metallic=0.1)
    MATS["hull2"] = m("factory_hull_grey", (0.50, 0.52, 0.55), roughness=0.5, metallic=0.15)
    MATS["dark"] = m("factory_structure_dark", (0.06, 0.065, 0.07), roughness=0.55, metallic=0.5)
    MATS["orange"] = m("factory_accent_orange", (0.85, 0.28, 0.03), roughness=0.45)
    MATS["hazard"] = m("factory_hazard", (0.8, 0.55, 0.02), roughness=0.5)
    MATS["mli"] = m("factory_mli_white", (0.8, 0.8, 0.78), roughness=0.85)
    MATS["mli_gold"] = m("factory_mli_gold", (0.8, 0.52, 0.15), roughness=0.4, metallic=0.9)
    MATS["pad"] = m("factory_deck", (0.15, 0.15, 0.16), roughness=0.7, metallic=0.2)
    MATS["ore"] = m("factory_ore", (0.22, 0.17, 0.13), roughness=0.9, metallic=0.1)
    MATS["radiator"] = m("factory_radiator", (0.12, 0.13, 0.14), roughness=0.4, metallic=0.7)
    MATS["window"] = m("factory_window_warm", (1.0, 0.85, 0.6), roughness=0.3,
                       emission=(1.0, 0.78, 0.5), emission_strength=3.5)
    MATS["light"] = m("factory_light_orange", (1.0, 0.45, 0.1), roughness=0.3,
                      emission=(1.0, 0.42, 0.08), emission_strength=5.0)
    MATS["red"] = m("factory_light_red", (1.0, 0.12, 0.05), roughness=0.3,
                    emission=(1.0, 0.1, 0.04), emission_strength=5.0)
    MATS["glow"] = m("factory_furnace_glow", (1.0, 0.36, 0.05), roughness=0.4,
                     emission=(1.0, 0.34, 0.05), emission_strength=6.0)


# extra surface kinds for the bake (station kinds are reused as they are)
EXTRA_KINDS = {
    "ore": dict(panel=(0.8, 0.8), tones=[(0.20, 0.16, 0.12), (0.17, 0.14, 0.11),
                                         (0.24, 0.19, 0.14), (0.14, 0.12, 0.10)],
                rough=(0.88, 0.08), metal=0.1, seam_dark=0.05, rivets=False,
                chip=(0.35, 0.30, 0.26), chip_metal=0.3, chip_k=0.6, grime_k=1.2, bleach=0.1),
    "radiator": dict(panel=(0.6, 3.0), tones=[(0.13, 0.14, 0.15), (0.11, 0.12, 0.13),
                                              (0.15, 0.155, 0.16), (0.12, 0.125, 0.13)],
                     rough=(0.38, 0.12), metal=0.7, seam_dark=0.5, rivets=False,
                     chip=(0.45, 0.45, 0.46), chip_metal=1.0, chip_k=0.6, grime_k=0.6,
                     bleach=0.25),
}

H = R = G = L = None   # parts: hull, radiators, furnace glow, lights


def lamp(pos, s=0.8, mat="light"):
    L.box(V(pos), (s, s, s * 0.6), mat, bevel=0.0)


def beacon(pos, r=0.7, mat="light"):
    """Bigger warning light on a short dark post (reads from far zoom)."""
    p = V(pos)
    H.cyl(p - V((0, 0, 0.5)), 0.25, 0.25, 1.0, "dark", segs=6)
    L.cyl(p + V((0, 0, 0.25)), r, r * 0.8, r * 0.9, mat, segs=8)


def tank(p, c, r, h, mat_body, band="orange"):
    """Vertical tank with elliptic domes, base at c.z, total height h."""
    x, y, z0 = c
    dome = r * 0.6
    prof = [(0.0, z0)]
    for k in range(1, 4):
        a = math.pi / 2 * k / 3
        prof.append((r * math.sin(a), z0 + dome * (1 - math.cos(a))))
    zb0, zb1 = z0 + dome + (h - 2 * dome) * 0.62, z0 + dome + (h - 2 * dome) * 0.70
    prof += [(r, zb0), (r, zb1)]
    for k in range(0, 4):
        a = math.pi / 2 * k / 3
        prof.append((r * math.cos(a), z0 + h - dome + dome * math.sin(a)))
    prof[-1] = (0.0, z0 + h)

    def mf(i, j):
        return band if j == 4 else mat_body
    p.lathe(prof, 16, mf, matrix=Matrix.Translation((x, y, 0)))


# ---------------------------------------------------------------- frame / keel
def build_frame(rng):
    # main keel under dock, transfer module and hall
    parts.box_truss(H, -30.0, 26.0, 2.2, 1.2, 8, "dark", "dark", chord=0.5, brace=0.3,
                    z0=-6.2, x0=0.0)
    parts.box_truss(H, -20.0, 6.0, 1.8, 1.0, 4, "dark", "dark", chord=0.4, brace=0.25,
                    z0=-5.4, x0=-22.5)
    parts.box_truss(H, -12.0, 24.0, 1.8, 1.0, 5, "dark", "dark", chord=0.4, brace=0.25,
                    z0=-7.0, x0=23.0)
    # cross girders tying the blocks together
    for y, x0, x1 in ((-3.0, -30.0, 30.0), (16.0, -30.0, 30.0)):
        H.box(V(((x0 + x1) / 2, y, -6.2)), (x1 - x0, 1.8, 2.2), "dark", bevel=0.05)
        H.box(V(((x0 + x1) / 2, y, -5.0)), (x1 - x0 - 2, 0.8, 0.25), "hull2", bevel=0.0)


# ---------------------------------------------------------------- receiving dock
def build_dock(rng):
    yc, ln = -18.0, 24.0
    H.box(V((0, yc, -3.75)), (20, ln, 1.5), "pad", bevel=0.05)
    for sx in (-1, 1):
        H.box(V((sx * 9.0, yc, 3.25)), (2.0, ln, 12.5), "hull", bevel=0.05)
        H.box(V((sx * 10.35, yc + 1, 1.0)), (0.7, 16, 6.0), "hull2", bevel=0.08)
        H.box(V((sx * 10.3, yc, 8.4)), (0.6, ln - 1, 0.6), "orange", bevel=0.0)
        for k in range(5):
            H.box(V((sx * 10.2, -28.0 + k * 5.0, 3.25)), (0.6, 0.8, 12.6), "dark", bevel=0.0)
        L.box(V((sx * 10.36, yc, 5.6)), (0.1, 18, 0.5), "window", bevel=0.0)
    H.box(V((0, yc, 10.25)), (20, ln, 1.5), "hull2", bevel=0.05)
    for k in range(6):
        H.box(V((0, -28.0 + k * 4.0, 11.2)), (20.4, 0.6, 0.5), "dark", bevel=0.0)
    H.box(V((0, -6.5, 3.25)), (16, 1.0, 12.5), "dark", bevel=0.0)
    # mouth frame
    H.box(V((0, MOUTH_Y - 0.4, 10.0)), (20.8, 1.2, 2.4), "hazard", bevel=0.05)
    for sx in (-1, 1):
        H.box(V((sx * 9.7, MOUTH_Y - 0.4, 3.2)), (1.6, 1.2, 12.8), "orange", bevel=0.05)
    L.box(V((0, MOUTH_Y - 1.02, 8.75)), (15.0, 0.1, 0.3), "window", bevel=0.0)
    for sx in (-1, 1):
        L.box(V((sx * 8.85, MOUTH_Y - 1.02, 3.0)), (0.3, 0.1, 11.0), "window", bevel=0.0)
        beacon((sx * 9.7, MOUTH_Y - 0.4, 11.7), 0.75)
    # apron
    H.box(V((0, MOUTH_Y - 3.0, -3.75)), (18, 6.0, 1.5), "pad", bevel=0.05)
    H.box(V((0, MOUTH_Y - 5.8, -2.95)), (18, 0.8, 0.12), "hazard", bevel=0.0)
    for sx in (-1, 1):
        H.box(V((sx * 8.6, MOUTH_Y - 3.0, -2.95)), (0.8, 6.0, 0.12), "hazard", bevel=0.0)
        lamp((sx * 8.6, MOUTH_Y - 5.8, -2.7), 0.7)
    # floor guide lights and ceiling strips
    for k in range(6):
        y = -28.0 + k * 4.0
        for sx in (-1, 1):
            L.box(V((sx * 6.5, y, -2.95)), (0.6, 1.4, 0.1), "light", bevel=0.0)
    for y in (-26.0, -18.0, -10.0):
        L.box(V((0, y, 9.45)), (8.0, 0.8, 0.1), "window", bevel=0.0)
    # interior: back wall machinery (unloading arms)
    for sx in (-1, 1):
        H.box(V((sx * 5.0, -7.6, 0.0)), (3.0, 1.4, 6.0), "hull2", bevel=0.08)
        H.box(V((sx * 5.0, -8.4, 1.5)), (2.0, 0.3, 0.6), "orange", bevel=0.0)
    # control cab on the roof, front left
    cc = V((-5.5, -25.5, 0))
    H.box(cc + V((0, 0, 12.8)), (6.0, 6.0, 3.6), "hull", bevel=0.06)
    L.box(cc + V((0, 0, 13.4)), (6.1, 6.1, 0.9), "window", bevel=0.0)
    H.box(cc + V((0, 0, 14.9)), (6.6, 6.6, 0.6), "dark", bevel=0.05)
    H.cyl(cc + V((2.0, 2.0, 17.5)), 0.18, 0.08, 5.0, "dark", segs=6)
    lamp(cc + V((2.0, 2.0, 20.1)), 0.5, "red")
    parts.dish(H, cc + V((-1.4, -1.2, 15.4)), 1.4, V((0.3, -0.5, 1.0)), "hull", "dark",
               depth=0.4, segs=12)
    # roof greebles: vents and service boxes
    for x, y, w, d, h, mat in ((4.0, -24.0, 3.0, 2.4, 1.2, "mli"), (5.0, -16.0, 4.0, 3.0, 1.0, "hull"),
                               (-4.0, -15.0, 3.0, 5.0, 0.9, "hull2"), (0.0, -9.5, 8.0, 2.0, 1.3, "mli"),
                               (-6.5, -10.5, 2.0, 2.0, 1.6, "hull2")):
        H.box(V((x, y, 11.0 + h / 2)), (w, d, h), mat, bevel=0.08)
    for sx in (-1, 1):
        lamp((sx * 9.6, -7.0, 11.3), 0.8)


# ---------------------------------------------------------------- transfer module
def build_transfer(rng):
    H.box(V((0, 1.0, 1.0)), (16, 14, 10), "hull2", bevel=0.05)
    H.box(V((0, 1.0, 6.4)), (14, 12, 0.8), "dark", bevel=0.05)
    H.box(V((-3.5, 1.0, 7.4)), (5, 8, 1.4), "mli", bevel=0.08)
    H.box(V((3.5, 2.0, 7.2)), (4, 4, 1.0), "hull", bevel=0.08)
    H.box(V((3.5, 2.0, 7.75)), (4.2, 0.8, 0.1), "orange", bevel=0.0)
    for sx in (-1, 1):
        L.box(V((sx * 8.03, 1.0, 3.0)), (0.08, 10.0, 0.4), "window", bevel=0.0)
        H.box(V((sx * 8.1, 1.0, -1.0)), (0.5, 12.0, 0.5), "orange", bevel=0.0)


# ---------------------------------------------------------------- ore hoppers
def build_hoppers(rng):
    for cx, cy in ((18.0, -24.0), (29.0, -21.0)):
        prof = [(0.0, 1.5), (1.6, 1.5), (1.6, 2.6), (5.0, 9.0), (5.4, 9.0), (5.4, 10.2),
                (4.8, 10.2), (4.6, 9.6), (1.4, 3.4), (0.0, 3.4)]
        hm = {0: "dark", 1: "dark", 2: "hull2", 3: "dark", 4: "hazard", 5: "hazard",
              6: "dark", 7: "dark", 8: "dark"}
        H.lathe(prof, 12, lambda i, j: hm[j], matrix=Matrix.Translation((cx, cy, 0)))
        H.lathe([(0.0, 9.5), (2.0, 9.25), (3.8, 8.7), (4.5, 8.2), (0.0, 8.2)], 12,
                lambda i, j: "ore", matrix=Matrix.Translation((cx, cy, 0)))
        for k in range(7):
            a = rng.uniform(0, 2 * math.pi)
            rr = rng.uniform(0.0, 3.2)
            H.rock(V((cx + rr * math.cos(a), cy + rr * math.sin(a), 9.3 - rr * 0.18)),
                   rng.uniform(0.5, 1.0), "ore", rng)
        # legs from the rim down to the crusher deck
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            top = V((cx + 4.7 * math.cos(a), cy + 4.7 * math.sin(a), 8.8))
            bot = V((cx + 3.6 * math.cos(a), cy + 3.6 * math.sin(a), -3.5))
            H.beam(bot, top, 0.5, 0.5, "dark")
        H.box(V((cx, cy, -1.0)), (5.0, 5.0, 5.0), "hull", bevel=0.06)
        H.box(V((cx, cy, 0.6)), (5.1, 5.1, 0.6), "orange", bevel=0.0)
        H.box(V((cx, cy, -4.0)), (8.0, 8.0, 1.0), "dark", bevel=0.05)
        # enclosed conveyor up into the smelter front face
        a, b = V((cx, cy + 2.5, 0.0)), V((cx, -13.0, 2.6))
        H.beam(a, b, 1.8, 1.6, "hull2")
        H.beam(a + V((0, 0, 0.9)), b + V((0, 0, 0.9)), 0.6, 0.2, "orange")
        mid = (a + b) / 2
        H.beam(mid - V((0, 0, 0.6)), V((mid.x, mid.y, -3.6)), 0.4, 0.4, "dark")
        for k in (0, 2):
            a2 = k * math.pi / 2 + 0.3
            beacon((cx + 5.1 * math.cos(a2), cy + 5.1 * math.sin(a2), 10.9), 0.55)


# ---------------------------------------------------------------- smelter
def build_smelter(rng):
    x0, x1, y0, y1 = 13.0, 33.0, -13.0, 13.0
    xc, yc = (x0 + x1) / 2, (y0 + y1) / 2
    H.box(V((xc, yc, 4.0)), (x1 - x0, y1 - y0, 20.0), "hull2", bevel=0.05)
    H.box(V((xc, yc, -5.0)), (x1 - x0 + 0.6, y1 - y0 + 0.6, 2.2), "dark", bevel=0.05)
    H.box(V((xc, yc, 11.0)), (x1 - x0 + 0.4, y1 - y0 + 0.4, 1.0), "dark", bevel=0.0)
    H.box(V((xc, yc, 13.4)), (x1 - x0 + 0.5, y1 - y0 + 0.5, 1.2), "hull", bevel=0.05)
    # buttresses on front and side faces
    for k in range(5):
        x = x0 + 1.0 + k * 4.5
        H.box(V((x, y0 - 0.35, 3.5)), (1.0, 0.8, 18.5), "dark", bevel=0.0)
    for k in range(6):
        y = y0 + 1.5 + k * 4.6
        H.box(V((x1 + 0.35, y, 3.5)), (0.8, 1.0, 18.5), "dark", bevel=0.0)
    # front furnace slot: glowing, under a heavy hood
    G.box(V((xc, y0 - 0.1, 6.2)), (16.0, 0.4, 1.8), "glow", bevel=0.0)
    H.box(V((xc, y0 - 0.9, 7.6)), (17.0, 1.8, 0.7), "dark", bevel=0.05)
    H.box(V((xc, y0 - 0.7, 4.8)), (17.0, 1.4, 0.5), "dark", bevel=0.0)
    H.box(V((xc, y0 - 1.7, 8.15)), (17.0, 0.3, 0.4), "hazard", bevel=0.0)
    # side window band (control gallery)
    L.box(V((x1 + 0.03, yc, 9.0)), (0.08, 22.0, 0.6), "window", bevel=0.0)
    L.box(V((xc - 4.0, y0 - 0.03, 1.0)), (8.0, 0.08, 0.5), "window", bevel=0.0)
    # roof: furnace vent (glow under a grille) on the front half
    vx, vy, vw, vd = 19.5, -7.0, 9.0, 8.0
    zr = 14.0
    G.box(V((vx, vy, zr + 0.3)), (vw - 0.6, vd - 0.6, 0.4), "glow", bevel=0.0)
    for sx in (-1, 1):
        H.box(V((vx + sx * vw / 2, vy, zr + 0.8)), (0.8, vd + 0.8, 1.6), "dark", bevel=0.05)
        H.box(V((vx, vy + sx * vd / 2, zr + 0.8)), (vw + 0.8, 0.8, 1.6), "dark", bevel=0.05)
    for k in range(6):
        y = vy - vd / 2 + 0.9 + k * (vd - 1.8) / 5
        H.box(V((vx, y, zr + 1.2)), (vw, 0.3, 0.3), "dark", bevel=0.0)
    H.box(V((vx, vy - vd / 2 - 0.5, zr + 1.7)), (vw + 0.8, 0.3, 0.2), "hazard", bevel=0.0)
    # stack
    sx_, sy_ = 29.0, -7.5
    prof = [(0.0, 14.0), (3.4, 14.0), (3.4, 16.2), (2.8, 17.0), (2.8, 22.6), (2.8, 23.4),
            (2.8, 24.6), (3.2, 25.0), (3.2, 26.0), (2.4, 26.0), (2.4, 25.4), (0.0, 25.4)]
    pm = {0: "dark", 1: "hull2", 2: "dark", 3: "hull", 4: "orange", 5: "hull", 6: "dark",
          7: "dark", 8: "dark", 9: "dark", 10: "dark"}
    H.lathe(prof, 16, lambda i, j: pm[j], matrix=Matrix.Translation((sx_, sy_, 0)))
    G.cyl(V((sx_, sy_, 25.55)), 2.35, 2.35, 0.3, "glow", segs=16)
    for k in range(3):
        a = k * 2 * math.pi / 3 + 0.4
        lamp((sx_ + 3.2 * math.cos(a), sy_ + 3.2 * math.sin(a), 26.3), 0.75, "red")
    # radiator fin bank on the back half of the roof (vertical, edge-on to the camera)
    ry0, ry1 = -1.5, 12.0
    ryc, rl = (ry0 + ry1) / 2, ry1 - ry0
    R.box(V((xc, ryc, zr + 0.5)), (x1 - x0 - 1.0, rl + 1.0, 0.8), "dark", bevel=0.05)
    fins = [15.0 + k * 2.6 for k in range(7)]
    zb, zt = zr + 1.0, zr + 12.0
    for x in fins:
        R.box(V((x, ryc, (zb + zt) / 2)), (0.22, rl, zt - zb), "radiator", bevel=0.0)
        for k in range(6):
            z = zb + 1.0 + k * (zt - zb - 2.0) / 5
            R.box(V((x, ryc, z)), (0.38, rl + 0.1, 0.16), "hull2", bevel=0.0)
        R.box(V((x, ryc, zt + 0.15)), (0.42, rl + 0.3, 0.3), "dark", bevel=0.0)
        for y in (ry0 - 0.2, ry1 + 0.2):
            R.box(V((x, y, (zb + zt) / 2)), (0.42, 0.3, zt - zb), "orange", bevel=0.0)
    for y in (ry0 - 0.9, ry1 + 0.9):
        R.tube(V((fins[0] - 1.0, y, zb + 0.4)), V((fins[-1] + 1.0, y, zb + 0.4)), 0.45, 0.45,
               "hull", segs=8)
        R.tube(V((fins[0] - 1.0, y, zt - 0.6)), V((fins[-1] + 1.0, y, zt - 0.6)), 0.35, 0.35,
               "hull", segs=8)
        for x in fins:
            R.box(V((x, (y + (ry0 if y < 0 else ry1)) / 2, zb + 0.4)), (0.3, 0.9, 0.3), "dark",
                  bevel=0.0)
    for y in (ry0 - 0.9, ry1 + 0.9):
        R.tube(V((fins[-1] + 1.0, y, zb + 0.4)), V((fins[-1] + 1.0, y, zt - 0.6)), 0.3, 0.3,
               "hull", segs=8)
    for x in (fins[0], fins[-1]):
        lamp((x, ry1 + 0.2, zt + 0.55), 0.6)
    # roof corner lights
    for x in (x0 + 0.5, x1 - 0.5):
        for y in (y0 + 0.5, y1 - 0.5):
            lamp((x, y, 14.3), 0.9)
    # pipes along the +X side
    for k, z in enumerate((-1.0, 0.4)):
        H.tube(V((x1 + 1.1, y0 + 1.0, z)), V((x1 + 1.1, y1 - 1.0, z)), 0.45, 0.45,
               ("orange", "hull")[k], segs=8)
    for y in (y0 + 3.0, 0.0, y1 - 3.0):
        H.box(V((x1 + 0.8, y, -0.3)), (1.0, 0.4, 2.4), "dark", bevel=0.0)


# ---------------------------------------------------------------- fabrication hall
def build_hall(rng):
    x0, x1, y0, y1 = -32.0, 10.0, 8.0, 26.0
    xc, yc = (x0 + x1) / 2, (y0 + y1) / 2
    w, d = x1 - x0, y1 - y0
    H.box(V((xc, yc, 3.5)), (w, d, 17.0), "hull", bevel=0.05)
    H.box(V((xc, yc, -4.6)), (w + 0.6, d + 0.6, 1.4), "dark", bevel=0.05)
    H.box(V((xc, yc, 12.6)), (w + 0.4, d + 0.4, 1.2), "hull2", bevel=0.05)
    H.box(V((xc + 1.0, yc, 14.2)), (w - 4.0, 6.0, 2.0), "hull", bevel=0.05)
    for sy in (-1, 1):
        H.box(V((xc + 1.0, yc + sy * 3.05, 15.3)), (w - 3.6, 0.4, 0.3), "dark", bevel=0.0)
    for sy in (-1, 1):
        L.box(V((xc + 1.0, yc + sy * 3.02, 14.3)), (w - 6.0, 0.08, 0.8), "window", bevel=0.0)
    # roof ribs and wall buttresses
    for k in range(8):
        x = x0 + 2.0 + k * (w - 4.0) / 7
        H.box(V((x, yc, 13.3)), (0.7, d + 0.6, 0.4), "dark", bevel=0.0)
        for y in (y0 - 0.35, y1 + 0.35):
            H.box(V((x, y, 3.5)), (1.0, 0.8, 16.6), "dark", bevel=0.0)
    for y, sgn in ((y0 - 0.03, -1), (y1 + 0.03, 1)):
        L.box(V((xc, y, 9.4)), (w - 2.0, 0.08, 0.6), "window", bevel=0.0)
    # wall panel variation: MLI blankets and grey service bays
    for k in range(3):
        x = x1 - 5.5 - k * 6.0
        H.box(V((x, y0 - 0.25, 2.0)), (4.4, 0.5, 6.0), "mli", bevel=0.08)
    H.box(V((x0 - 0.3, yc, 3.0)), (0.6, d - 4.0, 12.0), "mli", bevel=0.08)
    H.box(V((x0 - 0.65, yc, 3.0)), (0.2, d - 3.6, 0.6), "orange", bevel=0.0)
    L.box(V((x0 - 0.78, yc, 8.6)), (0.08, d - 4.0, 0.6), "window", bevel=0.0)
    # big fabrication door to the container yard
    dx, dw = -21.0, 12.0
    H.box(V((dx, y0 - 0.3, 1.5)), (dw, 0.6, 11.0), "dark", bevel=0.0)
    for k in range(5):
        H.box(V((dx, y0 - 0.65, -3.0 + 2.2 * (k + 0.5))), (dw - 0.6, 0.15, 0.15), "hull2", bevel=0.0)
    H.box(V((dx, y0 - 0.5, 7.6)), (dw + 1.6, 1.0, 1.0), "hazard", bevel=0.0)
    for sx in (-1, 1):
        H.box(V((dx + sx * (dw / 2 + 0.4), y0 - 0.5, 2.2)), (0.8, 1.0, 11.8), "hazard", bevel=0.0)
        lamp((dx + sx * (dw / 2 + 0.4), y0 - 1.1, 8.4), 0.7)
    # gantry cranes riding rails on the roof edges
    for y in (y0 + 0.6, y1 - 0.6):
        H.box(V((xc, y, 13.6)), (w, 0.8, 0.8), "dark", bevel=0.0)
    for gx, ty in ((-24.0, 13.0), (-3.0, 21.0)):
        for y in (y0 + 0.6, y1 - 0.6):
            H.box(V((gx, y, 14.3)), (3.0, 1.4, 0.8), "hull2", bevel=0.08)
            for sx in (-1, 1):
                H.beam(V((gx + sx * 1.1, y, 14.6)), V((gx, y, 17.6)), 0.5, 0.5, "orange")
        H.box(V((gx, yc, 18.2)), (1.6, d + 0.4, 1.4), "orange", bevel=0.05)
        for y in (y0 + 0.6, y1 - 0.6):
            H.box(V((gx, y, 18.2)), (1.7, 1.4, 1.5), "hazard", bevel=0.0)
            lamp((gx, y, 19.15), 0.7)
        H.box(V((gx, ty, 17.4)), (2.6, 2.6, 1.6), "hull2", bevel=0.08)
        H.box(V((gx, ty, 16.5)), (1.4, 1.4, 0.4), "dark", bevel=0.0)
    # roof corner lights
    for x in (x0 + 0.6, x1 - 0.6):
        for y in (y0 + 0.6, y1 - 0.6):
            lamp((x, y, 13.5), 0.9)
    # pipe bundle along the front wall, smelter -> west end
    for k, (z, mat, r) in enumerate(((9.9, "hull", 0.45), (10.9, "orange", 0.4),
                                     (11.8, "hull2", 0.35))):
        H.tube(V((x1 + 3.0, y0 - 1.3, z)), V((x0 + 1.0, y0 - 1.3, z)), r, r, mat, segs=8)
    for k in range(7):
        x = x1 - 2.0 - k * 6.4
        H.box(V((x, y0 - 0.9, 10.9)), (0.4, 1.4, 3.0), "dark", bevel=0.0)
    # conduit block bridging the hall and the smelter
    H.box(V((11.5, 10.5, 4.0)), (3.6, 4.0, 6.0), "dark", bevel=0.05)
    H.box(V((11.5, 10.5, 7.3)), (3.8, 4.2, 0.6), "orange", bevel=0.0)
    # link port: airlock module + collar flange at corridor height
    lx, ly, lz = LINK_POS
    H.box(V((lx, y1 + 1.5, lz)), (9.0, 3.0, 9.0), "hull2", bevel=0.06)
    H.box(V((lx, y1 + 1.5, lz + 4.7)), (9.4, 3.2, 0.4), "orange", bevel=0.0)
    H.cyl(V((lx, ly - 0.4, lz)), 3.8, 3.8, 0.8, "dark", segs=12, axis_rot=ALONG_Y)
    H.cyl(V((lx, ly - 0.05, lz)), 3.2, 3.2, 0.1, "hazard", segs=12, axis_rot=ALONG_Y)
    for sx in (-1, 1):
        for sz in (-1, 1):
            lamp((lx + sx * 4.2, y1 + 3.0, lz + sz * 4.2), 0.7)


# ---------------------------------------------------------------- tanks + pipes (back right)
def build_tanks(rng):
    specs = (((18.5, 20.5, -5.0), 3.3, 15.0, "mli_gold"), ((26.5, 19.0, -5.0), 3.6, 16.0, "hull"),
             ((24.0, 26.5, -5.0), 2.8, 13.0, "mli_gold"))
    for c, r, h, mat in specs:
        tank(H, c, r, h, mat)
        H.cyl(V((c[0], c[1], c[2] - 0.6)), r * 0.85, r * 0.85, 1.2, "dark", segs=12)
        beacon((c[0], c[1], c[2] + h + 0.5), 0.5)
        # feed pipe into the smelter back face
        H.tube(V((c[0], c[1] - r + 0.3, 0.0)), V((c[0], 13.0, 0.0)), 0.45, 0.45, "hull2", segs=8)
    H.box(V((22.5, 21.5, -5.6)), (14.0, 12.0, 1.0), "dark", bevel=0.05)
    # cross pipe to the hall
    H.tube(V((15.2, 20.5, 4.0)), V((10.0, 20.5, 4.0)), 0.5, 0.5, "orange", segs=8)
    H.tube(V((20.7, 26.5, 2.0)), V((10.0, 26.5 - 1.0, 2.0)), 0.4, 0.4, "hull", segs=8)


# ---------------------------------------------------------------- container yard
def build_yard(rng):
    x0, x1, y0, y1 = -33.0, -12.0, -21.0, 6.0
    xc, yc = (x0 + x1) / 2, (y0 + y1) / 2
    H.box(V((xc, yc, -3.75)), (x1 - x0, y1 - y0, 1.5), "pad", bevel=0.05)
    H.box(V((xc, y0 - 0.2, -2.95)), (x1 - x0, 0.6, 0.12), "hazard", bevel=0.0)
    H.box(V((x0 + 0.3, yc, -2.95)), (0.6, y1 - y0, 0.12), "hazard", bevel=0.0)
    for x in (x0 + 0.6, x1 - 0.6):
        H.box(V((x, yc, -2.8)), (0.8, y1 - y0, 0.4), "dark", bevel=0.0)
    # racks of finished-part containers: 3 blocks x 2 columns x 4 bays x 3 tiers
    cw, cl, ch = 2.6, 6.0, 2.6
    bays = [-17.6, -11.2, -4.8, 1.6]
    tiers = [-3.0 + 0.3 + k * (ch + 0.35) for k in range(3)]
    cols = ["orange", "hull", "hull2", "hull", "orange", "mli_gold", "hull2"]
    for bx in (-29.0, -22.5, -16.0):
        xs = (bx - 1.45, bx + 1.45)
        top = tiers[-1] + ch + 0.2
        for px in (bx - 2.9, bx, bx + 2.9):
            for k in range(len(bays) + 1):
                py = bays[0] - 3.2 + k * 6.4
                H.box(V((px, py, (-3.0 + top) / 2)), (0.3, 0.3, top + 3.0), "dark", bevel=0.0)
        for z in tiers:
            for px in (bx - 2.9, bx + 2.9):
                H.box(V((px, (bays[0] + bays[-1]) / 2, z - 0.1)),
                      (0.25, bays[-1] - bays[0] + 6.4, 0.2), "dark", bevel=0.0)
        for px in (bx - 2.9, bx + 2.9):
            H.box(V((px, (bays[0] + bays[-1]) / 2, top)), (0.35, bays[-1] - bays[0] + 6.6, 0.3),
                  "dark", bevel=0.0)
        for k in range(len(bays) + 1):
            H.box(V((bx, bays[0] - 3.2 + k * 6.4, top)), (6.1, 0.3, 0.3), "dark", bevel=0.0)
        for y in bays:
            for x in xs:
                for t, z in enumerate(tiers):
                    if rng.random() < (0.12 + 0.12 * t):
                        continue
                    mat = rng.choice(cols)
                    H.box(V((x, y, z + ch / 2)), (cw, cl, ch), mat, bevel=0.04)
                    H.box(V((x, y, z + ch / 2)), (cw + 0.06, 0.3, ch + 0.06), "dark", bevel=0.0)
        lamp((bx, bays[-1] + 3.3, top + 0.4), 0.6)
    # yard gantry crane: legs on the rails, girder across the yard
    gy = -7.5
    gz = 15.0
    for x in (x0 + 0.6, x1 - 0.6):
        H.box(V((x, gy, -2.3)), (1.4, 7.0, 0.8), "hull2", bevel=0.08)
        for sy in (-1, 1):
            H.beam(V((x, gy + sy * 3.0, -2.0)), V((x, gy + sy * 0.5, gz)), 0.7, 0.7, "orange",
                   up=V((1, 0, 0)))
        H.beam(V((x, gy - 1.9, 5.0)), V((x, gy + 1.9, 5.0)), 0.4, 0.4, "dark")
        H.box(V((x, gy, gz + 0.9)), (1.8, 2.2, 1.8), "hazard", bevel=0.0)
        beacon((x, gy, gz + 2.3), 0.6)
    H.box(V((xc, gy, gz + 1.0)), (x1 - x0 + 0.6, 1.6, 1.6), "orange", bevel=0.05)
    H.box(V((xc, gy + 1.0, gz + 1.9)), (x1 - x0 - 1.0, 0.3, 0.2), "dark", bevel=0.0)
    tx = -20.5
    H.box(V((tx, gy, gz)), (3.0, 3.0, 1.6), "hull2", bevel=0.08)
    sz = 7.4
    for sx in (-1, 1):
        for sy in (-1, 1):
            H.beam(V((tx + sx * 0.9, gy + sy * 0.9, gz - 0.8)),
                   V((tx + sx * 1.0, gy + sy * 2.6, sz + 0.25)), 0.08, 0.08, "dark")
    H.box(V((tx, gy, sz + 0.2)), (2.8, 6.2, 0.4), "dark", bevel=0.0)
    H.box(V((tx, gy, sz - ch / 2)), (cw, cl, ch), "orange", bevel=0.04)


def build_factory():
    global H, R, G, L
    rng = random.Random(5150)
    build_materials()
    H = parts.PanelPart("factory_hull", MATS)
    R = parts.PanelPart("factory_radiators", MATS)
    G = parts.PanelPart("factory_furnace_glow", MATS)
    L = parts.PanelPart("factory_lights", MATS)
    for b in (build_frame, build_dock, build_transfer, build_hoppers, build_smelter,
              build_hall, build_tanks, build_yard):
        b(rng)
    root = parts.make_root("factory", size=10)
    objs = [p.finish(root) for p in (H, R, G, L)]
    for o in objs[2:]:   # flat emissive meshes: no atlas, no panel layer
        o.data.uv_layers.remove(o.data.uv_layers["panel"])
    for name, pos, rz in (("dock_point", DOCK_POS, math.pi), ("spawn_point", SPAWN_POS, math.pi),
                          ("link_point", LINK_POS, 0.0)):
        parts.add_empty(name, root, pos, rot_z=rz, size=4)
    return root, objs


# ---------------------------------------------------------------- textures
def texture_factory(objs, others):
    """Bake one 2048 atlas for hull + radiators (station surface kinds)."""
    st.ATLAS_RES = ATLAS_RES
    st.KINDS.update(EXTRA_KINDS)
    atlas_keys = [k for k in st.KINDS if k in MATS]
    atlas_mats = {MATS[k] for k in atlas_keys}
    st.unwrap_atlas(objs, atlas_mats)
    st.setup_cycles(8)
    masks = st.new_image("factory_masks", ATLAS_RES, True)
    bms = {}
    for k in atlas_keys:
        nb = st.NB(MATS[k])
        geo = nb.n("ShaderNodeNewGeometry")
        aon = nb.n("ShaderNodeAmbientOcclusion", samples=16)
        aon.inputs["Distance"].default_value = 0.8
        aof = nb.n("ShaderNodeAmbientOcclusion", samples=16)
        aof.inputs["Distance"].default_value = 4.0
        bev = nb.n("ShaderNodeBevel", samples=8)
        bev.inputs["Radius"].default_value = 0.2
        edge = nb.m("MULTIPLY", nb.inv(nb.v("DOT_PRODUCT", bev.outputs["Normal"],
                                            geo.outputs["Normal"])), 14.0, clamp=True)
        col = nb.comb(aon.outputs["AO"], aof.outputs["AO"], edge)
        bm = st.BakeMat(MATS[k], dict(masks=col), nb)
        bm.set_pass("masks", masks)
        bms[k] = bm
    st.bake(objs, "EMIT", 16, masks)

    albedo = st.new_image("factory_albedo", ATLAS_RES, False)
    mr = st.new_image("factory_mr", ATLAS_RES, True)
    normal = st.new_image("factory_normal", ATLAS_RES, True)
    for i, k in enumerate(atlas_keys):
        nb = st.NB(MATS[k])
        outs = st.build_surface(nb, k, st.KINDS[k], masks, i + 1, [(0.0, -18.0)])
        bms[k] = st.BakeMat(MATS[k], outs, nb)
    for name, img, kind in (("albedo", albedo, "EMIT"), ("mr", mr, "EMIT"),
                            ("normal", normal, "NORMAL")):
        for bm in bms.values():
            bm.set_pass(name, img)
        st.bake(objs, kind, 8, img)
    p_alb = st.save_image(albedo, "factory_albedo.jpg", "JPEG", 92)
    p_mr = st.save_image(mr, "factory_mr.png", "PNG")
    p_nrm = st.save_image(normal, "factory_normal.png", "PNG")

    hull = st.pbr_material("factory_hull", st.load_saved(p_alb, False),
                           st.load_saved(p_mr, True), st.load_saved(p_nrm, True))
    mapping = {m: hull for m in atlas_mats}
    for o in objs:
        st.remap_materials(o, mapping)
        o.data.uv_layers.remove(o.data.uv_layers["panel"])
    for img in (masks, albedo, mr, normal):
        bpy.data.images.remove(img)
    for m in atlas_mats:
        if m.users == 0:
            bpy.data.materials.remove(m)


# ---------------------------------------------------------------- previews
def previews():
    target = (0.0, -2.0, 4.0)
    common.setup_preview(cam_loc=(-70, -105, 105), cam_target=target, ortho_scale=100,
                         res=(1600, 1200), key_dir=(-0.6, -0.35, 0.7), key_energy=3.5)
    common.render(os.path.join(common.PREVIEW_DIR, "factory_preview.png"))
    scene = bpy.context.scene
    cam = scene.camera
    cam.location = (0, 0, 150)
    cam.rotation_euler = (0, 0, 0)
    cam.data.ortho_scale = 92
    scene.render.resolution_x, scene.render.resolution_y = 1200, 1200
    common.render(os.path.join(common.PREVIEW_DIR, "factory_top.png"))
    # close-up for inspection: perspective over the yard toward the smelter
    cam.data.type = "PERSP"
    cam.data.lens = 30
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1000
    cam.location = (-42.0, -50.0, 34.0)
    tgt = Vector((8.0, -4.0, 4.0))
    cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
    common.render(os.path.join(common.PREVIEW_DIR, "factory_closeup.png"))


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_factory()
    if "--no-textures" not in argv:
        texture_factory(objs[:2], objs[2:])
    total = 0
    for o in objs:
        tris = sum(len(pl.vertices) - 2 for pl in o.data.polygons)
        total += tris
        bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
        lo = [min(v[i] for v in bb) for i in range(3)]
        hi = [max(v[i] for v in bb) for i in range(3)]
        rad = max(math.hypot(v.co.x, v.co.y) for v in o.data.vertices)
        print(f"STAT {o.name} tris={tris} mats={[m.name for m in o.data.materials]} "
              f"bbox={[round(c, 2) for c in lo]}..{[round(c, 2) for c in hi]} rxy={rad:.1f}")
    print(f"STAT total tris={total}")
    parts.save_blend(BLEND)
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_mainfile(filepath=BLEND)
    common.export_glb(root, OUT, export_image_format="JPEG", export_image_quality=90)
    if "--no-preview" not in argv:
        previews()


main()
