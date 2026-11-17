"""Generate the cargo shuttle .glb and previews (3/4, top-down, and a scale shot next to the miner).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_cargo_shuttle.py
  Add `-- --no-preview` to skip the PNG renders.
  Add `-- --no-textures` to skip the atlas bake (flat colours, fast iteration).
  Add `-- --extra=<dir>` for debug close-ups (RTS angle, bow, stern, side, front, belly,
  the empty cradle and the supply-run look).
  Add `-- --scale-png /abs/out.png` to also render a tilted top-down shot beside the miner.

Design: short-haul Belter cargo lighter / container tug of the station fleet, built along
the thrust axis, every section with a job, front to back:
  crew can  small armoured chamfered pressure can: three slit viewports in a dark armour
            band under a brow (no picture windows), side slit ports, port airlock with a
            handhold, rungs, nose docking collar, chin bar with two floodlights, antenna
            cluster and dish, flush radiators on the upper chamfers, RCS quads on the four
            corners, two work floodlights on the aft bulkhead looking back over the cargo.
  spine     an open box truss (the thrust path) with the feed and power lines inside and a
            service tray on top (conduit, pressure bottles, vent, junction boxes); under
            it the belly cargo coupling that mates with a pad or a berth arm (no landing
            legs) and two belly floodlights.
  cradle    three ribs under the container bed with a latch post at each tip (yellow jaw,
            ram; docking clamp shoes under the front and rear tips), a clamp arm over each
            rib with jaws on the containers' top rails, diagonal bracing under the bed.
            Empty it reads as a spine with ribs, no cage round the cargo.
  stern     a thrust frame the cradle butts against, two mismatched propellant tanks
            (white with the teal band, a dark replacement) in strap saddles, manifold core
            and helium bottles between them, thrust struts, a reactor / thrust block with
            flush radiators, RCS quads and a hazard collar, two big gimballed bells with
            stiffener rings and actuators (bell radius 0.78 m, was 0.55).
The cargo is four mismatched units clamped two a side, in worn desaturated paint: an oxide
red corrugated box with a blue welded patch, a dull green hard-shell pod in girdle frames,
a white tank container in an open frame and a slate blue corrugated box. Each has a pale ID
panel with its number on the roof (readable from the RTS camera), stencils on the sides,
hazard sills, lashing straps.
Paint: worn station white / grey with the teal identity band (hull ring on the can, tank
band, roof panel on the thrust block), hull number CS-07 / 07, stencils, hazard trim.

Surfaces: worn atlas (station_textures / worn_kit bake, one 2048 atlas named
cargo_shuttle_*, exported material "cargo_shuttle_hull") for everything opaque, so hulls
get plates, seams, rivets, hatches, grime and chipping. The ship-scale panel sizes and the
shuttle colours are process-local entries in station_textures.WORN_KINDS (the shared file
is untouched): teal, yellow and temper (the bells) are new keys, and hull3 / pad / mli are
re-toned as the three container paints because only those keys take stencils. Slit panes,
lights and the engine glow stay flat emissive ("cargo_shuttle_window_warm", "_window_amber",
"_glass_dark", "_light_amber / _red / _green / _white", "_engine_glow").
JPEG_QUALITY re-saves the baked maps lower if the .glb ever grows past its budget.

Layout (Blender Z up, exported +Y up). Ship centre near the origin on the play plane z=0.
The nose points along Blender +Y, which the exporter turns into Godot -Z (forward), same as
miner/salvager. About 9.1 m long (collar y 4.6 .. bell exits y -4.5; the glow reaches
-5.35), 5.2 m wide over the latch rams, z -1.25 (clamp shoes) .. 0.95 (can roof), antenna
whip to 1.9. Crew can y 2.6..4.4, spine and cradle y -1.62..2.7 (containers y -1.48..2.53,
z -0.78..0.78), thrust frame y -1.62, tanks y -2.64..-1.7, thrust block y -3.42..-2.56,
bells to NOZZLE_Y.
Hierarchy: cargo_shuttle (empty root) -> cargo_shuttle_hull, cargo_containers, engine_glow.
cargo_containers is its own node so Godot can hide it when the shuttle flies empty; its
origin sits at the middle of the container bed, on the bed (z BED_Z), so the supply-run
scale squashes the load down onto the cradle. engine_glow holds both glows; its origin is
on the bell exit plane (Blender y = NOZZLE_Y) and plumes extend along Godot local +Z, so
scaling it on Z lengthens both glows backwards.
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
from parts import ALONG_X, ALONG_Y  # noqa: E402

V = Vector
PRE = "cargo_shuttle"
OUT = os.path.join(common.ROOT, "assets", "models", "ships", "cargo_shuttle.glb")
BLEND = os.path.join(common.ROOT, "blender", "cargo_shuttle.blend")

NOZZLE_Y = -4.5
BELL_R = 0.78
BELL_LEN = 1.08
BELL_X = 0.86
SPINE_Y0, SPINE_Y1 = -1.62, 2.7
SPINE_HW, SPINE_HH, SPINE_Z = 0.4, 0.38, -0.1
SPINE_TOP = SPINE_Z + SPINE_HH
CONT = (1.7, 1.95, 1.55)          # w (x), len (y), h (z)
CONT_X = 1.5
CONT_Y = (1.55, -0.5)             # front, rear container centres
CONT_Z = 0.0
RIB_Y = (2.3, 0.525, -1.25)       # cradle ribs: under the front end, joint, rear end
RIB_X = 2.42                      # rib tip / clamp post centre line
BED_Z = CONT_Z - CONT[2] / 2      # container floor
THRUST_Y = -1.62                  # thrust frame the cradle butts against
TANK_X, TANK_R = 1.1, 0.62
TANK_Y0, TANK_Y1 = -2.64, -1.7
CARGO_ORIGIN = V((0.0, (CONT_Y[0] + CONT_Y[1]) / 2, BED_Z))
C_RED, C_BLUE, C_GREEN = "hull3", "pad", "mli"   # container paints (kinds that take stencils)

MATS = {}
DECALS = []
SCORCH = []
LABELS = ["CS-07", "07", "#CHEV", "#BAR", "NO STEP", "CARGO", "HAUL 4", "KEEP CLEAR", "H2",
          "TK-4471", "BX-2096", "MX-3350", "LOCK", "CLAMP", "22T", "ORE"]
INK = (0.04, 0.04, 0.045)
INK_PALE = (0.56, 0.56, 0.52)


# ---------------------------------------------------------------- materials
def _tones(c):
    k = ((1.0, 1.0, 1.0), (0.93, 0.935, 0.94), (1.06, 1.05, 1.04), (0.88, 0.89, 0.9),
         (0.99, 0.965, 0.93), (0.92, 0.94, 0.965))
    return [tuple(min(1.0, a * b) for a, b in zip(c, m)) for m in k]


def _kind(base, colour=None, **over):
    d = dict(st.WORN_KINDS[base])
    if colour is not None:
        d["tones"] = _tones(colour)
    d.update(over)
    return d


COLOURS = dict(hull=(0.52, 0.525, 0.51), hull2=(0.17, 0.175, 0.185), dark=(0.05, 0.052, 0.056),
               metal=(0.3, 0.3, 0.31), hazard=(0.5, 0.34, 0.045), radiator=(0.38, 0.385, 0.39),
               teal=(0.035, 0.25, 0.26), temper=(0.19, 0.165, 0.18), yellow=(0.5, 0.34, 0.04), hull3=(0.31, 0.105, 0.06),
               pad=(0.085, 0.15, 0.25), mli=(0.13, 0.21, 0.13))


def register_kinds():
    """Ship-scale worn kinds for this process only (station_textures.py is not edited).
    hull3 / pad / mli are re-used as the container paints: those keys take stencils."""
    W = st.WORN_KINDS
    hull0, hull2_0, dark0, metal0, haz0, rad0, acc0 = (
        dict(W[k]) for k in ("hull", "hull2", "dark", "metal", "hazard", "radiator", "accent"))
    C = COLOURS
    W["hull"] = dict(hull0, tones=_tones(C["hull"]), big=(1.4, 1.0), plate=(0.7, 0.5),
                     plate_var=0.07, hatches=0.12, seam_big=0.45, seam_small=0.17,
                     streak_k=0.42, grime_k=1.15, chip_k=1.15)
    W["hull2"] = dict(hull2_0, tones=_tones(C["hull2"]), big=(1.2, 1.0), plate=(0.6, 0.5),
                      plate_var=0.08, hatches=0.1, seam_big=0.45, seam_small=0.18)
    W["dark"] = dict(dark0, tones=_tones(C["dark"]), big=(1.0, 1.0), plate=(0.5, 0.5))
    W["metal"] = dict(metal0, big=(1.0, 0.5), plate=(0.5, 0.5))
    W["hazard"] = dict(haz0, tones=_tones(C["hazard"]), big=(1.2, 1.2), plate=(0.6, 0.6),
                       stripes=0.26, bleach=0.2)
    W["radiator"] = dict(rad0, tones=_tones(C["radiator"]), big=(1.6, 0.4), plate=(1.6, 0.2))
    W["teal"] = dict(acc0, tones=_tones(C["teal"]), big=(1.4, 1.0), plate=(0.7, 0.5),
                     chip_k=1.5, bleach=0.3, grime_k=1.1)
    W["yellow"] = dict(acc0, tones=_tones(C["yellow"]), big=(1.0, 0.6), plate=(0.5, 0.3),
                       chip_k=1.5, bleach=0.2, grime_k=1.2)
    W["temper"] = dict(metal0, big=(0.6, 0.5), plate=(0.3, 0.5), plate_var=0.15,
                       tones=[(0.20, 0.15, 0.22), (0.25, 0.17, 0.10), (0.13, 0.15, 0.24),
                              (0.28, 0.21, 0.13), (0.17, 0.13, 0.19), (0.21, 0.19, 0.21)],
                       rough=(0.34, 0.1), metal=0.92, seam_big=0.25, grime_k=0.6, streak_k=0.5)
    for key in (C_RED, C_BLUE):
        # fins: the radiator rib pattern doubles as corrugation on walls and roofs
        W[key] = dict(acc0, tones=_tones(C[key]), big=(2.0, 1.0), plate=(2.0, 0.11), fins=True,
                      plate_var=0.1, seam_small=0.05, chip_k=1.7, streak_k=0.6, grime_k=1.35,
                      bleach=0.4)
    W[C_GREEN] = dict(acc0, tones=_tones(C[C_GREEN]), big=(1.0, 0.8), plate=(0.5, 0.4),
                      plate_var=0.1, rivets=True, chip_k=1.7, streak_k=0.55, grime_k=1.3,
                      bleach=0.4)


def build_materials():
    m = common.make_material
    MATS.clear()
    for k, c in COLOURS.items():
        MATS[k] = m(f"{PRE}_{k}", c, roughness=0.55, metallic=0.5 if k in ("dark", "metal", "temper")
                    else 0.0)
    glow = (0.03, 0.028, 0.025)
    MATS["glass"] = m(f"{PRE}_glass_dark", (0.008, 0.011, 0.016), roughness=0.12)
    MATS["window"] = m(f"{PRE}_window_warm", glow, roughness=0.25,
                       emission=(1.0, 0.62, 0.3), emission_strength=1.5)
    MATS["window_dim"] = m(f"{PRE}_window_amber", glow, roughness=0.25,
                           emission=(1.0, 0.5, 0.18), emission_strength=1.2)
    MATS["light"] = m(f"{PRE}_light_amber", glow, roughness=0.3,
                      emission=(1.0, 0.5, 0.12), emission_strength=4.5)
    MATS["red"] = m(f"{PRE}_light_red", glow, roughness=0.3,
                    emission=(1.0, 0.06, 0.03), emission_strength=6.5)
    MATS["green"] = m(f"{PRE}_light_green", glow, roughness=0.3,
                      emission=(0.12, 1.0, 0.28), emission_strength=6.0)
    MATS["white"] = m(f"{PRE}_light_white", glow, roughness=0.3,
                      emission=(0.88, 0.94, 1.0), emission_strength=5.5)
    MATS["glow"] = m(f"{PRE}_engine_glow", (0.75, 0.92, 1.0), roughness=0.2,
                     emission=(0.6, 0.86, 1.0), emission_strength=5.0)
    for k in ("glass", "window", "window_dim", "light", "red", "green", "white", "glow"):
        MATS[k].use_backface_culling = False


# ---------------------------------------------------------------- shape helpers
def loft_secs(P, secs, mat_fn, cap_mat, x0=0.0, cap=True):
    """Loft chamfered sections (y, w, h, chamfer, z) along Y. Returns the point rings."""
    rings = [parts.oct_ring(y, w, h, c, x0=x0, z0=z) for y, w, h, c, z in secs]
    P.loft(rings, cap_mat, mat_fn=mat_fn, cap=cap)
    return rings


def oct_x(x, wy, h, c, y, z):
    """oct_ring turned to sit across X (w along Y, h along Z) at x."""
    hw, hh = wy / 2, h / 2
    pts = [(hw, -hh + c), (hw, hh - c), (hw - c, hh), (-hw + c, hh),
           (-hw, hh - c), (-hw, -hh + c), (-hw + c, -hh), (hw - c, -hh)]
    return [V((x, y + a, z + b)) for a, b in pts]


def xbeam(P, x0, x1, y, wy, h, c, z, mat):
    P.loft([oct_x(x0, wy, h, c, y, z), oct_x(x1, wy, h, c, y, z)], mat)


def face_pt(ra, rb, j, u, v):
    n = len(ra)
    a, b = ra[j], ra[(j + 1) % n]
    d, c = rb[j], rb[(j + 1) % n]
    return a.lerp(b, u).lerp(d.lerp(c, u), v)


def face_normal(ra, rb, j, centre):
    n = len(ra)
    a, b, d = ra[j], ra[(j + 1) % n], rb[j]
    nrm = (b - a).cross(d - a).normalized()
    mid = face_pt(ra, rb, j, 0.5, 0.5)
    if nrm.dot(mid - centre) < 0:
        nrm = -nrm
    return nrm


def plate(P, q, n, t, mat, lift=0.0):
    """Raised closed plate on a face: quad q (4 points), outward n, thickness t."""
    n = V(n).normalized()
    b = [P.bm.verts.new(V(p) + n * lift) for p in q]
    tp = [P.bm.verts.new(V(p) + n * (lift + t)) for p in q]
    idx = P.mi(mat)
    fs = [P.bm.faces.new(b), P.bm.faces.new(tp)]
    for i in range(4):
        k = (i + 1) % 4
        fs.append(P.bm.faces.new((b[i], b[k], tp[k], tp[i])))
    for f in fs:
        f.material_index = idx


def face_plate(P, rings, i, j, u0, u1, v0, v1, t, mat, centre, lift=0.0):
    ra, rb = rings[i], rings[i + 1]
    q = [face_pt(ra, rb, j, u, v) for u, v in ((u0, v0), (u1, v0), (u1, v1), (u0, v1))]
    plate(P, q, face_normal(ra, rb, j, centre), t, mat, lift)


def face_quad(P, rings, i, j, u0, u1, v0, v1, mat, centre, lift=0.03):
    ra, rb = rings[i], rings[i + 1]
    n = face_normal(ra, rb, j, centre)
    vs = [P.bm.verts.new(face_pt(ra, rb, j, u, v) + n * lift)
          for u, v in ((u0, v0), (u1, v0), (u1, v1), (u0, v1))]
    P.bm.faces.new(vs).material_index = P.mi(mat)


def face_rot(n, along):
    """4x4 rotation: X = along (made square to n), Z = n (outward)."""
    n = V(n).normalized()
    a = V(along)
    a = (a - n * a.dot(n)).normalized()
    return Matrix((a, n.cross(a), n)).transposed().to_4x4()


def vents(P, c, n, along, length, width, slats, mat_frame="dark", mat_slat="metal"):
    """Louvre: dark frame plate with raised slats across it."""
    n, along = V(n).normalized(), V(along).normalized()
    side = n.cross(along).normalized()
    c = V(c)
    q = [c + along * a * length / 2 + side * s * width / 2
         for a, s in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    plate(P, q, n, 0.02, mat_frame)
    r = Matrix((along, side, n)).transposed().to_4x4()
    for k in range(slats):
        t = -0.5 + (k + 0.5) / slats
        P.box(c + along * t * length * 0.9 + n * 0.03,
              (length / slats * 0.45, width * 0.86, 0.035), mat_slat, r=r, bevel=0.0)


def bulb(P, pos, s, mat):
    """Small lit marker block."""
    P.box(V(pos), (s, s, s * 0.6), mat, bevel=0.0)


def flood(P, c, n, up, w=0.24, h=0.16, mat="white", depth=0.14):
    """Work floodlight: dark hooded housing, lit lens on the face looking along n."""
    c, n = V(c), V(n).normalized()
    r = face_rot(n, V(up).cross(n))
    P.box(c - n * depth / 2, (w + 0.08, h + 0.08, depth), "dark", r=r, bevel=0.15)
    parts.quad(P, c + n * 0.012, n, up, w, h, mat)


def slit(P, c, n, w, h, lit="window", up=(0, 0, 1), along=(0, 1, 0)):
    """Armoured slit port: raised dark frame, glass, a thin lit pane."""
    c, n = V(c), V(n).normalized()
    P.box(c, (w + 0.12, h + 0.12, 0.05), "hull2", r=face_rot(n, along), bevel=0.2)
    parts.quad(P, c + n * 0.03, n, up, w, h, "glass")
    parts.quad(P, c + n * 0.034, n, up, w * 0.86, h * 0.5, lit)


def flush_radiator(P, c, n, along, length, height, ribs=4, t=0.05):
    """Flat radiator panel on a hull face (normal n), coolant ribs across `along`."""
    c, n = V(c), V(n).normalized()
    r = face_rot(n, along)
    a = r.to_3x3() @ V((1, 0, 0))
    u = r.to_3x3() @ V((0, 1, 0))
    P.box(c + n * t / 2, (length, height, t), "radiator", r=r, bevel=0.0)
    for k in range(ribs):
        s = -length / 2 + length * (k + 0.5) / ribs
        P.box(c + a * s + n * t, (0.04, height * 0.94, t * 0.9), "metal", r=r, bevel=0.0)
    for s in (-1, 1):
        P.box(c + u * s * (height / 2 + 0.02) + n * t * 0.6, (length + 0.08, 0.06, t * 1.6),
              "dark", r=r, bevel=0.0)


def rail(P, a, b, n, mat="yellow", t=0.03, off=0.08):
    """Handhold: a bar on two standoffs, `off` proud of the face with normal n."""
    a, b, n = V(a), V(b), V(n).normalized()
    parts.strut(P, a + n * off, b + n * off, t, t, mat, up=n)
    for q in (a, b):
        parts.strut(P, q, q + n * (off + t / 2), t, t, "metal", up=(b - a).normalized())


def label(text, centre, normal, up, h, colour=INK, opacity=0.85):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity))


def greebles(P, rng, c, size, n_items, mats=("hull2", "dark", "metal", "hull")):
    """Scatter small boxes on a flat top area centred at c (size x, y)."""
    for _ in range(n_items):
        w = rng.uniform(0.08, 0.24)
        ln = rng.uniform(0.1, 0.34)
        h = rng.uniform(0.04, 0.12)
        p = V(c) + V((rng.uniform(-0.5, 0.5) * (size[0] - w), rng.uniform(-0.5, 0.5) *
                      (size[1] - ln), h / 2))
        P.box(p, (w, ln, h), rng.choice(mats), bevel=0.0)


# ---------------------------------------------------------------- hull: crew can
CAN = [(2.6, 1.5, 1.2, 0.32, 0.0), (2.78, 2.3, 1.8, 0.5, 0.05), (3.85, 2.3, 1.8, 0.5, 0.05),
       (4.4, 1.8, 1.1, 0.36, -0.12)]
CAN_Z = 0.05
CAN_HW, CAN_TOP = 1.15, 0.95


def build_can(P, rng):
    """Armoured crew can: a blunt chamfered slab hull, slit viewports under a brow."""
    def mf(i, j):
        if i == 0:
            return "dark"
        if j in (5, 6, 7):
            return "hull2"
        if i == 2 and j in (1, 3):
            return "hull2"
        return "hull"
    rings = loft_secs(P, CAN, mf, "hull2")
    ctr = V((0, 3.4, CAN_Z))
    # station identity band, slightly proud (a hull ring)
    loft_secs(P, [(2.88, 2.36, 1.86, 0.52, CAN_Z), (3.14, 2.36, 1.86, 0.52, CAN_Z)],
              lambda i, j: "teal" if j not in (5, 6, 7) else "hull2", "teal", cap=False)
    loft_secs(P, [(3.8, 2.33, 1.83, 0.51, CAN_Z), (3.87, 2.33, 1.83, 0.51, CAN_Z)],
              lambda i, j: "dark", "dark", cap=False)
    # viewports: three slits in a dark armoured band on the front slope, mullions between
    face_plate(P, rings, 2, 2, 0.04, 0.96, 0.3, 0.8, 0.035, "hull2", ctr)
    for u0, u1 in ((0.09, 0.345), (0.385, 0.615), (0.655, 0.91)):
        face_quad(P, rings, 2, 2, u0, u1, 0.46, 0.65, "glass", ctr, lift=0.05)
        face_quad(P, rings, 2, 2, u0 + 0.02, u1 - 0.02, 0.525, 0.585, "window", ctr, lift=0.056)
    for u in (0.365, 0.635):
        face_plate(P, rings, 2, 2, u - 0.02, u + 0.02, 0.32, 0.78, 0.04, "hull2", ctr, lift=0.035)
    face_plate(P, rings, 2, 2, 0.1, 0.9, 0.84, 0.97, 0.03, "hazard", ctr)
    # brow over the slits, cheek blocks
    P.box(V((0, 3.99, CAN_TOP + 0.05)), (1.56, 0.42, 0.11), "hull", bevel=0.25)
    P.box(V((0, 4.19, CAN_TOP + 0.0)), (1.5, 0.04, 0.1), "dark", bevel=0.0)
    for sx in (-1, 1):
        P.box(V((sx * 0.74, 3.98, CAN_TOP - 0.06)), (0.12, 0.4, 0.2), "hull2", bevel=0.2)
    # side slit ports under the chamfer, forward
    for sx in (-1, 1):
        slit(P, V((sx * (CAN_HW + 0.02), 3.52, CAN_Z + 0.22)), (sx, 0, 0), 0.3, 0.07,
             lit="window_dim")
    # starboard flank: slab armour with the hull number, vent panel
    x = CAN_HW
    P.box(V((x + 0.03, 3.5, CAN_Z - 0.08)), (0.07, 0.56, 0.42), "hull", bevel=0.2)
    P.box(V((x + 0.03, 3.36, CAN_Z + 0.02)), (0.07, 0.38, 0.72), "hull", bevel=0.0)
    label("CS-07", V((x + 0.07, 3.44, CAN_Z - 0.12)), (1, 0, 0), (0, 0, 1), 0.2, INK, 0.92)
    for k in range(4):
        P.box(V((x + 0.03, 3.26 + k * 0.09, CAN_Z + 0.28)), (0.05, 0.045, 0.2), "dark",
              bevel=0.0)
    # port flank: airlock in a dark frame, handholds, lock lamp
    x = -CAN_HW
    P.box(V((x - 0.03, 3.42, CAN_Z - 0.02)), (0.1, 0.66, 0.84), "hull2", bevel=0.2)
    P.box(V((x - 0.07, 3.42, CAN_Z - 0.04)), (0.07, 0.46, 0.66), "hull", bevel=0.18)
    P.box(V((x - 0.1, 3.42, CAN_Z + 0.35)), (0.03, 0.5, 0.07), "hazard", bevel=0.0)
    parts.window(P, V((x - 0.075, 3.42, CAN_Z + 0.08)), (-1, 0, 0), (0, 0, 1), 0.14, 0.1,
                 "window_dim")
    rail(P, V((x - 0.04, 3.0, CAN_Z + 0.3)), V((x - 0.04, 3.0, CAN_Z - 0.3)), (-1, 0, 0))
    bulb(P, (x - 0.09, 3.42, CAN_Z + 0.46), 0.07, "light")
    label("LOCK", V((x - 0.11, 3.42, CAN_Z - 0.2)), (-1, 0, 0), (0, 0, 1), 0.1, INK, 0.8)
    # roof: number panel, hatch, handrails
    P.box(V((0.14, 3.48, CAN_TOP + 0.015)), (0.84, 0.5, 0.04), "hull", bevel=0.0)
    label("07", V((0.14, 3.48, CAN_TOP + 0.04)), (0, 0, 1), (0, 1, 0), 0.4, INK, 0.95)
    P.cyl(V((-0.33, 3.0, CAN_TOP + 0.05)), 0.24, 0.26, 0.07, "hull2", segs=10)
    P.cyl(V((-0.33, 3.0, CAN_TOP + 0.09)), 0.17, 0.17, 0.04, "metal", segs=10)
    for sx in (-1, 1):
        rail(P, V((sx * 0.58, 3.25, CAN_TOP)), V((sx * 0.58, 3.72, CAN_TOP)), (0, 0, 1), off=0.07)
    label("NO STEP", V((-0.36, 3.5, CAN_TOP)), (0, 0, 1), (0, 1, 0), 0.07, INK, 0.75)
    # antenna cluster on the aft roof: mast with strobe, whips, a small dish
    b = V((0.36, 2.98, CAN_TOP + 0.03))
    P.box(b + V((0, 0, 0.05)), (0.3, 0.26, 0.12), "dark", bevel=0.2)
    P.tube(b + V((0, 0, 0.1)), b + V((0, 0, 0.62)), 0.035, 0.025, "metal", segs=5)
    P.tube(b + V((0.1, 0.06, 0.1)), b + V((0.16, -0.05, 0.9)), 0.016, 0.008, "dark", segs=4)
    P.tube(b + V((-0.1, -0.05, 0.1)), b + V((-0.14, -0.12, 0.66)), 0.016, 0.008, "dark", segs=4)
    bulb(P, b + V((0, 0, 0.65)), 0.07, "red")
    parts.dish(P, V((0.02, 2.9, CAN_TOP + 0.26)), 0.2, (-0.2, -0.5, 0.8), "hull", "dark",
               depth=0.08, segs=10)
    P.tube(V((0.02, 2.9, CAN_TOP)), V((0.02, 2.9, CAN_TOP + 0.26)), 0.03, 0.03, "metal", segs=5)
    # flush radiators on the upper chamfers, RCS quads on the four corners
    for sx in (-1, 1):
        n = V((sx, 0, 1)).normalized()
        c = V((sx * (CAN_HW - 0.25), 3.46, CAN_TOP - 0.25))
        flush_radiator(P, c + n * 0.005, n, (0, 1, 0), 0.5, 0.52, ribs=4)
        for sz in (-1, 1):
            n = V((sx, 0, sz)).normalized()
            c = V((sx * (CAN_HW - 0.25), 3.01 if sz > 0 else 3.5,
                   CAN_Z + sz * 0.65)) + n * 0.1
            parts.rcs_quad(P, c, n, "hull2", "metal", s=0.2)
            SCORCH.append((c.x, c.y, c.z, 0.4))
        # running lights and coolant feed
        bulb(P, (sx * (CAN_HW + 0.03), 3.76, CAN_Z + 0.52), 0.08, "red" if sx < 0 else "green")
        parts.pipe(P, V((sx * (CAN_HW + 0.02), 2.84, CAN_Z + 0.52)),
                   V((sx * (CAN_HW + 0.02), 3.7, CAN_Z + 0.52)), 0.028, "metal", segs=5)
    for k in range(4):                # rungs up the starboard flank to the roof
        z = CAN_Z - 0.5 + k * 0.3
        rail(P, V((CAN_HW + 0.01, 2.93, z)), V((CAN_HW + 0.01, 3.09, z)), (1, 0, 0), mat="metal",
             off=0.06)
    for sx, y in ((-1, 3.66), (1, 3.62)):     # bolted armour plates on the forward chamfers
        n = V((sx, 0, 1)).normalized()
        P.box(V((sx * (CAN_HW - 0.25), y + 0.12, CAN_TOP - 0.25)) + n * 0.02, (0.2, 0.5, 0.04),
              "hull" if sx < 0 else "hull2", r=face_rot(n, (0, 1, 0)), bevel=0.0)
    # umbilicals from the aft bulkhead into the spine
    for x, z, r, mat in ((-0.5, 0.42, 0.04, "dark"), (0.52, 0.3, 0.05, "metal"),
                         (0.3, -0.5, 0.035, "yellow")):
        a, b = V((x, 2.74, z)), V((x * 0.5, 2.3, SPINE_Z + (0.3 if z > 0 else -0.3)))
        m = a.lerp(b, 0.5) + V((x * 0.3, 0, -0.08))
        parts.pipe(P, a, m, r, mat, segs=5)
        parts.pipe(P, m, b, r, mat, segs=5)
    # belly: equipment pallet, plates
    P.box(V((0.22, 3.3, CAN_Z - 0.94)), (0.66, 0.7, 0.12), "hull2", bevel=0.0)
    P.box(V((-0.36, 3.5, CAN_Z - 0.93)), (0.3, 0.46, 0.1), "dark", bevel=0.0)
    bulb(P, (0, 2.95, CAN_Z - 0.93), 0.1, "light")
    # nose: docking collar with a hatch, guide petals, floodlights, chin sensor
    ny, nz = 4.4, -0.12
    P.cyl(V((0, ny + 0.05, nz)), 0.4, 0.4, 0.12, "hull2", segs=12, axis_rot=ALONG_Y)
    P.cyl(V((0, ny + 0.13, nz)), 0.32, 0.3, 0.1, "metal", segs=12, axis_rot=ALONG_Y)
    P.cyl(V((0, ny + 0.185, nz)), 0.22, 0.22, 0.02, "dark", segs=12, axis_rot=ALONG_Y)
    P.torus(V((0, ny + 0.1, nz)), 0.41, 0.03, "hazard", segs=12, minor_segs=4, matrix=ALONG_Y)
    for k in range(3):
        a = math.pi / 2 + k * 2 * math.pi / 3
        d = V((math.cos(a), 0, math.sin(a)))
        P.box(V((0, ny + 0.17, nz)) + d * 0.31, (0.09, 0.14, 0.09), "dark",
              r=Matrix.Rotation(-a, 4, "Y"), bevel=0.0)
    # chin bar under the collar: two floodlights, a sensor head; kit either side of it
    P.box(V((0, 4.3, -0.74)), (0.9, 0.34, 0.16), "dark", bevel=0.2)
    for x in (-0.26, 0.2):
        flood(P, V((x, 4.5, -0.73)), (0, 1, -0.12), (0, 0, 1), 0.2, 0.1, depth=0.1)
    P.cyl(V((0.56, 4.4, -0.56)), 0.07, 0.07, 0.14, "metal", segs=6, axis_rot=ALONG_Y)
    P.box(V((-0.64, ny + 0.03, nz + 0.02)), (0.3, 0.07, 0.5), "hull2", bevel=0.0)
    for k in range(3):
        P.box(V((-0.64, ny + 0.07, nz - 0.14 + k * 0.16)), (0.22, 0.03, 0.05), "dark", bevel=0.0)
    P.box(V((0.66, ny + 0.03, nz - 0.06)), (0.28, 0.06, 0.3), "hull", bevel=0.0)
    rail(P, V((0.52, ny, nz + 0.3)), V((0.8, ny, nz + 0.3)), (0, 1, 0))
    P.tube(V((0.74, ny, nz + 0.16)), V((0.84, ny + 0.24, nz + 0.2)), 0.014, 0.008, "metal", segs=4)
    label("#CHEV", V((0.66, ny + 0.06, nz - 0.06)), (0, 1, 0), (0, 0, 1), 0.07, INK, 0.7)
    # aft bulkhead: work floodlights looking back over the cargo
    for sx in (-1, 1):
        flood(P, V((sx * 0.72, 2.76, CAN_TOP - 0.02)), (sx * 0.25, -1, -0.45), (0, 0, 1),
              0.24, 0.14)
    return rings


# ---------------------------------------------------------------- hull: spine + cradle
def build_spine(P, rng):
    """Spine truss, the thrust path from the drive block to the crew can. Feed and power
    lines run through it, service gear rides on top between the containers."""
    parts.box_truss(P, SPINE_Y0, SPINE_Y1, SPINE_HW, SPINE_HH, 5, "hull2", "dark", chord=0.15,
                    brace=0.08, z0=SPINE_Z)
    y0, y1 = SPINE_Y0, SPINE_Y1
    for x, z, r, mat in ((-0.16, -0.2, 0.075, "metal"), (0.14, -0.22, 0.055, "yellow"),
                         (0.02, 0.02, 0.09, "hull"), (-0.2, 0.08, 0.035, "teal")):
        parts.pipe(P, V((x, y0, SPINE_Z + z)), V((x, y1, SPINE_Z + z)), r, mat, segs=6)
    for y in (2.2, 1.35, 0.5, -0.36, -1.2):
        P.box(V((0, y, SPINE_Z - 0.08)), (0.56, 0.08, 0.44), "dark", bevel=0.0)
    # service tray on top: conduit, junction boxes, pressure bottles, a vent
    top = SPINE_TOP + 0.07
    P.box(V((0, 0.55, top + 0.02)), (0.72, 3.9, 0.04), "dark", bevel=0.0)
    P.box(V((0.2, 0.45, top + 0.09)), (0.14, 3.5, 0.1), "metal", bevel=0.0)
    parts.pipe(P, V((-0.24, -1.4, top + 0.09)), V((-0.24, 2.5, top + 0.09)), 0.045, "yellow",
               segs=5)
    for y in (1.75, 1.2):
        P.sphere(V((-0.06, y, top + 0.26)), 0.22, "metal", segs=10, rings=6)
        P.torus(V((-0.06, y, top + 0.26)), 0.225, 0.025, "dark", segs=10, minor_segs=3)
    P.box(V((-0.06, 1.475, top + 0.1)), (0.5, 0.9, 0.08), "hull2", bevel=0.0)
    P.box(V((-0.02, -0.38, top + 0.13)), (0.5, 0.62, 0.2), "hull", bevel=0.15)
    vents(P, V((-0.02, -0.38, top + 0.23)), (0, 0, 1), (0, 1, 0), 0.46, 0.34, 4)
    P.box(V((0.04, -1.02, top + 0.1)), (0.4, 0.3, 0.14), "hull2", bevel=0.0)
    greebles(P, rng, V((-0.1, 0.1, top + 0.04)), (0.5, 0.5), 3)
    label("NO STEP", V((-0.02, -0.38, top + 0.23)), (0, 0, 1), (1, 0, 0), 0.06, INK, 0.7)
    # belly cargo coupling under the spine (mates with a pad or a berth arm), marker lamps
    bz = SPINE_Z - SPINE_HH
    c = V((0, 1.42, bz - 0.2))
    P.box(c + V((0, 0, 0.14)), (0.98, 1.04, 0.14), "hull2", bevel=0.2)
    P.cyl(c, 0.42, 0.44, 0.3, "hull2", segs=12)
    P.cyl(c - V((0, 0, 0.17)), 0.34, 0.34, 0.06, "metal", segs=12)
    P.cyl(c - V((0, 0, 0.205)), 0.24, 0.24, 0.02, "dark", segs=12)
    P.torus(c - V((0, 0, 0.12)), 0.44, 0.035, "hazard", segs=12, minor_segs=4)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        P.box(c + V((math.cos(a) * 0.5, math.sin(a) * 0.5, -0.1)), (0.14, 0.14, 0.24), "dark",
              r=Matrix.Rotation(a, 4, "Z"), bevel=0.0)
    P.box(V((0, -0.4, bz - 0.1)), (0.6, 0.7, 0.12), "hull2", bevel=0.0)
    for y in (-0.4, 2.3):
        flood(P, V((0, y, bz - 0.17)), (0, 0, -1), (0, 1, 0), 0.2, 0.14, depth=0.08)
    bulb(P, (0, -1.3, bz - 0.06), 0.1, "light")


def build_cradle(P, rng):
    """Cargo cradle: three ribs under the bed with latch posts at their tips, a clamp arm
    over each rib. Empty it reads as a spine with ribs; no cage round the cargo."""
    rz = BED_Z - 0.13                 # rib centre (top is the container floor)
    bz = SPINE_Z - SPINE_HH
    for k, y in enumerate(RIB_Y):
        xbeam(P, -RIB_X - 0.04, RIB_X + 0.04, y, 0.3, 0.26, 0.07, rz, "hull2")
        for sx in (-1, 1):
            # hanger from the spine chord down to the rib, gusset
            P.box(V((sx * SPINE_HW, y, (bz + rz) / 2 + 0.04)), (0.2, 0.34, bz - rz + 0.3),
                  "dark", bevel=0.0)
            parts.strut(P, V((sx * 0.5, y, bz + 0.05)), V((sx * 0.62, y, rz + 0.1)), 0.1, 0.3,
                        "hull2", up=V((0, 1, 0)))
            # hazard tread on the rib where the container corners land
            P.box(V((sx * 1.5, y, BED_Z + 0.004)), (1.5, 0.14, 0.02), "hazard", bevel=0.0)
            # latch post at the rib tip: jaw on the container's lower rail, ram, lamp
            x = sx * RIB_X
            P.box(V((x + sx * 0.03, y, BED_Z + 0.02)), (0.2, 0.34, 0.56), "hull2", bevel=0.2)
            P.box(V((x - sx * 0.02, y, BED_Z + 0.24)), (0.18, 0.38, 0.16), "yellow", bevel=0.2)
            P.tube(V((x + sx * 0.15, y, BED_Z - 0.2)), V((x + sx * 0.08, y, BED_Z + 0.22)), 0.045,
                   0.03, "metal", segs=5)
            if k != 1:
                # docking clamp shoe under the tip (grips the pad / berth rails)
                P.box(V((x - sx * 0.06, y, rz - 0.21)), (0.4, 0.42, 0.18), "dark", bevel=0.2)
                P.box(V((x - sx * 0.06, y, rz - 0.31)), (0.3, 0.3, 0.04), "yellow", bevel=0.0)
            else:
                bulb(P, (x + sx * 0.12, y, BED_Z + 0.1), 0.09, "red" if sx < 0 else "green")
        # clamp arm over the rib: post on the spine, cross arm, jaws on the top rails
        az = CONT_Z + CONT[2] / 2 + 0.13
        P.box(V((0, y, (SPINE_TOP + az) / 2)), (0.22, 0.24, az - SPINE_TOP + 0.1), "hull2",
              bevel=0.0)
        xbeam(P, -1.0, 1.0, y, 0.24, 0.16, 0.05, az, "hull2")
        for sx in (-1, 1):
            P.box(V((sx * 0.86, y, az - 0.09)), (0.34, 0.34, 0.1), "yellow", bevel=0.0)
            P.tube(V((sx * 0.3, y, az + 0.1)), V((sx * 0.74, y, az + 0.1)), 0.04, 0.04, "metal",
                   segs=5)
        bulb(P, (0, y, az + 0.1), 0.08, "light")
    # diagonal bracing under the bed, rib tip to the next rib's root
    for sx in (-1, 1):
        for ya, yb in ((RIB_Y[0], RIB_Y[1]), (RIB_Y[2], RIB_Y[1])):
            parts.strut(P, V((sx * (RIB_X - 0.25), ya, rz)), V((sx * 0.5, yb, rz)), 0.09, 0.09,
                        "dark")
    label("CLAMP", V((RIB_X + 0.14, RIB_Y[0], BED_Z + 0.0)), (1, 0, 0), (0, 0, 1), 0.07,
          INK_PALE, 0.75)


# ---------------------------------------------------------------- hull: tanks + drive block
ENG = [(-2.56, 2.2, 1.2, 0.32, 0.0), (-2.72, 3.1, 1.6, 0.42, 0.0), (-3.26, 3.1, 1.6, 0.42, 0.0),
       (-3.42, 2.7, 1.3, 0.36, 0.0)]


def build_tanks(P, rng):
    """Thrust frame, two mismatched propellant tanks in strap saddles, the feed manifold
    and helium bottles between them."""
    y = THRUST_Y
    P.box(V((0, y, 0.0)), (3.5, 0.14, 1.5), "hull2", bevel=0.2)
    P.box(V((0, y + 0.075, 0.62)), (3.0, 0.02, 0.14), "hazard", bevel=0.0)
    for sx in (-1, 1):
        P.box(V((sx * 1.2, y + 0.075, -0.1)), (0.7, 0.03, 0.8), "hull", bevel=0.0)
        flood(P, V((sx * 1.5, y + 0.1, 0.8)), (-sx * 0.3, 1, -0.4), (0, 0, 1), 0.22, 0.14)
        bulb(P, (sx * 1.77, y, 0.0), 0.09, "red" if sx < 0 else "green")
    label("KEEP CLEAR", V((1.2, y + 0.09, 0.1)), (0, 1, 0), (0, 0, 1), 0.09, INK, 0.8)
    label("#CHEV", V((-1.2, y + 0.09, 0.1)), (0, 1, 0), (0, 0, 1), 0.12, INK, 0.7)
    for sx, body in ((-1, "hull"), (1, "hull2")):
        x = sx * TANK_X

        def tm(i, j, body=body, sx=sx):
            if j in (0, 6):
                return "metal"
            if sx < 0 and j == 3:
                return "teal"
            return body
        parts.capsule(P, TANK_Y0, TANK_Y1, TANK_R, tm, segs=14, x=x, z=0.0, dome0=0.7, dome1=0.7)
        ym = (TANK_Y0 + TANK_Y1) / 2
        P.torus(V((x, ym - 0.2, 0)), TANK_R + 0.01, 0.035, "dark", segs=14, minor_segs=4,
                matrix=ALONG_Y)
        P.box(V((x + sx * (TANK_R + 0.02), ym - 0.2, 0)), (0.08, 0.14, 0.2), "metal", bevel=0.0)
        # fill port and relief valve on top, feed line aft
        P.cyl(V((x, ym + 0.12, TANK_R + 0.02)), 0.11, 0.11, 0.08, "metal", segs=8)
        P.cyl(V((x, ym + 0.12, TANK_R + 0.08)), 0.075, 0.075, 0.05, "hazard", segs=8)
        parts.pipe(P, V((x - sx * 0.3, ym, TANK_R * 0.85)), V((sx * 0.3, ym, 0.7)), 0.04,
                   "metal", segs=5)
        SCORCH.append((x, ym + 0.12, TANK_R, 0.3))
    P.box(V((TANK_X + 0.12, -2.02, TANK_R * 0.93)), (0.4, 0.36, 0.04), "hull", bevel=0.0)
    label("H2", V((-TANK_X - TANK_R * 0.72, -2.15, TANK_R * 0.72)), (-1, 0, 1), (0, 1, 0), 0.16,
          INK, 0.85)
    for sx in (-1, 1):                # thrust struts from the frame to the drive block
        for sz in (-1, 1):
            parts.strut(P, V((sx * 1.56, THRUST_Y - 0.05, sz * 0.68)),
                        V((sx * 1.3, ENG[1][0] + 0.03, sz * 0.7)), 0.09, 0.09, "dark")
        parts.strut(P, V((sx * 1.72, THRUST_Y - 0.05, 0.0)), V((sx * 1.5, ENG[1][0] + 0.03, 0.0)),
                    0.08, 0.14, "hull2")
    # manifold core between the tanks, helium bottles on top
    loft_secs(P, [(TANK_Y1 + 0.05, 0.84, 1.2, 0.2, 0.0), (-2.6, 0.84, 1.2, 0.2, 0.0)],
              lambda i, j: "hull2", "hull2", cap=False)
    for yy in (-1.98, -2.4):
        c = V((0, yy, 0.76))
        P.sphere(c, 0.2, "metal", segs=10, rings=6)
        P.cyl(c + V((0, 0, 0.2)), 0.05, 0.05, 0.08, "yellow", segs=6)
    parts.pipe(P, V((0, -1.7, 0.63)), V((0, -2.7, 0.63)), 0.05, "yellow", segs=5)
    P.box(V((0, -2.19, 0.64)), (0.5, 0.1, 0.1), "dark", bevel=0.0)


def build_drive(P, rng):
    """Reactor / thrust block and the two main bells."""
    def mf(i, j):
        if i == 0:
            return "dark"
        if i == 2:
            return "dark"
        if j in (5, 6, 7):
            return "hull2"
        return "hull"
    loft_secs(P, ENG, mf, "hull2")
    loft_secs(P, [(-3.13, 3.15, 1.65, 0.44, 0.0), (-3.25, 3.15, 1.65, 0.44, 0.0)],
              lambda i, j: "hazard", "hazard", cap=False)
    top, hw, ym = 0.8, 1.55, -2.92
    for sx in (-1, 1):
        flush_radiator(P, V((sx * (hw + 0.003), ym, 0.0)), (sx, 0, 0), (0, 1, 0), 0.36, 0.66,
                       ribs=3)
        flush_radiator(P, V((sx * 0.72, ym, top + 0.003)), (0, 0, 1), (0, 1, 0), 0.36, 0.56,
                       ribs=3)
        for sz in (-1, 1):
            n = V((sx, 0, sz)).normalized()
            c = V((sx * (hw - 0.21), ym, sz * (top - 0.21))) + n * 0.09
            parts.rcs_quad(P, c, n, "hull2", "metal", s=0.21)
            SCORCH.append((c.x, c.y, c.z, 0.4))
    # roof: teal identity panel with the number, reactor hatch, strobe mast, whip
    P.box(V((-0.08, ym, top + 0.015)), (0.62, 0.38, 0.04), "teal", bevel=0.0)
    P.box(V((-0.08, ym + 0.02, top + 0.045)), (0.26, 0.2, 0.03), "hull2", bevel=0.0)
    P.cyl(V((0.24, -3.12, top + 0.12)), 0.05, 0.05, 0.26, "dark", segs=6)
    bulb(P, (0.24, -3.12, top + 0.27), 0.08, "white")
    P.tube(V((-0.3, -3.16, top)), V((-0.34, -3.3, top + 0.7)), 0.016, 0.008, "metal", segs=4)
    label("HAUL 4", V((0.72, -2.6, 0.72)), (0, 0.5, 1), (0, 1, 0), 0.07, INK, 0.75)
    label("HAUL 4", V((0, -2.95, -0.82)), (0, 0, -1), (1, 0, 0), 0.16, INK_PALE, 0.8)
    P.box(V((0.3, ym, -top - 0.03)), (0.8, 0.4, 0.1), "hull2", bevel=0.0)
    bulb(P, (-0.5, ym, -top - 0.03), 0.1, "light")
    # stern plate: gimbal mounts, bells with stiffener rings and actuators
    ry = ENG[-1][0]
    P.box(V((0, ry - 0.04, 0)), (0.36, 0.1, 1.0), "dark", bevel=0.0)
    parts.pipe(P, V((0, ry, 0.42)), V((0, ry - 0.5, 0.56)), 0.05, "metal", segs=5)
    parts.pipe(P, V((0, ry, -0.42)), V((0, ry - 0.5, -0.56)), 0.05, "metal", segs=5)
    for sz in (-1, 1):
        P.cyl(V((0, ry - 0.16, sz * 0.3)), 0.11, 0.11, 0.22, "metal", segs=8, axis_rot=ALONG_Y)
        P.box(V((0, ry - 0.1, sz * 0.62)), (0.3, 0.12, 0.16), "hull2", bevel=0.0)
    for sx in (-1, 1):
        x = sx * BELL_X
        P.cyl(V((x, ry - 0.05, 0)), 0.56, 0.5, 0.12, "hull2", segs=14, axis_rot=ALONG_Y)
        P.torus(V((x, ry - 0.1, 0)), 0.44, 0.05, "dark", segs=14, minor_segs=4, matrix=ALONG_Y)
        parts.bell(P, NOZZLE_Y, BELL_R, BELL_LEN, "temper", "dark", x=x, segs=16, throat=0.44)
        for t in (0.2, 0.55, 0.97):
            rr = BELL_R * (0.44 + 0.56 * t ** 0.65)
            yy = NOZZLE_Y + BELL_LEN * (1 - t)
            P.torus(V((x, yy, 0)), rr + 0.008, 0.028, "metal", segs=16, minor_segs=3,
                    matrix=ALONG_Y)
        for a in (math.radians(60), math.radians(180), math.radians(300)):
            d = V((math.cos(a) * sx, 0, math.sin(a)))
            p0 = V((x, ry - 0.04, 0)) + d * 0.6
            p1 = V((x, NOZZLE_Y + BELL_LEN * 0.6, 0)) + d * 0.52
            P.tube(p0, p1, 0.05, 0.03, "metal", segs=5)
            P.box(p0, (0.13, 0.1, 0.13), "dark", bevel=0.0)
        SCORCH.append((x, ry - 0.3, 0.0, 1.1))


# ---------------------------------------------------------------- containers
def frame(P, c, post=0.1, casting=0.15):
    """Container corner frame: side rails, end frames, corner castings."""
    w, ln, h = CONT
    for sz in (-1, 1):
        for sx in (-1, 1):
            P.box(c + V((sx * (w / 2 - post / 2), 0, sz * (h / 2 - post / 2))),
                  (post, ln - 0.1, post), "dark", bevel=0.0)
    for sy in (-1, 1):
        y = sy * (ln / 2 - post / 2)
        for sx in (-1, 1):
            P.box(c + V((sx * (w / 2 - post / 2), y, 0)), (post, post, h - 0.1), "dark",
                  bevel=0.0)
        for sz in (-1, 1):
            P.box(c + V((0, y, sz * (h / 2 - post / 2))), (w - 0.1, post, post), "dark",
                  bevel=0.0)
        for sx in (-1, 1):
            for sz in (-1, 1):
                P.box(c + V((sx * (w / 2 - 0.06), sy * (ln / 2 - 0.06), sz * (h / 2 - 0.06))),
                      (casting, casting, casting), "metal", bevel=0.0)


def corr_container(P, c, mat, ident, door_rear=True, patch=None):
    """Corrugated box container: ribbed walls and roof, door gear on one end, a pale ID
    panel and number on the roof, hazard sill, stencils on the sides."""
    w, ln, h = CONT
    c = V(c)
    out = 1 if c.x > 0 else -1
    s = -1 if door_rear else 1
    ry = c.y - s * 0.3
    P.box(c, (w - 0.06, ln - 0.06, h - 0.06), mat, bevel=0.03)
    # lashing strap over the roof and down both walls, ratchet on the outboard side
    for sx in (-1, 1):
        P.box(c + V((sx * (w / 2 + 0.012), s * 0.56, 0)), (0.02, 0.1, h - 0.1), "yellow",
              bevel=0.0)
    P.box(c + V((0, s * 0.56, h / 2 + 0.012)), (w, 0.1, 0.02), "yellow", bevel=0.0)
    P.box(c + V((out * (w / 2 + 0.04), s * 0.56, 0.3)), (0.07, 0.16, 0.2), "metal", bevel=0.0)
    # even rib counts: no rib over a face centre (the bake would count the wall as buried)
    n = 8
    for sx in (-1, 1):
        for k in range(n):
            y = -ln / 2 + 0.2 + (ln - 0.4) * k / (n - 1)
            P.box(c + V((sx * (w / 2 - 0.02), y, -0.02)), (0.04, 0.08, h - 0.34), mat, bevel=0.0)
    for k in range(6):
        y = -ln / 2 + 0.22 + (ln - 0.44) * k / 5
        if (ry - c.y) * (y - 0.0) > 0 and abs(y - (ry - c.y)) < 0.3:
            continue                  # the roof ID panel sits here
        P.box(c + V((0, y, h / 2 - 0.02)), (w - 0.3, 0.1, 0.04), mat, bevel=0.0)
    frame(P, c)
    # door end: two leaves, lock bars with cams, hazard sill
    ye = c.y + s * (ln / 2 + 0.01)
    for sx in (-1, 1):
        P.box(V((c.x + sx * w / 4, ye, c.z)), (w / 2 - 0.16, 0.03, h - 0.24), mat, bevel=0.0)
        for k in (0.3, 0.7):
            x = c.x + sx * w * k / 2 + sx * 0.06
            P.tube(V((x, ye + s * 0.03, c.z - h / 2 + 0.14)), V((x, ye + s * 0.03, c.z + h / 2 - 0.14)),
                   0.018, 0.018, "metal", segs=4)
            P.box(V((x, ye + s * 0.05, c.z - 0.1)), (0.06, 0.04, 0.16), "dark", bevel=0.0)
    P.box(V((c.x, ye + s * 0.02, c.z - h / 2 + 0.1)), (w - 0.24, 0.03, 0.1), "hazard", bevel=0.0)
    # roof: pale ID panel (off centre) with the number
    P.box(V((c.x, ry, c.z + h / 2 - 0.005)), (w - 0.7, 0.4, 0.03), "hull", bevel=0.0)
    label(ident, V((c.x, ry, c.z + h / 2 + 0.02)), (0, 0, 1), (0, 1, 0), 0.2, INK, 0.9)
    # sides: pale band, stencils, a placard
    for sx in (-1, 1):
        xf = c.x + sx * (w / 2 + 0.005)
        label(ident, V((xf, c.y + 0.3, c.z + 0.3)), (sx, 0, 0), (0, 0, 1), 0.17, INK_PALE, 0.85)
        label("22T", V((xf, c.y - 0.5, c.z - 0.3)), (sx, 0, 0), (0, 0, 1), 0.1, INK_PALE, 0.7)
        P.box(V((xf + sx * 0.008, c.y - 0.52, c.z + 0.24)), (0.02, 0.34, 0.22), "hull",
              bevel=0.0)
    if patch:                         # a welded plate in another paint (Belter repair)
        P.box(c + V((out * (w / 2 + 0.012), 0.42, -0.26)), (0.03, 0.5, 0.44), patch, bevel=0.0)
        P.box(c + V((-0.3, s * 0.5, h / 2 + 0.0)), (0.5, 0.36, 0.03), patch, bevel=0.0)


def pod_container(P, c, mat, ident):
    """Hard-shell freight pod: smooth chamfered case in three girdle frames, roof hatch,
    fork pockets, hazard corner trim."""
    w, ln, h = CONT
    c = V(c)
    P.box(c, (w - 0.1, ln - 0.08, h - 0.1), mat, bevel=0.07)
    for y in (-ln / 2 + 0.1, 0.0, ln / 2 - 0.1):
        for sx in (-1, 1):
            P.box(c + V((sx * (w / 2 - 0.04), y, 0)), (0.08, 0.16, h), "dark", bevel=0.0)
        for sz in (-1, 1):
            P.box(c + V((0, y, sz * (h / 2 - 0.04))), (w - 0.16, 0.16, 0.08), "dark", bevel=0.0)
    for sy in (-1, 1):
        for sx in (-1, 1):
            for sz in (-1, 1):
                P.box(c + V((sx * (w / 2 - 0.06), sy * (ln / 2 - 0.06), sz * (h / 2 - 0.06))),
                      (0.15, 0.15, 0.15), "metal", bevel=0.0)
            # hazard corner trim on the roof, between the frames
            P.box(c + V((sx * (w / 2 - 0.2), sy * 0.5, h / 2 - 0.04)), (0.1, 0.34, 0.02),
                  "hazard", bevel=0.0)
        P.box(c + V((0, sy * (ln / 2 - 0.03), -0.05)), (w - 0.5, 0.03, h - 0.5), "hull2",
              bevel=0.0)
    # roof hatch with dogs, pale ID panel
    P.box(c + V((0.0, 0.5, h / 2 - 0.035)), (0.7, 0.56, 0.04), "hull2", bevel=0.0)
    P.box(c + V((0.0, 0.5, h / 2 - 0.01)), (0.12, 0.34, 0.03), "metal", bevel=0.0)
    P.box(c + V((0.0, -0.5, h / 2 - 0.04)), (0.8, 0.36, 0.03), "hull", bevel=0.0)
    label(ident, c + V((0.0, -0.5, h / 2)), (0, 0, 1), (0, 1, 0), 0.18, INK, 0.9)
    for sx in (-1, 1):
        xf = c.x + sx * (w / 2 - 0.045)
        label(ident, V((xf, c.y + 0.48, c.z + 0.28)), (sx, 0, 0), (0, 0, 1), 0.15, INK_PALE, 0.85)
        label("CARGO", V((xf, c.y - 0.48, c.z - 0.3)), (sx, 0, 0), (0, 0, 1), 0.1, INK_PALE, 0.7)
        for y in (-0.48, 0.48):       # fork pockets
            P.box(V((xf + sx * 0.005, c.y + y, c.z - h / 2 + 0.16)), (0.03, 0.34, 0.1), "dark",
                  bevel=0.0)


def tank_container(P, c, ident):
    """Tank container: a pressure vessel in an open frame, walkway and manhole on top."""
    w, ln, h = CONT
    c = V(c)
    out = 1 if c.x > 0 else -1
    frame(P, c, post=0.12, casting=0.16)
    for sy in (-1, 1):
        y = sy * (ln / 2 - 0.06)
        P.beam(c + V((-w / 2 + 0.1, y, -h / 2 + 0.1)), c + V((w / 2 - 0.1, y, h / 2 - 0.1)), 0.07,
               0.07, "dark", up=V((0, 1, 0)))
    r = h / 2 - 0.13
    parts.capsule(P, c.y - ln / 2 + 0.1, c.y + ln / 2 - 0.1, r,
                  lambda i, j: "hazard" if j == 2 else "hull",
                  segs=14, x=c.x, z=c.z, dome0=0.35, dome1=0.35)
    for y in (-0.52, 0.52):   # saddle bands
        P.torus(c + V((0, y, 0)), r + 0.01, 0.03, "dark", segs=14, minor_segs=3, matrix=ALONG_Y)
        P.box(c + V((0, y, -h / 2 + 0.14)), (w - 0.3, 0.12, 0.2), "dark", bevel=0.0)
    P.box(c + V((0.16, 0, r + 0.02)), (0.3, ln - 0.5, 0.03), "metal", bevel=0.0)   # walkway
    P.cyl(c + V((-0.14, 0.3, r + 0.04)), 0.15, 0.15, 0.12, "hull2", segs=8)
    P.cyl(c + V((-0.14, -0.3, r + 0.03)), 0.06, 0.06, 0.1, "yellow", segs=6)
    P.cyl(c + V((0.3, -ln / 2 + 0.04, -h * 0.25)), 0.06, 0.06, 0.12, "yellow", segs=6,
          axis_rot=ALONG_Y)
    label(ident, c + V((out * r * 0.72, 0.0, r * 0.72)), (out, 0, 1), (0, 1, 0), 0.15, INK, 0.9)
    label("H2", c + V((-out * r * 0.72, 0.0, r * 0.72)), (-out, 0, 1), (0, 1, 0), 0.15, INK, 0.85)


def build_containers(rng):
    P = parts.PanelPart("cargo_containers", MATS)
    c = lambda sx, k: V((sx * CONT_X, CONT_Y[k], CONT_Z))   # noqa: E731
    corr_container(P, c(-1, 0), C_RED, "BX-2096", door_rear=False, patch=C_BLUE)
    pod_container(P, c(1, 0), C_GREEN, "MX-3350")
    tank_container(P, c(-1, 1), "TK-4471")
    corr_container(P, c(1, 1), C_BLUE, "ORE", door_rear=True)
    return P


# ---------------------------------------------------------------- assemble
def build_hull(rng):
    P = parts.PanelPart("cargo_shuttle_hull", MATS)
    build_can(P, rng)
    build_spine(P, rng)
    build_cradle(P, rng)
    build_tanks(P, rng)
    build_drive(P, rng)
    return P


def build_glow():
    p = parts.Part("engine_glow", MATS)
    for sx in (-1, 1):
        parts.exhaust_glow(p, BELL_R * 0.85, 0.85, "glow", x=sx * BELL_X, segs=16)
    return p


def build_ship(textures=True):
    rng = random.Random(7731)
    register_kinds()
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    root = parts.make_root(PRE)
    hull = build_hull(rng).finish(root)
    cont = build_containers(rng).finish(root)
    glow = build_glow().finish(root)
    glow.location = (0, NOZZLE_Y, 0)
    bpy.context.view_layer.update()
    if textures:
        glow.hide_render = True
        wk.texture([hull, cont], MATS, PRE, [(0.0, 0.0)], scorch=SCORCH,
                   decals=DECALS, labels=LABELS, seed0=73,
                   res=2048)
        glow.hide_render = False
        recompress()
    else:
        for o in (hull, cont):
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    # containers: origin on the middle of the bed so the supply-run scale squashes them down
    cont.data.transform(Matrix.Translation(-CARGO_ORIGIN))
    cont.location = CARGO_ORIGIN
    return root, [hull, cont, glow]


JPEG_QUALITY = dict(albedo=92, mr=92, normal=95)   # as baked; lower one to shrink the .glb


def recompress():
    """Re-save the baked maps at JPEG_QUALITY when that is below the bake's own quality
    (the exporter embeds the files as they are)."""
    base = dict(albedo=92, mr=92, normal=95)
    for img in bpy.data.images:
        name = os.path.basename(img.filepath)
        if not name.startswith(f"{PRE}_") or not name.endswith(".jpg"):
            continue
        kind = name[len(PRE) + 1:-4]
        if JPEG_QUALITY.get(kind, 100) >= base.get(kind, 0):
            continue
        img.file_format = "JPEG"
        img.save(quality=JPEG_QUALITY[kind])
        img.reload()
        print("RECOMPRESSED", name, os.path.getsize(bpy.path.abspath(img.filepath)))


def scale_preview(path):
    ship = "miner_hauler.glb" if os.path.exists(os.path.join(
        common.ROOT, "assets", "models", "ships", "miner_hauler.glb")) else "miner.glb"
    miner = os.path.join(common.ROOT, "assets", "models", "ships", ship)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=miner)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.parent is None:
            o.location.x += 12.0
    common.setup_preview(cam_loc=(-4, -16, 24), cam_target=(6.0, 0, 0), res=(1600, 1000),
                         key_dir=(-0.5, 0.4, 0.75), key_energy=3.5)
    common.render(path)


def extra_views(out_dir, cont):
    """Debug close-ups into out_dir; not part of the previews."""
    scene = bpy.context.scene
    if scene.camera is None:
        common.setup_preview(cam_loc=(-10, 7, 12), cam_target=(0, 0, 0), ortho_scale=13.5,
                             res=(1600, 1200), key_dir=(-0.5, 0.4, 0.75), key_energy=3.5)
    cam = scene.camera
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1200
    views = (("rts", (-3.5, -8, 17), (0, 0, 0), 13.5),
             ("bow", (-5, 10, 4.5), (0, 3.2, 0.1), 5.0),
             ("stern", (-6, -10, 5), (0, -2.9, 0.0), 6.5),
             ("side", (-30, 0, 0), (0, 0, 0.1), 11.0),
             ("front", (0, 30, 0), (0, 0, 0.1), 7.5),
             ("belly", (-7, 5, -8), (0, 0, -0.3), 12.0))
    for name, loc, tgt, ortho in views:
        cam.location = loc
        cam.rotation_euler = (V(tgt) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        cam.data.ortho_scale = ortho
        common.render(os.path.join(out_dir, f"{PRE}_{name}.png"))
    # the two looks Godot gives the load: empty cradle, supply run (CargoShuttle.SUPPLY_SCALE)
    cont.hide_render = True
    for name, loc, tgt, ortho in (views[0], (("q", (-10, 7, 12), (0, 0, 0), 13.5))):
        cam.location = loc
        cam.rotation_euler = (V(tgt) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        cam.data.ortho_scale = ortho
        common.render(os.path.join(out_dir, f"{PRE}_empty_{name}.png"))
    cont.hide_render = False
    cont.scale = (1.0, 0.6, 0.55)     # Godot (x, y up, z) = Blender (x, z up, y)
    cam.location = (-10, 7, 12)
    cam.rotation_euler = (V((0, 0, 0)) - V(cam.location)).to_track_quat("-Z", "Y").to_euler()
    common.render(os.path.join(out_dir, f"{PRE}_supply_q.png"))
    cont.scale = (1.0, 1.0, 1.0)


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_ship(textures="--no-textures" not in argv)
    wk.stats(objs)
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews(PRE, 10.0, target=(0, 0, 0))
    if "--scale-png" in argv:
        scale_preview(argv[argv.index("--scale-png") + 1])
    extra = [a.split("=", 1)[1] for a in argv if a.startswith("--extra=")]
    if extra:
        extra_views(extra[0], objs[1])


main()
