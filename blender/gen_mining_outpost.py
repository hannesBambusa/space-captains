"""Generate the mining outpost (ORM-1, ore receiving module) .glb and previews.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_mining_outpost.py
  Options after `--`: --no-preview, --no-textures (flat colours, fast), --no-ships (previews
  without haulers), --res=2048 (smaller atlas), --check (clearance asserts only, no export).
Textures: one worn-industrial atlas in the home station's language (worn_kit /
station_textures.WORN_KINDS plus gen_station's hull / radiator / slate / ochre overrides and
an "orestain" kind), 4096 by default, saved as blender/textures/mining_outpost_*.jpg. The
moving belt uses the outpost belt tile (outpost_textures.bake_belt_tile, also used by the
salvage yard).

Design: an ore-receiving module built by the station's people. Haulers back into an open
docking cradle (two truss rails with catwalks over crew tubes, a keel truss under the bay,
saddle clamps and belly drain probes, umbilical arms); a slewing grab crane on the +X side
lifts ore out of berth 0's hold into an intake funnel; a level belt gallery runs to the
crusher node, an ore lift carries the crushed ore up into the crowned bunker on top (open
cage, the fill level shows through); the process spine behind the bay (hab node, cans, centre
node with the control cab, crusher node) is pressurised station hardware; a radiator boom
trails aft (the crusher's heat); the west side has the fuel farm and the despatch rack of
typed ore canisters with the outbound jib. Colour has one meaning each: ochre = ore-moving
machinery, rust / orestain = ore contact, hazard = edges and moving parts.

Layout (Blender Z up, exported +Y up; Blender -Y = Godot +Z, the mouth). Centre at origin.
  cradle    rails x +-10.5, y -15..7.4; berths at (+-4.4, -3), outer clamps at (+-17, -14.5)
  spine     y 11: hab node x -24, west can, centre node x 0 (cab), east can, crusher node x 21
  crane     tower (15, 3.5), slewing ring top PIVOT z 8.6; grab rests over HOLD, swings
            +78.6 deg about up to the intake funnel HOPPER
  bunker    (21.5, 12), floor z 2.05 (ore_silo_fill), rim z 9
  west      fuel farm (-18.5, -11..-8), despatch rack x -25..-14, y -1.5..2.5
Hierarchy: mining_outpost (empty root) -> mining_outpost_hull, mining_outpost_lights,
  unload_arm (origin at the slewing ring), ore_conveyor_belt (origin at the tail),
  ore_silo_fill (origin at the bunker floor), unload_lights (amber, blinks while unloading),
  dock_point, spawn_point, ore_flow_point (empties). Same names and swing convention as
  before, so OutpostUnloadFx and Building drive it unchanged.
"""
import math
import os
import random
import shutil
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
PRE = "mining_outpost"
OUT = os.path.join(common.ROOT, "assets", "models", "buildings", f"{PRE}.glb")
BLEND = os.path.join(common.ROOT, "blender", f"{PRE}.blend")
HAULER_GLB = os.path.join(common.ROOT, "assets", "models", "ships", "miner_hauler.glb")
SHUTTLE_GLB = os.path.join(common.ROOT, "assets", "models", "ships", "cargo_shuttle.glb")
STATION_GLB = os.path.join(common.ROOT, "assets", "models", "station", "station_home.glb")
BELT_TEX = [os.path.join(st.TEX_DIR, f"outpost_belt_{n}") for n in
            ("albedo.jpg", "mr.png", "normal.png")]
BELT_TILE = 4.8

# ---------------------------------------------------------------- layout constants
DOCK_POS = V((0.0, -14.0, 0.0))
SPAWN_POS = V((0.0, -32.0, 0.0))
BERTH_X, BERTH_Y = 4.4, -3.0
HOLD = V((BERTH_X, -0.4, 0.0))
PIVOT = V((15.0, 3.5, 8.6))
SWING = math.radians(78.6)
R_ARM = (HOLD.xy - PIVOT.xy).length
A_HOLD = math.atan2(HOLD.y - PIVOT.y, HOLD.x - PIVOT.x)
HOPPER = V((PIVOT.x + R_ARM * math.cos(A_HOLD + SWING),
            PIVOT.y + R_ARM * math.sin(A_HOLD + SWING), 0.0))
FLOW_Z = 4.2
RAIL_X, RAIL_Y0, RAIL_Y1 = 10.5, -15.0, 7.4
SPINE_Y, SPINE_Z = 11.0, -1.0
KEEL_Z = -6.5
NODE_R = 4.6
CRUSH_C = V((21.0, 11.5, SPINE_Z))
BUNKER_C = V((21.5, 12.0, 0.0))
BUNKER_R, BUNKER_FLOOR, BUNKER_RIM = 4.4, 2.05, 9.0
BELT0 = V((HOPPER.x, -6.9, -4.3))
BELT1 = V((21.0, 5.6, -4.3))
OUTER_X, OUTER_Y = 17.0, -24.0

LABELS = ["MO-1", "ORE DOCK", "BERTH 1", "BERTH 2", "INTAKE", "CRUSHER", "ORE LIFT", "BUNKER",
          "LOAD LIMIT", "25", "50", "75", "FUEL", "NO STEP", "KEEP CLEAR", "HOT", "IRON",
          "TITAN", "CRYSTAL", "ORE", "ORE LINE", "OUTBOUND", "CAB", "SWING ZONE", "R-01",
          "R-02", "R-03", "#BAR", "#CHEV", "M-ARM 2"]
INK_DARK, INK_LIGHT = wk.INK_DARK, wk.INK_LIGHT
HAZ_INK = (0.36, 0.26, 0.04)
ID_COLS = [(0.045, 0.085, 0.17), (0.20, 0.045, 0.035), (0.06, 0.13, 0.06), (0.36, 0.26, 0.04)]
NO_PADS = [(0.0, 900.0), (0.0, 901.0)]

MATS = {}
DECALS = []
SCORCH = []
BEACONS = []
H = L = A = F = None
RNG = random.Random(61)

strut = parts.strut
pipe = parts.pipe
window = parts.window
pick_lit = parts.pick_lit


# ---------------------------------------------------------------- station look
def _kind(base, **kw):
    d = dict(st.WORN_KINDS[base])
    d.update(kw)
    return d


st.WORN_KINDS["hull"] = _kind("hull", tones=[(0.40, 0.40, 0.39), (0.36, 0.365, 0.365),
                              (0.44, 0.435, 0.42), (0.31, 0.32, 0.325), (0.38, 0.37, 0.35),
                              (0.34, 0.35, 0.36)], plate_var=0.09, grime_k=1.35, streak_k=0.6,
                              chip_k=1.25, hatches=0.18)
st.WORN_KINDS["radiator"] = _kind("radiator", tones=[(0.40, 0.405, 0.41), (0.37, 0.375, 0.38),
                                  (0.43, 0.435, 0.44), (0.36, 0.365, 0.37), (0.39, 0.395, 0.40),
                                  (0.38, 0.385, 0.39)], grime_k=1.0, streak_k=0.45)
st.WORN_KINDS["slate"] = _kind("hull3", tones=[(0.16, 0.19, 0.225), (0.145, 0.175, 0.205),
                               (0.175, 0.205, 0.24), (0.135, 0.16, 0.185), (0.165, 0.185, 0.21),
                               (0.15, 0.17, 0.2)], plate_var=0.06, chip_k=1.3, bleach=0.35)
st.WORN_KINDS["ochre"] = _kind("hull3", tones=[(0.30, 0.235, 0.12), (0.28, 0.22, 0.11),
                               (0.32, 0.25, 0.13), (0.27, 0.215, 0.115), (0.295, 0.235, 0.125),
                               (0.285, 0.225, 0.12)], plate_var=0.07, chip_k=1.6, bleach=0.45,
                               streak_k=0.55)
# Ore-stained steel: liners, belt skirts, funnel lining.
st.WORN_KINDS["orestain"] = _kind("hull2", tones=[(0.17, 0.13, 0.09), (0.15, 0.115, 0.08),
                                  (0.19, 0.145, 0.10), (0.14, 0.11, 0.075), (0.16, 0.125, 0.085),
                                  (0.18, 0.14, 0.095)], grime_k=1.8, streak_k=1.2, chip_k=1.4,
                                  bleach=0.2)


def build_materials():
    m = common.make_material
    wk.build_materials(PRE, MATS, extra=("rust", "ore"))
    MATS["slate"] = m(f"{PRE}_hull_slate", (0.16, 0.19, 0.22), roughness=0.58)
    MATS["ochre"] = m(f"{PRE}_hull_ochre", (0.30, 0.235, 0.12), roughness=0.6)
    MATS["orestain"] = m(f"{PRE}_orestain", (0.16, 0.125, 0.085), roughness=0.75)
    MATS["mli_gold"] = m(f"{PRE}_mli_gold", (0.6, 0.39, 0.12), roughness=0.3, metallic=1.0)
    MATS["mli_silver"] = m(f"{PRE}_mli_silver", (0.6, 0.6, 0.61), roughness=0.26, metallic=1.0)
    glow = (0.03, 0.028, 0.025)
    for key, col, s in (("nav_red", (1.0, 0.08, 0.03), 6.0), ("nav_green", (0.08, 1.0, 0.22), 6.0),
                        ("nav_white", (1.0, 0.97, 0.92), 4.0), ("flood", (1.0, 0.95, 0.85), 4.5)):
        MATS[key] = m(f"{PRE}_{key}", glow, roughness=0.3, emission=col, emission_strength=s)
        MATS[key].use_backface_culling = False
    MATS["amber"] = m(f"{PRE}_unload_amber", glow, roughness=0.3, emission=(1.0, 0.55, 0.06),
                      emission_strength=6.0)
    MATS["amber"].use_backface_culling = False


# ---------------------------------------------------------------- helpers
def label(text, centre, normal, up, h, colour, opacity=0.85):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity))


def up_for(n_up):
    """Label up direction that never reads upside down from the south (-Y) camera."""
    return n_up if n_up.y >= -1e-3 else -n_up


def nav(p, c, mat, s=0.5):
    """Nav light: dark base (on the hull, or on p when p is the arm) + emissive cap on p."""
    c = V(c)
    (H if p is L else p).box(c - V((0, 0, s * 0.45)), (s * 0.7, s * 0.7, s * 0.4), "dark",
                             bevel=0.0)
    p.box(c, (s, s, s * 0.6), mat, bevel=0.0)


def beacon_mast(base, h, mat, s=0.5):
    base = V(base)
    H.cyl(base + UP * h / 2, 0.14, 0.07, h, "metal", segs=6)
    H.box(base + UP * 0.15, (0.6, 0.6, 0.3), "dark", bevel=0.0)
    nav(L, base + UP * (h + s * 0.3), mat, s)


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
    c0, c1 = V(c0), V(c1)
    n = max(2, int((c1 - c0).length / pitch))
    for i in range(n):
        p.beam(c0.lerp(c1, i / n), c0.lerp(c1, (i + 1) / n), w, h,
               "hazard" if i % 2 == 0 else "dark", up=up)


def unload_beacon(pos):
    """Dark housing in the hull; the amber dome goes into unload_lights."""
    p = V(pos)
    H.cyl(p + V((0, 0, -0.2)), 0.26, 0.3, 0.4, "dark", segs=8)
    BEACONS.append(p)


def bracket_pipe(p0, p1, rad, mat, step=2.0, drop=0.3):
    """Conduit run with dark brackets every `step` metres (towards -Z by `drop`)."""
    p0, p1 = V(p0), V(p1)
    pipe(H, p0, p1, rad, mat, segs=6)
    n = max(1, int((p1 - p0).length / step))
    for k in range(n + 1):
        q = p0.lerp(p1, k / n)
        H.box(q - V((0, 0, drop * 0.5)), (0.25, 0.25, drop + rad), "dark", bevel=0.0)


# ---------------------------------------------------------------- pressurised modules
def drum(c, r, z0, z1, body, mode, win_arc=None, n_win=8, segs=32):
    """Junction drum like the station's ring nodes: vertical lathe, dark caps, a patchwork of
    body plates, a collar band, windows round the front arc."""
    c = V(c)
    prof = [(0.0, z0), (r * 0.7, z0), (r * 0.92, z0 + 0.6), (r, z0 + 1.2), (r, z1 - 0.9),
            (r * 0.9, z1 - 0.3), (r * 0.6, z1), (0.0, z1)]
    em = {0: "dark", 1: "hull2", 2: "hull2", 3: "body", 4: "hull2", 5: "hull2", 6: "dark"}
    panel = [RNG.choice(body) for _ in range(segs // 4)]

    def mf(i, j):
        k = em[j]
        return panel[i // 4] if k == "body" else k

    H.lathe(prof, segs, mf, matrix=Matrix.Translation((c.x, c.y, 0)), start=math.pi / segs)
    zc = (z0 + z1) / 2
    H.cyl(V((c.x, c.y, zc + 0.8)), r + 0.07, r + 0.07, 0.3, "dark", segs=segs)
    for k in range(12):   # stringers
        a = k * math.tau / 12 + 0.13
        H.box(V((c.x + (r + 0.05) * math.cos(a), c.y + (r + 0.05) * math.sin(a), zc)),
              (0.14, 0.22, z1 - z0 - 2.6), "dark", rot_z=a, bevel=0.0)
    if win_arc:
        a0, a1 = win_arc
        rf = r * math.cos(math.pi / segs) + 0.01
        for k in range(n_win):
            a = a0 + (a1 - a0) * (k + 0.5) / n_win
            n = V((math.cos(a), math.sin(a), 0))
            window(L, V((c.x, c.y, zc - 0.4)) + n * rf, n, UP, 0.5, 0.6, pick_lit(RNG, mode))


def can(x0, x1, y, z, r, mode, bands_at=(), paint=("hull", "hull3", "slate", "hull", "hull2")):
    """Pressurised can along X (no end domes: it plugs into nodes at both ends)."""
    ln = x1 - x0
    segs = 16
    prof = [(r * 0.86, 0.0), (r, 0.3), (r, ln - 0.3), (r * 0.86, ln)]
    patch = [RNG.choice(paint) for _ in range(segs // 4 + 1)]
    m = Matrix.Translation((x0, y, z)) @ parts.ALONG_X
    H.lathe(prof, segs, lambda i, j: "dark" if j != 1 else patch[i // 4], matrix=m,
            start=math.pi / segs)
    for k in range(int(ln / 4.0) + 1):   # dark collars
        H.cyl(V((x0 + 0.4 + k * (ln - 0.8) / max(int(ln / 4.0), 1), y, z)), r + 0.08, r + 0.08,
              0.3, "dark", segs=segs, axis_rot=parts.ALONG_X)
    for bx in bands_at:
        H.cyl(V((bx, y, z)), r + 0.05, r + 0.05, 0.7, "ochre", segs=segs, axis_rot=parts.ALONG_X)
    for a in (math.radians(60), math.radians(120)):   # stringer straps on the camera side
        n = V((0, -math.cos(a), math.sin(a))).normalized()
        H.beam(V((x0 + 0.3, y, z)) + n * (r + 0.04), V((x1 - 0.3, y, z)) + n * (r + 0.04), 0.12,
               0.08, "dark", up=n)
    # windows on the front (-Y)
    n_w = max(3, int(ln / 1.4))
    rf = r * math.cos(math.pi / segs) + 0.01
    for k in range(n_w):
        x = x0 + 0.9 + (ln - 1.8) * (k + 0.5) / n_w
        for zz in (-0.45, 0.55):
            window(L, V((x, y - rf, z + zz)), V((0, -1, 0)), UP, 0.45, 0.5, pick_lit(RNG, mode))
    # top conduits on brackets
    bracket_pipe(V((x0 + 0.5, y - 0.9, z + r + 0.45)), V((x1 - 0.5, y - 0.9, z + r + 0.45)),
                 0.16, "metal", step=2.0, drop=0.45)
    pipe(H, V((x0 + 0.5, y - 0.45, z + r + 0.32)), V((x1 - 0.5, y - 0.45, z + r + 0.32)), 0.09,
         "accent", segs=5)
    # doubler plates and service boxes
    for k in range(3):
        x = RNG.uniform(x0 + 1.5, x1 - 1.5)
        a = RNG.uniform(math.radians(200), math.radians(250))
        n = V((0, math.cos(a), math.sin(a)))
        H.box(V((x, y, z)) + n * (r + 0.03), (RNG.uniform(1.4, 3.0), 0.1, RNG.uniform(0.7, 1.3)),
              RNG.choice(["hull2", "hull3", "slate", "rust"]),
              r=Matrix.Rotation(-(a - math.pi * 1.5), 4, "X"), bevel=0.0)
    for k in range(2):
        x = RNG.uniform(x0 + 1.5, x1 - 1.5)
        H.box(V((x, y + 0.6, z + r + 0.35)), (1.4, 0.9, 0.7), "hull2", bevel=0.08)
        H.box(V((x, y + 0.6, z + r + 0.72)), (1.2, 0.7, 0.06), "dark", bevel=0.0)
    return rf


# ---------------------------------------------------------------- A. docking cradle
def build_cradle():
    for sx in (-1, 1):
        x = sx * RAIL_X
        mat = "metal" if sx > 0 else "rust"
        truss(H, (x, RAIL_Y0, -1.0), (x, RAIL_Y1, -1.0), 1.6, 2.0, 10, mat, chord=0.28,
              brace=0.16)
        # catwalk + handrail on the outer edge
        H.box(V((x, (RAIL_Y0 + RAIL_Y1) / 2, 0.05)), (1.4, RAIL_Y1 - RAIL_Y0, 0.1), "pad",
              bevel=0.0)
        handrail(H, [V((x + sx * 0.65, RAIL_Y0 + 0.5, 0.1)), V((x + sx * 0.65, RAIL_Y1 - 0.4, 0.1))])
        # crew tube under the rail
        H.cyl(V((x, -2.5, -3.2)), 0.85, 0.85, 19.0, "hull", segs=12, axis_rot=parts.ALONG_Y)
        for k in range(6):
            yy = -11.6 + k * 3.6
            H.cyl(V((x, yy, -3.2)), 0.93, 0.93, 0.25, "dark", segs=12, axis_rot=parts.ALONG_Y)
            H.beam(V((x, yy, -2.4)), V((x, yy, -2.0)), 0.3, 0.3, "dark")
        for k in range(5):
            yy = -10.0 + k * 3.6
            window(L, V((x + sx * 0.86, yy, -3.2)), V((sx, 0, 0)), UP, 0.4, 0.45,
                   pick_lit(RNG, "hab"))
        H.cyl(V((x, -12.2, -3.2)), 0.6, 0.85, 0.5, "hull2", segs=12, axis_rot=parts.ALONG_Y)
        H.cyl(V((x, 7.2, -3.2)), 0.85, 0.85, 0.5, "dark", segs=12, axis_rot=parts.ALONG_Y)
        # mouth collar pylon
        cx = sx * 11.5
        prof = [(0.0, -2.8), (1.6, -2.8), (2.2, -2.3), (2.2, -0.1), (2.2, 0.35), (1.7, 0.8),
                (0.0, 0.8)]
        cm = {0: "dark", 1: "hull2", 2: "hull3", 3: "hazard", 4: "hull2", 5: "dark"}
        H.lathe(prof, 16, lambda i, j: cm[j], matrix=Matrix.Translation((cx, RAIL_Y0, 0)),
                start=math.pi / 16)
        label("ORE DOCK", V((cx, RAIL_Y0 - 2.19, -1.3)), V((0, -1, 0)), UP, 0.42, INK_DARK)
        for dy in (-0.8, 0.8):   # flood masts, heads aimed into the bay
            base = V((sx * 10.1, RAIL_Y0 + dy, 0.8))
            H.beam(base, base + UP * 2.4, 0.18, 0.18, "metal")
            head = base + UP * 2.5
            H.box(head, (0.5, 0.42, 0.3), "dark", bevel=0.0)
            L.box(head + V((-sx * 0.27, 0.06, -0.05)), (0.08, 0.42, 0.22), "flood", bevel=0.0)
        unload_beacon(V((sx * 9.9, RAIL_Y0, 1.0)))
        # hazard kerb at the mouth end of the catwalk
        hazard_band(H, V((sx * 9.75, RAIL_Y0, 0.16)), V((sx * 9.75, RAIL_Y0 + 4.0, 0.16)), 0.18,
                    0.12)
        # lead-in lamps along the catwalk inner edge
        for k in range(6):
            yy = RAIL_Y0 + 1.0 + k * 3.6
            L.box(V((sx * 9.78, yy, 0.18)), (0.3, 0.3, 0.16),
                  "window_dim" if k % 2 == 0 else "nav_white", bevel=0.0)
        label("#CHEV", V((sx * 10.5, RAIL_Y0 + 2.0, 0.11)), UP, V((0, 1, 0)), 0.5, HAZ_INK)
        label("BERTH 1" if sx > 0 else "BERTH 2", V((sx * 10.5, -6.0, 0.11)), UP, V((0, 1, 0)),
              0.9, INK_LIGHT)
        # umbilical arm at y 1
        a0 = V((sx * 9.7, 1.0, 0.2))
        a1 = V((sx * 8.2, 1.0, 1.0))
        H.beam(a0, a1, 0.22, 0.22, "metal")
        H.beam(a0 + V((0, 0.35, 0)), a1 + V((0, 0.35, 0)), 0.16, 0.16, "metal")
        H.box(a1, (0.5, 0.8, 0.5), "dark", bevel=0.1)
        H.cyl(a1 + V((-sx * 0.32, 0.2, 0)), 0.16, 0.16, 0.25, "metal", segs=8,
              axis_rot=parts.ALONG_X)
        pipe(H, a0 + V((0, -0.2, 0.15)), a1 + V((0, -0.2, 0.2)), 0.09, "accent", segs=5)
    label("SWING ZONE", V((RAIL_X, 1.5, 0.11)), UP, V((0, 1, 0)), 0.42, HAZ_INK, 0.8)
    # keel truss and riser into the centre node
    truss(H, (0, -12.0, KEEL_Z), (0, 7.0, KEEL_Z), 2.4, 1.6, 8, "dark", chord=0.3, brace=0.16)
    H.cyl(V((0, 8.0, (KEEL_Z + SPINE_Z - 3.0) / 2)), 1.0, 1.0, SPINE_Z - 3.0 - KEEL_Z + 0.8,
          "hull2", segs=12)
    for sx in (-1, 1):
        x = sx * BERTH_X
        # saddle clamps
        for yy in (-1.2, 2.4):
            strut(H, V((sx * 1.2, yy, KEEL_Z + 0.8)), V((x - sx * 0.6, yy, -3.55)), 0.3, 0.3,
                  "dark")
            strut(H, V((sx * 1.2, yy, KEEL_Z - 0.8)), V((x + sx * 0.6, yy, -3.6)), 0.24, 0.24,
                  "dark")
            H.box(V((x, yy, -3.45)), (3.0, 0.8, 0.3), "hull2", bevel=0.1)
            for s2 in (-1, 1):
                H.box(V((x + s2 * 0.95, yy, -3.22)), (0.8, 0.8, 0.25), "pad",
                      r=Matrix.Translation((0, 0, 0)) @ Matrix.Rotation(-s2 * math.radians(25), 4, "Y"),
                      bevel=0.0)
                H.box(V((x + s2 * 1.46, yy, -3.45)), (0.08, 0.82, 0.32), "hazard", bevel=0.0)
        # belly drain probe
        px, py = x, HOLD.y
        H.beam(V((sx * 1.2, py, KEEL_Z + 0.8)), V((px, py, KEEL_Z + 0.8)), 0.36, 0.36, "dark")
        H.cyl(V((px, py, (KEEL_Z + 0.8 - 4.2) / 2)), 0.6, 0.6, 4.2 + KEEL_Z + 0.8, "hull2",
              segs=10)
        H.cyl(V((px, py, -3.6)), 0.42, 0.42, 1.2, "metal", segs=10)
        H.torus(V((px, py, -4.2)), 0.68, 0.12, "hazard", segs=16, minor_segs=6)
        for k in range(4):
            a = k * math.pi / 2 + math.pi / 4
            L.box(V((px + 0.62 * math.cos(a), py + 0.62 * math.sin(a), -4.05)), (0.12, 0.12, 0.08),
                  "green", bevel=0.0)
        pipe(H, V((px, py + 0.6, -5.2)), V((sx * 1.2, py + 0.6, KEEL_Z + 0.5)), 0.32, "dark")
        # blast plates on the spine fronts behind the sterns
        H.box(V((x, 7.75, SPINE_Z)), (6.0, 0.12, 4.0), "dark", bevel=0.0)
        SCORCH.append((x, 7.7, SPINE_Z, 2.6))
        # outer parking clamps
        truss(H, (sx * 11.5, -14.0, 1.0), (sx * 21.5, -14.0, 1.0), 1.2, 1.0, 6, "dark",
              chord=0.22, brace=0.12)
        H.box(V((sx * OUTER_X, -14.5, 2.0)), (3.0, 0.8, 2.0), "dark", bevel=0.05)
        H.box(V((sx * OUTER_X, -14.92, 2.0)), (2.4, 0.06, 1.4), "pad", bevel=0.0)
        label("#CHEV", V((sx * OUTER_X, -14.96, 2.0)), V((0, -1, 0)), UP, 0.45, HAZ_INK)
        nav(L, V((sx * 21.5, -14.0, 1.6)), "nav_green" if sx > 0 else "nav_red", 0.5)
        SCORCH.append((sx * OUTER_X, -14.9, 1.0, 1.8))
        SCORCH.append((sx * 11.5, RAIL_Y0, 0.0, 1.5))


# ---------------------------------------------------------------- B. process spine
def build_spine():
    # centre node with the control cab
    drum(V((0, SPINE_Y, 0)), NODE_R, SPINE_Z - 3.0, SPINE_Z + 3.0, ("hull", "hull3", "slate"),
         "work", win_arc=(math.radians(-150), math.radians(-30)), n_win=8)
    H.sphere(V((0, SPINE_Y, SPINE_Z + 3.05)), 1.4, "metal", segs=12, rings=6, scale=(1, 1, 0.35))
    cab = V((0, SPINE_Y - 1.4, SPINE_Z + 4.3))
    H.box(cab, (3.0, 2.4, 2.6), "hull3", bevel=0.08)
    H.box(cab + V((0, 0, 1.4)), (3.3, 2.7, 0.2), "dark", bevel=0.0)
    for k in range(4):
        L.box(cab + V((-1.05 + k * 0.7, -1.22, 0.35)), (0.5, 0.05, 0.6), "window_cool", bevel=0.0)
    label("CAB", cab + V((0, -1.21, -0.6)), V((0, -1, 0)), UP, 0.4, INK_DARK)
    beacon_mast(cab + V((0.9, 0.5, 1.5)), 2.2, "nav_red")
    parts.rcs_quad(H, V((0, SPINE_Y + NODE_R + 0.1, SPINE_Z + 1.0)), V((0, 1, 0)), "hull2", "dark",
                   s=0.6, fwd=UP)
    SCORCH.append((0, SPINE_Y + NODE_R, SPINE_Z + 1.0, 1.4))
    label("MO-1", V((0, SPINE_Y - NODE_R - 0.02, SPINE_Z - 1.6)), V((0, -1, 0)), UP, 0.8,
          INK_DARK)
    # cans
    can(-19.4, -NODE_R, SPINE_Y, SPINE_Z, 3.2, "hab", bands_at=(-12.0,))
    can(NODE_R, 16.4, SPINE_Y, SPINE_Z, 3.2, "work", bands_at=(10.5,))
    label("R-01", V((-15.5, SPINE_Y - 3.21, SPINE_Z + 1.4)), V((0, -1, 0)), UP, 0.5, INK_DARK)
    label("R-02", V((7.5, SPINE_Y - 3.21, SPINE_Z + 1.4)), V((0, -1, 0)), UP, 0.5, INK_DARK)
    label("#BAR", V((-9.0, SPINE_Y - 3.21, SPINE_Z - 1.6)), V((0, -1, 0)), UP, 0.35, ID_COLS[0])
    label("#BAR", V((13.0, SPINE_Y - 3.21, SPINE_Z - 1.6)), V((0, -1, 0)), UP, 0.35, ID_COLS[3])
    label("NO STEP", V((-8.0, SPINE_Y - 1.4, SPINE_Z + 3.1)), UP, V((0, 1, 0)), 0.3, INK_DARK, 0.7)
    label("NO STEP", V((8.0, SPINE_Y - 1.4, SPINE_Z + 3.1)), UP, V((0, 1, 0)), 0.3, INK_DARK, 0.7)
    # west hab node: dish, mast
    hab = V((-24.0, SPINE_Y, 0))
    drum(hab, NODE_R, SPINE_Z - 3.0, SPINE_Z + 3.0, ("hull", "hull3", "hull"), "hab",
         win_arc=(math.radians(-160), math.radians(-20)), n_win=8)
    parts.dish(H, V((hab.x, hab.y + 1.0, SPINE_Z + 3.3)), 1.8, V((0, -0.6, 0.8)), "hull", "metal")
    beacon_mast(V((hab.x - 4.0, hab.y, SPINE_Z + 1.5)), 1.6, "nav_red")
    for d in (V((-1, 0, 0)), V((0, 1, 0))):
        parts.rcs_quad(H, hab + V((0, 0, SPINE_Z + 1.0)) + d * (NODE_R + 0.1), d, "hull2", "dark",
                       s=0.6, fwd=UP)
        c = hab + V((0, 0, SPINE_Z + 1.0)) + d * NODE_R
        SCORCH.append((c.x, c.y, c.z, 1.4))
    label("R-03", V((hab.x, hab.y - NODE_R - 0.02, SPINE_Z - 1.6)), V((0, -1, 0)), UP, 0.6, INK_DARK)
    # crusher node: ochre plates, vents, twin crusher housings, head house
    drum(V((CRUSH_C.x, CRUSH_C.y, 0)), NODE_R, SPINE_Z - 3.0, SPINE_Z + 3.0,
         ("ochre", "ochre", "hull2"), "store")
    for k in range(4):
        a = math.radians(200 + k * 25)
        c = V((CRUSH_C.x + (NODE_R - 0.2) * math.cos(a), CRUSH_C.y + (NODE_R - 0.2) * math.sin(a),
               SPINE_Z + 3.2))
        H.cyl(c, 0.32, 0.26, 0.9, "dark", segs=8)
        H.cyl(c + V((0, 0, 0.5)), 0.36, 0.36, 0.12, "metal", segs=8)
    plate = V((CRUSH_C.x - 2.2, CRUSH_C.y - NODE_R - 0.02, SPINE_Z + 0.6))
    H.box(plate + V((0, 0.06, 0)), (2.0, 0.1, 0.9), "hull2", bevel=0.0)
    label("HOT", plate + V((0, -0.01, 0)), V((0, -1, 0)), UP, 0.5, INK_DARK)
    for k in range(4):
        L.box(V((CRUSH_C.x - 3.2 + k * 0.6, CRUSH_C.y - NODE_R - 0.06, SPINE_Z - 0.6)),
              (0.32, 0.06, 0.2), "window_dim", bevel=0.0)
    for yy in (11.0, 14.0):
        H.cyl(V((27.2, yy, SPINE_Z)), 1.3, 1.3, 3.2, "hull2", segs=14, axis_rot=parts.ALONG_X)
        for k in range(6):
            H.cyl(V((25.8 + k * 0.6, yy, SPINE_Z)), 1.38, 1.38, 0.14, "dark", segs=14,
                  axis_rot=parts.ALONG_X)
        H.box(V((27.2, yy, SPINE_Z + 1.6)), (1.4, 1.2, 0.8), "dark", bevel=0.05)
        H.cyl(V((28.95, yy, SPINE_Z)), 0.6, 0.6, 0.3, "metal", segs=10, axis_rot=parts.ALONG_X)
    nav(L, V((29.3, 12.5, SPINE_Z + 1.6)), "nav_green", 0.5)
    hh = V((21.0, 6.1, -4.0))
    H.box(hh, (3.4, 3.0, 3.6), "hull3", bevel=0.08)
    H.box(hh + V((0, 0, 1.85)), (3.6, 3.2, 0.12), "dark", bevel=0.0)
    H.box(V((21.0, 4.58, -3.6)), (2.0, 0.08, 0.7), "hull2", bevel=0.0)
    label("CRUSHER", V((21.0, 4.53, -3.6)), V((0, -1, 0)), UP, 0.45, INK_DARK)
    unload_beacon(V((21.0, 6.0, -2.05)))
    # ore lift: crusher -> bunker top
    lx, ly = 25.6, 7.6
    H.box(V((lx, ly, 3.5)), (1.2, 1.2, 13.0), "hull2", bevel=0.04)
    for k in range(13):
        H.box(V((lx, ly, -2.5 + k)), (1.32, 1.32, 0.1), "dark", bevel=0.0)
    H.box(V((24.0, 8.8, -3.0)), (2.4, 1.2, 1.4), "hull2", bevel=0.05)
    H.box(V((lx, ly, 10.6)), (1.8, 1.6, 1.2), "ochre", bevel=0.06)
    pipe(H, V((lx - 0.5, ly + 0.6, 10.6)), V((24.4, 9.6, 10.2)), 0.42, "rust", segs=8)
    pipe(H, V((24.4, 9.6, 10.2)), V((23.6, 10.2, 9.6)), 0.42, "rust", segs=8)
    H.box(V((lx, ly - 0.62, 6.0)), (1.0, 0.06, 0.5), "hull2", bevel=0.0)
    label("ORE LIFT", V((lx, ly - 0.66, 6.0)), V((0, -1, 0)), UP, 0.22, INK_DARK)
    # coolant line: crusher -> along the east can -> centre node -> radiator boom
    bracket_pipe(V((CRUSH_C.x - 1.0, CRUSH_C.y + 2.5, SPINE_Z + 3.2)),
                 V((CRUSH_C.x - 1.0, SPINE_Y + 1.2, SPINE_Z + 3.4)), 0.12, "accent", drop=0.2)
    bracket_pipe(V((CRUSH_C.x - 1.0, SPINE_Y + 1.2, SPINE_Z + 3.4)),
                 V((1.2, SPINE_Y + 1.2, SPINE_Z + 3.4)), 0.12, "accent", drop=0.25)
    pipe(H, V((1.2, SPINE_Y + 1.2, SPINE_Z + 3.4)), V((0.6, SPINE_Y + NODE_R + 0.4, SPINE_Z + 0.6)),
         0.12, "accent")
    pipe(H, V((0.6, SPINE_Y + NODE_R + 0.4, SPINE_Z + 0.6)), V((0.6, 30.0, SPINE_Z + 0.6)), 0.12,
         "accent")
    # bunker outlet duct -> despatch rack filler hood
    dz = -4.9
    pts = [V((CRUSH_C.x - 2.0, 13.4, dz)), V((-19.5, 13.4, dz)), V((-19.5, 4.2, dz)),
           V((-19.5, 4.2, 3.2))]
    for a, b in zip(pts, pts[1:]):
        pipe(H, a, b, 0.45, "metal", segs=8)
    for k in range(10):
        q = pts[0].lerp(pts[1], k / 9)
        H.cyl(q, 0.52, 0.52, 0.3, "rust", segs=8, axis_rot=parts.ALONG_X)
        H.box(q + V((0, 0, 0.7)), (0.25, 0.3, 0.9), "dark", bevel=0.0)
    H.cyl(V((-1.0, 13.4, dz)), 0.5, 0.5, 1.0, "hull2", segs=8, axis_rot=parts.ALONG_X)
    label("ORE LINE", V((-1.0, 12.88, dz)), V((0, -1, 0)), UP, 0.2, INK_DARK)


def build_bunker():
    c = BUNKER_C
    # ring girder + brackets on the crusher node top
    H.torus(V((c.x, c.y, BUNKER_FLOOR - 0.15)), BUNKER_R, 0.28, "dark", segs=24, minor_segs=6)
    H.cyl(V((c.x, c.y, BUNKER_FLOOR - 0.05)), BUNKER_R - 0.1, BUNKER_R - 0.1, 0.12, "dark", segs=24)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        H.beam(V((c.x + BUNKER_R * math.cos(a), c.y + BUNKER_R * math.sin(a), BUNKER_FLOOR - 0.2)),
               V((CRUSH_C.x + 3.4 * math.cos(a), CRUSH_C.y + 3.4 * math.sin(a), SPINE_Z + 2.9)), 0.3,
               0.3, "dark")
    # posts, hoops, liner bars, braces
    for k in range(12):
        a = k * math.tau / 12
        p0 = V((c.x + BUNKER_R * math.cos(a), c.y + BUNKER_R * math.sin(a), BUNKER_FLOOR))
        H.box(p0 + V((0, 0, (BUNKER_RIM - BUNKER_FLOOR) / 2)), (0.24, 0.24, BUNKER_RIM - BUNKER_FLOOR),
              "metal", rot_z=a, bevel=0.0)
        # liner bars between posts (orestain), every other bay fully lined
        a2 = a + math.tau / 24
        q = V((c.x + (BUNKER_R - 0.12) * math.cos(a2), c.y + (BUNKER_R - 0.12) * math.sin(a2), 0))
        nb = 2 if k % 2 == 0 else 1
        for j in range(nb):
            off = (j - (nb - 1) / 2) * 0.6
            t = V((-math.sin(a2), math.cos(a2), 0)) * off
            H.box(q + t + V((0, 0, (BUNKER_RIM + BUNKER_FLOOR) / 2 - 0.3)),
                  (0.12, 0.34, BUNKER_RIM - BUNKER_FLOOR - 1.0), "orestain", rot_z=a2, bevel=0.0)
        if k % 2 == 1:   # X brace in alternate bays
            b0 = V((c.x + BUNKER_R * math.cos(a), c.y + BUNKER_R * math.sin(a), 0))
            a3 = a + math.tau / 12
            b1 = V((c.x + BUNKER_R * math.cos(a3), c.y + BUNKER_R * math.sin(a3), 0))
            strut(H, b0 + V((0, 0, BUNKER_FLOOR + 0.4)), b1 + V((0, 0, BUNKER_RIM - 0.8)), 0.1, 0.1,
                  "dark")
            strut(H, b1 + V((0, 0, BUNKER_FLOOR + 0.4)), b0 + V((0, 0, BUNKER_RIM - 0.8)), 0.1, 0.1,
                  "dark")
    for z in (4.0, 6.0, 8.0):
        H.cyl(V((c.x, c.y, z)), BUNKER_R + 0.06, BUNKER_R + 0.06, 0.3, "ochre", segs=24)
        H.cyl(V((c.x, c.y, z)), BUNKER_R - 0.08, BUNKER_R - 0.08, 0.32, "dark", segs=24)
    H.torus(V((c.x, c.y, BUNKER_RIM + 0.05)), BUNKER_R + 0.05, 0.3, "dark", segs=24, minor_segs=6)
    for k in range(12):   # crown: retention coil blocks
        a = k * math.tau / 12 - math.pi / 2
        cc = V((c.x + 4.65 * math.cos(a), c.y + 4.65 * math.sin(a), BUNKER_RIM + 0.4))
        H.box(cc, (1.0, 1.2, 0.8), "metal", rot_z=a, bevel=0.1)
        H.box(cc + V((0, 0, 0.45)), (0.9, 1.1, 0.12), "ochre", rot_z=a, bevel=0.0)
    unload_beacon(V((c.x, c.y - 4.65, BUNKER_RIM + 0.95)))
    # gauge on the south post
    g = V((c.x, c.y - BUNKER_R - 0.16, 0))
    H.box(g + V((0, 0, 5.55)), (0.7, 0.06, 5.0), "dark", bevel=0.0)
    for txt, z in (("25", 3.8), ("50", 5.55), ("75", 7.3)):
        label(txt, g + V((0, -0.04, z)), V((0, -1, 0)), UP, 0.3, INK_LIGHT)
    H.box(V((c.x + 1.8, c.y - BUNKER_R + 0.05, BUNKER_RIM - 0.6)), (1.8, 0.06, 0.5), "hull2",
          bevel=0.0, rot_z=math.radians(24))
    label("LOAD LIMIT", V((c.x + 1.8, c.y - BUNKER_R + 0.01, BUNKER_RIM - 0.6)),
          V((math.sin(math.radians(24)), -math.cos(math.radians(24)), 0)), UP, 0.3, INK_DARK)
    H.box(V((c.x - 2.0, c.y - BUNKER_R + 0.2, 3.0)), (2.2, 0.06, 0.6), "hull2", bevel=0.0,
          rot_z=math.radians(-27))
    label("BUNKER", V((c.x - 2.0, c.y - BUNKER_R + 0.16, 3.0)),
          V((-math.sin(math.radians(27)), -math.cos(math.radians(27)), 0)), UP, 0.4, INK_DARK)


def build_fill():
    """ore_silo_fill: octagonal ore column with a low lumpy cap, built from z 0 up (origin set
    to the bunker floor after the bake); scale 1 = up to the rim."""
    r = BUNKER_R - 0.25
    hh = BUNKER_RIM - BUNKER_FLOOR - 0.1
    c = V((BUNKER_C.x, BUNKER_C.y, BUNKER_FLOOR))
    F.lathe([(0.0, 0.0), (r, 0.0), (r, hh - 0.2), (r * 0.7, hh + 0.25), (0.0, hh + 0.6)], 8,
            lambda i, j: "ore", matrix=Matrix.Translation(c), start=math.pi / 8)
    for k in range(5):
        a = k * 1.3
        rr = 0.6 + 1.4 * (k % 3) / 2
        F.rock(c + V((rr * math.cos(a), rr * math.sin(a), hh + 0.15)), 0.45, "ore", RNG)


def build_radiators():
    truss(H, (0, 15.6, SPINE_Z), (0, 30.5, SPINE_Z), 1.6, 1.2, 8, "dark", chord=0.24, brace=0.13)
    for yc in (17.3, 21.7, 26.1):
        for sx in (-1, 1):
            tilt = Matrix.Rotation(sx * math.radians(15), 4, "Y")
            c = V((sx * 4.8, yc, SPINE_Z + 0.5))
            rm = Matrix.Translation(c) @ tilt
            H.box(c, (7.2, 4.0, 0.16), "dark", r=tilt, bevel=0.0)
            H.box(c + (tilt.to_3x3() @ V((0, 0, 0.1))), (6.8, 3.6, 0.06), "radiator", r=tilt,
                  bevel=0.0)
            for k in range(6):
                y = yc - 1.6 + k * 0.64
                p0 = rm @ V((-3.4, y - yc, 0.16))
                p1 = rm @ V((3.4, y - yc, 0.16))
                H.beam(p0, p1, 0.12, 0.05, "metal", up=tilt.to_3x3() @ UP)
            H.box(V((sx * 1.2, yc, SPINE_Z)), (0.6, 0.8, 0.6), "dark", bevel=0.0)
            pipe(H, rm @ V((-3.4, -2.0, 0.2)), rm @ V((3.4, -2.0, 0.2)), 0.12, "metal")
    nav(L, V((0, 31.0, SPINE_Z)), "nav_white", 0.5)


# ---------------------------------------------------------------- C. crane
def build_crane():
    """Ore manipulator: a plated utility pylon (hull) with a slewing bearing on top, and
    unload_arm: an industrial manipulator in the station's hardware language. Slewing turret
    with a power pack and sensor head, a plated upper boom on twin hydraulic rams, elbow,
    forearm angled down to the wrist, and a three-finger magnetic grapple holding ore over the
    hold (rest pose). It only ever slews about up, like the old crane."""
    p = PIVOT
    # ---- pylon (static)
    prof = [(0.0, -5.0), (2.0, -5.0), (2.0, -4.4), (1.55, -4.0), (1.55, 2.6), (1.8, 2.9),
            (1.8, 3.4), (1.4, 3.7), (1.4, 7.1), (1.65, 7.45), (1.65, 8.0), (0.0, 8.0)]
    pm = {0: "dark", 1: "dark", 2: "hull2", 3: "slate", 4: "hull2", 5: "dark", 6: "hull2",
          7: "hull", 8: "hull2", 9: "dark", 10: "dark"}
    H.lathe(prof, 8, lambda i, j: pm[j], matrix=Matrix.Translation((p.x, p.y, 0)),
            start=math.pi / 8)
    for k in range(4):   # stringers between the collars
        a = k * math.pi / 2 + math.pi / 8 + 0.2
        for z0, z1, r in ((-3.8, 2.5, 1.57), (3.8, 7.0, 1.42)):
            H.box(V((p.x + r * math.cos(a), p.y + r * math.sin(a), (z0 + z1) / 2)),
                  (0.16, 0.2, z1 - z0), "dark", rot_z=a, bevel=0.0)
    # conduits and a cable tray down the camera side, on brackets
    for k, (dx, rad, mat) in enumerate(((-0.55, 0.11, "metal"), (-0.25, 0.08, "accent"),
                                        (0.6, 0.11, "metal"))):
        x0 = V((p.x + dx, p.y - 1.62, -3.6))
        x1 = V((p.x + dx, p.y - 1.47, 6.9))
        pipe(H, x0, x1, rad, mat, segs=6)
    H.box(V((p.x + 0.2, p.y - 1.52, 1.8)), (0.3, 0.12, 9.6), "dark", bevel=0.0)
    for z in (-2.5, 0.5, 4.6, 6.4):
        H.box(V((p.x, p.y - 1.56, z)), (1.6, 0.14, 0.18), "dark", bevel=0.0)
    H.box(V((p.x, p.y - 1.45, 5.6)), (1.0, 0.08, 0.5), "hull2", bevel=0.0)
    label("M-ARM 2", V((p.x, p.y - 1.5, 5.6)), V((0, -1, 0)), UP, 0.26, INK_DARK)
    # service ring with grating and rail
    H.lathe([(1.75, 3.35), (2.7, 3.35), (2.7, 3.5), (1.75, 3.5)], 8, lambda i, j: "pad",
            matrix=Matrix.Translation((p.x, p.y, 0)), start=math.pi / 8)
    ring = [V((p.x + 2.62 * math.cos(math.pi / 8 + k * math.pi / 4),
               p.y + 2.62 * math.sin(math.pi / 8 + k * math.pi / 4), 3.5)) for k in range(9)]
    handrail(H, ring, hgt=0.9, t=0.05)
    for a in (math.radians(-120), math.radians(-60)):   # work lights on the ring
        c = V((p.x + 2.1 * math.cos(a), p.y + 2.1 * math.sin(a), 4.1))
        H.box(c, (0.4, 0.34, 0.28), "dark", rot_z=a, bevel=0.0)
        L.box(c + V((0, 0, -0.16)), (0.3, 0.26, 0.04), "flood", rot_z=a, bevel=0.0)
    # ties to the rail and the spine
    H.box(V((p.x, p.y, -5.3)), (3.2, 3.2, 0.6), "dark", bevel=0.0)
    for tgt in (V((RAIL_X + 0.8, p.y, -0.4)), V((p.x, SPINE_Y - 3.2, SPINE_Z))):
        H.beam(V((p.x, p.y, -1.0)), tgt, 0.34, 0.34, "dark")
    H.beam(V((p.x, p.y, 4.0)), V((p.x, SPINE_Y - 3.0, SPINE_Z + 1.5)), 0.26, 0.26, "dark")
    # slewing bearing
    H.cyl(V((p.x, p.y, 8.3)), 1.6, 1.6, 0.6, "hull2", segs=18)
    H.cyl(V((p.x, p.y, 8.02)), 1.72, 1.72, 0.12, "dark", segs=18)
    for k in range(24):
        a = k * math.tau / 24
        H.box(V((p.x + 1.62 * math.cos(a), p.y + 1.62 * math.sin(a), 8.45)), (0.08, 0.08, 0.1),
              "metal", bevel=0.0)
    for cx, cy in ((13.8, 2.3), (16.2, 2.3)):   # unload beacons on brackets off the bearing
        H.beam(V((p.x + (cx - p.x) * 0.45, p.y - 0.9, 8.0)), V((cx, cy, 7.9)), 0.16, 0.16, "dark")
        H.box(V((cx, cy, 7.9)), (0.3, 0.3, 0.3), "dark", bevel=0.0)
        BEACONS.append(V((cx, cy, 8.2)))

    # ---- unload_arm (A): rest pose, grapple over HOLD
    d = V((math.cos(A_HOLD), math.sin(A_HOLD), 0))
    sd = V((-d.y, d.x, 0))
    rz = A_HOLD
    rot = Matrix.Rotation(rz, 4, "Z")

    def P(r, side, z):
        return V((p.x, p.y, 0)) + d * r + sd * side + V((0, 0, z))

    def ram(a0, a1, r_sleeve=0.2, r_rod=0.11, mat="dark"):
        """Hydraulic ram a0 -> a1: sleeve 60%, chromed rod, clevis blocks."""
        a0, a1 = V(a0), V(a1)
        m = a0.lerp(a1, 0.6)
        A.tube(a0, m, r_sleeve, r_sleeve, mat, segs=8)
        A.tube(m - (a1 - a0).normalized() * 0.1, a1, r_rod, r_rod, "metal", segs=8)
        for q in (a0, a1):
            A.box(q, (0.36, 0.36, 0.36), "dark", rot_z=rz, bevel=0.1)

    A.cyl(p + V((0, 0, 0.17)), 1.5, 1.5, 0.3, "dark", segs=18)       # bearing disc
    A.lathe([(0.0, 8.92), (1.85, 8.92), (1.85, 9.8), (1.45, 10.35), (0.0, 10.35)], 8,
            lambda i, j: ("dark", "hull3", "hull2", "hull2")[j],
            matrix=Matrix.Translation((p.x, p.y, 0)), start=rz + math.pi / 8)   # turret
    A.box(P(-0.0, 0, 9.4), (3.9, 0.12, 0.5), "dark", rot_z=rz, bevel=0.0)
    # power pack at the back: plated box, grille, two radiator fins
    pk = P(-2.15, 0, 9.85)
    A.box(pk, (2.0, 2.5, 1.7), "hull3", rot_z=rz, bevel=0.08)
    A.box(pk - d * 1.02, (0.06, 2.1, 1.2), "dark", rot_z=rz, bevel=0.0)
    for k in range(5):
        A.box(pk - d * 1.06 + V((0, 0, -0.45 + k * 0.22)), (0.05, 2.0, 0.07), "metal", rot_z=rz,
              bevel=0.0)
    A.box(pk + V((0, 0, 0.9)), (2.1, 2.6, 0.12), "slate", rot_z=rz, bevel=0.0)
    for side in (-1, 1):
        f = P(-2.3, side * 1.42, 10.35)
        A.box(f, (1.6, 0.08, 1.3), "radiator", rot_z=rz, bevel=0.0)
        A.box(f + V((0, 0, 0.7)), (1.7, 0.16, 0.12), "metal", rot_z=rz, bevel=0.0)
    A.box(pk - d * 1.07 + V((0, 0, 0.75)), (0.06, 2.4, 0.18), "hazard", rot_z=rz, bevel=0.0)
    # sensor head on the turret
    sh = P(0.55, 1.2, 10.75)
    A.box(sh, (0.7, 0.6, 0.55), "dark", rot_z=rz, bevel=0.08)
    A.box(sh + d * 0.36, (0.05, 0.36, 0.22), "window_cool", rot_z=rz, bevel=0.0)
    A.cyl(sh + V((0, 0, 0.45)), 0.05, 0.03, 0.5, "metal", segs=5)
    # shoulder: yoke plates, axle, caps
    S = P(0.7, 0, 11.05)
    for side in (-1, 1):
        A.box(P(0.7, side * 0.98, 10.65), (1.6, 0.28, 1.5), "dark", rot_z=rz, bevel=0.06)
        A.cyl(S + sd * side * 1.17, 0.62, 0.62, 0.1, "ochre", segs=12,
              axis_rot=rot @ parts.ALONG_Y)
    A.cyl(S, 0.55, 0.55, 2.2, "dark", segs=12, axis_rot=rot @ parts.ALONG_Y)
    # upper boom: plated box section with seams, patch plates, a cable tray on top
    E = P(6.3, 0, 13.9)
    bd = (E - S).normalized()
    bup = (UP - bd * bd.dot(UP)).normalized()
    A.beam(S, E, 1.1, 1.0, "hull", up=bup)
    A.beam(S.lerp(E, 0.38), S.lerp(E, 0.68), 1.14, 1.04, "slate", up=bup)
    for t in (0.18, 0.38, 0.68, 0.88):
        A.beam(S.lerp(E, t - 0.015), S.lerp(E, t + 0.015), 1.18, 1.08, "dark", up=bup)
    A.beam(S.lerp(E, 0.1) + bup * 0.56, S.lerp(E, 0.92) + bup * 0.56, 0.5, 0.1, "dark", up=bup)
    for o in (-0.14, 0.12):
        pipe(A, S.lerp(E, 0.08) + bup * 0.66 + sd * o, E + bup * 0.66 + sd * o - bd * 0.3, 0.06,
             "metal" if o < 0 else "accent", segs=5)
    label("KEEP CLEAR", S.lerp(E, 0.53) + sd * 0.58, sd, bup, 0.34, INK_DARK)
    label("KEEP CLEAR", S.lerp(E, 0.53) - sd * 0.58, -sd, bup, 0.34, INK_DARK)
    # twin lift rams under the boom
    for side in (-0.42, 0.42):
        ram(P(1.55, side, 9.95), S.lerp(E, 0.56) - bup * 0.55 + sd * side, 0.21, 0.12)
    # elbow
    for side in (-1, 1):
        A.box(E + sd * side * 0.72, (1.3, 0.24, 1.3), "dark", rot_z=rz, bevel=0.06)
        A.cyl(E + sd * side * 0.9, 0.5, 0.5, 0.1, "ochre", segs=12, axis_rot=rot @ parts.ALONG_Y)
    A.cyl(E, 0.46, 0.46, 1.7, "dark", segs=12, axis_rot=rot @ parts.ALONG_Y)
    # forearm down to the wrist over the hold
    W = P(R_ARM, 0, 7.15)
    fd = (W - E).normalized()
    fup = (sd.cross(fd)).normalized()
    if fup.z < 0:
        fup = -fup
    A.beam(E + fd * 0.4, W, 0.82, 0.82, "hull2", up=fup)
    A.beam(E.lerp(W, 0.35), E.lerp(W, 0.6), 0.86, 0.86, "hull3", up=fup)
    for t in (0.2, 0.62, 0.86):
        A.beam(E.lerp(W, t - 0.015), E.lerp(W, t + 0.015), 0.92, 0.92, "dark", up=fup)
    ram(S.lerp(E, 0.7) + bup * 0.6, E.lerp(W, 0.32) + fup * 0.5, 0.17, 0.1)
    A.box(E.lerp(W, 0.32) + fup * 0.45, (0.4, 0.5, 0.3), "dark", rot_z=rz, bevel=0.05)
    pipe(A, E + fup * 0.5 - sd * 0.3, W + fup * 0.3 - sd * 0.3, 0.07, "accent", segs=5)
    for side in (-0.28, 0.28):   # work lights under the forearm, aimed at the hold
        c = E.lerp(W, 0.8) - fup * 0.46 + sd * side
        A.box(c, (0.3, 0.26, 0.2), "dark", rot_z=rz, bevel=0.0)
        A.box(c - fup * 0.11, (0.24, 0.2, 0.03), "flood", rot_z=rz, bevel=0.0)
    # wrist, rotary joint, grapple head
    A.cyl(W + V((0, 0, -0.25)), 0.5, 0.5, 0.9, "dark", segs=12)
    A.cyl(W + V((0, 0, -0.78)), 0.66, 0.66, 0.18, "ochre", segs=12)
    hc = V((W.x, W.y, 5.95))
    A.lathe([(0.0, 6.35), (0.95, 6.35), (1.15, 6.1), (1.15, 5.75), (0.75, 5.55), (0.0, 5.55)], 6,
            lambda i, j: ("hull2", "hull2", "hazard", "dark", "dark")[j],
            matrix=Matrix.Translation((hc.x, hc.y, 0)), start=rz)
    A.cyl(V((hc.x, hc.y, 5.4)), 0.55, 0.62, 0.3, "dark", segs=12)        # magnet pad
    A.box(V((hc.x, hc.y, 5.24)), (0.9, 0.9, 0.02), "cyan", rot_z=rz + math.pi / 4, bevel=0.0)
    for k in range(3):   # three articulated fingers
        a = rz + k * math.tau / 3 + math.pi / 3
        rd = V((math.cos(a), math.sin(a), 0))
        k0 = hc + rd * 1.0 + V((0, 0, -0.1))
        k1 = hc + rd * 1.5 + V((0, 0, -0.95))
        k2 = hc + rd * 0.85 + V((0, 0, -1.58))
        A.box(k0, (0.42, 0.42, 0.42), "dark", rot_z=a, bevel=0.1)
        A.beam(k0, k1, 0.3, 0.26, "metal", up=UP)
        A.box(k1, (0.36, 0.36, 0.36), "dark", rot_z=a, bevel=0.1)
        A.beam(k1, k2, 0.26, 0.22, "metal", up=UP)
        A.beam(k2 + (k1 - k2).normalized() * 0.25, k2, 0.27, 0.23, "hazard", up=UP)
        pipe(A, hc + rd * 0.6 + V((0, 0, 0.35)), k1 + rd * 0.12 + V((0, 0, 0.1)), 0.05, "metal",
             segs=4)
    for k in range(4):   # ore held under the pad
        A.rock(V((hc.x, hc.y, 0)) + V((0.42 * math.cos(k * 1.7), 0.42 * math.sin(k * 1.7), 4.55)),
               0.32, "ore", RNG)
    nav(A, P(-1.2, -1.0, 10.9), "nav_red", 0.35)


# ---------------------------------------------------------------- D. intake, E. belt
def build_intake():
    c = HOPPER
    prof = [(0.0, -4.0), (1.4, -4.0), (1.4, -2.8), (1.6, -2.6), (4.0, 1.5), (4.0, 1.8),
            (3.5, 1.8), (3.4, 1.5), (2.2, -0.4), (1.1, -2.4), (0.0, -2.4)]
    mm = {0: "dark", 1: "dark", 2: "dark", 3: "ochre", 4: "hull2", 5: "hull2", 6: "hazard",
          7: "orestain", 8: "rust", 9: "dark"}
    H.lathe(prof, 8, lambda i, j: mm[j], matrix=Matrix.Translation((c.x, c.y, 0)),
            start=math.pi / 8)
    for k in range(6):   # grizzly bars
        o = -2.0 + k * 0.8
        H.beam(V((c.x + o, c.y - 2.6, 0.2)), V((c.x + o, c.y + 2.6, 0.2)), 0.18, 0.22, "dark")
    for k in range(6):
        H.rock(V((c.x - 1.6 + k * 0.7, c.y + RNG.uniform(-1.5, 1.5), 0.45)), 0.28, "ore", RNG)
    for k in range(4):
        a = math.pi / 8 + k * math.pi / 2
        q = V((c.x + 3.7 * math.cos(a), c.y + 3.7 * math.sin(a), 0.8))
        H.beam(q, V((RAIL_X + 0.8, c.y + (k - 1.5) * 1.4, -0.6)) if math.cos(a) < 0 else
               V((q.x, q.y, -4.2)), 0.26, 0.26, "dark")
    H.box(V((c.x, BELT0.y + 0.6, -3.6)), (2.8, 2.2, 1.2), "hull2", bevel=0.05)   # chute hood
    H.box(V((c.x, c.y - 4.02, 1.25)), (1.6, 0.06, 0.45), "hull2", bevel=0.0)
    label("INTAKE", V((c.x, c.y - 4.06, 1.25)), V((0, -1, 0)), UP, 0.3, INK_DARK)
    for a in (math.radians(-112.5), math.radians(-67.5)):
        unload_beacon(V((c.x + 4.0 * math.cos(a), c.y + 4.0 * math.sin(a), 2.1)))
    SCORCH.append((c.x, c.y, 1.8, 2.4))


def belt_frame_basis():
    d = BELT1 - BELT0
    dn = d.normalized()
    ac = V((dn.y, -dn.x, 0)).normalized()
    return d, dn, ac


def build_belt_frame():
    d, dn, ac = belt_frame_basis()
    ln = d.length
    for sd in (-1, 1):
        H.beam(BELT0 + ac * sd * 1.45 - V((0, 0, 0.5)), BELT1 + ac * sd * 1.45 - V((0, 0, 0.5)),
               0.3, 0.6, "dark")
        H.beam(BELT0 + ac * sd * 1.35 + V((0, 0, 0.35)), BELT1 + ac * sd * 1.35 + V((0, 0, 0.35)),
               0.08, 0.5, "orestain")
    n = int(ln / 1.2)
    for k in range(n + 1):
        q = BELT0 + d * (k / n)
        H.tube(q - ac * 1.2 - V((0, 0, 0.25)), q + ac * 1.2 - V((0, 0, 0.25)), 0.12, 0.12, "metal",
               segs=6)
    for k in range(int(ln / 3.0) + 1):
        q = BELT0 + d * (k / max(int(ln / 3.0), 1))
        for sd in (-1, 1):
            strut(H, q + ac * sd * 1.45 - V((0, 0, 0.8)), q + ac * sd * 1.45 + V((0, 0, 1.2)), 0.12,
                  0.12, "dark")
        strut(H, q + ac * -1.45 + V((0, 0, 1.2)), q + ac * 1.45 + V((0, 0, 1.2)), 0.12, 0.12, "dark")
    mid = BELT0 + d * 0.5
    H.beam(mid - V((0, 0, 0.8)), V((mid.x, mid.y, KEEL_Z)) + V((-2.0, 0, 0)), 0.3, 0.3, "dark")
    H.beam(V((mid.x - 2.0, mid.y, KEEL_Z)), V((1.2, mid.y, KEEL_Z)), 0.3, 0.3, "dark")
    label("ORE", BELT0 + d * 0.35 + ac * 1.39 + V((0, 0, 0.35)), ac, UP, 0.32, INK_LIGHT)


def build_belt():
    """ore_conveyor_belt: troughed belt BELT0 -> BELT1, UV u across (0..1), v along in 4.8 m
    tiles (v = 0 at the intake). Same convention as before."""
    d, dn, ac = belt_frame_basis()
    up = UP
    sec = [(-1.2, 0.28), (-0.7, 0.02), (0.7, 0.02), (1.2, 0.28)]
    seg = [math.hypot(sec[i + 1][0] - sec[i][0], sec[i + 1][1] - sec[i][1]) for i in range(3)]
    tot = sum(seg)
    us = [0.0, seg[0] / tot, (seg[0] + seg[1]) / tot, 1.0]
    n = 6
    verts, uvs = [], []
    for k in range(n + 1):
        t = k / n
        base = BELT0 + d * t
        for (x, z), u in zip(sec, us):
            verts.append(base + ac * x + up * z)
            uvs.append((u, d.length * t / BELT_TILE))
    faces = [(k * 4 + i, k * 4 + i + 1, k * 4 + i + 5, k * 4 + i + 4)
             for k in range(n) for i in range(3)]
    me = bpy.data.meshes.new("ore_conveyor_belt")
    me.from_pydata([tuple(v) for v in verts], [], faces)
    uvl = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li, vi in zip(poly.loop_indices, poly.vertices):
            uvl.data[li].uv = uvs[vi]
    me.update()
    if me.polygons[1].normal.dot(up) < 0:
        for poly in me.polygons:
            poly.flip()
        me.update()
    if not all(os.path.exists(p) for p in BELT_TEX):
        import outpost_textures
        outpost_textures.bake_belt_tile()
    if all(os.path.exists(p) for p in BELT_TEX):
        mat = st.pbr_material("ore_belt", st.load_saved(BELT_TEX[0], False),
                              st.load_saved(BELT_TEX[1], True), st.load_saved(BELT_TEX[2], True))
    else:
        mat = common.make_material("ore_belt", (0.05, 0.05, 0.05), roughness=0.8)
    me.materials.append(mat)
    obj = bpy.data.objects.new("ore_conveyor_belt", me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


# ---------------------------------------------------------------- F. west side
def build_west():
    # fuel farm: two horizontal tanks along X on cradles off the -X rail
    for k, yy in enumerate((-11.2, -8.0)):
        c = V((-18.5, yy, -2.0))
        H.cyl(c, 1.5, 1.5, 6.4, "hull2", segs=14, axis_rot=parts.ALONG_X)
        for sx in (-1, 1):
            H.sphere(c + V((sx * 3.2, 0, 0)), 1.5, "mli_gold" if (k + (sx > 0)) % 2 else "mli_silver",
                     segs=14, rings=7, scale=(0.45, 1, 1))
            H.cyl(c + V((sx * 2.4, 0, 0)), 1.58, 1.58, 0.18, "dark", segs=14, axis_rot=parts.ALONG_X)
            H.box(c + V((sx * 1.6, 0, -1.4)), (0.4, 2.4, 0.6), "dark", bevel=0.0)
        H.cyl(c, 1.56, 1.56, 0.18, "dark", segs=14, axis_rot=parts.ALONG_X)
    truss(H, (-RAIL_X - 0.8, -9.6, -3.6), (-22.5, -9.6, -3.6), 1.6, 0.6, 4, "dark", chord=0.2,
          brace=0.1, diag=False)
    pipe(H, V((-15.0, -8.0, -0.4)), V((-RAIL_X - 0.6, -8.0, -0.4)), 0.12, "accent")
    pipe(H, V((-RAIL_X - 0.6, -8.0, -0.4)), V((-RAIL_X + 0.6, 1.0, 0.1)), 0.12, "accent")
    H.box(V((-18.5, -12.75, -2.0)), (1.6, 0.06, 0.6), "hull2", bevel=0.0)
    label("FUEL", V((-18.5, -12.8, -2.0)), V((0, -1, 0)), UP, 0.4, INK_DARK)
    # despatch rack: dark truss box, 2 tiers x 4 slots of typed ore canisters
    x0, x1, y0, y1, z0, z1 = -25.0, -14.0, -1.5, 2.5, -4.0, 3.0
    for zz in (z0, (z0 + z1) / 2, z1):
        for yy in (y0, y1):
            strut(H, V((x0, yy, zz)), V((x1, yy, zz)), 0.24, 0.24, "dark")
        for xx in (x0, x1):
            strut(H, V((xx, y0, zz)), V((xx, y1, zz)), 0.2, 0.2, "dark")
    for xx in (x0, -22.25, -19.5, -16.75, x1):
        for yy in (y0, y1):
            strut(H, V((xx, yy, z0)), V((xx, yy, z1)), 0.22, 0.22, "dark")
    slots = [("rust", "IRON"), ("rust", "IRON"), ("slate", "TITAN"), ("hull", "CRYSTAL"),
             ("slate", "TITAN"), ("rust", "IRON"), (None, None), (None, None)]
    for i, (body, txt) in enumerate(slots):
        col, tier = i % 4, i // 4
        cx = x0 + 1.375 + col * 2.75
        cz = z0 + 1.75 + tier * 3.5
        c = V((cx, (y0 + y1) / 2, cz))
        H.box(c - V((0, 0, 1.2)), (2.5, 4.0, 0.2), "dark", bevel=0.0)   # cradle
        if body is None:
            for sy in (-1, 1):
                H.box(c + V((0, sy * 1.6, -0.8)), (2.0, 0.3, 0.6), "hazard", bevel=0.0)
            continue
        wk.cargo_pod(H, c, (2.0, 3.4, 2.2), rot_z=0.0, body=body, band="accent", frame="dark")
        H.box(c + V((0, -1.72, 0.3)), (1.4, 0.06, 0.45), "hull2", bevel=0.0)
        label(txt, c + V((0, -1.76, 0.3)), V((0, -1, 0)), UP, 0.28, INK_DARK)
        if txt == "CRYSTAL":
            L.box(c + V((1.02, 0, 0)), (0.06, 2.6, 0.12), "cyan", bevel=0.0)
    label("ORE", V((-21.0, y0 - 0.14, z0 + 0.3)), V((0, -1, 0)), UP, 0.35, INK_LIGHT)
    hood = V((-19.5, y1 + 0.6, z1 + 0.5))
    H.box(hood, (3.0, 1.6, 1.2), "hull3", bevel=0.08)
    for sx in (-1, 1):
        H.cyl(hood + V((sx * 0.8, -0.9, -0.6)), 0.25, 0.2, 0.8, "ochre", segs=8)
    # outbound jib towards the shuttle berth
    j0, j1 = V((-24.5, y0, z1)), V((-26.0, -13.0, z1))
    truss(H, j0, j1, 1.0, 1.0, 5, "dark", chord=0.18, brace=0.1)
    H.box(j1 + V((0, -0.4, -0.3)), (2.2, 0.8, 0.4), "ochre", bevel=0.0)
    for sx in (-1, 1):
        H.box(j1 + V((sx * 1.0, -0.4, 0.2)), (0.25, 0.8, 0.8), "ochre", bevel=0.0)
        L.box(j1 + V((sx * 1.0, -0.82, 0.45)), (0.16, 0.06, 0.16), "green", bevel=0.0)
    H.box(j1 + V((0, -0.83, -0.3)), (1.6, 0.06, 0.4), "hull2", bevel=0.0)
    label("OUTBOUND", j1 + V((0, -0.87, -0.3)), V((0, -1, 0)), UP, 0.22, INK_DARK)
    SCORCH.append((j1.x, j1.y - 0.4, j1.z, 1.0))


# ---------------------------------------------------------------- unload lights + assembly
def build_unload_lights():
    bm = bmesh.new()
    for c in BEACONS:
        bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=4, radius=0.35,
                                  matrix=Matrix.Translation(c + V((0, 0, 0.1))))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new("unload_lights")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(MATS["amber"])
    obj = bpy.data.objects.new("unload_lights", me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def set_origin(obj, pivot):
    obj.data.transform(Matrix.Translation(-V(pivot)))
    obj.location = V(pivot)


def build_outpost():
    global H, L, A, F
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    BEACONS.clear()
    H = parts.PanelPart(f"{PRE}_hull", MATS)
    L = parts.PanelPart(f"{PRE}_lights", MATS)
    A = parts.PanelPart("unload_arm", MATS)
    F = parts.PanelPart("ore_silo_fill", MATS)
    for b in (build_cradle, build_spine, build_bunker, build_fill, build_radiators, build_crane,
              build_intake, build_belt_frame, build_west):
        b()
    root = parts.make_root(PRE, size=10)
    hull, lights, arm, fill = (p.finish(root) for p in (H, L, A, F))
    lights.data.uv_layers.remove(lights.data.uv_layers["panel"])
    belt = build_belt()
    ul = build_unload_lights()
    for o in (belt, ul):
        o.parent = root
    return root, hull, lights, arm, fill, belt, ul


# ---------------------------------------------------------------- checks
def import_glb(path, loc, rot_z=0.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    r = next(o for o in new if o.parent is None)
    r.location = loc
    r.rotation_mode = "XYZ"
    r.rotation_euler = (0, 0, rot_z)
    return r, new


def bvh_of(obj, extra=Matrix()):
    dg = bpy.context.evaluated_depsgraph_get()
    bm = bmesh.new()
    bm.from_object(obj, dg)
    bm.transform(extra @ obj.matrix_world)
    t = BVHTree.FromBMesh(bm)
    bm.free()
    return t


def check(hull, arm, lights):
    """Geometry asserts: swing math, hauler clearances (with +-0.5 z bob), arm sweep."""
    ang = math.atan2(HOPPER.y - PIVOT.y, HOPPER.x - PIVOT.x) - SWING
    hold = V((PIVOT.x + R_ARM * math.cos(ang), PIVOT.y + R_ARM * math.sin(ang)))
    assert (hold - HOLD.xy).length < 1e-3, hold
    print(f"GEOM hold {tuple(round(c, 2) for c in HOLD)} pivot {tuple(PIVOT)} hopper "
          f"{HOPPER.x:.3f},{HOPPER.y:.3f} r_arm {R_ARM:.3f} a_hold {math.degrees(A_HOLD):.2f}")
    if not os.path.exists(HAULER_GLB):
        print("CHECK no hauler glb, clearance skipped")
        return 0
    bpy.context.view_layer.update()
    statics = [bvh_of(o) for o in (hull, arm, lights)]
    bad = 0
    for loc in [(sx * BERTH_X, BERTH_Y, 0.0) for sx in (-1, 1)] + \
               [(sx * OUTER_X, OUTER_Y, 2.0) for sx in (-1, 1)]:
        r, new = import_glb(HAULER_GLB, loc, math.pi)
        bpy.context.view_layer.update()
        meshes = [o for o in new if o.type == "MESH"]
        for bob in (-0.5, 0.0, 0.5):
            for m in meshes:
                t = bvh_of(m, Matrix.Translation((0, 0, bob)))
                for name, s in zip(("hull", "arm", "lights"), statics):
                    hits = s.overlap(t)
                    if hits:
                        bad += 1
                        print(f"CHECK overlap hauler@{loc} bob {bob} {m.name} vs {name}: {len(hits)}")
        for o in new:
            bpy.data.objects.remove(o, do_unlink=True)
    # arm sweep against the static hull above the slewing ring
    for k in range(9):
        a = SWING * k / 8
        rot = Matrix.Translation(PIVOT) @ Matrix.Rotation(a, 4, "Z") @ Matrix.Translation(-PIVOT)
        t = bvh_of(arm, rot)
        hits = [h for h in statics[0].overlap(t)]
        if hits:
            print(f"CHECK arm sweep step {k}: {len(hits)} face pairs touch the hull")
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


def previews(ships, compare):
    ul = bpy.data.objects.get("unload_lights")
    if ul:   # hidden in game while idle
        ul.hide_render = True
    if ships and os.path.exists(HAULER_GLB):
        for sx in (-1, 1):
            import_glb(HAULER_GLB, (sx * BERTH_X, BERTH_Y, 0.0), math.pi)
        import_glb(HAULER_GLB, (OUTER_X, OUTER_Y, 2.0), math.pi)
        if os.path.exists(SHUTTLE_GLB):
            import_glb(SHUTTLE_GLB, (-26.0, -44.0, 3.0), math.pi)
    common.setup_preview(cam_loc=(-45, -71, 80), cam_target=(0, 4, 0), ortho_scale=95,
                         res=(1600, 1200), key_dir=(-0.6, -0.35, 0.7), key_energy=3.5)
    dim_emission()
    scene = bpy.context.scene
    cam = scene.camera
    shots = []
    a = os.path.join(common.PREVIEW_DIR, f"{PRE}_preview.png")
    common.render(a)
    shots.append(a)
    cam.location = (0, 4, 200)
    cam.rotation_euler = (0, 0, 0)
    cam.data.ortho_scale = 80
    scene.render.resolution_x, scene.render.resolution_y = 1200, 1200
    b = os.path.join(common.PREVIEW_DIR, f"{PRE}_top.png")
    common.render(b)
    shots.append(b)
    # game pitch views (RTS camera: fov 50 vertical)
    cam.data.type = "PERSP"
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle_y = math.radians(50)
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    for pitch, dist, tag in ((42, 120, "game42"), (58, 260, "game58")):
        tgt = V((0, 2, 0))
        pr = math.radians(pitch)
        cam.location = tgt + V((0, -math.cos(pr) * dist, math.sin(pr) * dist))
        cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
        c = os.path.join(common.PREVIEW_DIR, f"{PRE}_{tag}.png")
        common.render(c)
        shots.append(c)
    cam.data.sensor_fit = "AUTO"
    cam.data.lens = 35
    cam.location = (40.0, -30.0, 18.0)
    tgt = V((17.0, -2.0, 2.0))
    cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
    d = os.path.join(common.PREVIEW_DIR, f"{PRE}_closeup.png")
    common.render(d)
    shots.append(d)
    cam.location = (28.0, -20.0, 17.0)
    tgt = V((11.0, -1.0, 8.5))
    cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
    d2 = os.path.join(common.PREVIEW_DIR, f"{PRE}_crane.png")
    common.render(d2)
    shots.append(d2)
    if compare and os.path.exists(STATION_GLB):
        r, new = import_glb(STATION_GLB, (-110.0, 0.0, 0.0))
        for mm in {s.material for o in new if o.type == "MESH" for s in o.material_slots}:
            if mm and mm.node_tree:
                bb = next((n for n in mm.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
                if bb:
                    bb.inputs["Emission Strength"].default_value *= 0.35
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = 230
        cam.location = (-50.0, -150.0, 150.0)
        cam.rotation_euler = (V((-50.0, 0, 0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.resolution_x, scene.render.resolution_y = 2400, 1200
        e = os.path.join(common.PREVIEW_DIR, f"{PRE}_compare.png")
        common.render(e)
        shots.append(e)
    print("PREVIEWS " + " ".join(shots))


def main():
    argv = parts.script_args(sys.argv)
    res = 4096
    for a in argv:
        if a.startswith("--res="):
            res = int(a.split("=")[1])
    common.reset_scene()
    root, hull, lights, arm, fill, belt, ul = build_outpost()
    if "--check" in argv:
        check(hull, arm, lights)
        return
    if "--no-textures" not in argv:
        wk.texture([hull, arm, fill], MATS, PRE, NO_PADS, scorch=SCORCH, decals=DECALS,
                   labels=LABELS, seed0=61, res=res)
    else:
        for o in (hull, arm, fill):
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    set_origin(arm, PIVOT)
    set_origin(fill, V((BUNKER_C.x, BUNKER_C.y, BUNKER_FLOOR)))
    set_origin(belt, BELT0)
    for name, pos, rz in (("dock_point", DOCK_POS, math.pi), ("spawn_point", SPAWN_POS, math.pi)):
        parts.add_empty(name, root, pos, rot_z=rz, size=4)
    e = parts.add_empty("ore_flow_point", root, V((HOPPER.x, HOPPER.y, FLOW_Z)), size=2)
    e.empty_display_type = "PLAIN_AXES"
    wk.stats([hull, lights, arm, fill, belt, ul])
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        previews("--no-ships" not in argv, "--no-compare" not in argv)


main()
