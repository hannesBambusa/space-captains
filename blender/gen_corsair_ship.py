"""Generate the corsair raider .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_corsair_ship.py
  Add `-- --no-preview` to skip the PNG renders, `-- --no-textures` to skip the atlas bake
  (fast shape iteration: flat colours only), `-- --extra=<dir>` for debug close-ups.

Design: Belter pirate fast-attack craft. A stripped racing pinnace turned raider, built
along the thrust axis with nothing aerodynamic on it. Front to back:
  bow       crash-couch cockpit pod: a small chamfered pressure pod with red-lit slit
            viewports under an armoured brow, a sensor block and whip probe on the nose,
            a dorsal escape hatch. Twin three-barrel rapid-fire cannon hang on cheek
            mounts either side (receiver, crimson top cover, cooling jacket, ammo drum
            and feed chute behind each); muzzle_l / muzzle_r sit at the barrel tips.
  spine     a slender armoured keel beam. Mismatched armour slabs are bolted over it on
            standoffs (graphite, gunmetal, scavenged plate, one crimson), with plumbing,
            an airlock hatch with handholds, a small dish and a tally of kills.
  tanks     exposed propellant tanks strapped to the spine: one long crimson-banded
            tank to port, a short tank and a sphere to starboard (salvaged, not a set),
            feed lines running aft, bolted splinter plates over their outer flanks.
            A stolen cargo crate hangs in the belly clamp.
  booms     four short outrigger booms (fore and aft pair) with RCS thruster clusters
            and crimson running lights at the tips: the widest points of the ship.
  drive     reactor block with flush radiators, heat slits, a point-defence dome and
            an antenna cluster, then one oversized faceted drive cone and a fusion bell
            as wide as the rest of the ship, with hoops and gimbal actuators.
Graphite black work paint, crimson identity paint (drive cone top, tank bands, cannon
covers, cockpit brow, diagonal slashes and chevrons painted across the slabs), bone
white stencils and a row of painted teeth along the jaw of the nose, crimson lights. Original design, no ship from any show is copied.

Layout (Blender Z up, exported +Y up). Ship centre at origin on the play plane z=0.
The nose points along Blender +Y, which the exporter turns into Godot -Z (forward).
  length ~13.0 m (bell exit y = NOZZLE_Y -6.45 .. muzzles y = MUZZLE_Y 6.5),
  width ~4.9 m over the RCS booms, height ~3.8 m (mast tip to belly crate); the
  nose probe reaches y 6.75.
  bell y -6.45..-4.5, drive cone y -4.5..-3.35, reactor y -3.35..-2.15,
  spine y -2.15..3.1, tanks y -1.9..1.5, cockpit pod y 3.1..5.95, guns x = +-GUN_X.
Hierarchy: corsair_raider (empty root) -> corsair_hull, engine_glow,
  muzzle_l (empty), muzzle_r (empty).
engine_glow has its origin on the bell exit plane (Blender y = NOZZLE_Y) and its plume
extends along Godot local +Z, so scaling it on Z lengthens the glow backwards.
Muzzle empties are unrotated, so their Godot -Z points forward along the barrels.
Same node contract as scavenger.glb (gen_scavenger_ship.py).
Textures: one 2048 worn atlas (worn_kit / station_textures bake, kinds re-scaled to ship
size and recoloured here, process-local), saved as
blender/textures/corsair_raider_{albedo,mr,normal}.jpg (+ _decals.png, the stencil sheet),
material "corsair_raider_hull". Emissive materials stay flat, named "corsair_raider_*".
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
import worn_kit as wk  # noqa: E402
from parts import ALONG_X, ALONG_Y, V, oct_ring, rot  # noqa: E402

PRE = "corsair_raider"
OUT = os.path.join(common.ROOT, "assets", "models", "ships", "corsair_raider.glb")
BLEND = os.path.join(common.ROOT, "blender", "corsair_raider.blend")

NOZZLE_Y = -6.45
BELL_R, BELL_LEN = 1.55, 1.95
GUN_X, GUN_Z = 1.14, -0.18
MUZZLE_Y = 6.5
SPINE_W, SPINE_H = 1.0, 0.95
DECK_Z = SPINE_H / 2
TANK_P = (-1.0, -0.05, 0.55)          # port tank x, z, radius
TANK_S = (0.96, -0.08, 0.47)          # starboard short tank
SPHERE_S = V((1.04, 0.85, -0.02))     # starboard sphere centre
BOOM_FORE_Y, BOOM_AFT_Y = 2.45, -2.9
BOOM_X = 2.14
LABELS = ["#BAR", "#CHEV", "13", "IIII II", "NO QUARTER", "KEEP OFF", "X", "DRIVE"]
CRIMSON_INK = (0.50, 0.018, 0.035)
BONE_INK = (0.50, 0.48, 0.42)

# (y, w, h, chamfer, z centre)
POD = (
    (3.1, 1.0, 0.95, 0.25, 0.0),
    (3.5, 1.5, 1.25, 0.38, 0.05),
    (4.9, 1.5, 1.25, 0.38, 0.05),
    (5.6, 1.0, 0.8, 0.26, -0.02),
    (5.95, 0.56, 0.46, 0.15, -0.08),
)
REACTOR = (
    (-2.15, 1.0, 0.95, 0.25, 0.0),
    (-2.4, 1.85, 1.7, 0.46, 0.0),
    (-3.35, 1.85, 1.7, 0.46, 0.0),
)
CONE = (
    (-3.35, 1.45, 1.4, 0.4, 0.0),
    (-3.5, 1.75, 1.65, 0.48, 0.0),
    (-4.35, 2.3, 2.15, 0.66, 0.0),
    (-4.5, 2.0, 1.85, 0.56, 0.0),
)

MATS = {}
DECALS = []
SCORCH = []

# Worn kinds at ship scale, in the corsair palette (process-local overrides).
SHIP_WORN = {
    # graphite black work paint
    "hull": dict(big=(1.4, 1.0), plate=(0.7, 0.5),
                 tones=[(0.070, 0.072, 0.080), (0.058, 0.060, 0.068), (0.082, 0.083, 0.090),
                        (0.050, 0.052, 0.060), (0.075, 0.073, 0.076), (0.062, 0.065, 0.074)],
                 plate_var=0.10, rough=(0.5, 0.14), metal=0.35, seam_big=0.5,
                 seam_small=0.25, rivets=True, hatches=0.14, chip=(0.30, 0.30, 0.31),
                 chip_metal=0.95, chip_k=1.25, grime_k=0.7, streak_k=0.3, bleach=0.12),
    # gunmetal slabs
    "hull2": dict(big=(1.2, 0.9), plate=(0.6, 0.45),
                  tones=[(0.135, 0.14, 0.15), (0.115, 0.12, 0.13), (0.15, 0.152, 0.16),
                         (0.105, 0.11, 0.12), (0.14, 0.135, 0.135), (0.12, 0.125, 0.14)],
                  plate_var=0.10, rough=(0.52, 0.14), metal=0.3, seam_big=0.45,
                  seam_small=0.2, rivets=True, hatches=0.1, chip=(0.33, 0.33, 0.34),
                  chip_metal=0.95, chip_k=1.2, grime_k=0.9, streak_k=0.35, bleach=0.12),
    # scavenged plate: whatever colour the donor ship was
    "hull3": dict(big=(1.0, 0.8), plate=(0.5, 0.4),
                  tones=[(0.23, 0.22, 0.20), (0.13, 0.135, 0.14), (0.26, 0.23, 0.17),
                         (0.17, 0.10, 0.075), (0.20, 0.19, 0.18), (0.15, 0.17, 0.17)],
                  plate_var=0.2, rough=(0.62, 0.16), metal=0.15, seam_big=0.45,
                  seam_small=0.2, rivets=True, hatches=0.0, chip=(0.12, 0.11, 0.11),
                  chip_metal=0.8, chip_k=1.6, grime_k=1.2, streak_k=0.5, bleach=0.15),
    "dark": dict(big=(1.0, 1.0), plate=(0.5, 0.5),
                 tones=[(0.034, 0.035, 0.039), (0.030, 0.031, 0.034), (0.040, 0.041, 0.044),
                        (0.027, 0.028, 0.031), (0.037, 0.036, 0.036), (0.032, 0.033, 0.037)],
                 plate_var=0.06, rough=(0.5, 0.14), metal=0.6, seam_big=0.35,
                 seam_small=0.15, rivets=False, hatches=0.0, chip=(0.26, 0.26, 0.27),
                 chip_metal=1.0, chip_k=0.9, grime_k=0.5, streak_k=0.2, bleach=0.05),
    "metal": dict(big=(1.0, 0.5), plate=(0.5, 0.5),
                  tones=[(0.30, 0.30, 0.31), (0.27, 0.27, 0.275), (0.33, 0.33, 0.335),
                         (0.25, 0.255, 0.26), (0.31, 0.305, 0.30), (0.28, 0.285, 0.29)],
                  plate_var=0.04, rough=(0.36, 0.1), metal=0.9, seam_big=0.3,
                  seam_small=0.1, rivets=False, hatches=0.0, chip=(0.36, 0.36, 0.37),
                  chip_metal=1.0, chip_k=0.0, grime_k=0.9, streak_k=0.3, bleach=0.0),
    # crimson identity paint (kept saturated: no bleaching, chips to black primer)
    "accent": dict(big=(1.2, 0.8), plate=(0.6, 0.4),
                   tones=[(0.50, 0.020, 0.036), (0.44, 0.016, 0.032), (0.55, 0.026, 0.042),
                          (0.40, 0.016, 0.030), (0.48, 0.022, 0.040), (0.46, 0.018, 0.034)],
                   plate_var=0.08, rough=(0.5, 0.1), metal=0.0, seam_big=0.45,
                   seam_small=0.18, rivets=True, hatches=0.0, chip=(0.06, 0.055, 0.06),
                   chip_metal=0.7, chip_k=1.3, grime_k=0.8, streak_k=0.3, bleach=0.0),
    "hazard": dict(big=(1.2, 1.2), plate=(0.6, 0.6),
                   tones=[(0.42, 0.29, 0.04), (0.40, 0.28, 0.035), (0.44, 0.31, 0.045),
                          (0.38, 0.27, 0.04), (0.43, 0.30, 0.04), (0.41, 0.285, 0.04)],
                   plate_var=0.05, rough=(0.6, 0.08), metal=0.0, seam_big=0.3,
                   seam_small=0.1, rivets=False, hatches=0.0, chip=(0.12, 0.12, 0.125),
                   chip_metal=0.7, chip_k=1.8, grime_k=1.2, streak_k=0.45, bleach=0.2,
                   stripes=0.26),
    # heat-tinted bell steel
    "temper": dict(big=(1.1, 0.65), plate=(0.55, 0.65),
                   tones=[(0.15, 0.13, 0.16), (0.18, 0.145, 0.115), (0.12, 0.13, 0.17),
                          (0.19, 0.16, 0.13), (0.14, 0.125, 0.15), (0.16, 0.155, 0.16)],
                   plate_var=0.08, rough=(0.36, 0.1), metal=0.92, seam_big=0.2,
                   seam_small=0.06, rivets=False, hatches=0.0, chip=(0.3, 0.3, 0.3),
                   chip_metal=1.0, chip_k=0.0, grime_k=0.6, streak_k=0.5, bleach=0.0),
    # bone white marking paint (the teeth)
    "bone": dict(big=(1.0, 1.0), plate=(0.5, 0.5),
                 tones=[(0.52, 0.50, 0.43), (0.48, 0.46, 0.40), (0.55, 0.52, 0.45),
                        (0.46, 0.44, 0.39), (0.50, 0.48, 0.42), (0.49, 0.47, 0.40)],
                 plate_var=0.05, rough=(0.6, 0.1), metal=0.0, seam_big=0.0,
                 seam_small=0.0, rivets=False, hatches=0.0, chip=(0.07, 0.07, 0.075),
                 chip_metal=0.7, chip_k=1.6, grime_k=1.1, streak_k=0.4, bleach=0.0),
    "radiator": dict(big=(1.6, 0.4), plate=(1.6, 0.2),
                     tones=[(0.20, 0.205, 0.21), (0.18, 0.185, 0.19), (0.22, 0.22, 0.225),
                            (0.17, 0.175, 0.18), (0.21, 0.21, 0.21), (0.19, 0.195, 0.2)],
                     plate_var=0.03, rough=(0.42, 0.08), metal=0.3, seam_big=0.5,
                     seam_small=0.3, rivets=False, hatches=0.0, chip=(0.3, 0.3, 0.3),
                     chip_metal=0.8, chip_k=0.3, grime_k=0.6, streak_k=0.3, bleach=0.0),
}
st.WORN_KINDS.update(SHIP_WORN)


def build_materials():
    m = common.make_material
    MATS.clear()
    MATS["hull"] = m(f"{PRE}_paint_graphite", (0.068, 0.07, 0.078), roughness=0.5,
                     metallic=0.35)
    MATS["hull2"] = m(f"{PRE}_paint_gunmetal", (0.13, 0.135, 0.145), roughness=0.52,
                      metallic=0.3)
    MATS["hull3"] = m(f"{PRE}_plate_salvage", (0.21, 0.2, 0.18), roughness=0.62)
    MATS["dark"] = m(f"{PRE}_structure", (0.034, 0.035, 0.039), roughness=0.5, metallic=0.6)
    MATS["metal"] = m(f"{PRE}_bare_metal", (0.3, 0.3, 0.31), roughness=0.36, metallic=0.9)
    MATS["accent"] = m(f"{PRE}_crimson", (0.5, 0.02, 0.036), roughness=0.5)
    MATS["hazard"] = m(f"{PRE}_hazard", (0.42, 0.29, 0.04), roughness=0.6)
    MATS["bone"] = m(f"{PRE}_bone", (0.5, 0.48, 0.42), roughness=0.6)
    MATS["temper"] = m(f"{PRE}_temper", (0.2, 0.15, 0.2), roughness=0.33, metallic=0.92)
    MATS["radiator"] = m(f"{PRE}_radiator", (0.2, 0.205, 0.21), roughness=0.42,
                         metallic=0.3)
    glow = (0.03, 0.02, 0.02)
    MATS["glass"] = m(f"{PRE}_glass_dark", (0.012, 0.008, 0.009), roughness=0.12)
    MATS["window"] = m(f"{PRE}_window_red", glow, roughness=0.25,
                       emission=(1.0, 0.13, 0.08), emission_strength=2.6)
    MATS["light"] = m(f"{PRE}_light_crimson", glow, roughness=0.3,
                      emission=(1.0, 0.03, 0.08), emission_strength=6.0)
    MATS["heat"] = m(f"{PRE}_heat_slit", glow, roughness=0.4,
                     emission=(1.0, 0.2, 0.06), emission_strength=1.6)
    MATS["glow"] = m(f"{PRE}_engine_glow", (1.0, 0.45, 0.55), roughness=0.2,
                     emission=(1.0, 0.25, 0.35), emission_strength=7.0)
    for k in ("glass", "window", "light", "heat", "glow"):
        MATS[k].use_backface_culling = False


# ---------------------------------------------------------------- small helpers
def label(text, centre, normal, up, h, colour, opacity=0.85, depth=0.6):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity, depth))


def slash(centre, ang, h, text="#BAR", normal=(0, 0, 1), opacity=0.92, depth=0.6):
    """Crimson paint slash on up-facing plates: a 3.8 h x 0.8 h bar, `ang` radians off
    the X axis, projected through `depth` metres so it runs over neighbouring slabs."""
    up = (-math.sin(ang), math.cos(ang), 0.0)
    label(text, centre, normal, up, h, CRIMSON_INK, opacity, depth)


def rings_of(table, x0=0.0):
    return [oct_ring(y, w, h, c, x0=x0, z0=z) for y, w, h, c, z in table]


def frame(n, up=(0, 0, 1)):
    """4x4 rotation: X across, Y = up projected, Z = n (outward)."""
    n = V(n).normalized()
    u = V(up)
    if abs(u.dot(n)) > 0.95:
        u = V((0, 1, 0))
    u = (u - n * u.dot(n)).normalized()
    x = u.cross(n)
    return Matrix((x, u, n)).transposed().to_4x4()


def face_of(ra, rb, j, axis):
    """Centre, outward normal and lengthwise unit vector of loft face j between two rings."""
    k = (j + 1) % len(ra)
    c = (ra[j] + ra[k] + rb[j] + rb[k]) / 4
    along = ((rb[j] + rb[k]) / 2 - (ra[j] + ra[k]) / 2).normalized()
    n = along.cross(ra[k] - ra[j]).normalized()
    if n.dot(c - V(axis)) < 0:
        n = -n
    return c, n, along


def plate(p, c, n, up, w, h, t, mat, rng, cut=0.22, spin=0.05, standoff=0.0, rib=None):
    """Bolted armour slab lying on a face (normal n): corner-cut outline, bolt heads at
    the corners, optional standoff legs so it floats clear of what it protects."""
    m = Matrix.Translation(V(c)) @ frame(n, up) @ Matrix.Rotation(rng.uniform(-spin, spin), 4, "Z")
    hw, hh = w / 2, h / 2
    pts = []
    for sx, sy in ((1, -1), (1, 1), (-1, 1), (-1, -1)):
        a = rng.uniform(0.04, cut) * min(w, h)
        b = rng.uniform(0.04, cut) * min(w, h)
        if sx * sy > 0:
            pts += [(sx * hw, sy * (hh - a)), (sx * (hw - b), sy * hh)]
        else:
            pts += [(sx * (hw - b), sy * hh), (sx * hw, sy * (hh - a))]
    p.slab(pts, -t / 2, t / 2, mat, matrix=m)
    r3 = m.to_3x3()
    if rib:   # stiffener bars across the slab and a lifting eye
        for sy in (-1, 1):
            p.box(m @ V((0, sy * hh * 0.45, t / 2 + 0.015)), (w * 0.72, 0.06, 0.035), rib,
                  r=r3.to_4x4(), bevel=0.0)
        p.box(m @ V((hw * 0.5, 0, t / 2 + 0.02)), (0.1, 0.16, 0.05), "metal", r=r3.to_4x4(),
              bevel=0.0)
    for sx in (-1, 1):
        for sy in (-1, 1):
            q = m @ V((sx * (hw - 0.14), sy * (hh - 0.14), t / 2))
            p.box(q, (0.07, 0.07, 0.05), "metal", r=r3.to_4x4(), bevel=0.0)
            if standoff > 0:
                q0 = m @ V((sx * (hw - 0.14), sy * (hh - 0.14), -t / 2 - standoff))
                q1 = m @ V((sx * (hw - 0.14), sy * (hh - 0.14), -t / 2))
                parts.pipe(p, q0, q1, 0.03, "dark", segs=5)


def slit(p, c, n, up, w, h):
    """Armoured slit viewport: w across, h along `up`, dark frame, red-lit pane."""
    n = V(n).normalized()
    parts.quad(p, V(c) + n * 0.04, n, up, w + 0.07, h + 0.07, "glass")
    parts.quad(p, V(c) + n * 0.065, n, up, w, h, "window")


def bolts(p, a, b, n, s=0.06, mat="metal", nrm=V((0, 0, 1))):
    for k in range(n):
        c = V(a).lerp(V(b), (k + 0.5) / n)
        p.box(c + nrm * s * 0.3, (s, s, s), mat, bevel=0.0)


def cable(p, a, b, sag, r=0.035, n=6, mat="dark", down=V((0, 0, -1))):
    """Sagging hose as a chain of open pipes."""
    pts = []
    for k in range(n + 1):
        t = k / n
        pts.append(V(a).lerp(V(b), t) + down * sag * 4 * t * (1 - t))
    for q0, q1 in zip(pts, pts[1:]):
        parts.pipe(p, q0, q1, r, mat, segs=5)


def run(p, pts, r, mat="metal", segs=6, elbows=True):
    """Pipe run through a list of points with ball elbows."""
    pts = [V(q) for q in pts]
    for a, b in zip(pts, pts[1:]):
        parts.pipe(p, a, b, r, mat, segs=segs)
    if elbows:
        for q in pts[1:-1]:
            p.sphere(q, r * 1.25, mat, segs=6, rings=4)


def tank(p, x, z, y0, y1, r, body, band_mat, bands, segs=14, dome=0.75):
    """Propellant tank along Y with elliptic domes; `bands` = (ya, yb) painted rings."""
    cuts = sorted({y0 + dome * r, y1 - dome * r} | {y for b in bands for y in b})
    prof, keys = [(0.0, y0)], []
    for k in range(1, 4):
        a = math.pi / 2 * k / 3
        prof.append((r * math.sin(a), y0 + dome * r * (1 - math.cos(a))))
        keys.append(body)
    for y in cuts[1:]:
        prof.append((r, y))
        mid = (prof[-2][1] + y) / 2
        keys.append(band_mat if any(a < mid < b for a, b in bands) else body)
    for k in range(1, 4):
        a = math.pi / 2 * k / 3
        prof.append((r * math.cos(a), y1 - dome * r * (1 - math.sin(a))))
        keys.append(body)
    prof[-1] = (0.0, y1)
    p.lathe(prof, segs, lambda i, j: keys[j], matrix=Matrix.Translation((x, 0, z)) @ ALONG_Y)


def hoop(p, y, r, minor, mat, x=0.0, z=0.0, segs=16):
    p.torus(V((x, y, z)), r, minor, mat, segs=segs, minor_segs=4, matrix=rot(rx=math.pi / 2))


def bell_r(y):
    """Outer radius of the main bell at y (matches parts.bell)."""
    t = min(1.0, max(0.0, 1 - (y - NOZZLE_Y) / BELL_LEN))
    rt = BELL_R * 0.42
    return rt + (BELL_R - rt) * t ** 0.65


# ---------------------------------------------------------------- hull
def build_hull(rng):
    p = parts.PanelPart("corsair_hull", MATS)
    spine(p, rng)
    tanks(p, rng)
    cockpit(p, rng)
    for sx in (-1, 1):
        cannon(p, sx)
    booms(p)
    reactor(p, rng)
    drive(p, rng)
    belly(p, rng)
    lights(p)
    return p


def spine(p, rng):
    """Slender armoured keel beam with bolted mismatched slabs, plumbing, airlock, dish."""
    W, H = SPINE_W, SPINE_H
    p.loft([oct_ring(-2.2, W, H, 0.25), oct_ring(3.15, W, H, 0.25)], "hull",
           mat_fn=lambda i, j: "dark" if j == 6 else "hull")
    # frame rings where the modules meet the keel
    for y in (-2.0, -0.2, 1.75, 3.0):
        p.loft([oct_ring(y - 0.07, W + 0.1, H + 0.1, 0.28),
                oct_ring(y + 0.07, W + 0.1, H + 0.1, 0.28)], "dark")
    # dorsal armour slabs on standoffs: (y, length, width, material, x offset)
    slabs = ((-1.45, 1.25, 1.3, "hull2", 0.03), (-0.2, 1.0, 1.15, "hull", -0.05),
             (0.85, 0.95, 1.3, "hull3", 0.06), (1.75, 0.7, 1.05, "accent", -0.02))
    for y, ln, w, mat, dx in slabs:
        plate(p, V((dx, y, DECK_Z + 0.16)), (0, 0, 1), (0, 1, 0), w, ln, 0.09, mat, rng,
              cut=0.2, spin=0.04, standoff=0.12, rib="dark" if mat in ("hull2", "hull3") else None)
    label("13", V((0.03, -1.45, DECK_Z + 0.2)), (0, 0, 1), (0, 1, 0), 0.3, BONE_INK, 0.9, 0.2)
    # plumbing under the slabs along the deck, clamps
    for x, r in ((-0.3, 0.05), (-0.17, 0.035), (0.26, 0.06)):
        parts.pipe(p, V((x, -2.15, DECK_Z + 0.05)), V((x, 3.1, DECK_Z + 0.05)), r, "metal")
    for y in (-0.85, 0.3, 1.3, 2.2):
        p.box(V((0, y, DECK_Z + 0.05)), (0.8, 0.07, 0.12), "dark", bevel=0.0)
    # airlock hatch on the port upper chamfer, handholds beside it
    c, n, along = face_of(oct_ring(2.0, W, H, 0.25), oct_ring(3.0, W, H, 0.25), 3, (0, 2.5, 0))
    r = Matrix.Translation(c + n * 0.03) @ frame(n, (0, 1, 0))
    p.cyl(c + n * 0.03, 0.2, 0.2, 0.07, "hull2", segs=10, axis_rot=frame(n, (0, 1, 0)))
    p.cyl(c + n * 0.07, 0.12, 0.12, 0.04, "dark", segs=10, axis_rot=frame(n, (0, 1, 0)))
    for s in (-1, 1):
        a = r @ V((s * 0.26, -0.22, 0.05))
        b = r @ V((s * 0.26, 0.22, 0.05))
        parts.pipe(p, a, b, 0.018, "metal", segs=4)
    # flanks of the keel between tanks and pod: cable trays and grab rails
    for sx in (-1, 1):
        x = sx * (W / 2 + 0.03)
        p.box(V((x, 2.35, 0.0)), (0.06, 1.1, 0.42), "hull2", bevel=0.2)
        for k in range(4):
            p.box(V((x + sx * 0.03, 2.0 + k * 0.22, 0.0)), (0.03, 0.05, 0.3), "dark", bevel=0.0)
        parts.pipe(p, V((x + sx * 0.06, 1.85, 0.3)), V((x + sx * 0.06, 2.85, 0.3)), 0.018,
                   "metal", segs=4)
    # small comms dish and a whip on the deck behind the pod
    base = V((0.28, 2.62, DECK_Z + 0.06))
    p.cyl(base + V((0, 0, 0.1)), 0.05, 0.05, 0.3, "dark", segs=6)
    parts.dish(p, base + V((0, 0, 0.27)), 0.26, (0.35, 0.3, 1.0), "hull2", "dark", depth=0.1,
               segs=10)
    p.tube(V((-0.3, 2.75, DECK_Z)), V((-0.42, 2.45, DECK_Z + 1.1)), 0.018, 0.008, "dark",
           segs=4)
    # painted slashes across the slabs (they run over the gaps, like sprayed in one pass)
    slash(V((0.0, -0.45, DECK_Z + 0.2)), math.radians(38), 0.42, depth=0.3)
    slash(V((0.05, 0.25, DECK_Z + 0.2)), math.radians(38), 0.42, depth=0.3)
    label("NO QUARTER", V((0.06, 0.95, DECK_Z + 0.21)), (0, 0, 1), (-1, 0, 0), 0.12, BONE_INK,
          0.8, 0.15)


def tanks(p, rng):
    """Exposed propellant tanks strapped either side of the keel, feed lines aft."""
    # port: one long tank, two crimson bands
    x, z, r = TANK_P
    y0, y1 = -1.9, 1.5
    tank(p, x, z, y0, y1, r, "hull2", "accent", ((-1.25, -0.55), (0.55, 0.85)))
    for y in (-1.4, -0.35, 0.35, 1.0):
        hoop(p, y, r + 0.012, 0.035, "dark", x=x, z=z, segs=14)
        p.beam(V((x + 0.3, y, z + 0.1)), V((-SPINE_W / 2 + 0.05, y, 0.1)), 0.12, 0.16, "dark")
        p.box(V((x + r * 0.72, y, z + r * 0.72)), (0.1, 0.12, 0.1), "metal", bevel=0.0)
    p.cyl(V((x, 1.52, z)), 0.1, 0.07, 0.14, "metal", segs=8, axis_rot=ALONG_Y)   # fill port
    p.cyl(V((x - 0.2, 0.0, z + r * 0.95)), 0.07, 0.07, 0.1, "metal", segs=6)     # vent valve
    run(p, [(x, y0 + 0.05, z), (x, -2.1, z), (x + 0.25, -2.3, z + 0.2), (x + 0.25, -2.45, z + 0.2)],
        0.06)
    # splinter plates bolted over the port tank's outer flank
    for y, ln, mat, a in ((-1.05, 1.1, "hull", 0.55), (0.25, 0.9, "hull3", 0.7),
                          (1.05, 0.55, "hull", 0.5)):
        n = V((-math.cos(a), 0, math.sin(a)))
        plate(p, V((x, y, z)) + n * (r + 0.13), n, (0, 1, 0), 0.7, ln, 0.07, mat, rng,
              standoff=0.1)
    # starboard: a short tank and a sphere off some other ship
    x, z, r = TANK_S
    tank(p, x, z, -1.95, -0.25, r, "hull3", "hull2", ((-1.3, -1.05),), segs=12)
    for y in (-1.5, -0.7):
        hoop(p, y, r + 0.012, 0.035, "dark", x=x, z=z, segs=12)
        p.beam(V((x - 0.25, y, z + 0.1)), V((SPINE_W / 2 - 0.05, y, 0.1)), 0.12, 0.16, "dark")
    run(p, [(x, -1.9, z), (x, -2.1, z), (x - 0.2, -2.3, z + 0.2), (x - 0.2, -2.45, z + 0.2)], 0.05)
    c, rs = SPHERE_S, 0.6
    p.sphere(c, rs, "hull", segs=16, rings=9)
    p.torus(c, rs + 0.012, 0.04, "accent", segs=16, minor_segs=4, matrix=rot(ry=math.pi / 2))
    p.torus(c, rs + 0.012, 0.035, "dark", segs=16, minor_segs=4)
    p.torus(c, rs + 0.012, 0.035, "dark", segs=16, minor_segs=4, matrix=rot(rx=math.pi / 2))
    for dy in (-0.3, 0.3):
        p.beam(c + V((-0.35, dy, 0.12)), V((SPINE_W / 2 - 0.05, c.y + dy, 0.1)), 0.1, 0.14, "dark")
    p.cyl(c + V((0, 0, rs + 0.03)), 0.09, 0.07, 0.12, "metal", segs=8)
    run(p, [c + V((0, -rs + 0.03, 0.0)), (c.x, -0.05, c.z), (TANK_S[0] + 0.2, -0.3, c.z + 0.3)],
        0.045)
    n = V((0.75, 0, 0.66)).normalized()
    plate(p, V((TANK_S[0], -1.1, TANK_S[1])) + n * (TANK_S[2] + 0.12), n, (0, 1, 0), 0.62, 1.15,
          0.07, "accent", rng, standoff=0.1)
    label("KEEP OFF", V((TANK_S[0], -1.1, TANK_S[1])) + n * (TANK_S[2] + 0.17), n, (0, 1, 0),
          0.1, BONE_INK, 0.8, 0.12)
    # cross-feed hose over the keel
    cable(p, V((-0.62, -0.75, DECK_Z + 0.1)), V((0.62, -0.95, DECK_Z + 0.08)), -0.03, r=0.035)


def cockpit(p, rng):
    """Crash-couch pod: chamfered pressure hull, slit viewports under an armoured brow."""
    rings = rings_of(POD)

    def cm(i, j):
        if i == 0:
            return "dark"
        if i == 3:
            return "hull2" if j in (1, 2, 3) else "hull"
        if j in (5, 6, 7):
            return "hull2"
        return "hull"
    p.loft(rings, "hull", mat_fn=cm)
    axis = (0, 4.5, 0.0)
    # forward slits: three on the front slope, one on each front chamfer
    c, n, along = face_of(rings[2], rings[3], 2, axis)
    for dx in (-0.21, 0.0, 0.21):
        slit(p, c + V((dx, 0, 0)) + along * 0.02, n, along, 0.15, 0.065)
    for j in (1, 3):
        c, n, along = face_of(rings[2], rings[3], j, axis)
        slit(p, c + along * 0.02, n, along, 0.2, 0.06)
    # side slits on the upper chamfers of the pod
    for j in (1, 3):
        c, n, along = face_of(rings[1], rings[2], j, axis)
        for dy in (0.3, 0.58):
            slit(p, c + along * dy, n, V((0, 0, 1)), 0.2, 0.055)
    # armoured brow over the forward slits, crimson, with a bolt row
    p.box(V((0, 4.86, 0.72)), (1.0, 0.36, 0.1), "accent", r=rot(rx=-0.1), bevel=0.25)
    bolts(p, V((-0.42, 4.76, 0.77)), V((0.42, 4.76, 0.77)), 5, 0.05)
    # roof: escape hatch, grab rails, top slab
    plate(p, V((0.0, 4.05, 0.72)), (0, 0, 1), (0, 1, 0), 0.72, 0.95, 0.08, "hull2", rng, cut=0.25,
          spin=0.0)
    p.cyl(V((0.0, 4.05, 0.78)), 0.22, 0.22, 0.05, "hull", segs=10)
    p.cyl(V((0.0, 4.05, 0.81)), 0.1, 0.1, 0.04, "metal", segs=8)
    for sx in (-1, 1):
        parts.pipe(p, V((sx * 0.3, 3.75, 0.8)), V((sx * 0.3, 4.35, 0.8)), 0.018, "metal", segs=4)
    slash(V((0.0, 3.62, 0.7)), math.radians(90), 0.26, text="#CHEV", depth=0.25)
    # cheek armour: flat slabs on the pod flanks, kill tally to starboard
    for sx in (-1, 1):
        plate(p, V((sx * 0.78, 4.15, 0.02)), (sx, 0, 0), (0, 0, 1), 1.15, 0.6, 0.06,
              "hull2" if sx < 0 else "hull", rng, cut=0.25)
    label("IIII II", V((0.82, 4.15, 0.05)), (1, 0, 0), (0, 0, 1), 0.14, BONE_INK, 0.85, 0.15)
    label("X", V((-0.82, 4.15, 0.02)), (-1, 0, 0), (0, 0, 1), 0.55, CRIMSON_INK, 0.9, 0.15)
    # nose: sensor block, lidar eye, whip probe, crimson nose band
    p.loft([oct_ring(5.42, 1.16, 0.93, 0.3, z0=-0.02), oct_ring(5.6, 1.02, 0.82, 0.265, z0=-0.02)],
           "accent", cap=False)
    p.box(V((0, 6.02, -0.08)), (0.4, 0.2, 0.32), "dark", bevel=0.2)
    p.cyl(V((0.0, 6.125, -0.05)), 0.075, 0.075, 0.02, "glass", segs=8, axis_rot=ALONG_Y)
    p.cyl(V((0.0, 6.14, -0.05)), 0.04, 0.04, 0.02, "window", segs=8, axis_rot=ALONG_Y)
    p.tube(V((-0.12, 6.1, -0.18)), V((-0.12, 6.75, -0.2)), 0.016, 0.008, "metal", segs=4)
    # teeth painted along the jaw line of the nose, both sides
    for j in (0, 4):
        c, n, along = face_of(rings[2], rings[3], j, axis)
        m = Matrix.Translation(c + n * 0.012) @ frame(n, (0, 0, 1))
        sgn = 1 if (m.to_3x3() @ V((1, 0, 0))).y > 0 else -1     # local +X towards the bow
        for k in range(4):
            x0 = sgn * (-0.3 + k * 0.16)
            w = sgn * 0.13
            h = 0.2 - k * 0.03
            p.slab([(x0, 0.16 - k * 0.028), (x0 + w, 0.16 - (k + 1) * 0.028), (x0 + w / 2, 0.16 - k * 0.028 - h)]
                   if sgn > 0 else
                   [(x0 + w, 0.16 - (k + 1) * 0.028), (x0, 0.16 - k * 0.028), (x0 + w / 2, 0.16 - k * 0.028 - h)],
                   0.0, 0.012, "bone", matrix=m)
    # belly of the pod: sensor blister and a ventral RCS quad
    p.sphere(V((0, 4.6, -0.6)), 0.2, "dark", segs=10, rings=5, scale=(1.0, 1.4, 0.6))
    parts.rcs_quad(p, V((0, 5.25, -0.45)), (0, 0, -1), "hull2", "metal", s=0.18)
    parts.rcs_quad(p, V((0, 5.3, 0.42)), (0, 0.35, 1), "hull2", "metal", s=0.16)
    SCORCH.append((0.0, 5.25, -0.5, 0.5))
    # neck collar where the pod bolts to the keel (it used to be an escape pinnace)
    p.loft([oct_ring(3.2, 1.2, 1.1, 0.3), oct_ring(3.36, 1.2, 1.1, 0.3)], "metal", cap=False)
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        p.box(V((math.cos(a) * 0.62, 3.28, math.sin(a) * 0.57)), (0.08, 0.2, 0.08), "dark",
              bevel=0.0)


def cannon(p, sx):
    """Three-barrel rapid-fire cannon on a cheek mount: receiver, cooling jacket, barrel
    cluster, muzzle plate; ammo drum and feed chute behind it."""
    x, z = sx * GUN_X, GUN_Z
    # cheek mount: two arms from the pod flank and a hinge pin
    for y in (3.7, 4.5):
        p.beam(V((sx * 0.7, y, z + 0.05)), V((x - sx * 0.2, y, z + 0.02)), 0.16, 0.2, "dark")
    p.cyl(V((sx * 0.86, 4.1, z)), 0.06, 0.06, 1.0, "metal", segs=6, axis_rot=ALONG_Y)
    # receiver
    p.box(V((x, 4.05, z)), (0.46, 1.5, 0.5), "hull", bevel=0.2)
    p.box(V((x, 4.1, z + 0.27)), (0.36, 1.2, 0.07), "accent", bevel=0.2)       # top cover
    p.box(V((x + sx * 0.24, 4.3, z)), (0.05, 0.6, 0.3), "hull2", bevel=0.2)    # side door
    for k in range(4):
        p.box(V((x + sx * 0.245, 3.55 + k * 0.1, z + 0.02)), (0.04, 0.04, 0.3), "dark",
              bevel=0.0)
    bolts(p, V((x, 3.55, z + 0.31)), V((x, 4.65, z + 0.31)), 5, 0.045)
    p.box(V((x, 3.27, z)), (0.34, 0.14, 0.38), "dark", bevel=0.2)              # breech cap
    # cooling jacket with rings
    p.cyl(V((x, 5.15, z)), 0.17, 0.15, 0.72, "hull2", segs=10, axis_rot=ALONG_Y)
    p.cyl(V((x, 4.84, z)), 0.2, 0.2, 0.1, "dark", segs=10, axis_rot=ALONG_Y)
    for k in range(4):
        p.cyl(V((x, 5.0 + k * 0.15, z)), 0.185, 0.185, 0.045, "dark", segs=10,
              axis_rot=ALONG_Y)
    # barrel cluster
    y0 = 5.5
    for k in range(3):
        a = math.pi / 2 + k * 2 * math.pi / 3
        bx, bz = x + math.cos(a) * 0.075, z + math.sin(a) * 0.075
        p.cyl(V((bx, (y0 + MUZZLE_Y) / 2, bz)), 0.04, 0.04, MUZZLE_Y - y0, "metal", segs=6,
              axis_rot=ALONG_Y)
    p.cyl(V((x, (y0 + MUZZLE_Y - 0.1) / 2, z)), 0.03, 0.03, MUZZLE_Y - 0.1 - y0, "dark",
          segs=5, axis_rot=ALONG_Y)
    for y in (5.85, 6.2):
        p.cyl(V((x, y, z)), 0.135, 0.135, 0.05, "dark", segs=9, axis_rot=ALONG_Y)
    p.cyl(V((x, MUZZLE_Y - 0.05, z)), 0.145, 0.13, 0.1, "temper", segs=9, axis_rot=ALONG_Y)
    SCORCH.append((x, MUZZLE_Y - 0.1, z, 0.45))
    # ammo drum behind the receiver, feed chute over the top
    d = V((sx * 0.92, 2.95, z - 0.02))
    p.cyl(d, 0.3, 0.3, 0.5, "hull3", segs=12, axis_rot=ALONG_X)
    for dx in (-0.2, 0.2):
        p.cyl(d + V((dx, 0, 0)), 0.315, 0.315, 0.05, "dark", segs=12, axis_rot=ALONG_X)
    p.cyl(d + V((sx * 0.27, 0, 0)), 0.12, 0.12, 0.06, "metal", segs=8, axis_rot=ALONG_X)
    p.box(d + V((sx * 0.02, 0, 0.3)), (0.3, 0.1, 0.05), "hazard", bevel=0.0)
    p.beam(d + V((0, 0, -0.1)), V((sx * 0.5, 2.95, -0.1)), 0.2, 0.16, "dark")
    p.beam(d + V((sx * 0.1, 0.2, 0.22)), V((x, 3.4, z + 0.22)), 0.2, 0.08, "metal")


def boom(p, sx, y, root_x, z, brace_y):
    """Short outrigger boom with an RCS cluster at the tip."""
    tip = V((sx * BOOM_X, y, z))
    root = V((sx * root_x, y, z))
    parts.strut(p, root, tip, 0.16, 0.14, "hull2")
    parts.strut(p, V((sx * root_x, brace_y, z - 0.12)), tip + V((-sx * 0.2, 0, -0.03)), 0.09, 0.09,
                "dark")
    parts.strut(p, V((sx * root_x, y, z + 0.4)), tip + V((-sx * 0.25, 0, 0.06)), 0.07, 0.07, "dark")
    parts.pipe(p, root + V((0, 0.1, 0.04)), tip + V((-sx * 0.1, 0.1, 0.04)), 0.025, "metal",
               segs=5)
    span = BOOM_X - root_x
    for t in (0.35, 0.7):
        p.box(root.lerp(tip, t), (0.07, 0.2, 0.18), "dark", bevel=0.0)
    p.box(root + V((sx * 0.05, 0, 0.0)), (0.14, 0.34, 0.3), "dark", bevel=0.2)
    # tip block: thruster quad plus one nozzle straight out
    p.box(tip, (0.3, 0.34, 0.3), "hull", bevel=0.2)
    p.box(tip + V((0, 0, 0.16)), (0.22, 0.24, 0.04), "accent", bevel=0.0)
    for d in (V((0, 1, 0)), V((0, -1, 0)), V((0, 0, 1)), V((0, 0, -1))):
        if d.z > 0.5:
            continue  # the top face carries the lamp
        p.tube(tip + d * 0.15, tip + d * 0.3, 0.04, 0.075, "metal", segs=7)
    p.tube(tip + V((sx * 0.14, 0, 0)), tip + V((sx * 0.3, 0, 0)), 0.045, 0.085, "metal", segs=7)
    p.box(tip + V((0, 0, 0.19)), (0.07, 0.09, 0.04), "light", bevel=0.0)
    SCORCH.append((tip.x + sx * 0.2, tip.y, tip.z, 0.4))
    return span


def booms(p):
    for sx in (-1, 1):
        boom(p, sx, BOOM_FORE_Y, SPINE_W / 2 - 0.02, 0.0, 1.85)
        boom(p, sx, BOOM_AFT_Y, 0.9, 0.05, -2.45)


def reactor(p, rng):
    """Reactor block: flush radiators with heat slits, PD dome, antenna cluster."""
    rings = rings_of(REACTOR)
    p.loft(rings, "hull", mat_fn=lambda i, j: "dark" if i == 0 else
           ("hull2" if j in (5, 6, 7) else "hull"))
    W, H = 1.85, 1.7
    for sx in (-1, 1):
        x = sx * (W / 2 + 0.03)
        parts.radiator(p, V((x, -2.88, 0.15)), 0.8, 0.62, (sx, 0, 0), "radiator", "metal",
                       ribs=6, t=0.05)
        for k in range(5):
            p.box(V((x + sx * 0.02, -3.21 + k * 0.133 + 0.066, 0.15)), (0.02, 0.03, 0.5), "heat",
                  bevel=0.0)
        p.box(V((x, -2.88, -0.42)), (0.05, 0.8, 0.3), "hull2", bevel=0.2)
    # top: radiator strip, bolted slab with the big slash, PD dome, mast cluster
    parts.radiator(p, V((0.42, -2.85, H / 2 + 0.03)), 0.85, 0.5, (0, 0, 1), "radiator", "metal",
                   ribs=6, t=0.05)
    for k in range(5):
        p.box(V((0.42, -3.2 + k * 0.142 + 0.071, H / 2 + 0.05)), (0.4, 0.03, 0.02), "heat",
              bevel=0.0)
    plate(p, V((-0.38, -2.85, H / 2 + 0.05)), (0, 0, 1), (0, 1, 0), 0.8, 0.95, 0.08, "hull3", rng,
          cut=0.2, spin=0.03)
    pd = V((-0.38, -2.75, H / 2 + 0.1))
    p.cyl(pd + V((0, 0, 0.03)), 0.24, 0.26, 0.08, "dark", segs=12)
    p.sphere(pd + V((0, 0, 0.06)), 0.2, "hull2", segs=12, rings=6, scale=(1, 1, 0.8))
    for s in (-1, 1):
        p.tube(pd + V((s * 0.05, 0.1, 0.14)), pd + V((s * 0.05, 0.5, 0.2)), 0.022, 0.022, "metal",
               segs=5)
    p.box(pd + V((0, 0.14, 0.15)), (0.2, 0.1, 0.09), "dark", bevel=0.0)
    base = V((0.55, -2.38, H / 2 + 0.02))
    p.box(base, (0.3, 0.26, 0.12), "dark", bevel=0.2)
    for dx, dy, hgt, r in ((0.0, 0.0, 1.25, 0.022), (0.1, 0.06, 0.8, 0.018),
                           (-0.09, 0.05, 0.55, 0.018)):
        top = base + V((dx, dy - hgt * 0.12, hgt))
        p.tube(base + V((dx, dy, 0.04)), top, r, r * 0.5, "metal", segs=4)
    p.box(base + V((0, -0.15, 1.25)), (0.06, 0.06, 0.06), "light", bevel=0.0)
    # upper chamfers: bolted slabs, chevron paint to port
    for j, mat in ((1, "hull2"), (3, "hull")):
        c, n, along = face_of(rings[1], rings[2], j, (0, -2.9, 0))
        plate(p, c + n * 0.045, n, (0, 1, 0), 0.5, 0.8, 0.06, mat, rng, cut=0.25)
    # coolant lines from the reactor into the drive cone
    for sx in (-1, 1):
        for z in (0.5, -0.5):
            parts.pipe(p, V((sx * 0.5, -3.3, z)), V((sx * 0.62, -3.6, z * 1.25)), 0.05, "metal",
                       segs=6)


def drive(p, rng):
    """One oversized fusion drive: faceted armoured cone, thrust ring, bell with hoops
    and gimbal actuators."""
    rings = rings_of(CONE)

    def cm(i, j):
        if i != 1:
            return "dark"
        return {2: "accent", 1: "hull", 3: "hull2", 0: "hull", 4: "hull", 6: "hull2",
                5: "hull3", 7: "hull"}[j]
    p.loft(rings, "hull", mat_fn=cm)
    axis = (0, -3.9, 0)
    # petal seams: raised battens along the cone edges, bolts on the top petal
    for j in range(8):
        a, b = rings[1][j], rings[2][j]
        out = V((a.x + b.x, 0, a.z + b.z)).normalized()
        parts.strut(p, a + out * 0.02, b + out * 0.02, 0.09, 0.07, "dark", up=out)
    c, n, along = face_of(rings[1], rings[2], 2, axis)
    r3 = frame(n, along)
    for t, hw in ((-0.3, 0.3), (0.3, 0.42)):
        q = c + along * t
        bolts(p, q - V((hw, 0, 0)) + n * 0.01, q + V((hw, 0, 0)) + n * 0.01, 5, 0.05, nrm=n)
    # access hatch and a stencil on the top petal
    p.box(c + along * 0.05 + n * 0.02 + V((0.22, 0, 0)), (0.34, 0.42, 0.05), "hull2", r=r3,
          bevel=0.2)
    # chevrons on the two upper side petals, pointing at the bell
    for j in (1, 3):
        cj, nj, alj = face_of(rings[1], rings[2], j, axis)
        DECALS.append(st.decal(LABELS.index("#CHEV"), cj + nj * 0.02 + alj * 0.1, nj,
                               nj.cross(alj) if j == 1 else alj.cross(nj), 0.2, CRIMSON_INK,
                               0.9, 0.25))
    for j in (0, 4):
        cj, nj, alj = face_of(rings[1], rings[2], j, axis)
        plate(p, cj + nj * 0.04, nj, alj, 0.55, 0.75, 0.06, "hull3" if j == 0 else "hull2", rng)
        label("DRIVE", cj + nj * 0.09 + alj * 0.02, nj, (0, 0, 1), 0.1, BONE_INK, 0.8, 0.12)
    # thrust ring and gimbal frame behind the cone
    p.cyl(V((0, -4.55, 0)), 0.92, 0.84, 0.16, "dark", segs=16, axis_rot=ALONG_Y)
    p.cyl(V((0, -4.66, 0)), 0.74, 0.68, 0.12, "metal", segs=16, axis_rot=ALONG_Y)
    parts.bell(p, NOZZLE_Y, BELL_R, BELL_LEN, "temper", "dark", segs=20)
    for y in (-4.95, -5.45, -5.95):
        hoop(p, y, bell_r(y) + 0.015, 0.035, "dark", segs=20)
    hoop(p, NOZZLE_Y + 0.05, BELL_R + 0.01, 0.045, "metal", segs=20)
    for k in range(6):
        a = k * math.pi / 3 + math.pi / 6
        q = V((math.cos(a), 0, math.sin(a)))
        y1 = -5.45
        p.tube(V((0, -4.5, 0)) + q * 0.9, V((0, y1, 0)) + q * (bell_r(y1) + 0.03), 0.045, 0.035,
               "metal", segs=5)
        p.box(V((0, -4.52, 0)) + q * 0.9, (0.16, 0.14, 0.16), "dark", bevel=0.0)
    # coolant loops round the throat
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        q = V((math.cos(a), 0, math.sin(a)))
        parts.pipe(p, V((0, -4.5, 0)) + q * 0.75, V((0, -4.95, 0)) + q * (bell_r(-4.95) + 0.06),
                   0.035, "accent", segs=5)
    SCORCH.append((0.0, -5.0, 0.0, 2.3))


def belly(p, rng):
    """Keel plate, cargo clamp with a stolen crate, skid stubs."""
    zb = -DECK_Z
    p.box(V((0, 0.3, zb - 0.04)), (0.62, 4.6, 0.08), "hull2", bevel=0.0)
    for y in (-1.7, 2.3):
        p.box(V((0, y, zb - 0.14)), (0.4, 0.5, 0.14), "dark", bevel=0.2)
    c = V((0, 0.45, zb - 0.5))
    p.box(c, (0.82, 1.3, 0.62), "hull3", bevel=0.06)
    for y in (-0.5, 0.5):
        p.box(c + V((0, y, 0)), (0.88, 0.1, 0.68), "dark", bevel=0.0)
    p.box(c + V((0, 0, -0.32)), (0.5, 0.9, 0.03), "hazard", bevel=0.0)
    for sx in (-1, 1):
        for y in (-0.28, 0.28):   # clamp jaws gripping the crate
            p.beam(V((sx * 0.36, c.y + y, zb - 0.02)), V((sx * 0.5, c.y + y, zb - 0.3)), 0.12, 0.1,
                   "metal")
            p.beam(V((sx * 0.5, c.y + y, zb - 0.3)), V((sx * 0.44, c.y + y, zb - 0.62)), 0.1, 0.08,
                   "dark")
    parts.rcs_quad(p, V((0, -2.9, -0.9)), (0, 0, -1), "hull2", "metal", s=0.2)


def lights(p):
    """Crimson running lights (the boom tips and the mast carry the rest)."""
    for sx in (-1, 1):
        p.box(V((sx * 0.94, -3.2, 0.72)), (0.07, 0.14, 0.07), "light", bevel=0.0)
        p.box(V((sx * 0.3, 5.72, 0.3)), (0.06, 0.1, 0.05), "light", bevel=0.0)
    p.box(V((0, -4.32, 1.1)), (0.14, 0.07, 0.05), "light", bevel=0.0)
    p.box(V((0, 0.45, -DECK_Z - 0.83)), (0.1, 0.2, 0.04), "light", bevel=0.0)


def build_glow():
    p = parts.Part("engine_glow", MATS)
    # Built around the bell exit plane at y = 0; the object origin is moved to NOZZLE_Y.
    parts.exhaust_glow(p, BELL_R * 0.74, 1.7, "glow", segs=18)
    return p


def build_ship():
    rng = random.Random(4471)
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    root = parts.make_root(PRE)
    hull = build_hull(rng).finish(root)
    glow = build_glow().finish(root)
    glow.location = (0, NOZZLE_Y, 0)
    for name, sx in (("muzzle_l", -1), ("muzzle_r", 1)):
        parts.add_empty(name, root, (sx * GUN_X, MUZZLE_Y, GUN_Z), size=0.6)
    return root, hull, glow


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, hull, glow = build_ship()
    bpy.context.view_layer.update()
    if "--no-textures" not in argv:
        glow.hide_render = True
        wk.texture([hull], MATS, PRE, [(0.0, 0.0)], scorch=SCORCH, decals=DECALS,
                   labels=LABELS, seed0=313)
        glow.hide_render = False
    else:
        hull.data.uv_layers.remove(hull.data.uv_layers["panel"])
    wk.stats([hull, glow])
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews(PRE, 15.0, target=(0, 0, 0))
    extra = [a.split("=", 1)[1] for a in argv if a.startswith("--extra=")]
    if extra:
        extra_views(extra[0])


def extra_views(out_dir):
    """Debug renders into out_dir (close-ups and the RTS camera angle); not part of the
    previews and never exported."""
    scene = bpy.context.scene
    cam = scene.camera
    if cam is None:
        common.setup_preview(cam_loc=(0, 0, 60), cam_target=(0, 0, 0), ortho_scale=20.0,
                             res=(1600, 1200), key_dir=(-0.5, 0.4, 0.75), key_energy=3.5)
        cam = scene.camera
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1200
    views = (("close", (-8, 12, 6), (0, 3.8, 0.0), 6.5),
             ("mid", (-9, 3, 9), (0, -0.3, 0.0), 7.5),
             ("belly", (-9, 7, -8), (0, 0, -0.4), 15.0),
             ("side", (-30, 0, 0), (0, 0, 0), 15.0),
             ("rear", (-8, -15, 7), (0, -4, 0.2), 9.0),
             ("front", (5, 20, 3), (0, 4, 0), 8.0),
             ("rts", (-6, -14, 30), (0, 0, 0), 24.0))
    for name, loc, tgt, ortho in views:
        cam.location = loc
        cam.rotation_euler = (V(tgt) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        cam.data.ortho_scale = ortho
        common.render(os.path.join(out_dir, f"corsair_{name}.png"))


main()
