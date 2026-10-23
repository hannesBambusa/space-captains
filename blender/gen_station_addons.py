"""Generate the home station addon modules (bolt-on Factory, Outfitter, Science Lab).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python /Users/hannesalm/code/games/space-majesty/blender/gen_station_addons.py
  Options after `--`:
    --only=factory,outfitter,science   build a subset
    --no-textures                      flat materials, no Cycles bake
    --no-build                         skip building, only render the preview
    --preview[=/abs/out.png]           after export, import station_home.glb + the addon glbs,
                                       mount factory/outfitter/science in bays 1/2/3 and render
                                       (default blender/previews/station_addons_preview.png)

Output: assets/models/station/addons/addon_{factory,outfitter,science}.glb, textures baked with
the station_textures surface kinds into one 2048 atlas per module (blender/textures/addon_*),
embedded in the glb as JPEG.

Frame (Blender Z up, exported +Y up; Blender -Y = Godot +Z):
  origin = attach point, the face of the mating collar. It meets the station bay collar face
  (gen_station.bay_collar, addon_bay_N empty) flush. Body runs along Blender -Y (Godot +Z,
  radially out from the station), y 0..-45, x within +-15, z within +-12.5.
Hierarchy: addon_<kind> (empty root) -> addon_<kind>_hull, addon_<kind>_lights
  (+ factory_furnace_glow on the factory; factory.gd pulses it by that name).
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
OUT_DIR = os.path.join(common.ROOT, "assets", "models", "station", "addons")
STATION_GLB = os.path.join(common.ROOT, "assets", "models", "station", "station_home.glb")
ATLAS_RES = 2048
LIMITS = (30.0, 25.0, 45.0)       # width (X), height (Z), length (-Y), metres
ALONG_X = parts.ALONG_X
OUTWARD = Matrix.Rotation(math.pi / 2, 4, "X")   # lathe/cylinder local +Z -> Blender -Y

MATS = {}
EXTRA_KINDS = {
    "radiator": dict(panel=(0.6, 3.0), tones=[(0.13, 0.14, 0.15), (0.11, 0.12, 0.13),
                                              (0.15, 0.155, 0.16), (0.12, 0.125, 0.13)],
                     rough=(0.38, 0.12), metal=0.7, seam_dark=0.5, rivets=False,
                     chip=(0.45, 0.45, 0.46), chip_metal=1.0, chip_k=0.6, grime_k=0.6,
                     bleach=0.25),
}

H = G = L = None   # parts: hull (atlas), furnace glow, lights


def build_materials(pre):
    m = common.make_material
    MATS.clear()
    MATS["hull"] = m(f"{pre}_hull_white", (0.78, 0.78, 0.76), roughness=0.45, metallic=0.1)
    MATS["hull2"] = m(f"{pre}_hull_grey", (0.50, 0.52, 0.55), roughness=0.5, metallic=0.15)
    MATS["dark"] = m(f"{pre}_structure_dark", (0.06, 0.065, 0.07), roughness=0.55, metallic=0.5)
    MATS["orange"] = m(f"{pre}_accent_orange", (0.85, 0.28, 0.03), roughness=0.45)
    MATS["hazard"] = m(f"{pre}_hazard", (0.8, 0.55, 0.02), roughness=0.5)
    MATS["mli"] = m(f"{pre}_mli_white", (0.8, 0.8, 0.78), roughness=0.85)
    MATS["mli_gold"] = m(f"{pre}_mli_gold", (0.8, 0.52, 0.15), roughness=0.4, metallic=0.9)
    MATS["pad"] = m(f"{pre}_deck", (0.15, 0.15, 0.16), roughness=0.7, metallic=0.2)
    MATS["radiator"] = m(f"{pre}_radiator", (0.12, 0.13, 0.14), roughness=0.4, metallic=0.7)
    MATS["window"] = m(f"{pre}_window_warm", (1.0, 0.85, 0.6), roughness=0.3,
                       emission=(1.0, 0.78, 0.5), emission_strength=3.0)
    MATS["light"] = m(f"{pre}_light_orange", (1.0, 0.45, 0.1), roughness=0.3,
                      emission=(1.0, 0.42, 0.08), emission_strength=4.0)
    MATS["red"] = m(f"{pre}_light_red", (1.0, 0.12, 0.05), roughness=0.3,
                    emission=(1.0, 0.1, 0.04), emission_strength=4.0)
    MATS["cyan"] = m(f"{pre}_light_cyan", (0.35, 0.8, 1.0), roughness=0.3,
                     emission=(0.3, 0.75, 1.0), emission_strength=3.0)
    MATS["glow"] = m("factory_furnace_glow", (1.0, 0.36, 0.05), roughness=0.4,
                     emission=(1.0, 0.34, 0.05), emission_strength=5.0)


def lamp(pos, s=0.7, mat="light"):
    L.box(V(pos), (s, s, s * 0.6), mat, bevel=0.0)


def beacon(pos, r=0.6, mat="light"):
    p = V(pos)
    H.cyl(p - V((0, 0, 0.5)), 0.22, 0.22, 1.0, "dark", segs=6)
    L.cyl(p + V((0, 0, 0.25)), r, r * 0.8, r * 0.9, mat, segs=8)


def out_m(y, x=0.0, z=0.0):
    """Frame at (x, y, z) with local +Z pointing outward (Blender -Y)."""
    return Matrix.Translation((x, y, z)) @ OUTWARD


def tank_v(c, r, h, mat_body, band="orange"):
    """Vertical tank with domes, base at c.z."""
    x, y, z0 = c
    dome = r * 0.6
    prof = [(0.0, z0)]
    for k in range(1, 4):
        a = math.pi / 2 * k / 3
        prof.append((r * math.sin(a), z0 + dome * (1 - math.cos(a))))
    zb0, zb1 = z0 + dome + (h - 2 * dome) * 0.62, z0 + dome + (h - 2 * dome) * 0.72
    prof += [(r, zb0), (r, zb1)]
    for k in range(0, 4):
        a = math.pi / 2 * k / 3
        prof.append((r * math.cos(a), z0 + h - dome + dome * math.sin(a)))
    prof[-1] = (0.0, z0 + h)
    H.lathe(prof, 14, lambda i, j: band if j == 4 else mat_body,
            matrix=Matrix.Translation((x, y, 0)))


# ---------------------------------------------------------------- shared collar
def mating_collar(neck_len=4.0, neck_r=3.6):
    """Addon half of the docking collar: face at y = 0, flange r 5.4 (same as the station bay
    collar), hazard ring r 3.6..4.6, then a pressurised neck out to y = -(1 + neck_len)."""
    prof = [(0.0, 0.15), (3.4, 0.15), (3.6, 0.0), (4.6, 0.0), (5.4, 0.0), (5.4, 1.0),
            (neck_r, 1.0), (neck_r, 1.0 + neck_len * 0.45), (neck_r, 1.0 + neck_len * 0.6),
            (neck_r, 1.0 + neck_len), (0.0, 1.0 + neck_len)]
    fm = {0: "dark", 1: "dark", 2: "hazard", 3: "hull", 4: "hull2", 5: "dark", 6: "hull2",
          7: "orange", 8: "hull2", 9: "dark"}
    H.lathe(prof, 24, lambda i, j: fm[j], matrix=out_m(0.0), start=math.pi / 24)
    for k in range(4):   # latch blocks, outside the station's latches
        ang = k * math.pi / 2
        H.box(V((math.cos(ang) * 4.9, -0.75, math.sin(ang) * 4.9)), (1.0, 0.7, 1.0), "dark",
              bevel=0.0)
    for k in range(4):   # neck stiffeners
        ang = math.pi / 4 + k * math.pi / 2
        H.beam(V((math.cos(ang) * 4.8, -1.0, math.sin(ang) * 4.8)),
               V((math.cos(ang) * (neck_r + 0.2), -1.0 - neck_len, math.sin(ang) * (neck_r + 0.2))),
               0.4, 0.4, "dark")


# ---------------------------------------------------------------- factory
def build_factory(rng):
    """Smelter + fab line: ore hoppers on -X, radiator wing on +X, smelter with a glowing
    roof vent, front furnace slot and a stack at the outer end."""
    mating_collar(4.0)
    # keel truss under the whole module
    parts.box_truss(H, -4.0, -44.0, 2.0, 1.0, 8, "dark", "dark", chord=0.45, brace=0.28, z0=-8.0)
    # fab hall (y -5..-24)
    y0, y1 = -5.0, -24.0
    yc, ln = (y0 + y1) / 2, y0 - y1
    H.box(V((0, yc, 0.0)), (16.0, ln, 12.0), "hull", bevel=0.05)
    H.box(V((0, yc, 6.4)), (14.5, ln - 1.5, 0.8), "dark", bevel=0.05)
    for k in range(4):
        H.box(V((0, y0 - 2.5 - k * 4.6, 7.0)), (15.0, 0.6, 0.5), "dark", bevel=0.0)
    H.box(V((-3.5, yc + 1.0, 7.4)), (5.0, 9.0, 1.2), "mli", bevel=0.08)
    H.box(V((3.5, yc - 3.0, 7.3)), (4.0, 5.0, 1.0), "hull2", bevel=0.08)
    H.box(V((3.5, yc - 3.0, 7.85)), (4.2, 0.8, 0.1), "orange", bevel=0.0)
    for sx in (-1, 1):
        L.box(V((sx * 8.03, yc, 3.0)), (0.08, ln - 3.0, 0.45), "window", bevel=0.0)
        H.box(V((sx * 8.1, yc, -2.0)), (0.5, ln - 1.0, 0.5), "orange", bevel=0.0)
        for k in range(5):
            H.box(V((sx * 8.3, y0 - 1.0 - k * 4.2, 0.0)), (0.6, 0.8, 12.0), "dark", bevel=0.0)
    H.box(V((0, yc, -6.6)), (16.6, ln + 0.4, 1.4), "dark", bevel=0.05)
    # ore hoppers on the -X side feeding the hall
    for hy in (-9.5, -18.5):
        hx = -11.2
        prof = [(0.0, -3.0), (1.2, -3.0), (1.2, -2.0), (3.3, 4.0), (3.6, 4.0), (3.6, 4.9),
                (3.2, 4.9), (3.0, 4.4), (1.0, -1.4), (0.0, -1.4)]
        hm = {0: "dark", 1: "dark", 2: "hull2", 3: "dark", 4: "hazard", 5: "hazard", 6: "dark",
              7: "dark", 8: "dark"}
        H.lathe(prof, 12, lambda i, j: hm[j], matrix=Matrix.Translation((hx, hy, 0)))
        H.lathe([(0.0, 4.3), (1.5, 4.1), (2.8, 3.6), (0.0, 3.6)], 12, lambda i, j: "pad",
                matrix=Matrix.Translation((hx, hy, 0)))
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            H.beam(V((hx + 3.2 * math.cos(a), hy + 3.2 * math.sin(a), 4.2)),
                   V((hx + 2.2 * math.cos(a), hy + 2.2 * math.sin(a), -5.5)), 0.4, 0.4, "dark")
        H.box(V((hx, hy, -4.5)), (3.4, 3.4, 3.0), "hull2", bevel=0.06)
        H.beam(V((hx + 1.7, hy, -4.0)), V((-8.0, hy, -3.0)), 1.4, 1.4, "hull2")
        beacon((hx - 2.6, hy, 5.6), 0.5)
    # radiator wing on the +X side (horizontal, faces the camera)
    rx0, rx1, ry0, ry1, rz = 9.0, 14.3, -6.0, -27.0, 1.5
    for y in (ry0 - 2.0, (ry0 + ry1) / 2, ry1 + 2.0):
        H.beam(V((8.0, y, rz)), V((rx1, y, rz)), 0.6, 0.5, "dark")
    H.box(V(((rx0 + rx1) / 2, (ry0 + ry1) / 2, rz + 0.35)), (rx1 - rx0, ry0 - ry1, 0.2),
          "radiator", bevel=0.0)
    for k in range(9):
        y = ry0 - 1.0 - k * (ry0 - ry1 - 2.0) / 8
        H.box(V(((rx0 + rx1) / 2, y, rz + 0.5)), (rx1 - rx0, 0.25, 0.14), "hull2", bevel=0.0)
    H.tube(V((rx0 + 0.3, ry0, rz + 0.6)), V((rx0 + 0.3, ry1, rz + 0.6)), 0.35, 0.35, "orange", 8)
    H.tube(V((rx1 - 0.2, ry0, rz + 0.6)), V((rx1 - 0.2, ry1, rz + 0.6)), 0.3, 0.3, "hull", 8)
    lamp((rx1, ry0, rz + 0.9), 0.55, "red")
    lamp((rx1, ry1, rz + 0.9), 0.55, "red")
    # smelter (y -24..-43), taller and darker
    s0, s1 = -24.5, -43.0
    sc, sl = (s0 + s1) / 2, s0 - s1
    H.box(V((0, sc, 0.5)), (20.0, sl, 17.0), "hull2", bevel=0.05)
    H.box(V((0, sc, -8.3)), (20.6, sl + 0.6, 1.6), "dark", bevel=0.05)
    H.box(V((0, sc, 9.3)), (20.5, sl + 0.5, 0.9), "hull", bevel=0.05)
    for k in range(5):
        x = -8.0 + k * 4.0
        H.box(V((x, s1 - 0.35, 0.0)), (0.9, 0.8, 16.0), "dark", bevel=0.0)
    for sx in (-1, 1):
        for k in range(4):
            H.box(V((sx * 10.35, s0 - 2.0 - k * 4.8, 0.0)), (0.8, 1.0, 16.0), "dark", bevel=0.0)
        L.box(V((sx * 10.03, sc, 6.5)), (0.08, sl - 3.0, 0.5), "window", bevel=0.0)
    # front furnace slot on the outer face under a hood
    G.box(V((0, s1 - 0.1, 3.0)), (13.0, 0.4, 1.6), "glow", bevel=0.0)
    H.box(V((0, s1 - 0.9, 4.3)), (14.0, 1.8, 0.6), "dark", bevel=0.05)
    H.box(V((0, s1 - 0.7, 1.8)), (14.0, 1.4, 0.5), "dark", bevel=0.0)
    H.box(V((0, s1 - 1.7, 4.8)), (14.0, 0.3, 0.35), "hazard", bevel=0.0)
    # roof vent: glow under a grille
    zr = 9.75
    vx, vy, vw, vd = -3.5, -30.5, 8.0, 7.0
    G.box(V((vx, vy, zr + 0.25)), (vw - 0.6, vd - 0.6, 0.4), "glow", bevel=0.0)
    for sx in (-1, 1):
        H.box(V((vx + sx * vw / 2, vy, zr + 0.7)), (0.7, vd + 0.7, 1.4), "dark", bevel=0.05)
        H.box(V((vx, vy + sx * vd / 2, zr + 0.7)), (vw + 0.7, 0.7, 1.4), "dark", bevel=0.05)
    for k in range(6):
        H.box(V((vx, vy - vd / 2 + 0.8 + k * (vd - 1.6) / 5, zr + 1.05)), (vw, 0.3, 0.3),
              "dark", bevel=0.0)
    # stack
    sx_, sy_ = 5.0, -37.5
    prof = [(0.0, zr), (2.8, zr), (2.8, zr + 0.8), (2.2, zr + 1.4), (2.2, 10.6), (2.2, 11.2),
            (2.5, 11.4), (2.5, 12.3), (1.9, 12.3), (1.9, 11.9), (0.0, 11.9)]
    pm = {0: "dark", 1: "hull2", 2: "dark", 3: "hull", 4: "orange", 5: "dark", 6: "dark",
          7: "dark", 8: "dark", 9: "dark"}
    H.lathe(prof, 16, lambda i, j: pm[j], matrix=Matrix.Translation((sx_, sy_, 0)))
    G.cyl(V((sx_, sy_, 12.0)), 1.85, 1.85, 0.2, "glow", segs=16)
    # roof radiator fins on the smelter (edge-on, back half)
    for k in range(4):
        x = 2.0 + k * 2.2
        H.box(V((x, -28.0, zr + 1.4)), (0.22, 5.5, 2.4), "radiator", bevel=0.0)
        H.box(V((x, -28.0, zr + 2.55)), (0.4, 5.8, 0.25), "dark", bevel=0.0)
    for x in (-9.5, 9.5):
        for y in (s0 - 0.5, s1 + 0.5):
            lamp((x, y, 10.0), 0.8)
    for x in (-7.5, 7.5):
        lamp((x, y1 + 0.6, 6.8), 0.7)
    # tanks tucked between hall and smelter on -X
    tank_v((-11.5, -27.0, -6.0), 2.2, 9.0, "mli_gold")
    H.tube(V((-11.5, -27.0, -1.0)), V((-9.5, -27.0, -1.0)), 0.4, 0.4, "hull", 8)


# ---------------------------------------------------------------- outfitter
def build_outfitter(rng):
    """Workshop can + open parts deck with racks and a slewing crane arm."""
    mating_collar(3.0)
    # workshop pressure hull (y -4..-20), MLI bands
    def wm(i, j):
        return "mli" if j in (3, 4) else ("hull" if j == 2 else "hull2")
    parts.capsule(H, -20.0, -3.5, 6.0, wm, segs=20, dome0=0.35, dome1=0.25, steps=2)
    for y, mat in ((-8.0, "dark"), (-16.5, "orange")):
        H.cyl(V((0, y, 0)), 6.25, 6.25, 0.8, mat, segs=20, axis_rot=parts.ALONG_Y)
    for sx in (-1, 1):
        L.box(V((sx * 6.05, -11.5, 1.5)), (0.12, 9.0, 0.45), "window", bevel=0.0)
    # roof workshop annex with a big hangar door
    H.box(V((0, -12.0, 6.2)), (8.0, 10.0, 3.4), "hull", bevel=0.06)
    H.box(V((0, -12.0, 8.0)), (8.4, 10.4, 0.4), "hull2", bevel=0.0)
    H.box(V((0, -12.0, 8.25)), (8.6, 1.2, 0.12), "orange", bevel=0.0)
    L.box(V((0, -6.95, 6.2)), (5.0, 0.08, 0.4), "window", bevel=0.0)
    # parts deck (y -19..-43): flat open grid platform
    d0, d1, dz = -19.0, -43.0, -3.0
    dc, dl = (d0 + d1) / 2, d0 - d1
    H.box(V((0, dc, dz)), (26.0, dl, 1.0), "pad", bevel=0.03)
    H.box(V((0, dc, dz - 0.9)), (24.0, dl - 1.0, 0.8), "dark", bevel=0.0)
    for sx in (-1, 1):
        H.box(V((sx * 13.1, dc, dz + 0.1)), (0.4, dl, 1.2), "hazard", bevel=0.0)
    H.box(V((0, d1 - 0.2, dz + 0.1)), (26.4, 0.4, 1.2), "hazard", bevel=0.0)
    parts.box_truss(H, -18.0, -43.0, 6.0, 1.2, 5, "dark", "dark", chord=0.4, brace=0.25,
                    z0=dz - 2.6)
    # racks: open dark frames along both sides holding grey/orange part crates
    for sx in (-1, 1):
        xr = sx * 9.0
        for k in range(4):
            yr = -22.0 - k * 5.0
            for (cx, cy) in ((-1.6, -1.6), (1.6, -1.6), (-1.6, 1.6), (1.6, 1.6)):
                H.beam(V((xr + cx, yr + cy, dz + 0.5)), V((xr + cx, yr + cy, dz + 7.5)),
                       0.3, 0.3, "dark")
            for zz in (dz + 0.7, dz + 4.0):
                H.box(V((xr, yr, zz)), (3.6, 3.6, 0.25), "dark", bevel=0.0)
            for (ax, ay, bx, by) in ((-1.6, -1.6, 1.6, -1.6), (-1.6, 1.6, 1.6, 1.6),
                                     (-1.6, -1.6, -1.6, 1.6), (1.6, -1.6, 1.6, 1.6)):
                H.beam(V((xr + ax, yr + ay, dz + 7.5)), V((xr + bx, yr + by, dz + 7.5)),
                       0.35, 0.35, "orange")
            for lvl, zz in enumerate((dz + 0.8, dz + 4.1)):
                if rng.random() < 0.85:
                    mat = rng.choice(["hull", "orange", "hull", "hull2", "mli_gold", "orange"])
                    h = rng.uniform(2.0, 3.0)
                    H.box(V((xr, yr, zz + h / 2)), (2.9, 2.9, h), mat, bevel=0.08)
            if k % 2 == 0:
                lamp((xr + sx * 1.8, yr, dz + 7.6), 0.5)
    # loose crates and a parts pallet on the centre lane
    for (x, y, w, d, h, mat) in ((0.0, -28.0, 4.0, 2.5, 1.6, "hull"),
                                 (-1.5, -33.5, 2.4, 2.4, 2.2, "orange"),
                                 (1.6, -34.0, 2.0, 3.0, 1.4, "hull2")):
        H.box(V((x, y, dz + 0.5 + h / 2)), (w, d, h), mat, bevel=0.08)
    # thruster/engine part on a cradle: a recognisable "module" being fitted
    H.box(V((0.0, -39.5, dz + 1.0)), (5.0, 3.0, 1.0), "dark", bevel=0.0)
    parts.bell(H, -41.0, 1.8, 3.6, "hull2", "dark", z=dz + 3.2, segs=14)
    # slewing crane: pedestal at the deck root, boom reaching out over the racks
    px, py = -5.0, -21.5
    H.cyl(V((px, py, dz + 3.0)), 1.6, 1.3, 5.0, "hull2", segs=12)
    H.cyl(V((px, py, dz + 5.8)), 1.9, 1.9, 0.8, "orange", segs=12)
    H.box(V((px, py, dz + 7.2)), (3.0, 3.0, 2.2), "hull", bevel=0.08)
    L.box(V((px, py - 1.53, dz + 7.4)), (2.0, 0.08, 0.6), "window", bevel=0.0)
    tip = V((10.0, -34.5, 10.0))
    base = V((px, py, dz + 7.8))
    H.beam(base, tip, 1.0, 1.1, "orange")
    H.beam(base + V((0, 0, 0.9)), tip + V((0, 0, 0.7)), 0.35, 0.35, "dark")
    H.beam(V((px - 1.2, py + 1.2, dz + 8.0)), V((px - 3.4, py + 3.6, dz + 7.0)), 0.8, 0.8, "dark")
    H.box(V((px - 3.6, py + 3.8, dz + 6.8)), (2.0, 2.0, 1.4), "hull2", bevel=0.05)
    H.beam(tip, tip - V((0, 0, 5.0)), 0.12, 0.12, "dark")
    H.box(tip - V((0, 0, 5.4)), (0.8, 0.8, 0.5), "hazard", bevel=0.0)
    H.box(tip - V((0, 0, 6.9)), (3.0, 2.0, 2.2), "orange", bevel=0.08)
    lamp(tip + V((0, 0, 0.7)), 0.6, "red")
    # deck corner beacons and a small parts dock sign on the outer edge
    for x in (-12.5, 12.5):
        beacon((x, d1 + 0.6, dz + 1.2), 0.5)
    for sx in (-1, 1):
        lamp((sx * 12.5, d0 - 0.6, dz + 0.7), 0.5, "window")


# ---------------------------------------------------------------- science
def build_science(rng):
    """Lab can with a cross module, observatory drum, telescope, sensor mast and a big dish."""
    mating_collar(3.0, neck_r=3.2)

    def lm(i, j):
        return "mli" if j in (3, 4) else ("hull" if j == 2 else "hull2")
    parts.capsule(H, -24.0, -3.5, 5.2, lm, segs=20, dome0=0.3, dome1=0.25, steps=2)
    for y, mat in ((-6.5, "dark"), (-21.0, "orange")):
        H.cyl(V((0, y, 0)), 5.45, 5.45, 0.7, mat, segs=20, axis_rot=parts.ALONG_Y)
    for sx in (-1, 1):
        L.box(V((sx * 5.25, -9.0, 1.2)), (0.12, 7.0, 0.4), "window", bevel=0.0)
    # cross module along X at y -15: lab wings with gold MLI end caps
    cx_prof = [(0.0, -13.5), (2.0, -13.3), (3.2, -12.6), (3.2, -10.5), (3.4, -10.2),
               (3.4, 10.2), (3.2, 10.5), (3.2, 12.6), (2.0, 13.3), (0.0, 13.5)]
    cxm = {0: "mli_gold", 1: "mli_gold", 2: "hull2", 3: "dark", 4: "mli", 5: "dark",
           6: "hull2", 7: "mli_gold", 8: "mli_gold"}
    H.lathe(cx_prof, 16, lambda i, j: cxm[j], matrix=Matrix.Translation((0, -15.0, 0)) @ ALONG_X)
    for sx in (-1, 1):
        H.cyl(V((sx * 7.5, -15.0, 0)), 3.6, 3.6, 0.6, "orange", segs=16, axis_rot=ALONG_X)
        L.box(V((sx * 9.0, -15.0, 3.42)), (4.0, 0.8, 0.08), "cyan", bevel=0.0)
    # small radiator fins on the cross module ends (edge-on, vertical)
    for sx in (-1, 1):
        H.box(V((sx * 11.0, -15.0, -5.8)), (3.0, 0.2, 5.0), "radiator", bevel=0.0)
        H.beam(V((sx * 11.0, -15.0, -3.0)), V((sx * 11.0, -15.0, -3.3)), 0.5, 0.5, "dark")
    # observatory drum (y -25..-33)
    dc = -29.0
    prof = [(0.0, -4.5), (6.0, -4.5), (7.0, -3.5), (7.0, -1.0), (7.0, 1.0), (7.0, 2.6),
            (6.0, 3.6), (4.2, 3.9), (0.0, 3.9)]
    dm = {0: "dark", 1: "hull2", 2: "hull", 3: "window", 4: "hull", 5: "hull2", 6: "dark",
          7: "dark"}
    H.lathe(prof, 8, lambda i, j: dm[j], matrix=Matrix.Translation((0, dc, 0)),
            start=math.pi / 8)
    parts.box_truss(H, -23.0, -31.0, 1.6, 1.6, 2, "dark", "dark", chord=0.35, brace=0.22)
    # telescope: long tube on a fork, raked up and outward
    tb = V((0.0, dc - 1.0, 5.5))
    td = V((0.0, -0.6, 0.8)).normalized()
    H.box(V((0.0, dc, 4.4)), (5.0, 3.0, 1.0), "hull2", bevel=0.06)
    for sx in (-1, 1):
        H.box(V((sx * 2.3, dc - 0.5, 5.6)), (0.6, 1.6, 2.6), "dark", bevel=0.0)
    t0, t1 = tb - td * 3.0, tb + td * 6.3
    H.tube(t0, t1, 1.7, 1.7, "hull", segs=16)
    H.tube(t1 - td * 0.6, t1 + td * 0.2, 1.95, 1.95, "dark", segs=16)
    H.tube(t0 + td * 2.2, t0 + td * 3.0, 1.85, 1.85, "orange", segs=16)
    H.tube(t0 - td * 0.2, t0 + td * 0.5, 1.2, 1.2, "dark", segs=12)
    # sensor mast on the lab can (tall, thin, reads as a spike)
    mx, my = 0.0, -7.0
    H.cyl(V((mx, my, 6.0)), 0.9, 0.9, 1.6, "hull2", segs=10)
    H.cyl(V((mx, my, 9.3)), 0.35, 0.22, 5.4, "dark", segs=8)
    for k, z in enumerate((8.0, 10.2)):
        H.beam(V((mx - 2.2, my, z)), V((mx + 2.2, my, z)), 0.18, 0.18, "dark")
        H.box(V((mx + 2.2, my, z)), (0.5, 0.5, 0.5), "hull", bevel=0.0)
        H.box(V((mx - 2.2, my, z)), (0.4, 0.8, 0.8), "hull2", bevel=0.0)
    lamp((mx, my, 11.9), 0.5, "red")
    parts.dish(H, V((mx, my + 1.2, 8.8)), 1.1, V((0.6, 0.5, 0.6)), "hull", "dark", depth=0.35)
    # big dish at the outer end on a pylon, facing up and out
    dy = -38.5
    H.box(V((0.0, -34.5, -2.0)), (4.0, 3.0, 3.0), "hull2", bevel=0.06)
    H.beam(V((0.0, -35.0, -1.0)), V((0.0, dy, 0.5)), 1.2, 1.2, "dark")
    H.cyl(V((0.0, dy, 1.2)), 1.3, 1.0, 1.6, "hull2", segs=12)
    nrm = V((0.0, -0.5, 1.0)).normalized()
    q = nrm.to_track_quat("Z", "Y").to_matrix().to_4x4()
    dm_ = Matrix.Translation((0.0, dy, 2.6)) @ q
    dish_prof = [(0.0, 0.0), (1.8, 0.15), (3.6, 0.6), (5.4, 1.4), (5.7, 1.45), (5.5, 1.2),
                 (3.6, 0.35), (1.4, -0.2), (0.0, -0.3)]
    dmats = {0: "hull", 1: "hull", 2: "hull", 3: "orange", 4: "dark", 5: "dark", 6: "dark",
             7: "dark"}
    H.lathe(dish_prof, 24, lambda i, j: dmats[j], matrix=dm_)
    tip = dm_ @ V((0, 0, 4.2))
    for k in range(3):
        a = k * 2 * math.pi / 3
        H.beam(dm_ @ V((4.8 * math.cos(a), 4.8 * math.sin(a), 1.2)), tip, 0.18, 0.18, "dark")
    H.box(tip, (0.7, 0.7, 0.7), "hull2", bevel=0.0)
    lamp(tip + nrm * 0.5, 0.45, "cyan")
    # lab lights
    for y in (-5.0, -22.0):
        lamp((0.0, y, 5.0), 0.5, "light")
    for sx in (-1, 1):
        lamp((sx * 7.0, dc, 2.8), 0.6, "cyan")


KINDS = {
    "factory": build_factory,
    "outfitter": build_outfitter,
    "science": build_science,
}
SEEDS = {"factory": 7101, "outfitter": 7202, "science": 7303}


# ---------------------------------------------------------------- textures
def texture_addon(pre, objs):
    """One atlas for the hull mesh (station surface kinds, same pipeline as gen_factory)."""
    st.ATLAS_RES = ATLAS_RES
    st.KINDS.update(EXTRA_KINDS)
    atlas_keys = [k for k in st.KINDS if k in MATS]
    atlas_mats = {MATS[k] for k in atlas_keys}
    st.unwrap_atlas(objs, atlas_mats)
    st.setup_cycles(8)
    masks = st.new_image(f"{pre}_masks", ATLAS_RES, True)
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
    albedo = st.new_image(f"{pre}_albedo", ATLAS_RES, False)
    mr = st.new_image(f"{pre}_mr", ATLAS_RES, True)
    normal = st.new_image(f"{pre}_normal", ATLAS_RES, True)
    for i, k in enumerate(atlas_keys):
        nb = st.NB(MATS[k])
        outs = st.build_surface(nb, k, st.KINDS[k], masks, i + 11, [(0.0, -31.0)])
        bms[k] = st.BakeMat(MATS[k], outs, nb)
    for name, img, kind in (("albedo", albedo, "EMIT"), ("mr", mr, "EMIT"),
                            ("normal", normal, "NORMAL")):
        for bm in bms.values():
            bm.set_pass(name, img)
        st.bake(objs, kind, 8, img)
    p_alb = st.save_image(albedo, f"{pre}_albedo.jpg", "JPEG", 92)
    p_mr = st.save_image(mr, f"{pre}_mr.png", "PNG")
    p_nrm = st.save_image(normal, f"{pre}_normal.png", "PNG")
    hull = st.pbr_material(f"{pre}_hull", st.load_saved(p_alb, False),
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


# ---------------------------------------------------------------- build / export
def build_one(kind, textures):
    global H, G, L
    pre = f"addon_{kind}"
    common.reset_scene()
    build_materials(pre)
    rng = random.Random(SEEDS[kind])
    H = parts.PanelPart(f"{pre}_hull", MATS)
    G = parts.PanelPart("factory_furnace_glow", MATS)
    L = parts.PanelPart(f"{pre}_lights", MATS)
    KINDS[kind](rng)
    root = parts.make_root(pre, size=6)
    objs = [H.finish(root)]
    flat = [p.finish(root) for p in ((G, L) if kind == "factory" else (L,))]
    for o in flat:   # flat emissive meshes: no atlas, no panel layer
        o.data.uv_layers.remove(o.data.uv_layers["panel"])
    if textures:
        texture_addon(pre, objs)
    allo = objs + flat
    lo = [min((o.matrix_world @ V(c))[i] for o in allo for c in o.bound_box) for i in range(3)]
    hi = [max((o.matrix_world @ V(c))[i] for o in allo for c in o.bound_box) for i in range(3)]
    dims = (hi[0] - lo[0], hi[2] - lo[2], -lo[1])
    tris = 0
    for o in allo:
        t = sum(len(pl.vertices) - 2 for pl in o.data.polygons)
        tris += t
        print(f"STAT {o.name} tris={t} mats={[m.name for m in o.data.materials]}")
    ok = (all(d <= lim + 1e-3 for d, lim in zip(dims, LIMITS)) and hi[1] <= 0.15
          and max(abs(lo[0]), abs(hi[0])) <= 15.0 and max(abs(lo[2]), abs(hi[2])) <= 12.5)
    print(f"STAT {pre} total tris={tris} bbox x {lo[0]:.2f}..{hi[0]:.2f} "
          f"y {lo[1]:.2f}..{hi[1]:.2f} z {lo[2]:.2f}..{hi[2]:.2f} "
          f"-> W {dims[0]:.2f} x H {dims[1]:.2f} x L {dims[2]:.2f} limits_ok={ok}")
    blend = os.path.join(common.ROOT, "blender", f"{pre}.blend")
    parts.save_blend(blend)
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_mainfile(filepath=blend)
    common.export_glb(root, os.path.join(OUT_DIR, f"{pre}.glb"), export_image_format="JPEG",
                      export_image_quality=90)


# ---------------------------------------------------------------- preview
def preview(out_path):
    """Station with factory / outfitter / science mounted on bays 1 / 2 / 3."""
    common.reset_scene()
    bpy.ops.import_scene.gltf(filepath=STATION_GLB)
    bays = {o.name: o for o in bpy.data.objects if o.name.startswith("addon_bay_")}
    print("PREVIEW bays", sorted(bays))
    station_meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.context.view_layer.update()
    for n, kind in ((1, "factory"), (2, "outfitter"), (3, "science")):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(OUT_DIR, f"addon_{kind}.glb"))
        new = [o for o in bpy.data.objects if o not in before]
        root = next(o for o in new if o.parent is None)
        root.matrix_world = bays[f"addon_bay_{n}"].matrix_world.copy()
    bpy.context.view_layer.update()
    # clearance: station vertices inside any bay's 30 x 25 x 45 module volume
    for name in sorted(bays):
        inv = bays[name].matrix_world.inverted()
        hits = {}
        for o in station_meshes:
            mw = o.matrix_world
            n_in = 0
            for v in o.data.vertices:
                q = inv @ (mw @ v.co)
                if abs(q.x) < 15.0 and 0.05 < -q.y < 45.0 and abs(q.z) < 12.5:
                    n_in += 1
            if n_in:
                hits[o.name] = n_in
        print(f"CLEARANCE {name} verts inside module volume: {hits or 'none'}")
    ring = bpy.data.objects.get("station_ring")
    if ring:
        rmax = max(math.hypot(*(ring.matrix_world @ v.co)[:2]) for v in ring.data.vertices)
        print(f"CLEARANCE station_ring max radius {rmax:.2f} (bay faces at r 47)")
    common.setup_preview(cam_loc=(-20, -190, 250), cam_target=(-15, 5, 0), ortho_scale=215,
                         res=(1600, 1200), key_dir=(-0.6, -0.35, 0.7), key_energy=3.5)
    common.render(out_path)


def main():
    argv = parts.script_args(sys.argv)
    only = next((a.split("=", 1)[1].split(",") for a in argv if a.startswith("--only=")),
                list(KINDS))
    if "--no-build" not in argv:
        for kind in only:
            build_one(kind, "--no-textures" not in argv)
    pv = next((a for a in argv if a.startswith("--preview")), None)
    if pv:
        path = pv.split("=", 1)[1] if "=" in pv else os.path.join(
            common.PREVIEW_DIR, "station_addons_preview.png")
        preview(path)


main()
