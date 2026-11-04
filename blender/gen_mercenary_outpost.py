"""Generate the Mercenary Outpost ("Drumhead rack", MX-12 merc carrier hub) .glb and previews.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_mercenary_outpost.py
  Options after `--`: --no-preview, --no-textures (flat materials, no Cycles bake),
  --no-ships (previews without the four docked merc interceptors), --check (measures
  merc_interceptor.glb, tests the docking corridors, the sideways path, the outer berth
  spots and the footprint radius, prints BERTH CHECK lines).
Textures: one 2048 worn-industrial atlas (worn_kit / station_textures.WORN_KINDS plus a
"merc" oxide-red paint kind and "scrap" patches), saved as
blender/textures/mercenary_outpost_*.jpg and embedded as JPEG.

Design: a free-floating merc carrier hub in the hard, industrial style of the Expanse.
There is no floor, deck or hangar shell. Four interceptors hang in an open rack, held from
above by dorsal clamp yokes and cradled from below by ventral saddles, between lattice
finger piers that carry pressurised walkway tubes, umbilicals and pipe runs. Each lane is
framed in free space by a red/green lamp pair on chunky guide arms that rake forward and
up from the fingertips, and a white bar on the forward ventral saddle beam. The rack hangs
from a cross-girder (service tunnel in a box truss) armoured on the threat side with
bolted, patched plates, with an ops gondola, propellant tanks and sodium work floods on
top. Two armoured torpedo magazines flank the rack (a dark steel threat face with
chamfered gunmetal cheeks, bolt rows and six recessed tube bores, VLS lids on top with one
hatch open, hull number "12"), with PDC turrets on their tops and bellies. Behind the
girder a non-rotating axle runs through a standing spin drum habitat (bearing collars,
hazard seams, contrasting spokes and a SPIN stencil imply the rotation), then two radiator
fans (a short boom off the axle, a coolant hub per side, three long narrow blades each,
swept in plan and twisted about their long axis), a comms mast, two rear PDCs and the
shuttle link port at the axle tail.

Layout (Blender Z up, exported +Y up; Blender -Y = Godot +Z). Centre at origin, docking
plane z = 0, docking face toward Blender -Y.
  rack      bays x = -15, -5, 5, 15, ships rest at y = -3.5 nose -Y (merc_interceptor
            x +-4.05, nose y -10.56, bell y +3.25, z -1.23..2.05); corridors x bx +-4.3,
            z +-3.2 stay clear except the clamps (bottom z >= 2.40, top z <= -1.58)
  fingers   inner x = -10, 0, 10, outer x = +-20.6, y -12..4.9, guide arms to y -17,
            z 6.2
  girder    x -31..31, y 4.9..9.1, z +-5 (brow armour, gondola, tanks on top)
  magazines x +-23..31, y -12.65..9, z +-4.6
  drum      r 11.4, y 10..21 around the axle (y 9.1..32.3)
  back      radiator hubs x +-8 y 28, blades to x +-24.8 y 19..31, mast y 24,
            link port y 32.3..33.6
Hierarchy: mercenary_outpost (empty root) -> mercenary_outpost_hull,
  mercenary_outpost_lights, dock_point, spawn_point, link_point (empties).
dock_point / spawn_point are rotated 180 deg about up, so their Godot -Z (forward) points
out of the rack mouth (Godot world +Z). link_point is unrotated: Godot -Z points out the
back.
Godot berth fields (data/buildings/mercenary_outpost.tres): inner_berths 4,
berth_spacing 10, berth_depth 10.5, outer_berth_side 30, outer_berth_step 11,
footprint_radius 40.
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
PRE = "mercenary_outpost"
OUT = os.path.join(common.ROOT, "assets", "models", "buildings", "mercenary_outpost.glb")
BLEND = os.path.join(common.ROOT, "blender", "mercenary_outpost.blend")
FIGHTER_GLB = os.path.join(common.ROOT, "assets", "models", "ships", "merc_interceptor.glb")
PREVIEW_COPY = os.path.join(wk.SCRATCH, "mercoutpost")

# Godot berth fields (keep in sync with data/buildings/mercenary_outpost.tres)
INNER_BERTHS = 4
BERTH_SPACING = 10.0
BERTH_DEPTH = 10.5
OUTER_SIDE = 30.0
OUTER_STEP = 11.0
OUTER_HEIGHT = 2.0

DOCK_POS = (0.0, -14.0, 0.0)
SPAWN_POS = (0.0, -34.0, 0.0)
LINK_POS = (0.0, 33.6, 0.0)
BAYS = [(k - (INNER_BERTHS - 1) / 2) * BERTH_SPACING for k in range(INNER_BERTHS)]
BERTH_Y = DOCK_POS[1] + BERTH_DEPTH          # -3.5
GAPS_IN = [-10.0, 0.0, 10.0]
OUTER_FINGER_X = 20.6
STATIONS = (-5.0, 0.5)                       # clamp yoke / saddle stations along y
# merc_interceptor at rest (rotated pi at (bx, -3.5, 0)); --check re-measures the glb
SHIP_HW, SHIP_ZMIN, SHIP_ZMAX = 4.05, -1.23, 2.05
NOSE_Y, TAIL_Y = -10.56, 3.25
LANE_HW, LANE_HH = 4.3, 3.2                  # docking corridor half sizes (x, z)
LABELS = ["BAY 1", "BAY 2", "BAY 3", "BAY 4", "12", "MX-12", "MERC", "SPIN", "ORD", "PDC",
          "OPS", "#CHEV", "#BAR"]
NO_PADS = [(0.0, 900.0), (0.0, 901.0)]   # no landing pads: keep the deck ring paint off-model

# merc paint: worn oxide red, same wear model as the station accent paint
MERC = dict(st.WORN_KINDS["accent"])
MERC["tones"] = [(0.30, 0.045, 0.035), (0.27, 0.04, 0.03), (0.33, 0.055, 0.04),
                 (0.25, 0.04, 0.032), (0.31, 0.05, 0.038), (0.28, 0.045, 0.036)]
MERC["bleach"] = 0.3
st.WORN_KINDS["merc"] = MERC

MATS = {}
DECALS = []
SCORCH = []
H = L = None
RNG = random.Random(23)
UP = V((0, 0, 1))
GIRDER_BAYS = 10


def build_materials():
    wk.build_materials(PRE, MATS, extra=("scrap",))
    MATS["merc"] = common.make_material(f"{PRE}_merc_paint", (0.3, 0.045, 0.035),
                                        roughness=0.6)


def label(text, centre, normal, up, h, colour, opacity=0.85):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity))


def lamp(pos, s=0.4, mat="light"):
    wk.lamp(L, pos, s, mat)


def rx(deg):
    return Matrix.Rotation(math.radians(deg), 4, "X")


def rz(rad):
    return Matrix.Rotation(rad, 4, "Z")


# ---------------------------------------------------------------- rack: fingers
def inner_finger(gx):
    y0, y1 = -11.5, 5.0
    for sx in (-1, 1):
        for sz in (-1, 1):
            H.beam(V((gx + sx * 0.25, y0, sz * 3.75)), V((gx + sx * 0.25, y1, sz * 3.75)),
                   0.3, 0.3, "dark")
    posts = (-11.5, -7.5, -3.5, 0.5, 4.5)
    for y in posts:
        H.box(V((gx, y, 0)), (0.7, 0.3, 7.8), "hull2", bevel=0.04)
    for k in range(len(posts) - 1):
        ya, yb = (posts[k], posts[k + 1]) if k % 2 == 0 else (posts[k + 1], posts[k])
        parts.strut(H, V((gx, ya, -3.6)), V((gx, yb, 3.6)), 0.2, 0.2, "dark")
    H.tube(V((gx, -11.0, 2.4)), V((gx, 4.9, 2.4)), 0.16, 0.16, "accent", segs=8)
    H.tube(V((gx, -11.0, -2.4)), V((gx, 4.9, -2.4)), 0.16, 0.16, "metal", segs=8)
    for sx in (-1, 1):   # umbilical heads facing the ships
        H.box(V((gx + sx * 0.475, -1.5, 0.6)), (0.15, 0.9, 0.7), "hazard", bevel=0.0)
    # pressurised walkway tube on top (gives the finger top-down presence)
    H.cyl(V((gx, -3.0, 4.75)), 0.6, 0.6, 15.8, "hull", segs=10, axis_rot=parts.ALONG_Y)
    for y in (-8.0, -1.0):
        H.cyl(V((gx, y, 4.75)), 0.68, 0.68, 0.3, "dark", segs=10, axis_rot=parts.ALONG_Y)
    top = 4.75 + 0.6 * math.cos(math.pi / 10)
    for y in (-9.0, -6.0, -3.0, 0.0):
        parts.window(L, V((gx, y, top)), V((0, 0, 1)), V((0, 1, 0)), 0.3, 0.3,
                     parts.pick_lit(RNG, "work"))
    # fingertip block, chevron plate, overhead work flood
    H.box(V((gx, -11.7, 0)), (0.8, 0.6, 7.8), "merc", bevel=0.05)
    H.box(V((gx, -12.03, 2.3)), (0.7, 0.06, 2.0), "hull", bevel=0.0)
    label("#CHEV", V((gx, -12.06, 2.3)), V((0, -1, 0)), V((-1, 0, 0)), 0.5, wk.INK_DARK)
    H.box(V((gx, -11.5, 4.1)), (1.4, 0.9, 0.3), "dark", bevel=0.0)
    L.box(V((gx, -11.7, 3.93)), (1.2, 0.4, 0.06), "cyan", bevel=0.0)


def outer_finger(sx):
    x0 = sx * OUTER_FINGER_X
    parts.box_truss(H, -11.5, 5.0, 0.7, 4.0, 4, "dark", "hull2", chord=0.4, brace=0.2, x0=x0)
    cyc = ("hull2", "hull2", "hull3", "merc")
    for course, zc in ((0, 2.1), (1, -2.1)):
        for k, y in enumerate((-9.6, -5.8, -2.0, 1.8)):
            mat = cyc[(k + course) % 4]
            if sx > 0 and course == 0 and k == 2:
                mat = "scrap"
            H.box(V((sx * 21.45, y, zc)), (0.3, 3.6, 3.4), mat, bevel=0.04)
            zb = zc + (1.45 if zc > 0 else -1.45)
            for o in (-1.2, 0.0, 1.2):
                H.box(V((sx * 21.62, y + o, zb)), (0.1, 0.22, 0.22), "dark", bevel=0.0)
    H.box(V((x0, -11.7, 0)), (1.6, 0.6, 8.2), "merc", bevel=0.05)
    H.box(V((x0, -12.03, 2.3)), (1.0, 0.06, 2.0), "hull", bevel=0.0)
    label("#CHEV", V((x0, -12.06, 2.3)), V((0, -1, 0)), V((-1, 0, 0)), 0.5, wk.INK_DARK)


# ---------------------------------------------------------------- rack: clamps per bay
def bay(i, bx):
    for ys in STATIONS:
        # dorsal clamp yoke; the outer bays reach into the outer finger chords
        xa = bx - 4.7 if bx > -15 else -OUTER_FINGER_X + 0.4
        xb = bx + 4.7 if bx < 15 else OUTER_FINGER_X - 0.4
        H.beam(V((xa, ys, 3.85)), V((xb, ys, 3.85)), 0.5, 0.6, "dark")
        H.box(V((bx, ys, 3.0)), (2.2, 1.1, 1.2), "merc", bevel=0.08)
        H.box(V((bx, ys, 2.40)), (1.4, 0.8, 0.08), "dark", bevel=0.0)    # pad, bottom 2.36
        for s in (-1, 1):
            parts.strut(H, V((bx + s * 1.6, ys, 3.6)), V((bx + s * 0.8, ys, 3.25)), 0.18, 0.18,
                        "metal")
        lamp(V((bx, ys - 0.58, 3.2)), 0.3, "light")
        if ys > 0:
            H.tube(V((bx + 1.8, ys, 3.6)), V((bx + 1.2, ys + 1.3, 2.75)), 0.16, 0.16, "accent",
                   segs=8)
            H.box(V((bx + 1.2, ys + 1.4, 2.7)), (0.4, 0.4, 0.25), "hazard", bevel=0.0)
        # ventral saddle
        H.beam(V((xa, ys, -3.85)), V((xb, ys, -3.85)), 0.5, 0.6, "dark")
        H.box(V((bx, ys, -3.15)), (1.2, 0.6, 0.9), "dark", bevel=0.0)
        H.box(V((bx, ys, -2.2)), (2.6, 1.0, 1.1), "hull2", bevel=0.06)
        H.box(V((bx, ys, -1.62)), (2.0, 0.8, 0.08), "dark", bevel=0.0)
        H.box(V((bx, ys - 0.52, -2.2)), (2.6, 0.05, 0.25), "hazard", bevel=0.0)
        lamp(V((bx + 2.2, ys - 0.3, -3.5)), 0.25, "amber")
    # white lane bar on the forward ventral beam (the dorsal frame lamps are on the arms)
    L.box(V((bx, -5.3, -3.85)), (2.4, 0.08, 0.2), "cyan", bevel=0.0)
    # exhaust baffle behind the bell (set back past the 1.3 m plume)
    H.box(V((bx, 4.8, 0)), (7.6, 0.4, 6.0), "metal", bevel=0.0)
    for dx in (-3.0, -1.5, 1.5, 3.0):
        H.box(V((bx + dx, 4.4, 0)), (0.25, 0.5, 6.0), "dark", bevel=0.0)
    H.box(V((bx, 4.57, -2.8)), (7.4, 0.06, 0.3), "hazard", bevel=0.0)
    SCORCH.append((bx, 4.6, 0.3, 2.4))
    label("#BAR", V((bx, 4.58, 2.4)), V((0, -1, 0)), V((0, 0, 1)), 0.4, wk.INK_DARK)
    # tail flood on the baffle top
    H.box(V((bx, 4.75, 3.25)), (2.2, 0.5, 0.5), "dark", bevel=0.0)
    L.box(V((bx, 4.49, 3.25)), (2.0, 0.04, 0.3), "cyan", bevel=0.0)


def guide_arm(p0, p1, head, mat="hull2"):
    """Chunky boxed arm from p0 to p1 with a lamp head housing at p1 (returns its front)."""
    H.beam(p0, p1, 0.7, 0.6, mat, up=V((1, 0, 0)))
    H.beam(p0 + V((0, 0.2, 0)), p1 + V((0, 0.2, 0)), 0.3, 0.9, "dark", up=V((1, 0, 0)))
    H.box(p1, head, "dark", bevel=0.06)
    return p1 - V((0, head[1] / 2 + 0.02, 0))


def guide_arms():
    """Docking guide arms: from every fingertip one chunky arm rakes forward and up into
    free space and ends in a single lamp head carrying the lane's red (left) and green
    (right) lamp. The white bar under each lane sits on the forward ventral saddle beam, so
    every lane is framed once above and once below. The outer heads also carry a white
    strobe on the rack edges. No repeated lamp rows."""
    gxs = [-OUTER_FINGER_X] + GAPS_IN + [OUTER_FINGER_X]
    for gx in gxs:
        outer = abs(gx) > 15
        sx = (1 if gx > 0 else -1) if outer else 0
        top = V((gx + sx * 1.2, -16.4, 6.2))
        f = guide_arm(V((gx, -11.9, 3.9)), top, (1.6 if not outer else 1.2, 0.8, 0.7))
        H.box(f + V((0, 0.0, -0.36)), (0.8, 0.06, 0.08), "hazard", bevel=0.0)
        if gx > -15:                                    # green: right edge of the lane on -X
            lamp(f + V((-0.45, 0, 0.05)), 0.4, "green")
        if gx < 15:                                     # red: left edge of the lane on +X
            lamp(f + V((0.45, 0, 0.05)), 0.4, "red")
        if outer:
            wk.beacon(H, L, top + V((0, 0, 0.95)), 0.45, "cyan")


def build_rack():
    for gx in GAPS_IN:
        inner_finger(gx)
    for sx in (-1, 1):
        outer_finger(sx)
    for i, bx in enumerate(BAYS):
        bay(i, bx)
    guide_arms()


# ---------------------------------------------------------------- girder (keelson)
def build_girder():
    H.cyl(V((0, 7, 0)), 2.0, 2.0, 62, "hull2", segs=16, axis_rot=parts.ALONG_X)
    for k in range(7):
        x = -27 + 9 * k
        H.cyl(V((x, 7, 0)), 2.25, 2.25, 0.5, "dark", segs=16, axis_rot=parts.ALONG_X)
    for y in (5.2, 8.8):
        for z in (-5.0, 5.0):
            H.beam(V((-31, y, z)), V((31, y, z)), 0.45, 0.45, "dark")
    xs = [-31 + 62 * k / GIRDER_BAYS for k in range(GIRDER_BAYS + 1)]
    for k, x in enumerate(xs):
        for y in (5.2, 8.8):
            H.beam(V((x, y, -5)), V((x, y, 5)), 0.3, 0.3, "dark", up=V((0, 1, 0)))
        for z in (-5.0, 5.0):
            H.beam(V((x, 5.2, z)), V((x, 8.8, z)), 0.3, 0.3, "dark")
        if k < GIRDER_BAYS:
            xa, xb = (x, xs[k + 1]) if k % 2 == 0 else (xs[k + 1], x)
            for y in (5.2, 8.8):
                parts.strut(H, V((xa, y, -5)), V((xb, y, 5)), 0.25, 0.25, "dark",
                            up=V((0, 1, 0)))
    # armour brow on the threat side, dorsal and ventral
    mats = {-20: "hull3", -15: "hull2", -10: "merc", -5: "hull2", 0: "scrap", 5: "hull2",
            10: "merc", 15: "hull2", 20: "hull3"}
    for sz in (1, -1):
        R = rx(-20 * sz)
        r3 = R.to_3x3()
        n = r3 @ V((0, -1, 0))
        u = r3 @ V((0, 0, 1))
        out_edge = r3 @ V((0, 0, sz))
        for k in range(9):
            x = -20 + 5 * k
            mat = mats[x]
            if sz < 0 and mat == "scrap":
                mat = "hull3"
            c = V((x, 4.8, sz * 5.6))
            H.box(c, (4.8, 0.5, 2.4), mat, r=R, bevel=0.06)
            for o in (-1.8, 0.0, 1.8):
                H.box(c + out_edge * 0.95 + n * 0.28 + V((o, 0, 0)), (0.22, 0.1, 0.22), "dark",
                      r=R, bevel=0.0)
            if sz > 0 and x in BAYS:
                label(f"BAY {BAYS.index(x) + 1}", c + n * 0.25, n, u, 0.7, wk.INK_DARK)
        H.box(V((0, 4.5, sz * 4.45)), (45, 0.1, 0.35), "merc", bevel=0.0)
    # sodium work floods on the brow corners, aimed into the berths
    for sx in (-1, 1):
        H.beam(V((sx * 18.5, 5.4, 6.6)), V((sx * 18.5, 4.7, 7.9)), 0.25, 0.25, "dark")
        H.box(V((sx * 18.5, 4.55, 8.0)), (0.8, 0.45, 0.5), "dark", bevel=0.0)
        L.box(V((sx * 18.5, 4.31, 7.95)), (0.6, 0.05, 0.35), "window", bevel=0.0)


def build_gondola():
    """Ops gondola: horizontal pressure capsule lying on the girder."""
    c = V((0, 6.6, 8.3))
    rot = parts.ALONG_X @ Matrix.Rotation(math.radians(15), 4, "Z")   # facet faces -Y
    H.cyl(c, 1.8, 1.8, 10, "hull", segs=12, axis_rot=rot)
    for sx in (-1, 1):
        H.sphere(c + V((sx * 5, 0, 0)), 1.8, "hull", segs=12, rings=7, scale=(0.5, 1, 1))
        H.cyl(c + V((sx * 3.2, 0, 0)), 1.88, 1.88, 0.3, "dark", segs=12, axis_rot=rot)
        parts.strut(H, V((sx * 3, 6.6, 6.6)), V((sx * 3, 6.6, 5.0)), 0.35, 0.35, "dark")
        parts.strut(H, V((sx * 3, 8.0, 6.8)), V((sx * 3, 8.8, 5.0)), 0.35, 0.35, "dark")
    flat = 1.8 * math.cos(math.radians(15))
    wk.win_row(L, RNG, (-4, c.y - flat, c.z), (4, c.y - flat, c.z), (0, -1, 0), 8, 0.7, 0.45,
               "work")
    # upper front facet: OPS plate, cool strips either side
    n = V((0, -math.cos(math.radians(30)), math.sin(math.radians(30))))
    u = V((0, math.sin(math.radians(30)), math.cos(math.radians(30))))
    fc = c + n * flat
    H.box(fc + n * 0.04, (2.4, 0.08, 0.6), "hull2", r=rx(-30), bevel=0.0)
    label("OPS", fc + n * 0.08, n, u, 0.5, wk.INK_DARK)
    for sx in (-1, 1):
        L.box(fc + n * 0.02 + V((sx * 2.9, 0, 0)) - u * 0.15, (2.6, 0.06, 0.12), "window_cool",
              r=rx(-30), bevel=0.0)
    H.cyl(V((3.2, 7.2, 10.05)), 0.25, 0.25, 0.3, "dark", segs=8)
    parts.dish(H, V((3.2, 7.2, 10.2)), 1.3, V((-0.3, -0.6, 0.75)), "hull", "dark")
    H.cyl(V((-3.4, 7.4, 11.6)), 0.06, 0.06, 3.0, "dark", segs=6)
    lamp(V((-3.4, 7.4, 13.2)), 0.4, "red")


def build_tanks():
    for sx in (-1, 1):
        wk.tank_v(H, V((sx * 13.5, 7.0, 5.2)), 1.6, 4.4, "hull3", "merc", segs=12)
        wk.tank_v(H, V((sx * 13.5, 7.0, -9.6)), 1.6, 4.4, "hull3", "merc", segs=12)
    for z in (5.45, -5.45):
        H.tube(V((-15, 7.0, z)), V((15, 7.0, z)), 0.22, 0.22, "metal", segs=8)


# ---------------------------------------------------------------- magazines + PDCs
def pdc(c, up, d, tab=False):
    """Multi-barrel point defence turret in an armoured ball mount. c = base on the hull,
    up = mount normal (+-Z), d = barrel direction."""
    c, up, d = V(c), V(up), V(d).normalized()
    dh = V((d.x, d.y, 0)).normalized()
    psi = math.atan2(dh.x, -dh.y)          # local -Y -> dh, local X -> side
    ry = rz(psi)
    side = ry.to_3x3() @ V((1, 0, 0))
    H.cyl(c + up * 0.3, 1.6, 1.4, 0.6, "dark", segs=12,
          axis_rot=None if up.z > 0 else Matrix.Rotation(math.pi, 4, "X"))
    ball = c + up * 1.5
    H.sphere(ball, 1.3, "hull2", segs=12, rings=8, scale=(1, 1, 0.85))
    for s in (-1, 1):
        H.box(ball + side * s * 1.15, (0.35, 1.8, 1.4), "merc", r=ry, bevel=0.06)
    e1 = side
    e2 = d.cross(e1).normalized()
    for k in range(6):
        t = k * math.pi / 3
        off = (e1 * math.cos(t) + e2 * math.sin(t)) * 0.22
        H.tube(ball + d * 1.0 + off, ball + d * 3.6 + off, 0.07, 0.07, "dark", segs=5)
    q = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    H.cyl(ball + d * 2.6, 0.32, 0.32, 0.15, "metal", segs=8, axis_rot=q)
    H.cyl(ball + d * 1.3, 0.4, 0.4, 0.8, "dark", segs=8, axis_rot=q)
    H.box(ball - dh * 1.4, (1.0, 0.9, 0.7), "hazard", r=ry, bevel=0.05)
    lamp(c + up * 2.75, 0.35, "red")
    if tab:
        tc = c + up * 0.35 + dh * 1.58
        H.box(tc, (1.2, 0.1, 0.4), "hull2", r=ry, bevel=0.0)
        label("PDC", tc + dh * 0.05, dh, V((0, 0, 1)), 0.3, wk.INK_DARK)


def magazine(sx):
    x0 = sx * 27.0
    parts.prism(H, -12.0, 9.0, (8.0, 9.2, 1.6), (8.0, 9.2, 1.6), "hull2", x0=x0)
    # hardened threat face: dark steel core plate, chamfered gunmetal cheeks top, bottom and
    # sides, so the front reads as a bunker face and not a crate lid
    H.box(V((x0, -12.25, 0)), (5.0, 0.5, 7.4), "dark", bevel=0.0)
    for s in (-1, 1):                                     # side cheeks, swept back 35 deg
        a = math.radians(35) * s
        H.box(V((x0 + s * 3.32, -11.68, 0)), (2.0, 0.5, 8.6), "hull2", r=rz(a), bevel=0.04)
    for s in (-1, 1):                                     # top / bottom chamfers, 45 deg
        H.box(V((x0, -11.95, s * 4.05)), (5.2, 0.45, 1.7), "hull2", r=rx(-45 * s), bevel=0.04)
    for z in (-3.5, 3.5):                                 # bolt rows on the core plate edges
        for k in range(8):
            H.box(V((x0 - 2.1 + 0.6 * k, -12.53, z)), (0.18, 0.08, 0.18), "metal", bevel=0.0)
    # 2 x 3 torpedo tube hatches: raised collar, thin oxide lip, near-black bore
    for dx in (-1.3, 1.3):
        for z in (-2.4, 0.0, 2.4):
            m = Matrix.Translation((x0 + dx, 0, z)) @ parts.ALONG_Y
            H.lathe([(0.6, -12.5), (0.6, -12.76), (0.76, -12.76), (0.76, -12.5)], 12,
                    lambda i, j: ("dark", "merc", "hull2")[j], matrix=m)
            L.cyl(V((x0 + dx, -12.52, z)), 0.6, 0.6, 0.03, "glass", segs=12,
                  axis_rot=parts.ALONG_Y)
    n = V((0, -1, 1)).normalized()
    label("ORD", V((x0, -11.95, 4.05)) + n * 0.24, n, V((0, 1, 1)).normalized(), 0.6,
          wk.INK_LIGHT)
    SCORCH.append((x0, -12.6, 0.0, 1.8))
    # outboard armour: 2 courses x 6, bolted; the MX-12 plates stay hull2
    cyc = ("hull2", "hull2", "hull3", "merc")
    xo = sx * 31.25
    for course, zc in ((0, 1.55), (1, -1.55)):
        for k in range(6):
            y = -10.4 + 3.5 * k
            mat = cyc[(k + 2 * course) % 4]
            if course == 0 and k in (2, 3):
                mat = "hull2"
            if (sx < 0 and course == 1 and k == 4) or (sx > 0 and course == 1 and k == 1):
                mat = "scrap"
            H.box(V((xo, y, zc)), (0.5, 3.3, 2.9), mat, bevel=0.04)
            zb = zc + (1.2 if zc > 0 else -1.2)
            for o in (-1.2, 0.0, 1.2):
                H.box(V((sx * 31.55, y + o, zb)), (0.12, 0.22, 0.22), "dark", bevel=0.0)
    H.box(V((sx * 31.52, -1.5, 0)), (0.06, 21, 0.8), "merc", bevel=0.0)
    label("MX-12", V((sx * 31.52, -1.65, 1.7)), V((sx, 0, 0)), V((0, 0, 1)), 1.2, wk.INK_DARK)
    # hull number on top, text up +Y so it reads from the RTS camera
    label("12", V((x0, -3.0, 4.62)), V((0, 0, 1)), V((0, 1, 0)), 2.6, wk.INK_DARK, 0.8)
    # VLS lids, one open with a torpedo nose showing
    for i, dx in enumerate((-0.8, 0.8)):
        for j, y in enumerate((3.5, 5.0, 6.5)):
            x = x0 + dx
            H.box(V((x, y, 4.62)), (1.3, 1.4, 0.06), "hazard", bevel=0.0)
            if sx < 0 and abs(x - (-27.8)) < 1e-6 and y == 6.5:
                H.box(V((x, y, 4.64)), (1.0, 1.1, 0.06), "dark", bevel=0.0)
                hinge = V((x, y + 0.6, 4.66))
                H.box(hinge + rx(-100).to_3x3() @ V((0, -0.6, 0)), (1.1, 1.2, 0.12), "merc",
                      r=rx(-100), bevel=0.0)
                H.cyl(V((x, y, 5.1)), 0.42, 0.05, 1.0, "merc", segs=10)
                continue
            mat = "hull3" if (i + j) % 2 == 0 else "merc"
            H.box(V((x, y, 4.66)), (1.1, 1.2, 0.12), mat, bevel=0.0)
    lamp(V((x0, 7.8, 4.72)), 0.4, "light")
    for dx in (-2.1, 2.1):          # armour rails along the top edges
        H.box(V((x0 + dx, -1.5, 4.7)), (0.3, 20.0, 0.2), "dark", bevel=0.0)
    H.box(V((sx * 22.2, 2.0, -3.6)), (1.8, 1.4, 1.0), "dark", bevel=0.04)
    lamp(V((sx * 30.6, -10.9, 4.75)), 0.45, "red")       # one strobe per magazine
    # PDCs on top and belly, aimed forward and outboard
    yaw, pit = math.radians(25), math.radians(8)
    for zs in (1, -1):
        d = V((sx * math.sin(yaw) * math.cos(pit), -math.cos(yaw) * math.cos(pit),
               zs * math.sin(pit)))
        pdc(V((x0, -8.5, zs * 4.6)), V((0, 0, zs)), d, tab=zs > 0)


# ---------------------------------------------------------------- axle, drum, back
DRUM_PROFILE = [(4.6, 10.0), (10.4, 10.0), (11.0, 10.4), (11.4, 10.4), (11.4, 11.4),
                (11.0, 11.4), (11.0, 15.1), (11.2, 15.1), (11.2, 15.9), (11.0, 15.9),
                (11.0, 19.6), (11.4, 19.6), (11.4, 20.6), (11.0, 20.6), (10.4, 21.0),
                (4.6, 21.0), (4.6, 10.0)]


def drum_mat(i, j):
    if j in (0, 14):
        return "hull2"
    if j in (1, 13, 2, 3, 4, 10, 11, 12, 15):
        return "dark"
    if j in (6, 7, 8):
        return "merc"
    if i % 11 == 3:
        return "scrap"
    if i % 5 == 0:
        return "hull3"
    return "hull"


def build_axle():
    parts.prism(H, 9.1, 32.3, (5.4, 5.4, 1.2), (5.4, 5.4, 1.2), "hull2")
    for y in (24.0, 29.0):
        parts.prism(H, y, y + 0.6, (5.6, 5.6, 1.25), (5.6, 5.6, 1.25), "merc")
    for k, (px, pz) in enumerate(((-2.9, 2.0), (2.9, 2.0), (-2.9, -2.0), (2.9, -2.0))):
        H.tube(V((px, 9.1, pz)), V((px, 32.3, pz)), 0.2, 0.2, "metal" if k % 2 else "accent",
               segs=8)


def build_drum():
    H.lathe(DRUM_PROFILE, 32, drum_mat, matrix=parts.ALONG_Y)
    for k in range(6):
        a = math.radians(30 + 60 * k)
        H.box(V((7.6 * math.cos(a), 9.85, 7.6 * math.sin(a))), (5.6, 0.3, 0.9),
              "merc" if k % 2 == 0 else "dark", bevel=0.04, r=Matrix.Rotation(-a, 4, "Y"))
    for k in range(6):
        for da in (-14, 14):
            a = math.radians(60 * k + da)
            parts.window(L, V((9 * math.cos(a), 10.0, 9 * math.sin(a))), V((0, -1, 0)),
                         V((0, 0, 1)), 0.6, 0.5, parts.pick_lit(RNG, "hab"))
    rf = 11.0 * math.cos(math.pi / 32)
    for y in (12.6, 18.4):
        for k in range(32):
            if k % 4 == 3:                              # 24 per row, a blank every 4th
                continue
            a = (k + 0.5) * 2 * math.pi / 32
            d = V((math.cos(a), 0, -math.sin(a)))      # lathe facet direction (ALONG_Y)
            if d.z < -math.cos(math.radians(15)):
                continue
            parts.window(L, d * rf + V((0, y, 0)), d, V((0, 1, 0)), 0.55, 0.45,
                         parts.pick_lit(RNG, "hab"))
    for deg in (45, 135, 225, 315):
        a = math.radians(deg)
        lamp(V((11.5 * math.cos(a), 10.9, 11.5 * math.sin(a))), 0.45, "red")
    for deg, text in ((60, "MERC"), (120, "SPIN")):
        a = math.radians(deg)
        c = V((6.2 * math.cos(a), 9.95, 6.2 * math.sin(a)))
        H.box(c, (2.8, 0.08, 1.0), "hull2", bevel=0.0)
        label(text, c - V((0, 0.05, 0)), V((0, -1, 0)), V((0, 0, 1)), 0.7, wk.INK_DARK)
    # bearing collars and hazard seams: fixed axle vs spinning drum
    for y0, y1 in ((8.9, 10.0), (21.0, 22.2)):
        H.lathe([(2.8, y0), (5.4, y0), (5.4, y1), (2.8, y1), (2.8, y0)], 24,
                lambda i, j: "dark", matrix=parts.ALONG_Y)
        H.cyl(V((0, (y0 + y1) / 2, 0)), 5.47, 5.47, 0.25, "hazard", segs=24,
              axis_rot=parts.ALONG_Y)


RAD_HUB_X = 8.0                              # fin hub, both sides of the axle
RAD_FANS = (8.0, -12.0, -32.0)               # blade sweep in plan, deg from +-X toward +Y
RAD_R0, RAD_R1 = 3.0, 16.5                   # blade span from the hub
RAD_W = 1.9                                  # blade chord
RAD_TILT = 40.0                              # blade twist about its long axis, deg


def build_radiators():
    """Radiator fans: a short boom off the axle carries a coolant hub each side, and each
    hub fans three long, narrow blades out in plan (swept 8, -12 and -32 deg) so they show
    as separate feathers from the top camera. The blades are twisted 40 deg about their
    long axis (alternating), plain dark grey with fine lengthwise ribs, a coolant spar and
    a faint warm core strip in _lights."""
    for y in (27.6, 28.4):
        for z in (-0.5, 0.5):
            H.beam(V((-RAD_HUB_X, y, z)), V((RAD_HUB_X, y, z)), 0.32, 0.32, "dark")
    for k in range(4):
        x = -RAD_HUB_X + 4 * k
        parts.strut(H, V((x, 27.6, -0.5)), V((x + 4, 28.4, 0.5)), 0.18, 0.18, "dark")
    length = RAD_R1 - RAD_R0
    for sx in (-1, 1):
        hub = V((sx * RAD_HUB_X, 28.0, 0))
        H.cyl(hub, 1.3, 1.3, 1.8, "dark", segs=12)
        H.cyl(hub, 1.38, 1.38, 0.35, "merc", segs=12)
        for k, phi in enumerate(RAD_FANS):
            p = math.radians(phi)
            d = V((sx * math.cos(p), math.sin(p), 0))
            yaw = p if sx > 0 else math.pi - p
            R = rz(yaw) @ rx(RAD_TILT * (1 if k % 2 == 0 else -1))
            ch = R.to_3x3() @ V((0, 1, 0))
            nrm = R.to_3x3() @ V((0, 0, 1))
            c = hub + d * ((RAD_R0 + RAD_R1) / 2)
            H.tube(hub + d * 1.0, hub + d * (RAD_R0 + 0.3), 0.24, 0.24, "metal", segs=8)
            H.box(c, (length, RAD_W, 0.1), "dark", r=R, bevel=0.0)
            for t in (-0.6, 0.6):               # fine lengthwise ribs, both faces
                for s in (-1, 1):
                    H.box(c + ch * t + nrm * s * 0.06, (length - 0.4, 0.05, 0.03), "hull2",
                          r=R, bevel=0.0)
            H.tube(hub + d * RAD_R0, hub + d * (RAD_R1 - 0.2), 0.13, 0.1, "metal", segs=6)
            for s in (-1, 1):                   # faint warm core strip
                L.box(c + d * 0.4 + nrm * s * 0.07 + ch * 0.25, (length - 1.6, 0.14, 0.02),
                      "window_dim", r=R, bevel=0.0)
        tip = hub + V((sx * math.cos(math.radians(8)), math.sin(math.radians(8)), 0)) * RAD_R1
        lamp(tip + V((0, 0, 0.12)), 0.45, "red")


def build_back():
    wk.lattice_mast(H, V((0, 24.0, 2.7)), 13.0, 0.8, 0.45, 4, "dark", chord=0.24, brace=0.12)
    parts.dish(H, V((0.6, 24.4, 10.8)), 1.0, V((0.2, -0.5, 0.85)), "hull", "dark")
    lamp(V((0, 24.0, 13.3)), 0.45, "red")
    pdc(V((0, 30.2, 2.7)), V((0, 0, 1)), V((0.8, 0.45, 0.4)))
    pdc(V((0, 30.2, -2.7)), V((0, 0, -1)), V((-0.8, 0.45, -0.4)))
    # link port at the axle tail
    H.cyl(V((0, 32.9, 0)), 2.3, 2.3, 1.2, "dark", segs=12, axis_rot=parts.ALONG_Y)
    H.cyl(V((0, 33.5, 0)), 1.7, 1.7, 0.15, "hull", segs=12, axis_rot=parts.ALONG_Y)
    H.box(V((0, 33.55, 1.95)), (1.6, 0.1, 0.4), "dark", bevel=0.0)
    label("#BAR", V((0, 33.6, 1.95)), V((0, 1, 0)), V((0, 0, 1)), 0.3, wk.INK_DARK)
    for sx in (-1, 1):
        lamp(V((sx * 2.3, 33.0, 0.0)), 0.35, "red")      # on the collar sides


# ---------------------------------------------------------------- checks
def _box_bm(lo, hi):
    bm = bmesh.new()
    lo, hi = V(lo), V(hi)
    m = Matrix.Translation((lo + hi) / 2) @ Matrix.Diagonal((*(hi - lo), 1.0))
    bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    return bm


def measure_fighter():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=FIGHTER_GLB)
    new = [o for o in bpy.data.objects if o not in before]
    bpy.context.view_layer.update()
    lo, hi = [1e9] * 3, [-1e9] * 3
    for o in new:
        if o.type != "MESH" or o.name.startswith("engine_glow"):
            continue
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for i in range(3):
                lo[i], hi[i] = min(lo[i], w[i]), max(hi[i], w[i])
    for o in new:
        bpy.data.objects.remove(o)
    hw = max(-lo[0], hi[0])
    got = dict(SHIP_HW=hw, SHIP_ZMIN=lo[2], SHIP_ZMAX=hi[2], NOSE_Y=BERTH_Y - hi[1],
               TAIL_Y=BERTH_Y - lo[1])
    want = dict(SHIP_HW=SHIP_HW, SHIP_ZMIN=SHIP_ZMIN, SHIP_ZMAX=SHIP_ZMAX, NOSE_Y=NOSE_Y,
                TAIL_Y=TAIL_Y)
    ok = all(abs(got[k] - want[k]) <= 0.05 for k in got)
    print("FIGHTER bounds", {k: round(v, 3) for k, v in got.items()}, "OK" if ok else "FAIL")
    return ok


def check_build():
    """Forbidden boxes (docking corridors, sideways path, outer berth spots) and the footprint
    radius, on H.bm / L.bm in world coordinates. Returns True when everything is clear."""
    ok = measure_fighter()
    boxes = []
    for i, bx in enumerate(BAYS):
        boxes.append((f"bay{i + 1}_A", (bx - LANE_HW, -40.0, -LANE_HH),
                      (bx + LANE_HW, NOSE_Y, LANE_HH)))
        boxes.append((f"bay{i + 1}_B", (bx - LANE_HW, NOSE_Y, SHIP_ZMIN - 0.3),
                      (bx + LANE_HW, 3.5, SHIP_ZMAX + 0.3)))
    boxes.append(("path_C", (-46.0, -42.0, -4.0), (46.0, -21.0, 6.0)))
    _, outer = berths()
    for k, p in enumerate(outer):
        boxes.append((f"outer{k}_D", tuple(p - V((5, 5, 5))), tuple(p + V((5, 5, 5)))))
    trees = []
    for part in (H, L):
        part.bm.faces.ensure_lookup_table()
        part.bm.normal_update()
        trees.append((part, BVHTree.FromBMesh(part.bm)))
    eps = 1e-4
    for name, lo, hi in boxes:
        lo, hi = V(lo), V(hi)
        n_in, hits = 0, []
        bbm = _box_bm(lo, hi)
        btree = BVHTree.FromBMesh(bbm)
        for part, tree in trees:
            for v in part.bm.verts:
                c = v.co
                if all(lo[i] + eps < c[i] < hi[i] - eps for i in range(3)):
                    n_in += 1
                    if len(hits) < 3:
                        f = v.link_faces[0] if v.link_faces else None
                        hits.append((part.name, part.slots[f.material_index].name if f else "?",
                                     tuple(round(x, 2) for x in c)))
            for fa, _fb in tree.overlap(btree):
                n_in += 1
                if len(hits) < 3:
                    f = part.bm.faces[fa]
                    hits.append((part.name, part.slots[f.material_index].name,
                                 tuple(round(x, 2) for x in f.calc_center_median())))
        bbm.free()
        print(f"BERTH CHECK {name} {'OK' if n_in == 0 else 'FAIL'} {n_in}"
              + (f" first {hits}" if hits else ""))
        ok = ok and n_in == 0
    far = max((v.co for part in (H, L) for v in part.bm.verts), key=lambda c: c.xy.length)
    r = far.xy.length
    print(f"BERTH CHECK footprint max XY radius {r:.2f} at {tuple(round(x, 2) for x in far)} "
          f"{'OK' if r <= 40.0 else 'FAIL'}")
    ok = ok and r <= 40.0
    print("BERTH CHECK", "ALL OK" if ok else "FAILED")
    return ok


# ---------------------------------------------------------------- assembly
def build_outpost(check=False):
    global H, L
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    H = parts.PanelPart(f"{PRE}_hull", MATS)
    L = parts.PanelPart(f"{PRE}_lights", MATS)
    build_rack()
    build_girder()
    build_gondola()
    build_tanks()
    for sx in (-1, 1):
        magazine(sx)
    build_axle()
    build_drum()
    build_radiators()
    build_back()
    if check:
        check_build()
    root = parts.make_root(PRE, size=10)
    hull = H.finish(root)
    lights = L.finish(root)
    lights.data.uv_layers.remove(lights.data.uv_layers["panel"])
    for name, pos, rzz in (("dock_point", DOCK_POS, math.pi), ("spawn_point", SPAWN_POS, math.pi),
                           ("link_point", LINK_POS, 0.0)):
        parts.add_empty(name, root, pos, rot_z=rzz, size=4)
    return root, hull, lights


def berths():
    """Blender-space berth origins, mirroring Building.berth_transform (building.gd):
    inner = dock - out*depth + side*row*spacing, side = out x up (Godot) = Blender -X."""
    dock, spawn = V(DOCK_POS), V(SPAWN_POS)
    out = V((0, -1, 0))
    side = V((-1, 0, 0))
    res = []
    for i in range(INNER_BERTHS):
        row = i - (INNER_BERTHS - 1) * 0.5
        p = dock - out * BERTH_DEPTH + side * row * BERTH_SPACING
        res.append(V((p.x, p.y, dock.z)))
    outer = []
    for k in range(4):
        sgn = -1.0 if k % 2 == 0 else 1.0
        p = spawn - out * 8.0 + side * sgn * (OUTER_SIDE + OUTER_STEP * (k // 2))
        outer.append(V((p.x, p.y, dock.z + OUTER_HEIGHT)))
    return res, outer


def add_ships():
    """Preview only: one merc_interceptor per inner berth, nose out (not exported)."""
    inner, outer = berths()
    for p in inner:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=FIGHTER_GLB)
        new = [o for o in bpy.data.objects if o not in before]
        r = next(o for o in new if o.parent is None)
        r.location = p
        r.rotation_mode = "XYZ"
        r.rotation_euler = (0, 0, math.pi)
    for i, p in enumerate(inner):
        print(f"BERTH inner {i} blender {tuple(round(c, 2) for c in p)} "
              f"godot ({p.x:.2f}, {p.z:.2f}, {-p.y:.2f})")
    for i, p in enumerate(outer):
        print(f"BERTH outer {i} blender {tuple(round(c, 2) for c in p)}")


def previews(ships):
    sfx = "_ships" if ships else ""
    os.makedirs(PREVIEW_COPY, exist_ok=True)
    target = (0.0, 6.0, 0.0)
    common.setup_preview(cam_loc=(target[0] - 45, target[1] - 75, target[2] + 80),
                         cam_target=target, ortho_scale=100, res=(1600, 1200),
                         key_dir=(-0.6, -0.35, 0.7), key_energy=3.5)
    a = os.path.join(common.PREVIEW_DIR, f"{PRE}_preview{sfx}.png")
    common.render(a)
    scene = bpy.context.scene
    cam = scene.camera
    cam.location = (0.0, 7.0, 200)
    cam.rotation_euler = (0, 0, 0)
    cam.data.ortho_scale = 92
    scene.render.resolution_x, scene.render.resolution_y = 1200, 1200
    b = os.path.join(common.PREVIEW_DIR, f"{PRE}_top{sfx}.png")
    common.render(b)
    for p in (a, b):
        shutil.copy(p, PREVIEW_COPY)


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, hull, lights = build_outpost(check="--check" in argv)
    if "--no-textures" not in argv:
        wk.texture([hull], MATS, PRE, NO_PADS, scorch=SCORCH, decals=DECALS, labels=LABELS,
                   seed0=53)
    wk.stats([hull, lights])
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        previews(False)
        if "--no-ships" not in argv and os.path.exists(FIGHTER_GLB):
            add_ships()
            previews(True)


main()
