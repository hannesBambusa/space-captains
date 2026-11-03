"""Generate the planet raider dropship .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_dropship.py
  Add `-- --no-preview` to skip the PNG renders, `-- --no-textures` to skip the atlas bake
  (fast shape iteration: flat colours only).

Design: rugged military/industrial atmospheric dropship that drops into a planet's air,
grabs cargo and climbs back out. Lofted 10-sided lifting-body fuselage with a flat belly
and a drooping beak nose, a raised wrap-around flight deck canopy, a dorsal spine with
heat-exchanger grilles, intakes and piping. Swept stub wings carry two round lift-fan
nacelles (ducted fan on top, louvred lift nozzle underneath). Twin canted tail fins, a
boxy thrust block with two main bells. Underneath: dark ceramic heat tiles on the belly,
chines, nose cap and every leading edge (scorched from re-entry), four landing legs
folded flat in the chines, two pod clamp yokes, a chin ball turret with twin cannons and
a big ribbed cargo pod. Grey worn paint with orange markings, hazard trim, stencils.

Layout (Blender Z up, exported +Y up). Ship centre at origin on the play plane z=0.
The nose points along Blender +Y = Godot -Z (forward), like every other ship.
  length ~13.4 m (bell exits y -6.6 .. gun muzzles y 6.75), width ~7.9 m over the
  nacelles, height ~6.6 m (pod bottom z -3.3 .. tail fin tips z ~3.3).
Hierarchy: dropship (empty root) -> dropship_hull, dropship_pod, engine_glow,
  muzzle_l, muzzle_r (empties).
engine_glow has its origin on the bell exit plane (Blender y = NOZZLE_Y), plume along
Godot local +Z (scale Z to lengthen). dropship_pod has its origin at the clamp plane
(top of the pod, Blender z = POD_TOP), so Godot can lower or hide it; the hull is
complete without it (tiled belly, open clamp yokes, folded legs).
Textures: one 2048 worn atlas (worn_kit / station_textures bake, kinds re-scaled to ship
size here, plus "tile" heat tiles and "temper" heat-tinted nozzle metal), saved as
blender/textures/dropship_{albedo,mr,normal}.jpg, material "dropship_hull". Emissive
materials stay flat, named "dropship_*".
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
import worn_kit as wk  # noqa: E402
import station_textures as st  # noqa: E402
from parts import ALONG_Y, V, rot  # noqa: E402

PRE = "dropship"
OUT = os.path.join(common.ROOT, "assets", "models", "ships", "dropship.glb")
BLEND = os.path.join(common.ROOT, "blender", "dropship.blend")
NOZZLE_Y = -6.6
BELL_R = 0.72
BELL_LEN = 0.95
ENG_X = 1.05
ENG_Z = 0.3
NAC_X = 3.2
NAC_Z = 0.12
NAC_R = 0.7
NAC_Y0, NAC_Y1 = -3.4, 1.05      # nacelle tail / intake lip
FAN_Y = -1.2
POD_TOP = -1.45
POD_BAKE = V((0.0, 0.0, -60.0))   # pod location during the bake (no AO on the belly)
GUN = V((0.0, 5.0, -1.45))
MUZZLE_Y = 6.75
LABELS = ["DS-07", "#CHEV", "NO STEP", "#BAR", "LIFT", "CARGO 07", "07", "KEEP CLEAR"]
ORANGE_INK = (0.6, 0.2, 0.03)

# fuselage stations: (y, half width W, belly z, top z)
FUS = (
    (-5.35, 1.35, -0.75, 1.25),
    (-4.9, 1.75, -1.15, 1.6),
    (-3.8, 1.8, -1.3, 1.8),
    (-1.0, 1.85, -1.3, 1.83),
    (0.8, 1.95, -1.3, 1.85),
    (2.6, 1.9, -1.28, 1.8),
    (3.7, 1.75, -1.22, 1.35),
    (4.7, 1.5, -1.12, 0.85),
    (5.6, 1.1, -0.95, 0.35),
    (6.25, 0.62, -0.72, -0.02),
    (6.45, 0.32, -0.56, -0.16),
)
# flight deck canopy hump, same section shape
CANOPY = (
    (1.9, 0.92, 1.3, 2.18),
    (3.0, 1.06, 1.15, 2.24),
    (3.95, 1.0, 0.85, 1.82),
    (4.75, 0.78, 0.5, 1.12),
    (5.2, 0.46, 0.28, 0.52),
)
# section shape: right half (x / W, z fraction of height), mirrored to the left
SEC = ((0.74, 0.0), (1.0, 0.25), (0.97, 0.6), (0.85, 0.86), (0.55, 1.0))
N_SEC = 10

MATS = {}
DECALS = []
SCORCH = []
RNG = random.Random(7)

# Worn kinds at ship scale (process-local overrides; every generator is its own Blender
# run, so the station and structure bakes are not affected).
SHIP_WORN = {
    "hull": dict(big=(1.6, 1.2), plate=(0.8, 0.6),
                 tones=[(0.205, 0.212, 0.215), (0.19, 0.198, 0.203), (0.22, 0.225, 0.222),
                        (0.182, 0.188, 0.194), (0.21, 0.207, 0.2), (0.176, 0.184, 0.19)],
                 plate_var=0.07, rough=(0.55, 0.12), metal=0.05, seam_big=0.45,
                 seam_small=0.18, rivets=True, hatches=0.16, chip=(0.1, 0.1, 0.105),
                 chip_metal=0.8, chip_k=1.0, grime_k=0.8, streak_k=0.22, bleach=0.08),
    "hull2": dict(big=(1.4, 1.0), plate=(0.7, 0.5),
                  tones=[(0.11, 0.115, 0.12), (0.095, 0.10, 0.105), (0.125, 0.13, 0.13),
                         (0.085, 0.09, 0.095), (0.115, 0.11, 0.105), (0.10, 0.105, 0.115)],
                  plate_var=0.08, rough=(0.55, 0.12), metal=0.1, seam_big=0.45,
                  seam_small=0.18, rivets=True, hatches=0.12, chip=(0.30, 0.30, 0.31),
                  chip_metal=0.9, chip_k=0.9, grime_k=0.8, streak_k=0.22, bleach=0.1),
    "hull3": dict(big=(1.2, 1.2), plate=(0.6, 0.6),
                  tones=[(0.27, 0.27, 0.262), (0.255, 0.258, 0.255), (0.285, 0.282, 0.272),
                         (0.245, 0.248, 0.245), (0.265, 0.262, 0.252), (0.25, 0.25, 0.247)],
                  plate_var=0.06, rough=(0.55, 0.12), metal=0.05, seam_big=0.4,
                  seam_small=0.12, rivets=True, hatches=0.14, chip=(0.1, 0.1, 0.105),
                  chip_metal=0.8, chip_k=1.1, grime_k=0.85, streak_k=0.22, bleach=0.08),
    "dark": dict(big=(1.0, 1.0), plate=(0.5, 0.5),
                 tones=[(0.045, 0.047, 0.05), (0.04, 0.042, 0.045), (0.052, 0.054, 0.056),
                        (0.036, 0.038, 0.04), (0.05, 0.048, 0.046), (0.042, 0.044, 0.048)],
                 plate_var=0.06, rough=(0.5, 0.14), metal=0.6, seam_big=0.35,
                 seam_small=0.15, rivets=False, hatches=0.0, chip=(0.26, 0.26, 0.27),
                 chip_metal=1.0, chip_k=0.8, grime_k=0.5, streak_k=0.2, bleach=0.05),
    "metal": dict(big=(1.0, 0.5), plate=(0.5, 0.5),
                  tones=[(0.30, 0.30, 0.31), (0.27, 0.27, 0.275), (0.33, 0.33, 0.335),
                         (0.25, 0.255, 0.26), (0.31, 0.305, 0.30), (0.28, 0.285, 0.29)],
                  plate_var=0.04, rough=(0.36, 0.1), metal=0.9, seam_big=0.3,
                  seam_small=0.1, rivets=False, hatches=0.0, chip=(0.36, 0.36, 0.37),
                  chip_metal=1.0, chip_k=0.0, grime_k=0.8, streak_k=0.3, bleach=0.0),
    "accent": dict(big=(1.2, 0.8), plate=(0.6, 0.4),
                   tones=[(0.62, 0.21, 0.035), (0.56, 0.19, 0.03), (0.66, 0.24, 0.045),
                          (0.52, 0.18, 0.035), (0.6, 0.22, 0.04), (0.58, 0.2, 0.035)],
                   plate_var=0.06, rough=(0.55, 0.1), metal=0.0, seam_big=0.4,
                   seam_small=0.15, rivets=False, hatches=0.0, chip=(0.13, 0.13, 0.135),
                   chip_metal=0.8, chip_k=1.3, grime_k=1.0, streak_k=0.4, bleach=0.2),
    "hazard": dict(big=(1.2, 1.2), plate=(0.6, 0.6),
                   tones=[(0.42, 0.29, 0.04), (0.40, 0.28, 0.035), (0.44, 0.31, 0.045),
                          (0.38, 0.27, 0.04), (0.43, 0.30, 0.04), (0.41, 0.285, 0.04)],
                   plate_var=0.05, rough=(0.6, 0.08), metal=0.0, seam_big=0.3,
                   seam_small=0.1, rivets=False, hatches=0.0, chip=(0.12, 0.12, 0.125),
                   chip_metal=0.7, chip_k=1.6, grime_k=1.1, streak_k=0.45, bleach=0.2,
                   stripes=0.32),
    # ceramic re-entry tiles: small staggered squares, near-black with scorched and
    # odd replaced (lighter) tiles, chips showing pale substrate
    "tile": dict(big=(0.6, 0.6), plate=(0.3, 0.3),
                 tones=[(0.03, 0.03, 0.032), (0.045, 0.04, 0.036), (0.025, 0.026, 0.03),
                        (0.06, 0.055, 0.05), (0.038, 0.034, 0.03), (0.05, 0.05, 0.052)],
                 plate_var=0.55, rough=(0.85, 0.1), metal=0.0, seam_big=0.7,
                 seam_small=0.6, rivets=False, hatches=0.0, chip=(0.32, 0.3, 0.27),
                 chip_metal=0.0, chip_k=0.7, grime_k=0.5, streak_k=0.6, bleach=0.0),
    # heat-tinted nozzle metal: straw, bronze and blue-violet temper colours
    "temper": dict(big=(0.6, 0.5), plate=(0.3, 0.5),
                   tones=[(0.20, 0.15, 0.24), (0.26, 0.17, 0.09), (0.13, 0.15, 0.26),
                          (0.30, 0.22, 0.12), (0.17, 0.12, 0.2), (0.22, 0.2, 0.22)],
                   plate_var=0.15, rough=(0.33, 0.1), metal=0.92, seam_big=0.25,
                   seam_small=0.1, rivets=False, hatches=0.0, chip=(0.3, 0.3, 0.3),
                   chip_metal=1.0, chip_k=0.0, grime_k=0.6, streak_k=0.5, bleach=0.0),
}
st.WORN_KINDS.update(SHIP_WORN)


def build_materials():
    m = common.make_material
    MATS.clear()
    MATS["hull"] = m(f"{PRE}_paint_grey", (0.3, 0.31, 0.31), roughness=0.55)
    MATS["hull2"] = m(f"{PRE}_paint_dark", (0.11, 0.115, 0.12), roughness=0.55)
    MATS["hull3"] = m(f"{PRE}_paint_patch", (0.4, 0.4, 0.385), roughness=0.55)
    MATS["dark"] = m(f"{PRE}_structure", (0.045, 0.047, 0.05), roughness=0.5, metallic=0.6)
    MATS["metal"] = m(f"{PRE}_bare_metal", (0.3, 0.3, 0.31), roughness=0.36, metallic=0.9)
    MATS["accent"] = m(f"{PRE}_orange", (0.6, 0.21, 0.035), roughness=0.55)
    MATS["hazard"] = m(f"{PRE}_hazard", (0.42, 0.29, 0.04), roughness=0.6)
    MATS["tile"] = m(f"{PRE}_heat_tile", (0.04, 0.038, 0.036), roughness=0.85)
    MATS["temper"] = m(f"{PRE}_temper", (0.2, 0.15, 0.2), roughness=0.33, metallic=0.92)
    glow = (0.03, 0.028, 0.025)
    MATS["glass"] = m(f"{PRE}_canopy", (0.008, 0.011, 0.016), roughness=0.14,
                      emission=(0.16, 0.3, 0.4), emission_strength=0.15)
    MATS["window"] = m(f"{PRE}_window_warm", glow, roughness=0.25,
                       emission=(1.0, 0.62, 0.3), emission_strength=2.2)
    MATS["light"] = m(f"{PRE}_light_amber", glow, roughness=0.3,
                      emission=(1.0, 0.5, 0.12), emission_strength=5.0)
    MATS["white"] = m(f"{PRE}_light_white", glow, roughness=0.3,
                      emission=(0.9, 0.95, 1.0), emission_strength=6.0)
    MATS["nav_r"] = m(f"{PRE}_nav_red", glow, roughness=0.3,
                      emission=(1.0, 0.05, 0.03), emission_strength=7.0)
    MATS["nav_g"] = m(f"{PRE}_nav_green", glow, roughness=0.3,
                      emission=(0.1, 1.0, 0.25), emission_strength=7.0)
    MATS["glow"] = m(f"{PRE}_engine_glow", (0.8, 0.95, 1.0), roughness=0.2,
                     emission=(0.65, 0.92, 1.0), emission_strength=6.0)


def label(text, centre, normal, up, h, colour, opacity=0.85):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity))


# ---------------------------------------------------------------- section helpers
def sec_ring(y, W, zb, zt, grow=0.0, x0=0.0):
    """10-point fuselage section at y: flat belly, lower chine, near-vertical side,
    rounded shoulder, flat top. `grow` pushes every point outward (paint bands)."""
    H = zt - zb
    right = [(W * fx + grow, zb + H * fz) for fx, fz in SEC]
    right[0] = (right[0][0], right[0][1] - grow)
    right[-1] = (right[-1][0], right[-1][1] + grow)
    right[1] = (right[1][0], right[1][1])
    pts = right + [(-x, z) for x, z in reversed(right)]
    return [V((x0 + x, y, z)) for x, z in pts]


def table_at(table, y):
    """Interpolated (W, zb, zt) of a section table at y."""
    if y <= table[0][0]:
        return table[0][1:]
    for a, b in zip(table, table[1:]):
        if a[0] <= y <= b[0]:
            t = (y - a[0]) / (b[0] - a[0])
            return tuple(a[k] + (b[k] - a[k]) * t for k in (1, 2, 3))
    return table[-1][1:]


def face_frame(table, y, j, v, x0=0.0):
    """Point on section face j (between ring points j and j+1) at fraction v, and a frame
    with X along the face edge, Y along the ship, Z the outward face normal."""
    W, zb, zt = table_at(table, y)
    r0 = sec_ring(y, W, zb, zt, x0=x0)
    W1, zb1, zt1 = table_at(table, y + 0.05)
    r1 = sec_ring(y + 0.05, W1, zb1, zt1, x0=x0)
    a, b = r0[j], r0[(j + 1) % N_SEC]
    p = a.lerp(b, v)
    q = r1[j].lerp(r1[(j + 1) % N_SEC], v)
    ex = (b - a).normalized()
    ey = (q - p).normalized()
    n = ex.cross(ey).normalized()
    if n.dot(p - V((x0, y, (zb + zt) / 2))) < 0:
        n = -n
        ex = -ex
    ey = n.cross(ex)
    return p, Matrix((ex, ey, n)).transposed().to_4x4()


def on_hull(p, table, y, j, v, size, mat, lift=0.0, bevel=0.12, dy=0.0, x0=0.0):
    """Box lying on a hull face (size = across edge, along ship, thickness)."""
    c, r = face_frame(table, y, j, v, x0)
    n = r.col[2].xyz
    c = c + n * (size[2] / 2 - 0.02 + lift) + r.col[1].xyz * dy
    p.box(c, size, mat, r=r, bevel=bevel)
    return c, r


def fus_mat(i, j):
    """Fuselage face material: tiled belly, chines and nose, painted flanks and top."""
    y0, y1 = FUS[i][0], FUS[i + 1][0]
    if j in (9, 0, 8):
        return "tile"
    if y0 >= 5.6:
        return "tile"                       # beak: tiled all round
    if y0 >= 4.7 and j in (1, 7):
        return "tile"                       # chin cheeks
    if y1 <= -4.9:
        return "hull2"
    return "hull"


# ---------------------------------------------------------------- hull
def build_hull():
    p = parts.PanelPart("dropship_hull", MATS)
    rings = [sec_ring(y, W, zb, zt) for y, W, zb, zt in FUS]
    p.loft(rings, "tile", mat_fn=fus_mat)
    canopy(p)
    paint_bands(p)
    spine(p)
    flanks(p)
    for sx in (-1, 1):
        wing(p, sx)
        nacelle(p, sx)
    tail_fins(p)
    engines(p)
    belly(p)
    chin_turret(p)
    lights(p)
    return p


def canopy(p):
    """Wrap-around flight deck: framed dark glass on the front slope, armoured roof."""
    rings = [sec_ring(y, W, zb, zt) for y, W, zb, zt in CANOPY]

    def cm(i, j):
        if i in (1, 2) and j in (2, 3, 4, 5, 6):
            return "glass"
        if i == 3:
            return "tile" if j in (3, 4, 5) else "hull"
        return "hull"
    p.loft(rings, "hull", mat_fn=cm)
    # frame mullions along the ring edges over the glass and across the rings
    for i in (1, 2, 3):
        r = rings[i]
        for j in range(2, 7):
            a, b = r[j], r[j + 1]
            n = ((a + b) / 2 - V((0, a.y, 1.0))).normalized()
            parts.strut(p, a + n * 0.03, b + n * 0.03, 0.09, 0.07, "hull2")
    for j in (2, 3, 4, 5, 6, 7):
        a, b = rings[1][j], rings[3][j]
        n = (a - V((0, a.y, 1.2))).normalized()
        parts.strut(p, a + n * 0.03, rings[2][j] + n * 0.03, 0.08, 0.06, "hull2")
        parts.strut(p, rings[2][j] + n * 0.03, b + n * 0.03, 0.08, 0.06, "hull2")
    # warm interior light behind the side panes
    for sx in (-1, 1):
        c, r = face_frame(CANOPY, 3.4, 2 if sx > 0 else 6, 0.5)
        parts.quad(p, c + r.col[2].xyz * 0.035, r.col[2].xyz, (0, 0, 1), 0.3, 0.12, "window")
    # roof: hatch, sensor blister, blade antenna, wipers of armour on the roof edge
    on_hull(p, CANOPY, 2.4, 4, 0.5, (0.9, 0.7, 0.06), "hull3", bevel=0.2)
    label("07", V((0.0, 2.45, 2.27)), (0, 0, 1), (0, 1, 0), 0.5, ORANGE_INK, 0.95)
    p.slab([(1.9, 0.0), (2.5, 0.0), (2.0, 0.45)], -0.025, 0.025, "dark",
           matrix=Matrix.Translation((0.55, 0, 2.2)) @ parts.SIDE)
    for sx in (-1, 1):
        on_hull(p, CANOPY, 2.5, 3 if sx > 0 else 5, 0.5, (0.32, 1.1, 0.07), "hull2")
        p.box(V((sx * 0.62, 3.05, 2.27)), (0.18, 0.12, 0.08), "light" if sx < 0 else "white",
              bevel=0.0)


def paint_bands(p):
    """Orange identity bands: behind the flight deck and around the stern."""
    for y0, y1, mats in ((2.15, 2.5, "accent"), (-4.55, -4.35, "accent")):
        r0 = sec_ring(y0, *table_at(FUS, y0), grow=0.025)
        r1 = sec_ring(y1, *table_at(FUS, y1), grow=0.025)
        p.loft([r0, r1], mats, cap=False,
               mat_fn=lambda i, j: "tile" if j in (9, 0, 8) else mats)
    # nose stripe pair down the top of the beak
    for sx in (-1, 1):
        on_hull(p, FUS, 5.15, 4, 0.5 + sx * 0.22, (0.16, 1.4, 0.04), "accent", bevel=0.0)
    label("#CHEV", V((0.0, 5.15, 0.6)), (0, 0.5, 1), (-1, 0, 0), 0.32, ORANGE_INK, 0.9)


def spine(p):
    """Dorsal spine: armoured fairing, heat-exchanger grilles, intakes, pipes, antennas."""
    y0, y1 = -4.7, 0.9
    rings = [parts.oct_ring(y, w, h, c, z0=1.95) for y, (w, h, c) in
             ((y0, (0.8, 0.3, 0.1)), (y0 + 0.5, (1.25, 0.5, 0.18)), (y1 - 0.6, (1.25, 0.5, 0.18)),
              (y1, (0.9, 0.3, 0.12)))]
    p.loft(rings, "hull2")
    # heat exchanger grille: dark well with metal slats
    for yc in (-3.3, -1.6):
        p.box(V((0, yc, 2.2)), (0.9, 1.3, 0.06), "dark", bevel=0.0)
        for k in range(7):
            p.box(V((0, yc - 0.54 + k * 0.18, 2.24)), (0.82, 0.06, 0.05), "metal", bevel=0.0)
    p.box(V((0, -0.1, 2.21)), (0.7, 0.6, 0.06), "hull3", bevel=0.2)
    label("DS-07", V((0.0, -0.1, 2.21)), (0, 0, 1), (-1, 0, 0), 0.24, wk.INK_DARK, 0.95)
    # twin intakes ahead of the spine, behind the canopy
    for sx in (-1, 1):
        x = sx * 0.62
        p.loft([parts.oct_ring(0.6, 0.5, 0.32, 0.08, x0=x, z0=1.98),
                parts.oct_ring(1.55, 0.55, 0.4, 0.1, x0=x, z0=2.02)], "hull2")
        p.box(V((x, 1.57, 2.02)), (0.42, 0.04, 0.3), "dark", bevel=0.0)
        for k in range(3):
            p.box(V((x, 1.6, 1.92 + k * 0.1)), (0.44, 0.03, 0.03), "metal", bevel=0.0)
        # coolant pipes down the spine sides
        for dz, rr in ((2.0, 0.05), (2.12, 0.04)):
            parts.pipe(p, V((sx * 0.78, -4.3, dz)), V((sx * 0.78, 0.4, dz)), rr, "metal")
        for yy in (-3.8, -2.4, -1.0, 0.2):
            p.box(V((sx * 0.8, yy, 2.06)), (0.12, 0.08, 0.2), "dark", bevel=0.0)
    # antennas: whip mast + strobe, blade, small dish
    p.cyl(V((0.42, -4.3, 2.55)), 0.035, 0.02, 0.9, "dark", segs=5)
    p.box(V((0.42, -4.3, 3.02)), (0.09, 0.09, 0.09), "white", bevel=0.0)
    p.slab([(-3.9, 0.0), (-3.2, 0.0), (-3.75, 0.5)], -0.025, 0.025, "dark",
           matrix=Matrix.Translation((-0.3, 0, 2.3)) @ parts.SIDE)
    parts.dish(p, V((0.0, -0.9, 2.3)), 0.28, (0.0, 0.4, 1.0), "hull3", "dark", depth=0.1, segs=10)


def flanks(p):
    """Side detail: crew doors, armour plates, vents, RCS, access hatches, grab rails."""
    for sx in (-1, 1):
        js = 1 if sx > 0 else 7         # side wall
        jsh = 3 if sx > 0 else 5        # upper shoulder
        jl = 2 if sx > 0 else 6         # lower shoulder
        # crew door with hazard frame, porthole, step lamp
        c, r = on_hull(p, FUS, 1.6, js, 0.55, (0.92, 1.25, 0.05), "hazard", bevel=0.0)
        n = r.col[2].xyz
        p.box(c + n * 0.03, (0.78, 1.1, 0.04), "hull3", r=r, bevel=0.15)
        parts.quad(p, c + n * 0.06 + V((0, 0.25, 0.18)), n, (0, 0, 1), 0.18, 0.12, "window")
        p.box(c + n * 0.06 + V((0, -0.35, 0)), (0.06, 0.2, 0.25), "dark", r=r, bevel=0.0)
        # armour plates down the side, staggered
        for y, l, v in ((-2.9, 1.7, 0.45), (-0.9, 1.9, 0.5), (3.3, 0.9, 0.5)):
            on_hull(p, FUS, y, js, v, (0.82, l, 0.08), "hull3", bevel=0.25)
        # shoulder plates and louvred vents
        for y, l in ((-3.4, 1.1), (-1.7, 1.4), (0.2, 1.2)):
            on_hull(p, FUS, y, jsh, 0.5, (0.42, l, 0.06), "hull", bevel=0.3)
        for y in (-2.6, -0.6):
            c, r = on_hull(p, FUS, y, jl, 0.5, (0.32, 0.9, 0.04), "dark", bevel=0.0)
            for k in range(5):
                p.box(c + r.col[2].xyz * 0.03 + r.col[1].xyz * (-0.36 + k * 0.18),
                      (0.3, 0.05, 0.04), "metal", r=r, bevel=0.0)
        # grab rails along the shoulder
        c0, r0 = face_frame(FUS, -1.8, jl, 0.2)
        c1, _ = face_frame(FUS, 1.0, jl, 0.2)
        nn = r0.col[2].xyz
        parts.pipe(p, c0 + nn * 0.1, c1 + nn * 0.1, 0.025, "metal", segs=5)
        for yy in (-1.8, -0.4, 1.0):
            cc, _ = face_frame(FUS, yy, jl, 0.2)
            p.box(cc + nn * 0.05, (0.04, 0.04, 0.12), "metal", r=r0, bevel=0.0)
        # long orange stripe on the lower shoulder, fore of the wing
        on_hull(p, FUS, 2.9, jl, 0.5, (0.12, 1.3, 0.03), "accent", bevel=0.0)
        # RCS quads front and aft on the shoulders
        for y in (4.15, -4.2):
            c, r = face_frame(FUS, y, jsh, 0.5)
            parts.rcs_quad(p, c + r.col[2].xyz * 0.08, r.col[2].xyz, "hull2", "dark", s=0.24)
        # cheek intake sponson beside the flight deck, mouth facing forward
        cx = sx * 1.98
        p.loft([parts.oct_ring(1.7, 0.3, 0.7, 0.1, x0=cx - sx * 0.12, z0=-0.15),
                parts.oct_ring(2.3, 0.62, 1.0, 0.18, x0=cx, z0=-0.12),
                parts.oct_ring(3.7, 0.62, 1.0, 0.18, x0=cx - sx * 0.08, z0=-0.12),
                parts.oct_ring(3.95, 0.55, 0.92, 0.16, x0=cx - sx * 0.1, z0=-0.12)], "hull2",
               mat_fn=lambda i, j: "tile" if j in (5, 6, 7) or i == 2 else "hull2")
        mc = V((cx - sx * 0.1, 3.96, -0.12))
        p.box(mc, (0.42, 0.04, 0.74), "dark", bevel=0.0)
        for k in range(4):
            p.box(mc + V((0, 0.03, -0.27 + k * 0.18)), (0.44, 0.03, 0.04), "metal", bevel=0.0)
        p.box(V((cx + sx * 0.3, 3.0, -0.12)), (0.04, 1.2, 0.08), "accent", bevel=0.0)
        # side stencil
        c, r = face_frame(FUS, -3.95, js, 0.62)
        label("07", c + r.col[2].xyz * 0.08, r.col[2].xyz, (0, 0, 1), 0.75, ORANGE_INK, 0.95)


def wing_ring(x, y_le, y_te, zc, t):
    """Faceted airfoil section at span x: 8 points in the Y-Z plane."""
    c = y_le - y_te
    pts = [(y_le + 0.02, zc - t * 0.05), (y_le - c * 0.1, zc + t * 0.45),
           (y_le - c * 0.4, zc + t * 0.5), (y_te + c * 0.12, zc + t * 0.3),
           (y_te, zc + t * 0.05), (y_te + c * 0.12, zc - t * 0.25),
           (y_le - c * 0.4, zc - t * 0.45), (y_le - c * 0.1, zc - t * 0.4)]
    return [V((x, y, z)) for y, z in pts]


def wing(p, sx):
    """Swept stub wing from the fuselage side into the nacelle."""
    secs = ((1.6, 1.5, -4.35, -0.05, 0.56), (2.3, 0.65, -4.15, 0.04, 0.44),
            (2.75, 0.25, -4.05, 0.08, 0.38))
    rings = [wing_ring(sx * x, a, b, z, t) for x, a, b, z, t in secs]

    def wm(i, j):
        return "tile" if j in (0, 7, 6) else ("hull" if j in (1, 2) else "hull2")
    p.loft(rings, "hull", mat_fn=wm)
    # flap seam plates, NO STEP, orange tip chevron, fences
    for x, w in ((2.15, 1.1), (2.95, 0.7)):     # flaps, the outer one behind the nacelle
        p.box(V((sx * x, -3.95, 0.12)), (w, 0.5, 0.06), "hull2", rot_z=0.0, bevel=0.0)
        p.box(V((sx * x, -3.68, 0.16)), (w, 0.04, 0.05), "dark", bevel=0.0)
    for x in (2.6, 3.3):
        p.box(V((sx * x, -3.95, 0.1)), (0.04, 0.5, 0.2), "dark", bevel=0.0)
    p.box(V((sx * 2.15, -1.2, 0.29)), (0.05, 2.8, 0.1), "hull2", rot_z=sx * -0.18, bevel=0.0)
    label("NO STEP", V((sx * 2.25, -1.7, 0.29)), (0, 0, 1), (sx * -1, 0, 0), 0.16,
          wk.INK_LIGHT, 0.75)


def nacelle(p, sx):
    """Lift-fan nacelle: round pod with intake lip, ducted fan on top, louvred lift
    nozzle underneath, exhaust cone at the tail."""
    x, z = sx * NAC_X, NAC_Z
    R = NAC_R
    y0, y1 = NAC_Y0, NAC_Y1
    prof = [(0.0, y1 - 0.4), (0.46, y1 - 0.4), (0.5, y1 - 0.05), (0.6, y1), (R * 0.97, y1 - 0.25),
            (R, y1 - 0.6), (R, y1 - 0.95), (R + 0.03, y1 - 0.95), (R + 0.03, y1 - 1.25),
            (R, y1 - 1.25), (R, y0 + 1.0), (R + 0.03, y0 + 1.0), (R + 0.03, y0 + 0.75),
            (R, y0 + 0.75), (R * 0.9, y0 + 0.35), (R * 0.68, y0 + 0.05), (R * 0.5, y0),
            (R * 0.38, y0 + 0.12), (0.0, y0 + 0.12)]
    jm = {0: "dark", 1: "dark", 2: "metal", 3: "tile", 4: "tile", 5: "hull", 6: "accent",
          7: "accent", 8: "accent", 9: "hull", 10: "hull2", 11: "hull2", 12: "hull2",
          13: "hull2", 14: "temper", 15: "temper", 16: "dark", 17: "dark"}

    def nm(i, j):
        k = jm.get(j, "hull")
        if k == "hull" and 4 <= i <= 11:      # lower half (lathe angle 180..360 below)
            return "tile" if j == 5 else "hull"
        return k
    p.lathe(prof, 16, nm, matrix=Matrix.Translation((x, 0, z)) @ ALONG_Y)
    # intake fan face: hub and stator bars
    p.cyl(V((x, y1 - 0.38, z)), 0.16, 0.08, 0.12, "metal", segs=8, axis_rot=ALONG_Y)
    for k in range(5):
        a = k * math.pi / 5 + 0.3
        d = V((math.cos(a), 0, math.sin(a))) * 0.44
        p.beam(V((x, y1 - 0.36, z)) - d, V((x, y1 - 0.36, z)) + d, 0.04, 0.04, "hull2",
               up=V((0, 1, 0)))
    # ducted fan on top: raised collar, dark well, grille, hub, hazard ring
    fz = z + R - 0.05
    p.cyl(V((x, FAN_Y, fz)), 0.66, 0.7, 0.24, "hull2", segs=18)
    p.torus(V((x, FAN_Y, fz + 0.12)), 0.6, 0.05, "metal", segs=18, minor_segs=4)
    p.cyl(V((x, FAN_Y, fz + 0.1)), 0.56, 0.56, 0.06, "dark", segs=18)
    for k in range(9):
        a = k * 2 * math.pi / 9
        blade = Matrix.Translation((x, FAN_Y, fz + 0.12)) @ Matrix.Rotation(a, 4, "Z")
        p.box(blade @ V((0.32, 0.0, 0.0)), (0.42, 0.11, 0.025), "metal",
              r=Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(0.5, 4, "X"), bevel=0.0)
    for k in range(4):
        a = k * math.pi / 4
        d = V((math.cos(a), math.sin(a), 0)) * 0.58
        p.beam(V((x, FAN_Y, fz + 0.17)) - d, V((x, FAN_Y, fz + 0.17)) + d, 0.04, 0.035,
               "hull2")
    p.cyl(V((x, FAN_Y, fz + 0.16)), 0.15, 0.1, 0.08, "hull3", segs=10)
    # fan collar hazard ticks
    for k in range(8):
        a = k * 2 * math.pi / 8 + 0.2
        p.box(V((x + math.cos(a) * 0.69, FAN_Y + math.sin(a) * 0.69, fz + 0.02)),
              (0.08, 0.16, 0.2), "hazard", rot_z=a, bevel=0.0)
    # lift nozzle underneath: box housing with louvres and a heat-tinted rim
    lz = z - R + 0.02
    p.box(V((x, FAN_Y, lz - 0.08)), (0.95, 1.25, 0.3), "hull2", bevel=0.15)
    p.box(V((x, FAN_Y, lz - 0.24)), (0.8, 1.1, 0.04), "temper", bevel=0.0)
    for k in range(6):
        p.box(V((x, FAN_Y - 0.45 + k * 0.18, lz - 0.28)), (0.76, 0.05, 0.12), "dark",
              r=rot(rx=0.35), bevel=0.0)
    SCORCH.append((x, FAN_Y, lz - 0.3, 0.9))
    # armour strakes on the outer flank, maintenance hatch, pylon fairing on top
    c = V((x + sx * (R - 0.02), -2.4, z + 0.05))
    p.box(c, (0.08, 1.3, 0.55), "hull3", r=rot(ry=0.0), bevel=0.25)
    p.box(c + V((sx * 0.05, 0.1, 0.0)), (0.03, 0.35, 0.3), "dark", bevel=0.0)
    for y in (-3.0, 0.3):
        p.box(V((x + sx * 0.25, y, z + R - 0.02)), (0.22, 0.5, 0.06), "hull3", bevel=0.2)
    label("DS-07", V((x + sx * (R + 0.08), -0.6, z + 0.12)), (sx, 0, 0), (0, 0, 1), 0.28,
          wk.INK_DARK, 0.9)
    # exhaust vanes at the tail
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        d = V((math.cos(a), 0, math.sin(a)))
        p.box(V((x, y0 - 0.02, z)) + d * 0.28, (0.05, 0.4, 0.22), "dark",
              r=Matrix.Rotation(-a, 4, "Y"), bevel=0.0)
    # tip nav light, outward
    p.box(V((x + sx * (R + 0.02), y1 - 0.75, z + 0.25)), (0.08, 0.22, 0.12),
          "nav_r" if sx < 0 else "nav_g", bevel=0.0)


def tail_fins(p):
    """Two canted dorsal stabilisers: tiled leading edge, orange tip, nav strobe."""
    for sx in (-1, 1):
        m = (Matrix.Translation((sx * 0.95, 0, 1.5)) @ Matrix.Rotation(sx * 0.42, 4, "Y")
             @ parts.SIDE)
        p.slab([(-5.55, 0.0), (-2.9, 0.0), (-3.2, 0.3), (-4.75, 1.6), (-5.75, 1.7)],
               -0.09, 0.09, "hull", matrix=m)
        p.slab([(-3.2, 0.3), (-2.9, 0.0), (-2.55, 0.0), (-4.55, 1.62), (-4.75, 1.6)],
               -0.06, 0.06, "tile", matrix=m)
        p.slab([(-5.68, 1.3), (-4.9, 1.3), (-4.6, 1.66), (-5.78, 1.74)], -0.1, 0.1,
               "accent", matrix=m)
        p.slab([(-5.5, 0.35), (-4.4, 0.35), (-4.65, 0.5), (-5.5, 0.5)], -0.1, 0.1,
               "hull2", matrix=m)
        tip = m @ V((-5.4, 1.78, 0))
        p.box(tip, (0.12, 0.2, 0.08), "white", bevel=0.0)
        p.slab([(-5.5, -0.1), (-3.0, -0.1), (-3.3, 0.12), (-5.5, 0.12)], -0.18, 0.18, "hull2",
               matrix=m)


def engines(p):
    """Thrust block at the stern: chamfered frame, two gimballed bells, actuators."""
    rings = [parts.oct_ring(-5.25, 3.0, 2.0, 0.5, z0=ENG_Z), parts.oct_ring(-5.45, 3.6, 2.2, 0.55, z0=ENG_Z),
             parts.oct_ring(-5.95, 3.5, 2.05, 0.5, z0=ENG_Z)]
    p.loft(rings, "hull2", mat_fn=lambda i, j: "dark" if i == 1 else "hull2")
    p.box(V((0, -5.97, ENG_Z)), (0.5, 0.06, 1.7), "dark", bevel=0.0)
    p.hazard(-1.6, 1.6, 0.18, -0.02, 0.02,
             matrix=Matrix.Translation((0, -5.98, ENG_Z + 0.88)) @ rot(rx=math.pi / 2),
             pitch=0.3, cols=("hazard", "dark"))
    for sx in (-1, 1):
        x = sx * ENG_X
        p.cyl(V((x, -6.0, ENG_Z)), 0.6, 0.6, 0.18, "metal", segs=16, axis_rot=ALONG_Y)
        p.cyl(V((x, -6.12, ENG_Z)), 0.5, 0.46, 0.12, "dark", segs=16, axis_rot=ALONG_Y)
        parts.bell(p, NOZZLE_Y, BELL_R, BELL_LEN - 0.3, "temper", "dark", x=x, z=ENG_Z, segs=20)
        p.torus(V((x, NOZZLE_Y + 0.12, ENG_Z)), BELL_R * 0.97, 0.035, "metal", segs=20,
                minor_segs=4, matrix=rot(rx=math.pi / 2))
        # gimbal actuators
        for a in (0.6, 2.4):
            d = V((math.cos(a) * sx, 0, math.sin(a)))
            parts.pipe(p, V((x, -5.95, ENG_Z)) + d * 0.62, V((x, -6.35, ENG_Z)) + d * 0.5,
                       0.05, "metal", segs=5)
        SCORCH.append((x, -6.1, ENG_Z, 1.1))
        # side exhaust ports on the thrust block
        p.box(V((sx * 1.82, -5.6, ENG_Z - 0.2)), (0.06, 0.35, 0.5), "dark", bevel=0.0)


def belly(p):
    """Tiled belly hardware: pod clamp yokes, folded landing legs, sensor + lamps."""
    zb = -1.3
    for y in (-2.9, 1.9):
        p.box(V((0, y, zb - 0.06)), (2.5, 0.45, 0.14), "dark", bevel=0.1)
        p.box(V((0, y, zb - 0.12)), (0.6, 0.3, 0.1), "hazard", bevel=0.0)
        for sx in (-1, 1):
            p.box(V((sx * 1.25, y, zb - 0.22)), (0.22, 0.5, 0.36), "metal", bevel=0.15)
            p.box(V((sx * 1.25, y, zb - 0.36)), (0.26, 0.3, 0.12), "hazard", bevel=0.0)
            parts.pipe(p, V((sx * 0.4, y - 0.18, zb - 0.1)), V((sx * 1.15, y - 0.18, zb - 0.2)),
                       0.04, "metal", segs=5)
    # folded landing legs in the chines: hinge, strut, oleo, foot pad
    for sx in (-1, 1):
        x = sx * 1.7
        for y0, y1 in ((-3.9, -1.6), (0.6, 2.9)):
            zc, rr = face_frame(FUS, (y0 + y1) / 2, 0 if sx > 0 else 8, 0.25)
            z = zc.z - 0.12
            p.box(V((x, y0, z + 0.05)), (0.42, 0.5, 0.36), "dark", bevel=0.15)       # hinge
            p.cyl(V((x, y0, z + 0.02)), 0.14, 0.14, 0.56, "metal", segs=8,
                  axis_rot=parts.ALONG_X)
            p.beam(V((x, y0 + 0.2, z)), V((x, y1 - 0.4, z - 0.05)), 0.26, 0.24, "hull2")
            p.tube(V((x - sx * 0.2, y0 + 0.4, z + 0.05)), V((x - sx * 0.2, y1 - 0.5, z)),
                   0.07, 0.07, "metal", segs=6)                                    # oleo
            p.tube(V((x - sx * 0.2, y0 + 0.4, z + 0.05)), V((x - sx * 0.2, y0 + 1.1, z + 0.04)),
                   0.1, 0.1, "dark", segs=6)
            p.cyl(V((x, y1 - 0.2, z - 0.06)), 0.4, 0.44, 0.14, "hull2", segs=12,
                  axis_rot=parts.ALONG_X)                                           # pad
            p.box(V((x + sx * 0.08, y1 - 0.2, z - 0.06)), (0.04, 0.5, 0.5), "hazard",
                  r=Matrix.Rotation(math.pi / 4, 4, "X"), bevel=0.0)
    # belly sensor, landing lamps, antenna blade
    p.sphere(V((0, -0.5, zb - 0.05)), 0.25, "dark", segs=10, rings=5, scale=(1, 1, 0.5))
    for y in (3.2, -4.3):
        for sx in (-1, 1):
            p.box(V((sx * 0.9, y, zb - 0.04)), (0.3, 0.2, 0.08), "light", bevel=0.0)
    for k in range(4):
        SCORCH.append((0.0, 5.6 - k * 1.6, -1.35, 1.6))
        for sx in (-1, 1):
            SCORCH.append((sx * 1.6, 5.0 - k * 2.2, -1.25, 0.8))
    SCORCH.append((0.0, 6.2, -0.4, 0.9))


def chin_turret(p):
    """Chin ball turret: armoured ring, ball, twin cannons with muzzle brakes."""
    p.cyl(GUN + V((0, 0, 0.3)), 0.5, 0.56, 0.18, "hull2", segs=14)
    p.cyl(GUN + V((0, 0, 0.18)), 0.46, 0.46, 0.08, "metal", segs=14)
    p.sphere(GUN, 0.38, "hull2", segs=14, rings=8)
    p.box(GUN + V((0, 0.26, 0.0)), (0.5, 0.3, 0.32), "dark", bevel=0.2)
    p.box(GUN + V((0, 0.3, 0.2)), (0.14, 0.12, 0.08), "light", bevel=0.0)
    for sx in (-1, 1):
        g = GUN + V((sx * 0.15, 0, -0.02))
        p.cyl(g + V((0, 0.95, 0)), 0.055, 0.055, 1.3, "dark", segs=8, axis_rot=ALONG_Y)
        p.cyl(g + V((0, 0.55, 0)), 0.09, 0.09, 0.4, "metal", segs=8, axis_rot=ALONG_Y)
        p.cyl(g + V((0, 1.62, 0)), 0.085, 0.085, 0.24, "hull2", segs=8, axis_rot=ALONG_Y)
        p.box(g + V((0, 1.62, 0)), (0.2, 0.06, 0.05), "dark", bevel=0.0)


def lights(p):
    """Nav and landing lights, strobes, cockpit-side lamps."""
    for sx in (-1, 1):
        c, r = face_frame(FUS, 5.3, 1 if sx > 0 else 7, 0.5)
        p.box(c + r.col[2].xyz * 0.02, (0.12, 0.3, 0.1), "white", r=r, bevel=0.0)
        p.box(V((sx * 1.6, -5.2, 1.0)), (0.1, 0.2, 0.1), "nav_r" if sx < 0 else "nav_g",
              bevel=0.0)
    p.box(V((0, -5.1, 1.32)), (0.18, 0.14, 0.1), "light", bevel=0.0)


# ---------------------------------------------------------------- pod
def build_pod():
    """Underslung cargo pod, built with its clamp plane at z = 0 (origin moved later)."""
    p = parts.PanelPart("dropship_pod", MATS)
    L, W, H = 6.4, 2.8, 1.85
    cy = -0.5
    ya, yb = cy - L / 2, cy + L / 2

    def pm(i, j):
        if j == 6:
            return "tile"
        return "hull3" if i == 1 else "hull2"
    p.loft([parts.oct_ring(ya, W - 0.4, H - 0.4, 0.3, z0=-H / 2),
            parts.oct_ring(ya + 0.3, W, H, 0.4, z0=-H / 2),
            parts.oct_ring(yb - 0.3, W, H, 0.4, z0=-H / 2),
            parts.oct_ring(yb, W - 0.4, H - 0.4, 0.3, z0=-H / 2)], "hull2", mat_fn=pm)
    # corrugation ribs and end frames
    for k in range(7):
        y = ya + 0.75 + k * (L - 1.5) / 6
        mat = "accent" if k == 4 else "hull2"
        p.loft([parts.oct_ring(y - 0.08, W + 0.06, H + 0.06, 0.42, z0=-H / 2),
                parts.oct_ring(y + 0.08, W + 0.06, H + 0.06, 0.42, z0=-H / 2)], mat)
    for y in (ya + 0.15, yb - 0.15):
        p.loft([parts.oct_ring(y - 0.15, W + 0.1, H + 0.1, 0.45, z0=-H / 2),
                parts.oct_ring(y + 0.15, W + 0.1, H + 0.1, 0.45, z0=-H / 2)], "dark")
    # end doors: hazard chevron band, hinge bars, latch lamps
    for s, y in ((-1, ya), (1, yb)):
        p.box(V((0, y + s * 0.01, -H / 2)), (W - 0.7, 0.06, H - 0.7), "hull3", bevel=0.15)
        p.hazard(-0.95, 0.95, 0.22, -0.02, 0.02,
                 matrix=Matrix.Translation((0, y + s * 0.05, -0.55)) @ rot(rx=math.pi / 2),
                 pitch=0.3, cols=("hazard", "dark"))
        for sx in (-1, 1):
            p.box(V((sx * 0.75, y + s * 0.05, -H / 2 - 0.1)), (0.1, 0.06, 0.8), "metal",
                  bevel=0.0)
        p.box(V((0, y + s * 0.06, -H + 0.35)), (0.3, 0.05, 0.08), "light", bevel=0.0)
    # side panels, stencils, hazard sill
    for sx in (-1, 1):
        for k in range(3):
            y = ya + 1.15 + k * 1.95
            if k == 2:
                y -= 0.5
            p.box(V((sx * (W / 2 + 0.02), y, -H / 2)), (0.05, 1.05, 0.95), "hull", bevel=0.2)
        label("CARGO 07", POD_BAKE + V((sx * (W / 2 + 0.05), cy - 1.4, -H / 2)), (sx, 0, 0), (0, 0, 1),
              0.24, wk.INK_DARK, 0.9)
        p.box(V((sx * (W / 2 - 0.05), cy, -H + 0.12)), (0.06, L - 1.0, 0.1), "hazard",
              bevel=0.0)
    # top: lifting lugs at the clamp points, walkway grip strip, cable trays
    for y in (-2.9, 1.9):
        for sx in (-1, 1):
            p.box(V((sx * 1.25, y, 0.02)), (0.3, 0.36, 0.1), "metal", bevel=0.2)
    p.box(V((0, cy, -0.02)), (0.5, L - 1.2, 0.06), "dark", bevel=0.0)
    label("KEEP CLEAR", POD_BAKE + V((0.5, cy + 0.3, 0.01)), (0, 0, 1), (1, 0, 0), 0.22, wk.INK_DARK, 0.8)
    # underside skids, scuffed
    for sx in (-1, 1):
        p.box(V((sx * 0.9, cy, -H - 0.06)), (0.22, L - 0.5, 0.14), "metal", bevel=0.15)
    return p


def build_glow():
    p = parts.Part("engine_glow", MATS)
    for sx in (-1, 1):
        parts.exhaust_glow(p, BELL_R * 0.85, 1.1, "glow", x=sx * ENG_X, z=ENG_Z, segs=16)
    return p


def build_ship():
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    root = parts.make_root("dropship")
    hull = build_hull().finish(root)
    pod_part = build_pod()
    pod = pod_part.finish(root)
    glow = build_glow().finish(root)
    glow.location = (0, NOZZLE_Y, 0)
    for name, sx in (("muzzle_l", -1), ("muzzle_r", 1)):
        parts.add_empty(name, root, (sx * 0.15, MUZZLE_Y, GUN.z - 0.02), size=1.0)
    return root, hull, pod, glow


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, hull, pod, glow = build_ship()
    if "--no-textures" not in argv:
        # bake with the pod and glow out of the way: no pod-shaped AO on the belly
        pod.location = POD_BAKE
        glow.hide_render = True
        bpy.context.view_layer.update()
        wk.texture([hull, pod], MATS, PRE, [(0.0, 0.0)], scorch=SCORCH, decals=DECALS,
                   labels=LABELS, seed0=71)
        glow.hide_render = False
    else:
        for o in (hull, pod):
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    pod.location = (0, 0, POD_TOP)
    bpy.context.view_layer.update()
    wk.stats([hull, pod, glow])
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews("dropship", 15.0, target=(0, 0, -0.4))
    extra = [a.split("=", 1)[1] for a in argv if a.startswith("--extra=")]
    if extra:
        extra_views(extra[0])


def extra_views(out_dir):
    """Debug renders (close-up, belly, side) into out_dir; not part of the previews."""
    scene = bpy.context.scene
    cam = scene.camera
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1200
    for name, loc, tgt, ortho in (("close", (-9, 10, 9), (0, 2.5, 0.5), 8.0),
                                  ("belly", (-10, 8, -9), (0, 0, -1.5), 16.0),
                                  ("side", (-30, 0, 0), (0, 0, 0), 15.0),
                                  ("rear", (-8, -14, 7), (0, -3, 0.5), 12.0)):
        cam.location = loc
        cam.rotation_euler = (V(tgt) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        cam.data.ortho_scale = ortho
        common.render(os.path.join(out_dir, f"dropship_{name}.png"))


main()
