"""Generate the Mercenary Outpost (fighter hangar) .glb and previews.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_mercenary_outpost.py
  Options after `--`: --no-preview, --no-textures (flat materials, no Cycles bake),
  --no-ships (previews without the four docked merc fighters).
Textures: one 2048 worn-industrial atlas (worn_kit / station_textures.WORN_KINDS plus a
"merc" red paint kind), saved as blender/textures/mercenary_outpost_*.jpg and embedded
as JPEG.

Design: armoured fighter hangar for freelance pilots. Four launch cradles in a row under
an open truss roof, each with a catapult sled on twin rails, clamp saddles, a repair
gantry bridge with a hanging tool arm, a side service arm, a blast deflector behind the
engine and its own launch lights on the mouth header and down the apron. Heavy sloped
armour plating on the side walls, PD turrets on the front corners, a flight control
tower on +X, an ordnance yard (missile racks, ammo crates, loader) on -X, power block
with radiators and the shuttle link port at the back.

Layout (Blender Z up, exported +Y up; Blender -Y = Godot +Z). Centre at origin, plane z=0.
Same family as the raider dock / explorer outpost: the hangar mouth faces Blender -Y.
  hangar   x -23.5..23.5 (inner -20.5..20.5), mouth y = -14, back wall y = 10,
           deck top z = -3.4, header underside z = 6.4, wall top z = 7.2
  berths   x = -15, -5, 5, 15, y = -3.5 (berth_spacing 10, berth_depth 10.5),
           ships rest at z = 0 nose out (merc_fighter 4.1 x 16.2 x 5.4 m)
  apron    y -14.6..-25.5, launch light rows + booms out to y -32
  +X       flight control tower (30, -10), tanks + radiators behind it
  -X       ordnance yard x -34..-25.5, y -12..9
  back     power block y 11.6..18, link port at y 18.6
Hierarchy: mercenary_outpost (empty root) -> mercenary_outpost_hull,
  mercenary_outpost_lights, dock_point, spawn_point, link_point (empties).
dock_point / spawn_point are rotated 180 deg about up, so their Godot -Z (forward) points
out of the mouth (Godot world +Z). link_point is unrotated: Godot -Z points out the back.
Godot berth fields (data/buildings/mercenary_outpost.tres): inner_berths 4,
berth_spacing 10, berth_depth 10.5, outer_berth_side 30, outer_berth_step 11,
footprint_radius 40.
"""
import math
import os
import random
import shutil
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
import station_textures as st  # noqa: E402
import worn_kit as wk  # noqa: E402

V = Vector
PRE = "mercenary_outpost"
OUT = os.path.join(common.ROOT, "assets", "models", "buildings", "mercenary_outpost.glb")
BLEND = os.path.join(common.ROOT, "blender", "mercenary_outpost.blend")
FIGHTER_GLB = os.path.join(common.ROOT, "assets", "models", "ships", "merc_fighter.glb")
PREVIEW_COPY = os.path.join(wk.SCRATCH, "mercoutpost")

# Godot berth fields (keep in sync with data/buildings/mercenary_outpost.tres)
INNER_BERTHS = 4
BERTH_SPACING = 10.0
BERTH_DEPTH = 10.5
OUTER_SIDE = 30.0
OUTER_STEP = 11.0
OUTER_HEIGHT = 2.0

MOUTH_Y, BACK_Y = -14.0, 10.0
DOCK_POS = (0.0, MOUTH_Y, 0.0)
SPAWN_POS = (0.0, -34.0, 0.0)
LINK_POS = (0.0, 18.6, 0.5)
BAYS = [(k - (INNER_BERTHS - 1) / 2) * BERTH_SPACING for k in range(INNER_BERTHS)]
BERTH_Y = MOUTH_Y + BERTH_DEPTH          # -3.5
DECK_Z = -3.4
WALL_IN, WALL_OUT = 20.5, 23.5
FOOT_X = WALL_OUT + 1.8                  # outer wall foot
HEAD_Z = 6.4                             # mouth header underside
ROOF_Z = 7.1                             # roof truss centre
RAIL_Z = 5.8                             # gantry rail top
WALL_TOP = 7.2
DIVIDERS = (-10.0, 0.0, 10.0)
APRON_Y = -24.5
TOWER = V((30.0, -10.0, 0.0))
YARD = (-34.0, -25.5, -12.0, 9.0)        # x0, x1, y0, y1
# merc_fighter bounds (ship frame, nose +Y): x +-2.06, y -8.6..7.62, z -2.45..2.98
SHIP_HW, SHIP_BOT, SHIP_TOP = 2.06, -2.45, 2.98
NOSE_Y = BERTH_Y - 7.62                  # docked nose out (-Y)
TAIL_Y = BERTH_Y + 8.6
LABELS = ["BAY 1", "BAY 2", "BAY 3", "BAY 4", "#BAR", "#CHEV", "NO STEP", "MX-12",
          "AMMO", "ORD", "FLT CTRL", "LAUNCH", "HOT", "MERC"]
NO_PADS = [(0.0, 900.0), (0.0, 901.0)]   # no landing pads: keep the deck ring paint off-model
XZ = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))

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


def build_materials():
    wk.build_materials(PRE, MATS)
    MATS["merc"] = common.make_material(f"{PRE}_merc_paint", (0.3, 0.045, 0.035),
                                        roughness=0.6)


def label(text, centre, normal, up, h, colour, opacity=0.85):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity))


def lamp(pos, s=0.4, mat="light"):
    wk.lamp(L, pos, s, mat)


# ---------------------------------------------------------------- hangar shell
def build_shell():
    y0, y1 = MOUTH_Y, BACK_Y
    cy, ln = (y0 + y1) / 2, y1 - y0
    # base slab + deck
    H.box(V((0, cy - 0.6, -5.6)), (2 * FOOT_X + 0.6, ln + 2.4, 1.6), "dark", bevel=0.04)
    H.box(V((0, cy, DECK_Z - 0.4)), (2 * WALL_IN, ln, 0.8), "pad", bevel=0.0)
    for sx in (-1, 1):
        # side wall: thick slab, vertical foot, sloped armour face, walkway top
        sec = [(WALL_IN, -5.0), (FOOT_X, -5.0), (FOOT_X, -1.5), (WALL_OUT, WALL_TOP),
               (WALL_IN, WALL_TOP)]
        sec = [(sx * x, z) for x, z in sec]
        if sx < 0:
            sec.reverse()
        H.slab(sec, y0, y1 + 1.6, "hull2", matrix=XZ)
        H.box(V((sx * (WALL_IN + WALL_OUT) / 2, cy + 0.8, WALL_TOP + 0.25)),
              (WALL_OUT - WALL_IN + 0.3, ln + 1.6, 0.5), "dark", bevel=0.0)
        armour(sx)
        # inner face: pilaster ribs, service gallery window band, red edge stripe
        for k in range(7):
            yy = y0 + 1.2 + k * (ln - 2.4) / 6
            H.box(V((sx * (WALL_IN - 0.2), yy, (DECK_Z + WALL_TOP) / 2)),
                  (0.4, 0.7, WALL_TOP - DECK_Z), "dark", bevel=0.0)
        H.box(V((sx * (WALL_IN - 0.05), cy, 3.4)), (0.12, ln - 1.0, 1.4), "dark", bevel=0.0)
        wk.win_row(L, RNG, (sx * (WALL_IN - 0.12), y0 + 2.0, 3.4),
                   (sx * (WALL_IN - 0.12), y1 - 2.0, 3.4), (-sx, 0, 0), 12, 0.8, 0.5, "work")
        H.box(V((sx * (WALL_IN - 0.05), cy, -2.6)), (0.1, ln, 0.5), "hazard", bevel=0.0)
    # back wall: maintenance gallery, deflectors are per bay
    H.box(V((0, y1 + 0.8, (WALL_TOP - 5.0) / 2)), (2 * WALL_IN + 0.2, 1.6, WALL_TOP + 5.0),
          "hull2", bevel=0.04)
    H.box(V((0, y1 - 0.08, 3.6)), (2 * WALL_IN - 1.0, 0.2, 1.4), "dark", bevel=0.0)
    wk.win_row(L, RNG, (-WALL_IN + 1.0, y1 - 0.2, 3.6), (WALL_IN - 1.0, y1 - 0.2, 3.6),
               (0, -1, 0), 18, 1.0, 0.7, "hab")
    H.box(V((0, y1 - 0.3, 4.7)), (2 * WALL_IN, 0.6, 0.25), "dark", bevel=0.0)   # walkway
    label("MX-12", (-14.0, y1 - 0.02, 5.6), (0, -1, 0), (0, 0, 1), 0.9, wk.INK_DARK)
    label("MERC", (14.0, y1 - 0.02, 5.6), (0, -1, 0), (0, 0, 1), 0.9, wk.INK_DARK)
    build_mouth()
    build_roof()


def armour(sx):
    """Bolted armour plates on the sloped outer face, two courses, staggered, with a red
    band course between; buttresses on the vertical foot."""
    p0 = V((sx * FOOT_X, 0, -1.5))
    p1 = V((sx * WALL_OUT, 0, WALL_TOP))
    d = (p1 - p0)
    slope = d.length
    du = d.normalized()
    n = V((sx * abs(du.z), 0, abs(du.x)))
    th = math.atan2(n.z, n.x)            # rotation of local X onto the face normal
    r = Matrix.Rotation(-th, 4, "Y")
    y0, y1 = MOUTH_Y + 0.3, BACK_Y + 1.3
    for course, (t0, t1) in enumerate(((0.04, 0.47), (0.53, 0.97))):
        nplates = 6 if course == 0 else 7
        pl = (y1 - y0) / nplates
        for k in range(nplates):
            yc = y0 + pl * (k + 0.5)
            c = p0 + d * ((t0 + t1) / 2) + n * 0.22
            c.y = yc
            H.box(c, (0.44, pl - 0.25, slope * (t1 - t0)), "hull" if (k + course) % 3 else
                  "hull3", r=r, bevel=0.06)
            # bolt heads along the plate top edge
            for b in (-0.35, 0.0, 0.35):
                q = p0 + d * (t1 - 0.04) + n * 0.47
                q.y = yc + b * (pl - 0.6)
                H.box(q, (0.1, 0.22, 0.22), "dark", r=r, bevel=0.0)
    band = p0 + d * 0.5 + n * 0.12
    band.y = (y0 + y1) / 2
    H.box(band, (0.24, y1 - y0, slope * 0.06), "merc", r=r, bevel=0.0)
    for k in range(7):
        yy = y0 + 0.4 + k * (y1 - y0 - 0.8) / 6
        H.box(V((sx * (FOOT_X + 0.5), yy, -3.3)), (1.0, 1.0, 3.6), "dark", bevel=0.04)
    H.box(V((sx * (FOOT_X + 0.06), (y0 + y1) / 2, -2.2)), (0.12, y1 - y0, 0.45), "hazard",
          bevel=0.0)
    label("MERC" if sx < 0 else "MX-12", (sx * (FOOT_X + 0.02), MOUTH_Y + 6.0, -3.6),
          (sx, 0, 0), (0, 0, 1), 1.1, wk.INK_DARK)
    lamp((sx * (FOOT_X + 0.1), MOUTH_Y + 0.6, -1.0), 0.4, "red")
    lamp((sx * (FOOT_X + 0.1), BACK_Y + 1.0, -1.0), 0.4, "red")


def build_mouth():
    fy = MOUTH_Y - 0.6
    for sx in (-1, 1):
        # heavy frame posts with hazard faces and edge lamps
        H.box(V((sx * (WALL_IN + 1.6), fy, (HEAD_Z - 2.0) / 2)), (3.6, 1.6, HEAD_Z + 8.0),
              "hull2", bevel=0.05)
        H.box(V((sx * (WALL_IN + 0.15), fy - 0.81, (DECK_Z + HEAD_Z) / 2)),
              (0.6, 0.06, HEAD_Z - DECK_Z), "hazard",
              bevel=0.0)
        for z in (-2.4, 0.4, 3.2, 5.8):
            lamp((sx * (WALL_IN - 0.25), fy - 0.75, z), 0.42, "light")
    # header: deep box girder spanning the whole mouth
    H.box(V((0, fy, HEAD_Z + 1.1)), (2 * WALL_OUT + 1.6, 1.8, 2.2), "hull2", bevel=0.05)
    H.box(V((0, fy - 0.92, HEAD_Z + 0.25)), (2 * WALL_IN, 0.06, 0.4), "hazard", bevel=0.0)
    H.box(V((0, fy, HEAD_Z + 2.5)), (2 * WALL_OUT + 1.2, 1.4, 0.6), "dark", bevel=0.0)
    for i, bx in enumerate(BAYS):
        # bay number + launch signal (red / amber / green stack) per bay
        label(f"BAY {i + 1}", (bx - 1.6, fy - 0.91, HEAD_Z + 1.4), (0, -1, 0), (0, 0, 1),
              0.8, wk.INK_DARK)
        H.box(V((bx + 2.6, fy - 1.0, HEAD_Z + 1.1)), (1.0, 0.3, 1.9), "dark", bevel=0.0)
        for k, m in enumerate(("red", "light", "green")):
            on = m if (i + k) % 3 != 1 or m == "green" else "light"
            lamp((bx + 2.6, fy - 1.18, HEAD_Z + 1.7 - k * 0.6), 0.42, on)
        # floodlight strip on the header underside
        L.box(V((bx, fy, HEAD_Z - 0.04)), (6.0, 0.5, 0.06), "cyan", bevel=0.0)
    for sx in (-1, 1):
        label("#CHEV", (sx * (WALL_IN + 1.0), fy - 0.91, HEAD_Z + 1.1), (0, -1, 0),
              (0, 0, 1), 0.6, wk.INK_DARK)


def build_roof():
    y0, y1 = MOUTH_Y, BACK_Y
    # longitudinal gantry rails on the dividers and along the walls
    for x in DIVIDERS + (-WALL_IN + 0.5, WALL_IN - 0.5):
        H.box(V((x, (y0 + y1) / 2, RAIL_Z - 0.4)), (0.9, y1 - y0, 0.8), "dark", bevel=0.0)
        H.box(V((x, (y0 + y1) / 2, RAIL_Z + 0.05)), (0.4, y1 - y0, 0.1), "metal", bevel=0.0)
    # open roof over the bays: floodlight bars hung from the rails over each bay nose
    for bx in BAYS:
        yy = NOSE_Y + 3.0
        H.box(V((bx, yy, RAIL_Z - 0.2)), (BERTH_SPACING - 1.0, 0.4, 0.3), "dark", bevel=0.0)
        L.box(V((bx, yy, RAIL_Z - 0.37)), (3.0, 0.3, 0.05), "cyan", bevel=0.0)
    # armoured roof over the rear (engine bays + deflectors)
    ry0, ry1 = 5.6, BACK_Y + 1.6
    H.box(V((0, (ry0 + ry1) / 2, ROOF_Z)), (2 * WALL_OUT, ry1 - ry0, 1.2), "hull2",
          bevel=0.03)
    for k in range(6):
        x = -WALL_OUT + 2.6 + k * (2 * WALL_OUT - 5.2) / 5
        H.box(V((x, (ry0 + ry1) / 2 + 0.2, ROOF_Z + 0.75)), (6.4, ry1 - ry0 - 1.2, 0.3),
              "hull" if k % 2 else "hull3", bevel=0.05)
    H.box(V((0, ry0 + 0.25, ROOF_Z + 0.65)), (2 * WALL_OUT, 0.5, 0.2), "hazard", bevel=0.0)
    # radiator fins on the rear roof (edge-on, along X)
    for k in range(6):
        y = ry0 + 1.2 + k * 0.7
        H.box(V((-8.0, y, ROOF_Z + 2.2)), (9.0, 0.1, 2.6), "radiator", bevel=0.0)
        H.box(V((8.0, y, ROOF_Z + 2.2)), (9.0, 0.1, 2.6), "radiator", bevel=0.0)
    for sx in (-1, 1):
        H.box(V((sx * 8.0, ry0 + 3.0, ROOF_Z + 0.95)), (9.4, 4.6, 0.3), "dark", bevel=0.0)
        H.tube(V((sx * 3.0, ry0 + 1.4, ROOF_Z + 1.1)), V((sx * 3.0, ry1 - 1.0, ROOF_Z + 1.1)),
               0.25, 0.25, "accent", segs=8)
    # roof edge lamps
    for x in (-WALL_OUT + 0.4, WALL_OUT - 0.4):
        for y in (MOUTH_Y + 0.4, BACK_Y + 1.2):
            lamp((x, y, WALL_TOP + 0.7), 0.4, "red")
    # PD turrets on the front wall tops
    for sx in (-1, 1):
        pd_turret(V((sx * (WALL_IN + 1.5), MOUTH_Y + 4.5, WALL_TOP + 0.5)), sx)


def pd_turret(c, sx):
    H.cyl(c + V((0, 0, 0.35)), 2.0, 1.9, 0.7, "dark", segs=12)
    H.cyl(c + V((0, 0, 1.0)), 1.5, 1.5, 0.7, "hull2", segs=12)
    yaw = math.radians(-90 + sx * 20)
    r = Matrix.Rotation(yaw + math.pi / 2, 4, "Z")
    H.box(c + V((0, 0, 2.0)), (2.8, 3.2, 1.5), "hull", r=r, bevel=0.15)
    H.box(c + V((0, 0, 2.78)), (2.2, 2.6, 0.08), "merc", r=r, bevel=0.0)
    d = V((math.cos(yaw), math.sin(yaw), 0))
    s = V((-d.y, d.x, 0))
    for o in (-0.55, 0.55):
        H.tube(c + V((0, 0, 2.0)) + s * o + d * 1.4, c + V((0, 0, 2.0)) + s * o + d * 5.0,
               0.18, 0.14, "dark", segs=6)
        H.cyl(c + V((0, 0, 2.0)) + s * o + d * 2.0, 0.28, 0.28, 0.9, "hull2", segs=6,
              axis_rot=Matrix.Rotation(yaw - math.pi / 2, 4, "Z") @ parts.ALONG_Y)
    H.box(c + V((0, 0, 2.0)) - s * 1.6, (0.4, 1.4, 1.0), "dark", r=r, bevel=0.0)
    lamp(c + V((0, 0, 2.9)) - d * 0.9, 0.35, "red")


# ---------------------------------------------------------------- bays
def build_bays():
    for i, bx in enumerate(BAYS):
        cradle(i, bx)
        gantry(bx)
        deflector(bx)
    for x in DIVIDERS:
        divider(x)
    side_arm(-WALL_IN + 0.3, BAYS[0], wall=True)
    side_arm(WALL_IN - 0.3, BAYS[-1], wall=True)


def cradle(i, x):
    """Launch cradle: catapult sled on twin rails, two clamp saddles, deck markings."""
    yc = BERTH_Y
    dz = DECK_Z
    # deck markings: hazard border around the bay box, bay number on the deck
    for sx in (-1, 1):
        H.box(V((x + sx * 4.3, (MOUTH_Y + TAIL_Y + 2) / 2, dz + 0.02)),
              (0.35, TAIL_Y + 2 - MOUTH_Y - 0.4, 0.05), "hazard", bevel=0.0)
    H.box(V((x, TAIL_Y + 1.8, dz + 0.02)), (8.95, 0.35, 0.05), "hazard", bevel=0.0)
    label(f"BAY {i + 1}", (x + 2.9, MOUTH_Y + 1.2, dz + 0.03), (0, 0, 1), (0, 1, 0), 0.6,
          wk.INK_LIGHT, 0.6)
    # catapult rails: from the deflector out across the mouth onto the apron
    for sx in (-1, 1):
        H.box(V((x + sx * 1.3, (TAIL_Y + 2.0 + APRON_Y + 1.0) / 2, dz + 0.1)),
              (0.36, TAIL_Y + 2.0 - APRON_Y - 1.0, 0.2), "metal", bevel=0.0)
    H.box(V((x, (TAIL_Y + 2.0 + APRON_Y + 1.0) / 2, dz + 0.04)),
          (1.6, TAIL_Y + 2.0 - APRON_Y - 1.0, 0.08), "dark", bevel=0.0)
    # sled + saddles under the hull (hull bottom z SHIP_BOT)
    H.box(V((x, yc, dz + 0.35)), (3.4, 12.0, 0.5), "hull2", bevel=0.1)
    H.box(V((x, yc - 6.2, dz + 0.4)), (3.0, 0.5, 0.6), "hazard", bevel=0.0)
    for dy in (-4.2, 3.6):
        # yoke + rubber pad, 5 cm under the hull bottom
        H.box(V((x, yc + dy, dz + 0.6)), (3.6, 1.4, 0.5), "dark", bevel=0.0)
        H.box(V((x, yc + dy, SHIP_BOT - 0.1)), (1.6, 1.0, 0.1), "metal", bevel=0.0)
        for sx in (-1, 1):
            # clamp arm: post beside the hull, jaw angled in under it
            px = x + sx * (SHIP_HW + 0.6)
            H.box(V((px, yc + dy, -2.4)), (0.45, 0.9, 2.0), "merc", bevel=0.1)
            H.box(V((px - sx * 0.45, yc + dy, -2.75)), (0.6, 0.8, 0.3), "dark", bevel=0.0)
            lamp((px + sx * 0.25, yc + dy - 0.46, -1.6), 0.25, "amber")
    # deck service pit + umbilical to the ship flank (stops short of the hull)
    for sx in (-1, 1):
        if (sx > 0) == (i % 2 == 0):
            continue
        px = x + sx * 3.4
        H.box(V((px, yc + 1.5, dz + 0.4)), (1.2, 2.0, 0.8), "dark", bevel=0.05)
        H.box(V((px, yc + 1.5, dz + 0.82)), (1.0, 1.8, 0.05), "hazard", bevel=0.0)
        H.tube(V((px, yc + 1.5, dz + 0.8)), V((px, yc + 1.5, -0.8)), 0.22, 0.22, "accent",
               segs=8)
        H.tube(V((px, yc + 1.5, -0.8)), V((x + sx * (SHIP_HW + 0.3), yc + 1.5, -0.6)), 0.2,
               0.2, "accent", segs=8)
        lamp((px, yc + 0.48, dz + 0.75), 0.25, "green")
    SCORCH.append((x, TAIL_Y + 1.0, dz, 3.2))
    SCORCH.append((x, MOUTH_Y - 2.0, dz, 2.6))


def gantry(x):
    """Repair gantry: bridge on the divider rails over the mid hull, trolley, telescopic
    mast, two-link tool arm hovering above the dorsal hull."""
    gy = BERTH_Y + 3.4
    span = BERTH_SPACING - 0.9
    zb = RAIL_Z + 0.7
    H.box(V((x, gy, zb)), (span, 1.3, 0.9), "merc", bevel=0.08)
    H.box(V((x, gy, zb + 0.5)), (span - 0.4, 0.5, 0.12), "hazard", bevel=0.0)
    for sx in (-1, 1):   # end trucks riding the rails
        H.box(V((x + sx * (span / 2 - 0.2), gy, zb - 0.1)), (1.1, 2.6, 1.0), "hull2",
              bevel=0.08)
        lamp((x + sx * (span / 2 - 0.2), gy - 1.32, zb), 0.28, "light")
    tx = x + 1.2
    H.box(V((tx, gy, zb - 0.85)), (1.6, 1.8, 0.8), "hull", bevel=0.1)
    mz = SHIP_TOP + 1.6
    H.box(V((tx, gy, (zb - 1.2 + mz) / 2)), (0.55, 0.55, zb - 1.2 - mz), "metal",
          bevel=0.0)
    H.box(V((tx, gy, (zb - 1.2 + mz + 2.0) / 2)), (0.75, 0.75, 1.6), "hull2", bevel=0.0)
    j0 = V((tx, gy, mz))
    j1 = V((x - 0.6, gy - 3.0, SHIP_TOP + 1.5))
    j2 = V((x - 1.0, gy - 5.4, SHIP_TOP + 0.75))
    H.box(j0, (0.8, 0.8, 0.8), "dark", bevel=0.1)
    parts.strut(H, j0, j1, 0.4, 0.4, "hull")
    H.box(j1, (0.6, 0.6, 0.6), "dark", bevel=0.1)
    parts.strut(H, j1, j2, 0.3, 0.3, "hull")
    H.box(j2, (0.45, 0.6, 0.35), "hazard", bevel=0.0)
    lamp(j2 + V((0, 0, -0.25)), 0.22, "cyan")
    # second, parked tool arm aft, folded up
    k0 = V((x - 2.4, gy + 0.2, zb - 0.5))
    k1 = V((x - 2.9, gy + 2.6, SHIP_TOP + 2.4))
    parts.strut(H, k0, k1, 0.3, 0.3, "hull2")
    H.box(k1, (0.5, 0.5, 0.5), "hazard", bevel=0.0)


def deflector(x):
    """Blast deflector behind the engine bell: ribbed plate leaning back toward the wall."""
    y = TAIL_Y + 3.2
    r = Matrix.Rotation(math.radians(-28), 4, "X")
    H.box(V((x, y, DECK_Z + 2.0)), (8.0, 0.4, 4.4), "metal", r=r, bevel=0.0)
    for k in range(5):
        H.box(V((x - 3.2 + k * 1.6, y + 0.35, DECK_Z + 2.0)), (0.25, 0.4, 4.4), "dark", r=r,
              bevel=0.0)
    H.box(V((x, y + 1.5, DECK_Z + 1.0)), (8.0, 1.4, 2.0), "dark", bevel=0.05)
    H.box(V((x, y - 0.95, DECK_Z + 0.08)), (7.6, 0.3, 0.16), "hazard", bevel=0.0)


def divider(x):
    """Bay divider: low blast barrier, two pillars carrying the gantry rail, side arms."""
    y0, y1 = BERTH_Y - 1.0, BACK_Y
    H.box(V((x, (y0 + y1) / 2, DECK_Z + 0.8)), (0.6, y1 - y0, 1.6), "hull2", bevel=0.1)
    H.box(V((x, (y0 + y1) / 2, DECK_Z + 1.62)), (0.7, y1 - y0, 0.1), "hazard", bevel=0.0)
    H.box(V((x, y0 - 0.4, DECK_Z + 0.5)), (0.8, 0.8, 1.0), "hazard", bevel=0.0)
    for yy in (BERTH_Y - 1.0, BACK_Y - 0.6):
        H.box(V((x, yy, (DECK_Z + RAIL_Z) / 2)), (1.0, 1.0, RAIL_Z - DECK_Z), "hull2",
              bevel=0.06)
        H.box(V((x, yy, DECK_Z + 0.4)), (1.4, 1.4, 0.8), "hazard", bevel=0.0)
        lamp((x, yy - 0.52, 5.0), 0.32, "red")
    for d in (-1, 1):
        side_arm(x, x + d * BERTH_SPACING / 2)


def side_arm(px, bx, wall=False):
    """Service arm from a divider pillar (or the wall) to the ship flank, short of it."""
    s = 1 if bx > px else -1
    yy = BERTH_Y - 1.0
    base = V((px + s * 0.5, yy, 1.6))
    H.box(base, (0.5, 0.9, 0.9), "dark", bevel=0.05)
    elbow = V((bx - s * (SHIP_HW + 2.0), yy - 2.0, 2.0))
    tip = V((bx - s * (SHIP_HW + 1.2), yy - 3.4, 1.2))
    parts.strut(H, base, elbow, 0.32, 0.32, "hull")
    H.box(elbow, (0.5, 0.5, 0.5), "dark", bevel=0.1)
    parts.strut(H, elbow, tip, 0.26, 0.26, "hull")
    H.box(tip, (0.3, 0.5, 0.4), "hazard", bevel=0.0)
    lamp(tip + V((0, 0, 0.3)), 0.2, "green")
    if wall:
        H.box(V((px + s * 0.25, yy, 0.0)), (0.6, 1.4, 4.0), "hull2", bevel=0.05)


# ---------------------------------------------------------------- apron
def build_apron():
    ay0, ay1 = MOUTH_Y - 1.4, APRON_Y
    acy = (ay0 + ay1) / 2
    H.box(V((0, acy, DECK_Z - 0.6)), (2 * WALL_OUT + 1.0, ay0 - ay1, 1.2), "pad", bevel=0.0)
    H.box(V((0, acy, DECK_Z - 1.8)), (2 * WALL_IN, ay0 - ay1 - 1.0, 1.2), "dark", bevel=0.0)
    for sx in (-1, 1):
        H.box(V((sx * (WALL_OUT + 0.1), acy, DECK_Z + 0.02)), (0.8, ay0 - ay1, 0.06),
              "hazard", bevel=0.0)
        for k in range(4):
            lamp((sx * (WALL_OUT + 0.35), ay0 - 1.5 - k * 3.0, DECK_Z + 0.2), 0.4, "red")
    H.box(V((0, ay1 + 0.4, DECK_Z + 0.02)), (2 * WALL_OUT + 0.6, 0.8, 0.06), "hazard",
          bevel=0.0)
    for x in (-10.0, 10.0):
        label("NO STEP", (x, ay1 + 2.6, DECK_Z + 0.03), (0, 0, 1), (0, 1, 0), 1.0,
              wk.INK_LIGHT, 0.6)
    label("HOT", (0.0, ay1 + 2.6, DECK_Z + 0.03), (0, 0, 1), (0, 1, 0), 1.2, wk.INK_LIGHT,
          0.6)
    for bx in BAYS:
        SCORCH.append((bx, acy, DECK_Z, 4.0))
        # launch lights: lamp pairs either side of the catapult rails, then a light boom
        for k in range(5):
            yy = ay0 - 1.0 - k * 2.2
            m = "green" if k == 0 else "light"
            lamp((bx - 2.3, yy, DECK_Z + 0.2), 0.42, m)
            lamp((bx + 2.3, yy, DECK_Z + 0.2), 0.42, m)
        parts.strut(H, V((bx, ay1 + 0.2, DECK_Z - 1.0)), V((bx, ay1 - 6.6, DECK_Z - 1.0)),
                    0.4, 0.4, "dark")
        for k in range(3):
            yy = ay1 - 1.4 - k * 2.4
            H.box(V((bx, yy, DECK_Z - 0.8)), (2.4, 0.25, 0.25), "dark", bevel=0.0)
            for dx in (-0.9, 0.0, 0.9):
                lamp((bx + dx, yy, DECK_Z - 0.6), 0.3, "cyan" if k % 2 == 0 else "light")
        lamp((bx, ay1 - 6.7, DECK_Z - 0.8), 0.45, "red")


# ---------------------------------------------------------------- +X: control tower
def build_tower():
    t = TOWER
    # deck under the services
    H.box(V((30.0, -1.0, -5.5)), (9.6, 26.0, 1.2), "dark", bevel=0.0)
    H.box(V((30.0, -1.0, -4.8)), (9.0, 25.4, 0.3), "pad", bevel=0.0)
    # shaft
    cz = 15.4
    sz0, sz1 = -4.8, cz - 1.8
    H.box(t + V((0, 0, (sz0 + sz1) / 2)), (4.6, 4.6, sz1 - sz0), "hull", bevel=0.04)
    for sx in (-1, 1):
        H.box(t + V((sx * 2.35, 0, (sz0 + sz1) / 2)), (0.12, 1.2, sz1 - sz0), "merc",
              bevel=0.0)
    for z in (2.6, 5.0, 7.4, 9.8):
        wk.win_row(L, RNG, t + V((-1.5, -2.32, z)), t + V((1.5, -2.32, z)), (0, -1, 0), 3,
                   0.55, 0.6, "hab")
    for z in (4.0, 9.0):   # ring platforms around the shaft
        H.box(t + V((0, 0, z)), (5.6, 5.6, 0.3), "dark", bevel=0.0)
    label("FLT CTRL", t + V((0, -2.32, -0.6)), (0, -1, 0), (0, 0, 1), 0.7, wk.INK_DARK)
    # flight control cab: wider than the shaft, slanted window band all round
    H.box(t + V((0, 0, cz - 1.4)), (6.4, 6.4, 1.0), "hull2", bevel=0.05)
    prof = [(0.0, cz - 0.9), (3.9, cz - 0.9), (4.6, cz + 0.6), (4.3, cz + 1.8),
            (0.0, cz + 1.8)]
    H.lathe(prof, 8, lambda i, j: {0: "hull2", 1: "glass", 2: "hull", 3: "hull"}[j],
            matrix=Matrix.Translation(t), start=math.pi / 8)
    for k in range(8):
        a = math.pi / 8 + (k + 0.5) * 2 * math.pi / 8
        n = V((math.cos(a), math.sin(a), -0.45)).normalized()
        c = t + V((4.3 * math.cos(a) * 0.97, 4.3 * math.sin(a) * 0.97, cz - 0.15))
        if k % 4 != 1:
            parts.quad(L, c + n * 0.05, n, (0, 0, 1), 2.6, 0.9,
                       "window" if k % 3 else "window_cool")
    H.box(t + V((0, 0, cz + 2.0)), (5.0, 5.0, 0.5), "dark", bevel=0.0)
    parts.dish(H, t + V((-1.2, 0.8, cz + 2.6)), 1.5, (-0.5, -0.6, 0.7), "hull", "dark")
    H.cyl(t + V((1.6, -1.2, cz + 4.2)), 0.1, 0.06, 3.6, "dark", segs=5)
    lamp(t + V((1.6, -1.2, cz + 6.1)), 0.45, "red")
    H.box(t + V((1.4, 1.4, cz + 2.7)), (1.6, 0.25, 0.6), "hull2", rot_z=0.5, bevel=0.0)
    # skybridge to the hangar wall top
    H.box(V(((WALL_OUT + t.x - 2.3) / 2, t.y, WALL_TOP + 0.4)),
          (t.x - 2.3 - WALL_OUT + 0.6, 2.2, 2.2),
          "hull2", bevel=0.05)
    L.box(V(((WALL_OUT + t.x - 2.3) / 2, t.y - 1.12, WALL_TOP + 0.5)),
          (t.x - 3.3 - WALL_OUT, 0.06, 0.5),
          "window", bevel=0.0)
    # tanks + manifold behind the tower
    for i, (x, y) in enumerate(((28.0, 2.0), (31.6, 2.0), (28.0, 6.2), (31.6, 6.2))):
        wk.tank_v(H, (x, y, -4.65), 1.6, 6.4, "hull" if i % 2 else "hull3", "merc", segs=12)
    H.tube(V((26.0, 4.1, -3.6)), V((33.4, 4.1, -3.6)), 0.25, 0.25, "metal", segs=6)
    H.tube(V((26.0, 4.1, -3.6)), V((FOOT_X, 4.1, -3.6)), 0.25, 0.25, "metal", segs=6)
    # radiator rack at the back corner (vertical fins)
    for k in range(6):
        y = 9.0 + k * 0.9
        H.box(V((30.0, y, -1.8)), (4.0, 0.12, 5.2), "radiator", bevel=0.0)
    H.box(V((30.0, 11.25, -4.4)), (4.4, 5.6, 0.6), "dark", bevel=0.0)
    wk.beacon(H, L, (34.2, -13.4, -3.9), 0.4, "red")
    wk.beacon(H, L, (34.2, 11.6, -3.9), 0.4, "red")


# ---------------------------------------------------------------- -X: ordnance yard
def build_yard():
    x0, x1, y0, y1 = YARD
    H.box(V(((x0 + x1) / 2, (y0 + y1) / 2, -5.5)), (x1 - x0 + 0.8, y1 - y0 + 0.8, 1.2),
          "dark", bevel=0.0)
    H.box(V(((x0 + x1) / 2, (y0 + y1) / 2, -4.8)), (x1 - x0, y1 - y0, 0.3), "pad", bevel=0.0)
    H.box(V((x0 + 0.1, (y0 + y1) / 2, -4.62)), (0.3, y1 - y0, 0.06), "hazard", bevel=0.0)
    H.box(V(((x0 + x1) / 2, y0 + 0.1, -4.62)), (x1 - x0, 0.3, 0.06), "hazard", bevel=0.0)
    # missile racks: frame, three tiers of missiles (along Y), red warheads
    for rx in (x0 + 2.2, x0 + 5.8):
        ry0, ry1 = y1 - 11.5, y1 - 1.0
        for xx in (rx - 1.4, rx + 1.4):
            for yy in (ry0, (ry0 + ry1) / 2, ry1):
                H.box(V((xx, yy, -1.4)), (0.3, 0.3, 6.6), "dark", bevel=0.0)
            for z in (-3.6, -1.6, 0.4, 1.9):
                parts.strut(H, V((xx, ry0, z)), V((xx, ry1, z)), 0.22, 0.22, "dark")
        for z in (-3.6, -1.6, 0.4):
            for k in range(4):
                mx = rx - 1.0 + k * 0.66
                mz = z + 0.55
                H.cyl(V((mx, ry0 + 4.6, mz)), 0.27, 0.27, 8.4, "hull", segs=8,
                      axis_rot=parts.ALONG_Y)
                H.cyl(V((mx, ry0 + 0.0, mz)), 0.05, 0.27, 0.9, "merc", segs=8,
                      axis_rot=parts.ALONG_Y)
                H.box(V((mx, ry0 + 8.4, mz)), (0.12, 0.6, 0.7), "dark", bevel=0.0)
        H.box(V((rx, ry0 - 0.2, 2.15)), (3.2, 0.3, 0.5), "hazard", bevel=0.0)
    H.box(V((x0 + 4.0, y1 - 11.72, 3.0)), (6.6, 0.06, 1.0), "hull", bevel=0.0)
    label("AMMO", (x0 + 4.0, y1 - 11.76, 3.0), (0, -1, 0), (0, 0, 1), 0.8, wk.INK_DARK)
    # ammo crates in the front of the yard
    tones = ("hull2", "hull3", "hull2", "hull", "hull3", "hull2")
    bands = ("merc", "hazard", "merc", "hazard", "merc", "merc")
    i = 0
    for cx, cy, n in ((x0 + 2.0, y0 + 2.2, 2), (x0 + 5.0, y0 + 2.2, 3), (x0 + 2.0, y0 + 5.6, 1),
                      (x0 + 5.0, y0 + 5.6, 2)):
        for lv in range(n):
            wk.cargo_pod(H, (cx + RNG.uniform(-0.1, 0.1), cy, -3.85 + lv * 1.6),
                         (2.6, 3.0, 1.5), rot_z=RNG.uniform(-0.04, 0.04), body=tones[i % 6],
                         band=bands[(i + lv) % 6])
            i += 1
    label("ORD", (x0 + 3.5, y0 - 0.02, -3.9), (0, -1, 0), (0, 0, 1), 0.7, wk.INK_DARK)
    H.box(V((x0 + 3.5, y0 - 0.01, -3.9)), (3.4, 0.05, 0.9), "hull", bevel=0.0)
    # overhead loader: A-frame legs, beam into the hangar wall, hoist with a missile
    lx = (x0 + x1) / 2 - 0.8
    for yy in (y0 + 0.6, y1 - 0.6):
        parts.strut(H, V((x0 + 0.4, yy, -4.6)), V((lx, yy, 5.4)), 0.4, 0.4, "merc")
        parts.strut(H, V((x1 - 0.4, yy, -4.6)), V((lx, yy, 5.4)), 0.4, 0.4, "merc")
    H.box(V((lx, (y0 + y1) / 2, 5.8)), (1.0, y1 - y0 + 1.0, 0.8), "dark", bevel=0.0)
    hy = y0 + 8.0
    H.box(V((lx, hy, 5.0)), (1.6, 1.4, 0.8), "hazard", bevel=0.0)
    parts.strut(H, V((lx, hy, 4.6)), V((lx, hy, 2.0)), 0.06, 0.06, "dark")
    H.cyl(V((lx, hy, 1.6)), 0.3, 0.3, 4.8, "hull", segs=8, axis_rot=parts.ALONG_Y)
    H.box(V((lx, hy, 1.95)), (0.5, 1.2, 0.3), "dark", bevel=0.0)
    # feed conveyor from the yard into the hangar side wall
    H.box(V(((x1 + (-FOOT_X)) / 2, -2.0, -1.4)), (abs(-FOOT_X - x1) + 1.2, 1.6, 1.2),
          "hull2", bevel=0.05)
    H.box(V((x1 - 0.6, -2.0, -3.2)), (1.2, 1.4, 2.4), "dark", bevel=0.0)
    lamp((x1 - 0.2, -2.9, -0.4), 0.3, "amber")
    # yard floodlight poles
    for xx, yy in ((x0 + 0.4, y0 + 0.4), (x0 + 0.4, y1 - 0.4)):
        H.cyl(V((xx, yy, -0.6)), 0.12, 0.1, 8.0, "dark", segs=6)
        H.box(V((xx + 0.3, yy, 3.4)), (0.8, 0.5, 0.3), "dark", bevel=0.0)
        L.box(V((xx + 0.3, yy, 3.22)), (0.6, 0.35, 0.05), "cyan", bevel=0.0)
    for k in range(4):
        lamp((x0 + 0.6 + k * 2.6, y0 - 0.3, -4.6), 0.4, "light")


# ---------------------------------------------------------------- back
def build_back():
    pb = V((0, BACK_Y + 4.8, 0))
    H.box(pb + V((0, 0, -0.8)), (24.0, 6.4, 8.4), "hull2", bevel=0.05)
    H.box(pb + V((0, 0, 3.6)), (22.0, 5.4, 0.5), "dark", bevel=0.0)
    # reactor caps + vents
    for sx in (-1, 1):
        H.cyl(pb + V((sx * 6.5, 0.2, 4.6)), 1.8, 1.8, 1.6, "hull", segs=12)
        H.cyl(pb + V((sx * 6.5, 0.2, 5.6)), 1.8, 1.2, 0.4, "hull", segs=12)
        L.cyl(pb + V((sx * 6.5, 0.2, 5.85)), 0.5, 0.5, 0.2, "light", segs=6)
        wk.win_row(L, RNG, pb + V((sx * 12.02, -2.2, 1.0)), pb + V((sx * 12.02, 2.2, 1.0)),
                   (sx, 0, 0), 4, 0.5, 0.5, "store")
    H.box(pb + V((0, 3.22, 1.4)), (20.0, 0.06, 0.6), "merc", bevel=0.0)
    H.box(pb + V((0, 3.22, -3.6)), (20.0, 0.06, 0.5), "hazard", bevel=0.0)
    label("#BAR", (-7.5, pb.y + 3.24, -1.6), (0, 1, 0), (0, 0, 1), 0.7, wk.INK_DARK)
    label("#CHEV", (7.5, pb.y + 3.24, -1.6), (0, 1, 0), (0, 0, 1), 0.7, wk.INK_DARK)
    # link port on the back face (cargo shuttle side)
    H.cyl(V((LINK_POS[0], LINK_POS[1] - 0.9, LINK_POS[2])), 2.2, 2.2, 1.2, "dark", segs=12,
          axis_rot=parts.ALONG_Y)
    H.cyl(V((LINK_POS[0], LINK_POS[1] - 0.25, LINK_POS[2])), 1.6, 1.6, 0.2, "hull", segs=12,
          axis_rot=parts.ALONG_Y)
    for sx in (-1, 1):
        lamp((sx * 2.6, LINK_POS[1] - 0.5, LINK_POS[2] + 1.6), 0.35, "red")
    # comms mast at the back left
    m = V((-9.0, BACK_Y + 5.6, 3.85))
    wk.lattice_mast(H, m, 18.0, 0.9, 0.5, 4, "dark", chord=0.28, brace=0.13)
    H.box(m + V((0, 0, 14.6)), (5.0, 0.6, 0.4), "merc", rot_z=0.4, bevel=0.0)
    lamp(m + V((0, 0, 15.2)), 0.45, "red")
    wk.beacon(H, L, (11.0, BACK_Y + 7.4, 4.3), 0.4, "red")


# ---------------------------------------------------------------- assemble
def build_outpost():
    global H, L
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    H = parts.PanelPart(f"{PRE}_hull", MATS)
    L = parts.PanelPart(f"{PRE}_lights", MATS)
    for b in (build_shell, build_bays, build_apron, build_tower, build_yard, build_back):
        b()
    root = parts.make_root(PRE, size=10)
    hull = H.finish(root)
    lights = L.finish(root)
    lights.data.uv_layers.remove(lights.data.uv_layers["panel"])
    for name, pos, rz in (("dock_point", DOCK_POS, math.pi), ("spawn_point", SPAWN_POS, math.pi),
                          ("link_point", LINK_POS, 0.0)):
        parts.add_empty(name, root, pos, rot_z=rz, size=4)
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
    """Preview only: one merc_fighter per inner berth, nose out (not exported)."""
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
    target = (0.0, -6.0, 1.0)
    common.setup_preview(cam_loc=(target[0] - 45, target[1] - 75, target[2] + 80),
                         cam_target=target, ortho_scale=92, res=(1600, 1200),
                         key_dir=(-0.6, -0.35, 0.7), key_energy=3.5)
    a = os.path.join(common.PREVIEW_DIR, f"{PRE}_preview{sfx}.png")
    common.render(a)
    scene = bpy.context.scene
    cam = scene.camera
    cam.location = (0.0, -6.0, 200)
    cam.rotation_euler = (0, 0, 0)
    cam.data.ortho_scale = 80
    scene.render.resolution_x, scene.render.resolution_y = 1200, 1200
    b = os.path.join(common.PREVIEW_DIR, f"{PRE}_top{sfx}.png")
    common.render(b)
    for p in (a, b):
        shutil.copy(p, PREVIEW_COPY)


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, hull, lights = build_outpost()
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
