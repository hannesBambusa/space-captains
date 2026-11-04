"""Generate the scavenger hideout "Breaker's Hulk" (.glb + previews).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_scavenger_den.py
  Options after `--`: --no-preview, --no-textures (flat materials, no Cycles bake),
  --rts=/abs/out.png (extra RTS-camera render with a scavenger raider for scale; after
  the export, never in the .glb).
Textures: one 2048 worn atlas (worn_kit / station_textures.WORN_KINDS plus the local
kinds "olive" and "junk" copied from gen_scavenger_ship.py and "scavred", oxide claim
paint), saved as blender/textures/scavenger_den_*.jpg and embedded as JPEG. The den
carries its own colour (no faction_paint material). Lamps, windows, the hangar glow, the
welding arc and the molten metal are flat emissive materials.

Design: the scavengers took a dead bulk ore carrier (registry OKV-2207, crossed out in
oxide paint) and turned it into a ship-breaking yard that eats its host. The bow was
torched off and sits beside the hulk in a yellow breaking cradle, stripped back to its
ribs, with a torch carriage still cutting the next ring under a white-blue arc. Cut
plate rides a conveyor up to a shredder and a magnetic sorter on the spine, then into an
open induction crucible whose molten mouth is the orange eye seen from above; ingots
stack beside it. The opened forward cargo hold is the launch hangar, held rigid by a
welded breach collar with a red-lit mouth. Part of the hold roof is cut away so a
salvaged docking manipulator can lower stolen containers into the hold. Three oxide claw
slashes are welded on the roof. Loot sits in mismatched containers in a girder rack on
the port flank. The carrier's fusion plant in the stern still runs, dumping heat through
six mismatched radiator panels; its cut-off starboard drive bell hangs on a tether. The
crew lives in an olive hab can on the starboard shoulder, and caged propellant spheres
feed the hangar fuel line. Five point-defence mounts, each torn off a different ship
(twin autocannons and rotary PDCs), sit on welded scrap pedestals.

Layout (Blender Z up, exported +Y up; Blender -Y = Godot +Z). The hulk runs along
Blender Y with its open hold toward -Y. Play plane z = 0.
  hold + collar   x -13..13, y -31..-4, z -10..10; roof breach x -8..8, y -17..-4
  apron           x -10.3..10.3, y -41..-30, top z -8
  midship         y -4..18 (24 x 18 m), engineering y 18..32 (22 x 17 m), drive taper
                  y 32..40, port bell to y 45.6
  radiator wings  x -36..36 at y 20.5..30.5, z ~3
  bow chunk       centre (30, -14, -3), yaw -122 deg, footprint x 14.8..45.2,
                  y -29..1.3 (with its cradle)
  spine plant     shredder (3.5, -0.5), crucible (0, 10.5) rim z 20, stack z 27,
                  mast (-4.5, 36.5) to z 29.6, hab can x 7.6..14.8, y 4..21
  loot rack       x -19.7..-13.3, y -24..16
  overall         about 87 x 88 x 43 m
Hierarchy: scavenger_den (empty root)
  -> den_hull (the hulk and everything that stays as the burnt ruin),
     den_salvage (hidden when destroyed: containers, manipulator, mast, cables, tethered
       bell, conveyor belt, torch, molten metal, ingots, every window),
     den_hangar_glow (hangar mouth trim, floor guides, ceiling strips, airlock, bulkhead
       bar; material den_hangar_glow, pulsed by Godot),
     den_lights (only the small red blobs plus the white-blue torch arc and sparks,
       flickered by Godot),
     den_turret_1..5 (origin on the slewing ring, rotated to the gun heading; they stay
       and burn with the hull),
     spawn_point (empty), den_gun_1..5 (empties).
Hooks: spawn_point at (0, -35, 0), rotated 180 deg about up, so its Godot -Z points out
of the mouth (Blender -Y). den_gun_k sit at the muzzle tips with rot_z = the turret yaw,
so their Godot -Z runs along the barrels: 1 and 2 twin autocannons on the front
shoulders, 3 rotary PDC aft dorsal, 4 rotary PDC on the port rack, 5 twin autocannon on
the cradle deck (starboard).
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

PRE = "scavenger_den"
OUT = os.path.join(common.ROOT, "assets", "models", "buildings", "scavenger_den.glb")
BLEND = os.path.join(common.ROOT, "blender", "scavenger_den.blend")
SHIP_GLB = os.path.join(common.ROOT, "assets", "models", "ships", "scavenger.glb")
SEED = 8821
RNG = random.Random(SEED)
CUT_Y = -30.0
FLOOR_Z = -7.4
STERN_Y = 40.0
SPAWN_POS = (0.0, -35.0, 0.0)
CHUNK_C = V((30.0, -14.0, -3.0))
CHUNK_YAW = -2.13
TURRET_S = 1.3
LABELS = ["OKV-2207", "#CHEV", "#BAR", "HOLD 3", "CLAIMED", "REACTOR", "KEEP CLEAR"]
RED_INK = (0.40, 0.05, 0.03)

# Turrets: (type, base, yaw). Heading = (-sin yaw, cos yaw).
TURRETS = [("A", (-10.5, -28.0, 10.5), 2.618),
           ("A", (10.5, -28.0, 10.5), -2.618),
           ("B", (0.0, 34.2, 10.4), 0.0),
           ("B", (-16.5, 15.5, 4.3), 1.223),
           ("A", (39.08, -3.65, 7.8), -1.329)]

# Worn kinds copied from gen_scavenger_ship.py (not imported: it runs on import).
OLIVE = dict(big=(2.2, 1.6), plate=(1.1, 0.8),
             tones=[(0.105, 0.115, 0.05), (0.09, 0.10, 0.045), (0.12, 0.125, 0.06),
                    (0.08, 0.085, 0.045), (0.115, 0.11, 0.055), (0.095, 0.105, 0.06)],
             plate_var=0.18, rough=(0.78, 0.12), metal=0.15, seam_big=0.35,
             seam_small=0.18, rivets=True, hatches=0.0, chip=(0.16, 0.075, 0.035),
             chip_metal=0.4, chip_k=1.6, grime_k=1.3, streak_k=0.6, bleach=0.15)
JUNK = dict(big=(1.2, 0.9), plate=(0.6, 0.45),
            tones=[(0.22, 0.09, 0.04), (0.11, 0.12, 0.06), (0.17, 0.15, 0.12),
                   (0.08, 0.075, 0.07), (0.20, 0.14, 0.05), (0.14, 0.065, 0.035)],
            plate_var=0.22, rough=(0.72, 0.18), metal=0.3, seam_big=0.4,
            seam_small=0.2, rivets=True, hatches=0.0, chip=(0.24, 0.22, 0.2),
            chip_metal=0.85, chip_k=1.7, grime_k=1.3, streak_k=0.5, bleach=0.1)
# Oxide claim paint, heavily chipped back to rust: the faction accent.
SCAVRED = dict(big=(3, 2), plate=(1.5, 1),
               tones=[(0.36, 0.055, 0.03), (0.30, 0.045, 0.025), (0.40, 0.07, 0.035),
                      (0.27, 0.05, 0.03), (0.34, 0.06, 0.03), (0.31, 0.05, 0.028)],
               plate_var=0.08, rough=(0.66, 0.1), metal=0.0, seam_big=0.35,
               seam_small=0.12, rivets=False, hatches=0.0, chip=(0.15, 0.07, 0.035),
               chip_metal=0.4, chip_k=1.9, grime_k=1.1, streak_k=0.55, bleach=0.3)
st.WORN_KINDS.setdefault("olive", OLIVE)
st.WORN_KINDS.setdefault("junk", JUNK)
st.WORN_KINDS.setdefault("scavred", SCAVRED)
# The carrier's own warm grey, darker and dirtier than the station hull3 after decades
# dead in the belt. Replaces hull3 in this process only (station_textures is untouched),
# so the hulk keeps the decal-carrying hull3 key.
HULK3 = dict(st.WORN_KINDS["hull3"])
HULK3.update(tones=[(0.150, 0.140, 0.118), (0.132, 0.125, 0.108), (0.165, 0.150, 0.122),
                    (0.118, 0.114, 0.104), (0.145, 0.132, 0.105), (0.126, 0.122, 0.112)],
             plate_var=0.12, chip_k=1.7, grime_k=1.9, streak_k=1.0, bleach=0.05)
st.WORN_KINDS["hull3"] = HULK3

MATS = {}
DECALS = []
SCORCH = []
H = S = G = L = None

CR = Matrix.Rotation(CHUNK_YAW, 4, "Z")
CM = Matrix.Translation(CHUNK_C) @ CR

# Drive bell profile (r, local z), pointing +Y through ALONG_Y.
BELL = [(0, 0), (1.6, 0), (1.7, 0.8), (2.4, 2.2), (3.2, 3.8), (3.8, 5.0), (3.5, 5.0),
        (2.9, 3.8), (2.1, 2.2), (1.4, 0.9), (0, 0.9)]


def bell_mat(i, j):
    return "metal" if j < 5 else "dark"


def cp(x, y, z):
    """Point in the bow chunk frame -> world."""
    return CM @ V((x, y, z))


# ---------------------------------------------------------------- materials, helpers
def build_materials():
    wk.build_materials(PRE, MATS, extra=("rust",))
    m = common.make_material
    MATS["olive"] = m(f"{PRE}_olive", (0.10, 0.11, 0.05), roughness=0.8, metallic=0.2)
    MATS["junk"] = m(f"{PRE}_junk", (0.13, 0.115, 0.095), roughness=0.75, metallic=0.4)
    MATS["scavred"] = m(f"{PRE}_scavred", (0.36, 0.055, 0.03), roughness=0.66)
    base = (0.03, 0.02, 0.015)
    MATS["window"] = m("scav_den_window_red", base, roughness=0.25,
                       emission=(1.0, 0.22, 0.05), emission_strength=4.0)
    MATS["window_dim"] = m("scav_den_window_dim", base, roughness=0.25,
                           emission=(1.0, 0.18, 0.04), emission_strength=2.0)
    MATS["red"] = m("scav_den_light_red", base, roughness=0.3,
                    emission=(1.0, 0.06, 0.02), emission_strength=7.0)
    MATS["arc"] = m("scav_den_arc", base, roughness=0.3,
                    emission=(0.75, 0.86, 1.0), emission_strength=12.0)
    MATS["molten"] = m("scav_den_molten", (1.0, 0.45, 0.1), roughness=0.3,
                       emission=(1.0, 0.42, 0.06), emission_strength=9.0)
    MATS["glow"] = m("den_hangar_glow", base, roughness=0.3,
                     emission=(1.0, 0.12, 0.035), emission_strength=6.5)
    for k in ("window", "window_dim", "red", "arc", "molten", "glow", "glass"):
        MATS[k].use_backface_culling = False


def label(text, centre, normal, up, h, colour, opacity=0.85):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity))


def lamp(pos, s=0.7, mat="red"):
    L.box(V(pos), (s, s, s), mat, bevel=0.0)


def _key(mat, j):
    return mat(j) if callable(mat) else mat


def oct_shell(p, y0, y1, w, h, c, t, mat, skip=(), M=None):
    """Chamfered-rectangle shell along Y (one plate per octagon edge, plates t thick
    inside the outline w x h, chamfer c). Edge j: 0 = +X side, 1 = top-right chamfer,
    2 = top, 3 = top-left chamfer, 4 = -X side, 5..7 = bottom. M places it in a frame."""
    P = oct_ring(0.0, w, h, c)
    ym = (y0 + y1) / 2
    for j in range(8):
        if j in skip:
            continue
        a, b = P[j], P[(j + 1) % 8]
        ex, ez = b.x - a.x, b.z - a.z
        ln = math.hypot(ex, ez)
        n = V((ez / ln, 0, -ex / ln))
        ctr = V(((a.x + b.x) / 2, ym, (a.z + b.z) / 2)) - n * t / 2
        r = Matrix(((ex / ln, 0, -ez / ln), (0, 1, 0), (ez / ln, 0, ex / ln))).to_4x4()
        if M is not None:
            ctr = M @ ctr
            r = M.to_3x3().to_4x4() @ r
        p.box(ctr, (ln + 0.8 * t, y1 - y0, t), _key(mat, j), r=r, bevel=0.04)


def girder(p, a, b, w, h, n, mat="dark", chord=0.45, brace=0.25):
    """Open box girder from a to b (w across, h up), n bays of X-braced frames."""
    a, b = V(a), V(b)
    x = (b - a).normalized()
    side = x.cross(V((0, 0, 1))).normalized()
    up = side.cross(x).normalized()
    cs = [side * sx * w / 2 + up * sz * h / 2 for sx in (-1, 1) for sz in (-1, 1)]
    for c in cs:
        parts.strut(p, a + c, b + c, chord, chord, mat)
    for k in range(n):
        p0 = a.lerp(b, k / n)
        p1 = a.lerp(b, (k + 1) / n)
        for sz in (-1, 1):
            parts.strut(p, p0 + side * w / 2 + up * sz * h / 2, p1 - side * w / 2 + up * sz * h / 2,
                        brace, brace, mat)
        for sx in (-1, 1):
            parts.strut(p, p0 + side * sx * w / 2 - up * h / 2, p1 + side * sx * w / 2 + up * h / 2,
                        brace, brace, mat)
        parts.strut(p, p1 + side * w / 2 + up * h / 2, p1 - side * w / 2 + up * h / 2, brace,
                    brace, mat)
    for c in (a, b):   # end frames
        parts.strut(p, c + side * w / 2 + up * h / 2, c - side * w / 2 + up * h / 2, brace,
                    brace, mat)
        parts.strut(p, c + side * w / 2 - up * h / 2, c - side * w / 2 - up * h / 2, brace,
                    brace, mat)


def cable(p, a, b, sag, r=0.12, n=6, mat="dark"):
    """Sagging cable as a chain of open pipes (sag along -Z)."""
    a, b = V(a), V(b)
    pts = []
    for k in range(n + 1):
        t = k / n
        q = a.lerp(b, t)
        q.z -= sag * 4 * t * (1 - t)
        pts.append(q)
    for q0, q1 in zip(pts, pts[1:]):
        parts.pipe(p, q0, q1, r, mat, segs=5)


def axis_q(d):
    return V(d).normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()


def line_frame(a, b):
    """Rotation with columns (across, along a->b, up)."""
    d = (V(b) - V(a)).normalized()
    side = d.cross(V((0, 0, 1))).normalized()
    up = side.cross(d).normalized()
    return Matrix((side, d, up)).transposed().to_4x4()


# ---------------------------------------------------------------- 1. hold, collar, slashes
def build_hold():
    def front_mats(j):
        return "scavred" if j in (1, 3) else ("hull3" if j in (0, 2, 4) else "hull2")

    def hold_mats(j):
        return "hull3" if j <= 4 else "hull2"
    oct_shell(H, -30, -24, 24, 18, 4, 0.9, front_mats)
    oct_shell(H, -24, -17, 24, 18, 4, 0.9, hold_mats)
    oct_shell(H, -17, -4, 24, 18, 4, 0.9, hold_mats, skip=(2,))
    # breach collar: the welded mouth frame
    oct_shell(H, -31, -29, 26, 20, 4.6, 1.9, "dark")
    H.box((0, -31.1, 9.05), (12, 0.2, 1.2), "scavred", bevel=0.02)
    for s in (-1, 1):
        H.box((s * 12.05, -31.1, 0), (1.2, 0.2, 8), "scavred", bevel=0.02)
    H.hazard(-8, 8, 1.0, 0, 0.08, matrix=Matrix.Translation((0, -31.0, -9.0)) @ parts.FRONT,
             cols=("hazard", "dark"), pitch=1.4)
    for a, b in zip(oct_ring(-29, 26, 20, 4.6), oct_ring(-25, 24.2, 18.2, 4.1)):
        H.beam(a, b, 0.8, 0.8, "dark")
    for y in (-24, -17):
        oct_shell(H, y - 0.3, y + 0.3, 24.7, 18.7, 4.3, 0.6, "dark")
    # roof breach: coaming and the cut roof grid, gap y -13.4..-6.6 left open
    for s in (-1, 1):
        H.beam((s * 8.2, -17, 9.2), (s * 8.2, -4, 9.2), 0.6, 0.6, "hazard")
        H.beam((s * 4, -17, 8.5), (s * 4, -4, 8.5), 0.6, 0.6, "dark")
        parts.rcs_quad(H, (s * 10.4, -21, 7.4), (s, 0, 1), "dark", "metal", s=1.3)
    for y in (-16, -14, -6):
        H.beam((-8, y, 8.5), (8, y, 8.5), 0.6, 0.9, "dark")
    # three oxide claw slashes welded on the forward roof, leaning toward the aft
    for xc in (-4.0, 0.0, 4.0):
        pts = [(xc - 2.3, -29.0), (xc - 0.7, -29.0), (xc + 2.3, -20.2), (xc + 0.7, -20.2)]
        H.slab(pts, 9.0, 9.14, "scavred")
    SCORCH.append((0.0, -31.0, 0.0, 5.0))


# ---------------------------------------------------------------- 2. hangar interior
def build_hangar():
    for y in (-26, -22.5, -19, -15.5, -12, -8.5):
        oct_shell(H, y - 0.35, y + 0.35, 22.2, 16.2, 3.4, 0.9, "dark")
    H.box((0, -17.5, -7.6), (20, 25, 0.4), "pad", bevel=0.02)
    for s in (-1, 1):
        for y in (-20, -14):
            H.box((s * 4.2, y, -6.4), (1.6, 2.4, 2.0), "metal", bevel=0.06)
        H.beam((s * 5, -29, 7.2), (s * 5, -6, 7.2), 0.8, 1.0, "dark")
    parts.prism(H, -4.9, -4.1, (22.4, 16.4, 3.5), (22.4, 16.4, 3.5), "hull2")   # aft bulkhead
    H.box((0, -5.7, 3.2), (12, 1.6, 3), "hull2", bevel=0.05)                    # ops booth
    H.box((0, -5.15, -4.4), (8, 0.5, 6.2), "dark", bevel=0.03)                  # airlock frame
    # loose kit (den_salvage)
    S.box((0, -14, 6.4), (11.6, 2, 1), "hazard", bevel=0.05)
    S.cyl((0, -14, 3.5), 0.12, 0.12, 5, "dark", segs=6)
    S.box((0, -14, 0.8), (1.2, 1.2, 1), "dark", bevel=0.08)
    S.box((0, -6.55, 3.4), (10, 0.1, 1.1), "window", bevel=0)
    # hangar glow
    P = oct_ring(-31, 22.2, 16.2, 3.4)
    for j in range(8):
        a, b = P[j], P[(j + 1) % 8]
        ex, ez = b.x - a.x, b.z - a.z
        ln = math.hypot(ex, ez)
        n = V((ez / ln, 0, -ex / ln))
        ctr = V(((a.x + b.x) / 2, -31.06, (a.z + b.z) / 2)) + n * 0.3
        r = Matrix(((ex / ln, 0, -ez / ln), (0, 1, 0), (ez / ln, 0, ex / ln))).to_4x4()
        G.box(ctr, (ln - 0.6, 0.12, 0.35), "glow", r=r, bevel=0)
    for s in (-1, 1):
        G.box((s * 6.5, -17.5, -7.33), (0.35, 23, 0.06), "glow", bevel=0)
    for y in (-28, -24, -20, -16, -12, -8):
        G.box((0, y, -7.33), (1.6, 0.5, 0.06), "glow", bevel=0)
    for y in (-28, -24, -20):
        G.box((0, y, 7.9), (16, 0.6, 0.08), "glow", bevel=0)
    G.box((0, -5.45, -4.6), (6.4, 0.12, 4.6), "glow", bevel=0)
    G.box((0, -4.97, 6.6), (18, 0.12, 0.8), "glow", bevel=0)


# ---------------------------------------------------------------- 3. launch apron
def build_apron():
    for s in (-1, 1):
        H.beam((s * 7, -29.5, -8.9), (s * 7, -41, -8.9), 1.0, 1.2, "dark")
    for x, jr, jz in ((-6.8, 0.02, 0.03), (0.0, -0.015, -0.04), (6.8, 0.01, 0.02)):
        H.box((x, -35.5, -8.2 + jz), (7.0, 10.5, 0.4), "pad", r=rot(rz=jr), bevel=0.02)
    H.hazard(-10.5, 10.5, 0.9, 0, 0.08, matrix=Matrix.Translation((0, -40.6, -8.0)),
             cols=("hazard", "dark"), pitch=1.4)
    SCORCH.append((0.0, -33.0, -8.0, 4.0))


# ---------------------------------------------------------------- 4. midship + engineering
def hull_mats(i, j):
    return "hull2" if j == 6 else ("dark" if j in (5, 7) else "hull3")


def build_midship():
    parts.prism(H, -4, 18, (24, 18, 4), (24, 18, 4), "hull3", mat_fn=hull_mats)
    for y in (1.5, 12.5):   # belts, starboard top chamfer left out under the hab can
        oct_shell(H, y - 0.3, y + 0.3, 24.7, 18.7, 4.3, 0.6, "dark", skip=(1,))
    oct_shell(H, 7.0, 10.5, 24.12, 18.12, 4.05, 0.3, lambda j: "hull" if j <= 4 else "hull2")
    oct_shell(H, 17.4, 18.6, 25, 19, 4.4, 1.5, "dark", skip=(1,))
    parts.prism(H, 18, 32, (22, 17, 4), (22, 17, 4), "hull3", mat_fn=hull_mats)
    oct_shell(H, 31.6, 32.4, 22.8, 17.8, 4.3, 0.9, "dark")
    parts.prism(H, 32, STERN_Y, (22, 17, 4), (16, 13, 3.5), "hull3", mat_fn=hull_mats)
    # scavenger patch plates on the roof
    keep_out_box = [(-0.5, 7.5, -4, 3), (-4.7, -1.7, -3.5, -0.5), (-7.7, -5.1, 12.9, 15.5),
                    (-4.5, 7, 15.4, 17), (-2, 7, 20, 30), (-8.3, -3.8, 5.5, 11.5)]
    keep_out_r = [((0, 10.5), 5.6), ((4.2, 14.6), 1.5), ((-5.8, 21.5), 3.0),
                  ((-5.8, 28.5), 3.0), ((0, 34.2), 3.6), ((-4.5, 36.5), 2.0)]
    mats = ("rust", "junk", "olive", "rust", "scavred")
    placed = 0
    for _ in range(400):
        if placed >= 18:
            break
        w, ln = RNG.uniform(2, 5), RNG.uniform(1.5, 4)
        x, y = RNG.uniform(-7, 7), RNG.uniform(-3, 31)
        rz = RNG.uniform(-0.12, 0.12)
        mat = RNG.choice(mats)
        if any(x0 <= x <= x1 and y0 <= y <= y1 for x0, x1, y0, y1 in keep_out_box):
            continue
        if any(math.hypot(x - cx, y - cy) < r for (cx, cy), r in keep_out_r):
            continue
        if y - ln / 2 < 18.8 and y + ln / 2 > 16.9:   # step collar
            continue
        if y > 31 - ln / 2:
            continue
        hw = 7.0 if y < 18 else 6.5
        if abs(x) + w / 2 > hw:
            continue
        top = 9.0 if y < 18 else 8.5
        H.box((x, y, top + 0.1), (w, ln, 0.25), mat, rot_z=rz, bevel=0.1)
        placed += 1
    placed = 0
    for _ in range(400):
        if placed >= 14:
            break
        s = RNG.choice((-1, 1))
        y = RNG.uniform(-29, 31)
        ln, hz = RNG.uniform(2, 5), RNG.uniform(1.5, 3.5)
        z = RNG.uniform(-3.5, 3.5)
        mat = RNG.choice(mats)
        rx = RNG.uniform(-0.1, 0.1)
        y0, y1 = y - ln / 2, y + ln / 2
        if y0 < -29.5 or y1 > 31.5 or (y0 < 18.8 and y1 > 16.9):
            continue
        if abs(z) + hz / 2 > (4.6 if y < 18 else 4.1):
            continue
        if s < 0 and not (-29 <= y0 and y1 <= -25 or 16 <= y0 and y1 <= 31):
            continue
        if y > 18 and (y0 < 27.5 and y1 > 22.5):   # boom roots, CLAIMED stencil
            continue
        if y > 18 and z + hz / 2 > 1.8:              # portholes
            continue
        if s > 0 and y0 < 11.5 and y1 > 6 and z - hz / 2 < 1.5 and z + hz / 2 > -1.5:
            continue                                  # registry stencil
        if s > 0 and y0 < -16 and y1 > -25 and abs(z) < 2.5:
            continue                                  # claim band stencil
        x = s * (12.12 if y < 18 else 11.12)
        H.box((x, y, z), (0.25, ln, hz), mat, r=rot(rx=rx), bevel=0.1)
        placed += 1
    for s in (-1, 1):
        parts.rcs_quad(H, (s * 10.6, 29, -5.6), (s, 0, -1), "dark", "metal", s=1.3)
        parts.rcs_quad(H, (s * 5.0, 40.5, 5.0), (0, 1, 0.3), "dark", "metal", s=1.3)
        for y in (20, 22, 28, 30):
            parts.window(S, (s * 11.06, y, 3.0), (s, 0, 0), (0, 0, 1), 0.8, 0.6, "window_dim")
    label("OKV-2207", (12.08, 8.75, 0), (1, 0, 0), (0, 0, 1), 2.4, wk.INK_DARK, 0.75)
    label("#BAR", (12.08, 8.75, 0), (1, 0, 0), (0, 0, 1), 0.5, RED_INK, 0.9)
    label("#BAR", (1.25, 16.2, 9.02), (0, 0, 1), (0, 1, 0), 1.2, RED_INK, 0.85)
    label("#BAR", (12.02, -20.5, 0), (1, 0, 0), (0, 0, 1), 2.2, RED_INK, 0.85)
    for s in (-1, 1):
        label("CLAIMED", (s * 11.02, 25, -2.5), (s, 0, 0), (0, 0, 1), 1.6, RED_INK, 0.85)


# ---------------------------------------------------------------- 5. stern drive, tethered bell
def build_stern():
    H.box((0, 40.4, 0), (15, 1.2, 4), "dark", bevel=0.05)
    H.lathe(BELL, 18, bell_mat, matrix=Matrix.Translation((-4.5, 40.6, 0)) @ ALONG_Y)
    H.cyl((4.5, 40.9, 0), 2.1, 2.1, 1.0, "dark", segs=16, axis_rot=ALONG_Y)
    for k in range(6):
        a = k * math.pi / 3
        x, z = 4.5 + 1.2 * math.cos(a), 1.2 * math.sin(a)
        parts.pipe(H, (x, 40.9, z), (x, 42.1, z), 0.25, "metal")
    m = (Matrix.Translation((15.5, 37, -6)) @ Matrix.Rotation(-0.7, 4, "Z")
         @ Matrix.Rotation(0.3, 4, "X") @ ALONG_Y)
    S.lathe(BELL, 16, bell_mat, matrix=m)
    S.cyl(m @ V((0, 0, 0.5)), 1.9, 1.9, 0.4, "dark", segs=16, axis_rot=m.to_3x3().to_4x4())
    cable(S, (8, 38, -4), m @ V((0, 0, 0.3)), 0.6)
    SCORCH.append((-4.5, 46.0, 0.0, 4.0))
    SCORCH.append((4.5, 41.0, 0.0, 3.0))


# ---------------------------------------------------------------- 6. radiator wings
def panel_frame(c, hx, hy, r=None):
    r3 = (r or Matrix()).to_3x3()
    cs = [V(c) + r3 @ V((sx * hx, sy * hy, 0)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    for a, b in zip(cs, cs[1:] + cs[:1]):
        H.beam(a, b, 0.35, 0.35, "dark")


def build_radiators():
    for s in (-1, 1):
        girder(H, (s * 11, 25, 2), (s * 36, 25, 2), 2.0, 1.6, 6, "dark")
        for y in (24.3, 25.7):
            H.tube((s * 11, y, 2.6), (s * 35, y, 2.6), 0.35, 0.35, "metal", segs=8)
        for x in (15.5, 31.5):
            parts.radiator(H, (s * x, 25, 3.1), 9.0, 7.4, (0, 0, 1), "radiator", "dark",
                           ribs=5, t=0.25)
            panel_frame((s * x, 25, 3.1), 3.7, 4.5)
        # mismatched middle panel, tilted on its mounts
        c = V((s * 23.5, 26.0, 3.1))
        r = rot(rx=0.12)
        pm, rm = ("metal", "dark") if s < 0 else ("radiator", "rust")
        H.box(c, (7.4, 9.0, 0.25), pm, r=r, bevel=0)
        for k in range(5):
            y = -4.5 + 9.0 * (k + 0.5) / 5
            H.box(c + r.to_3x3() @ V((0, y, 0.12)), (7.1, 0.14, 0.4), rm, r=r, bevel=0)
        panel_frame(c, 3.7, 4.5, r)


# ---------------------------------------------------------------- 7. bow chunk + cradle
def build_chunk():
    H.loft([[CM @ p for p in oct_ring(-3, 22, 16, 4)], [CM @ p for p in oct_ring(3, 22, 16, 4)]],
           "hull3", mat_fn=lambda i, j: "hull2" if j >= 5 else "hull3")
    rings = [oct_ring(3, 22, 16, 4), oct_ring(8, 15, 11, 3, x0=0.6, z0=-0.6),
             oct_ring(11, 8, 6, 2, x0=1.4, z0=-1.4)]
    H.loft([[CM @ p for p in r] for r in rings], "hull3",
           mat_fn=lambda i, j: "dark" if i == 1 and j in (0, 1) else "hull3")
    oct_shell(H, 0.2, 2.2, 22.12, 16.12, 4.05, 0.3, "hull", M=CM)
    for y in (-4.6, -6.6, -8.6):
        oct_shell(H, y - 0.35, y + 0.35, 22, 16, 4, 0.8, "dark", M=CM)
    oct_shell(H, -10.95, -10.25, 22, 16, 4, 0.8, "dark", skip=(4, 5), M=CM)
    for p in oct_ring(0, 21.2, 15.2, 3.6):
        H.beam(cp(p.x, -11, p.z), cp(p.x, -3, p.z), 0.5, 0.5, "dark")
    H.cyl(cp(0, -6.8, -1), 4.6, 4.6, 7.4, "rust", segs=16, axis_rot=CR @ ALONG_Y)
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.pipe(H, cp(sx * 6, -11, sz * 4), cp(sx * 6, -4, sz * 4), 0.4, "metal")
    # breaking cradle
    H.beam(cp(0, -12, -9.5), cp(0, 3.5, -9.5), 2, 2, "dark")
    for yc in (-7.0, 2.2):
        H.beam(cp(-13.6, yc, -9.5), cp(13.6, yc, -9.5), 2, 2, "hazard")
        for s in (-1, 1):
            H.beam(cp(s * 13.6, yc, -10.5), cp(s * 13.6, yc, 10.5), 1.8, 1.8, "dark")
            H.box(cp(s * 12.3, yc, -0.5), (1.6, 3, 3.4), "metal", r=CR, bevel=0.06)
    H.beam(cp(-13.6, -7, 10.5), cp(13.6, -7, 10.5), 1.6, 1.6, "hazard")
    H.box(cp(-13.6, 2.2, 10.4), (7, 7, 0.8), "junk", r=CR, bevel=0.05)
    girder(H, cp(0, -12, -9.5), (11.0, -9.0, -7.0), 2.2, 2.2, 3)
    girder(H, cp(13.6, -7, -9.5), (11.0, -21.0, -7.5), 2.2, 2.2, 2)
    # torch carriage hung under the portal beam (den_salvage)
    S.box(cp(3, -7, 8.9), (2.6, 2.2, 1.2), "hazard", r=CR, bevel=0.06)
    S.beam(cp(3, -6.4, 8.5), cp(3, -3.6, 8.6), 0.45, 0.45, "metal")
    S.cyl(cp(3, -3.3, 8.45), 0.35, 0.25, 0.9, "dark", segs=8)
    S.box(cp(-2, -3, 8.04), (10, 0.18, 0.06), "molten", r=CR, bevel=0)
    S.box(cp(11.04, -3, 0.5), (0.06, 0.18, 7), "molten", r=CR, bevel=0)
    label("OKV-2207", cp(0, -0.6, 8.02), CR.to_3x3() @ V((0, 0, 1)), CR.to_3x3() @ V((0, 1, 0)),
          1.4, wk.INK_DARK, 0.7)
    SCORCH.append((27.46, -12.41, 5.0, 3.0))


# ---------------------------------------------------------------- 8. conveyor, shredder, sorter
def build_shredder():
    a, b = V((24.1, -10.3, 9.0)), V((4.0, -0.5, 15.8))
    girder(H, a, b, 2.0, 1.4, 6, "dark")
    H.box((24.1, -10.3, 8.4), (2.4, 2.4, 0.6), "dark", bevel=0.05)
    up = V((0, 0, 0.85))
    S.beam(a + up, b + up, 1.5, 0.2, "pad")
    fr = line_frame(a, b)
    for t, mat in ((0.2, "hull3"), (0.45, "rust"), (0.7, "scavred")):
        q = a.lerp(b, t) + up + fr.to_3x3() @ V((0, 0, 0.19))
        S.box(q, (1.4, 1.8, 0.18), mat, r=fr @ Matrix.Rotation(RNG.uniform(-0.3, 0.3), 4, "Z"),
              bevel=0.05)
    H.box((3.5, -0.5, 10.75), (8, 7, 3.5), "hull2", bevel=0.05)
    pts = [V((3.5 + sx * 3, -0.5 + sy * 3, 12.5)) for sx in (-1, 1) for sy in (-1, 1)]
    pts += [V((3.5 + sx * 4.5, -0.5 + sy * 4, 16.5)) for sx in (-1, 1) for sy in (-1, 1)]
    parts.part_hull(H, pts, "rust")
    H.box((8.6, -0.5, 8.25), (3.0, 5.6, 3.3), "dark", bevel=0.05)   # motor mount
    for y in (-2.1, 1.1):
        H.cyl((8.6, y, 10.5), 1.3, 1.3, 3.0, "metal", segs=12, axis_rot=ALONG_X)
    H.cyl((3.5, 4.1, 11.8), 1.5, 1.5, 7.0, "dark", segs=14, axis_rot=ALONG_X)
    for s in (-1, 1):
        H.cyl((3.5 + s * 3.65, 4.1, 11.8), 1.6, 1.6, 0.3, "metal", segs=14, axis_rot=ALONG_X)
        H.box((3.5 + s * 2.6, 4.1, 9.65), (0.8, 2.4, 1.3), "dark", bevel=0.05)
    H.box((2.0, 5.6, 12.0), (2.0, 2.4, 1.0), "dark", r=rot(rx=-0.5), bevel=0.05)
    H.box((-3.2, -2.0, 10.3), (3, 3, 2.6), "hull2", bevel=0.06)
    S.box((-3.2, -3.56, 10.6), (2.2, 0.1, 0.8), "window", bevel=0)


# ---------------------------------------------------------------- 9. crucible
def build_crucible():
    prof = [(0, 9), (5, 9), (5, 10.2), (4.4, 10.6), (4.4, 16.8), (4.0, 18.4), (3.4, 18.8),
            (3.4, 20), (2.6, 20), (2.6, 19.6), (0, 19.6)]
    cm = ("dark", "dark", "dark", "rust", "hull2", "dark", "metal", "dark", "dark", "dark")
    H.lathe(prof, 22, lambda i, j: cm[j], matrix=Matrix.Translation((0, 10.5, 0)))
    H.ring_segment(V((0, 10.5, 0)), 3.3, 4.1, 0, 2 * math.pi, 20.0, 20.4, "scavred", steps=16)
    for z in (12, 13.8, 15.6):
        H.cyl((0, 10.5, z), 4.65, 4.65, 0.6, "metal", segs=22)
    H.box((-6.4, 14.2, 10.5), (2.6, 2.6, 3), "hull2", bevel=0.06)
    for z in (11.2, 12.0):
        H.beam((-5.1, 14.2, z), (-3.0, 13.6, z), 0.4, 0.4, "metal")
    H.tube((4.2, 14.6, 9.0), (4.2, 14.6, 26.5), 0.9, 0.8, "dark", segs=12)
    H.cyl((4.2, 14.6, 26.7), 1.2, 1.2, 0.4, "dark", segs=12)
    H.beam((2.9, 13.2, 20.6), (4.2, 14.6, 22.0), 0.8, 0.8, "dark")
    H.box((-4.9, 9.0, 12.2), (3.0, 1.2, 0.9), "dark", r=rot(ry=0.25), bevel=0.05)
    H.box((-6.2, 8.5, 9.8), (4, 6, 1.6), "dark", bevel=0.05)
    S.cyl((0, 10.5, 19.65), 2.6, 2.6, 0.1, "molten", segs=22)
    S.box((-6.4, 9.0, 11.3), (0.5, 0.5, 1.6), "molten", bevel=0)
    for y in (6.0, 6.9, 7.8):
        for x in (-7.25, -5.35):
            for k in range(3):
                S.box((x, y, 10.85 + k * 0.47), (1.8, 0.5, 0.45), "metal", bevel=0)
    SCORCH.append((0.0, 10.5, 20.0, 3.5))
    SCORCH.append((4.2, 14.6, 26.5, 2.0))


# ---------------------------------------------------------------- 10. crew hab
def build_hab():
    parts.capsule(H, 4.0, 21.0, 3.6, lambda i, j: "olive" if j == 3 else "hull2", segs=22,
                  x=11.2, z=11.0)
    for y in (7.5, 12.5, 17.5):
        H.cyl((11.2, y, 11.0), 3.75, 3.75, 0.6, "dark", segs=22, axis_rot=ALONG_Y)
        H.box((11.2, y, 6.9), (3.4, 1.0, 2.2), "dark", bevel=0.05)
    H.cyl((11.2, 3.6, 11.0), 1.4, 1.4, 1.2, "metal", segs=12, axis_rot=ALONG_Y)
    for a in (0.35, -0.05):
        for k in range(6):
            c = (11.2 + 3.64 * math.cos(a), 6.0 + 2.5 * k, 11.0 + 3.64 * math.sin(a))
            if abs(c[1] - 7.5) < 0.8 or abs(c[1] - 12.5) < 0.8 or abs(c[1] - 17.5) < 0.8:
                c = (c[0], c[1] + 0.9, c[2])
            parts.window(S, c, (math.cos(a), 0, math.sin(a)), (-math.sin(a), 0, math.cos(a)),
                         0.9, 0.6, parts.pick_lit(RNG, "hab"))


# ---------------------------------------------------------------- 11. spheres, cowling, pipes
def build_plant():
    for y, mat in ((21.5, "olive"), (28.5, "rust")):
        c = V((-5.8, y, 11.6))
        H.sphere(c, 2.6, mat, segs=22, rings=12)
        H.cyl(c, 2.72, 2.72, 0.35, "dark", segs=22)
        H.cyl(c, 2.72, 2.72, 0.35, "dark", segs=22, axis_rot=ALONG_Y)
        H.cyl(c, 2.72, 2.72, 0.35, "dark", segs=22, axis_rot=ALONG_X)
        H.box((-5.8, y, 9.0), (4, 3, 1.2), "dark", bevel=0.05)
        H.tube((-5.8, y, 9.0), (-9.6, y, 8.4), 0.32, 0.32, "metal", segs=8)
    H.tube((-9.6, 29, 8.4), (-9.6, -4.2, 8.4), 0.32, 0.32, "metal", segs=8)
    for y in range(-3, 28, 4):
        surf = 7.4 if y < 18 else 5.9
        z0 = surf - 0.3
        H.box((-9.6, y, (z0 + 8.3) / 2), (1.0, 0.5, 8.3 - z0), "dark", bevel=0.03)
    H.box((2.5, 25, 9.7), (9, 10, 2.4), "metal", bevel=0.04)
    for y in (19.9, 30.1):
        H.box((2.5, y, 9.7), (9.2, 0.3, 2.0), "hazard", bevel=0)
    for x, y in ((-0.5, 22), (5.5, 28)):
        H.box((x, y, 11.2), (2, 1.4, 0.6), "dark", bevel=0.05)
    for s in (-1, 1):
        H.tube((2.5 + s * 4.6, 25, 10.0), (s * 8.6, 25, 9.6), 0.5, 0.5, "metal", segs=10)
        H.tube((s * 8.6, 25, 9.6), (s * 11.4, 25, 4.0), 0.5, 0.5, "metal", segs=10)
        H.sphere((s * 8.6, 25, 9.6), 0.55, "metal", segs=10, rings=6)
    label("REACTOR", (2.5, 25, 10.92), (0, 0, 1), (0, 1, 0), 1.0, wk.INK_DARK, 0.85)


# ---------------------------------------------------------------- 12. loot rack
def build_rack():
    parts.box_truss(H, -24, 16, 3.2, 4.5, 8, "dark", "dark", chord=0.5, brace=0.3, z0=-1,
                    x0=-16.5)
    for y in (-20, -8, 4, 14):
        for z in (-3, 3):
            H.beam((-12, y, z), (-13.3, y, z), 0.8, 0.8, "dark")
    H.box((-16.5, 15.5, 3.9), (7, 7, 0.8), "pad", bevel=0.04)
    H.beam((-16.5, 18.5, 3.5), (-14.0, 16.0, -1.0), 0.5, 0.5, "dark")   # deck strut
    bodies = ("scavred", "olive", "hull3", "junk", "rust", "scavred")
    for x in (-17.95, -15.05):
        for z in (-4.0, -1.2, 1.6):
            for y in (-21, -14.6, -8.2, -1.8, 4.6, 11.0):
                forced = (x, y, z) == (-17.95, -1.8, 1.6)
                fill = RNG.random() < 0.62
                rz = RNG.uniform(-0.03, 0.03)
                body, band = RNG.choice(bodies), RNG.choice(("dark", "hazard"))
                if forced:
                    body, band = "hull", "accent"
                elif not fill:
                    continue
                wk.cargo_pod(S, (x, y, z), (2.6, 6.0, 2.6), rot_z=rz, body=body, band=band,
                             frame="dark")
    wk.cargo_pod(S, (-16.5, -12, 4.9), (2.6, 6.0, 2.6), rot_z=0.18, body="scavred",
                 band="dark")
    S.sphere((-16.5, 2.0, 5.6), 1.9, "hull3", segs=14, rings=8)
    S.cyl((-16.5, 2.0, 5.6), 2.0, 2.0, 0.35, "dark", segs=14, axis_rot=ALONG_Y)
    cable(S, (-13.3, -24, 3.5), (-12.5, -29.2, 9.0), 0.5)
    cable(S, (-11, 24, 1.5), (-13.3, 16, 3.5), 0.5)


# ---------------------------------------------------------------- 13. cargo manipulator
def build_manipulator():
    S.cyl((-5, -19, 9.6), 1.8, 1.8, 1.2, "dark", segs=12)
    S.box((-5, -19, 11.2), (2.4, 2.4, 2.0), "hazard", bevel=0.06)
    S.beam((-5, -19, 12), (-3, -13.5, 17), 1.3, 1.3, "hazard")
    S.cyl((-3, -13.5, 17), 0.9, 0.9, 1.6, "dark", segs=10, axis_rot=ALONG_X)
    S.beam((-3, -13.5, 17), (1, -10, 13.5), 1.0, 1.0, "hazard")
    S.box((1, -10, 13.2), (1.2, 1.2, 1.0), "dark", bevel=0.06)
    r = Matrix.Rotation(0.3, 3, "Z")
    for cx, cy in ((-1.2, -2.9), (1.2, 2.9), (0.0, 0.0)):
        tip = V((1, -10, 11.3)) + r @ V((cx, cy, 0))
        mid = V((1, -10, 12.6)).lerp(tip, 0.45) + V((0, 0, 0.7))
        S.beam((1, -10, 12.8), mid, 0.4, 0.4, "dark")
        S.beam(mid, tip, 0.4, 0.4, "dark")
    wk.cargo_pod(S, (1, -10, 10.0), (2.6, 6, 2.6), rot_z=0.3, body="scavred", band="hazard")


# ---------------------------------------------------------------- 14. mast, cables
def build_mast():
    wk.lattice_mast(S, (-4.5, 36.5, 7.2), 29.0, 1.3, 0.5, 6, "dark", chord=0.35, brace=0.18)
    S.beam((-4.5, 36.5, 16), (-8, 36.5, 16), 0.4, 0.4, "dark")
    parts.dish(S, (-8.4, 36.5, 16), 2.4, (-0.4, 0.3, 0.86), "hull3", "dark", depth=0.7, segs=14)
    S.cyl((-4.5, 36.5, 27.5), 0.12, 0.05, 4.0, "dark", segs=5)
    cable(S, (-4.5, 36.5, 12), (-5.8, 28.5, 14.2), 0.8)
    cable(S, (11.2, 21.6, 12.0), (5.5, 28, 11.5), 0.5)
    cable(S, (24.1, -10.3, 9.0), (11.2, 2.9, 11.0), 1.4)


# ---------------------------------------------------------------- 15. turrets
def turret_a(name):
    """Twin autocannon off a gunboat: slewing ring at z 0, barrels along +Y."""
    p = parts.PanelPart(name, MATS)
    p.cyl(V((0, 0, 0.3)), 2.6, 2.6, 0.6, "dark", segs=16)
    p.cyl(V((0, 0, 0.7)), 2.3, 2.3, 0.2, "metal", segs=16)
    side = Matrix.Translation((0, 0, 0.8)) @ parts.SIDE
    prof = [(-2.8, 0), (2.2, 0), (3.0, 1.1), (1.8, 2.8), (-2.4, 2.8), (-3.0, 1.5)]
    p.slab(prof[::-1], -2.0, 2.0, "olive", matrix=side)
    cheek = [(-2.2, 0.4), (1.8, 0.4), (2.4, 1.2), (1.5, 2.4), (-2.0, 2.4)][::-1]
    p.slab(cheek, 2.0, 2.15, "scavred", matrix=side)
    p.slab(cheek, -2.15, -2.0, "scavred", matrix=side)
    p.box(V((0, -2.9, 2.5)), (2.8, 1.4, 1.6), "junk", bevel=0.06)
    p.beam(V((1, -2.2, 2.9)), V((0.5, 1, 3.3)), 0.4, 0.4, "dark")
    p.box(V((1.3, 0.6, 3.95)), (0.7, 0.7, 0.6), "dark", bevel=0.05)
    root = V((0, 2.7, 2.4))
    p.box(root, (2.6, 1.1, 1.6), "dark", bevel=0.06)
    el = math.radians(12)
    fwd = V((0, math.cos(el), math.sin(el)))
    q = axis_q(fwd)
    for sx in (-0.42, 0.42):
        b0 = root + V((sx, 0, 0))
        p.cyl(b0 + fwd * 1.1, 0.3, 0.3, 1.6, "metal", segs=10, axis_rot=q)
        p.cyl(b0 + fwd * 3.6, 0.17, 0.17, 4.0, "dark", segs=8, axis_rot=q)
        p.cyl(b0 + fwd * 5.75, 0.28, 0.28, 0.6, "dark", segs=8, axis_rot=q)
    return p, root + fwd * 6.05


def turret_b(name):
    """Warship rotary PDC: ball mount in a yoke, six-barrel cluster along +Y."""
    p = parts.PanelPart(name, MATS)
    p.cyl(V((0, 0, 0.3)), 2.4, 2.4, 0.6, "dark", segs=16)
    p.cyl(V((0, 0, 0.8)), 2.1, 2.1, 0.4, "hull2", segs=16)
    for s in (-1, 1):
        p.box(V((s * 1.9, 0, 2.4)), (0.6, 3.0, 3.2), "scavred", bevel=0.08)
    c = V((0, 0, 2.6))
    p.sphere(c, 1.9, "hull2", segs=16, rings=10, scale=(1, 1, 0.9))
    el = math.radians(8)
    fwd = V((0, math.cos(el), math.sin(el)))
    q = axis_q(fwd)
    u1, u2 = V((1, 0, 0)), V((0, -fwd.z, fwd.y))
    p.cyl(c + fwd * 2.4, 0.75, 0.75, 1.6, "metal", segs=12, axis_rot=q)
    for k in range(6):
        a = k * math.pi / 3
        off = (u1 * math.cos(a) + u2 * math.sin(a)) * 0.42
        p.cyl(c + fwd * 4.6 + off, 0.13, 0.13, 4.2, "dark", segs=6, axis_rot=q)
    p.cyl(c + fwd * 6.3, 0.68, 0.68, 0.35, "dark", segs=12, axis_rot=q)
    p.cyl(V((0, -2.4, 1.9)), 1.2, 1.2, 1.4, "junk", segs=14, axis_rot=ALONG_X)
    p.box(V((1.2, -1, 4.4)), (0.8, 0.8, 0.8), "dark", bevel=0.06)
    return p, c + fwd * 6.7


def turret_pose(base, yaw):
    return Matrix.Translation(base) @ Matrix.Rotation(yaw, 4, "Z")


def build_pedestals():
    for s in (-1, 1):
        H.box((s * 10.5, -28, 8.5), (6.5, 6.5, 4), "junk", bevel=0.05)
    H.cyl((0, 34.2, 9.2), 3.4, 3.4, 2.4, "dark", segs=16)


def build_turrets(root):
    out = []
    for i, (kind, base, yaw) in enumerate(TURRETS):
        p, tip = (turret_a if kind == "A" else turret_b)(f"den_turret_{i + 1}")
        o = p.finish(root)
        pose = turret_pose(base, yaw)
        o.data.transform(pose @ Matrix.Scale(TURRET_S, 4))   # world pose while baking
        out.append((o, pose, pose @ (tip * TURRET_S), yaw))
    return out


# ---------------------------------------------------------------- 16. lights
def build_lights():
    for p in oct_ring(-31.25, 26.4, 20.4, 4.8):
        lamp(p, 0.9)
    lamp((0, -31.25, 10.25), 0.9)
    for s in (-1, 1):
        lamp((s * 10, -31.8, -7.7), 0.7)
        lamp((s * 10, -40.8, -7.7), 0.7)
        lamp((s * 35.2, 20.6, 3.45), 0.8)
        lamp((s * 35.2, 29.4, 3.45), 0.8)
        lamp((s * 7.0, 40.15, 2.8), 0.8)
        lamp((s * 7.0, 40.15, -2.8), 0.8)
        lamp((s * 3.9, 10.5, 20.55), 0.5)
    lamp(cp(1.4, 11.3, -1.4), 1.0)
    for x, y in ((-13.6, -7), (13.6, -7)):
        lamp(cp(x, y, 11.6), 0.7)
    lamp(cp(13.6, 2.2, 10.9), 0.7)
    lamp((-4.5, 36.5, 29.6), 1.0)
    for z, sx in ((16.0, 1), (22.0, -1)):
        w = 1.3 + (0.5 - 1.3) * (z - 7.2) / (29.0 - 7.2)
        lamp((-4.5 + sx * w, 36.5 + sx * w, z), 0.5)
    lamp((4.2, 14.6, 27.2), 0.8)
    lamp((11.2, 6.0, 14.7), 0.7)
    lamp((11.2, 19.0, 14.7), 0.7)
    lamp((-19.9, -24.2, 3.8), 0.7)
    lamp((-19.9, 16.2, 3.8), 0.7)
    for kind, base, yaw in TURRETS:
        lamp(turret_pose(base, yaw) @ (V((0, -3.4, 3.4)) * TURRET_S), 0.5)
    arc = cp(3, -3.1, 8.15)
    L.box(arc, (0.6, 0.6, 0.5), "arc", r=CR, bevel=0)
    rng = random.Random(SEED + 5)
    for _ in range(3):
        off = V((rng.uniform(-1.0, 1.0), rng.uniform(-1.0, 0.3), rng.uniform(-1.2, -0.3)))
        s = rng.uniform(0.15, 0.25)
        L.box(arc + CR.to_3x3() @ off, (s, s, s), "arc", bevel=0)


# ---------------------------------------------------------------- assembly
def build_den():
    global H, S, G, L
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    H = parts.PanelPart("den_hull", MATS)
    S = parts.PanelPart("den_salvage", MATS)
    G = parts.Part("den_hangar_glow", MATS)
    L = parts.Part("den_lights", MATS)
    for b in (build_hold, build_hangar, build_apron, build_midship, build_stern,
              build_radiators, build_chunk, build_shredder, build_crucible, build_hab,
              build_plant, build_rack, build_manipulator, build_mast, build_pedestals,
              build_lights):
        b()
    root = parts.make_root(PRE, size=20)
    objs = [H.finish(root), S.finish(root), G.finish(root), L.finish(root)]
    turrets = build_turrets(root)
    return root, objs, turrets


def add_hooks(root, turrets):
    parts.add_empty("spawn_point", root, SPAWN_POS, rot_z=math.pi, size=6)
    for i, (o, pose, tip, yaw) in enumerate(turrets):
        o.data.transform(pose.inverted())   # origin onto the slewing ring
        o.matrix_world = pose
        e = parts.add_empty(f"den_gun_{i + 1}", root, tuple(tip), rot_z=yaw, size=2)
        print(f"HOOK den_gun_{i + 1} pos=({tip.x:.2f}, {tip.y:.2f}, {tip.z:.2f}) yaw={yaw:.3f}"
              f" heading=({-math.sin(yaw):.3f}, {math.cos(yaw):.3f})")
        e.empty_display_size = 2


def rts_view(path):
    """RTS-camera style render (perspective, ~45 deg from ~400 m) with a scavenger raider
    beside the mouth for scale. Runs after the export, never part of the .glb."""
    if os.path.exists(SHIP_GLB):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=SHIP_GLB)
        new = [o for o in bpy.data.objects if o not in before and o.parent is None]
        for o in new:
            o.location = (-16.0, -52.0, 0.0)
            o.rotation_euler = (0, 0, math.pi * 0.9)
    scene = bpy.context.scene
    cam = scene.camera
    cam.data.type = "PERSP"
    cam.data.lens = 50
    tgt = V((5.0, 0.0, 0.0))
    loc = tgt + V((-0.25, -0.67, 0.7)).normalized() * 400.0
    cam.location = loc
    cam.rotation_euler = (tgt - loc).to_track_quat("-Z", "Y").to_euler()
    cam.data.clip_end = 2000
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1000
    common.render(path)
    loc = tgt + V((-0.25, -0.67, 0.7)).normalized() * 170.0
    cam.location = loc
    common.render(path.replace(".png", "_close.png"))


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs, turrets = build_den()
    hull, salvage = objs[0], objs[1]
    tur_objs = [t[0] for t in turrets]
    baked = [hull, salvage] + tur_objs
    if "--no-textures" not in argv:
        wk.texture(baked, MATS, PRE, [(0.0, -36.0)], scorch=SCORCH, decals=DECALS,
                   labels=LABELS, seed0=71, res=2048)
    else:
        for o in baked:
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    add_hooks(root, turrets)
    wk.stats(objs + tur_objs)
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        wk.previews(PRE, (7.0, 2.0, 2.0), 130, 120, cam_off=(-85, -135, 150))
    rts = [a.split("=", 1)[1] for a in argv if a.startswith("--rts=")]
    if rts:
        rts_view(rts[0])


main()
