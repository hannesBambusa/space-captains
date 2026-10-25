"""Generate the Salvage Yard (scrap processing yard) .glb and previews.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_salvage_yard.py
  Options after `--`: --no-preview, --no-textures, --no-ships (preview without salvagers).
Textures: one 2048 worn-industrial atlas (worn_kit / station_textures.WORN_KINDS plus the
"rust", "scrap" and "ore" kinds), saved as blender/textures/salvage_yard_*.jpg. The moving
belt reuses the mining outpost's belt tile (blender/textures/outpost_belt_*), so run
gen_mining_outpost.py first on a clean checkout.

Design: scrap yard run as a small business. Salvagers back into an open-topped two-ship
berth; a slewing claw crane on the +X wall grabs scrap out of the docked hold and drops it
into the jaw crusher hopper beside the berth; a conveyor carries the crushed scrap up to
the sorting house over three ore bins (iron, titanium, crystal) at the back right; a
reprocessing furnace block stands at the back; on -X the scrap field: rusted hull
sections, junk piles, a baler press and stacked bales.

Layout (Blender Z up, exported +Y up; Blender -Y = Godot +Z). Centre at origin, plane z=0.
  berth    x -10..10 open bay, deck top z -3, walls to z 3.4, mouth y -14 (Godot +Z)
  crane    pedestal top PIVOT (12.5, 3.0, 8.2); claw rests over berth 0's hold (4.4, -3.5),
           swings +78.6 deg about up to the crusher hopper HOPPER (17.27, -6.23)
  belt     crusher outlet -> sorting house, x 17.3, y -1.5..11
  bins     three open bins at y 15.5, x 12.5 / 17.3 / 22.1 (the middle one holds the fill)
  scrap    field x -28..-12, y -14..12; baler press (-15.5, 13)
  furnace  back centre x -8..7, y 9..19
Hierarchy: salvage_yard (empty root) -> salvage_yard_hull, salvage_yard_lights,
  unload_arm (origin at the slewing ring), ore_conveyor_belt (origin at the tail),
  ore_silo_fill (origin at the bin floor, scale Godot Y 1 = full), unload_lights,
  dock_point, spawn_point, link_point, ore_flow_point (empties).
Same node names and swing convention as the mining outpost, so OutpostUnloadFx drives it.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
import station_textures as st  # noqa: E402
import worn_kit as wk  # noqa: E402

V = Vector
PRE = "salvage_yard"
OUT = os.path.join(common.ROOT, "assets", "models", "buildings", "salvage_yard.glb")
BLEND = os.path.join(common.ROOT, "blender", "salvage_yard.blend")
SALVAGER_GLB = os.path.join(common.ROOT, "assets", "models", "ships", "salvager.glb")
BELT_TEX = [os.path.join(st.TEX_DIR, f"outpost_belt_{n}") for n in
            ("albedo.jpg", "mr.png", "normal.png")]
DOCK_POS = V((0.0, -14.0, 0.0))
SPAWN_POS = V((0.0, -32.0, 0.0))
LINK_POS = V((0.0, 19.6, 1.5))
MOUTH_Y, BACK_Y = -14.0, 7.0
DECK_Z, WALL_TOP = -3.0, 3.4
WALL_IN, WALL_OUT = 9.6, 11.0
BERTH_X, BERTH_Y = 4.4, -3.0
HOLD = V((4.4, -3.5, 0.0))
PIVOT = V((12.5, 3.0, 8.2))
SWING = math.radians(78.6)
R_ARM = (HOLD.xy - PIVOT.xy).length
A_HOLD = math.atan2(HOLD.y - PIVOT.y, HOLD.x - PIVOT.x)
HOPPER = V((PIVOT.x + R_ARM * math.cos(A_HOLD + SWING),
            PIVOT.y + R_ARM * math.sin(A_HOLD + SWING), 0.0))
HOPPER_RIM = 4.2
FLOW_Z = 5.6
BELT0 = V((HOPPER.x, -1.6, -1.6))
BELT1 = V((HOPPER.x, 11.0, 7.0))
BINS_Y = 15.5
BINS_X = (HOPPER.x - 4.8, HOPPER.x, HOPPER.x + 4.8)
BIN_W, BIN_FLOOR, BIN_TOP = 4.2, -3.0, 2.6
LABELS = ["SALV-3", "FE", "TI", "CR", "#BAR", "#CHEV", "NO STEP", "CRUSH"]

MATS = {}
DECALS = []
SCORCH = []
BEACONS = []
H = L = A = F = None
RNG = random.Random(11)


def label(text, centre, normal, up, h, colour, opacity=0.85):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity))


def lamp(pos, s=0.4, mat="light"):
    wk.lamp(L, pos, s, mat)


def unload_beacon(pos):
    """Housing in the hull, the amber lens goes into unload_lights."""
    p = V(pos)
    H.cyl(p + V((0, 0, -0.25)), 0.3, 0.3, 0.5, "dark", segs=6)
    BEACONS.append(p)


# ---------------------------------------------------------------- berth
def build_berth():
    y0, y1 = MOUTH_Y, BACK_Y
    cy, ln = (y0 + y1) / 2, y1 - y0
    H.box(V((0, cy, DECK_Z - 1.0)), (2 * WALL_OUT, ln, 2.0), "hull2", bevel=0.0)
    H.box(V((0, cy, DECK_Z - 0.05)), (2 * WALL_IN, ln - 0.5, 0.1), "pad", bevel=0.0)
    H.box(V((0, cy - 1.0, DECK_Z - 2.6)), (2 * WALL_OUT + 2.0, ln + 3.0, 1.4), "dark", bevel=0.0)
    for sx in (-1, 1):
        x = sx * (WALL_IN + WALL_OUT) / 2
        H.box(V((x, cy, (WALL_TOP + DECK_Z) / 2)), (WALL_OUT - WALL_IN, ln, WALL_TOP - DECK_Z),
              "hull", bevel=0.04)
        H.box(V((x, cy, WALL_TOP + 0.15)), (WALL_OUT - WALL_IN + 0.3, ln + 0.2, 0.3), "hazard",
              bevel=0.0)
        for k in range(6):   # buttresses on the outer face
            yy = y0 + 1.0 + k * (ln - 2.0) / 5
            H.slab([(0, -2.0), (1.6, -2.0), (0, 3.0)], -0.35, 0.35, "dark",
                   matrix=Matrix.Translation((sx * WALL_OUT, yy, 0))
                   @ Matrix(((sx, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1))))
        # bumper rails + deck markings
        H.box(V((sx * (WALL_IN - 0.2), cy, -1.6)), (0.4, ln - 2.0, 0.6), "accent", bevel=0.0)
        H.box(V((sx * BERTH_X, BERTH_Y - 2.0, DECK_Z + 0.03)), (0.25, 14.0, 0.05), "hull",
              bevel=0.0)
        lamp((sx * (WALL_IN - 0.05), y0 + 0.6, 2.6), 0.4, "light")
        lamp((sx * (WALL_IN - 0.05), y1 - 0.6, 2.6), 0.4, "red")
        for k in range(4):
            lamp((sx * (WALL_IN - 0.45), y0 + 3.0 + k * 4.5, -1.2), 0.3, "light")
    # back wall with a control window, berth number
    H.box(V((0, y1 + 0.8, 0.5)), (2 * WALL_OUT, 1.6, 7.0), "hull2", bevel=0.04)
    wk.win_row(L, RNG, (-6, y1 - 0.02, 2.0), (6, y1 - 0.02, 2.0), (0, -1, 0), 8, 0.8, 0.6, "work")
    label("SALV-3", (0.0, y1 - 0.02, -0.6), (0, -1, 0), (0, 0, 1), 1.0, wk.INK_DARK)
    # mouth: hazard sill, posts with lamps
    H.box(V((0, y0 - 0.3, DECK_Z + 0.05)), (2 * WALL_IN, 0.6, 0.1), "hazard", bevel=0.0)
    for sx in (-1, 1):
        H.box(V((sx * (WALL_OUT - 0.4), y0 - 0.6, 0.6)), (1.6, 1.2, 7.6), "hull2", bevel=0.06)
        lamp((sx * (WALL_OUT - 0.4), y0 - 1.22, 3.8), 0.4, "light")
        unload_beacon((sx * (WALL_OUT - 0.4), y0 - 0.6, 4.6))
    # apron
    ay0, ay1 = y0 - 1.2, y0 - 9.0
    H.box(V((0, (ay0 + ay1) / 2, DECK_Z - 1.0)), (2 * WALL_OUT, ay0 - ay1, 2.0), "pad", bevel=0.0)
    H.box(V((0, ay1 + 0.3, DECK_Z + 0.03)), (2 * WALL_OUT, 0.6, 0.05), "hazard", bevel=0.0)
    for k in range(3):
        for sx in (-1, 1):
            lamp((sx * BERTH_X, ay0 - 1.5 - k * 2.2, DECK_Z + 0.08), 0.4, "light")
    label("NO STEP", (0.0, ay1 + 2.5, DECK_Z + 0.04), (0, 0, 1), (0, 1, 0), 0.9, wk.INK_LIGHT,
          0.6)
    for sx in (-1, 1):
        SCORCH.append((sx * BERTH_X, BERTH_Y - 9.0, DECK_Z, 3.0))


# ---------------------------------------------------------------- crane (static + arm)
def build_crane():
    """Pedestal (hull) + unload_arm: slewing deck, cab, boom out to the hold, claw."""
    p = PIVOT
    # pedestal from the yard deck beside the +X wall
    H.box(V((p.x, p.y, DECK_Z - 1.2)), (5.0, 5.0, 2.4), "dark", bevel=0.0)
    H.cyl(V((p.x, p.y, (DECK_Z + p.z - 0.6) / 2)), 1.6, 1.25, p.z - 0.6 - DECK_Z, "hull2", segs=12)
    H.cyl(V((p.x, p.y, p.z - 0.4)), 2.0, 2.0, 0.6, "dark", segs=14)
    H.box(V((p.x - 1.3, p.y, 1.0)), (0.8, 1.4, 1.8), "hazard", bevel=0.05)
    label("#BAR", (p.x, p.y - 1.37, 2.0), (0, -1, 0), (0, 0, 1), 0.5, wk.INK_DARK)
    # arm: built in world space (rest pose: boom over the hold), origin moved to PIVOT later
    d = (HOLD.xy - p.xy).normalized().to_3d()
    s = V((-d.y, d.x, 0))
    a = math.atan2(d.y, d.x)
    A.cyl(p + V((0, 0, 0.25)), 2.2, 2.2, 0.5, "accent", segs=14)
    A.box(p + V((0, 0, 1.4)) - d * 1.8, (3.0, 2.6, 1.6), "hull2", rot_z=a, bevel=0.06)  # house
    A.box(p + V((0, 0, 1.4)) - d * 3.2, (1.4, 2.4, 1.8), "dark", rot_z=a, bevel=0.0)    # ballast
    cab = p + V((0, 0, 1.6)) + s * 1.6 + d * 0.6
    A.box(cab, (1.8, 1.4, 1.6), "hull", rot_z=a, bevel=0.08)
    A.box(cab + d * 0.92 + V((0, 0, 0.2)), (0.06, 1.1, 0.6), "window", rot_z=a, bevel=0.0)
    # boom: two box chords tapering to the head over the hold
    tip = HOLD + V((0, 0, p.z + 2.6))
    foot = p + V((0, 0, 1.2)) + d * 0.6
    for o in (s * 0.55, -s * 0.55):
        A.beam(foot + o, tip + o * 0.6, 0.75, 0.9, "accent")
    for k in range(5):
        q = foot.lerp(tip, (k + 0.5) / 5)
        w = 0.55 - 0.22 * (k + 0.5) / 5
        A.beam(q + s * w + V((0, 0, 0.5)), q - s * w + V((0, 0, 0.5)), 0.3, 0.3, "dark")
    A.box(tip, (1.8, 1.9, 1.3), "hull2", rot_z=a, bevel=0.08)       # boom head
    A.beam(p + V((0, 0, 2.2)) - d * 1.0, p + V((0, 0, 5.5)), 0.4, 0.4, "dark")  # A-frame
    A.beam(p + V((0, 0, 5.5)), tip + V((0, 0, 0.4)), 0.08, 0.08, "dark")
    A.beam(p + V((0, 0, 5.5)), p + V((0, 0, 2.2)) - d * 3.4, 0.08, 0.08, "dark")
    A.box(p + V((0, 0, 5.8)), (0.4, 0.4, 0.4), "red", bevel=0.0)
    # hoist lines + orange-peel claw hanging over the hold
    cz = 4.4
    hub = V((HOLD.x, HOLD.y, cz + 1.0))
    for o in (s * 0.25, -s * 0.25):
        A.beam(tip + o + V((0, 0, -0.45)), hub + o + V((0, 0, 0.6)), 0.05, 0.05, "dark")
    A.cyl(hub + V((0, 0, 0.3)), 0.6, 0.7, 0.8, "hazard", segs=8)
    A.cyl(hub + V((0, 0, -0.25)), 0.85, 0.85, 0.35, "dark", segs=8)
    for k in range(5):     # claw tines, half closed
        ta = k * 2 * math.pi / 5
        r0 = V((math.cos(ta), math.sin(ta), 0))
        k0 = hub + r0 * 0.75 + V((0, 0, -0.35))
        k1 = hub + r0 * 1.35 + V((0, 0, -1.2))
        k2 = hub + r0 * 0.7 + V((0, 0, -2.0))
        A.beam(k0, k1, 0.28, 0.22, "metal", up=V((0, 0, 1)))
        A.beam(k1, k2, 0.26, 0.2, "metal", up=V((0, 0, 1)))
    A.box(tip + V((0, 0, 0.55)), (0.3, 0.3, 0.2), "light", bevel=0.0)


# ---------------------------------------------------------------- crusher, belt, bins
def build_crusher():
    c = HOPPER
    # base deck for the +X processing line
    H.box(V((HOPPER.x, 4.0, DECK_Z - 1.4)), (14.0, 30.0, 2.0), "dark", bevel=0.0)
    H.box(V((HOPPER.x, 4.0, DECK_Z - 0.35)), (13.0, 29.0, 0.1), "pad", bevel=0.0)
    H.box(V((WALL_OUT + 0.6, 4.0, DECK_Z - 1.4)), (2.0, 20.0, 1.6), "dark", bevel=0.0)
    # jaw crusher body: heavy block, flywheels on both sides, outlet chute to the belt tail
    H.box(V((c.x, c.y, -1.4)), (5.6, 5.0, 3.6), "hull2", bevel=0.05)
    H.box(V((c.x, c.y, 0.5)), (6.0, 5.4, 0.4), "dark", bevel=0.0)
    for sx in (-1, 1):
        H.cyl(V((c.x + sx * 3.15, c.y - 0.6, -0.6)), 1.9, 1.9, 0.5, "accent", segs=14,
              axis_rot=parts.ALONG_X)
        H.cyl(V((c.x + sx * 3.45, c.y - 0.6, -0.6)), 0.5, 0.5, 0.3, "metal", segs=8,
              axis_rot=parts.ALONG_X)
    H.box(V((c.x + 3.6, c.y + 1.6, -1.6)), (1.4, 1.6, 2.4), "dark", bevel=0.05)     # motor
    H.box(V((c.x, c.y + 2.9, -1.5)), (2.4, 1.6, 1.4), "dark", bevel=0.0)            # chute
    label("CRUSH", (c.x, c.y - 2.52, -1.6), (0, -1, 0), (0, 0, 1), 0.8, wk.INK_DARK)
    # hopper: square funnel on four legs, rim at HOPPER_RIM
    prof = [(0.0, 0.8), (1.2, 0.8), (1.3, 1.2), (3.2, HOPPER_RIM - 0.4), (3.4, HOPPER_RIM),
            (3.0, HOPPER_RIM), (1.1, 1.4), (0.0, 1.4)]
    hm = {0: "dark", 1: "dark", 2: "rust", 3: "hazard", 4: "dark", 5: "rust", 6: "dark"}
    H.lathe(prof, 4, lambda i, j: hm[j], matrix=Matrix.Translation((c.x, c.y, 0)),
            start=math.pi / 4)
    H.lathe([(0.0, 3.1), (1.4, 2.8), (2.6, 2.2), (0.0, 2.2)], 8, lambda i, j: "scrap",
            matrix=Matrix.Translation((c.x, c.y, 0)))
    for k in range(4):
        ang = math.pi / 4 + k * math.pi / 2
        H.beam(V((c.x + 3.3 * math.cos(ang), c.y + 3.3 * math.sin(ang), HOPPER_RIM - 0.2)),
               V((c.x + 3.3 * math.cos(ang), c.y + 3.3 * math.sin(ang), DECK_Z - 0.4)), 0.35,
               0.35, "dark")
    for k in range(4):
        ang = math.pi / 4 + k * math.pi / 2
        unload_beacon((c.x + 3.3 * math.cos(ang), c.y + 3.3 * math.sin(ang), HOPPER_RIM + 0.55))
    SCORCH.append((c.x, c.y, HOPPER_RIM, 3.0))


def build_belt_frame():
    d = BELT1 - BELT0
    dn = d.normalized()
    ac = V((1, 0, 0))
    up = (V((0, 0, 1)) - dn * dn.z).normalized()
    for sx in (-1, 1):   # side stringers
        H.beam(BELT0 + ac * sx * 1.35 + up * 0.1, BELT1 + ac * sx * 1.35 + up * 0.1, 0.25, 0.5,
               "accent")
    n = 6
    for k in range(n + 1):  # idler frames + trestle legs
        q = BELT0 + d * (k / n)
        H.beam(q - ac * 1.4 - up * 0.2, q + ac * 1.4 - up * 0.2, 0.25, 0.25, "dark")
        if 0 < k < n:
            for sx in (-1, 1):
                parts.strut(H, q + ac * sx * 1.3 - up * 0.3, V((q.x + sx * 1.6, q.y, DECK_Z - 0.3)),
                            0.3, 0.3, "dark")
    H.cyl(BELT0 + V((0, 0, -0.1)), 0.45, 0.45, 2.6, "metal", segs=8, axis_rot=parts.ALONG_X)
    # walkway beside the belt
    H.beam(BELT0 + ac * 2.2 - up * 0.1, BELT1 + ac * 2.2 - up * 0.1, 1.0, 0.12, "pad")


def build_belt():
    """ore_conveyor_belt: troughed belt surface BELT0 -> BELT1, UV u across (0..1), v along in
    4.8 m tiles (v = 0 at the crusher end). Same convention as the mining outpost."""
    d = BELT1 - BELT0
    dn = d.normalized()
    up = (V((0, 0, 1)) - dn * dn.z).normalized()
    ac = V((1, 0, 0))
    sec = [(-1.2, 0.28), (-0.75, 0.02), (0.75, 0.02), (1.2, 0.28)]
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
            uvs.append((u, d.length * t / 4.8))
    faces = [(k * 4 + i, k * 4 + i + 1, k * 4 + i + 5, k * 4 + i + 4)
             for k in range(n) for i in range(3)]
    me = bpy.data.meshes.new("ore_conveyor_belt")
    me.from_pydata([tuple(v) for v in verts], [], faces)
    uvl = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li, vi in zip(poly.loop_indices, poly.vertices):
            uvl.data[li].uv = uvs[vi]
    me.update()
    if me.polygons[0].normal.dot(up) < 0:
        for poly in me.polygons:
            poly.flip()
        me.update()
    if all(os.path.exists(p) for p in BELT_TEX):
        mat = st.pbr_material("ore_belt", st.load_saved(BELT_TEX[0], False),
                              st.load_saved(BELT_TEX[1], True), st.load_saved(BELT_TEX[2], True))
    else:
        mat = common.make_material("ore_belt", (0.05, 0.05, 0.05), roughness=0.8)
    me.materials.append(mat)
    obj = bpy.data.objects.new("ore_conveyor_belt", me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def build_bins():
    # sorting house over the belt head: drops into a distributor over the bins
    sh = V((BELT1.x, BELT1.y + 1.0, BELT1.z + 0.5))
    H.box(sh, (5.0, 5.0, 4.0), "hull", bevel=0.05)
    H.box(sh + V((0, 0, 2.2)), (5.4, 5.4, 0.4), "dark", bevel=0.0)
    wk.win_row(L, RNG, sh + V((-1.8, -2.52, 0.6)), sh + V((1.8, -2.52, 0.6)), (0, -1, 0), 3,
               0.6, 0.5, "work")
    H.box(V((BINS_X[1], BINS_Y, BIN_TOP + 2.6)), (14.6, 1.6, 1.2), "hull2", bevel=0.05)
    H.box(V((BINS_X[1], BINS_Y - 0.82, BIN_TOP + 3.1)), (14.0, 0.06, 0.25), "hazard", bevel=0.0)
    for x in BINS_X:   # chute spouts
        H.box(V((x, BINS_Y, BIN_TOP + 1.6)), (1.0, 1.0, 1.0), "dark", bevel=0.0)
    for x in (BINS_X[0] - 2.4, BINS_X[2] + 2.4):   # gantry posts
        H.box(V((x, BINS_Y, 1.5)), (0.6, 0.8, 9.0), "dark", bevel=0.0)
    # bins: open boxes, walls 0.4 thick, ore heaps, labels on the front faces
    heaps = ("ore", "scrap", "ore")
    for i, x in enumerate(BINS_X):
        w = BIN_W
        hz = (BIN_FLOOR + BIN_TOP) / 2
        hh = BIN_TOP - BIN_FLOOR
        H.box(V((x, BINS_Y, BIN_FLOOR - 0.2)), (w, w, 0.4), "dark", bevel=0.0)
        for sx in (-1, 1):
            H.box(V((x + sx * (w / 2 - 0.2), BINS_Y, hz)), (0.4, w, hh), "hull3", bevel=0.0)
            H.box(V((x, BINS_Y + sx * (w / 2 - 0.2), hz)), (w - 0.8, 0.4, hh), "hull3", bevel=0.0)
        H.box(V((x, BINS_Y - w / 2 - 0.02, BIN_TOP - 0.3)), (w, 0.1, 0.4), "hazard", bevel=0.0)
        label(("FE", "TI", "CR")[i], (x, BINS_Y - w / 2 - 0.03, 0.2), (0, -1, 0), (0, 0, 1),
              0.9, wk.INK_DARK)
        if i != 1:   # static heaps; the middle bin gets ore_silo_fill
            H.lathe([(0.0, 1.6), (0.9, 1.4), (1.7, 0.6), (1.75, BIN_FLOOR + 0.1),
                     (0.0, BIN_FLOOR + 0.1)], 8, lambda a, b, k=heaps[i]: k,
                    matrix=Matrix.Translation((x, BINS_Y, 0)), start=math.pi / 8)
            for k in range(3):
                H.rock(V((x + RNG.uniform(-1, 1), BINS_Y + RNG.uniform(-1, 1), 1.3)),
                       RNG.uniform(0.35, 0.5), heaps[i], RNG)
        lamp((x + w / 2 - 0.2, BINS_Y - w / 2 - 0.05, BIN_TOP + 0.2), 0.3, "light")
    H.box(V((BINS_X[1], BINS_Y, BIN_FLOOR - 1.0)), (15.0, 5.2, 1.2), "dark", bevel=0.0)


def build_fill():
    """ore_silo_fill in the middle bin, built from z = 0 up (origin at the bin floor),
    full at scale 1 (heap peak just over the bin rim)."""
    x = BINS_X[1]
    r = BIN_W / 2 - 0.45
    c = V((x, BINS_Y, BIN_FLOOR))
    hh = BIN_TOP - BIN_FLOOR
    F.lathe([(0.0, 0.0), (r * 1.41, 0.0), (r * 1.41, hh - 0.9), (r * 0.9, hh - 0.3),
             (0.4, hh + 0.5), (0.0, hh + 0.6)], 4, lambda i, j: "ore",
            matrix=Matrix.Translation(c), start=math.pi / 4)
    for k in range(6):
        a = k * 1.1
        rr = 0.5 + 0.9 * (k % 3) / 2
        F.rock(c + V((rr * math.cos(a), rr * math.sin(a), hh - 0.1 - 0.25 * rr)), 0.42, "ore", RNG)


# ---------------------------------------------------------------- scrap field + baler
def junk(cx, cy, n, spread, z0=-3.3):
    """Junk pile: a heaped mound of crushed scrap, then rusted plates, beams, pipe stubs
    and painted scrap chunks thrown on it."""
    pts = []
    for k in range(18):
        a = RNG.uniform(0, 2 * math.pi)
        rr = spread * 1.5 * math.sqrt(RNG.uniform(0.3, 1.0))
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a), z0 - 0.2))
    for k in range(7):
        a = RNG.uniform(0, 2 * math.pi)
        rr = spread * RNG.uniform(0.0, 0.7)
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a),
                    z0 + 2.4 * (1 - rr / spread) * RNG.uniform(0.7, 1.0)))
    parts.part_hull(H, pts, RNG.choice(("scrap", "rust")))
    for k in range(n):
        x = min(max(cx + RNG.gauss(0, spread), -26.5), -13.5)
        y = min(max(cy + RNG.gauss(0, spread), -13.5), 10.5)
        dist = math.hypot(x - cx, y - cy) / (spread * 2.0)
        z = z0 + max(0.0, 2.2 * (1 - dist)) * RNG.uniform(0.5, 1.0)
        kind = RNG.random()
        mat = RNG.choice(("rust", "scrap", "rust", "metal", "scrap", "hull3"))
        r = parts.rot(RNG.uniform(-0.6, 0.6), RNG.uniform(-0.6, 0.6), RNG.uniform(0, 6.3))
        if kind < 0.45:
            H.box(V((x, y, z)), (RNG.uniform(1.0, 2.6), RNG.uniform(0.8, 2.0), 0.15), mat, r=r,
                  bevel=0.0)
        elif kind < 0.65:
            H.box(V((x, y, z)), (RNG.uniform(1.5, 2.6), 0.3, 0.3), "rust", r=r, bevel=0.0)
        elif kind < 0.8:
            H.cyl(V((x, y, z)), 0.35, 0.35, RNG.uniform(1.0, 2.4), mat, segs=6,
                  axis_rot=r)
        else:
            H.rock(V((x, y, z)), RNG.uniform(0.6, 1.0), mat, RNG)


def hull_section(c, length, r, rot_z, roll):
    """A torn-off ship hull section: open half-cylinder shell with frame ribs."""
    m = (Matrix.Translation(c) @ Matrix.Rotation(rot_z, 4, "Z") @ parts.ALONG_Y
         @ Matrix.Rotation(roll, 4, "Z"))
    steps = 6
    for k in range(steps):
        a0, a1 = math.pi * k / steps, math.pi * (k + 1) / steps
        mat = "scrap" if k in (1, 4) else "rust"
        pts = [(r * math.cos(a0), r * math.sin(a0)), (r * math.cos(a1), r * math.sin(a1)),
               ((r - 0.25) * math.cos(a1), (r - 0.25) * math.sin(a1)),
               ((r - 0.25) * math.cos(a0), (r - 0.25) * math.sin(a0))]
        H.slab(pts, -length / 2, length / 2 - (0.0 if k % 3 else 1.2), mat, matrix=m)
    for z in (-length / 2 + 0.6, 0.0, length / 2 - 0.6):
        for k in range(steps):
            a0, a1 = math.pi * k / steps, math.pi * (k + 1) / steps
            pts = [((r + 0.1) * math.cos(a0), (r + 0.1) * math.sin(a0)),
                   ((r + 0.1) * math.cos(a1), (r + 0.1) * math.sin(a1)),
                   ((r - 0.45) * math.cos(a1), (r - 0.45) * math.sin(a1)),
                   ((r - 0.45) * math.cos(a0), (r - 0.45) * math.sin(a0))]
            H.slab(pts, z - 0.15, z + 0.15, "dark", matrix=m)


def build_scrap_field():
    x0, x1, y0, y1 = -28.0, -12.0, -15.0, 12.0
    H.box(V(((x0 + x1) / 2, (y0 + y1) / 2, -4.3)), (x1 - x0, y1 - y0, 1.6), "dark", bevel=0.0)
    H.box(V(((x0 + x1) / 2, (y0 + y1) / 2, -3.48)), (x1 - x0 - 0.6, y1 - y0 - 0.6, 0.05), "pad",
          bevel=0.0)
    H.box(V((x1 + 0.5, -3.0, -4.3)), (2.0, 10.0, 1.6), "dark", bevel=0.0)
    # perimeter fence posts with hazard caps and lamps
    for k in range(7):
        y = y0 + 0.4 + k * (y1 - y0 - 0.8) / 6
        H.box(V((x0 + 0.3, y, -2.2)), (0.3, 0.3, 2.6), "dark", bevel=0.0)
        H.box(V((x0 + 0.3, y, -0.85)), (0.34, 0.34, 0.12), "hazard", bevel=0.0)
        if k % 2 == 0:
            lamp((x0 + 0.3, y, -0.6), 0.35, "light")
    parts.strut(H, V((x0 + 0.3, y0 + 0.4, -1.4)), V((x0 + 0.3, y1 - 0.4, -1.4)), 0.12, 0.12,
                "dark")
    parts.strut(H, V((x0 + 0.3, y0 + 0.4, -2.6)), V((x0 + 0.3, y1 - 0.4, -2.6)), 0.12, 0.12,
                "dark")
    # torn hull sections and junk piles
    hull_section(V((-22.5, -9.0, -3.0)), 8.0, 2.6, 0.5, 0.15)
    hull_section(V((-17.0, 2.5, -3.2)), 6.0, 2.0, -0.9, -0.4)
    junk(-24.0, 0.0, 34, 2.4)
    junk(-17.5, -6.5, 26, 2.0)
    junk(-24.5, 7.5, 18, 1.6)
    # an old engine bell and a cockpit nose lying in the field
    parts.bell(H, -13.6, 1.3, 1.9, "rust", "dark", x=-26.2, z=-2.2, segs=10)
    # magnet gantry crane spanning the field, magnet hanging over the big pile
    gy = -3.0
    for gx in (-27.4, -12.6):
        for dy in (-1.6, 1.6):
            parts.strut(H, V((gx, gy + dy, -3.4)), V((gx, gy + dy * 0.3, 8.0)), 0.5, 0.5, "accent")
        H.box(V((gx, gy, -3.2)), (1.2, 4.4, 0.5), "dark", bevel=0.0)
    H.box(V((-20.0, gy, 8.4)), (16.0, 1.4, 1.2), "accent", bevel=0.05)
    H.box(V((-20.0, gy, 9.2)), (15.0, 0.5, 0.4), "dark", bevel=0.0)
    tx = -22.5
    H.box(V((tx, gy, 7.5)), (2.0, 1.8, 0.9), "hull2", bevel=0.05)
    for dx in (-0.4, 0.4):
        parts.strut(H, V((tx + dx, gy, 7.0)), V((tx + dx * 0.5, gy, 2.4)), 0.06, 0.06, "dark")
    H.cyl(V((tx, gy, 2.0)), 1.5, 1.5, 0.7, "dark", segs=12)
    H.cyl(V((tx, gy, 2.5)), 0.6, 0.6, 0.4, "hazard", segs=8)
    lamp((-12.6, gy, 8.9), 0.4, "red")
    lamp((-27.4, gy, 8.9), 0.4, "red")
    # baler press: frame, ram head, bale chute, stacked bales
    b = V((-16.0, 9.5, 0))
    H.box(b + V((0, 0, -2.2)), (4.4, 6.0, 2.2), "hull2", bevel=0.05)
    for sx in (-1, 1):
        for sy in (-1, 1):
            H.box(b + V((sx * 1.9, sy * 1.0, 1.0)), (0.6, 0.6, 5.2), "dark", bevel=0.0)
    H.box(b + V((0, 0, 3.8)), (4.6, 2.8, 1.0), "accent", bevel=0.05)
    H.box(b + V((0, 0, 1.6)), (3.0, 1.8, 1.2), "metal", bevel=0.05)              # ram head
    H.cyl(b + V((0, 0, 3.0)), 0.35, 0.35, 1.6, "metal", segs=8)
    for k, (dx, dy, dz) in enumerate(((-1.0, -4.2, -2.4), (1.0, -4.2, -2.4), (0.0, -4.2, -1.2),
                                      (-3.6, -2.0, -2.4), (-3.6, 0.0, -2.4), (-3.6, -1.0, -1.2))):
        H.box(b + V((dx, dy, dz)), (1.9, 1.9, 1.2), "scrap" if k % 2 else "rust", rot_z=0.05 * k,
              bevel=0.05)
    lamp(b + V((2.35, 0, 3.8)), 0.35, "red")


def build_furnace():
    pb = V((-0.5, 14.0, 0))
    H.box(pb + V((0, 0, 0.0)), (15.0, 10.0, 9.0), "hull2", bevel=0.04)
    H.box(pb + V((0, 0, 4.7)), (13.4, 8.4, 0.5), "dark", bevel=0.0)
    H.box(pb + V((0, -5.02, 3.6)), (15.0, 0.06, 0.4), "accent", bevel=0.0)
    wk.win_row(L, RNG, pb + V((-6.0, -5.03, 2.0)), pb + V((6.0, -5.03, 2.0)), (0, -1, 0), 10,
               0.5, 0.5, "work")
    for sx in (-1, 1):
        wk.win_row(L, RNG, pb + V((sx * 7.52, -3.5, 2.0)), pb + V((sx * 7.52, 3.5, 2.0)),
                   (sx, 0, 0), 5, 0.5, 0.5, "store")
    # smelter stacks with heat-scorched tops
    for i, (dx, dy) in enumerate(((-4.0, 1.5), (-1.2, 2.5))):
        H.cyl(pb + V((dx, dy, 8.5)), 1.0, 0.8, 7.5, "hull3", segs=10)
        H.cyl(pb + V((dx, dy, 12.35)), 0.95, 0.95, 0.4, "accent", segs=10)
        lamp(pb + V((dx + 0.9, dy, 12.6)), 0.35, "red")
        SCORCH.append((pb.x + dx, pb.y + dy, 12.0, 1.8))
    # furnace mouth glow slot + ore feed pipe from the bins
    L.box(pb + V((3.5, -5.03, -2.0)), (3.0, 0.06, 1.0), "amber", bevel=0.0)
    H.box(pb + V((3.5, -5.6, -1.2)), (3.6, 1.2, 0.4), "dark", bevel=0.0)
    H.tube(V((BINS_X[0] - 2.4, BINS_Y, 3.2)), pb + V((7.5, 1.5, 3.2)), 0.5, 0.5, "metal", segs=8)
    # link port on the back face
    H.cyl(V((LINK_POS.x, LINK_POS.y - 0.6, LINK_POS.z)), 2.0, 2.0, 1.2, "dark", segs=12,
          axis_rot=parts.ALONG_Y)
    H.box(V((0, LINK_POS.y - 1.6, LINK_POS.z - 2.4)), (2.6, 2.0, 4.8), "hull", bevel=0.05)
    lamp((2.2, LINK_POS.y - 0.25, LINK_POS.z + 1.5), 0.35, "red")
    lamp((-2.2, LINK_POS.y - 0.25, LINK_POS.z + 1.5), 0.35, "red")
    # radiator rack on the roof
    for k in range(5):
        H.box(pb + V((3.5, -2.8 + k * 1.3, 6.0)), (5.0, 0.1, 2.0), "radiator", bevel=0.0)
    wk.beacon(H, L, pb + V((-6.6, -4.2, 5.4)), 0.4, "red")


# ---------------------------------------------------------------- assemble
def build_unload_lights():
    bm = bmesh.new()
    for c in BEACONS:
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=8, radius1=0.38,
                              radius2=0.32, depth=0.5, matrix=Matrix.Translation(c + V((0, 0, 0.25))))
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


def build_yard():
    global H, L, A, F
    wk.build_materials(PRE, MATS, extra=("rust", "scrap", "ore"))
    DECALS.clear()
    SCORCH.clear()
    BEACONS.clear()
    H = parts.PanelPart(f"{PRE}_hull", MATS)
    L = parts.PanelPart(f"{PRE}_lights", MATS)
    A = parts.PanelPart("unload_arm", MATS)
    F = parts.PanelPart("ore_silo_fill", MATS)
    for b in (build_berth, build_crane, build_crusher, build_belt_frame, build_bins, build_fill,
              build_scrap_field, build_furnace):
        b()
    root = parts.make_root(PRE, size=10)
    hull, lights, arm, fill = (p.finish(root) for p in (H, L, A, F))
    lights.data.uv_layers.remove(lights.data.uv_layers["panel"])
    belt = build_belt()
    ul = build_unload_lights()
    for o in (belt, ul):
        o.parent = root
    return root, hull, lights, arm, fill, belt, ul


def add_ships():
    """Preview only: salvagers in both berths (not exported)."""
    for sx in (1, -1):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=SALVAGER_GLB)
        new = [o for o in bpy.data.objects if o not in before]
        r = next(o for o in new if o.parent is None)
        r.location = (sx * BERTH_X, BERTH_Y, 0)
        r.rotation_mode = "XYZ"
        r.rotation_euler = (0, 0, math.pi)


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, hull, lights, arm, fill, belt, ul = build_yard()
    if "--no-textures" not in argv:
        wk.texture([hull, arm, fill], MATS, PRE, [(sx * BERTH_X, BERTH_Y) for sx in (-1, 1)],
                   scorch=SCORCH, decals=DECALS, labels=LABELS, seed0=41)
    else:
        for o in (hull, arm, fill):
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    set_origin(arm, PIVOT)
    set_origin(fill, V((BINS_X[1], BINS_Y, BIN_FLOOR)))
    set_origin(belt, BELT0)
    for name, pos, rz in (("dock_point", DOCK_POS, math.pi), ("spawn_point", SPAWN_POS, math.pi),
                          ("link_point", LINK_POS, 0.0)):
        parts.add_empty(name, root, pos, rot_z=rz, size=4)
    e = parts.add_empty("ore_flow_point", root, V((HOPPER.x, HOPPER.y, FLOW_Z)), size=2)
    e.empty_display_type = "PLAIN_AXES"
    print(f"GEOM hold {tuple(round(c, 2) for c in HOLD)} pivot {tuple(PIVOT)} "
          f"hopper {HOPPER.x:.2f},{HOPPER.y:.2f} r_arm {R_ARM:.2f}")
    wk.stats([hull, lights, arm, fill, belt, ul])
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        if "--no-ships" not in argv and os.path.exists(SALVAGER_GLB):
            add_ships()
        wk.previews(PRE, (-2.0, -2.0, 0.0), 82, 74)


main()
