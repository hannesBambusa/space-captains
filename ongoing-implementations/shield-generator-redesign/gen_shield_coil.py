"""Shield Generator, variant "coil spire": a field coil tower (SG-01) in the worn-industrial
language of the redesigned buildings (defense turret, mercenary outpost, mining outpost).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python gen_shield_coil.py -- [--res=2048] [--no-textures] [--no-preview] [--check]

Design: the tall counterpart of the flat "lens". A heavy armoured drum carries the plant (four
capacitor banks on outriggers on the diagonals, two vertical coolant radiator fins on +-X, a
control cabin on the camera side, a service block with umbilicals on +Y, a keel with two
tanks below). From a sloped plinth a tapering column rises through five stacked toroidal
field coils (segmented by dark frames and gunmetal clamp bands, cyan coil slots on the glow
mesh). Four spine ribs on the diagonals climb the outside of the coils from foot blocks on
the deck (the HV busbars from the banks land on them), pass the crown collar and curl
inward as the claw arms of the crown. Each arm has an elbow emitter level with the field
cradle and a talon emitter at its tip, cyan tips aimed at the cradle; a ninth emitter sits
on the spire axis under the cradle. Colour has one meaning each: cyan = the field
(emitters, coil slots, core, capacitor charge strips), warm white floods / amber windows =
work light, red / green / white = nav lights, hazard = HV and moving edges.

Layout (Blender Z up, exported +Y up; Blender +Y = Godot -Z). Origin centre, play plane z 0.
  keel       z -5.0..-0.5, tanks r 6.0 at 240 / 300
  drum       r 9.4, z -0.6..6.4 (deck top z 6.4, r 8.6)
  caps       4 banks at r 13.3 on 45 / 135 / 225 / 315, z 0.4..7.0, charge strips z 1.6..6.2
  radiators  +-X vertical fin pairs, x 10.4..16.6, z 0.9..5.9
  cabin      -Y, y -8.9..-11.5, z 1.8..5.4
  service    +Y, y 8.75..12.4, link_point (0, 13.2, 3.5)
  plinth     r 6.9 -> 5.9, z 6.4..8.1; column r 3.3 (z 9) -> 1.9 (z 23.8)
  coils      5 at z 9.8 / 13.5 / 16.9 / 20.0 / 22.8, R 6.4 / 5.6 / 4.85 / 4.2 / 3.65,
             outer r 7.2 .. 4.29, section 1.6 x 1.44 scaled 1.0 .. 0.8
  ribs       4 on 45 / 135 / 225 / 315, foot blocks r 7.75 on the deck, up the coil faces
  crown      cup r 5.3, z 23.7..25.6 (cyan ring r 2.3..2.7 inside); arms curl out to r 7.45
             at z 30.4 (elbow emitters) and back in to r 4.9 at z 34.6 (talon emitters);
             brace ring r 6.35 z 27.4; axis emitter z 25.1..25.44; emitter tips r 4.8
  cradle     centre (0, 0, 30), clear sphere r 4.5; core r 0.9
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
OUT = os.path.join(HERE, "shield_generator_coil.glb")
BLEND = os.path.join(HERE, "shield_generator_coil.blend")
STATION_GLB = os.path.join(REPO, "assets", "models", "station", "station_home.glb")
TURRET_GLB = os.path.join(REPO, "assets", "models", "buildings", "defense_turret.glb")
PRE = "shield_coil"
KEY = "coil"

V = Vector
UP = V((0, 0, 1))
ALONG_X = parts.ALONG_X
ALONG_Y = parts.ALONG_Y

# ---------------------------------------------------------------- layout constants
CZ = 30.0
CORE = V((0.0, 0.0, CZ))
CRADLE_R = 4.5
CORE_R = 0.9
DRUM_R, DECK_Z, DECK_R = 9.4, 6.4, 8.6
PLINTH_R = 6.9
CAP_R, CAP_Z0, CAP_Z1 = 13.3, 1.6, 6.2
CAP_ANGLES = (225, 315, 45, 135)        # bank 1..4, camera side first
RIBS = (225, 315, 45, 135)              # spine ribs / crown arms, one per bank
# field coils: (centre z, major radius, section scale)
COILS = [(9.8, 6.4, 1.0), (13.5, 5.6, 0.95), (16.9, 4.85, 0.9), (20.0, 4.2, 0.85),
         (22.8, 3.65, 0.8)]
C_HW, C_HH, C_CH = 0.8, 0.72, 0.3
COL_Z0, COL_R0, COL_Z1, COL_R1 = 9.0, 3.3, 23.8, 1.9
FRAMES = (0, 90, 180, 270)
LINK = V((0.0, 13.2, 3.5))
NO_PADS = [(0.0, 900.0), (0.0, 901.0)]
FOOTPRINT_MAX = 20.0
HEIGHT_MAX = 44.0
FIELD_COL = (0.32, 0.72, 1.0)
TIP_GAP = 4.8                            # emitter tips stop this far from the cradle centre

LABELS = ["SG-01", "HV", "DANGER HV", "FIELD EMITTER", "NO STEP", "KEEP CLEAR",
          "CAP BANK 1", "CAP BANK 2", "CAP BANK 3", "CAP BANK 4", "COOLANT", "PWR IN", "SVC",
          "EVA", "HOT", "#BAR", "COIL 1", "COIL 2", "COIL 3", "COIL 4", "COIL 5", "#CHEV"]
INK_DARK, INK_LIGHT = wk.INK_DARK, wk.INK_LIGHT
HAZ_INK = (0.36, 0.26, 0.04)
ID_BLUE = (0.045, 0.085, 0.17)

MATS = {}
DECALS = []
SCORCH = []
B = G = CP = None
RNG = random.Random(131)

strut = parts.strut
pipe = parts.pipe
window = parts.window


def polar(r, a_deg, z=0.0):
    return wk.polar(r, math.radians(a_deg), z)


def rad_t(a_deg):
    a = math.radians(a_deg)
    return V((math.cos(a), math.sin(a), 0.0)), V((-math.sin(a), math.cos(a), 0.0))


def col_r(z):
    f = (z - COL_Z0) / (COL_Z1 - COL_Z0)
    return COL_R0 + (COL_R1 - COL_R0) * f


def coil_outer(k):
    z, r, s = COILS[k]
    return r + C_HW * s


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


def build_materials():
    m = common.make_material
    wk.build_materials(PRE, MATS)
    MATS["slate"] = m(f"{PRE}_hull_slate", (0.16, 0.19, 0.22), roughness=0.58)
    MATS["gunmetal"] = m(f"{PRE}_gunmetal", (0.12, 0.125, 0.135), roughness=0.4, metallic=0.8)
    MATS["radfine"] = m(f"{PRE}_radiator_fin", (0.085, 0.09, 0.098), roughness=0.56,
                        metallic=0.12)
    MATS["tank"] = m(f"{PRE}_tank", (0.115, 0.125, 0.14), roughness=0.48, metallic=0.25)
    MATS["deckplate"] = m(f"{PRE}_deck_plate", (0.14, 0.142, 0.15), roughness=0.7, metallic=0.2)
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


def path_len(path):
    s = [0.0]
    for a, b in zip(path, path[1:]):
        s.append(s[-1] + (b - a).length)
    return s


def sweep_taper(p, path, w0, w1, h0, h1, side, mat_fn, cr=0.1):
    """Rounded-rect member along `path`, w along `side`, h across (u = side x tangent),
    tapering linearly by length. Section edges (n=1): 1 = +u face, 5 = -u face, 3 / 7 the
    sides, even = chamfers."""
    side = V(side).normalized()
    s = path_len(path)
    rings = []
    for i, c in enumerate(path):
        f = s[i] / s[-1]
        w, h = w0 + (w1 - w0) * f, h0 + (h1 - h0) * f
        t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        t = (t - side * t.dot(side)).normalized()
        u = side.cross(t)
        rings.append([c + side * x + u * y for x, y in rrect(w, h, cr, 1)])
    p.loft(rings, "dark", mat_fn=mat_fn)


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


def coil_band(p, k, a_deg, half_deg, scale, mat, steps=1):
    """Collar round field coil k's section at angle a (scaled section, +-half_deg)."""
    z, rr, s = COILS[k]
    sec = ring_sec(C_HW * s * scale, C_HH * s * scale, C_CH * s * scale)
    rings = []
    for i in range(steps + 1):
        a = math.radians(a_deg - half_deg + 2 * half_deg * i / steps)
        rd = V((math.cos(a), math.sin(a), 0))
        rings.append([rd * (rr + u) + V((0, 0, z + v)) for u, v in sec])
    p.loft(rings, mat)


def arc_strip(p, r_in, r_out, z0, z1, a0, a1, mat, step=3.75):
    """Curved strip (annular sector) r_in..r_out, z0..z1, a0..a1 degrees."""
    n = max(1, math.ceil((a1 - a0) / step))
    rings = []
    for i in range(n + 1):
        a = a0 + (a1 - a0) * i / n
        rings.append([polar(r_in, a, z0), polar(r_out, a, z0), polar(r_out, a, z1),
                      polar(r_in, a, z1)])
    p.loft(rings, mat)


def emitter(c, d, length, r_house=0.32):
    """Gunmetal emitter barrel from c along d (unit), collars, cyan cone tip whose point ends
    at c + d * length."""
    c, d = V(c), V(d).normalized()
    blen = length - 1.15
    B.tube(c, c + d * blen, r_house, r_house * 0.55, "gunmetal", segs=8)
    for f, rr, mat in ((0.25, r_house * 1.08, "dark"), (0.85, r_house * 0.8, "metal")):
        q = c + d * blen * f
        B.tube(q - d * 0.08, q + d * 0.08, rr, rr, mat, segs=8)
    G.tube(c + d * (blen - 0.05), c + d * (blen + 0.2), 0.13, 0.24, "field", segs=8)
    G.tube(c + d * (blen + 0.2), c + d * length, 0.24, 0.05, "field", segs=8)


# ---------------------------------------------------------------- keel
def build_keel():
    patch = [RNG.choice(("hull2", "slate", "tank")) for _ in range(4)]
    B.lathe([(0.0, -5.0), (2.0, -5.0), (3.0, -4.4), (3.4, -1.2), (4.4, -0.5)], 16,
            lambda i, j: "dark" if j < 2 else patch[i // 4], start=math.pi / 16)
    for z in (-3.7, -2.5):
        B.cyl(V((0, 0, z)), 3.3, 3.3, 0.28, "dark", segs=16)
    nav(B, V((0, 0, -5.18)), "nav_white", 0.45, hang=True)
    for k, a in enumerate((240, 300)):
        c = polar(6.0, a, -4.0)
        tank_v(B, (c.x, c.y, c.z), 1.1, 3.55, "tank", band="dark" if k == 0 else "slate")
        for z in (-3.2, -1.7):
            B.beam(polar(4.95, a, z), polar(3.3, a, z), 0.25, 0.25, "dark")
    for k in range(6):
        a = 30 + 60 * k
        strut(B, polar(3.3, a, -2.9), polar(7.0, a, -0.55), 0.24, 0.24, "dark")
    label("HV", polar(3.36, 270, -3.1), polar(1.0, 270), UP, 0.3, INK_LIGHT)
    build_underside()


def build_underside():
    """Drum floor (z -0.6, r 4.4..7.4): radial ribs, hatches, a conduit ring, sensor pods."""
    zf = -0.6
    for k in range(8):
        a = 22.5 + 45 * k
        if a in (247.5, 292.5):     # keep the tank bays clear
            continue
        B.beam(polar(4.5, a, zf - 0.12), polar(7.3, a, zf - 0.12), 0.32, 0.24, "dark")
    for k in range(4):
        a = 45 + 90 * k
        box_ra(B, 6.0, a, zf - 0.03, (1.3, 1.1, 0.06), "deckplate")
        box_ra(B, 6.0 + 0.55, a, zf - 0.07, (0.06, 0.3, 0.04), "metal")
    pts = ring_pts(6.9, 0, 360, zf - 0.2, step_m=1.3)
    for a0, a1 in zip(pts, pts[1:]):
        pipe(B, a0, a1, 0.1, "metal", segs=6)
    for q in pts[::3]:
        B.box(q + V((0, 0, 0.08)), (0.22, 0.22, 0.16), "dark", bevel=0.0)
    for a in (110, 160):
        c = polar(5.6, a, zf - 0.55)
        B.cyl(c + V((0, 0, 0.3)), 0.12, 0.12, 0.5, "dark", segs=6)
        B.cyl(c, 0.45, 0.32, 0.4, "gunmetal", segs=10)
        nav(B, c - V((0, 0, 0.3)), "nav_white", 0.18, hang=True)
    parts.dish(B, polar(6.2, 20, zf - 1.0), 0.7, V((0.3, 0.1, -0.95)), "hull", "dark",
               depth=0.22, segs=12)
    B.cyl(polar(6.2, 20, zf - 0.5), 0.08, 0.08, 0.7, "dark", segs=6)


# ---------------------------------------------------------------- drum
def build_drum():
    prof = [(0.0, -0.6), (7.4, -0.6), (9.0, 0.6), (DRUM_R, 1.2), (DRUM_R, 5.5), (9.0, 6.1),
            (DECK_R, DECK_Z), (0.0, DECK_Z)]
    em = {0: "dark", 1: "hull2", 2: "dark", 3: "body", 4: "hull2", 5: "dark", 6: "pad"}
    patch = [RNG.choice(("hull", "hull3", "slate", "hull", "hull2")) for _ in range(8)]
    for p_i in range(8):
        ca = (4 * p_i + 2) * 11.25
        if 180 <= ca <= 315 or ca == 22.5:
            patch[p_i] = "hull"

    def mf(i, j):
        k = em[j]
        return patch[i // 4] if k == "body" else k
    B.lathe(prof, 32, mf, start=0.0)
    for z in (1.95, 4.85):
        B.cyl(V((0, 0, z)), DRUM_R + 0.05, DRUM_R + 0.05, 0.22, "dark", segs=32)
    # ribs, skipping the cabin, service block and radiator roots
    for k in range(32):
        a = k * 11.25 + 5.625
        if 250 < a < 290 or 70 < a < 110 or a < 12 or a > 348 or 168 < a < 192:
            continue
        box_ra(B, DRUM_R + 0.04, a, 3.4, (0.08, 0.12, 2.7), "metal")
    # windows: one regular strip either side of the cabin
    rf = DRUM_R * math.cos(math.pi / 32) + 0.01
    for k, a_d in enumerate((236, 243, 250, 290, 297, 304)):
        a = math.radians(a_d + 2.8)
        n = V((math.cos(a), math.sin(a), 0))
        lit = {0: "window", 2: "window_cool", 4: "window", 5: "window_dim"}.get(k)
        window(B, V((0, 0, 3.95)) + n * rf, n, UP, 0.42, 0.5, lit)
    label("SG-01", polar(DRUM_R + 0.02, 202, 3.4), polar(1.0, 202), UP, 1.15, INK_DARK,
          depth=1.2)
    label("SG-01", polar(DRUM_R + 0.02, 22, 3.4), polar(1.0, 22), UP, 1.15, INK_DARK,
          depth=1.2)
    label("#BAR", polar(DRUM_R + 0.02, 318, 1.5), polar(1.0, 318), UP, 0.22, ID_BLUE)
    # pipe run round the upper wall, bracketed
    for a0, a1 in ((195, 245), (295, 345), (15, 65), (115, 165)):
        pts = ring_pts(DRUM_R + 0.14, a0, a1, 5.25, step_m=1.4)
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
        box_ra(B, 9.3, aa, 5.85, (0.3, 0.4, 0.4), "dark")
        parts.rcs_quad(B, polar(9.6, aa, 5.85), polar(1.0, aa), "hull2", "dark", s=0.32, fwd=UP)
        c = polar(9.6, aa, 5.85)
        SCORCH.append((c.x, c.y, c.z, 0.9))
    # open ring truss under the drum skirt
    for k in range(8):
        a0, a1 = 22.5 + 45 * k, 22.5 + 45 * (k + 1)
        strut(B, polar(8.2, a0, 0.0), polar(8.2, a1, 0.0), 0.2, 0.2, "dark")


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
        # side cooling fin packs (lower half)
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
        # side faces: labels
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
        for z in (1.6, 5.0):
            for s in (-1, 1):
                strut(B, polar(r0, a, z) + t * s * 1.6, polar(DRUM_R - 0.1, a, z) + t * s * 1.2,
                      0.26, 0.26, "dark")
        strut(B, polar(r0, a, 1.6), polar(DRUM_R - 0.1, a, 5.0) + t * 1.2, 0.16, 0.16, "metal")
        B.beam(polar(r0 + 0.05, a, 4.0), polar(DRUM_R - 0.05, a, 4.0), 0.9, 0.12, "dark")
        for k in range(3):
            pipe(B, polar(r0 + 0.05, a, 4.12) + t * (-0.25 + k * 0.25),
                 polar(DRUM_R - 0.05, a, 4.12) + t * (-0.25 + k * 0.25), 0.07,
                 ("metal", "dark", "metal")[k], segs=5)


# ---------------------------------------------------------------- HV busbars to the rib feet
def build_busbars():
    for a in CAP_ANGLES:
        rd, t = rad_t(a)
        for s in (-1, 1):
            p0 = polar(CAP_R - 0.4, a, 9.38) + t * s * 1.1
            pts = [p0, p0 + V((0, 0, 0.45)), polar(10.6, a, 9.83) + t * s * 1.0,
                   polar(8.7, a, 8.55) + t * s * 0.9, polar(8.25, a, 7.6) + t * s * 0.9]
            path = smooth_path(pts, 0.6, steps=3)
            sweep(B, path, 0.3, 0.2, "gunmetal", t, cr=0.05, n=1)
            for c, tg in path_points(path, 1.5, skip0=0.6, skip1=0.6):
                B.beam(c - tg * 0.07, c + tg * 0.07, 0.4, 0.3, "dark",
                       up=t.cross(tg).normalized())
            # terminal lug on the foot block
            B.box(polar(8.25, a, 7.62) + t * s * 0.9, (0.55, 0.5, 0.25), "dark", rot_z=math.radians(a),
                  bevel=0.0)


# ---------------------------------------------------------------- deck + plinth
def build_deck():
    zd = DECK_Z
    # sloped armour plinth the spire stands on
    B.lathe([(PLINTH_R, zd + 0.01), (PLINTH_R, 7.0), (6.65, 7.25), (5.9, 8.1), (5.6, 8.25),
             (3.6, 8.3), (0.0, 8.3)], 32,
            lambda i, j: {0: "dark", 1: "gunmetal", 2: ("slate" if (i // 4) % 2 else "hull2"),
                          3: "gunmetal"}.get(j, "dark"), start=math.pi / 32)
    for k in range(16):
        a = k * 22.5 + 11.25
        if any(abs(((a - r + 180) % 360) - 180) < 15 for r in RIBS):
            continue
        box_ra(B, 6.35, a, 7.65, (1.1, 0.14, 0.5), "dark")
    # inset plates and hatches on the deck ring
    for a, s in ((20, (1.0, 1.1)), (160, (0.9, 1.2)), (110, (0.9, 0.8)), (200, (0.8, 1.0)),
                 (340, (0.8, 1.0))):
        box_ra(B, 7.75, a, zd + 0.02, (s[0], s[1], 0.05), "deckplate")
        box_ra(B, 7.75 + s[0] / 2 - 0.12, a, zd + 0.06, (0.05, 0.24, 0.04), "metal")
    for a in (0, 180):
        c = polar(7.8, a, zd)
        box_ra(B, 7.8, a, zd + 0.04, (1.1, 1.1, 0.08), "deckplate")
        for dx, dy, w, l in ((0.58, 0, 0.1, 1.26), (-0.58, 0, 0.1, 1.26), (0, 0.58, 1.16, 0.1),
                             (0, -0.58, 1.16, 0.1)):
            r3 = Matrix.Rotation(math.radians(a), 4, "Z").to_3x3()
            B.box(c + r3 @ V((dx, dy, 0.06)), (w, l, 0.1), "dark", rot_z=math.radians(a),
                  bevel=0.0)
        label("EVA", polar(7.8, a, zd + 0.1), UP, up_for(rad_t(a)[1]), 0.26, INK_LIGHT)
    # hazard ring round the plinth foot, broken at the rib feet
    pts = ring_pts(PLINTH_R + 0.18, 0, 360, zd + 0.03, step_m=0.6)
    for k, (p0, p1) in enumerate(zip(pts, pts[1:])):
        ang = math.degrees(math.atan2(p0.y, p0.x)) % 360
        if any(abs(((ang - r + 180) % 360) - 180) < 12 for r in RIBS):
            continue
        B.beam(p0, p1, 0.3, 0.05, "hazard" if k % 2 == 0 else "dark")
    label("KEEP CLEAR", polar(7.9, 270, zd + 0.01), UP, V((0, 1, 0)), 0.36, INK_LIGHT)
    label("NO STEP", polar(7.95, 245, zd + 0.01), UP, up_for(rad_t(245)[1]), 0.24, INK_LIGHT)
    # floods aimed up the spire
    for a in (252, 288, 72, 108):
        rd, t = rad_t(a)
        B.box(polar(8.1, a, zd + 0.08), (0.3, 0.3, 0.16), "dark", bevel=0.0)
        box_ra(B, 8.1, a, zd + 0.34, (0.42, 0.4, 0.34), "dark", bevel=0.03)
        d = (-rd + V((0, 0, 1.4))).normalized()
        parts.quad(B, polar(8.1, a, zd + 0.34) - rd * 0.22, d, UP, 0.3, 0.2, "flood")
    # handrail round the deck edge, gaps at the rib feet
    for k, a in enumerate(sorted(RIBS)):
        nxt = sorted(RIBS)[(k + 1) % 4]
        a0, a1 = a + 13, nxt - 13
        if a1 < a0:
            a1 += 360
        handrail(B, ring_pts(8.42, a0, a1, zd, step_m=1.5))
    # cleats on the rim
    for k in range(24):
        a = k * 15 + 7.5
        if any(abs(((a - r + 180) % 360) - 180) < 12 for r in RIBS):
            continue
        box_ra(B, 8.85, a, 6.3, (0.18, 0.34, 0.12), "dark")


# ---------------------------------------------------------------- column + coils
def build_column():
    def cm(i, j):
        if j == 0:
            return "dark"
        return "slate" if (i // 3) % 2 else "hull2"
    B.lathe([(3.6, 8.29), (COL_R0 + 0.15, 8.6), (COL_R0, COL_Z0), (COL_R1, COL_Z1)], 24, cm,
            start=math.pi / 24)
    # dark bands between the coils
    for k in range(len(COILS) - 1):
        z = (COILS[k][0] + COILS[k + 1][0]) / 2
        B.cyl(V((0, 0, z)), col_r(z) + 0.08, col_r(z) + 0.08, 0.2, "dark", segs=24)
    # field feeders up the column (between the coil frames)
    for a in FRAMES:
        rd, t = rad_t(a)
        p0, p1 = polar(col_r(9.2) + 0.12, a, 9.2), polar(col_r(23.4) + 0.12, a, 23.4)
        B.beam(p0, p1, 0.26, 0.16, "gunmetal", up=rd)
        for k in range(len(COILS) - 1):
            z = (COILS[k][0] + COILS[k + 1][0]) / 2 + 0.5
            box_ra(B, col_r(z) + 0.15, a, z, (0.24, 0.42, 0.16), "dark")
    # hatch on the camera side
    z = 11.6
    box_ra(B, col_r(z) + 0.02, 255, z, (0.08, 1.0, 1.3), "hull", bevel=0.0)
    box_ra(B, col_r(z) + 0.05, 255, z, (0.06, 0.8, 1.1), "dark", bevel=0.0)


def build_coils():
    for k, (z, rr, s) in enumerate(COILS):
        sec = ring_sec(C_HW * s, C_HH * s, C_CH * s)
        prof = [(rr + u, z + v) for u, v in sec] + [(rr + sec[0][0], z + sec[0][1])]

        def mf(i, j):
            blk = i // 5                       # 45 deg blocks between frames / ribs
            if j == 0:
                return "hull" if blk % 2 else "hull2"
            if j in (1, 7):
                return "gunmetal"
            if j == 2:
                return "slate" if blk % 2 else "hull2"
            return "dark"
        B.lathe(prof, 40, mf, start=0.0)
        ro = rr + C_HW * s
        hf = (C_HH - C_CH) * s                # half height of the flat outer face
        # frames at the cardinals, clamp bands where the ribs pass
        for a in FRAMES:
            coil_band(B, k, a, math.degrees(0.16 / ro), 1.12, "dark")
            bolt_row(B, polar(ro + 0.1, a, z - hf), polar(ro + 0.1, a, z + hf), 3, 0.07, "metal")
        for a in RIBS:
            half = math.degrees((0.65 + 0.4) / ro)
            coil_band(B, k, a, half, 1.07, "gunmetal")
        # spokes to the column
        for j in range(8):
            a = 22.5 + 45 * j
            B.beam(polar(col_r(z) - 0.1, a, z), polar(rr - C_HW * s + 0.1, a, z), 0.3, 0.3,
                   "dark")
        # cyan coil slots in a dark channel, one per segment (one front segment carries
        # the coil number instead)
        mg = math.degrees(0.95 / ro) + 2.0
        for j in range(8):
            a0, a1 = 45 * j + mg, 45 * (j + 1) - mg
            if j == 5:
                ink = INK_DARK           # 225..270 block is hull (light)
                label(f"COIL {k + 1}", polar(ro + 0.01, 247.5, z), polar(1.0, 247.5), UP,
                      min(0.5, hf * 1.1), ink, 0.9, depth=1.0)
                continue
            arc_strip(B, ro - 0.05, ro + 0.035, z - 0.25 * s, z + 0.25 * s, a0, a1, "dark",
                      step=7.5)
            arc_strip(G, ro - 0.03, ro + 0.07, z - 0.12 * s, z + 0.12 * s, a0 + 0.6, a1 - 0.6,
                      "field", step=7.5)


# ---------------------------------------------------------------- spine ribs + crown
def rib_rz():
    pts = [(7.95, 7.4)]
    for k, (z, rr, s) in enumerate(COILS):
        pts.append((coil_outer(k) + 0.4 - 0.02 * k, z))
    pts += [(4.75, 24.4), (5.8, 26.3), (7.0, 28.4), (7.45, 30.4), (7.05, 32.5), (6.1, 34.0),
            (4.9, 34.6)]
    return pts


def build_ribs():
    rz = rib_rz()
    n_spire = len(COILS) + 1
    for n, a in enumerate(RIBS):
        rd, t = rad_t(a)
        # foot block on the deck, the busbars land on its top
        box_ra(B, 7.75, a, 6.95, (1.4, 2.4, 1.1), "hull", bevel=0.05)
        box_ra(B, 7.75, a, 6.45, (1.6, 2.6, 0.12), "dark")
        label("HV", polar(8.46, a, 6.95), rd, UP, 0.62, INK_DARK, 0.9)
        path = smooth_path([polar(r, a, z) for r, z in rz], 1.0, steps=3)

        def mf(i, j):
            if j == 1:
                return "hull2"
            if j in (3, 7):
                return "slate"
            if j == 5:
                return "dark"
            return "gunmetal"
        sweep_taper(B, path, 1.3, 0.8, 0.82, 0.6, t, mf)
        s = path_len(path)
        # collars along the rib
        for c, tg in path_points(path, 3.0, skip0=1.4, skip1=0.9):
            f = next((s[i] / s[-1] for i, q in enumerate(path) if (q - c).length < 1.4), 0.5)
            w, h = 1.3 + (0.8 - 1.3) * f, 0.82 + (0.6 - 0.82) * f
            u = t.cross(tg).normalized()
            B.beam(c - tg * 0.12, c + tg * 0.12, w + 0.14, h + 0.14, "dark", up=u)
        # crown arm: hazard band below the elbow, elbow emitter, talon emitter, red light
        el = polar(7.45, a, 30.4)
        box_ra(B, 7.45 - 0.4, a, 30.4, (0.5, 1.15, 1.3), "gunmetal", bevel=0.06)
        box_ra(B, 7.45 - 0.66, a, 30.4, (0.1, 0.8, 0.9), "dark")
        c0 = polar(7.45 - 0.7, a, 30.4)
        d = (CORE - c0).normalized()
        emitter(c0, d, (CORE - c0).length - TIP_GAP, r_house=0.34)
        tip = polar(4.9, a, 34.6)
        tg_end = (path[-1] - path[-3]).normalized()
        B.beam(tip - tg_end * 0.55, tip + tg_end * 0.35, 0.95, 0.85, "gunmetal",
               up=t.cross(tg_end).normalized())
        d = (CORE - tip).normalized()
        c1 = tip + d * 0.35
        emitter(c1, d, (CORE - c1).length - TIP_GAP, r_house=0.3)
        nav(B, tip + V((0, 0, 0.58)), "nav_red", 0.32)
        # rib to coil clamps: bolts on the rib face
        for k in range(len(COILS)):
            z = COILS[k][0]
            q = polar(rz[k + 1][0] + 0.42 - 0.01 * k, a, z)
            bolt_row(B, q - t * 0.4, q + t * 0.4, 2, 0.08, "metal")
    # crown cup on the column top: rim wall, inner slope with a cyan field ring
    B.lathe([(COL_R1 - 0.05, COL_Z1 - 0.1), (3.2, 23.9), (4.9, 24.25), (5.3, 24.65),
             (5.3, 25.35), (5.05, 25.6), (4.5, 25.6), (3.3, 25.3), (1.5, 25.1), (0.0, 25.1)], 32,
            lambda i, j: {0: "dark", 1: "gunmetal", 2: "dark",
                          3: ("slate" if (i // 4) % 2 else "hull2"), 4: "gunmetal", 5: "hull2",
                          6: ("deckplate" if i % 2 else "dark")}.get(j, "dark"),
            start=0.0)
    for k in range(16):
        a = 22.5 * k + 11.25
        if any(abs(((a - r + 180) % 360) - 180) < 12 for r in RIBS):
            continue
        box_ra(B, 5.33, a, 25.0, (0.12, 0.3, 0.6), "dark")
    for k in range(4):
        a0 = 90 * k + 8
        arc_strip(B, 2.15, 2.85, 25.12, 25.22, a0 - 2, a0 + 76, "dark", step=7.5)
        arc_strip(G, 2.3, 2.7, 25.15, 25.27, a0, a0 + 74, "field", step=7.5)
    # axis emitter under the cradle
    B.cyl(V((0, 0, 25.12)), 0.7, 0.6, 0.06, "dark", segs=12)
    G.tube(V((0, 0, 25.08)), V((0, 0, CZ - 4.56)), 0.34, 0.06, "field", segs=10)
    # brace ring between the arms
    zb = 27.4
    rb = 6.35
    B.torus(V((0, 0, zb)), rb, 0.17, "gunmetal", segs=48, minor_segs=6)
    for a in RIBS:
        box_ra(B, rb, a + 45, zb, (0.5, 0.6, 0.5), "dark")
        B.cyl(polar(rb, a + 45, zb + 0.4), 0.16, 0.16, 0.4, "metal", segs=6)


def build_core():
    G.sphere(CORE, CORE_R, "field", segs=16, rings=10)


# ---------------------------------------------------------------- radiators (vertical fins)
def build_radiators():
    z0, z1 = 0.9, 5.9
    zc = (z0 + z1) / 2
    x0, x1 = 10.4, 16.6
    for sx, nav_mat in ((1, "nav_green"), (-1, "nav_red")):
        # root manifold and a spine pipe between the fins
        B.box(V((sx * 10.0, 0, zc)), (1.3, 1.4, 4.0), "dark", bevel=0.05)
        label("COOLANT", V((sx * 10.0, -0.71, zc + 0.6)), V((0, -1, 0)), UP, 0.28, INK_LIGHT)
        label("HOT", V((sx * 10.0, 0.0, zc + 2.01)), UP, V((0, 1, 0)), 0.3, INK_LIGHT)
        for z in (z0 + 0.5, z1 - 0.5):
            pipe(B, V((sx * 10.5, 0, z)), V((sx * x1, 0, z)), 0.14, "metal", segs=8)
        for s in (-1, 1):
            th = s * math.radians(9)
            r = Matrix.Rotation(th, 4, "X")
            c = V((sx * (x0 + x1) / 2, s * 0.62, zc))
            B.box(c, (x1 - x0, 0.05, z1 - z0), "radfine", r=r, bevel=0.0)
            for x in (x0, x1, (x0 + x1) / 2):
                B.box(V((sx * x, c.y, c.z)), (0.08, 0.08, z1 - z0), "metal", r=r, bevel=0.0)
            for z in (z0, z1):
                q = r.to_3x3() @ V((0, 0, z - zc))
                B.box(c + q, (x1 - x0, 0.09, 0.08), "metal", r=r, bevel=0.0)
            # fin roots on the manifold pipes
            for z in (z0 + 0.5, z1 - 0.5):
                q = r.to_3x3() @ V((0, 0, z - zc))
                B.beam(V((sx * x0, 0, z)), V((sx * x0, (c + q).y, (c + q).z)), 0.2, 0.2, "dark")
        for x in (12.0, 14.5):
            for z in (z0 + 0.5, z1 - 0.5):
                B.box(V((sx * x, 0, z)), (0.26, 0.5, 0.42), "dark", bevel=0.0)
        # support struts from the drum
        for z in (1.4, 5.0):
            strut(B, V((sx * 9.2, 0.0, z)), V((sx * 12.0, 0.0, zc)), 0.16, 0.16, "dark")
        B.box(V((sx * (x1 + 0.2), 0, z1 + 0.05)), (0.4, 0.42, 0.42), "dark", bevel=0.03)
        nav(B, V((sx * (x1 + 0.2), 0, z1 + 0.5)), nav_mat, 0.3)
        SCORCH.append((sx * 10.0, 0.0, zc, 0.6))


# ---------------------------------------------------------------- cabin (-Y) and service (+Y)
def build_cabin():
    y0, y1, z0, z1 = -8.9, -11.5, 1.8, 5.4
    yc, zc = (y0 + y1) / 2, (z0 + z1) / 2
    B.box(V((0, yc, zc)), (5.2, y0 - y1, z1 - z0), "hull", bevel=0.05)
    B.box(V((0, yc - 0.1, z1 + 0.08)), (5.4, y0 - y1 + 0.2, 0.16), "dark", bevel=0.0)
    B.box(V((0, y1 - 0.03, 4.35)), (4.6, 0.06, 0.82), "dark", bevel=0.0)
    for k in range(5):
        x = -1.8 + k * 0.9
        lit = ("window", "window", None, "window_dim", "window")[k]
        window(B, V((x, y1 - 0.04, 4.35)), V((0, -1, 0)), UP, 0.62, 0.48, lit)
    label("SG-01", V((0.0, y1 - 0.01, 3.05)), V((0, -1, 0)), UP, 0.95, INK_DARK)
    hazard_band(B, V((-2.5, y1 - 0.05, 2.05)), V((2.5, y1 - 0.05, 2.05)), 0.06, 0.2,
                up=UP, pitch=0.45)
    B.box(V((2.62, yc, 3.0)), (0.08, 1.0, 1.9), "hull2", bevel=0.0)
    B.box(V((2.66, yc, 3.0)), (0.04, 0.8, 1.7), "dark", bevel=0.0)
    label("EVA", V((2.61, yc, 4.2)), V((1, 0, 0)), UP, 0.3, INK_DARK)
    label("#BAR", V((2.61, yc, 1.95)), V((1, 0, 0)), UP, 0.18, ID_BLUE)
    B.box(V((-1.3, yc, z1 + 0.4)), (1.4, 1.2, 0.6), "hull2", bevel=0.06)
    for k in range(4):
        B.box(V((-1.3, yc - 0.3 + k * 0.2, z1 + 0.72)), (1.2, 0.08, 0.04), "dark", bevel=0.0)
    B.cyl(V((1.6, -9.8, z1 + 1.0)), 0.1, 0.1, 2.0, "dark", segs=6)
    parts.dish(B, V((1.6, -9.8, z1 + 1.6)), 0.6, V((0.4, -0.5, 0.75)), "hull", "dark",
               depth=0.22, segs=12)
    nav(B, V((1.6, -9.8, z1 + 2.15)), "nav_white", 0.26)
    for sx in (-1, 1):
        c = V((sx * 2.2, y1 + 0.25, z1 + 0.3))
        B.box(c, (0.42, 0.3, 0.3), "dark", bevel=0.0)
        d = V((sx * 0.3, -1.0, -0.5)).normalized()
        parts.quad(B, c + d * 0.17, d, UP, 0.32, 0.18, "flood")


def build_service():
    y0, y1, z0, z1 = 8.75, 12.4, 1.4, 5.6
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
    label("PWR IN", V((0, y1 + 0.01, 4.8)), V((0, 1, 0)), UP, 0.4, INK_LIGHT)
    label("SVC", V((-1.5, y1 + 0.01, 2.2)), V((0, 1, 0)), UP, 0.4, INK_LIGHT)
    label("#BAR", V((1.5, y1 + 0.01, 2.2)), V((0, 1, 0)), UP, 0.2, ID_BLUE)


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
              build_coils, build_ribs, build_core, build_radiators, build_cabin, build_service):
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
    root = base.parent
    names = sorted(o.name for o in root.children)
    want = sorted(["shield_base", "shield_emitter_glow", "shield_capacitors",
                   "shield_emitter_point", "link_point"])
    print(f"CHECK hierarchy {root.name}: {names}")
    if root.name != "shield_generator" or names != want:
        bad += 1
    ep = bpy.data.objects["shield_emitter_point"]
    lp = bpy.data.objects["link_point"]
    print(f"CHECK emitter_point {tuple(round(x, 3) for x in ep.matrix_world.translation)}, "
          f"glow origin {tuple(round(x, 3) for x in glow.matrix_world.translation)}, link_point "
          f"{tuple(round(x, 3) for x in lp.matrix_world.translation)} rot "
          f"{tuple(round(x, 4) for x in lp.rotation_euler)}")
    if (ep.matrix_world.translation - CORE).length > 1e-4 or \
            (glow.matrix_world.translation - CORE).length > 1e-4 or \
            lp.matrix_world.translation.y <= 0 or any(abs(x) > 1e-6 for x in lp.rotation_euler):
        bad += 1
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
    org = caps.matrix_world.translation
    print(f"CHECK caps z {min(zs):.3f}..{max(zs):.3f}, origin {tuple(org)}")
    if abs(min(zs) - org.z) > 1e-3 or abs(org.x) > 1e-6 or abs(org.y) > 1e-6:
        bad += 1
    bmc.free()
    gm = [m.name for m in glow.data.materials]
    cm = [m.name for m in caps.data.materials]
    print(f"CHECK glow mats {gm} caps mats {cm}")
    if len(gm) != 1 or len(cm) != 1:
        bad += 1
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
    tris = sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)
    print(f"CHECK tris {tris} (<= 40000)")
    if tris > 40000:
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
    tgt = V((0, 0, 13))
    common.setup_preview(cam_loc=tgt + V((-45, -75, 80)), cam_target=tgt, ortho_scale=62,
                         res=(1600, 1200), key_dir=(-0.45, -0.3, 0.85), key_energy=3.5)
    # Shadowless fill from the far side so the shaded flank of the spire is not pure black.
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
    cam.data.ortho_scale = 40
    scene.render.resolution_x, scene.render.resolution_y = 1200, 1200
    shot("_top")
    # game camera: perspective, 55 deg elevation, building ~1/4 of the frame
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1200
    cam.data.type = "PERSP"
    cam.data.lens = 35
    el = math.radians(55)
    d = 105.0
    gt = V((0, 0, 12))
    aim(cam, gt + V((0, -d * math.cos(el), d * math.sin(el))), gt)
    shot("_game")
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 24
    aim(cam, CORE + V((-22, -34, 22)), CORE + V((0, 0, -3.5)))
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
        aim(cam, (-60.0, -95.0, 100.0), (-12.0, 0.0, 10.0))
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
                   seed0=131, res=res, ao_far=2.0, edge_r=0.1)
    else:
        base.data.uv_layers.remove(base.data.uv_layers["panel"])
    rig(root, objs)
    bpy.context.view_layer.update()
    wk.stats(objs)
    bad = check(objs)
    if "--check" in argv:
        print(f"CONTRACT {'OK' if bad == 0 else 'FAILED'}")
        return
    wk.save_and_export(root, BLEND, OUT)
    print(f"CONTRACT {'OK' if bad == 0 else 'FAILED'}")
    if "--no-preview" not in argv:
        previews(objs, "--no-compare" not in argv)


main()
