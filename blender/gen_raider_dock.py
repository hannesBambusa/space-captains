"""Generate the Raider Dock (planet raider dropship base) .glb and previews.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_raider_dock.py
  Options after `--`: --no-preview, --no-textures (flat materials, no Cycles bake),
  --no-ships (preview without the two docked dropships).
Textures: one 2048 worn-industrial atlas (worn_kit / station_textures.WORN_KINDS), saved as
blender/textures/raider_dock_*.{jpg} and embedded as JPEG.

Design: free-standing hangar where the planet raider crews base. Two open-roofed drop bays
side by side, each with a dropship cradle (pod saddles, clamp arms, fuel umbilicals) under
a light roof truss; an apron with approach light rows out front; two side landing pads
for waiting ships; a stack yard of cargo pods (the dropship's pod) with a tall slewing
tower crane on -X; ops tower, fuel tanks and radiators on +X; power block at the back.

Layout (Blender Z up, exported +Y up; Blender -Y = Godot +Z). Centre at origin, plane z=0.
Same family as the mercenary / mining outposts: the hangar mouth faces Blender -Y.
  hangar   x -13..13, mouth y = -14, back wall y = 9, cradle deck top z = -3.6,
           bays centred x = +-5 (ships rest at z = 0, pod bottoms z -3.3)
  apron    y -14..-24, approach light rows out to y -31
  pads     side landing pads centred (+-17.5, -24), top z -1.6 (outer berths, 2 m up)
  yard     cargo pod stacks x -27..-15, y -10..8, tower crane at (-20, 12)
  +X       ops tower (19, -6), fuel tanks, radiators
Hierarchy: raider_dock (empty root) -> raider_dock_hull, raider_dock_lights,
  dock_point, spawn_point, link_point (empties).
dock_point / spawn_point are rotated 180 deg about up, so their Godot -Z (forward) points
out of the mouth (Godot world +Z). link_point is unrotated: Godot -Z points out the back.
Berths: with Building defaults (berth_depth 11) the two inner berths sit at Godot
(+-berth_spacing/2, 0, 3); the cradles are built for berth_spacing = 10.
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

V = Vector
PRE = "raider_dock"
OUT = os.path.join(common.ROOT, "assets", "models", "buildings", "raider_dock.glb")
BLEND = os.path.join(common.ROOT, "blender", "raider_dock.blend")
DROPSHIP_GLB = os.path.join(common.ROOT, "assets", "models", "ships", "dropship.glb")
MOUTH_Y, BACK_Y = -14.0, 9.0
DOCK_POS = (0.0, -14.0, 0.0)
SPAWN_POS = (0.0, -32.0, 0.0)
LINK_POS = (0.0, 18.4, 0.5)
BAY_X = 5.0                  # berth centre |x| (berth_spacing 10)
BERTH_Y = -3.0               # dock_point y + berth_depth 11
DECK_Z = -3.6
WALL_IN, WALL_OUT = 10.6, 13.2
ROOF_Z = 7.0
PADS = ((-17.5, -24.0), (17.5, -24.0))
PAD_Z = -1.6
CRANE = V((-20.5, 12.0, 0.0))
ALONG_Y = parts.ALONG_Y
LABELS = ["DROP 1", "DROP 2", "#BAR", "#CHEV", "NO STEP", "FUEL", "RD-07", "PODS"]

MATS = {}
DECALS = []
SCORCH = []
H = L = None
RNG = random.Random(7)


def label(text, centre, normal, up, h, colour, opacity=0.85):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity))


def lamp(pos, s=0.4, mat="light"):
    wk.lamp(L, pos, s, mat)


# ---------------------------------------------------------------- hangar
def build_hangar():
    y0, y1 = MOUTH_Y, BACK_Y
    cy, ln = (y0 + y1) / 2, y1 - y0
    # base slab + cradle deck
    H.box(V((0, cy - 1.0, -5.4)), (2 * WALL_OUT + 1.0, ln + 2.0, 1.6), "dark", bevel=0.05)
    H.box(V((0, cy, DECK_Z - 0.4)), (2 * WALL_IN, ln, 0.8), "pad", bevel=0.0)
    # side walls: armoured slab with a sloped outer face, top walkway, ribs
    for sx in (-1, 1):
        sec = [(WALL_IN, -4.6), (WALL_OUT + 1.6, -4.6), (WALL_OUT + 1.6, -1.0),
               (WALL_OUT, 4.6), (WALL_IN, 4.6)]
        sec = [(sx * x, z) for x, z in sec]
        if sx < 0:
            sec.reverse()
        H.slab(sec, y0, y1, "hull", matrix=Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0),
                                                    (0, 0, 0, 1))))
        H.box(V((sx * (WALL_IN + WALL_OUT) / 2, cy, 4.85)), (WALL_OUT - WALL_IN + 0.2, ln, 0.5),
              "hull2", bevel=0.0)
        for k in range(6):
            yy = y0 + 1.0 + k * (ln - 2.0) / 5
            H.box(V((sx * (WALL_OUT + 0.9), yy, -1.6)), (1.6, 0.8, 6.0), "dark", bevel=0.05)
            H.box(V((sx * (WALL_IN - 0.15), yy, 0.0)), (0.3, 0.6, 9.2), "dark", bevel=0.0)
        # inner wall: warm window strip + red bay edge lamps
        wk.win_row(L, RNG, (sx * (WALL_IN - 0.02), y0 + 2.0, 2.8),
                   (sx * (WALL_IN - 0.02), y1 - 2.0, 2.8), (-sx, 0, 0), 9, 0.7, 0.45, "work")
        H.box(V((sx * (WALL_OUT + 0.82), cy, -0.2)), (0.1, ln - 3.0, 0.5), "accent", bevel=0.0)
        label("DROP 1" if sx < 0 else "DROP 2", (sx * (WALL_OUT + 1.6), y0 + 5.0, -2.8),
              (sx, 0, 0), (0, 0, 1), 1.0, wk.INK_DARK)
    # back wall with a hangar control gallery window band
    H.box(V((0, y1 + 0.8, 0.0)), (2 * WALL_OUT, 1.6, 9.6), "hull2", bevel=0.05)
    H.box(V((0, y1 - 0.1, 3.0)), (2 * WALL_IN - 1, 0.25, 1.6), "dark", bevel=0.0)
    wk.win_row(L, RNG, (-WALL_IN + 1.0, y1 - 0.25, 3.0), (WALL_IN - 1.0, y1 - 0.25, 3.0),
               (0, -1, 0), 12, 0.9, 0.7, "hab")
    # centre divider: a row of pillars carrying the roof spine, hazard footings
    for k in range(4):
        yy = y0 + 1.5 + k * (ln - 3.0) / 3
        H.box(V((0, yy, 1.6)), (0.8, 0.8, 10.8), "hull2", bevel=0.08)
        H.box(V((0, yy, DECK_Z + 0.4)), (1.3, 1.3, 0.8), "hazard", bevel=0.0)
        lamp((0, yy - 0.45, 5.2), 0.35, "red")
    # roof: open truss (transverse trusses + spine), so the bays read from above
    for k in range(5):
        yy = y0 + 0.6 + k * (ln - 1.2) / 4
        H.box(V((0, yy, ROOF_Z)), (2 * WALL_OUT, 0.7, 0.9), "dark", bevel=0.0)
        for sx in (-1, 1):   # knee braces
            parts.strut(H, V((sx * (WALL_IN - 1.6), yy, ROOF_Z - 0.4)),
                        V((sx * (WALL_IN - 0.2), yy, 4.4)), 0.25, 0.25, "dark", up=V((0, 1, 0)))
        for sx in (-1, 1):
            parts.strut(H, V((sx * WALL_IN, yy, 4.6)), V((sx * WALL_IN, yy, ROOF_Z + 0.5)),
                        0.35, 0.35, "dark")
    H.box(V((0, cy, ROOF_Z + 0.6)), (1.0, ln - 1.0, 0.6), "hull2", bevel=0.0)
    # floodlights under the roof trusses, aimed down into the bays
    for k in range(1, 4):
        yy = y0 + 0.6 + k * (ln - 1.2) / 4
        for sx in (-1, 1):
            H.box(V((sx * BAY_X, yy, ROOF_Z - 0.55)), (1.6, 0.6, 0.3), "dark", bevel=0.0)
            L.box(V((sx * BAY_X, yy, ROOF_Z - 0.72)), (1.3, 0.4, 0.05), "cyan", bevel=0.0)
    for sx in (-1, 1):
        H.box(V((sx * (WALL_IN - 0.2), cy, ROOF_Z + 0.75)), (0.6, ln, 0.5), "hull2", bevel=0.0)
    # roof crane bridge parked over the back third (rails on the wall tops)
    by = y1 - 4.5
    H.box(V((0, by, ROOF_Z + 2.3)), (2 * WALL_OUT - 1.0, 1.4, 1.2), "accent", bevel=0.05)
    for sx in (-1, 1):
        H.box(V((sx * (WALL_IN + 1.2), by, ROOF_Z + 1.4)), (1.2, 2.4, 1.0), "dark", bevel=0.0)
        H.box(V((sx * BAY_X, by, ROOF_Z + 1.25)), (1.6, 1.8, 0.9), "hull2", bevel=0.05)
        parts.strut(H, V((sx * BAY_X, by, ROOF_Z + 0.8)), V((sx * BAY_X, by, ROOF_Z - 1.6)),
                    0.06, 0.06, "dark")
        H.box(V((sx * BAY_X, by, ROOF_Z - 1.8)), (0.9, 0.9, 0.4), "hazard", bevel=0.0)
    lamp((-WALL_OUT + 0.8, by, ROOF_Z + 3.0), 0.35, "light")
    lamp((WALL_OUT - 0.8, by, ROOF_Z + 3.0), 0.35, "light")

    # mouth: heavy frame posts, header beam with bay numbers, edge lamps
    fy = y0 - 0.5
    for sx in (-1, 1):
        H.box(V((sx * (WALL_IN + 1.3), fy, 0.3)), (3.2, 1.2, 10.0), "hull2", bevel=0.06)
        H.box(V((sx * (WALL_IN + 0.0), fy - 0.62, 0.3)), (0.5, 0.06, 8.4), "hazard", bevel=0.0)
        for z in (-3.0, 1.0, 4.6):
            lamp((sx * (WALL_IN - 0.4), fy - 0.6, z), 0.4, "light")
    H.box(V((0, fy, ROOF_Z - 0.2)), (2 * WALL_OUT + 0.4, 1.2, 1.6), "hull2", bevel=0.06)
    H.box(V((0, fy - 0.62, ROOF_Z - 0.75)), (2 * WALL_IN, 0.06, 0.35), "hazard", bevel=0.0)
    label("RD-07", (-6.0, fy - 0.61, ROOF_Z), (0, -1, 0), (0, 0, 1), 0.9, wk.INK_DARK)
    label("#CHEV", (6.0, fy - 0.61, ROOF_Z), (0, -1, 0), (0, 0, 1), 0.9, wk.INK_DARK)
    for sx in (-1, 1):
        cradle(sx * BAY_X)


def cradle(x):
    """Dropship cradle: two pod saddles, clamp arms, fuel umbilical arm, deck markings."""
    yc = BERTH_Y - 0.35        # the pod centre sits 0.35 m aft of the ship origin
    # deck markings: hazard border + centre line under the bay
    for sx in (-1, 1):
        H.box(V((x + sx * 4.3, BERTH_Y - 1.0, DECK_Z + 0.02)), (0.3, 18.0, 0.05), "hazard",
              bevel=0.0)
    H.box(V((x, BERTH_Y - 5.5, DECK_Z + 0.02)), (0.25, 7.0, 0.05), "hull", bevel=0.0)
    # saddles under the pod ends (pod bottom at z -3.32)
    for dy in (-2.6, 2.6):
        H.box(V((x, yc + dy, DECK_Z + 0.08)), (4.6, 1.2, 0.3), "dark", bevel=0.0)
        for sx in (-1, 1):
            H.box(V((x + sx * 1.45, yc + dy, -3.42)), (0.9, 1.0, 0.16), "hazard", bevel=0.0)
            H.box(V((x + sx * 1.95, yc + dy, -2.6)), (0.35, 0.8, 1.8), "hull2", bevel=0.1)
            H.box(V((x + sx * 1.8, yc + dy, -1.75)), (0.35, 0.8, 0.25), "dark", bevel=0.0)
    # rail pair the saddles ride on
    for sx in (-1, 1):
        H.box(V((x + sx * 1.6, yc, DECK_Z + 0.05)), (0.3, 8.0, 0.2), "metal", bevel=0.0)
    # fuel umbilical arm from the side wall to the ship flank (outer side of each bay)
    side = 1 if x > 0 else -1
    wx = side * (WALL_IN - 0.4)
    H.box(V((wx, BERTH_Y + 1.0, 1.0)), (0.8, 1.2, 1.2), "dark", bevel=0.05)
    H.tube(V((wx, BERTH_Y + 1.0, 1.0)), V((side * (BAY_X + 4.35), BERTH_Y + 0.4, 0.8)), 0.22,
           0.22, "accent", segs=8)
    H.box(V((side * (BAY_X + 4.3), BERTH_Y + 0.4, 0.8)), (0.4, 0.5, 0.5), "hazard", bevel=0.0)
    label("FUEL", (wx - side * 0.42, BERTH_Y + 1.0, 2.2), (-side, 0, 0), (0, 0, 1), 0.4,
          wk.INK_LIGHT)
    lamp((wx - side * 0.45, BERTH_Y + 1.0, 1.75), 0.3, "green")
    # bay scorch from lift nozzles (deck, under the nacelles)
    for sx in (-1, 1):
        SCORCH.append((x + sx * 3.05, BERTH_Y - 1.1, DECK_Z, 3.0))
    SCORCH.append((x, BERTH_Y - 6.6, DECK_Z, 2.4))


# ---------------------------------------------------------------- apron, pads, lights
def build_apron():
    ay0, ay1 = MOUTH_Y - 1.1, MOUTH_Y - 11.0
    acy = (ay0 + ay1) / 2
    H.box(V((0, acy, -4.3)), (2 * WALL_OUT + 1.0, ay0 - ay1, 1.4), "pad", bevel=0.0)
    H.box(V((0, acy, -5.5)), (2 * WALL_IN, ay0 - ay1 - 1.0, 1.0), "dark", bevel=0.0)
    for sx in (-1, 1):
        H.box(V((sx * (WALL_OUT + 0.2), acy, -3.58)), (0.6, ay0 - ay1, 0.06), "hazard",
              bevel=0.0)
    H.box(V((0, ay1 + 0.3, -3.58)), (2 * WALL_OUT + 0.6, 0.6, 0.06), "hazard", bevel=0.0)
    label("NO STEP", (0.0, ay1 + 2.2, -3.59), (0, 0, 1), (0, 1, 0), 1.0, wk.INK_LIGHT, 0.6)
    for sx in (-1, 1):
        SCORCH.append((sx * BAY_X, acy, -3.6, 4.5))
    # approach light rows: lamps down each bay axis, out on a light boom past the apron
    for sx in (-1, 1):
        x = sx * BAY_X
        for k in range(5):
            lamp((x, ay0 - 1.2 - k * 2.0, -3.5), 0.45, "light")
        parts.strut(H, V((x, ay1 + 0.2, -4.3)), V((x, ay1 - 8.0, -4.3)), 0.4, 0.4, "dark")
        for k in range(4):
            yy = ay1 - 1.2 - k * 2.2
            H.box(V((x, yy, -4.0)), (1.6, 0.25, 0.25), "dark", bevel=0.0)
            for dx in (-0.6, 0.0, 0.6):
                lamp((x + dx, yy, -3.8), 0.3, "light" if k % 2 else "cyan")
        lamp((x, ay1 - 8.1, -4.0), 0.45, "red")


def build_pads():
    for px, py in PADS:
        wk.landing_pad(H, L, (px, py, PAD_Z), 6.0, n_lamps=8)
        sx = 1 if px > 0 else -1
        # pylon + strut back to the hangar wall foot
        H.cyl(V((px, py, PAD_Z - 3.0)), 1.3, 0.9, 3.4, "hull2", segs=8)
        H.beam(V((px - sx * 3.0, py + 3.0, PAD_Z - 1.6)),
               V((sx * (WALL_OUT + 1.2), MOUTH_Y + 2.0, -4.6)), 1.0, 0.9, "dark")
        H.box(V((px, py, PAD_Z + 0.03)), (5.0, 0.4, 0.05), "hull", bevel=0.0)
        H.box(V((px, py, PAD_Z + 0.03)), (0.4, 5.0, 0.05), "hull", bevel=0.0)
        SCORCH.append((px, py, PAD_Z, 3.6))
        wk.beacon(H, L, (px + sx * 5.2, py - 3.2, PAD_Z + 0.9), 0.4, "red")


# ---------------------------------------------------------------- pod yard + crane
def build_yard():
    x0, x1, y0, y1 = -27.0, -15.0, -11.0, 9.0
    H.box(V(((x0 + x1) / 2, (y0 + y1) / 2, -5.2)), (x1 - x0 + 1.0, y1 - y0 + 1.0, 1.2), "dark",
          bevel=0.0)
    H.box(V(((x0 + x1) / 2, (y0 + y1) / 2, -4.5)), (x1 - x0, y1 - y0, 0.3), "pad", bevel=0.0)
    H.box(V((x1 + 0.5, (y0 + y1) / 2, -4.6)), (2.0, 6.0, 1.2), "dark", bevel=0.0)  # tie to wall
    # rack frame posts
    for xx in (x0 + 0.3, (x0 + x1) / 2, x1 - 0.3):
        for yy in (y0 + 0.3, y1 - 0.3):
            H.box(V((xx, yy, -1.0)), (0.4, 0.4, 7.0), "dark", bevel=0.0)
        parts.strut(H, V((xx, y0 + 0.3, 2.4)), V((xx, y1 - 0.3, 2.4)), 0.35, 0.35, "dark")
    # pods: 3.4 x 7.0 x 1.9 (the dropship pod), two columns, stacked 1-3 high
    tones = ("hull3", "hull", "accent", "hull2", "hull3", "hull")
    bands = ("accent", "hazard", "hull", "accent", "hazard", "accent")
    i = 0
    for cx in (x0 + 3.2, x0 + 8.8):
        for cy, n in ((y0 + 4.0, 3 if cx < -20 else 2), (y0 + 11.6, 2 if cx < -20 else 1),
                      (y0 + 17.2, 1 if cx < -20 else 3)):
            for lv in range(n):
                wk.cargo_pod(H, (cx + RNG.uniform(-0.15, 0.15), cy, -3.4 + lv * 2.0),
                             (3.4, 6.4, 1.9), rot_z=RNG.uniform(-0.03, 0.03),
                             body=tones[i % 6], band=bands[(i + lv) % 6])
                i += 1
    label("PODS", (x0 + 6.0, y0 - 0.02, -4.0), (0, -1, 0), (0, 0, 1), 0.9, wk.INK_LIGHT)
    # loose pods on the deck by the crane, one hanging from the hook
    wk.cargo_pod(H, (-17.0, 12.5, -3.4), (3.4, 6.4, 1.9), rot_z=0.25, body="accent",
                 band="hull")
    for k in range(4):
        lamp((x0 + 0.2 + k * 4.0, y0 - 0.3, -4.2), 0.4, "light")
    build_crane()


def build_crane():
    """Slewing tower crane: lattice tower, cab + counter-jib, long jib over the pod yard,
    trolley with a hook holding a pod."""
    c = CRANE
    top = 20.0
    H.box(c + V((0, 0, -4.8)), (5.0, 5.0, 1.6), "hull2", bevel=0.05)
    wk.lattice_mast(H, c + V((0, 0, -4.0)), top, 1.3, 1.1, 6, "accent", chord=0.35, brace=0.16)
    H.cyl(c + V((0, 0, top + 0.3)), 1.8, 1.8, 0.6, "dark", segs=12)
    a = math.radians(-97)                       # jib heading: out over the stacks
    d = V((math.cos(a), math.sin(a), 0))
    s = V((-d.y, d.x, 0))
    jz = top + 1.3
    # cab
    H.box(c + V((0, 0, top + 1.6)) + s * 1.6, (2.2, 2.2, 2.0), "hull", rot_z=a, bevel=0.08)
    L.box(c + V((0, 0, top + 1.9)) + s * 1.6 + d * 1.12, (1.6, 0.06, 0.7), "window",
          r=Matrix.Rotation(a + math.pi / 2, 4, "Z"), bevel=0.0)
    # jib: triangular lattice, 24 m
    jl = 21.0
    tip = c + d * jl + V((0, 0, jz))
    root = c + V((0, 0, jz))
    for o in (s * 0.7, -s * 0.7):
        parts.strut(H, root + o, tip + o * 0.5, 0.3, 0.3, "accent")
    parts.strut(H, root + V((0, 0, 1.6)), tip + V((0, 0, 0.4)), 0.3, 0.3, "accent")
    for k in range(10):
        p0 = root.lerp(tip, k / 10)
        p1 = root.lerp(tip, (k + 1) / 10)
        w = 0.7 - 0.35 * (k / 10)
        apex = p0.lerp(p1, 0.5) + V((0, 0, 1.6 - 1.2 * (k + 0.5) / 10))
        for o in (s * w, -s * w):
            parts.strut(H, p0 + o, apex, 0.14, 0.14, "accent")
            parts.strut(H, apex, p1 + o, 0.14, 0.14, "accent")
        parts.strut(H, p0 + s * w, p0 - s * w, 0.14, 0.14, "accent")
    # counter-jib with ballast blocks, A-frame and stays
    cj = c - d * 8.0 + V((0, 0, jz))
    for o in (s * 0.7, -s * 0.7):
        parts.strut(H, root + o, cj + o, 0.3, 0.3, "accent")
    H.box(cj + d * 1.2, (2.4, 1.6, 1.8), "hull2", rot_z=a + math.pi / 2, bevel=0.05)
    H.box(cj + d * 3.4, (2.4, 1.6, 1.8), "hull2", rot_z=a + math.pi / 2, bevel=0.05)
    peak = c + V((0, 0, jz + 5.0))
    parts.strut(H, root + V((0, 0, 0.5)), peak, 0.4, 0.4, "dark")
    parts.strut(H, peak, tip.lerp(root, 0.35) + V((0, 0, 1.1)), 0.08, 0.08, "dark")
    parts.strut(H, peak, cj, 0.08, 0.08, "dark")
    wk.beacon(H, L, peak + V((0, 0, 0.6)), 0.35, "red")
    lamp(tip + V((0, 0, 0.6)), 0.4, "red")
    # trolley + hook + hanging pod (two thirds out)
    tr = root.lerp(tip, 0.62)
    H.box(tr + V((0, 0, -0.35)), (1.5, 1.2, 0.5), "dark", rot_z=a, bevel=0.0)
    hz = 3.8
    for o in (s * 0.4, -s * 0.4):
        parts.strut(H, tr + o + V((0, 0, -0.5)), V((tr.x, tr.y, hz + 1.0)) + o * 0.5, 0.05, 0.05,
                    "dark")
    H.box(V((tr.x, tr.y, hz + 0.8)), (1.2, 0.6, 0.6), "hazard", rot_z=a, bevel=0.0)
    for o in (d * 2.6, -d * 2.6):
        parts.strut(H, V((tr.x, tr.y, hz + 0.6)), V((tr.x, tr.y, hz - 0.9)) + o, 0.05, 0.05,
                    "dark")
    wk.cargo_pod(H, (tr.x, tr.y, hz - 1.9), (3.4, 6.4, 1.9), rot_z=a + math.pi / 2,
                 body="hull3", band="hazard")


# ---------------------------------------------------------------- +X side, back
def build_services():
    # deck under the +X services
    H.box(V((20.5, -2.0, -5.3)), (13.0, 26.0, 1.2), "dark", bevel=0.0)
    H.box(V((20.5, -2.0, -4.6)), (12.0, 25.0, 0.3), "pad", bevel=0.0)
    # ops tower: tall block, slanted window band all round, roof sensors
    t = V((19.5, -8.0, 0))
    H.box(t + V((0, 0, 1.0)), (5.0, 5.0, 11.0), "hull", bevel=0.05)
    H.box(t + V((0, 0, 7.6)), (6.6, 6.6, 2.4), "hull2", bevel=0.08)
    for n, (dx, dy) in ((V((0, -1, 0)), (0, -3.32)), (V((1, 0, 0)), (3.32, 0)),
                        (V((-1, 0, 0)), (-3.32, 0)), (V((0, 1, 0)), (0, 3.32))):
        L.box(t + V((dx, dy, 7.8)), (5.6 if dx == 0 else 0.06, 0.06 if dx == 0 else 5.6, 0.9),
              "window", bevel=0.0)
    H.box(t + V((0, 0, 9.0)), (7.0, 7.0, 0.4), "dark", bevel=0.0)
    wk.win_row(L, RNG, t + V((-1.8, -2.52, 3.5)), t + V((1.8, -2.52, 3.5)), (0, -1, 0), 4, 0.5,
               0.6, "hab")
    wk.win_row(L, RNG, t + V((-1.8, -2.52, 1.5)), t + V((1.8, -2.52, 1.5)), (0, -1, 0), 4, 0.5,
               0.6, "hab")
    H.cyl(t + V((1.5, 1.5, 10.6)), 0.1, 0.06, 2.8, "dark", segs=5)
    lamp(t + V((1.5, 1.5, 12.1)), 0.4, "red")
    parts.dish(H, t + V((-1.4, -0.8, 9.4)), 1.4, (-0.4, -0.6, 0.7), "hull", "dark")
    # walkway tower -> hangar wall top
    H.box(V((15.0, -8.0, 3.6)), (4.4, 2.0, 2.0), "hull2", bevel=0.05)
    L.box(V((15.0, -9.02, 3.6)), (3.4, 0.06, 0.5), "window", bevel=0.0)
    # fuel tanks with a manifold
    for i, (x, y) in enumerate(((18.5, 2.0), (23.0, 2.0), (18.5, 7.0), (23.0, 7.0))):
        wk.tank_v(H, (x, y, -4.5), 2.0, 7.5, "hull" if i % 2 else "hull3", "accent", segs=12)
        H.tube(V((x, y, -3.6)), V((15.0, y, -3.6)), 0.25, 0.25, "metal", segs=6)
    label("FUEL", (20.75, -0.02, -1.0), (0, -1, 0), (0, 0, 1), 0.8, wk.INK_DARK)
    wk.beacon(H, L, (25.2, -12.0, -3.8), 0.4, "red")
    # radiator rack on the outer edge (edge-on fins, vertical)
    for k in range(6):
        y = -13.0 + k * 1.3
        H.box(V((25.0, y, -1.6)), (3.0, 0.12, 5.4), "radiator", bevel=0.0)
    H.box(V((25.0, -9.75, -4.3)), (3.4, 8.0, 0.6), "dark", bevel=0.0)
    H.tube(V((23.4, -13.2, 0.9)), V((23.4, -6.6, 0.9)), 0.2, 0.2, "accent", segs=6)


def build_back():
    pb = V((0, BACK_Y + 5.2, 0))
    H.box(pb + V((0, 0, -0.5)), (18.0, 7.2, 8.0), "hull2", bevel=0.05)
    H.box(pb + V((0, 0, 3.7)), (16.0, 6.0, 0.6), "dark", bevel=0.0)
    for sx in (-1, 1):
        H.cyl(pb + V((sx * 4.2, 0.4, 4.6)), 1.7, 1.7, 1.6, "hull", segs=12)
        H.cyl(pb + V((sx * 4.2, 0.4, 5.6)), 1.7, 1.1, 0.4, "hull", segs=12)
        L.cyl(pb + V((sx * 4.2, 0.4, 5.85)), 0.45, 0.45, 0.2, "light", segs=6)
        wk.win_row(L, RNG, pb + V((sx * 9.02, -2.5, 1.0)), pb + V((sx * 9.02, 2.5, 1.0)),
                   (sx, 0, 0), 4, 0.5, 0.5, "store")
    H.box(pb + V((0, 3.62, 0.2)), (14.0, 0.06, 0.8), "hazard", bevel=0.0)
    label("#BAR", (0.0, pb.y + 3.66, -2.0), (0, 1, 0), (0, 0, 1), 0.8, wk.INK_DARK)
    # link port on the back face (cargo shuttle side)
    H.cyl(V((LINK_POS[0], LINK_POS[1] - 0.6, LINK_POS[2])), 2.2, 2.2, 1.2, "dark", segs=12,
          axis_rot=ALONG_Y)
    H.box(V((0, LINK_POS[1] - 2.0, LINK_POS[2] - 2.5)), (3.0, 2.0, 5.0), "hull2", bevel=0.05)
    lamp((2.4, LINK_POS[1] - 0.3, LINK_POS[2] + 1.6), 0.35, "red")
    lamp((-2.4, LINK_POS[1] - 0.3, LINK_POS[2] + 1.6), 0.35, "red")
    # comms mast at the back right corner
    m = V((7.0, BACK_Y + 5.6, 3.9))
    wk.lattice_mast(H, m, 17.0, 0.9, 0.5, 4, "dark", chord=0.28, brace=0.13)
    H.box(m + V((0, 0, 13.8)), (5.0, 0.6, 0.4), "hull", rot_z=0.4, bevel=0.0)
    lamp(m + V((0, 0, 14.4)), 0.45, "red")


def build_dock():
    global H, L
    wk.build_materials(PRE, MATS)
    DECALS.clear()
    SCORCH.clear()
    H = parts.PanelPart(f"{PRE}_hull", MATS)
    L = parts.PanelPart(f"{PRE}_lights", MATS)
    for b in (build_hangar, build_apron, build_pads, build_yard, build_services, build_back):
        b()
    root = parts.make_root(PRE, size=10)
    hull = H.finish(root)
    lights = L.finish(root)
    lights.data.uv_layers.remove(lights.data.uv_layers["panel"])
    for name, pos, rz in (("dock_point", DOCK_POS, math.pi), ("spawn_point", SPAWN_POS, math.pi),
                          ("link_point", LINK_POS, 0.0)):
        parts.add_empty(name, root, pos, rot_z=rz, size=4)
    return root, hull, lights


def add_ships():
    """Preview only: two dropships in the cradles (not exported)."""
    for sx in (-1, 1):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=DROPSHIP_GLB)
        new = [o for o in bpy.data.objects if o not in before]
        r = next(o for o in new if o.parent is None)
        r.location = (sx * BAY_X, BERTH_Y, 0)
        r.rotation_mode = "XYZ"
        r.rotation_euler = (0, 0, math.pi)


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, hull, lights = build_dock()
    if "--no-textures" not in argv:
        wk.texture([hull], MATS, PRE, [(p[0], p[1]) for p in PADS], scorch=SCORCH,
                   decals=DECALS, labels=LABELS, seed0=31)
    wk.stats([hull, lights])
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        if "--no-ships" not in argv and os.path.exists(DROPSHIP_GLB):
            add_ships()
        wk.previews(PRE, (-1.0, -6.0, 0.0), 82, 72)


main()
