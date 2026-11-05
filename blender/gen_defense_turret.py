"""Generate the station defense turret (PDM-2 "Warden" point-defence mount) .glb and previews.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_defense_turret.py
  Options after `--`: --no-preview, --no-textures (flat colours, fast), --res=2048 (smaller
  atlas, default 4096), --check (clearance sweep only, no export).
Textures: one worn-industrial atlas in the home station's language (worn_kit /
station_textures.WORN_KINDS with gen_station-style hull / radiator / slate overrides, a
turret-scale panel grid and a carbon-fouled "gunmetal" kind), saved as
blender/textures/defense_turret_*.jpg plus the stencil sheet defense_turret_decals.png.

Design: a free-standing point-defence cannon platform built by the station's people, in the
spirit of an Expanse PDC mount, with the mass high: a thin deck slab, a dark machine neck
and a compact gun house, the base kept low and dark. From the bottom up: a keel (magazine
can, two short reaction-mass tanks, all matte dark) under a recessed core; a thin deck slab
(r 7.6, a 0.55 m armoured edge over an underside sloping back to the core) with three rim
notches cut back to r 6.6 (the radiator wing roots at +-X, the power conduit at +Y); thin
chamfered armour cassettes and an open ring truss under the slab; one window strip on the
camera side; four RCS quads; two near-horizontal radiator wings (one broad panel per side
on a coolant manifold out of the notch, a thin light frame, tilted 10 deg to the camera).
The deck carries two dark reaction-mass tanks with shallow dished heads and three straps
(45 / 135 deg), ammo hatches with cantilever monorail hoists out of the barbette (knee
brace, trolley, a hanging ammo canister), radial cable trays, the power conduit, vents, a
few inset plates, floods, a lidar post and a toe-rail. The barbette is an armoured foot, a
tall dark recessed band with strakes (and the EVA door module), then a short collar under
the yaw turntable. The turret house holds a ready magazine at the back, flat link chutes
(sparse clamps) along the roof edges to feed ports over the trunnions, coolant fin stacks,
a phased-array slab, a lidar can, two small dim floods under hood lips on the rear chamfer
and the status lamp. A dark pleated bellows mantlet (an arc round the pitch axis) closes
the slot between the house front and the pitch pod: receivers (PDC 1 / 2 on their top
plates), boresight camera, two six-barrel rotary guns in full-length dark cooling jackets
with shroud rings and muzzle brakes. The +Y side (the side BuildingManager turns to the
station) is a plain service / power block with umbilical stubs: no corridor port. Colour
has one meaning each: accent (dark maroon, small tags only) = ammunition, hazard = moving
edges.

Layout (Blender Z up, exported +Y up; Blender +Y = Godot -Z = the barrels' rest heading).
Yaw axis = Z through the origin, which sits on the play plane. Angles from +X, CCW.
  keel       magazine can z 4.3..8.2, tanks at r 4.4 (225 / 315), z 5.3..7.9
  core       r 5.2, z 8.0..11.05; cassettes r 6.78..6.98, z 9.6..11.4; ring truss r 6.3
  slab       underside r 5.2 z 11.0 -> r 7.3 z 11.55; edge r 7.6, z 11.75..12.3; deck top
             12.6 (r 4.4) .. 12.5 (r 7.2); notches at 0 / 90 / 180 deg, +-7 deg, to r 6.6
  wings      panels x +-8.0..11.15, y +-1.5, z ~11.5 (10 deg tilt), manifold z 11.36
  deck tanks r 6.15 at 45 / 135, top z ~14.4; hoist rails r 4.5..6.95 at z 14.3
  barbette   r 4.4: foot z 12.6..12.9, recess r 3.95 z 13.0..14.3, collar 14.4..15.6 (= yaw deck)
  service    +Y block y 5.3..8.55, z 8.4..11.8, stubs to y 9.36, link_point (0, 9.4, 10.0)
  turret     turntable r 4.6 z 15.62..16.0, house x +-2.95 y -3.4..0 roof z 19.0,
             magazine 4.7 x 0.9 (y -4.3..-3.4),
             cheeks x +-1.95..2.8, y 0..3.6, chutes 0.5 x 0.18 in the plane x +-2.15,
             mantlet r 1.42..1.95 round the pitch axis, 152..222 deg, x +-1.9
  guns       pitch axis (y 2.0, z 18.0), guns at x +-0.8 (receivers r 0.84 on an axis 0.17
             high, barrel cluster r 0.37, jacket r 0.6 y 5.3..9.8, shroud rings r 0.69,
             brake r 0.58), muzzles at y 10.95
Hierarchy: defense_turret (empty root)
  -> turret_base (mesh, origin 0) -> link_point (empty)
  -> turret_yaw (mesh, origin on the yaw axis at the deck, z = 15.6)
       -> turret_pitch (mesh, origin on the pitch axis) -> muzzle_l, muzzle_r (empties)
       -> turret_status_light (emissive mesh, own material "turret_status_light")
All empties are unrotated: Godot -Z = Blender +Y (out of the barrels / toward the station).
Pitch range -25..+70 everywhere is clear (nothing tall on the +Y side), checked by --check
over the full sweep (yaw 5 deg, pitch 2.5 deg).
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
import station_textures as st  # noqa: E402
import worn_kit as wk  # noqa: E402

V = Vector
UP = V((0, 0, 1))
ALONG_X = parts.ALONG_X
ALONG_Y = parts.ALONG_Y
PRE = "defense_turret"
OUT = os.path.join(common.ROOT, "assets", "models", "buildings", f"{PRE}.glb")
BLEND = os.path.join(common.ROOT, "blender", f"{PRE}.blend")
STATION_GLB = os.path.join(common.ROOT, "assets", "models", "station", "station_home.glb")

# ---------------------------------------------------------------- layout constants
YAW_Z = 15.6
PITCH_Y, PITCH_Z = 2.0, 18.0
GUN_X = 0.8
MUZZLE_Y = 10.95
DRUM_R, DRUM_Z0, DRUM_Z1 = 7.6, 7.4, 12.6
BARB_R, BARB_TOP = 4.4, 15.6
TT_R = 4.6
LINK = V((0.0, 9.4, 10.0))
STATUS_O = V((1.35, -2.2, 19.285))
NO_PADS = [(0.0, 900.0), (0.0, 901.0)]
FOOTPRINT_MAX = 11.5

LABELS = ["PDC 1", "PDC 2", "DT-04", "AMMO", "PWR IN", "SVC", "EVA", "MAG",
          "NO STEP", "KEEP CLEAR", "FIRE CTRL", "HOT", "R-02", "#BAR", "H2O"]
INK_DARK, INK_LIGHT = wk.INK_DARK, wk.INK_LIGHT
HAZ_INK = (0.36, 0.26, 0.04)
ID_BLUE = (0.045, 0.085, 0.17)

MATS = {}
DECALS = []
SCORCH = []
B = Y = P = S = None
RNG = random.Random(71)

strut = parts.strut
pipe = parts.pipe
window = parts.window
pick_lit = parts.pick_lit


def polar(r, a_deg, z=0.0):
    return wk.polar(r, math.radians(a_deg), z)


def zmax(r):
    """Highest a base item at horizontal radius r may reach: the -25 deg barrel cone from the
    pitch axis, minus the shroud ring radius (0.7) and a margin."""
    return 18.0 - math.tan(math.radians(25)) * (math.sqrt(max(r * r - 1.3 * 1.3, 0.0)) - 2.0) - 0.75


# ---------------------------------------------------------------- station look
def _kind(base, **kw):
    d = dict(st.WORN_KINDS[base])
    d.update(kw)
    return d


# Edge wear at turret scale: fine chips (chip_scale) on a crisp, narrow edge band (edge_cut
# and the 8 cm bevel bake in main), lighter worn-metal chips, so wear reads as the station's
# scuffed edges and streaks, not as soft dark blotches on the small house faces.
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
# Ammunition marking: dark maroon, small tags only, so it never reads orange.
st.WORN_KINDS["accent"] = _kind("accent", tones=[(0.12, 0.035, 0.03), (0.105, 0.031, 0.027),
                                (0.135, 0.04, 0.034), (0.10, 0.033, 0.029), (0.115, 0.036, 0.03),
                                (0.11, 0.034, 0.03)])
# Heat radiator panels: dark grey, fine coolant channels running vertically (panel u = X or
# Y along the panel, v = Z), so they read as channels off the manifold, not as slats.
st.WORN_KINDS["radpanel"] = _kind("radiator", tones=[(0.13, 0.135, 0.14), (0.12, 0.125, 0.13),
                                  (0.145, 0.15, 0.155), (0.115, 0.12, 0.125),
                                  (0.135, 0.14, 0.145), (0.125, 0.13, 0.135)], big=(0.72, 6.0),
                                  plate=(0.18, 6.0), rough=(0.42, 0.06), metal=0.35,
                                  seam_big=0.25, seam_small=0.2, chip_k=0.2, grime_k=0.5,
                                  streak_k=0.25)
# Fine radiator wing channels: narrow, low-contrast vertical channels (no raised fin ribs), so
# the wings read as ISS radiator panels, not slats or roll-up shutters.
st.WORN_KINDS["radfine"] = _kind("radiator", tones=[(0.085, 0.09, 0.098), (0.08, 0.085, 0.092),
                                 (0.09, 0.095, 0.103), (0.078, 0.082, 0.09),
                                 (0.088, 0.092, 0.1), (0.082, 0.087, 0.095)], big=(3.2, 6.0),
                                 plate=(0.4, 6.0), rough=(0.72, 0.05), metal=0.04,
                                 seam_big=0.08, seam_small=0.035, chip_k=0.15, grime_k=0.4,
                                 streak_k=0.2, bleach=0.0, fins=False)
# Reaction-mass tanks: dark blue-grey, no sun bleach, a full value step under the house.
st.WORN_KINDS["tank"] = _kind("hull2", tones=[(0.115, 0.125, 0.14), (0.10, 0.11, 0.123),
                              (0.125, 0.135, 0.15), (0.095, 0.104, 0.115), (0.12, 0.126, 0.135),
                              (0.108, 0.117, 0.13)], plate_var=0.04, rough=(0.48, 0.1),
                              metal=0.25, big=(2.4, 1.6), plate=(1.2, 0.8), grime_k=0.7,
                              chip_k=0.7, chip=(0.28, 0.28, 0.29), bleach=0.0, **FINE)
# Inset deck plates and hatch lids: a touch lighter than the pad deck, never sun-bleached.
st.WORN_KINDS["deckplate"] = _kind("pad", tones=[(0.14, 0.142, 0.15), (0.128, 0.13, 0.137),
                                   (0.15, 0.152, 0.158), (0.122, 0.124, 0.13),
                                   (0.145, 0.143, 0.14), (0.134, 0.136, 0.142)], bleach=0.0,
                                   big=(1.2, 1.2), plate=(0.6, 0.6), pad=False, **FINE)
# Gun steel: dark blued metal, bright chips, carbon fouling instead of brown grime.
st.WORN_KINDS["gunmetal"] = _kind("metal", tones=[(0.12, 0.125, 0.132), (0.10, 0.105, 0.112),
                                  (0.135, 0.14, 0.147), (0.11, 0.115, 0.122),
                                  (0.145, 0.15, 0.157), (0.125, 0.13, 0.137)],
                                  rough=(0.40, 0.10), metal=0.8, chip=(0.50, 0.50, 0.52),
                                  chip_k=0.8, grime_k=1.0, streak_k=0.4, rivets=False,
                                  hatches=0.0, bleach=0.0, **FINE)
# Dark tank skin (keel tanks, magazine can, deck tanks). A dielectric at the deck's albedo
# reads mid grey in Godot (the "dark" kind only reads dark because it is half metal), so this
# is a full value step darker than the deck and partly metallic, with a rough finish.
st.WORN_KINDS["tankdark"] = _kind("hull2", tones=[(0.042, 0.045, 0.05), (0.038, 0.041, 0.046),
                                  (0.046, 0.049, 0.054), (0.036, 0.039, 0.043),
                                  (0.044, 0.046, 0.05), (0.04, 0.043, 0.048)], plate_var=0.03,
                                  rough=(0.62, 0.06), metal=0.35, big=(2.4, 1.6),
                                  plate=(1.2, 0.8), grime_k=0.6, chip_k=0.6,
                                  chip=(0.24, 0.24, 0.25), bleach=0.0, **FINE)
# Flat link chutes: gun steel with a duller, rougher finish than the receivers.
st.WORN_KINDS["chute"] = _kind("gunmetal", rough=(0.55, 0.08), metal=0.55, chip_k=0.5)


def build_materials():
    m = common.make_material
    wk.build_materials(PRE, MATS)
    MATS["slate"] = m(f"{PRE}_hull_slate", (0.16, 0.19, 0.22), roughness=0.58)
    MATS["gunmetal"] = m(f"{PRE}_gunmetal", (0.12, 0.125, 0.135), roughness=0.4, metallic=0.8)
    MATS["radpanel"] = m(f"{PRE}_radiator_fin", (0.17, 0.175, 0.18), roughness=0.5, metallic=0.3)
    MATS["radfine"] = m(f"{PRE}_radiator_wing", (0.085, 0.09, 0.098), roughness=0.72, metallic=0.04)
    MATS["tank"] = m(f"{PRE}_tank", (0.115, 0.125, 0.14), roughness=0.48, metallic=0.25)
    MATS["deckplate"] = m(f"{PRE}_deck_plate", (0.14, 0.142, 0.15), roughness=0.7, metallic=0.2)
    MATS["tankdark"] = m(f"{PRE}_tank_dark", (0.042, 0.045, 0.05), roughness=0.62, metallic=0.35)
    MATS["chute"] = m(f"{PRE}_link_chute", (0.12, 0.125, 0.135), roughness=0.55, metallic=0.55)
    glow = (0.03, 0.028, 0.025)
    for key, col, s in (("nav_red", (1.0, 0.08, 0.03), 6.0), ("nav_green", (0.08, 1.0, 0.22), 6.0),
                        ("nav_white", (1.0, 0.97, 0.92), 4.0), ("flood", (1.0, 0.95, 0.85), 4.5),
                        ("flood_low", (1.0, 0.95, 0.85), 1.5)):
        MATS[key] = m(f"{PRE}_{key}", glow, roughness=0.3, emission=col, emission_strength=s)
        MATS[key].use_backface_culling = False
    # Godot recolours this one (green / amber / red); exact name, no prefix, only on S.
    # Authored in the game's IDLE_COLOR so previews and the icon match the idle state.
    MATS["status"] = m("turret_status_light", (0.3, 1.0, 0.45), roughness=0.3,
                       emission=(0.3, 1.0, 0.45), emission_strength=6.0)


# ---------------------------------------------------------------- helpers
def label(text, centre, normal, up, h, colour, opacity=0.85, depth=0.6):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity, depth))


def up_for(n_up):
    """Label up direction that never reads upside down from the south (-Y) camera."""
    n_up = V(n_up)
    return n_up if n_up.y >= -1e-3 else -n_up


def nav(part, c, mat, s=0.5, hang=False):
    """Nav light: dark base + emissive cap (the base above the cap when it hangs)."""
    c = V(c)
    d = 1.0 if hang else -1.0
    part.box(c + V((0, 0, d * s * 0.45)), (s * 0.7, s * 0.7, s * 0.4), "dark", bevel=0.0)
    part.box(c, (s, s, s * 0.6), mat, bevel=0.0)


def truss(p, p0, p1, w, h, n, mat, chord=0.22, brace=0.13, up=UP, diag=True, brace_mat=None):
    """Open square truss p0 -> p1: 4 longerons, n bays, frames and side diagonals."""
    p0, p1 = V(p0), V(p1)
    bm = brace_mat or mat
    x = (p1 - p0).normalized()
    z = (up - x * up.dot(x)).normalized()
    y = z.cross(x)
    for cy, cz in [(sy * w / 2, sz * h / 2) for sy in (-1, 1) for sz in (-1, 1)]:
        strut(p, p0 + y * cy + z * cz, p1 + y * cy + z * cz, chord, chord, mat, up=z)
    pts = [p0.lerp(p1, i / n) for i in range(n + 1)]
    for i, q in enumerate(pts):
        for sz in (-1, 1):
            strut(p, q + z * sz * h / 2 - y * w / 2, q + z * sz * h / 2 + y * w / 2, brace,
                  brace, bm, up=z)
        if not diag or i == n:
            continue
        qa, qb = (q, pts[i + 1]) if i % 2 == 0 else (pts[i + 1], q)
        for sy in (-1, 1):
            strut(p, qa + y * sy * w / 2 - z * h / 2, qb + y * sy * w / 2 + z * h / 2, brace,
                  brace, bm, up=y)


def handrail(p, pts, hgt=0.9, t=0.06):
    up = UP * hgt
    for a, b in zip(pts, pts[1:]):
        strut(p, a + up, b + up, t, t, "metal")
        strut(p, a + up * 0.5, b + up * 0.5, t * 0.8, t * 0.8, "metal")
    for a in pts:
        strut(p, a, a + up, t, t, "metal")


def hazard_band(p, c0, c1, w, h, up=UP, pitch=0.9):
    """Alternating hazard / dark segments c0 -> c1 (h measured along `up`)."""
    c0, c1 = V(c0), V(c1)
    n = max(2, int((c1 - c0).length / pitch))
    for i in range(n):
        p.beam(c0.lerp(c1, i / n), c0.lerp(c1, (i + 1) / n), w, h,
               "hazard" if i % 2 == 0 else "dark", up=up)


def bracket_pipe(p, p0, p1, rad, mat, step=2.0, drop=0.3):
    """Conduit run with dark brackets every `step` metres (towards -Z by `drop`)."""
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


def smooth_path(pts, rad, steps=7):
    """Polyline with every inner corner replaced by a quadratic Bezier of reach `rad`."""
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


def rrect(w, h, cr, n=3):
    """Rounded rectangle section (x across, y up), corner radius cr, n steps per corner."""
    pts = []
    for cx, cy, a0 in ((1, 1, 0.0), (-1, 1, 90.0), (-1, -1, 180.0), (1, -1, 270.0)):
        for k in range(n + 1):
            a = math.radians(a0 + 90.0 * k / n)
            pts.append((cx * (w / 2 - cr) + cr * math.cos(a), cy * (h / 2 - cr) + cr * math.sin(a)))
    return pts


def sweep(p, path, w, h, mat, side, cr=0.08, cap=True):
    """Rounded-rect conduit along `path` (a curve in the plane normal to `side`)."""
    side = V(side).normalized()
    sec = rrect(w, h, cr)
    rings = []
    for i, c in enumerate(path):
        t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        t = (t - side * t.dot(side)).normalized()
        u = side.cross(t)
        rings.append([c + side * x + u * y for x, y in sec])
    p.loft(rings, mat, cap=cap)


def path_points(path, step, skip0=0.0, skip1=0.0):
    """(point, tangent) every `step` metres of arc length along a polyline."""
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


# ---------------------------------------------------------------- base: keel
def tank_prof(r, z0, z1, zb0, zb1, steps, dome_k=0.55):
    """Domed tank profile z0..z1 (radius r), a band zb0..zb1; band face index = steps + 1."""
    dome = r * dome_k
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


def tank_h(p, c, a_deg, r, length, body, band="dark", segs=20, steps=5, dome_k=0.55):
    """Horizontal tank lying tangentially at polar angle a_deg, centred at c."""
    prof = tank_prof(r, -length / 2, length / 2, -0.18, 0.18, steps, dome_k)
    ar = math.radians(a_deg)
    tangent = V((-math.sin(ar), math.cos(ar), 0.0))
    rot = tangent.to_track_quat("Z", "Y").to_matrix().to_4x4()
    p.lathe(prof, segs, lambda i, j: band if j == steps + 1 else body,
            matrix=Matrix.Translation(V(c)) @ rot)
    return tangent


def tank_v(p, c, r, h, body, band="dark", segs=16, steps=5):
    """Vertical domed tank, base at c.z (worn_kit.tank_v with rounder domes)."""
    x, y, z0 = c
    dome = r * 0.55
    zb0 = z0 + dome + (h - 2 * dome) * 0.62
    prof = tank_prof(r, z0, z0 + h, zb0, zb0 + (h - 2 * dome) * 0.1, steps)
    p.lathe(prof, segs, lambda i, j: band if j == steps + 1 else body,
            matrix=Matrix.Translation((x, y, 0)))


def build_keel():
    """Magazine can and two short reaction-mass tanks tucked under the core, all matte dark
    so they sit back in shadow instead of reading as pale bottles."""
    def can_mf(i, j):
        if j < 2:
            return "dark"
        return can_patch[i // 4]
    can_patch = [RNG.choice(("tankdark", "dark", "tankdark")) for _ in range(4)]
    B.lathe([(0.0, 4.3), (1.7, 4.3), (2.4, 4.9), (2.4, 8.2)], 16, can_mf, start=math.pi / 16)
    for z in (5.4, 6.4, 7.4):
        B.cyl(V((0, 0, z)), 2.48, 2.48, 0.3, "dark", segs=16)
    label("MAG", V((0, -2.42, 6.9)), V((0, -1, 0)), UP, 0.45, INK_LIGHT, 0.7)
    nav(B, V((0, 0, 4.12)), "nav_white", 0.4, hang=True)
    # two short reaction-mass tanks under the camera side, strapped to the can
    for a in (225, 315):
        c = polar(4.4, a, 5.3)
        tank_v(B, (c.x, c.y, c.z), 0.95, 2.6, "tankdark", band="dark")
        for z in (6.0, 7.1):
            B.beam(polar(3.45, a, z), polar(2.3, a, z), 0.25, 0.25, "dark")
    # feet: can -> core bottom
    for k in range(8):
        a = 22.5 + 45 * k
        strut(B, polar(2.4, a, 5.8), polar(4.6, a, 8.05), 0.24, 0.24, "dark")


# ---------------------------------------------------------------- base: platform
SLAB_UNDER = (5.2, 11.0, 7.3, 11.55)     # underside slope: (r0, z0) -> (r1, z1)
NOTCHES = (0.0, 90.0, 180.0)              # rim notches: wing roots and the power conduit
NOTCH_HW = 7.0                            # notch half width, degrees
RIM_IN = 6.6                              # notch depth: the rim is cut back to this radius


def under_z(r):
    r0, z0, r1, z1 = SLAB_UNDER
    return z0 + (r - r0) / (r1 - r0) * (z1 - z0)


def rim_arcs():
    """(a0, a1) arcs of the slab rim between the notches."""
    cuts = sorted(NOTCHES)
    out = []
    for k, c in enumerate(cuts):
        nxt = cuts[(k + 1) % len(cuts)] + (360.0 if k == len(cuts) - 1 else 0.0)
        out.append((c + NOTCH_HW, nxt - NOTCH_HW))
    return out


def in_notch(a_deg, pad=0.0):
    return any(abs(((a_deg - c + 180) % 360) - 180) < NOTCH_HW + pad for c in NOTCHES)


def build_drum():
    """Thin deck slab on a recessed core. The slab is a thin armoured edge (r 7.6, z 11.75 ..
    12.3) over an underside that slopes back up to the core, so from the game camera the
    base reads as a deck plate, not a saucer. Three notches cut the rim back to r 6.6: the
    radiator wing roots (+-X) and the power conduit (+Y). Thin armour cassettes and an open
    ring truss hang under the slab, so the core shows through gaps."""
    # inner slab (full circle) out to the notch depth; its r 6.6 wall is the notch back wall
    zi = under_z(RIM_IN)
    B.lathe([(0.0, 11.0), (SLAB_UNDER[0], 11.0), (RIM_IN, zi), (RIM_IN, deck_z(RIM_IN)),
             (4.4, 12.6)], 64, lambda i, j: ("dark", "hull2", "dark", "pad")[j],
            start=math.pi / 64)
    # outer rim sectors between the notches (convex section swept round the arc)
    sec = [(RIM_IN, zi), (7.3, 11.55), (DRUM_R, 11.75), (DRUM_R, 12.3), (7.2, 12.5),
           (RIM_IN, deck_z(RIM_IN))]
    sec_mats = ("hull2", "hull2", None, "pad", "pad", "dark")
    for a0, a1 in rim_arcs():
        n = max(2, round((a1 - a0) / 5.625))
        body = [RNG.choice(("hull", "hull3", "slate", "hull", "hull2")) for _ in range(n)]
        rings = []
        for k in range(n + 1):
            a = a0 + (a1 - a0) * k / n
            rings.append([polar(r, a, z) for r, z in sec])
        for k in range(n):
            am = a0 + (a1 - a0) * (k + 0.5) / n
            if 225 <= am % 360 <= 315:
                body[k] = "hull"

        def mf(i, j, body=body):
            return sec_mats[j] or body[i]
        B.loft(rings, "hull2", cap=True, mat_fn=mf)
    # notch fittings: a dark frame lip on each notch edge, a grating across the back
    for c in NOTCHES:
        for sd in (-1, 1):
            a = c + sd * NOTCH_HW
            B.beam(polar(RIM_IN, a, 12.52), polar(DRUM_R, a, 12.32), 0.12, 0.1, "dark")
        for k in range(4):
            a = c - NOTCH_HW * 0.8 + k * NOTCH_HW * 1.6 / 3
            box_ra(B, RIM_IN + 0.04, a, 12.0, (0.08, 0.1, 0.9), "metal")
    # recessed core under the slab
    cpatch = [RNG.choice(("hull3", "slate", "hull2")) for _ in range(6)]
    B.lathe([(0.0, 8.0), (4.8, 8.0), (5.2, 8.4), (5.2, 11.05), (0.0, 11.05)], 24,
            lambda i, j: "dark" if j < 2 else cpatch[i // 4], start=math.pi / 24)
    for z in (9.0, 10.2):
        B.cyl(V((0, 0, z)), 5.26, 5.26, 0.16, "dark", segs=24)
    # core risers and junction boxes (seen through the cassette gaps)
    for a in (190, 262, 278, 350, 10, 170):
        for k, o in enumerate((-0.14, 0.14)):
            ar = math.radians(a)
            t = V((-math.sin(ar), math.cos(ar), 0))
            c0 = polar(5.32, a, 8.5) + t * o
            pipe(B, c0, c0 + V((0, 0, 2.5)), 0.06, "metal" if k == 0 else "dark", segs=6)
        box_ra(B, 5.33, a, 9.6, (0.22, 0.6, 0.4), "hull2", bevel=0.03)
        box_ra(B, 5.45, a, 9.6, (0.03, 0.4, 0.06), "metal")

    # slab edge: one regular window strip on the camera side
    rf = DRUM_R + 0.012
    for k in range(7):
        a = math.radians(243 + 9.0 * k)
        n = V((math.cos(a), math.sin(a), 0))
        lit = {1: "window", 3: "window_cool", 5: "window"}.get(k)
        window(B, V((0, 0, 12.03)) + n * rf, n, UP, 0.3, 0.3, lit)
    # trim rail under the edge, pipe runs round the back half of the edge, bracketed
    for a0, a1 in rim_arcs():
        pts = ring_pts(7.64, a0 + 1.0, a1 - 1.0, 11.8, step_m=1.2)
        for p0, p1 in zip(pts, pts[1:]):
            B.beam(p0, p1, 0.06, 0.06, "metal")
    for a0, a1 in ((-55, -8), (8, 55), (125, 172), (188, 235)):
        pts = ring_pts(7.72, a0, a1, 12.16, step_m=1.4)
        for p0, p1 in zip(pts, pts[1:]):
            pipe(B, p0, p1, 0.06, "metal", segs=6)
        for q in pts[::2]:
            B.box(q - q.normalized().to_2d().to_3d() * 0.05, (0.14, 0.14, 0.2), "dark",
                  bevel=0.0)
    # small edge greebles
    for a, s, mat in ((205, (0.12, 0.5, 0.34), "hull2"), (229, (0.1, 0.3, 0.3), "dark"),
                      (312, (0.12, 0.45, 0.26), "hull2"), (334, (0.1, 0.36, 0.36), "dark"),
                      (66, (0.12, 0.6, 0.36), "hull2"), (114, (0.12, 0.6, 0.36), "hull2"),
                      (22, (0.1, 0.28, 0.22), "dark"), (158, (0.1, 0.28, 0.22), "dark")):
        box_ra(B, 7.62 + s[0] / 2, a, 12.02, s, mat, bevel=0.02)
    # RCS quads on standoffs on the slab edge
    for k in range(4):
        a = 45 + 90 * k
        box_ra(B, 7.7, a, 12.02, (0.3, 0.4, 0.36), "dark")
        parts.rcs_quad(B, polar(7.98, a, 12.02), polar(1.0, a), "hull2", "dark", s=0.3, fwd=UP)
        c = polar(7.98, a, 12.02)
        SCORCH.append((c.x, c.y, c.z, 0.9))

    # open ring truss under the slab: octagon + braces down to the core foot
    verts = [polar(6.3, 22.5 + 45 * k, under_z(6.3) - 0.14) for k in range(8)]
    feet = [polar(5.2, 22.5 + 45 * k, 8.5) for k in range(8)]
    for k in range(8):
        n = (k + 1) % 8
        strut(B, verts[k], verts[n], 0.2, 0.2, "dark")
        strut(B, feet[k], verts[k], 0.2, 0.2, "dark")
        strut(B, feet[k], verts[n], 0.12, 0.12, "metal")
        B.box(verts[k], (0.34, 0.34, 0.24), "dark", rot_z=math.radians(22.5 + 45 * k), bevel=0.0)
    # thin armour cassettes hung under the slab, chamfered outer face, gaps between them
    for a, mat in ((205, "slate"), (243, "dark"), (297, "dark"), (335, "slate"),
                   (25, "slate"), (155, "slate")):
        ar = math.radians(a)
        t = V((-math.sin(ar), math.cos(ar), 0))
        z0, z1 = 9.6, under_z(6.95) - 0.05
        prof = [(6.78, z0), (6.9, z0), (6.98, z0 + 0.12), (6.98, z1 - 0.18), (6.88, z1),
                (6.78, z1)]
        pts = [polar(r, a, z) + t * o for r, z in prof for o in (-1.0, 1.0)]
        parts.part_hull(B, pts, mat)
        box_ra(B, 6.99, a, z0 + 0.32, (0.04, 1.8, 0.08), "dark")
        for o in (-0.7, 0.7):
            for z in (z1 - 0.35, z0 + 0.4):
                strut(B, polar(6.78, a, z) + t * o, polar(5.2, a, z) + t * o * 0.8, 0.13,
                      0.13, "dark")
    label("R-02", polar(6.995, 243, 10.55), polar(1.0, 243), UP, 0.3, INK_LIGHT)
    label("#BAR", polar(6.995, 297, 10.55), polar(1.0, 297), UP, 0.2, INK_LIGHT, 0.6)


def build_wings():
    """Radiator wings off +-X: one broad, near-horizontal panel per side (tilted 10 deg to the
    camera side), so the game camera sees its face, not its edge. A coolant manifold runs
    out of the rim notch under the panel's centre line; a thin light frame, a root fitting in
    the notch, a strut from the core, a tip fitting with a white strobe (green means status)."""
    tilt = math.radians(10.0)
    x0, x1, hw, zp = 8.0, 11.15, 1.5, 11.5
    for sx in (-1, 1):
        r = Matrix.Rotation(-tilt, 4, "X")     # -Y edge down: the face turns to the camera
        r3 = r.to_3x3()
        xc = sx * (x0 + x1) / 2
        c = V((xc, 0, zp))
        B.box(c, (x1 - x0, 2 * hw, 0.06), "radfine", r=r, bevel=0.0)
        # thin light frame: two long rails, end bars, one mid bar
        for y in (-hw, hw):
            B.box(c + r3 @ V((0, y, 0.0)), (x1 - x0, 0.09, 0.1), "radiator", r=r, bevel=0.0)
        for x in (x0, (x0 + x1) / 2, x1):
            B.box(V((sx * x, 0, zp)), (0.09, 2 * hw, 0.1), "radiator", r=r, bevel=0.0)
        # coolant manifold under the centre line, out of the notch, and a thin return line
        zb = zp - 0.14
        pipe(B, V((sx * 6.75, 0, zb)), V((sx * 11.05, 0, zb)), 0.12, "metal", segs=8)
        pipe(B, V((sx * 6.75, 0.24, zb - 0.06)), V((sx * 10.9, 0.24, zb - 0.06)), 0.045, "dark",
             segs=6)
        for x in (8.6, 9.6, 10.6):            # saddles holding the panel to the manifold
            B.box(V((sx * x, 0, zb + 0.05)), (0.16, 0.5, 0.12), "dark", bevel=0.0)
        # root fitting in the rim notch
        B.box(V((sx * 7.15, 0, 11.75)), (0.9, 1.0, 0.7), "dark", bevel=0.04)
        B.box(V((sx * 7.15, 0, 12.12)), (0.7, 0.8, 0.06), "hull2", bevel=0.0)
        label("HOT", V((sx * 7.15, -0.51, 11.75)), V((0, -1, 0)), UP, 0.2, INK_LIGHT)
        strut(B, V((sx * 5.2, 0, 9.4)), V((sx * 8.6, 0, zb - 0.1)), 0.14, 0.14, "dark")
        strut(B, V((sx * 5.2, 0.3, 10.3)), V((sx * 6.9, 0.3, zb - 0.1)), 0.1, 0.1, "metal")
        # tip fitting: a swivel block and end cap on the manifold, strobe on top
        B.box(V((sx * 11.05, 0, zb)), (0.22, 0.32, 0.32), "dark", bevel=0.03)
        B.cyl(V((sx * 11.19, 0, zb)), 0.09, 0.09, 0.06, "metal", segs=8, axis_rot=ALONG_X)
        nav(B, V((sx * 11.05, -0.3, zp + 0.12)), "nav_white", 0.2)
        SCORCH.append((sx * 7.15, 0.0, 11.75, 0.5))


def deck_z(r):
    """Top of the deck at radius r (slab top chamfer 4.4 -> 7.2)."""
    return 12.6 - (r - 4.4) / 2.8 * 0.1


def build_shoulder():
    zd = deck_z
    # inset deck plates and access panels: few, uneven, a seam across the full plate and a
    # lift handle at the outer edge (no centred "switch" glyph)
    for a, r, s, so in ((3, 5.75, (1.4, 1.1), 0.2), (176, 5.5, (1.0, 1.2), -0.25),
                        (253, 5.3, (0.9, 0.85), 0.18), (318, 6.6, (0.75, 0.65), 0.0),
                        (101, 6.55, (0.7, 0.8), -0.15)):
        ar = math.radians(a)
        t = V((-math.sin(ar), math.cos(ar), 0))
        box_ra(B, r, a, zd(r) + 0.015, (s[0], s[1], 0.04), "deckplate")
        if so:
            B.box(polar(r, a, zd(r) + 0.035) + t * so * s[1], (s[0], 0.035, 0.02), "dark",
                  rot_z=ar, bevel=0.0)
        B.box(polar(r + s[0] / 2 - 0.09, a, zd(r) + 0.045) - t * s[1] * 0.25, (0.05, 0.22, 0.035),
              "metal", rot_z=ar, bevel=0.0)
    # ammo hatches (dark frames, one small accent tag each) and hoists to the barbette
    for a in (235, 305):
        ar = math.radians(a)
        r3 = Matrix.Rotation(ar, 4, "Z").to_3x3()
        c = polar(6.4, a, zd(6.4))
        B.box(c + V((0, 0, 0.01)), (1.3, 1.3, 0.08), "deckplate", rot_z=ar, bevel=0.0)
        for dx, dy, w, l in ((0.7, 0, 0.1, 1.5), (-0.7, 0, 0.1, 1.5), (0, 0.7, 1.4, 0.1),
                             (0, -0.7, 1.4, 0.1)):
            B.box(c + r3 @ V((dx, dy, 0.035)), (w, l, 0.1), "dark", rot_z=ar, bevel=0.0)
        B.box(c + r3 @ V((0.45, 0.45, 0.07)), (0.24, 0.24, 0.05), "accent", rot_z=ar, bevel=0.0)
        for dx in (-0.5, 0.5):     # lift handles, clear of the stencil
            B.box(c + r3 @ V((dx, 0.0, 0.07)), (0.06, 0.3, 0.05), "metal", rot_z=ar, bevel=0.0)
        # hoist: a cantilever monorail out of the barbette feed box (no gantry post), knee
        # braced from the barbette foot, a trolley over the hatch and an ammo canister on it
        h = 14.3
        p_out, p_in = polar(6.95, a, h), polar(4.5, a, h)
        B.beam(p_out, p_in, 0.2, 0.26, "dark")
        B.beam(p_out + V((0, 0, 0.16)), p_in + V((0, 0, 0.16)), 0.26, 0.06, "metal")
        box_ra(B, 6.98, a, h - 0.05, (0.08, 0.34, 0.46), "hull2")
        strut(B, polar(4.42, a, 12.95), polar(6.0, a, h - 0.14), 0.14, 0.14, "dark")
        strut(B, polar(5.2, a, 13.35), polar(5.2, a, h - 0.14), 0.08, 0.08, "metal")
        box_ra(B, 6.4, a, h - 0.3, (0.5, 0.4, 0.3), "gunmetal", bevel=0.04)
        for o in (-0.15, 0.15):
            B.cyl(polar(6.4 + o, a, h - 0.1), 0.07, 0.07, 0.34, "dark", segs=8,
                  axis_rot=Matrix.Rotation(ar, 4, "Z") @ ALONG_Y)
        cz = zd(6.4) + 0.32 + 0.45          # canister centre, 0.32 over the hatch
        for o in (-0.18, 0.18):
            pipe(B, polar(6.4 + o, a, h - 0.45), polar(6.4 + o, a, cz + 0.45), 0.025, "metal",
                 segs=5)
        box_ra(B, 6.4, a, cz, (0.6, 0.6, 0.9), "gunmetal", bevel=0.08)
        for dz in (-0.28, 0.28):
            box_ra(B, 6.4, a, cz + dz, (0.63, 0.63, 0.08), "dark")
        box_ra(B, 6.4, a, cz + 0.47, (0.44, 0.2, 0.06), "dark")
        B.box(polar(6.4, a, cz + 0.05) + r3 @ V((0, -0.31, 0)), (0.2, 0.02, 0.14), "accent",
              rot_z=ar, bevel=0.0)
        box_ra(B, 4.47, a, 14.15, (0.3, 0.9, 0.9), "dark")
        box_ra(B, 4.5, a, 14.66, (0.1, 1.0, 0.1), "metal")
        rad = V((math.cos(ar), math.sin(ar), 0))
        label("AMMO", polar(6.4, a, zd(6.4) + 0.1), UP, up_for(rad), 0.36, INK_DARK, 0.9)
    # radial cable trays at four angles, junction boxes at each end
    for a in (20, 160, 200, 340):
        ar = math.radians(a)
        r0, r1 = 4.55, 7.15
        B.beam(polar(r0, a, zd(r0) + 0.06), polar(r1, a, zd(r1) + 0.06), 0.42, 0.1, "dark")
        for sd in (-1, 1):
            t = V((-math.sin(ar), math.cos(ar), 0)) * 0.2 * sd
            B.beam(polar(r0, a, zd(r0) + 0.14) + t, polar(r1, a, zd(r1) + 0.14) + t, 0.04,
                   0.08, "metal")
        for k in range(3):
            t = V((-math.sin(ar), math.cos(ar), 0)) * (-0.1 + k * 0.1)
            pipe(B, polar(r0, a, zd(r0) + 0.17) + t, polar(r1, a, zd(r1) + 0.17) + t, 0.035,
                 ("metal", "dark", "metal")[k], segs=5)
        box_ra(B, 4.75, a, zd(4.75) + 0.3, (0.4, 0.6, 0.6), "hull2", bevel=0.04)
        box_ra(B, 4.96, a, zd(4.75) + 0.35, (0.03, 0.4, 0.08), "metal")
        box_ra(B, 7.1, a, zd(7.1) + 0.22, (0.36, 0.5, 0.44), "dark", bevel=0.03)
    # ring conduit round the barbette foot, bracketed
    pts = ring_pts(4.62, 0, 360, 12.78, step_m=0.9)
    for p0, p1 in zip(pts, pts[1:]):
        pipe(B, p0, p1, 0.075, "metal", segs=6)
        pipe(B, p0 + V((0, 0, 0.18)), p1 + V((0, 0, 0.18)), 0.045, "dark", segs=5)
    for q in pts[:-1:3]:
        B.box(q + V((0, 0, -0.04)), (0.18, 0.18, 0.36), "dark", rot_z=math.atan2(q.y, q.x),
              bevel=0.0)
    # power conduit from the service side straight in to the barbette
    for x, rad in ((-0.35, 0.13), (0.35, 0.1)):
        bracket_pipe(B, V((x, 7.3, 12.82)), V((x, 4.4, 12.82)), rad, "metal", step=1.2,
                     drop=0.24)
    box_ra(B, 4.75, 90, zd(4.75) + 0.35, (0.45, 1.3, 0.7), "hull2", bevel=0.05)
    label("PWR IN", polar(4.99, 90, zd(4.75) + 0.38), polar(1.0, 90), UP, 0.14, INK_LIGHT)
    # vents either side of the conduit
    for a in (72, 108):
        z = zd(5.6) + 0.22
        box_ra(B, 5.6, a, z, (1.0, 0.7, 0.44), "hull2", bevel=0.06)
        for k in range(5):
            box_ra(B, 5.6 - 0.36 + k * 0.18, a, z + 0.24, (0.06, 0.62, 0.05), "dark")
    # deck reaction-mass tanks on cradles at 45 / 135 (they read from the RTS camera):
    # matte dark skin, shallow dished heads with a dark end ring, three dark straps
    for a in (45, 135):
        r, tr, ln = 6.15, 0.82, 3.8
        zc = zd(r) + 0.3 + tr
        t = tank_h(B, polar(r, a, zc), a, tr, ln, "tankdark", dome_k=0.2)
        rq = t.to_track_quat("Z", "Y").to_matrix().to_4x4()
        for o in (-1.05, 1.05):
            c = polar(r, a, zd(r) + 0.32) + t * o
            B.box(c, (1.3, 0.3, 0.3), "dark", rot_z=math.radians(a), bevel=0.0)
            B.cyl(polar(r, a, zc) + t * o, tr + 0.035, tr + 0.035, 0.14, "dark", segs=20,
                  axis_rot=rq)
            for rr in (-0.55, 0.55):
                strut(B, polar(r + rr, a, zd(r + rr)) + t * o, polar(r + rr * 0.9, a, zc - 0.45)
                      + t * o, 0.16, 0.16, "dark")
        for o in (-1, 1):                     # dark end rings at the head welds
            B.cyl(polar(r, a, zc) + t * o * (ln / 2 - tr * 0.2 - 0.06), tr + 0.03, tr + 0.03,
                  0.1, "dark", segs=20, axis_rot=rq)
        # fill line from the tank end to the deck
        e = polar(r, a, zc) - t * (ln / 2 + 0.05)
        pipe(B, e, e - V((0, 0, zc - zd(r) - 0.05)), 0.07, "metal", segs=6)
        B.box(V((e.x, e.y, zd(r) + 0.12)), (0.3, 0.3, 0.2), "dark", bevel=0.0)
        label("H2O", polar(r, a, zc + tr) + t * 0.55, UP, up_for(polar(1.0, a)), 0.32, INK_LIGHT,
              0.7, depth=0.4)
    # deck floods aimed at the barbette hatch
    for a in (258, 282):
        ar = math.radians(a)
        rad = V((math.cos(ar), math.sin(ar), 0))
        B.box(polar(6.95, a, zd(6.95) + 0.06), (0.25, 0.25, 0.14), "dark", bevel=0.0)
        box_ra(B, 6.95, a, zd(6.95) + 0.28, (0.4, 0.36, 0.3), "dark", bevel=0.03)
        parts.quad(B, polar(6.95, a, zd(6.95) + 0.28) - rad * 0.21, -rad, UP, 0.28, 0.18,
                   "flood")
    # lidar post on the deck rim
    a = 12
    box_ra(B, 6.9, a, zd(6.9) + 0.1, (0.6, 0.6, 0.2), "dark")
    B.cyl(polar(6.9, a, zd(6.9) + 0.9), 0.12, 0.12, 1.4, "dark", segs=8)
    B.cyl(polar(6.9, a, zd(6.9) + 1.75), 0.26, 0.26, 0.4, "gunmetal", segs=12)
    B.cyl(polar(6.9, a, zd(6.9) + 1.78), 0.275, 0.275, 0.1, "glass", segs=12)
    B.cyl(polar(6.9, a, zd(6.9) + 2.0), 0.16, 0.2, 0.08, "dark", segs=12)
    # toe-rail round the deck edge (no handrail), gaps at the conduit and the wing roots
    for a0, a1 in ((8, 82), (98, 172), (188, 352)):
        pts = ring_pts(7.25, a0, a1, zd(7.25) + 0.09, step_m=1.0)
        for p0, p1 in zip(pts, pts[1:]):
            B.beam(p0, p1, 0.07, 0.16, "metal")
    # tie-down cleats
    for k in range(16):
        a = k * 22.5 + 11.25
        if 75 < a < 105 or 25 < a < 65 or 115 < a < 155 or 225 < a < 245 or 295 < a < 315:
            continue
        box_ra(B, 6.85, a, zd(6.85) + 0.06, (0.16, 0.36, 0.12), "dark")
    label("NO STEP", polar(5.6, 208, zd(5.6) + 0.01), UP,
          up_for(V((-math.sin(math.radians(208)), math.cos(math.radians(208)), 0))), 0.34,
          INK_LIGHT)
    label("KEEP CLEAR", polar(5.45, 322, zd(5.45) + 0.01), UP,
          up_for(V((-math.sin(math.radians(322)), math.cos(math.radians(322)), 0))), 0.3,
          HAZ_INK, 0.7)


def build_barbette():
    """Armoured foot ring, a tall dark recessed band with structural strakes (the machine
    neck), then a short armour collar under the turntable, so the barbette never reads as a
    plain drum. The EVA hatch is a framed door module standing in the recess."""
    def mf(i, j):
        if j == 0:
            return "hull2"
        if j != 4:
            return "dark"
        ca = (i + 1) * 15.0
        for t in (0, 180, 270):
            if abs(((ca - t + 180) % 360) - 180) <= 25:
                return "hull2"
        return "slate"
    B.lathe([(BARB_R, 12.6), (BARB_R, 12.9), (3.95, 13.0), (3.95, 14.3), (BARB_R, 14.4),
             (BARB_R, 15.0), (4.5, 15.3), (4.5, 15.6), (0.0, 15.6)], 24, mf, start=math.pi / 24)
    for k in range(24):                      # strakes across the recessed band
        a = k * 15 + 7.5
        if abs(((a - 270 + 180) % 360) - 180) < 10:
            continue                         # the EVA door module stands here
        box_ra(B, 4.15, a, 13.65, (0.42, 0.16, 1.32), "hull2" if k % 2 else "gunmetal")
    for k in range(12):                      # a ring of pipe runs behind the strakes
        a0 = k * 30.0
        if abs(((a0 + 15 - 270 + 180) % 360) - 180) < 20:
            continue
        for z, rad, mat in ((13.3, 0.07, "metal"), (14.0, 0.05, "dark")):
            pts = ring_pts(4.02, a0, a0 + 30.0, z, step_m=0.8)
            for p0, p1 in zip(pts, pts[1:]):
                pipe(B, p0, p1, rad, mat, segs=6)
    # EVA door module in the recess on the camera side
    rf = BARB_R * math.cos(math.pi / 24)
    B.box(V((0, -(3.95 + rf) / 2, 13.65)), (1.3, rf - 3.95, 1.32), "hull2", bevel=0.04)
    B.box(V((0, -rf - 0.02, 13.62)), (0.8, 0.06, 1.05), "dark", bevel=0.0)
    B.box(V((0.26, -rf - 0.06, 13.62)), (0.06, 0.05, 0.3), "metal", bevel=0.0)
    label("EVA", V((0, -rf - 0.02, 14.23)), V((0, -1, 0)), UP, 0.12, INK_LIGHT)
    rfw = rf + 0.01
    for a_d, lit in ((292, "window"), (248, None), (270, "window_cool")):
        a = math.radians(a_d)
        n = V((math.cos(a), math.sin(a), 0))
        window(B, V((0, 0, 14.72)) + n * rfw, n, UP, 0.3, 0.26, lit)
    for sx in (-1, 1):
        label("DT-04", V((sx * 4.45, 0, 14.7)), V((sx, 0, 0)), UP, 0.4, INK_LIGHT)
    for k in range(24):
        a = k * 15 + 7.5
        box_ra(B, 4.5, a, 15.45, (0.12, 0.1, 0.1), "metal")


def build_service():
    """+Y service / power side (link_point side): plain, nothing above z 13.4."""
    B.box(V((0, 6.925, 10.1)), (4.4, 3.25, 3.4), "hull2", bevel=0.08)
    B.box(V((0, 7.85, 11.84)), (4.5, 1.5, 0.08), "dark", bevel=0.0)
    for x in (-1.0, 0.0, 1.0):
        pipe(B, V((x, 8.5, 10.1)), V((x, 9.25, 10.1)), 0.22, "metal", segs=8)
        B.cyl(V((x, 9.3, 10.1)), 0.32, 0.32, 0.12, "dark", segs=10, axis_rot=ALONG_Y)
        B.cyl(V((x, 8.58, 10.1)), 0.3, 0.3, 0.06, "dark", segs=10, axis_rot=ALONG_Y)
    for sx in (-1, 1):
        B.box(V((sx * 2.22, 6.6, 9.9)), (0.1, 0.9, 1.7), "dark", bevel=0.0)
        bolt_row(B, V((sx * 2.24, 5.6, 11.5)), V((sx * 2.24, 8.3, 11.5)), 8, 0.07)
    label("EVA", V((2.22, 6.6, 11.1)), V((1, 0, 0)), UP, 0.3, INK_LIGHT)
    label("PWR IN", V((0, 8.57, 11.0)), V((0, 1, 0)), UP, 0.4, INK_LIGHT)
    label("SVC", V((0, 8.57, 8.95)), V((0, 1, 0)), UP, 0.45, INK_LIGHT)
    label("R-02", V((1.6, 8.57, 9.0)), V((0, 1, 0)), UP, 0.3, INK_LIGHT)
    label("#BAR", V((-1.6, 8.57, 9.0)), V((0, 1, 0)), UP, 0.2, ID_BLUE)
    # comms mast with a small dish
    B.cyl(V((-1.7, 8.1, 12.4)), 0.12, 0.12, 1.2, "dark", segs=8)
    B.box(V((-1.7, 8.1, 11.92)), (0.4, 0.4, 0.16), "dark", bevel=0.0)
    parts.dish(B, V((-1.7, 8.1, 12.55)), 0.7, V((0, 0.6, 0.8)), "hull", "dark", depth=0.25,
               segs=12)
    nav(B, V((-1.7, 8.1, 13.15)), "nav_white", 0.3)
    # cable tray down under the core to the magazine can
    for x in (-0.35, 0.35):
        pts = [V((x, 6.0, 8.6)), V((x, 5.6, 7.8)), V((x, 2.6, 5.8))]
        for a, b in zip(pts, pts[1:]):
            pipe(B, a, b, 0.1, "dark")
    for a, b in ((V((0, 6.0, 8.6)), V((0, 5.6, 7.8))), (V((0, 5.6, 7.8)), V((0, 2.6, 5.8)))):
        n = max(1, int((b - a).length / 1.2))
        for k in range(1, n + 1):
            q = a.lerp(b, k / n)
            B.box(q, (1.0, 0.12, 0.12), "dark", bevel=0.0)


# ---------------------------------------------------------------- yaw
ROOF_Z = 19.0      # house roof, level with the cheek tops


def build_yaw():
    # turntable (2 cm over the barbette top) and skirt
    Y.cyl(V((0, 0, 15.81)), TT_R, TT_R, 0.38, "hull2", segs=32)
    Y.lathe([(4.3, 16.0), (4.3, 16.02), (4.6, 16.02), (4.6, 16.0)], 32, lambda i, j: "dark",
            start=math.pi / 32)
    for k in range(24):
        a = k * 15 + 7.5
        box_ra(Y, 4.45, a, 16.07, (0.14, 0.14, 0.1), "metal")
    Y.lathe([(4.62, 15.3), (4.75, 15.3), (4.75, 16.0), (4.62, 16.0), (4.62, 15.3)], 32,
            lambda i, j: "dark", start=math.pi / 32)
    for k in range(24):
        a0, a1 = k * 15, (k + 1) * 15
        Y.beam(polar(4.80, a0, 15.65), polar(4.80, a1, 15.65), 0.06, 0.2,
               "hazard" if k % 2 == 0 else "dark")

    # turret house: compact chamfered prism, roof dropping at the back
    hx, hxi = 2.8, 2.95
    prof = [(0.0, 16.0), (0.0, ROOF_Z), (-2.6, ROOF_Z), (-3.4, ROOF_Z - 0.6), (-3.4, 16.0)]
    inset = [(-0.15, 16.0), (-0.15, ROOF_Z - 0.15), (-2.55, ROOF_Z - 0.15),
             (-3.25, ROOF_Z - 0.67), (-3.25, 16.0)]
    pts = [V((sx * hx, y, z)) for sx in (-1, 1) for y, z in prof]
    pts += [V((sx * hxi, y, z)) for sx in (-1, 1) for y, z in inset]
    parts.part_hull(Y, pts, "hull")
    nrm = V((0, -0.6, 0.8)).normalized()
    Y.beam(V((0, -2.65, ROOF_Z - 0.04)) + nrm * 0.035, V((0, -3.35, ROOF_Z - 0.56)) + nrm * 0.035,
           5.4, 0.06, "hull2", up=nrm)
    # side armour skirts, dark sensor ports
    for sx in (-1, 1):
        Y.box(V((sx * 3.07, -1.85, 17.3)), (0.25, 2.9, 2.2), "slate", bevel=0.05)
        bolt_row(Y, V((sx * 3.21, -3.2, 18.25)), V((sx * 3.21, -0.5, 18.25)), 8, 0.08)
        bolt_row(Y, V((sx * 3.21, -3.2, 16.35)), V((sx * 3.21, -0.5, 16.35)), 8, 0.08)
        Y.box(V((sx * 3.21, -0.62, 17.75)), (0.06, 0.36, 0.32), "dark", bevel=0.0)
        window(Y, V((sx * 3.21, -0.62, 17.75)), V((sx, 0, 0)), UP, 0.22, 0.18, None)
    # roof: access hatch, grille
    rz = ROOF_Z
    Y.box(V((0.75, -1.0, rz + 0.06)), (1.0, 1.0, 0.12), "hull2", bevel=0.08)
    Y.box(V((0.75, -1.0, rz + 0.13)), (0.76, 0.76, 0.04), "dark", bevel=0.0)
    for k in range(5):
        Y.box(V((0.3, -2.4 + k * 0.15, rz + 0.03)), (0.8, 0.08, 0.06), "dark", bevel=0.0)
    label("NO STEP", V((0.75, -0.26, rz + 0.01)), UP, up_for(V((0, -1, 0))), 0.26, INK_DARK)
    # ready magazine at the back (one small accent tag = ammunition)
    mw, my, md, mz0, mz1 = 4.7, -3.85, 0.9, 16.05, 18.35
    mzc, mf = (mz0 + mz1) / 2, my - md / 2
    Y.box(V((0, my, mzc)), (mw, md, mz1 - mz0), "hull2", bevel=0.08)
    Y.box(V((0, my, mz1 + 0.02)), (mw - 0.4, md - 0.2, 0.06), "dark", bevel=0.0)
    for sx in (-1, 1):
        Y.box(V((sx * 0.95, mf - 0.02, mzc - 0.1)), (0.1, 0.06, 1.5), "dark", bevel=0.0)
        Y.box(V((sx * (mw / 2 - 0.05), my, mzc)), (0.12, md + 0.04, mz1 - mz0 - 0.2), "dark",
              bevel=0.0)
    Y.box(V((-1.55, mf - 0.02, mzc + 0.62)), (0.5, 0.05, 0.24), "accent", bevel=0.0)
    for x in (1.4, 1.9):
        Y.box(V((x, mf - 0.08, mzc + 0.05)), (0.06, 0.06, 2.1), "metal", bevel=0.0)
    for k in range(6):
        Y.box(V((1.65, mf - 0.12, 16.35 + k * 0.33)), (0.56, 0.06, 0.06), "metal", bevel=0.0)
    label("AMMO", V((0, mf - 0.02, mzc + 0.1)), V((0, -1, 0)), UP, 0.4, INK_LIGHT, 0.95)
    label("#BAR", V((-1.55, mf - 0.02, mzc - 0.6)), V((0, -1, 0)), UP, 0.2, ID_BLUE)

    # cheeks, trunnions, pinch hazard, elevation drive
    cprof = [(0.0, 16.0), (3.6, 16.0), (3.6, 16.6), (2.6, 19.0), (0.0, 19.0)]
    gnrm = V((0, 2.4, 1.0)).normalized()
    for sx in (-1, 1):
        parts.part_hull(Y, [V((sx * x, y, z)) for x in (1.99, 2.8) for y, z in cprof], "slate")
        parts.part_hull(Y, [V((sx * x, y, z)) for x in (1.95, 1.99) for y, z in cprof], "hull2")
        for (y0, y1, z0, z1) in ((0.2, 1.6, 16.3, 18.6), (1.8, 3.2, 16.3, 17.4)):
            Y.box(V((sx * 2.84, (y0 + y1) / 2, (z0 + z1) / 2)), (0.08, y1 - y0, z1 - z0),
                  "hull3", bevel=0.0)
            bolt_row(Y, V((sx * 2.9, y0 + 0.1, z1 - 0.1)), V((sx * 2.9, y1 - 0.1, z1 - 0.1)), 6,
                     0.07)
        Y.cyl(V((sx * 2.95, PITCH_Y, PITCH_Z)), 0.75, 0.75, 0.35, "gunmetal", segs=16,
              axis_rot=ALONG_X)
        Y.cyl(V((sx * 3.17, PITCH_Y, PITCH_Z)), 0.4, 0.4, 0.1, "dark", segs=12, axis_rot=ALONG_X)
        for k in range(6):
            a = k * math.pi / 3
            Y.box(V((sx * 3.14, PITCH_Y + 0.58 * math.cos(a), PITCH_Z + 0.58 * math.sin(a))),
                  (0.06, 0.1, 0.1), "metal", bevel=0.0)
        Y.cyl(V((sx * 1.94, PITCH_Y, PITCH_Z)), 0.7, 0.7, 0.02, "dark", segs=16,
              axis_rot=ALONG_X)
        xh = sx * 2.01
        hazard_band(Y, V((xh, 3.6 + 0.02, 16.05)), V((xh, 3.6 + 0.02, 16.6)), 0.12, 0.04,
                    up=V((0, 1, 0)), pitch=0.3)
        hazard_band(Y, V((xh, 3.6, 16.6)) + gnrm * 0.02, V((xh, 2.6, 19.0)) + gnrm * 0.02, 0.12,
                    0.04, up=gnrm, pitch=0.45)
    Y.box(V((-2.95, 0.6, 16.6)), (0.4, 1.0, 0.7), "hull2", bevel=0.06)
    Y.cyl(V((-2.97, 1.5, 16.6)), 0.26, 0.26, 0.8, "dark", segs=10, axis_rot=ALONG_Y)
    Y.cyl(V((-2.97, 1.92, 16.6)), 0.2, 0.2, 0.06, "metal", segs=10, axis_rot=ALONG_Y)

    # flexible link chutes: magazine feed box -> up the chamfer -> along the roof edge ->
    # down onto the cheek -> feed port over the trunnion. One swept conduit each, smooth
    # bends, metal ring clamps, saddles where it rests on the roof and the cheek.
    ch_w, ch_h = 0.5, 0.18
    zr = ROOF_Z + 0.11
    for sx in (-1, 1):
        x = sx * 2.15
        Y.box(V((sx * 2.1, -3.85, 18.48)), (0.5, 0.55, 0.26), "gunmetal", bevel=0.06)
        Y.box(V((sx * 2.1, -3.85, 18.63)), (0.4, 0.45, 0.04), "dark", bevel=0.0)
        Y.box(V((x, 1.75, 19.25)), (0.6, 0.5, 0.5), "gunmetal", bevel=0.06)
        Y.box(V((x, 1.75, 19.03)), (0.72, 0.62, 0.06), "dark", bevel=0.0)
        bolt_row(Y, V((x - 0.24, 2.01, 19.4)), V((x + 0.24, 2.01, 19.4)), 3, 0.06)
        path = smooth_path([V((x, y, z)) for y, z in ((-3.85, 18.74), (-3.15, 18.74),
                                                       (-2.62, zr), (1.6, zr))], 0.4)
        sweep(Y, path, ch_w, ch_h, "chute", V((1, 0, 0)), cr=0.05)
        for c, t in path_points(path, 1.2, skip0=0.35, skip1=0.3):
            sweep(Y, [c - t * 0.05, c + t * 0.05], ch_w + 0.06, ch_h + 0.06, "metal",
                  V((1, 0, 0)), cr=0.06)
        for y in (-2.2, -0.9):
            Y.box(V((x, y, ROOF_Z + 0.04)), (0.52, 0.16, 0.08), "dark", bevel=0.0)
        Y.box(V((x, 1.0, 19.06)), (0.5, 0.16, 0.12), "dark", bevel=0.0)
        # gun-coolant heat exchanger: a horizontal fin stack between two end plates on the
        # skirt, coolant headers above and below
        yc, zc, ln, ht = -1.95, 17.3, 2.0, 1.4
        Y.box(V((sx * 3.225, yc, zc)), (0.05, ln, ht), "dark", bevel=0.0)
        for k in range(9):
            Y.box(V((sx * 3.38, yc, zc - ht / 2 + 0.1 + k * (ht - 0.2) / 8)), (0.27, ln - 0.1, 0.035),
                  "gunmetal", bevel=0.0)
        for y in (yc - ln / 2, yc + ln / 2):
            Y.box(V((sx * 3.36, y, zc)), (0.32, 0.07, ht + 0.06), "dark", bevel=0.0)
        for z, rad in ((zc + ht / 2 + 0.09, 0.075), (zc - ht / 2 - 0.09, 0.065)):
            pipe(Y, V((sx * 3.36, yc - ln / 2 - 0.2, z)), V((sx * 3.36, yc + ln / 2 + 0.15, z)), rad,
                 "metal", segs=8)
        Y.box(V((sx * 3.3, yc - ln / 2 - 0.2, zc + ht / 2 + 0.09)), (0.18, 0.12, 0.18), "dark",
              bevel=0.0)

    # fire control: armoured phased-array slab on the roof front edge, lidar can
    tilt = Matrix.Rotation(0.26, 4, "X")   # face tilted up over the barrels
    ac = V((-1.0, -0.35, ROOF_Z + 0.42))
    Y.box(V((-1.0, -0.45, ROOF_Z + 0.05)), (1.6, 0.6, 0.1), "hull2", bevel=0.0)
    an0 = tilt.to_3x3() @ V((0, 1, 0))
    for k in range(5):   # cooling fins on the back of the array
        Y.box(ac - an0 * 0.16 + V((-0.5 + k * 0.25, 0, 0)), (0.04, 0.14, 0.7), "metal", r=tilt,
              bevel=0.0)
    pipe(Y, ac - an0 * 0.12 + V((0.55, 0, -0.3)), V((-0.3, -0.85, ROOF_Z + 0.03)), 0.05, "dark")
    Y.box(ac, (1.4, 0.2, 0.9), "gunmetal", r=tilt, bevel=0.03)
    an = tilt.to_3x3() @ V((0, 1, 0))
    au = tilt.to_3x3() @ UP
    parts.quad(Y, ac + an * 0.105, an, au, 1.2, 0.72, "glass")
    for k in range(3):
        Y.box(ac + an * 0.11 - au * 0.39 + V((-0.35 + k * 0.35, 0, 0)), (0.06, 0.04, 0.06),
              "cyan", bevel=0.0)
    for sxx in (-1, 1):
        Y.box(ac + V((sxx * 0.74, 0, 0)), (0.08, 0.3, 0.95), "dark", r=tilt, bevel=0.0)
    rz = ROOF_Z
    Y.box(V((-1.0, -1.2, rz + 0.02)), (1.7, 0.5, 0.04), "dark", bevel=0.0)
    label("FIRE CTRL", V((-1.0, -1.2, rz + 0.04)), UP, up_for(V((0, -1, 0))), 0.16, INK_LIGHT)
    Y.box(V((-1.2, -2.05, rz + 0.03)), (0.8, 0.8, 0.06), "hull2", bevel=0.0)
    Y.cyl(V((-1.2, -2.05, rz + 0.31)), 0.32, 0.32, 0.5, "gunmetal", segs=12)
    Y.cyl(V((-1.2, -2.05, rz + 0.38)), 0.335, 0.335, 0.12, "glass", segs=12)
    Y.cyl(V((-1.2, -2.05, rz + 0.59)), 0.22, 0.26, 0.06, "dark", segs=12)
    # work floods on the rear chamfer: dark housing on a stalk, a small dim lens set back in
    # a bezel under a hood lip, facing down and back (never brighter than the status lamp)
    d = V((0, -1.0, -0.55)).normalized()
    rq = d.to_track_quat("-Y", "Z").to_matrix().to_4x4()
    r3q = rq.to_3x3()
    for sx in (-1, 1):
        surf = V((sx * 1.3, -3.0, ROOF_Z - 0.3))
        c = surf + nrm * 0.17
        strut(Y, surf - nrm * 0.03, c, 0.12, 0.12, "dark")
        Y.box(c, (0.42, 0.26, 0.24), "dark", r=rq, bevel=0.0)
        parts.quad(Y, c + d * 0.131, d, UP, 0.2, 0.08, "flood_low")
        for lx, lz, w, hh in ((0.0, 0.07, 0.34, 0.05), (0.0, -0.07, 0.34, 0.05),
                              (0.13, 0.0, 0.06, 0.19), (-0.13, 0.0, 0.06, 0.19)):
            Y.box(c + r3q @ V((lx, -0.15, lz)), (w, 0.04, hh), "dark", r=rq, bevel=0.0)
        Y.box(c + r3q @ V((0.0, -0.2, 0.12)), (0.44, 0.16, 0.03), "dark", r=rq, bevel=0.0)
    # status lamp collar
    Y.cyl(V((STATUS_O.x, STATUS_O.y, ROOF_Z + 0.08)), 0.36, 0.36, 0.16, "dark", segs=12)
    build_mantlet()


def build_mantlet():
    """Dark bellows mantlet closing the slot between the house front (y 0) and the gun pod.
    It is an arc of pleats round the pitch axis (r 1.42 .. 1.95), so the pod's rear corners
    (r 1.35) swing inside it at every elevation."""
    r_in, pl_hi, pl_lo, hx = 1.42, 1.95, 1.84, 1.9
    p0, p1, n = 152.0, 222.0, 14
    rings = []
    for k in range(n + 1):
        ph = math.radians(p0 + (p1 - p0) * k / n)
        dvec = V((0, math.cos(ph), math.sin(ph)))
        ro = pl_hi if k % 2 == 0 else pl_lo
        c = V((0, PITCH_Y, PITCH_Z))
        rings.append([V((-hx, 0, 0)) + c + dvec * r_in, V((hx, 0, 0)) + c + dvec * r_in,
                      V((hx, 0, 0)) + c + dvec * ro, V((-hx, 0, 0)) + c + dvec * ro])
    Y.loft(rings, "dark", cap=True)

def build_status():
    S.cyl(V((STATUS_O.x, STATUS_O.y, STATUS_O.z)), 0.25, 0.2, 0.25, "status", segs=12)


# ---------------------------------------------------------------- pitch
RCV_R = 0.84        # receiver radius
RCV_Z = PITCH_Z + 0.17   # receiver axis sits high: its belly clears the turntable at -25
SHROUD_R = 0.69     # shroud ring radius (zmax keeps 0.75 for it)
JACKET_R = 0.6      # dark cooling jacket over the barrel cluster


def build_pitch():
    """Gun pod: receiver block between the cheeks, boresight camera, two six-barrel rotary
    guns: fat receivers (r 0.84), a full-length dark cooling jacket (y 5.3 .. 9.8) over the
    barrel cluster with shroud rings (r 0.69), slotted muzzle brakes."""
    P.cyl(V((0, PITCH_Y, PITCH_Z)), 0.5, 0.5, 3.76, "gunmetal", segs=12, axis_rot=ALONG_X)
    P.box(V((0, 2.6, 18.0)), (3.2, 3.2, 1.8), "hull2", bevel=0.12)
    P.box(V((0, 2.8, 18.96)), (2.8, 2.4, 0.12), "slate", bevel=0.0)
    for sx in (-1, 1):
        P.box(V((sx * 1.64, 2.6, 18.0)), (0.08, 2.2, 1.25), "hull", bevel=0.0)
        bolt_row(P, V((sx * 1.67, 1.6, 18.72)), V((sx * 1.67, 3.6, 18.72)), 6, 0.06)
        P.box(V((sx * 1.62, 3.95, 18.0)), (0.04, 0.45, 0.3), "dark", bevel=0.0)
    hazard_band(P, V((-1.6, 4.22, 17.25)), V((1.6, 4.22, 17.25)), 0.04, 0.14, pitch=0.5)
    # boresight camera
    P.box(V((0, 2.7, 19.19)), (0.6, 0.8, 0.35), "dark", bevel=0.06)
    parts.quad(P, V((0, 3.11, 19.19)), V((0, 1, 0)), UP, 0.36, 0.2, "glass")
    for sx in (-1, 1):
        x = sx * GUN_X
        P.cyl(V((x, 4.7, RCV_Z)), RCV_R, RCV_R, 1.0, "gunmetal", segs=20, axis_rot=ALONG_Y)
        P.cyl(V((x, 4.25, RCV_Z)), RCV_R + 0.02, RCV_R + 0.02, 0.1, "dark", segs=20,
              axis_rot=ALONG_Y)
        P.cyl(V((x, 5.25, (RCV_Z + PITCH_Z) / 2)), 0.68, RCV_R - 0.06, 0.12, "dark", segs=20,
              axis_rot=ALONG_Y)
        for k in range(4):          # receiver bolts round the front flange
            a = k * math.pi / 2 + math.pi / 4
            P.box(V((x + 0.78 * math.cos(a), 5.16, RCV_Z + 0.78 * math.sin(a))),
                  (0.08, 0.08, 0.08), "metal", bevel=0.0)
        P.box(V((sx * 1.72, 4.7, RCV_Z)), (0.18, 0.6, 0.3), "dark", bevel=0.05)
        # flat cover plate on the receiver top carrying the gun number, facing up
        zt = RCV_Z + math.sqrt(RCV_R ** 2 - 0.36 ** 2)
        P.box(V((x, 4.7, zt + 0.03)), (0.72, 0.84, 0.14), "hull2", bevel=0.03)
        label("PDC 1" if sx < 0 else "PDC 2", V((x, 4.7, zt + 0.105)), UP,
              up_for(V((0, 1, 0))), 0.26, INK_DARK, 0.9, depth=0.3)
        hose = [V((sx * 1.0, 3.4, 18.95)), V((sx * 1.0, 4.0, 18.85)),
                V((x + sx * 0.1, 4.45, 18.7))]
        for a, b in zip(hose, hose[1:]):
            pipe(P, a, b, 0.06, "metal", segs=5)
        for k in range(6):
            a = k * math.pi / 3 + math.pi / 6
            bx, bz = x + 0.37 * math.cos(a), PITCH_Z + 0.37 * math.sin(a)
            P.cyl(V((bx, 7.85, bz)), 0.115, 0.115, 4.9, "metal", segs=6, axis_rot=ALONG_Y)
        P.cyl(V((x, 7.85, PITCH_Z)), 0.17, 0.17, 4.9, "dark", segs=6, axis_rot=ALONG_Y)
        P.cyl(V((x, 7.55, PITCH_Z)), JACKET_R, JACKET_R, 4.5, "dark", segs=16, axis_rot=ALONG_Y)
        for y in (5.45, 6.9, 8.35, 9.7):
            P.cyl(V((x, y, PITCH_Z)), SHROUD_R, SHROUD_R, 0.2, "gunmetal", segs=16,
                  axis_rot=ALONG_Y)
        P.box(V((x, 7.6, PITCH_Z + JACKET_R + 0.05)), (0.06, 4.1, 0.12), "gunmetal", bevel=0.0)
        # muzzle: collar, then a slotted brake out to the tip
        P.cyl(V((x, 10.12, PITCH_Z)), 0.66, 0.66, 0.16, "dark", segs=16, axis_rot=ALONG_Y)
        P.cyl(V((x, 10.55, PITCH_Z)), 0.58, 0.58, 0.72, "gunmetal", segs=16, axis_rot=ALONG_Y)
        for k in range(4):
            a = k * math.pi / 2 + math.pi / 4
            for yy in (10.4, 10.68):
                c = V((x + 0.57 * math.cos(a), yy, PITCH_Z + 0.57 * math.sin(a)))
                P.box(c, (0.07, 0.18, 0.12), "dark", r=Matrix.Rotation(-a, 4, "Y"), bevel=0.0)
        P.cyl(V((x, 10.93, PITCH_Z)), 0.6, 0.6, 0.04, "dark", segs=16, axis_rot=ALONG_Y)
        P.cyl(V((x, 10.935, PITCH_Z)), 0.3, 0.3, 0.035, "glass", segs=12, axis_rot=ALONG_Y)
        SCORCH.append((x, 10.6, PITCH_Z, 0.9))


# ---------------------------------------------------------------- assembly
def build():
    global B, Y, P, S
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    B = parts.PanelPart("turret_base", MATS)
    Y = parts.PanelPart("turret_yaw", MATS)
    P = parts.PanelPart("turret_pitch", MATS)
    S = parts.PanelPart("turret_status_light", MATS)
    for f in (build_keel, build_drum, build_wings, build_shoulder, build_barbette, build_service,
              build_yaw, build_status, build_pitch):
        f()
    root = parts.make_root(PRE, size=6)
    objs = [p.finish(root) for p in (B, Y, P, S)]
    objs[3].data.uv_layers.remove(objs[3].data.uv_layers["panel"])
    return root, objs


def reorigin(obj, parent, world_origin, parent_world):
    o = V(world_origin)
    obj.data.transform(Matrix.Translation(-o))
    obj.parent = parent
    obj.location = o - V(parent_world)


def rig(root, objs):
    base, yaw, pitch, light = objs
    yaw_o = V((0, 0, YAW_Z))
    pitch_o = V((0, PITCH_Y, PITCH_Z))
    reorigin(yaw, root, yaw_o, (0, 0, 0))
    reorigin(pitch, yaw, pitch_o, yaw_o)
    reorigin(light, yaw, STATUS_O, yaw_o)
    for name, sx in (("muzzle_l", -1), ("muzzle_r", 1)):
        parts.add_empty(name, pitch, V((sx * GUN_X, MUZZLE_Y, PITCH_Z)) - pitch_o, size=1.0)
    parts.add_empty("link_point", base, LINK, size=3)


# ---------------------------------------------------------------- checks
def mesh_bm(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.transform(obj.matrix_world)
    return bm


def bvh_of(bm, m=Matrix()):
    c = bm.copy()
    c.transform(m)
    t = BVHTree.FromBMesh(c)
    c.free()
    return t


def pitch_m(psi, theta):
    po = V((0, PITCH_Y, PITCH_Z))
    return (Matrix.Rotation(psi, 4, "Z") @ Matrix.Translation(po)
            @ Matrix.Rotation(theta, 4, "X") @ Matrix.Translation(-po))


def check(objs):
    """Clearance sweep: pitch -25..70 (2.5 deg) and yaw 0..355 (5 deg) against the yaw house and the base,
    footprint radius, and the base under the -25 deg barrel cone."""
    base, yaw, pitch, light = objs
    bpy.context.view_layer.update()
    bb, bp = mesh_bm(base), mesh_bm(pitch)
    yaw_s = bmesh.new()      # meshes still sit at the world origin here
    yaw_s.from_mesh(yaw.data)
    yaw_s.from_mesh(light.data)
    bad = 0
    t_base = bvh_of(bb)
    thetas = [math.radians(-25.0 + 2.5 * k) for k in range(39)]     # -25 .. 70 by 2.5
    psis = [math.radians(5.0 * k) for k in range(72)]                # 0 .. 355 by 5
    t_ys = bvh_of(yaw_s)
    for th in thetas:
        hits = t_ys.overlap(bvh_of(bp, pitch_m(0.0, th)))
        if hits:
            bad += 1
            print(f"CHECK pitch {math.degrees(th):.1f} vs yaw/status: {len(hits)} tri pairs")
            yaw_s.faces.ensure_lookup_table()
            bp.faces.ensure_lookup_table()
            m = pitch_m(0.0, th)
            for ia, ib in hits[:3]:
                ca = yaw_s.faces[ia].calc_center_median()
                cb = m @ bp.faces[ib].calc_center_median()
                print(f"CHECK   yaw face at {tuple(round(v, 2) for v in ca)}, pitch face at "
                      f"{tuple(round(v, 2) for v in cb)}")
    for ps in psis:
        hits = t_base.overlap(bvh_of(yaw_s, Matrix.Rotation(ps, 4, "Z")))
        if hits:
            bad += 1
            print(f"CHECK yaw {math.degrees(ps):.0f} vs base: {len(hits)} tri pairs")
    for ps in psis:
        for th in thetas:
            hits = t_base.overlap(bvh_of(bp, pitch_m(ps, th)))
            if hits:
                bad += 1
                print(f"CHECK yaw {math.degrees(ps):.0f} pitch {math.degrees(th):.0f} "
                      f"vs base: {len(hits)} tri pairs")
                if bad > 40:
                    print("CHECK too many problems, stopping")
                    return bad
    # footprint
    r_base = max(v.co.xy.length for v in bb.verts)
    r_yaw = max(v.co.xy.length for v in yaw_s.verts)
    r_pitch = 0.0
    for th in thetas:
        m = pitch_m(0.0, th)
        r_pitch = max(r_pitch, max((m @ v.co).xy.length for v in bp.verts))
    print(f"CHECK footprint base {r_base:.2f} yaw {r_yaw:.2f} pitch {r_pitch:.2f} "
          f"(max {FOOTPRINT_MAX})")
    if max(r_base, r_yaw, r_pitch) > FOOTPRINT_MAX:
        bad += 1
        print("CHECK footprint exceeded")
    # base under the barrel cone
    margin = 1e9
    worst = None
    for v in bb.verts:
        r = v.co.xy.length
        if r > TT_R:
            mg = zmax(r) - v.co.z
            if mg < margin:
                margin, worst = mg, v.co.copy()
    print(f"CHECK cone min margin {margin:.2f} at r {worst.xy.length:.2f} z {worst.z:.2f}")
    if margin < 0:
        bad += 1
    # +Y side: tallest base point on the service side outside the drum top
    ys = [v.co.z for v in bb.verts if v.co.y > 7.2 and abs(v.co.x) < 3.0]
    print(f"CHECK service side max z {max(ys):.2f} (barbette top {BARB_TOP})")
    for b in (bb, bp, yaw_s):
        b.free()
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


def previews(objs, compare=True):
    base, yaw, pitch, light = objs
    tgt = V((0, 0, 12))
    common.setup_preview(cam_loc=tgt + V((-45, -75, 80)), cam_target=tgt, ortho_scale=30,
                         res=(1600, 1200), key_dir=(-0.6, -0.35, 0.7), key_energy=3.5)
    dim_emission()
    scene = bpy.context.scene
    cam = scene.camera
    key = bpy.data.objects["key"]
    key_rot = key.rotation_euler.copy()
    shots = []

    def shot(tag):
        p = os.path.join(common.PREVIEW_DIR, f"{PRE}{tag}.png")
        common.render(p)
        shots.append(p)

    shot("_preview")
    cam.location = (0, 0, 200)
    cam.rotation_euler = (0, 0, 0)
    cam.data.ortho_scale = 26
    scene.render.resolution_x, scene.render.resolution_y = 1200, 1200
    shot("_top")
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1200
    cam.data.ortho_scale = 30
    for tag, yz, px, loc, t in (("_posed", 45, 20, (40.0, -30.0, 30.0), (0, 1, 14)),
                                ("_posed_low", 0, -25, (38.0, -12.0, 24.0), (0, 2, 13)),
                                ("_posed_high", 90, 70, (36.0, -34.0, 22.0), (0, 0, 15))):
        yaw.rotation_euler = (0, 0, math.radians(yz))
        pitch.rotation_euler = (math.radians(px), 0, 0)
        aim(cam, loc, t)
        key.rotation_euler = (-(V(loc) - V(t)).normalized() - V((0, 0, 0.6))).to_track_quat(
            "-Z", "Y").to_euler()
        shot(tag)
    yaw.rotation_euler = (0, 0, 0)
    pitch.rotation_euler = (0, 0, 0)
    key.rotation_euler = key_rot
    cam.data.ortho_scale = 12
    aim(cam, (-20.0, -30.0, 32.0), (0.0, -0.5, 17.8))
    shot("_closeup")
    if compare and os.path.exists(STATION_GLB):
        r, new = import_glb(STATION_GLB, (0.0, 0.0, 0.0))
        bpy.context.view_layer.update()
        xs = [(o.matrix_world @ V(c)).x for o in new if o.type == "MESH" for c in o.bound_box]
        r.location = (-max(xs) - 14.0, 0.0, 0.0)
        for mm in {s.material for o in new if o.type == "MESH" for s in o.material_slots}:
            if mm and mm.node_tree:
                bb = next((n for n in mm.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
                if bb:
                    bb.inputs["Emission Strength"].default_value *= 0.35
        cam.data.ortho_scale = 80
        scene.render.resolution_x, scene.render.resolution_y = 2000, 1200
        aim(cam, (-60.0, -75.0, 75.0), (-22.0, 0.0, 6.0))
        shot("_compare")
    print("PREVIEWS " + " ".join(shots))


def main():
    argv = parts.script_args(sys.argv)
    res = 4096
    for a in argv:
        if a.startswith("--res="):
            res = int(a.split("=")[1])
    common.reset_scene()
    root, objs = build()
    if "--check" in argv:
        check(objs)
        return
    tex = objs[:3]
    if "--no-textures" not in argv:
        # bake while every mesh still sits at the world origin
        # far AO at turret scale (the kit's 4 m is station scale and blots small parts)
        wk.texture(tex, MATS, PRE, NO_PADS, scorch=SCORCH, decals=DECALS, labels=LABELS,
                   seed0=71, res=res, ao_far=1.5, edge_r=0.08)
    else:
        for o in tex:
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    rig(root, objs)
    bpy.context.view_layer.update()
    wk.stats(objs)
    r_max = max((o.matrix_world @ v.co).xy.length for o in objs for v in o.data.vertices)
    print(f"STAT max horizontal extent {r_max:.2f} m (limit {FOOTPRINT_MAX})")
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        previews(objs, "--no-compare" not in argv)


main()
