"""Generate the construction drone .glb (CD-07 welding tender; flies round structures being
built, decorative).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_construction_drone.py
  Options after `--`: --no-preview, --no-textures (flat colours), --res=N (atlas, default 1024),
  --check (arm sweep and contract asserts only, no export), --scale-png /abs/out.png (the
  shuttle comparison shot to that path).

Design: a station-built work drone in the home station's worn-plate language, the small
cousin of the mining outpost's manipulator. A plated core with a deck and a lifting frame, an
X of outriggers to four cold-gas RCS pods (hazard caps on the corners, dark lift bells, no
glow), nitrogen tanks along the flanks, an aft power pack with radiator fins, whips and a small
dish, a nose sensor head (lidar strip, camera), landing legs and a cassette of spare plates
underneath. Under the chin hangs the welding arm: shoulder hub between cheek plates, a plated
boom with a cable tray and a gas bottle, a ram across the knee, a forearm with work lights, a
wrist ring and the torch with its spatter visor. Ochre only on the joints that move the work,
hazard only on edges and tools. Lights each have a job: an amber caged beacon (drone_light,
pulsed by the game), red / green nav on the front pods, floods, a cool sensor strip.

Built in GAME metres (what Godot shows at drone_scale 2.0), baked, then every mesh is scaled by
EXPORT_K = 0.5 (never the root), so the game's numbers stay as they are.
Layout (Blender Z up, +Y = nose = Godot -Z). Origin at the body centre.
Hierarchy: construction_drone (root, identity) -> drone_body, drone_lamps, drone_arm
(-> weld_tip), drone_light. drone_arm origin = the shoulder axis (the game swings its local X,
rest rotation 0); weld_tip is an empty on the arm's centreline at the torch tip; drone_light
origin is the beacon lens centre (the game pulses its scale).
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
X = V((1, 0, 0))
PRE = "construction_drone"
OUT = os.path.join(common.ROOT, "assets", "models", "ships", f"{PRE}.glb")
BLEND = os.path.join(common.ROOT, "blender", f"{PRE}.blend")
SHUTTLE_GLB = os.path.join(common.ROOT, "assets", "models", "ships", "cargo_shuttle.glb")
OUTPOST_GLB = os.path.join(common.ROOT, "assets", "models", "buildings", "mining_outpost.glb")
EXPORT_K = 0.5
NO_PADS = [(0.0, 900.0), (0.0, 901.0)]

# Arm geometry (game metres, x = 0 plane).
S = V((0.0, 0.70, -0.46))
E = V((0.0, 1.12, -0.60))
W = V((0.0, 1.28, -0.96))
FD = (W - E).normalized()
TIP = W + FD * 0.30
LIGHT_C = V((0.0, -0.32, 0.49))
POD_C = [V((sx * 1.28, sy * 1.02, 0.06)) for sx in (-1, 1) for sy in (-1, 1)]

LABELS = ["CD-07", "NO STEP", "KEEP CLEAR", "N2", "HOT", "#CHEV", "#BAR"]
INK_DARK, INK_LIGHT = wk.INK_DARK, wk.INK_LIGHT
ID_BLUE = (0.045, 0.085, 0.17)

MATS = {}
DECALS = []
SCORCH = []
B = L = A = LT = None
RNG = random.Random(7)
strut = parts.strut
pipe = parts.pipe


# ---------------------------------------------------------------- worn kinds at drone scale
def _kind(base, **kw):
    d = dict(st.WORN_KINDS[base])
    d.update(kw)
    return d


DRONE_WORN = {
    "hull": _kind("hull", tones=[(0.40, 0.40, 0.39), (0.36, 0.365, 0.365), (0.44, 0.435, 0.42),
                                 (0.31, 0.32, 0.325), (0.38, 0.37, 0.35), (0.34, 0.35, 0.36)],
                  big=(0.7, 0.5), plate=(0.35, 0.25), plate_var=0.09, seam_big=0.45,
                  seam_small=0.18, rivets=True, hatches=0.18, chip_k=0.8, grime_k=1.0,
                  streak_k=0.45, bleach=0.2),
    "hull2": _kind("hull2", big=(0.6, 0.45), plate=(0.3, 0.22), chip_k=0.8),
    "hull3": _kind("hull3", big=(0.5, 0.5), plate=(0.25, 0.25)),
    "slate": _kind("hull3", tones=[(0.16, 0.19, 0.225), (0.145, 0.175, 0.205), (0.175, 0.205, 0.24),
                                   (0.135, 0.16, 0.185), (0.165, 0.185, 0.21), (0.15, 0.17, 0.2)],
                   big=(0.5, 0.4), plate=(0.25, 0.2), plate_var=0.06, chip_k=1.0, bleach=0.3),
    "ochre": _kind("hull3", tones=[(0.30, 0.235, 0.12), (0.28, 0.22, 0.11), (0.32, 0.25, 0.13),
                                   (0.27, 0.215, 0.115), (0.295, 0.235, 0.125), (0.285, 0.225, 0.12)],
                   big=(0.5, 0.4), plate=(0.25, 0.2), plate_var=0.07, chip_k=1.2, bleach=0.45,
                   streak_k=0.55),
    "dark": _kind("dark", big=(0.4, 0.4), plate=(0.2, 0.2), chip_k=0.6),
    "metal": _kind("metal", big=(0.4, 0.2), plate=(0.2, 0.2)),
    "accent": _kind("accent", big=(0.4, 0.3), plate=(0.2, 0.15)),
    "hazard": _kind("hazard", tones=[(0.42, 0.29, 0.04), (0.40, 0.28, 0.035), (0.44, 0.31, 0.045),
                                     (0.38, 0.27, 0.04), (0.43, 0.30, 0.04), (0.41, 0.285, 0.04)],
                    big=(0.4, 0.4), plate=(0.2, 0.2), stripes=0.14),
    "radiator": _kind("radiator", tones=[(0.40, 0.405, 0.41), (0.37, 0.375, 0.38), (0.43, 0.435, 0.44),
                                         (0.36, 0.365, 0.37), (0.39, 0.395, 0.40), (0.38, 0.385, 0.39)],
                      big=(0.5, 0.12), plate=(0.5, 0.06)),
    "rust": _kind("rust", big=(0.3, 0.25), plate=(0.15, 0.12)),
}
st.WORN_KINDS.update(DRONE_WORN)


def build_materials():
    m = common.make_material
    wk.build_materials(PRE, MATS, extra=("rust",))
    MATS["slate"] = m(f"{PRE}_hull_slate", (0.16, 0.19, 0.22), roughness=0.58)
    MATS["ochre"] = m(f"{PRE}_hull_ochre", (0.30, 0.235, 0.12), roughness=0.6)
    MATS["hazard"] = m(f"{PRE}_hazard", (0.42, 0.29, 0.04), roughness=0.62)
    glow = (0.03, 0.028, 0.025)
    for key, col, s in (("status", (1.0, 0.55, 0.06), 4.5), ("nav_red", (1.0, 0.08, 0.03), 3.5),
                        ("nav_green", (0.08, 1.0, 0.22), 3.5), ("flood", (1.0, 0.95, 0.85), 2.5),
                        ("pilot", (1.0, 0.6, 0.25), 2.5)):
        MATS[key] = m(f"{PRE}_{key}", glow, roughness=0.3, emission=col, emission_strength=s)
        MATS[key].use_backface_culling = False


# ---------------------------------------------------------------- helpers
def label(text, centre, normal, up, h, colour, opacity=0.85, depth=0.08):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity, depth))


def nav(c, mat, s):
    c = V(c)
    B.box(c - V((0, 0, s * 0.45)), (s * 0.7, s * 0.7, s * 0.4), "dark", bevel=0.0)
    L.box(c, (s, s, s * 0.6), mat, bevel=0.0)


def look(n):
    """4x4 rotation whose local +Z points along n."""
    n = V(n).normalized()
    return n.to_track_quat("Z", "Y").to_matrix().to_4x4()


def set_origin(obj, pivot):
    obj.data.transform(Matrix.Translation(-V(pivot)))
    obj.location = V(pivot)


# ---------------------------------------------------------------- body
def build_core():
    B.box(V((0, 0, 0.05)), (1.10, 1.40, 0.62), "hull", bevel=0.05)
    B.box(V((0, -0.02, 0.375)), (0.88, 0.98, 0.03), "hull2", bevel=0.0)
    B.box(V((-0.22, 0.30, 0.395)), (0.34, 0.40, 0.02), "slate", bevel=0.0)
    B.box(V((0.56, -0.30, 0.22)), (0.02, 0.40, 0.20), "hull3", bevel=0.0)
    for sy in (-1, 1):   # waist frame
        B.box(V((0, sy * 0.71, -0.08)), (1.14, 0.06, 0.10), "dark", bevel=0.0)
    for sx in (-1, 1):
        B.box(V((sx * 0.575, 0, -0.08)), (0.06, 1.44, 0.10), "dark", bevel=0.0)
        strut(B, V((sx * 0.47, -0.60, 0.47)), V((sx * 0.47, 0.55, 0.47)), 0.05, 0.05, "dark")
        for yy in (-0.55, 0.0, 0.50):
            strut(B, V((sx * 0.47, yy, 0.39)), V((sx * 0.47, yy, 0.47)), 0.05, 0.05, "dark")
    strut(B, V((-0.47, -0.55, 0.47)), V((0.47, -0.55, 0.47)), 0.05, 0.05, "dark")
    B.box(V((0, 0, -0.275)), (0.80, 1.10, 0.03), "dark", bevel=0.0)
    label("CD-07", V((0, 0.10, 0.391)), UP, V((0, 1, 0)), 0.12, INK_LIGHT)
    label("#BAR", V((0, -0.06, 0.391)), UP, V((0, 1, 0)), 0.04, ID_BLUE)
    label("NO STEP", V((0.16, -0.32, 0.391)), UP, V((0, 1, 0)), 0.06, INK_LIGHT, 0.7)
    label("#CHEV", V((0, 0.701, 0.08)), V((0, 1, 0)), UP, 0.08, INK_DARK)


def build_head():
    B.box(V((0, 0.78, 0.30)), (0.46, 0.22, 0.20), "dark", bevel=0.1)
    B.box(V((0, 0.86, 0.405)), (0.50, 0.12, 0.015), "hull2", bevel=0.0)
    B.cyl(V((0.17, 0.92, 0.25)), 0.045, 0.045, 0.08, "dark", segs=8, axis_rot=parts.ALONG_Y)
    L.cyl(V((0.17, 0.963, 0.25)), 0.025, 0.025, 0.006, "window_cool", segs=8, axis_rot=parts.ALONG_Y)
    B.cyl(V((-0.12, 0.76, 0.43)), 0.06, 0.06, 0.06, "metal", segs=8)
    B.cyl(V((-0.12, 0.76, 0.466)), 0.062, 0.062, 0.012, "dark", segs=8)
    L.box(V((0, 0.895, 0.32)), (0.26, 0.012, 0.06), "window_cool", bevel=0.0)


def build_chin():
    B.box(V((0, 0.57, -0.305)), (0.46, 0.18, 0.11), "dark", bevel=0.0)
    for sx in (-1, 1):
        B.box(V((sx * 0.17, 0.70, -0.44)), (0.05, 0.24, 0.26), "dark", bevel=0.05)
    B.cyl(S, 0.04, 0.04, 0.40, "dark", segs=8, axis_rot=parts.ALONG_X)
    B.cyl(V((0.25, 0.70, -0.46)), 0.12, 0.12, 0.10, "dark", segs=10, axis_rot=parts.ALONG_X)
    B.cyl(V((0.31, 0.70, -0.46)), 0.125, 0.125, 0.02, "ochre", segs=10, axis_rot=parts.ALONG_X)
    B.cyl(V((-0.205, 0.70, -0.46)), 0.10, 0.10, 0.02, "ochre", segs=10, axis_rot=parts.ALONG_X)
    n = V((0, 0.6, -0.8))
    for sx in (-1, 1):
        c = V((sx * 0.28, 0.74, -0.27))
        B.box(c, (0.12, 0.07, 0.08), "dark", r=parts.rot(rx=-0.93), bevel=0.0)
        parts.quad(L, c + n * 0.045, n, V((0, 0.8, 0.6)), 0.09, 0.05, "flood")
    SCORCH.append((0.0, 0.74, -0.30, 0.10))


def build_tanks():
    for sx in (-1, 1):
        x = sx * 0.78
        parts.capsule(B, -0.42, 0.36, 0.17, lambda i, j: "hull", segs=10, x=x, z=-0.02)
        for yy in (-0.22, 0.18):
            pipe(B, V((x, yy - 0.02, -0.02)), V((x, yy + 0.02, -0.02)), 0.178, "dark", segs=10)
            B.box(V((sx * 0.66, yy, -0.02)), (0.22, 0.06, 0.12), "dark", bevel=0.0)
        for yy in (0.48, -0.54):
            B.box(V((x, yy, -0.02)), (0.07, 0.07, 0.07), "rust", bevel=0.0)
        label("N2", V((sx * 0.951, -0.05, 0.0)), V((sx, 0, 0)), UP, 0.08, INK_DARK)


def build_pods():
    for c in POD_C:
        sx = 1 if c.x > 0 else -1
        sy = 1 if c.y > 0 else -1
        a0 = V((sx * 0.50, sy * 0.60, 0.05))
        B.beam(a0, c, 0.11, 0.09, "dark")
        mid = a0.lerp(c, 0.5)
        ang = math.atan2(c.y - a0.y, c.x - a0.x)
        B.box(mid, (0.20, 0.13, 0.11), "hull2", rot_z=ang, bevel=0.05)
        vb = V((sx * 0.78, sy * 0.48 if sy > 0 else -0.54, -0.02))
        top = a0 + V((0, 0, 0.07))
        pipe(B, vb, top, 0.018, "metal", segs=6)
        pipe(B, top, c + V((0, 0, 0.07)), 0.018, "metal", segs=6)
        B.box(mid + V((0, 0, 0.07)), (0.04, 0.04, 0.04), "dark", bevel=0.0)
        parts.rcs_quad(B, c + V((0, 0, 0.04)), V((0, 0, 1)), "hull2", "metal", s=0.26,
                       fwd=V((0, 1, 0)))
        B.box(c + V((0, 0, 0.214)), (0.20, 0.20, 0.02), "hazard", bevel=0.0)
        prof = [(0.0, -0.10), (0.06, -0.10), (0.065, -0.13), (0.11, -0.27), (0.095, -0.27),
                (0.05, -0.15), (0.0, -0.15)]
        B.lathe(prof, 8, lambda i, j: "metal" if j < 3 else "dark",
                matrix=Matrix.Translation(c))
        SCORCH.append((c.x, c.y, -0.12, 0.08))
    nav(V((-1.33, 1.07, 0.26)), "nav_red", 0.06)
    nav(V((1.33, 1.07, 0.26)), "nav_green", 0.06)


def build_pack():
    B.box(V((0, -0.88, 0.06)), (0.86, 0.36, 0.44), "slate", bevel=0.05)
    B.box(V((0, -0.71, 0.06)), (0.88, 0.02, 0.46), "dark", bevel=0.0)
    B.box(V((0, -1.07, 0.06)), (0.62, 0.02, 0.38), "hull3", bevel=0.0)
    B.box(V((0, -1.085, 0.10)), (0.50, 0.015, 0.20), "dark", bevel=0.0)
    for k in range(4):
        B.box(V((0, -1.094, 0.03 + k * 0.045)), (0.48, 0.02, 0.025), "metal", bevel=0.0)
    label("HOT", V((0, -1.081, -0.065)), V((0, -1, 0)), UP, 0.06, INK_DARK)
    for sx in (-1, 1):
        B.box(V((sx * 0.46, -0.88, 0.40)), (0.04, 0.34, 0.26), "radiator", bevel=0.0)
        B.box(V((sx * 0.46, -0.88, 0.54)), (0.05, 0.36, 0.02), "metal", bevel=0.0)
        for yy in (-0.96, -0.80):
            B.box(V((sx * 0.46, yy, 0.40)), (0.05, 0.015, 0.24), "metal", bevel=0.0)
        base = V((sx * 0.34, -0.64, 0.41))
        B.box(base - V((0, 0, 0.025)), (0.05, 0.05, 0.05), "dark", bevel=0.0)
        tip = base + V((sx * math.sin(math.radians(8)), 0, math.cos(math.radians(8)))) * 0.36
        B.tube(base, tip, 0.012, 0.005, "metal", segs=6)
        # aft cold-gas bells
        m = Matrix.Translation((sx * 0.26, 0, -0.10)) @ parts.ALONG_Y
        prof = [(0.0, -1.08), (0.04, -1.08), (0.06, -1.14), (0.09, -1.26), (0.08, -1.26), (0.0, -1.15)]
        B.lathe(prof, 8, lambda i, j: "dark" if j < 3 else "metal", matrix=m)
        SCORCH.append((sx * 0.26, -1.22, -0.10, 0.10))
    # small dish
    dc = V((0.24, -0.95, 0.30))
    dm = Matrix.Translation(dc) @ look(V((0, -0.5, 0.85)))
    B.lathe([(0.0, 0.0), (0.045, 0.012), (0.09, 0.04), (0.083, 0.046), (0.0, 0.015)], 10,
            lambda i, j: "metal", matrix=dm)
    feed = dc + V((0, -0.5, 0.85)).normalized() * 0.10
    for k in range(3):
        a = k * math.tau / 3
        rim = dm @ V((0.085 * math.cos(a), 0.085 * math.sin(a), 0.04))
        strut(B, rim, feed, 0.012, 0.012, "dark")
    B.box(feed, (0.025, 0.025, 0.025), "dark", bevel=0.0)
    nav(V((0, -1.02, 0.31)), "flood", 0.05)


def build_beacon():
    B.cyl(V((0, -0.32, 0.42)), 0.07, 0.07, 0.06, "dark", segs=10)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        p0 = V((0.08 * math.cos(a), -0.32 + 0.08 * math.sin(a), 0.45))
        strut(B, p0, p0 + V((0, 0, 0.095)), 0.015, 0.015, "metal")
    B.cyl(V((0, -0.32, 0.55)), 0.08, 0.08, 0.01, "dark", segs=10)
    LT.cyl(LIGHT_C, 0.055, 0.055, 0.07, "status", segs=8)


def build_underside():
    for sx in (-1, 1):
        for sy in (-1, 1):
            top = V((sx * 0.48, sy * 0.58, -0.26))
            foot = V((sx * 0.60, sy * 0.70, -0.50))
            strut(B, top, foot, 0.05, 0.05, "dark")
            B.box(top + V((0, 0, -0.03)), (0.07, 0.07, 0.10), "hull2", bevel=0.0)
            B.cyl(V((sx * 0.62, sy * 0.72, -0.54)), 0.10, 0.10, 0.05, "dark", segs=10)
            pipe(B, V((sx * 0.62, sy * 0.72, -0.5225)), V((sx * 0.62, sy * 0.72, -0.5075)), 0.105,
                 "metal", segs=10)
    for sx in (-1, 1):
        B.box(V((sx * 0.30, 0, -0.31)), (0.06, 0.62, 0.05), "dark", bevel=0.0)
    B.box(V((0, 0, -0.345)), (0.54, 0.46, 0.025), "hull3", bevel=0.0)
    B.box(V((0, 0, -0.372)), (0.52, 0.44, 0.025), "slate", bevel=0.0)
    B.box(V((0, 0, -0.40)), (0.54, 0.46, 0.025), "hull", bevel=0.0)
    for sx in (-1, 1):
        for sy in (-1, 1):
            B.box(V((sx * 0.30, sy * 0.20, -0.38)), (0.08, 0.08, 0.10), "dark", bevel=0.0)


# ---------------------------------------------------------------- arm
def build_arm():
    bd = (E - S).normalized()
    bup = (UP - bd * bd.dot(UP)).normalized()
    fup = (X.cross(FD)).normalized()
    if fup.y < 0:
        fup = -fup
    A.cyl(S, 0.08, 0.08, 0.26, "dark", segs=10, axis_rot=parts.ALONG_X)
    A.beam(S, E, 0.20, 0.17, "hull", up=bup)
    A.beam(S.lerp(E, 0.38), S.lerp(E, 0.68), 0.21, 0.18, "slate", up=bup)
    for t in (0.2, 0.4, 0.7, 0.88):
        A.beam(S.lerp(E, t - 0.006), S.lerp(E, t + 0.006), 0.215, 0.185, "dark", up=bup)
    A.beam(S.lerp(E, 0.12) + bup * 0.095, S.lerp(E, 0.9) + bup * 0.095, 0.09, 0.02, "dark", up=bup)
    bc = S.lerp(E, 0.55) - bup * 0.13
    A.tube(bc - bd * 0.09, bc + bd * 0.09, 0.04, 0.04, "hull3", segs=6)
    for o in (-0.05, 0.05):
        pipe(A, bc + bd * o - X * 0.005, bc + bd * o + X * 0.005, 0.045, "dark", segs=6)
    label("KEEP CLEAR", S.lerp(E, 0.55) + X * 0.101, X, bup, 0.06, INK_DARK)
    label("KEEP CLEAR", S.lerp(E, 0.55) - X * 0.101, -X, bup, 0.06, INK_DARK)
    # elbow
    for sx in (-1, 1):
        A.box(E + X * sx * 0.11, (0.04, 0.17, 0.17), "dark", bevel=0.05)
        A.cyl(E + X * sx * 0.135, 0.075, 0.075, 0.02, "ochre", segs=10, axis_rot=parts.ALONG_X)
    A.cyl(E, 0.07, 0.07, 0.22, "dark", segs=10, axis_rot=parts.ALONG_X)
    # forearm
    A.beam(E + FD * 0.06, W, 0.15, 0.15, "hull2", up=fup)
    A.beam(E.lerp(W, 0.35), E.lerp(W, 0.6), 0.155, 0.155, "hull3", up=fup)
    for t in (0.2, 0.86):
        A.beam(E.lerp(W, t - 0.006), E.lerp(W, t + 0.006), 0.16, 0.16, "dark", up=fup)
    # ram across the knee
    a0, a1 = V((0, 0.927, -0.409)), V((0, 1.267, -0.685))
    m = a0.lerp(a1, 0.6)
    A.tube(a0, m, 0.035, 0.035, "dark", segs=8)
    A.tube(m - (a1 - a0).normalized() * 0.01, a1, 0.02, 0.02, "metal", segs=8)
    for q in (a0, a1):
        A.box(q, (0.06, 0.06, 0.06), "dark", bevel=0.1)
    A.box(a0 - bup * 0.03, (0.06, 0.04, 0.04), "dark", bevel=0.0)
    A.box(a1 - fup * 0.03, (0.06, 0.04, 0.04), "dark", bevel=0.0)
    # hoses on the tray
    path = [S + bd * 0.06 + bup * 0.07, S + bd * 0.40 + bup * 0.115,
            E + (bup + fup).normalized() * 0.13, E + FD * 0.30 + fup * 0.09,
            W + fup * 0.09 - FD * 0.02]
    for xo, rad, mat in ((0.03, 0.014, "metal"), (-0.03, 0.012, "accent")):
        for p0, p1 in zip(path, path[1:]):
            pipe(A, p0 + X * xo, p1 + X * xo, rad, mat, segs=5)
    for q in path[1:4]:
        A.box(q, (0.1, 0.04, 0.04), "dark", bevel=0.0)
    # forearm floods aimed along the torch
    for sx in (-1, 1):
        c = E.lerp(W, 0.7) + X * sx * 0.105
        A.box(c, (0.06, 0.08, 0.06), "dark", bevel=0.0)
        parts.quad(A, c + FD * 0.045, FD, fup, 0.05, 0.04, "flood")
    # wrist and torch
    A.cyl(W, 0.08, 0.08, 0.08, "dark", segs=10, axis_rot=look(FD))
    A.cyl(W + FD * 0.02, 0.095, 0.095, 0.04, "ochre", segs=10, axis_rot=look(FD))
    A.tube(W + FD * 0.04, W + FD * 0.17, 0.07, 0.07, "dark", segs=10)
    A.cyl(W + FD * 0.17, 0.077, 0.077, 0.025, "hazard", segs=10, axis_rot=look(FD))
    A.tube(W + FD * 0.18, TIP, 0.032, 0.016, "metal", segs=8)
    A.cyl(TIP - FD * 0.005, 0.02, 0.02, 0.01, "pilot", segs=8, axis_rot=look(FD))
    # spatter visor: a plate across the wrist, facing along the torch (x across, thin along FD)
    vc = W + fup * 0.10 + FD * 0.05
    vm = Matrix((X, FD, fup)).transposed().to_4x4()
    A.box(vc, (0.20, 0.015, 0.14), "hull2", r=vm, bevel=0.0)
    A.box(vc + fup * 0.075, (0.20, 0.02, 0.02), "hazard", r=vm, bevel=0.0)
    A.box(W + X * 0.10, (0.05, 0.06, 0.05), "dark", bevel=0.0)
    A.cyl(W + X * 0.10 + FD * 0.035, 0.015, 0.015, 0.02, "metal", segs=6, axis_rot=look(FD))
    SCORCH.append((0.0, 1.33, -1.13, 0.10))


# ---------------------------------------------------------------- assembly and checks
def build_drone():
    global B, L, A, LT
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    B = parts.PanelPart("drone_body", MATS)
    L = parts.PanelPart("drone_lamps", MATS)
    A = parts.PanelPart("drone_arm", MATS)
    LT = parts.PanelPart("drone_light", MATS)
    for f in (build_core, build_head, build_chin, build_tanks, build_pods, build_pack, build_beacon,
              build_underside, build_arm):
        f()
    root = parts.make_root(PRE, size=1.0)
    body, lamps, arm, light = (p.finish(root) for p in (B, L, A, LT))
    for o in (lamps, light):
        o.data.uv_layers.remove(o.data.uv_layers["panel"])
    return root, body, lamps, arm, light


def bvh_of(obj, extra=Matrix()):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.transform(extra @ obj.matrix_world)
    t = BVHTree.FromBMesh(bm)
    bm.free()
    return t


def check(body, lamps, arm):
    """Arm sweep over the game's clamp range against the body; contract numbers."""
    bpy.context.view_layer.update()
    statics = [bvh_of(body), bvh_of(lamps)]
    smeshes = []
    for o in (body, lamps):
        sb = bmesh.new()
        sb.from_mesh(o.data)
        sb.transform(o.matrix_world)
        sb.faces.ensure_lookup_table()
        smeshes.append(sb)
    bad = 0
    bm = bmesh.new()
    bm.from_mesh(arm.data)
    bm.transform(arm.matrix_world)
    bm.faces.ensure_lookup_table()
    for a in (-1.2, -0.9, -0.6, -0.3, 0.0, 0.3, 0.6, 0.9):
        rot = Matrix.Translation(S) @ Matrix.Rotation(a, 4, "X") @ Matrix.Translation(-S)
        t = bvh_of(arm, rot)
        hits = 0
        for s, sb in zip(statics, smeshes):
            for ia, ib in s.overlap(t):
                ca = sb.faces[ia].calc_center_median()
                cb = rot @ bm.faces[ib].calc_center_median()
                # the axle pin runs through the hub and the boom root on purpose
                if (V((0, ca.y, ca.z)) - S).length < 0.16 or (cb - S).length < 0.16:
                    continue
                hits += 1
                if hits <= 3:
                    print(f"   touch body face at {tuple(round(c, 2) for c in ca)} arm face at {tuple(round(c, 2) for c in cb)}")
        if hits:
            print(f"CHECK arm at {a:+.1f} rad: {hits} face pairs touch the body")
            bad += 1
    bm.free()
    for sb in smeshes:
        sb.free()
    up = Matrix.Translation(S) @ Matrix.Rotation(0.9, 4, "X") @ Matrix.Translation(-S)
    assert (up @ TIP).z > TIP.z, "positive arm rotation must lift the tip"
    rest = math.atan2((TIP - S).z, (TIP - S).y)
    print(f"GEOM shoulder {tuple(round(c, 3) for c in S * EXPORT_K)} tip(arm-local) "
          f"{tuple(round(c, 3) for c in (TIP - S) * EXPORT_K)} rest angle {rest:.3f} rad")
    assert -1.0 <= rest <= -0.4, rest
    print(f"CHECK done, {bad} problems")
    return bad


def finish_export(root, body, lamps, arm, light):
    set_origin(arm, S)
    set_origin(light, LIGHT_C)
    for o in (body, lamps, arm, light):
        o.data.transform(Matrix.Scale(EXPORT_K, 4))
        o.location = o.location * EXPORT_K
    tip = parts.add_empty("weld_tip", arm, (TIP - S) * EXPORT_K, size=0.03)
    tip.empty_display_type = "PLAIN_AXES"
    bpy.context.view_layer.update()
    # contract asserts
    assert root.matrix_world == Matrix.Identity(4)
    assert arm.parent == root and tuple(arm.rotation_euler) == (0.0, 0.0, 0.0)
    assert tip.parent == arm and abs(tip.location.x) < 1e-5
    names = [o.name for o in bpy.data.objects if o == root or o.parent and (o.parent == root or o.parent == arm)]
    for n in ("drone_arm", "weld_tip", "drone_light"):
        assert names.count(n) == 1, (n, names)
    lo, hi = V((9, 9, 9)), V((-9, -9, -9))
    for o in (body, lamps, arm, light):
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            lo = V((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = V((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    print(f"ENVELOPE unscaled x {lo.x:.3f}..{hi.x:.3f} y {lo.y:.3f}..{hi.y:.3f} z {lo.z:.3f}..{hi.z:.3f}")
    assert max(abs(lo.x), hi.x) <= 0.85 and lo.y >= -0.7 and hi.y <= 0.9 and lo.z >= -0.65 and hi.z <= 0.42, (lo, hi)
    return tip


# ---------------------------------------------------------------- previews
def import_glb(path, loc, rot_z=0.0, scale=1.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    r = next(o for o in new if o.parent is None)
    r.location = loc
    r.rotation_mode = "XYZ"
    r.rotation_euler = (0, 0, rot_z)
    r.scale = (scale, scale, scale)
    return r, new


def dim(objs, k=0.35):
    for mm in {s.material for o in objs if o.type == "MESH" for s in o.material_slots}:
        if mm and mm.node_tree:
            b = next((n for n in mm.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if b:
                b.inputs["Emission Strength"].default_value *= k


def aim(cam, loc, tgt):
    cam.location = V(loc)
    cam.rotation_euler = (V(tgt) - cam.location).to_track_quat("-Z", "Y").to_euler()


def previews(root, arm, scale_png=None):
    root.scale = (1 / EXPORT_K,) * 3   # preview at game size; the glb is already written
    bpy.context.view_layer.update()
    common.setup_preview(cam_loc=(-3.2, 3.6, 3.0), cam_target=(0, 0.2, -0.1), ortho_scale=4.4,
                         res=(1600, 1200), key_dir=(-0.5, 0.4, 0.75), key_energy=3.5)
    scene = bpy.context.scene
    cam = scene.camera
    shots = []

    def shot(name):
        p = os.path.join(common.PREVIEW_DIR, f"{PRE}_{name}.png")
        common.render(p)
        shots.append(p)

    shot("preview")
    aim(cam, (0, 0.2, 20), (0, 0.2, 0))
    cam.rotation_euler = (0, 0, 0)
    scene.render.resolution_x, scene.render.resolution_y = 1200, 1200
    shot("top")
    cam.data.type = "PERSP"
    cam.data.lens = 50
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1000
    aim(cam, (1.6, 2.5, -0.4), (0, 1.1, -0.75))
    shot("arm")
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 4.2
    for a, tag in ((-1.2, "m120"), (0.0, "0"), (0.9, "p90")):
        arm.rotation_euler.x = a
        aim(cam, (8, 0.3, -0.2), (0, 0.3, -0.2))
        shot(f"sweep_{tag}")
    arm.rotation_euler.x = 0.0
    # next to the cargo shuttle for scale
    if os.path.exists(SHUTTLE_GLB):
        r, new = import_glb(SHUTTLE_GLB, (6.0, 0.0, 0.0))
        cam.data.type = "PERSP"
        cam.data.lens = 35
        aim(cam, (-6, -10, 7), (3.0, 0.0, 0.0))
        shot("shuttle")
        if scale_png:
            import shutil
            shutil.copy(shots[-1], scale_png)
        for o in new:
            bpy.data.objects.remove(o, do_unlink=True)
    # a crew at the mining outpost, game camera pitch
    if os.path.exists(OUTPOST_GLB):
        r, new = import_glb(OUTPOST_GLB, (0, 0, 0))
        dim(new)
        crew = []
        for k, (x, y, z, yaw) in enumerate(((15.0, -2.0, 12.6, 0.6), (9.0, 7.0, 6.0, -0.4),
                                            (20.0, 4.0, 4.5, 2.4), (-6.0, 12.0, 6.5, 0.0),
                                            (22.5, 10.0, 13.5, 3.0))):
            rr, nn = import_glb(OUT, (x, y, z), yaw, 1 / EXPORT_K)
            crew.append(nn)
        cam.data.type = "PERSP"
        cam.data.sensor_fit = "VERTICAL"
        cam.data.angle_y = math.radians(50)
        scene.render.resolution_x, scene.render.resolution_y = 1920, 1080
        for dist, tag in ((80, "game80"), (25, "outpost_close")):
            pr = math.radians(30)
            tgt = V((12, 4, 6))
            aim(cam, tgt + V((0, -math.cos(pr) * dist, math.sin(pr) * dist)), tgt)
            shot(tag)
    print("PREVIEWS " + " ".join(shots))


def main():
    argv = parts.script_args(sys.argv)
    res = 1024
    for a in argv:
        if a.startswith("--res="):
            res = int(a.split("=")[1])
    common.reset_scene()
    root, body, lamps, arm, light = build_drone()
    if "--check" in argv:
        check(body, lamps, arm)
        return
    check(body, lamps, arm)
    if "--no-textures" not in argv:
        wk.texture([body, arm], MATS, PRE, NO_PADS, scorch=SCORCH, decals=DECALS, labels=LABELS,
                   seed0=7, res=res)
    else:
        for o in (body, arm):
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    finish_export(root, body, lamps, arm, light)
    wk.stats([body, lamps, arm, light])
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        sp = argv[argv.index("--scale-png") + 1] if "--scale-png" in argv else None
        previews(root, arm, sp)


main()
