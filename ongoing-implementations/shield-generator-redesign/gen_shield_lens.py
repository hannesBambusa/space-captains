"""Shield Generator, variant "lens": a projector ring lens (SG-01) in the worn-industrial
language of the redesigned buildings (defense turret, mercenary outpost, mining outpost).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python gen_shield_lens.py -- [--res=2048] [--no-textures] [--no-preview] [--check]

Design: a squat armoured drum carries the plant (four capacitor banks on outriggers on the
diagonals, two coolant radiator wings on +-X, a control cabin on the camera side, a service
block with umbilicals on +Y, a keel with two tanks below). From the deck a central column
holds a parabolic reflector bowl whose focus is the field cradle. Three gimballed pylons
(90 / 210 / 330 deg) hold a thick segmented field lens ring (r 12) level with the cradle;
twelve emitter prongs on the lens point inward at the field core, their tips cyan. HV
busbars on insulator posts run from each capacitor bank's insulator stacks to the column.
Colour has one meaning each: cyan = the field (emitter tips, lens coil slots, core,
capacitor charge strips), warm white floods / amber windows = work light, red / green /
white = nav lights, hazard = HV and moving edges.

Layout (Blender Z up, exported +Y up; Blender +Y = Godot -Z). Origin centre, play plane z 0.
  keel       z -5.6..-0.5, tanks r 6.0 at 240 / 300
  drum       r 9.6, z -0.6..7.2 (deck top z 7.2, r 8.6)
  caps       4 banks at r 13.5 on 45 / 135 / 225 / 315, z 0.4..7.0, charge strips z 1.6..6.2
  radiators  +-X, x 10.6..18.1, boom z 3.6
  cabin      -Y, y -9.1..-11.7, z 2.0..5.6
  service    +Y, y 9.0..12.6, link_point (0, 13.4, 3.6)
  column     r 2.3, z 7.2..15.2; bowl rim r 7.9 at z 18.45, vertex z 16.0 (focus = cradle)
  cradle     centre (0, 0, 22), clear sphere r 4.5; core r 0.9
  lens ring  r 12, section 1.9 x 1.7, z 21.15..22.85; prong tips r 6.3
  pylons     feet r 7.9 on the deck, yokes at r 12, bearing blocks z 20.9..23.1
Hierarchy: shield_generator (root empty) -> shield_base (atlas + flat lamps, origin 0),
  shield_emitter_glow (origin at the cradle centre), shield_capacitors (origin (0, 0, 1.6),
  the strip bottoms), shield_emitter_point, link_point (empties, unrotated).
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

REPO = "/Users/hannesalm/code/games/space-majesty"
sys.path.insert(0, os.path.join(REPO, "blender"))
import common  # noqa: E402
import parts  # noqa: E402
import station_textures as st  # noqa: E402
import worn_kit as wk  # noqa: E402

# Work output (glb, blend, atlas, previews). Not the repo asset paths; the final script does that.
HERE = os.environ.get("SHIELD_OUT",
                      os.path.join(os.path.dirname(os.path.abspath(__file__)), "out"))
os.makedirs(HERE, exist_ok=True)
st.TEX_DIR = HERE
common.PREVIEW_DIR = HERE
OUT = os.path.join(HERE, "shield_generator.glb")
BLEND = os.path.join(HERE, "shield_generator.blend")
STATION_GLB = os.path.join(REPO, "assets", "models", "station", "station_home.glb")
TURRET_GLB = os.path.join(REPO, "assets", "models", "buildings", "defense_turret.glb")
PRE = "shield_lens"
KEY = "lens"

V = Vector
UP = V((0, 0, 1))
ALONG_X = parts.ALONG_X
ALONG_Y = parts.ALONG_Y

# ---------------------------------------------------------------- layout constants
CZ = 22.0
CORE = V((0.0, 0.0, CZ))
CRADLE_R = 4.5
CORE_R = 0.9
RING_R, RING_HW, RING_HH, RING_CH = 12.0, 0.95, 0.85, 0.3
DRUM_R, DECK_Z, DECK_R = 9.6, 7.2, 8.6
CAP_R, CAP_Z0, CAP_Z1 = 13.5, 1.6, 6.2
CAP_ANGLES = (225, 315, 45, 135)        # bank 1..4, camera side first
PYLONS = (90, 210, 330)
NODES = [15 + 30 * k for k in range(12)]
JOINTS = [30 * k for k in range(12)]
TIP_R = 6.3
LINK = V((0.0, 13.4, 3.6))
NO_PADS = [(0.0, 900.0), (0.0, 901.0)]
FOOTPRINT_MAX = 20.0
HEIGHT_MAX = 44.0
FIELD_COL = (0.32, 0.72, 1.0)

LABELS = ["SG-01", "HV", "DANGER HV", "FIELD EMITTER", "NO STEP", "KEEP CLEAR",
          "CAP BANK 1", "CAP BANK 2", "CAP BANK 3", "CAP BANK 4", "COOLANT", "PWR IN", "SVC",
          "EVA", "HOT", "#BAR", "LENS A", "LENS B", "LENS C", "FOCUS", "#CHEV"]
INK_DARK, INK_LIGHT = wk.INK_DARK, wk.INK_LIGHT
HAZ_INK = (0.36, 0.26, 0.04)
ID_BLUE = (0.045, 0.085, 0.17)

MATS = {}
DECALS = []
SCORCH = []
B = G = CP = None
RNG = random.Random(117)

strut = parts.strut
pipe = parts.pipe
window = parts.window


def polar(r, a_deg, z=0.0):
    return wk.polar(r, math.radians(a_deg), z)


def rad_t(a_deg):
    a = math.radians(a_deg)
    return V((math.cos(a), math.sin(a), 0.0)), V((-math.sin(a), math.cos(a), 0.0))


# ---------------------------------------------------------------- station look
def _kind(base, **kw):
    d = dict(st.WORN_KINDS[base])
    d.update(kw)
    return d


FINE = dict(chip_scale=9.0, edge_cut=(0.35, 0.75))
st.WORN_KINDS["hull"] = _kind("hull", tones=[(0.37, 0.37, 0.36), (0.335, 0.34, 0.34),
                              (0.41, 0.405, 0.39), (0.29, 0.30, 0.305), (0.355, 0.345, 0.33),
                              (0.32, 0.33, 0.34)], plate_var=0.07, grime_k=0.7, streak_k=0.55,
                              chip_k=0.7, chip=(0.25, 0.255, 0.26), hatches=0.14,
                              big=(4.0, 3.0), plate=(2.0, 1.5), **FINE)
st.WORN_KINDS["hull2"] = _kind("hull2", big=(3.4, 2.1), plate=(0.85, 1.05), grime_k=0.6,
                               chip_k=0.65, **FINE)
st.WORN_KINDS["hull3"] = _kind("hull3", big=(2.6, 2.6), plate=(1.3, 1.3), grime_k=0.8,
                               chip_k=0.7, chip=(0.22, 0.225, 0.23), **FINE)
st.WORN_KINDS["dark"] = _kind("dark", big=(1.4, 1.4), plate=(0.7, 0.7), **FINE)
st.WORN_KINDS["pad"] = _kind("pad", big=(2.1, 2.1), plate=(1.05, 1.05), **FINE)
st.WORN_KINDS["radiator"] = _kind("radiator", tones=[(0.40, 0.405, 0.41), (0.37, 0.375, 0.38),
                                  (0.43, 0.435, 0.44), (0.36, 0.365, 0.37), (0.39, 0.395, 0.40),
                                  (0.38, 0.385, 0.39)], grime_k=1.0, streak_k=0.45)
st.WORN_KINDS["slate"] = _kind("hull3", tones=[(0.16, 0.19, 0.225), (0.145, 0.175, 0.205),
                               (0.175, 0.205, 0.24), (0.135, 0.16, 0.185), (0.165, 0.185, 0.21),
                               (0.15, 0.17, 0.2)], plate_var=0.06, chip_k=0.75, grime_k=0.7,
                               bleach=0.35, chip=(0.26, 0.265, 0.27), big=(2.6, 2.6),
                               plate=(1.3, 1.3), **FINE)
st.WORN_KINDS["radfine"] = _kind("radiator", tones=[(0.085, 0.09, 0.098), (0.08, 0.085, 0.092),
                                 (0.09, 0.095, 0.103), (0.078, 0.082, 0.09),
                                 (0.088, 0.092, 0.1), (0.082, 0.087, 0.095)], big=(2.9, 6.0),
                                 plate=(0.06, 6.0), rough=(0.56, 0.05), metal=0.12,
                                 seam_big=0.08, seam_small=0.035, chip_k=0.15, grime_k=0.4,
                                 streak_k=0.2, bleach=0.0, fins=False)
st.WORN_KINDS["tank"] = _kind("hull2", tones=[(0.115, 0.125, 0.14), (0.10, 0.11, 0.123),
                              (0.125, 0.135, 0.15), (0.095, 0.104, 0.115), (0.12, 0.126, 0.135),
                              (0.108, 0.117, 0.13)], plate_var=0.04, rough=(0.48, 0.1),
                              metal=0.25, big=(2.4, 1.6), plate=(1.2, 0.8), grime_k=0.7,
                              chip_k=0.7, chip=(0.28, 0.28, 0.29), bleach=0.0, **FINE)
st.WORN_KINDS["deckplate"] = _kind("pad", tones=[(0.14, 0.142, 0.15), (0.128, 0.13, 0.137),
                                   (0.15, 0.152, 0.158), (0.122, 0.124, 0.13),
                                   (0.145, 0.143, 0.14), (0.134, 0.136, 0.142)], bleach=0.0,
                                   big=(1.2, 1.2), plate=(0.6, 0.6), pad=False, **FINE)
st.WORN_KINDS["gunmetal"] = _kind("metal", tones=[(0.12, 0.125, 0.132), (0.10, 0.105, 0.112),
                                  (0.135, 0.14, 0.147), (0.11, 0.115, 0.122),
                                  (0.145, 0.15, 0.157), (0.125, 0.13, 0.137)],
                                  rough=(0.40, 0.10), metal=0.8, chip=(0.50, 0.50, 0.52),
                                  chip_k=0.8, grime_k=1.0, streak_k=0.4, rivets=False,
                                  hatches=0.0, bleach=0.0, **FINE)
# Reflector bowl petals: satin light grey, fine radial seams, no rivets, low grime.
st.WORN_KINDS["dish"] = _kind("hull2", tones=[(0.27, 0.28, 0.29), (0.25, 0.26, 0.27),
                              (0.29, 0.295, 0.30), (0.24, 0.25, 0.26), (0.28, 0.285, 0.29),
                              (0.26, 0.27, 0.28)], plate_var=0.03, rough=(0.34, 0.06),
                              metal=0.45, big=(2.2, 2.0), plate=(1.1, 1.0), seam_big=0.3,
                              seam_small=0.08, rivets=False, hatches=0.0, grime_k=0.35,
                              streak_k=0.15, chip_k=0.3, bleach=0.0, **FINE)


def build_materials():
    m = common.make_material
    wk.build_materials(PRE, MATS)
    MATS["slate"] = m(f"{PRE}_hull_slate", (0.16, 0.19, 0.22), roughness=0.58)
    MATS["gunmetal"] = m(f"{PRE}_gunmetal", (0.12, 0.125, 0.135), roughness=0.4, metallic=0.8)
    MATS["radfine"] = m(f"{PRE}_radiator_wing", (0.085, 0.09, 0.098), roughness=0.56,
                        metallic=0.12)
    MATS["tank"] = m(f"{PRE}_tank", (0.115, 0.125, 0.14), roughness=0.48, metallic=0.25)
    MATS["deckplate"] = m(f"{PRE}_deck_plate", (0.14, 0.142, 0.15), roughness=0.7, metallic=0.2)
    MATS["dish"] = m(f"{PRE}_reflector", (0.27, 0.28, 0.29), roughness=0.34, metallic=0.45)
    glow = (0.03, 0.028, 0.025)
    for key, col, s in (("nav_red", (1.0, 0.08, 0.03), 6.0), ("nav_green", (0.08, 1.0, 0.22), 6.0),
                        ("nav_white", (1.0, 0.97, 0.92), 4.0), ("flood", (1.0, 0.95, 0.85), 4.5)):
        MATS[key] = m(f"{PRE}_{key}", glow, roughness=0.3, emission=col, emission_strength=s)
        MATS[key].use_backface_culling = False
    # The two Godot-driven materials: one each, flat cyan.
    MATS["field"] = m(f"{PRE}_field_emitter", (0.05, 0.11, 0.16), roughness=0.3,
                      emission=FIELD_COL, emission_strength=3.0)
    MATS["charge"] = m(f"{PRE}_field_charge", (0.05, 0.11, 0.16), roughness=0.3,
                       emission=FIELD_COL, emission_strength=2.5)


# ---------------------------------------------------------------- helpers (turret kit)
def label(text, centre, normal, up, h, colour, opacity=0.85, depth=0.6):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity, depth))


def up_for(n_up):
    n_up = V(n_up)
    return n_up if n_up.y >= -1e-3 else -n_up


def nav(part, c, mat, s=0.5, hang=False):
    c = V(c)
    d = 1.0 if hang else -1.0
    part.box(c + V((0, 0, d * s * 0.45)), (s * 0.7, s * 0.7, s * 0.4), "dark", bevel=0.0)
    part.box(c, (s, s, s * 0.6), mat, bevel=0.0)


def handrail(p, pts, hgt=0.9, t=0.06):
    up = UP * hgt
    for a, b in zip(pts, pts[1:]):
        strut(p, a + up, b + up, t, t, "metal")
        strut(p, a + up * 0.5, b + up * 0.5, t * 0.8, t * 0.8, "metal")
    for a in pts:
        strut(p, a, a + up, t, t, "metal")


def hazard_band(p, c0, c1, w, h, up=UP, pitch=0.9):
    c0, c1 = V(c0), V(c1)
    n = max(2, int((c1 - c0).length / pitch))
    for i in range(n):
        p.beam(c0.lerp(c1, i / n), c0.lerp(c1, (i + 1) / n), w, h,
               "hazard" if i % 2 == 0 else "dark", up=up)


def bracket_pipe(p, p0, p1, rad, mat, step=2.0, drop=0.3):
    p0, p1 = V(p0), V(p1)
    pipe(p, p0, p1, rad, mat, segs=6)
    n = max(1, int((p1 - p0).length / step))
    for k in range(n + 1):
        q = p0.lerp(p1, k / n)
        p.box(q - V((0, 0, drop * 0.5)), (0.25, 0.25, drop + rad), "dark", bevel=0.0)


def bolt_row(p, c0, c1, n, s=0.09, mat="dark"):
    c0, c1 = V(c0), V(c1)
    for k in range(n):
        p.box(c0.lerp(c1, (k + 0.5) / n), (s, s, s), mat, bevel=0.0)


def ring_pts(r, a0, a1, z, step_m=1.2):
    n = max(1, round(math.radians(a1 - a0) * r / step_m))
    return [polar(r, a0 + (a1 - a0) * k / n, z) for k in range(n + 1)]


def smooth_path(pts, rad, steps=6):
    pts = [V(q) for q in pts]
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        a, c, b = pts[i - 1], pts[i], pts[i + 1]
        r = min(rad, 0.45 * (c - a).length, 0.45 * (b - c).length)
        p0 = c + (a - c).normalized() * r
        p1 = c + (b - c).normalized() * r
        for k in range(steps + 1):
            t = k / steps
            out.append(p0 * (1 - t) ** 2 + c * 2 * t * (1 - t) + p1 * t * t)
    out.append(pts[-1])
    return [q for i, q in enumerate(out) if i == 0 or (q - out[i - 1]).length > 1e-4]


def rrect(w, h, cr, n=2):
    pts = []
    for cx, cy, a0 in ((1, 1, 0.0), (-1, 1, 90.0), (-1, -1, 180.0), (1, -1, 270.0)):
        for k in range(n + 1):
            a = math.radians(a0 + 90.0 * k / n)
            pts.append((cx * (w / 2 - cr) + cr * math.cos(a), cy * (h / 2 - cr) + cr * math.sin(a)))
    return pts


def sweep(p, path, w, h, mat, side, cr=0.06, cap=True, n=2):
    side = V(side).normalized()
    sec = rrect(w, h, cr, n)
    rings = []
    for i, c in enumerate(path):
        t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        t = (t - side * t.dot(side)).normalized()
        u = side.cross(t)
        rings.append([c + side * x + u * y for x, y in sec])
    p.loft(rings, mat, cap=cap)


def path_points(path, step, skip0=0.0, skip1=0.0):
    segs = [(a, b, (b - a).length) for a, b in zip(path, path[1:])]
    total = sum(s[2] for s in segs)
    out = []
    n = max(1, int((total - skip0 - skip1) / step))
    for k in range(n + 1):
        s = skip0 + (total - skip0 - skip1) * k / n
        for a, b, ln in segs:
            if s <= ln or (a, b, ln) == segs[-1]:
                f = min(1.0, s / ln) if ln > 0 else 0.0
                out.append((a.lerp(b, f), (b - a).normalized()))
                break
            s -= ln
    return out


def box_ra(p, r, a_deg, z, size, mat, bevel=0.0):
    """Box centred at polar(r, a, z), local X radial (size = radial, tangential, height)."""
    p.box(polar(r, a_deg, z), size, mat, rot_z=math.radians(a_deg), bevel=bevel)


def member(p, p0, p1, w0, h0, w1, h1, mat, side):
    """Tapered rectangular member p0 -> p1 (w along `side`, h across), capped."""
    p0, p1 = V(p0), V(p1)
    x = (p1 - p0).normalized()
    s = (V(side) - x * V(side).dot(x)).normalized()
    u = x.cross(s)

    def ring(c, w, h):
        return [c + s * a * w / 2 + u * b * h / 2 for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    p.loft([ring(p0, w0, h0), ring(p1, w1, h1)], mat)


def tank_prof(r, z0, z1, zb0, zb1, steps):
    dome = r * 0.55
    prof = [(0.0, z0)]
    for k in range(1, steps + 1):
        a = math.pi / 2 * k / steps
        prof.append((r * math.sin(a), z0 + dome * (1 - math.cos(a))))
    prof += [(r, zb0), (r, zb1)]
    for k in range(0, steps + 1):
        a = math.pi / 2 * k / steps
        prof.append((r * math.cos(a), z1 - dome + dome * math.sin(a)))
    prof[-1] = (0.0, z1)
    return prof


def tank_v(p, c, r, h, body, band="dark", segs=16, steps=4):
    x, y, z0 = c
    dome = r * 0.55
    zb0 = z0 + dome + (h - 2 * dome) * 0.62
    prof = tank_prof(r, z0, z0 + h, zb0, zb0 + (h - 2 * dome) * 0.1, steps)
    p.lathe(prof, segs, lambda i, j: band if j == steps + 1 else body,
            matrix=Matrix.Translation((x, y, 0)))


def ring_sec(hw, hh, ch):
    """Chamfered (r, z) section around (0, 0): edges 0 outer, 2 top, 4 inner, 6 bottom."""
    return [(hw, -hh + ch), (hw, hh - ch), (hw - ch, hh), (-hw + ch, hh), (-hw, hh - ch),
            (-hw, -hh + ch), (-hw + ch, -hh), (hw - ch, -hh)]


def ring_band(p, a_deg, half_deg, scale, mat, steps=1):
    """Collar round the lens ring section at angle a (scaled section, +-half_deg)."""
    sec = ring_sec(RING_HW * scale, RING_HH * scale, RING_CH * scale)
    rings = []
    for k in range(steps + 1):
        a = math.radians(a_deg - half_deg + 2 * half_deg * k / steps)
        rd = V((math.cos(a), math.sin(a), 0))
        rings.append([rd * (RING_R + u) + V((0, 0, CZ + v)) for u, v in sec])
    p.loft(rings, mat)


# ---------------------------------------------------------------- keel
def build_keel():
    patch = [RNG.choice(("hull2", "slate", "tank")) for _ in range(4)]
    B.lathe([(0.0, -5.6), (2.0, -5.6), (3.0, -5.0), (3.4, -1.2), (4.4, -0.5)], 16,
            lambda i, j: "dark" if j < 2 else patch[i // 4], start=math.pi / 16)
    for z in (-4.2, -2.8):
        B.cyl(V((0, 0, z)), 3.3, 3.3, 0.28, "dark", segs=16)
    nav(B, V((0, 0, -5.78)), "nav_white", 0.45, hang=True)
    for k, a in enumerate((240, 300)):
        c = polar(6.0, a, -4.4)
        tank_v(B, (c.x, c.y, c.z), 1.1, 3.95, "tank", band="dark" if k == 0 else "slate")
        for z in (-3.6, -1.9):
            B.beam(polar(4.95, a, z), polar(3.3, a, z), 0.25, 0.25, "dark")
    for k in range(6):
        a = 30 + 60 * k
        strut(B, polar(3.3, a, -3.2), polar(7.2, a, -0.55), 0.24, 0.24, "dark")
    label("HV", polar(3.36, 270, -3.5), polar(1.0, 270), UP, 0.3, INK_LIGHT)
    build_underside()


def build_underside():
    """Drum floor (z -0.6, r 4.4..7.6): radial ribs, hatches, a conduit ring, sensor pods."""
    zf = -0.6
    for k in range(8):
        a = 22.5 + 45 * k
        if a in (247.5, 292.5):     # keep the tank bays clear
            continue
        B.beam(polar(4.5, a, zf - 0.12), polar(7.5, a, zf - 0.12), 0.32, 0.24, "dark")
    for k in range(4):
        a = 45 + 90 * k
        box_ra(B, 6.1, a, zf - 0.03, (1.3, 1.1, 0.06), "deckplate")
        box_ra(B, 6.1 + 0.55, a, zf - 0.07, (0.06, 0.3, 0.04), "metal")
    pts = ring_pts(7.05, 0, 360, zf - 0.2, step_m=1.3)
    for a0, a1 in zip(pts, pts[1:]):
        pipe(B, a0, a1, 0.1, "metal", segs=6)
    for q in pts[::3]:
        B.box(q + V((0, 0, 0.08)), (0.22, 0.22, 0.16), "dark", bevel=0.0)
    for a in (110, 160):
        c = polar(5.6, a, zf - 0.55)
        B.cyl(c + V((0, 0, 0.3)), 0.12, 0.12, 0.5, "dark", segs=6)
        B.cyl(c, 0.45, 0.32, 0.4, "gunmetal", segs=10)
        nav(B, c - V((0, 0, 0.3)), "nav_white", 0.18, hang=True)
    parts.dish(B, polar(6.3, 20, zf - 1.0), 0.7, V((0.3, 0.1, -0.95)), "hull", "dark",
               depth=0.22, segs=12)
    B.cyl(polar(6.3, 20, zf - 0.5), 0.08, 0.08, 0.7, "dark", segs=6)


# ---------------------------------------------------------------- drum
def build_drum():
    prof = [(0.0, -0.6), (7.6, -0.6), (9.2, 0.6), (DRUM_R, 1.2), (DRUM_R, 6.2), (9.2, 6.9),
            (DECK_R, DECK_Z), (0.0, DECK_Z)]
    em = {0: "dark", 1: "hull2", 2: "dark", 3: "body", 4: "hull2", 5: "dark", 6: "pad"}
    patch = [RNG.choice(("hull", "hull3", "slate", "hull", "hull2")) for _ in range(8)]
    for p_i in range(8):
        ca = (4 * p_i + 2) * 11.25
        if 225 <= ca <= 315:
            patch[p_i] = "hull"

    def mf(i, j):
        k = em[j]
        return patch[i // 4] if k == "body" else k
    B.lathe(prof, 32, mf, start=0.0)
    for z in (2.0, 5.2):
        B.cyl(V((0, 0, z)), DRUM_R + 0.05, DRUM_R + 0.05, 0.22, "dark", segs=32)
    # ribs, skipping the cabin, service block and radiator roots
    for k in range(32):
        a = k * 11.25 + 5.625
        if 250 < a < 290 or 70 < a < 110 or a < 12 or a > 348 or 168 < a < 192:
            continue
        box_ra(B, DRUM_R + 0.04, a, 3.6, (0.08, 0.12, 2.9), "metal")
    # windows: one regular strip either side of the cabin
    rf = DRUM_R * math.cos(math.pi / 32) + 0.01
    for k, a_d in enumerate((236, 243, 250, 290, 297, 304)):
        a = math.radians(a_d + 2.8)
        n = V((math.cos(a), math.sin(a), 0))
        lit = {0: "window", 2: "window_cool", 4: "window", 5: "window_dim"}.get(k)
        window(B, V((0, 0, 4.25)) + n * rf, n, UP, 0.42, 0.5, lit)
    label("SG-01", polar(DRUM_R + 0.02, 202, 3.55), polar(1.0, 202), UP, 1.15, INK_LIGHT,
          depth=1.2)
    label("SG-01", polar(DRUM_R + 0.02, 22, 3.55), polar(1.0, 22), UP, 1.15, INK_LIGHT,
          depth=1.2)
    label("#BAR", polar(DRUM_R + 0.02, 318, 1.55), polar(1.0, 318), UP, 0.22, ID_BLUE)
    # pipe run round the upper wall, bracketed
    for a0, a1 in ((195, 245), (295, 345), (15, 65), (115, 165)):
        pts = ring_pts(DRUM_R + 0.14, a0, a1, 5.75, step_m=1.4)
        for a, b in zip(pts, pts[1:]):
            pipe(B, a, b, 0.08, "metal", segs=6)
        for q in pts[::2]:
            B.box(q - q.normalized().to_2d().to_3d() * 0.06, (0.18, 0.18, 0.26), "dark",
                  bevel=0.0)
    # wall greebles
    for a, z, s, mat in ((214, 2.6, (0.14, 0.7, 0.5), "hull2"), (340, 3.3, (0.12, 0.5, 0.6),
                         "dark"), (35, 2.6, (0.14, 0.6, 0.5), "hull2"),
                         (160, 3.5, (0.12, 0.45, 0.4), "dark"), (128, 3.3, (0.14, 0.7, 0.5),
                         "hull2"), (52, 3.2, (0.12, 0.4, 0.45), "dark")):
        box_ra(B, DRUM_R + s[0] / 2, a, z, s, mat, bevel=0.02)
    # RCS quads on the shoulder
    for a in (0, 180, 90, 270):
        aa = a + 22.5
        box_ra(B, 9.55, aa, 6.55, (0.3, 0.4, 0.4), "dark")
        parts.rcs_quad(B, polar(9.85, aa, 6.55), polar(1.0, aa), "hull2", "dark", s=0.32, fwd=UP)
        c = polar(9.85, aa, 6.55)
        SCORCH.append((c.x, c.y, c.z, 0.9))
    # open ring truss under the drum skirt
    for k in range(8):
        a0, a1 = 22.5 + 45 * k, 22.5 + 45 * (k + 1)
        strut(B, polar(8.4, a0, 0.0), polar(8.4, a1, 0.0), 0.2, 0.2, "dark")


# ---------------------------------------------------------------- capacitor banks
def cab_ring(a_deg, hr, ht, c, z):
    """Chamfered-rectangle ring round the bank at angle a: hr radial, ht tangential half
    sizes, chamfer c. Edges 0 outer face, 2 / 6 sides, 4 inner face, odd = chamfers."""
    rd, t = rad_t(a_deg)
    o = polar(CAP_R, a_deg, z)
    sec = [(hr, -ht + c), (hr, ht - c), (hr - c, ht), (-hr + c, ht), (-hr, ht - c),
           (-hr, -ht + c), (-hr + c, -ht), (hr - c, -ht)]
    return [o + rd * x + t * y for x, y in sec]


def cab_prism(p, a_deg, hr, ht, c, z0, z1, mat):
    p.loft([cab_ring(a_deg, hr, ht, c, z0), cab_ring(a_deg, hr, ht, c, z1)], mat)


def cab_body(p, a_deg, body):
    """Cabinet z 0.85..7.0: straight walls to 6.3, then a shoulder sloping in 0.35 m."""
    rings = [cab_ring(a_deg, 2.0, 2.5, 0.45, 0.85), cab_ring(a_deg, 2.0, 2.5, 0.45, 6.3),
             cab_ring(a_deg, 1.65, 2.15, 0.45, 6.95)]

    def mf(i, j):
        if i == 1:
            return "dark"
        return "gunmetal" if j % 2 else body
    p.loft(rings, body, mat_fn=mf)


def build_caps():
    for n, a in enumerate(CAP_ANGLES):
        rd, t = rad_t(a)
        ar = math.radians(a)
        r0, r1 = CAP_R - 2.0, CAP_R + 2.0
        # cabinet: octagonal plinth, chamfered body (gunmetal corner posts), sloped shoulder
        body = "hull2" if n % 2 == 0 else "hull3"
        cab_prism(B, a, 2.15, 2.65, 0.55, 0.4, 0.9, "dark")
        cab_body(B, a, body)
        cab_prism(B, a, 2.06, 2.56, 0.47, 3.95, 4.15, "dark")
        box_ra(B, CAP_R - 0.4, a, 7.07, (1.5, 3.4, 0.25), "dark")
        label("HV", polar(CAP_R + 0.95, a, 6.96), UP, up_for(t), 0.8, INK_LIGHT, 0.85, depth=0.3)
        # roof: breaker box on one corner, vent grille on the other
        B.box(polar(CAP_R + 1.0, a, 7.2) + t * 1.5, (0.7, 0.8, 0.5), "gunmetal", rot_z=ar,
              bevel=0.05)
        for k in range(5):
            B.box(polar(CAP_R - 0.9 + k * 0.42, a, 7.0) - t * 1.6, (0.2, 0.9, 0.1), "dark",
                  rot_z=ar, bevel=0.0)
        # outer face: visor over the charge strips, side pilasters
        box_ra(B, r1 + 0.32, a, CAP_Z1 + 0.42, (0.64, 4.0, 0.14), "dark")
        for s in (-1, 1):
            B.box(polar(r1 + 0.12, a, 3.6) + t * s * 1.98, (0.24, 0.16, 5.4), "gunmetal",
                  rot_z=ar, bevel=0.0)
        # side faces: raised label plate
        for s in (-1, 1):
            B.box(polar(CAP_R, a, 5.25) + t * s * 2.52, (3.0, 0.06, 1.75), "slate", rot_z=ar,
                  bevel=0.0)
        # side cooling fin packs (lower half), labels above them
        for s in (-1, 1):
            for k in range(7):
                ro = -1.5 + k * 0.5
                B.box(polar(CAP_R + ro, a, 2.45) + t * s * 2.66, (0.06, 0.32, 2.4), "metal",
                      rot_z=ar, bevel=0.0)
            for z in (1.2, 3.7):
                B.box(polar(CAP_R, a, z) + t * s * 2.66, (3.3, 0.36, 0.1), "dark", rot_z=ar,
                      bevel=0.0)
        # inner face junction box
        box_ra(B, r0 - 0.2, a, 5.6, (0.4, 1.6, 1.0), "gunmetal", bevel=0.05)
        # outer face: recessed dark charge panel, three strips, bolt rows
        box_ra(B, r1 + 0.03, a, (CAP_Z0 + CAP_Z1) / 2, (0.08, 3.9, CAP_Z1 - CAP_Z0 + 0.6), "dark")
        for o in (-1.25, 0.0, 1.25):
            c = polar(r1 + 0.09, a, (CAP_Z0 + CAP_Z1) / 2) + t * o
            CP.box(c, (0.06, 0.34, CAP_Z1 - CAP_Z0), "charge", rot_z=ar, bevel=0.0)
            for s in (-1, 1):   # dark slot cheeks either side of each strip
                B.box(polar(r1 + 0.1, a, (CAP_Z0 + CAP_Z1) / 2) + t * (o + s * 0.24),
                      (0.1, 0.1, CAP_Z1 - CAP_Z0 + 0.3), "gunmetal", rot_z=ar, bevel=0.0)
        bolt_row(B, polar(r1 + 0.05, a, 6.0) - t * 1.75, polar(r1 + 0.05, a, 6.0) + t * 1.75, 8,
                 0.07, "metal")
        hazard_band(B, polar(r1 + 0.06, a, 1.0) - t * 1.9, polar(r1 + 0.06, a, 1.0) + t * 1.9,
                    0.06, 0.18, up=UP, pitch=0.4)
        # side faces: labels, vents
        for s in (-1, 1):
            fc = polar(CAP_R, a, 4.4) + t * s * 2.56
            label(f"CAP BANK {n + 1}", fc + V((0, 0, 1.3)), t * s, UP, 0.62, INK_LIGHT)
            label("DANGER HV", fc + V((0, 0, 0.55)), t * s, UP, 0.42, HAZ_INK, 0.9)
        # insulator stacks + HV terminals on the roof
        for s in (-1, 1):
            base = polar(CAP_R - 0.4, a, 7.27) + t * s * 1.1
            B.cyl(base + V((0, 0, 0.2)), 0.55, 0.55, 0.3, "dark", segs=10)
            B.cyl(base + V((0, 0, 1.1)), 0.22, 0.22, 1.6, "dark", segs=8)
            for k in range(5):
                B.cyl(base + V((0, 0, 0.5 + k * 0.3)), 0.48 - k * 0.02, 0.48 - k * 0.02, 0.12,
                      "radiator", segs=12)
            B.cyl(base + V((0, 0, 2.0)), 0.32, 0.32, 0.24, "metal", segs=10)
        # struts and a cable tray to the drum
        for z in (1.6, 5.8):
            for s in (-1, 1):
                strut(B, polar(r0, a, z) + t * s * 1.6, polar(DRUM_R - 0.1, a, z) + t * s * 1.2,
                      0.26, 0.26, "dark")
        strut(B, polar(r0, a, 1.6), polar(DRUM_R - 0.1, a, 5.8) + t * 1.2, 0.16, 0.16, "metal")
        B.beam(polar(r0 + 0.05, a, 4.0), polar(DRUM_R - 0.05, a, 4.0), 0.9, 0.12, "dark")
        for k in range(3):
            pipe(B, polar(r0 + 0.05, a, 4.12) + t * (-0.25 + k * 0.25),
                 polar(DRUM_R - 0.05, a, 4.12) + t * (-0.25 + k * 0.25), 0.07,
                 ("metal", "dark", "metal")[k], segs=5)


# ---------------------------------------------------------------- HV busbars
def build_busbars():
    for a in CAP_ANGLES:
        rd, t = rad_t(a)
        for s in (-1, 1):
            p0 = polar(CAP_R - 0.4, a, 9.38) + t * s * 1.1
            pts = [p0, p0 + V((0, 0, 0.55)), polar(10.0, a, 9.93) + t * s * 0.9,
                   polar(6.0, a, 9.93) + t * s * 0.5, polar(2.15, a, 9.93) + t * s * 0.5]
            path = smooth_path(pts, 0.6, steps=3)
            sweep(B, path, 0.3, 0.2, "gunmetal", t, cr=0.05, n=1)
            for c, tg in path_points(path, 1.6, skip0=0.6, skip1=0.4):
                B.beam(c - tg * 0.07, c + tg * 0.07, 0.4, 0.3, "dark",
                       up=t.cross(tg).normalized())
        # support posts on the drum rim and on the deck, insulator on top
        for r, z0 in ((9.15, 6.95), (6.2, DECK_Z)):
            for s in (-1, 1):
                q = polar(r, a, 0) + t * s * (0.9 if r > 8 else 0.5)
                B.box(V((q.x, q.y, z0 + 0.1)), (0.5, 0.5, 0.2), "dark", bevel=0.0)
                B.cyl(V((q.x, q.y, (z0 + 9.75) / 2)), 0.1, 0.1, 9.75 - z0, "dark", segs=6)
                for k in range(3):
                    B.cyl(V((q.x, q.y, 9.2 + k * 0.17)), 0.24, 0.24, 0.08, "radiator", segs=8)
            if r < 8:
                c = polar(r, a, DECK_Z + 0.01)
                label("HV", c - rd * 0.9, UP, up_for(t), 0.3, HAZ_INK, 0.85, depth=0.3)
    # bus collars where the bars land on the column
    B.cyl(V((0, 0, 9.93)), 2.45, 2.45, 0.6, "gunmetal", segs=24)
    for k in range(8):
        box_ra(B, 2.48, 45 * k, 9.93, (0.12, 0.3, 0.7), "metal")


# ---------------------------------------------------------------- deck
def build_deck():
    zd = DECK_Z
    # inset plates and hatches
    for a, r, s in ((20, 6.7, (1.3, 1.1)), (160, 6.6, (1.1, 1.2)), (250, 5.2, (1.0, 0.9)),
                    (290, 5.2, (1.0, 0.9)), (110, 5.0, (0.9, 0.8)), (180, 4.6, (0.8, 1.0))):
        box_ra(B, r, a, zd + 0.02, (s[0], s[1], 0.05), "deckplate")
        box_ra(B, r + s[0] / 2 - 0.12, a, zd + 0.06, (0.05, 0.24, 0.04), "metal")
    for a in (0, 180):
        c = polar(7.3, a, zd)
        box_ra(B, 7.3, a, zd + 0.04, (1.3, 1.3, 0.08), "deckplate")
        for dx, dy, w, l in ((0.68, 0, 0.1, 1.46), (-0.68, 0, 0.1, 1.46), (0, 0.68, 1.36, 0.1),
                             (0, -0.68, 1.36, 0.1)):
            r3 = Matrix.Rotation(math.radians(a), 4, "Z").to_3x3()
            B.box(c + r3 @ V((dx, dy, 0.06)), (w, l, 0.1), "dark", rot_z=math.radians(a),
                  bevel=0.0)
        label("EVA", polar(7.3, a, zd + 0.1), UP, up_for(rad_t(a)[1]), 0.3, INK_LIGHT)
    # hazard ring round the column foot
    pts = ring_pts(4.0, 0, 360, zd + 0.03, step_m=0.7)
    for k, (p0, p1) in enumerate(zip(pts, pts[1:])):
        B.beam(p0, p1, 0.32, 0.05, "hazard" if k % 2 == 0 else "dark")
    label("KEEP CLEAR", polar(4.85, 270, zd + 0.01), UP, V((0, 1, 0)), 0.5, INK_LIGHT)
    label("NO STEP", polar(6.7, 200, zd + 0.01), UP, up_for(rad_t(200)[1]), 0.3, INK_LIGHT)
    label("FOCUS", polar(4.75, 90, zd + 0.01), UP, V((0, 1, 0)), 0.3, INK_LIGHT)
    # deck floods aimed at the column
    for a in (255, 285):
        rd, t = rad_t(a)
        B.box(polar(7.6, a, zd + 0.08), (0.3, 0.3, 0.16), "dark", bevel=0.0)
        box_ra(B, 7.6, a, zd + 0.34, (0.42, 0.4, 0.34), "dark", bevel=0.03)
        d = (-rd + V((0, 0, 0.7))).normalized()
        parts.quad(B, polar(7.6, a, zd + 0.34) - rd * 0.22, d, UP, 0.3, 0.2, "flood")
    # handrail round the deck edge, gaps at the pylon feet
    for k, a in enumerate(PYLONS):
        a0, a1 = a + 14, PYLONS[(k + 1) % 3] - 14
        if a1 < a0:
            a1 += 360
        handrail(B, ring_pts(8.35, a0, a1, zd, step_m=1.5))
    # cleats on the rim
    for k in range(24):
        a = k * 15 + 7.5
        if any(abs(((a - p + 180) % 360) - 180) < 12 for p in PYLONS):
            continue
        box_ra(B, 8.85, a, 7.03, (0.18, 0.34, 0.12), "dark")


# ---------------------------------------------------------------- column + reflector
def build_column():
    def cm(i, j):
        if j in (0, 3):
            return "dark"
        return "slate" if (i // 3) % 2 else "hull2"
    B.lathe([(3.6, DECK_Z + 0.01), (3.0, 7.9), (2.3, 8.6), (2.3, 14.0), (2.9, 15.3)], 24, cm,
            start=math.pi / 24)
    for z in (8.9, 11.6, 13.2):
        B.cyl(V((0, 0, z)), 2.38, 2.38, 0.2, "dark", segs=24)
    # four field feeders up the column (busbars from the collar into the bowl)
    for k in range(4):
        a = 45 + 90 * k
        rd, t = rad_t(a)
        p0, p1 = polar(2.45, a, 10.3), polar(2.45, a, 14.1)
        B.beam(p0, p1, 0.24, 0.16, "metal", up=rd)
        for z in (11.0, 12.2, 13.4):
            box_ra(B, 2.5, a, z, (0.22, 0.4, 0.14), "dark")
    # hatch + ladder on the camera side
    B.box(polar(2.33, 270, 11.0), (1.0, 0.08, 1.6), "hull2", rot_z=0, bevel=0.0)
    B.box(polar(2.36, 270, 11.0), (0.8, 0.06, 1.4), "dark", bevel=0.0)
    for k in range(6):
        B.box(polar(2.5, 250, 8.9 + k * 0.45), (0.06, 0.6, 0.05), "metal",
              rot_z=math.radians(250), bevel=0.0)


def build_bowl():
    """Parabolic reflector: focus at the cradle centre (f = 6), rim r 7.9."""
    f = CZ - 16.0
    inner = [(r, 16.0 + r * r / (4 * f)) for r in (7.45, 6.4, 5.2, 3.9, 2.5, 1.2, 0.0)]
    prof = [(0.0, 14.9), (2.6, 15.05), (5.4, 16.15), (7.5, 17.75), (7.95, 18.45), (7.95, 18.6),
            (7.5, 18.6)] + inner
    n_out = 4

    def mf(i, j):
        if j < n_out:
            return "hull2" if j < 2 else ("slate" if i % 2 else "hull2")
        if j < 6:
            return "dark"
        return "dish" if i % 2 == 0 else "deckplate"
    B.lathe(prof, 32, mf, start=0.0)
    # rim brackets and radial ribs underneath
    for k in range(16):
        a = k * 22.5
        box_ra(B, 7.98, a, 18.35, (0.2, 0.36, 0.6), "dark")
    for k in range(8):
        a = 22.5 * (2 * k + 1) / 2 * 2 - 11.25
        strut(B, polar(2.3, a, 14.6), polar(7.3, a, 17.4), 0.22, 0.42, "dark")
    # feed stub at the vertex, outside the cradle
    B.cyl(V((0, 0, 16.3)), 0.75, 0.55, 0.6, "gunmetal", segs=12)
    B.cyl(V((0, 0, 16.82)), 0.42, 0.34, 0.44, "dark", segs=12)
    B.cyl(V((0, 0, 17.08)), 0.36, 0.36, 0.08, "metal", segs=12)


# ---------------------------------------------------------------- lens ring
def build_ring():
    sec = ring_sec(RING_HW, RING_HH, RING_CH)
    prof = [(RING_R + u, CZ + v) for u, v in sec] + [(RING_R + sec[0][0], CZ + sec[0][1])]

    def mf(i, j):
        seg = i // 4
        if j == 4:
            return "dark"
        if j == 2:
            return "hull" if seg % 3 == 0 else "hull2"
        if j == 0:
            return "slate" if seg % 2 else "hull2"
        if j in (1, 3):
            return "dark"
        return "hull2"
    B.lathe(prof, 48, mf, start=0.0)
    # coil channel along the inner top edge (field winding duct)
    zt = CZ + RING_HH
    B.lathe([(11.3, zt - 0.02), (11.3, zt + 0.26), (11.42, zt + 0.36), (11.68, zt + 0.36),
             (11.8, zt + 0.26), (11.8, zt - 0.02)], 48,
            lambda i, j: "gunmetal" if j != 2 else ("dark" if i % 4 == 0 else "gunmetal"))
    for k in range(48):
        if k % 2 == 0:
            box_ra(B, 11.55, k * 7.5 + 3.75, zt + 0.37, (0.6, 0.12, 0.05), "metal")
    # joint collars (bearings at the pylons, plain collars elsewhere) + top straps
    for a in JOINTS:
        if a in PYLONS:
            continue
        ring_band(B, a, 1.4, 1.1, "dark")
        rd, t = rad_t(a)
        bolt_row(B, polar(RING_R - 0.6, a, CZ + RING_HH * 1.1 + 0.02) - t * 0.0,
                 polar(RING_R + 0.6, a, CZ + RING_HH * 1.1 + 0.02), 4, 0.07, "metal")
    for a in NODES:
        for o in (-7.5, 7.5):
            box_ra(B, 12.35, a + o, CZ + RING_HH + 0.02, (0.9, 0.28, 0.06), "metal")
            box_ra(B, RING_R + RING_HW + 0.02, a + o, CZ, (0.06, 0.28, 1.15), "metal")
    # walkway plate and an outer handrail on top of the ring, between the yokes
    for k, a in enumerate(PYLONS):
        a0, a1 = a + 9.5, PYLONS[(k + 1) % 3] - 9.5
        if a1 < a0:
            a1 += 360
        handrail(B, ring_pts(RING_R + 0.55, a0, a1, CZ + RING_HH, step_m=2.4), hgt=0.85,
                 t=0.06)
    # emitter nodes: housing on the inner face, tapered prong, collars, cyan tip
    for k, a in enumerate(NODES):
        rd, t = rad_t(a)
        ri = RING_R - RING_HW
        box_ra(B, ri - 0.3, a, CZ, (0.8, 1.5, 1.4), "gunmetal", bevel=0.06)
        box_ra(B, ri - 0.72, a, CZ, (0.12, 1.1, 1.0), "dark")
        for s in (-1, 1):
            box_ra(B, ri - 0.2, a, CZ + s * 0.78, (0.6, 1.1, 0.12), "dark")
        B.tube(polar(ri - 0.75, a, CZ), polar(7.1, a, CZ), 0.36, 0.17, "gunmetal", segs=8)
        for r, rr, mat in ((9.4, 0.38, "dark"), (8.3, 0.3, "metal"), (7.25, 0.24, "dark")):
            B.cyl(polar(r, a, CZ), rr, rr, 0.16, mat, segs=8,
                  axis_rot=Matrix.Rotation(math.radians(a), 4, "Z") @ ALONG_X)
        G.tube(polar(7.15, a, CZ), polar(6.85, a, CZ), 0.13, 0.24, "field", segs=8)
        G.tube(polar(6.85, a, CZ), polar(TIP_R, a, CZ), 0.24, 0.05, "field", segs=8)
        # coil slots either side of the node on the inner face
        for a0, a1 in ((a - 12.0, a - 3.6), (a + 3.6, a + 12.0)):
            G.beam(polar(ri - 0.07, a0, CZ), polar(ri - 0.07, a1, CZ), 0.05, 0.16, "field")
    # top labels (read from the camera side)
    # Outer face plates alternate per 30 deg segment: slate (odd) takes light ink, hull2
    # (even) dark or hazard ink.
    for a, txt, h, ink in ((225, "SG-01", 0.72, INK_LIGHT), (285, "FIELD EMITTER", 0.68,
                           INK_LIGHT), (255, "DANGER HV", 0.6, HAZ_INK),
                           (315, "DANGER HV", 0.6, HAZ_INK), (75, "FIELD EMITTER", 0.68, INK_DARK),
                           (135, "DANGER HV", 0.6, HAZ_INK)):
        rd, t = rad_t(a)
        label(txt, polar(RING_R + RING_HW + 0.01, a, CZ), rd, UP, h, ink, 0.9, depth=0.5)


def build_core():
    G.sphere(CORE, CORE_R, "field", segs=16, rings=10)


# ---------------------------------------------------------------- pylons
def build_pylons():
    for k, a in enumerate(PYLONS):
        rd, t = rad_t(a)
        ar = math.radians(a)
        foot = polar(7.9, a, DECK_Z + 0.55)
        top = polar(RING_R, a, 20.35)
        # foot plinth
        box_ra(B, 7.9, a, DECK_Z + 0.3, (2.6, 3.2, 0.6), "hull2", bevel=0.05)
        bolt_row(B, polar(7.9, a, DECK_Z + 0.62) - t * 1.4, polar(7.9, a, DECK_Z + 0.62) + t * 1.4,
                 8, 0.08)
        # two tapered legs
        legs = []
        for s in (-1, 1):
            p0, p1 = foot + t * s * 0.95, top + t * s * 0.78
            member(B, p0, p1, 0.6, 0.85, 0.42, 0.6, "slate" if s < 0 else "hull2", t)
            legs.append((p0, p1))
        # ladder braces and diagonals
        n = 6
        for i in range(1, n):
            q0 = legs[0][0].lerp(legs[0][1], i / n)
            q1 = legs[1][0].lerp(legs[1][1], i / n)
            strut(B, q0, q1, 0.22, 0.22, "dark")
            if i < n - 1:
                r0 = legs[1][0].lerp(legs[1][1], (i + 1) / n) if i % 2 else \
                    legs[0][0].lerp(legs[0][1], (i + 1) / n)
                strut(B, q0 if i % 2 else q1, r0, 0.13, 0.13, "metal")
        # gimbal actuator from the deck to the 55% brace
        mid = (legs[0][0].lerp(legs[0][1], 0.5) + legs[1][0].lerp(legs[1][1], 0.5)) / 2
        anc = polar(5.3, a, DECK_Z + 0.35)
        B.box(anc, (0.7, 0.9, 0.5), "dark", rot_z=ar, bevel=0.0)
        piv = mid - rd * 0.25
        cut = anc.lerp(piv, 0.6)
        B.tube(anc + V((0, 0, 0.2)), cut, 0.3, 0.3, "gunmetal", segs=10)
        B.tube(cut, piv, 0.15, 0.15, "metal", segs=8)
        B.box(piv, (0.4, 0.6, 0.4), "dark", rot_z=ar, bevel=0.0)
        # power feed conduit up the outside of the arm
        p0 = polar(8.95, a, DECK_Z + 0.65)
        p1 = polar(RING_R + 0.85, a, 20.0)
        for s, rad, mat in ((-0.25, 0.11, "metal"), (0.25, 0.08, "dark")):
            pipe(B, p0 + t * s, p1 + t * s, rad, mat, segs=6)
        for i in range(1, 6):
            q = p0.lerp(p1, i / 6)
            B.box(q - rd * 0.12, (0.25, 0.8, 0.2), "dark", rot_z=ar, bevel=0.0)
        # yoke: base plate, cheeks, tangent bearings, the bearing block on the ring
        box_ra(B, RING_R, a, 20.4, (1.8, 3.8, 0.5), "gunmetal", bevel=0.05)
        for s in (-1, 1):
            c = polar(RING_R, a, 21.9) + t * s * 1.55
            B.box(c, (1.7, 0.35, 3.1), "slate", rot_z=ar, bevel=0.04)
            hazard_band(B, c + V((0, 0, 1.58)) - rd * 0.8, c + V((0, 0, 1.58)) + rd * 0.8, 0.36,
                        0.05, pitch=0.35)
            ax = Matrix.Rotation(ar, 4, "Z") @ ALONG_Y
            B.cyl(polar(RING_R, a, CZ) + t * s * 1.85, 0.8, 0.8, 0.3, "gunmetal", segs=16,
                  axis_rot=ax)
            B.cyl(polar(RING_R, a, CZ) + t * s * 2.04, 0.45, 0.45, 0.12, "dark", segs=12,
                  axis_rot=ax)
            for kk in range(6):
                b = kk * math.pi / 3
                B.box(polar(RING_R, a, CZ) + t * s * 2.02 + rd * 0.62 * math.cos(b)
                      + V((0, 0, 0.62 * math.sin(b))), (0.1, 0.08, 0.1), "metal", rot_z=ar,
                      bevel=0.0)
        box_ra(B, RING_R, a, CZ, (2.3, 2.55, 2.2), "hull2", bevel=0.05)
        box_ra(B, RING_R, a, CZ + 1.12, (1.9, 2.1, 0.08), "dark")
        bolt_row(B, polar(RING_R + 1.16, a, CZ + 0.85) - t * 1.0,
                 polar(RING_R + 1.16, a, CZ + 0.85) + t * 1.0, 6, 0.07)
        label(("LENS A", "LENS B", "LENS C")[k], polar(RING_R + 1.16, a, CZ - 0.1), rd, UP, 0.55,
              INK_LIGHT)
        nav(B, polar(RING_R + 0.4, a, CZ + 1.42), "nav_white", 0.32)


# ---------------------------------------------------------------- radiators
def build_radiators():
    zb = 3.6
    for sx, nav_mat in ((1, "nav_green"), (-1, "nav_red")):
        a = 0 if sx > 0 else 180
        pipe(B, V((sx * 9.5, 0, zb)), V((sx * 18.3, 0, zb)), 0.17, "metal", segs=8)
        pipe(B, V((sx * 9.5, 0.0, zb + 0.32)), V((sx * 18.0, 0.0, zb + 0.32)), 0.06, "dark", segs=6)
        x0, x1 = 10.6, 18.1
        for s in (-1, 1):
            th = -s * math.radians(11)
            r = Matrix.Rotation(th, 4, "X")
            w = 2.35
            root = V((sx * (x0 + x1) / 2, s * 0.22, zb))
            c = root + r.to_3x3() @ V((0, s * w / 2, 0))
            B.box(c, (x1 - x0, w, 0.05), "radfine", r=r, bevel=0.0)
            for x in (x0, x1, (x0 + x1) / 2):
                B.box(V((sx * x, c.y, c.z)), (0.06, w, 0.08), "metal", r=r, bevel=0.0)
            edge = root + r.to_3x3() @ V((0, s * w, 0))
            B.box(V((sx * (x0 + x1) / 2, edge.y, edge.z)), (x1 - x0, 0.07, 0.08), "metal", r=r,
                  bevel=0.0)
            B.box(V((sx * (x0 + x1) / 2, s * 0.3, zb)), (x1 - x0, 0.16, 0.14), "radiator",
                  bevel=0.0)
        for x in (11.5, 14.4, 17.2):
            B.box(V((sx * x, 0, zb)), (0.26, 0.6, 0.42), "dark", bevel=0.0)
        # root manifold box and support struts
        B.box(V((sx * 10.0, 0, zb)), (1.2, 1.5, 1.3), "dark", bevel=0.05)
        label("COOLANT", V((sx * 10.0, -0.76, zb + 0.1)), V((0, -1, 0)), UP, 0.28, INK_LIGHT)
        label("HOT", V((sx * 10.0, 0.0, zb + 0.66)), UP, V((0, 1, 0)), 0.3, INK_LIGHT)
        for s in (-1, 1):
            strut(B, V((sx * 9.4, s * 0.6, 0.9)), V((sx * 13.8, s * 0.2, zb - 0.15)), 0.16, 0.16,
                  "dark")
        B.box(V((sx * 18.35, 0, zb)), (0.3, 0.42, 0.42), "dark", bevel=0.03)
        nav(B, V((sx * 18.35, 0, zb + 0.42)), nav_mat, 0.3)
        SCORCH.append((sx * 10.0, 0.0, zb, 0.6))


# ---------------------------------------------------------------- cabin (-Y) and service (+Y)
def build_cabin():
    y0, y1, z0, z1 = -9.1, -11.7, 2.0, 5.6
    yc, zc = (y0 + y1) / 2, (z0 + z1) / 2
    B.box(V((0, yc, zc)), (5.2, y0 - y1, z1 - z0), "hull", bevel=0.05)
    B.box(V((0, yc - 0.1, z1 + 0.08)), (5.4, y0 - y1 + 0.2, 0.16), "dark", bevel=0.0)
    B.box(V((0, y1 - 0.03, 4.55)), (4.6, 0.06, 0.82), "dark", bevel=0.0)
    for k in range(5):
        x = -1.8 + k * 0.9
        lit = ("window", "window", None, "window_dim", "window")[k]
        window(B, V((x, y1 - 0.04, 4.55)), V((0, -1, 0)), UP, 0.62, 0.48, lit)
    label("SG-01", V((0.0, y1 - 0.01, 3.25)), V((0, -1, 0)), UP, 0.95, INK_DARK)
    hazard_band(B, V((-2.5, y1 - 0.05, 2.25)), V((2.5, y1 - 0.05, 2.25)), 0.06, 0.2,
                up=UP, pitch=0.45)
    # side door + label
    B.box(V((2.62, yc, 3.2)), (0.08, 1.0, 1.9), "hull2", bevel=0.0)
    B.box(V((2.66, yc, 3.2)), (0.04, 0.8, 1.7), "dark", bevel=0.0)
    label("EVA", V((2.61, yc, 4.4)), V((1, 0, 0)), UP, 0.3, INK_DARK)
    label("#BAR", V((2.61, yc, 2.05)), V((1, 0, 0)), UP, 0.18, ID_BLUE)
    # roof: AC unit, mast, floods
    B.box(V((-1.3, yc, z1 + 0.4)), (1.4, 1.2, 0.6), "hull2", bevel=0.06)
    for k in range(4):
        B.box(V((-1.3, yc - 0.3 + k * 0.2, z1 + 0.72)), (1.2, 0.08, 0.04), "dark", bevel=0.0)
    B.cyl(V((1.6, -10.0, z1 + 1.0)), 0.1, 0.1, 2.0, "dark", segs=6)
    parts.dish(B, V((1.6, -10.0, z1 + 1.6)), 0.6, V((0.4, -0.5, 0.75)), "hull", "dark",
               depth=0.22, segs=12)
    nav(B, V((1.6, -10.0, z1 + 2.15)), "nav_white", 0.26)
    for sx in (-1, 1):
        c = V((sx * 2.2, y1 + 0.25, z1 + 0.3))
        B.box(c, (0.42, 0.3, 0.3), "dark", bevel=0.0)
        d = V((sx * 0.3, -1.0, -0.5)).normalized()
        parts.quad(B, c + d * 0.17, d, UP, 0.32, 0.18, "flood")


def build_service():
    y0, y1, z0, z1 = 8.95, 12.6, 1.4, 5.8
    yc, zc = (y0 + y1) / 2, (z0 + z1) / 2
    B.box(V((0, yc, zc)), (4.8, y1 - y0, z1 - z0), "hull2", bevel=0.08)
    B.box(V((0, y1 - 0.6, z1 + 0.05)), (4.9, 1.3, 0.1), "dark", bevel=0.0)
    for x in (-1.2, 0.0, 1.2):
        pipe(B, V((x, y1 - 0.1, LINK.z)), V((x, LINK.y - 0.1, LINK.z)), 0.24, "metal", segs=8)
        B.cyl(V((x, LINK.y - 0.06, LINK.z)), 0.34, 0.34, 0.12, "dark", segs=10, axis_rot=ALONG_Y)
        B.cyl(V((x, y1 + 0.03, LINK.z)), 0.32, 0.32, 0.06, "dark", segs=10, axis_rot=ALONG_Y)
    for sx in (-1, 1):
        B.box(V((sx * 2.42, yc, zc)), (0.1, 1.0, 1.9), "dark", bevel=0.0)
        bolt_row(B, V((sx * 2.44, y0 + 0.4, z1 - 0.3)), V((sx * 2.44, y1 - 0.4, z1 - 0.3)), 8,
                 0.07)
    label("PWR IN", V((0, y1 + 0.01, 5.0)), V((0, 1, 0)), UP, 0.4, INK_LIGHT)
    label("SVC", V((-1.5, y1 + 0.01, 2.3)), V((0, 1, 0)), UP, 0.4, INK_LIGHT)
    label("#BAR", V((1.5, y1 + 0.01, 2.3)), V((0, 1, 0)), UP, 0.2, ID_BLUE)


# ---------------------------------------------------------------- assembly
def build():
    global B, G, CP
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    B = parts.PanelPart("shield_base", MATS)
    G = parts.PanelPart("shield_emitter_glow", MATS)
    CP = parts.PanelPart("shield_capacitors", MATS)
    for f in (build_keel, build_drum, build_caps, build_busbars, build_deck, build_column,
              build_bowl, build_ring, build_core, build_pylons, build_radiators, build_cabin,
              build_service):
        t0 = sum(len(fc.verts) - 2 for fc in B.bm.faces)
        f()
        print(f"TRIS {f.__name__} {sum(len(fc.verts) - 2 for fc in B.bm.faces) - t0}")
    root = parts.make_root("shield_generator", size=10)
    objs = [p.finish(root) for p in (B, G, CP)]
    for o in objs[1:]:
        o.data.uv_layers.remove(o.data.uv_layers["panel"])
    return root, objs


def reorigin(obj, origin):
    o = V(origin)
    obj.data.transform(Matrix.Translation(-o))
    obj.location = o


def rig(root, objs):
    base, glow, caps = objs
    reorigin(glow, CORE)
    reorigin(caps, (0.0, 0.0, CAP_Z0))
    parts.add_empty("shield_emitter_point", root, CORE, size=3)
    parts.add_empty("link_point", root, LINK, rot_z=0.0, size=4)


# ---------------------------------------------------------------- checks
def world_bm(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.transform(obj.matrix_world)
    return bm


def check(objs):
    bpy.context.view_layer.update()
    base, glow, caps = objs
    bad = 0
    for o in (base, caps):
        bm = world_bm(o)
        tree = BVHTree.FromBMesh(bm)
        loc, nrm, idx, dist = tree.find_nearest(CORE)
        print(f"CHECK cradle {o.name}: nearest surface {dist:.2f} m (need >= {CRADLE_R})")
        if dist < CRADLE_R:
            bad += 1
        bm.free()
    bm = world_bm(glow)
    ds = [(v.co - CORE).length for v in bm.verts]
    mid = [d for d in ds if CORE_R * 1.34 < d < CRADLE_R]
    core = max(d for d in ds if d <= CORE_R * 1.34)
    print(f"CHECK glow: core r {core:.2f} (<= 1.2), verts inside cradle shell {len(mid)}, "
          f"nearest outer {min(d for d in ds if d > 1.2):.2f}")
    if mid or core > 1.2:
        bad += 1
    bm.free()
    bmc = world_bm(caps)
    zs = [v.co.z for v in bmc.verts]
    print(f"CHECK caps z {min(zs):.3f}..{max(zs):.3f}, origin {caps.matrix_world.translation[:]}")
    bmc.free()
    print(f"CHECK glow mats {[m.name for m in glow.data.materials]} caps mats "
          f"{[m.name for m in caps.data.materials]}")
    r_max, z_lo, z_hi = 0.0, 1e9, -1e9
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            r_max = max(r_max, w.xy.length)
            z_lo, z_hi = min(z_lo, w.z), max(z_hi, w.z)
    print(f"CHECK extent r {r_max:.2f} (<= {FOOTPRINT_MAX}), z {z_lo:.2f}..{z_hi:.2f} height "
          f"{z_hi - z_lo:.2f} (<= {HEIGHT_MAX})")
    if r_max > FOOTPRINT_MAX or z_hi - z_lo > HEIGHT_MAX or z_lo < -8:
        bad += 1
    print(f"CHECK done, {bad} problems")
    return bad


# ---------------------------------------------------------------- previews
def dim_emission():
    for m in bpy.data.materials:
        if not m.node_tree:
            continue
        b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if b:
            b.inputs["Emission Strength"].default_value *= 0.35


def import_glb(path, loc, rot_z=0.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    r = next(o for o in new if o.parent is None)
    r.location = loc
    r.rotation_mode = "XYZ"
    r.rotation_euler = (0, 0, rot_z)
    return r, new


def aim(cam, loc, tgt):
    cam.location = loc
    cam.rotation_euler = (V(tgt) - V(loc)).to_track_quat("-Z", "Y").to_euler()


def preview_orb():
    """Stand-in for Godot's ShieldFieldCore (never exported): translucent fresnel orb r 4
    and a faint equatorial pulse ring."""
    mat = bpy.data.materials.new("preview_orb")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*FIELD_COL, 1)
    em.inputs["Strength"].default_value = 2.2
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.35
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = "MULTIPLY_ADD"
    pw.inputs[1].default_value = 0.85
    pw.inputs[2].default_value = 0.12
    nt.links.new(lw.outputs["Facing"], pw.inputs[0])
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(pw.outputs[0], mix.inputs[0])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
        try:
            setattr(mat, attr, val)
        except Exception:
            pass
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=4.0, location=CORE)
    orb = bpy.context.active_object
    orb.data.materials.append(mat)
    orb.visible_shadow = False
    bpy.ops.object.shade_smooth()
    rm = bpy.data.materials.new("preview_ring")
    rm.use_nodes = True
    b = rm.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0, 0, 0, 1)
    b.inputs["Emission Color"].default_value = (*FIELD_COL, 1)
    b.inputs["Emission Strength"].default_value = 1.6
    for rr, mr in ((4.6, 0.035), (6.0, 0.025)):
        bpy.ops.mesh.primitive_torus_add(major_radius=rr, minor_radius=mr, major_segments=96,
                                         minor_segments=6, location=CORE)
        bpy.context.active_object.data.materials.append(rm)
        bpy.context.active_object.visible_shadow = False
    return orb


def previews(objs, compare=True):
    tgt = V((0, 0, 11))
    common.setup_preview(cam_loc=tgt + V((-45, -75, 80)), cam_target=tgt, ortho_scale=50,
                         res=(1600, 1200), key_dir=(-0.45, -0.3, 0.85), key_energy=3.5)
    # Shadowless fill from the far side: the bowl and lens ring shade the +X radiator and
    # the NE bank, which went pure black with the key alone.
    fill = bpy.data.lights.new("fill", "SUN")
    fill.energy = 1.1
    fill.use_shadow = False
    fo = bpy.data.objects.new("fill", fill)
    bpy.context.scene.collection.objects.link(fo)
    fo.rotation_euler = (-V((0.6, 0.45, 0.55)).normalized()).to_track_quat("-Z", "Y").to_euler()
    dim_emission()
    preview_orb()
    scene = bpy.context.scene
    cam = scene.camera
    shots = []

    def shot(tag):
        p = os.path.join(common.PREVIEW_DIR, f"{KEY}{tag}.png")
        common.render(p)
        shots.append(p)

    shot("_preview")
    cam.location = (0, 0, 200)
    cam.rotation_euler = (0, 0, 0)
    cam.data.ortho_scale = 42
    scene.render.resolution_x, scene.render.resolution_y = 1200, 1200
    shot("_top")
    # game camera: perspective, 55 deg elevation, building ~1/4 of the frame
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1200
    cam.data.type = "PERSP"
    cam.data.lens = 35
    el = math.radians(55)
    d = 105.0
    aim(cam, tgt + V((0, -d * math.cos(el), d * math.sin(el))), tgt)
    shot("_game")
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 20
    aim(cam, CORE + V((-22, -34, 26)), CORE + V((0, 0, -2.5)))
    shot("_closeup")
    if compare and os.path.exists(STATION_GLB):
        r, new = import_glb(STATION_GLB, (0.0, 0.0, 0.0))
        bpy.context.view_layer.update()
        xs = [(o.matrix_world @ V(c)).x for o in new if o.type == "MESH" for c in o.bound_box]
        r.location = (-max(xs) - 26.0, 0.0, 0.0)
        new_all = list(new)
        if os.path.exists(TURRET_GLB):
            _, tn = import_glb(TURRET_GLB, (34.0, -4.0, 0.0))
            new_all += tn
        for mm in {s.material for o in new_all if o.type == "MESH" for s in o.material_slots}:
            if mm and mm.node_tree:
                bb = next((n for n in mm.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
                if bb:
                    bb.inputs["Emission Strength"].default_value *= 0.35
        cam.data.ortho_scale = 120
        scene.render.resolution_x, scene.render.resolution_y = 2000, 1200
        aim(cam, (-60.0, -95.0, 95.0), (-12.0, 0.0, 6.0))
        shot("_compare")
    print("PREVIEWS " + " ".join(shots))


def main():
    argv = parts.script_args(sys.argv)
    res = 2048
    for a in argv:
        if a.startswith("--res="):
            res = int(a.split("=")[1])
    common.reset_scene()
    root, objs = build()
    base, glow, caps = objs
    if "--no-textures" not in argv:
        wk.texture([base], MATS, PRE, NO_PADS, scorch=SCORCH, decals=DECALS, labels=LABELS,
                   seed0=117, res=res, ao_far=2.0, edge_r=0.1)
    else:
        base.data.uv_layers.remove(base.data.uv_layers["panel"])
    rig(root, objs)
    bpy.context.view_layer.update()
    wk.stats(objs)
    bad = check(objs)
    if "--check" in argv:
        return
    wk.save_and_export(root, BLEND, OUT)
    print(f"CONTRACT {'OK' if bad == 0 else 'FAILED'}")
    if "--no-preview" not in argv:
        previews(objs, "--no-compare" not in argv)


main()
