"""Generate the Explorer Outpost (survey / scout base) .glb and previews.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_explorer_outpost.py
  Options after `--`: --no-preview, --no-textures (flat materials, no Cycles bake).
Textures: one 2048 worn-industrial atlas (worn_kit / station_textures.WORN_KINDS plus a
"survey" blue paint kind), saved as blender/textures/explorer_outpost_*.jpg and embedded
as JPEG.

Design: free-standing survey base where scout captains hire on. A two-bay scout hangar
with a cable-stayed mag-launch rail on its roof that cantilevers out over the apron; a big
deep-space tracking dish on a yoke mount over its control block on -X; a three-dish
antenna array on the data block at the back; a tall nav beacon mast, an observatory /
telemetry block with a dome and the scout fuel tanks on +X; landing pads either side of
the apron for waiting ships.

Layout (Blender Z up, exported +Y up; Blender -Y = Godot +Z). Centre at origin, plane z=0.
Same family as the mercenary / mining outposts and the raider dock: the mouth faces -Y.
  hangar   x -12.6..12.6, mouth y = -14, back wall y = 8, deck top z = -3.6,
           berths x = +-4.4, y = -3 (Building defaults: berth_spacing 8.8, berth_depth 11)
  rail     roof launch rail x = 6, deck top z ~9.6, y 6..-27 (cantilever past the mouth)
  apron    y -15..-25, approach light rows out to y -33
  pads     side landing pads centred (+-17.5, -24), top z -1.6 (outer berths, 2 m up)
  dish     tracking dish over the DSN block at (-24, 1), dish rim up to z ~17
  back     data block y 9..16 with three array dishes on its roof, link port at y 16.6
  +X       observatory (19.5, -6), fuel tanks, nav beacon mast (21, 11) to z ~31
Hierarchy: explorer_outpost (empty root) -> explorer_outpost_hull, explorer_outpost_lights,
  dock_point, spawn_point, link_point (empties).
dock_point / spawn_point are rotated 180 deg about up, so their Godot -Z (forward) points
out of the mouth (Godot world +Z). link_point is unrotated: Godot -Z points out the back.
"""
import math
import os
import random
import sys

from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
import station_textures as st  # noqa: E402
import worn_kit as wk  # noqa: E402

V = Vector
PRE = "explorer_outpost"
OUT = os.path.join(common.ROOT, "assets", "models", "buildings", "explorer_outpost.glb")
BLEND = os.path.join(common.ROOT, "blender", "explorer_outpost.blend")
MOUTH_Y, BACK_Y = -14.0, 8.0
DOCK_POS = (0.0, -14.0, 0.0)
SPAWN_POS = (0.0, -32.0, 0.0)
LINK_POS = (0.0, 16.6, 0.5)
BAY_X = 4.4                  # berth centre |x| (berth_spacing 8.8)
BERTH_Y = -3.0               # dock_point y + berth_depth 11
DECK_Z = -3.6
WALL_IN, WALL_OUT = 9.0, 12.6
ROOF_Z = 7.0                 # bay ceiling (roof slab underside)
ROOF_TOP = 8.4
RAIL_X = 6.0
RAIL_Z = 9.6                 # rail deck top
PADS = ((-17.5, -24.0), (17.5, -24.0))
PAD_Z = -1.6
DISH = V((-24.0, 1.0, 0.0))  # tracking dish turntable centre
MAST = V((21.0, 11.0, 0.0))
OBS = V((19.5, -6.0, 0.0))
ALONG_Y = parts.ALONG_Y
# the dishes all look the same way: up and out toward -X -Y (their bowls face the camera)
LOOK_AZ, LOOK_EL = math.radians(225), math.radians(52)
LOOK = V((math.cos(LOOK_EL) * math.cos(LOOK_AZ), math.cos(LOOK_EL) * math.sin(LOOK_AZ),
          math.sin(LOOK_EL)))
LABELS = ["SURVEY", "EX-04", "#BAR", "#CHEV", "NAV", "DSN-2", "NO STEP", "SCOUT 1",
          "SCOUT 2", "FUEL", "LAUNCH"]
XZ = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))

# survey paint: muted navy-blue, same wear model as the station accent paint
SURVEY = dict(st.WORN_KINDS["accent"])
SURVEY["tones"] = [(0.045, 0.085, 0.15), (0.04, 0.075, 0.135), (0.055, 0.095, 0.165),
                   (0.038, 0.07, 0.125), (0.05, 0.09, 0.155), (0.042, 0.08, 0.14)]
SURVEY["bleach"] = 0.35
st.WORN_KINDS["survey"] = SURVEY

MATS = {}
DECALS = []
SCORCH = []
H = L = None
RNG = random.Random(11)


def build_materials():
    wk.build_materials(PRE, MATS)
    m = common.make_material
    MATS["survey"] = m(f"{PRE}_survey_paint", (0.05, 0.09, 0.15), roughness=0.6)
    MATS["mli_gold"] = m(f"{PRE}_mli_gold", (0.58, 0.38, 0.12), roughness=0.3, metallic=1.0)


def label(text, centre, normal, up, h, colour, opacity=0.85):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity))


def lamp(pos, s=0.4, mat="light"):
    wk.lamp(L, pos, s, mat)


def look_frame(centre):
    """4x4 frame at `centre` with local +Z along LOOK (dish axis) and local X horizontal."""
    z = LOOK.normalized()
    x = V((0, 0, 1)).cross(z).normalized()
    y = z.cross(x)
    return Matrix.Translation(centre) @ Matrix((x, y, z)).transposed().to_4x4()


def dish(centre, r, depth, segs, ribs=True, sub=True):
    """Prime / Cassegrain dish in look_frame(centre): white panelled bowl, dark back, metal
    rim, quadrupod with a subreflector, gold feed cone. Returns the frame."""
    m = look_frame(centre)
    f = r * r / (4 * depth)
    rk = [r * k / 6 for k in range(1, 7)]
    prof = [(0.0, -0.3 * r / 9)]
    prof += [(q, q * q / (4 * f) - 0.35 * r / 9) for q in rk]
    prof += [(r + 0.2 * r / 9, depth + 0.05), (r + 0.2 * r / 9, depth + 0.2 * r / 9)]
    prof += [(q, q * q / (4 * f) + 0.02) for q in reversed(rk)]
    prof += [(0.0, 0.02)]
    nb = 7

    def mat_fn(i, j):
        if j < nb - 1:
            return "hull2"
        if j < nb + 1:
            return "metal"
        return "hull" if j % 2 else "hull3"
    H.lathe(prof, segs, mat_fn, matrix=m)
    # back: hub and radial ribs
    H.cyl(m @ V((0, 0, -0.9 * r / 9)), 1.8 * r / 9, 1.4 * r / 9, 1.4 * r / 9, "dark", segs=10)
    if ribs:
        for k in range(8):
            a = k * math.pi / 4
            q = r * 0.92
            parts.strut(H, m @ V((math.cos(a) * 1.5 * r / 9, math.sin(a) * 1.5 * r / 9,
                                  -0.9 * r / 9)),
                        m @ V((math.cos(a) * q, math.sin(a) * q, q * q / (4 * f) - 0.5 * r / 9)),
                        0.3 * r / 9, 0.3 * r / 9, "dark")
    # feed cone at the vertex, quadrupod to the subreflector
    H.cyl(m @ V((0, 0, 0.8 * r / 9)), 0.9 * r / 9, 0.45 * r / 9, 1.6 * r / 9, "mli_gold",
          segs=8)
    if sub:
        top = m @ V((0, 0, depth + r * 0.42))
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            q = r * 0.8
            parts.strut(H, m @ V((math.cos(a) * q, math.sin(a) * q, q * q / (4 * f) + 0.05)),
                        top, 0.22 * r / 9 + 0.04, 0.22 * r / 9 + 0.04, "dark")
        H.lathe([(0.0, -0.25 * r / 9), (1.3 * r / 9, 0.1 * r / 9), (1.3 * r / 9, 0.3 * r / 9),
                 (0.0, 0.15 * r / 9)], 10, lambda i, j: "metal",
                matrix=Matrix.Translation(top) @ m.to_3x3().to_4x4())
        lamp(top + V((0, 0, 0.45 * r / 9 + 0.2)), 0.4 if r > 5 else 0.3, "red")
    return m


# ---------------------------------------------------------------- hangar
def build_hangar():
    y0, y1 = MOUTH_Y, BACK_Y
    cy, ln = (y0 + y1) / 2, y1 - y0
    H.box(V((0, cy - 1.0, -5.4)), (2 * WALL_OUT + 1.0, ln + 2.0, 1.6), "dark", bevel=0.05)
    H.box(V((0, cy, DECK_Z - 0.4)), (2 * WALL_IN, ln, 0.8), "pad", bevel=0.0)
    # side walls: sloped-shoulder section, ribs, survey stripe, window band
    for sx in (-1, 1):
        sec = [(WALL_IN, -4.6), (WALL_OUT, -4.6), (WALL_OUT, 0.8), (WALL_IN + 1.6, ROOF_TOP),
               (WALL_IN, ROOF_TOP)]
        sec = [(sx * x, z) for x, z in sec]
        if sx < 0:
            sec.reverse()
        H.slab(sec, y0, y1, "hull", matrix=XZ)
        for k in range(6):
            yy = y0 + 1.0 + k * (ln - 2.0) / 5
            H.box(V((sx * (WALL_OUT + 0.4), yy, -1.9)), (0.8, 0.8, 5.4), "dark", bevel=0.05)
            H.box(V((sx * (WALL_IN - 0.15), yy, 1.5)), (0.3, 0.6, 11.0), "dark", bevel=0.0)
        H.box(V((sx * (WALL_OUT + 0.06), cy, -0.4)), (0.12, ln - 2.0, 0.7), "survey", bevel=0.0)
        wk.win_row(L, RNG, (sx * (WALL_OUT + 0.02), y0 + 3.0, -2.2),
                   (sx * (WALL_OUT + 0.02), y1 - 3.0, -2.2), (sx, 0, 0), 8, 0.6, 0.5, "work")
        wk.win_row(L, RNG, (sx * (WALL_IN - 0.02), y0 + 2.0, 3.2),
                   (sx * (WALL_IN - 0.02), y1 - 2.0, 3.2), (-sx, 0, 0), 8, 0.7, 0.45, "work")
        label("SCOUT 1" if sx < 0 else "SCOUT 2", (sx * (WALL_OUT + 0.02), y0 + 6.5, 1.0),
              (sx, 0, 0), (0, 0, 1), 0.9, wk.INK_DARK)
    # roof slab, transverse ribs, survey bands
    H.box(V((0, cy, (ROOF_Z + ROOF_TOP) / 2)), (2 * WALL_IN + 0.2, ln, ROOF_TOP - ROOF_Z),
          "hull2", bevel=0.0)
    for k in range(6):
        yy = y0 + 0.8 + k * (ln - 1.6) / 5
        H.box(V((0, yy, ROOF_TOP + 0.2)), (2 * WALL_IN + 3.0, 0.7, 0.4), "dark", bevel=0.0)
    H.box(V((-2.0, cy, ROOF_TOP + 0.03)), (0.9, ln - 1.0, 0.08), "survey", bevel=0.0)
    H.box(V((-7.6, cy, ROOF_TOP + 0.03)), (1.4, ln - 1.0, 0.08), "survey", bevel=0.0)
    # back wall + gallery
    H.box(V((0, y1 + 0.8, 1.5)), (2 * WALL_OUT, 1.6, 12.4), "hull2", bevel=0.05)
    H.box(V((0, y1 - 0.1, 3.4)), (2 * WALL_IN - 1, 0.25, 1.6), "dark", bevel=0.0)
    wk.win_row(L, RNG, (-WALL_IN + 1.0, y1 - 0.25, 3.4), (WALL_IN - 1.0, y1 - 0.25, 3.4),
               (0, -1, 0), 10, 0.9, 0.7, "work")
    # bay ceiling floodlights
    for k in range(1, 5):
        yy = y0 + 0.8 + k * (ln - 1.6) / 5 - 2.0
        for sx in (-1, 1):
            H.box(V((sx * BAY_X, yy, ROOF_Z - 0.15)), (1.6, 0.6, 0.3), "dark", bevel=0.0)
            L.box(V((sx * BAY_X, yy, ROOF_Z - 0.32)), (1.3, 0.4, 0.05), "cyan", bevel=0.0)
    # centre divider pillars with red lamps
    for k in range(3):
        yy = y0 + 2.0 + k * (ln - 4.0) / 2
        H.box(V((0, yy, 1.7)), (0.8, 0.8, 10.6), "hull2", bevel=0.08)
        H.box(V((0, yy, DECK_Z + 0.4)), (1.3, 1.3, 0.8), "hazard", bevel=0.0)
        lamp((0, yy - 0.45, 5.0), 0.35, "red")
    # mouth frame: posts, header with the station mark, edge lamps
    fy = y0 - 0.5
    for sx in (-1, 1):
        H.box(V((sx * (WALL_IN + 1.6), fy, 1.8)), (3.6, 1.2, 13.0), "hull2", bevel=0.06)
        H.box(V((sx * WALL_IN, fy - 0.62, 1.4)), (0.5, 0.06, 9.6), "hazard", bevel=0.0)
        for z in (-3.0, 0.6, 4.2):
            lamp((sx * (WALL_IN - 0.4), fy - 0.6, z), 0.4, "light")
        lamp((sx * (WALL_OUT - 0.3), fy - 0.6, 7.6), 0.4, "cyan")
    H.box(V((0, fy, ROOF_Z + 0.4)), (2 * WALL_OUT, 1.2, 2.2), "hull2", bevel=0.06)
    H.box(V((0, fy - 0.62, ROOF_Z - 0.45)), (2 * WALL_IN, 0.06, 0.35), "hazard", bevel=0.0)
    H.box(V((-6.0, fy - 0.61, ROOF_Z + 0.55)), (6.0, 0.05, 1.1), "survey", bevel=0.0)
    label("SURVEY", (-6.0, fy - 0.64, ROOF_Z + 0.55), (0, -1, 0), (0, 0, 1), 0.85,
          wk.INK_LIGHT)
    label("EX-04", (3.0, fy - 0.61, ROOF_Z + 0.55), (0, -1, 0), (0, 0, 1), 0.9, wk.INK_DARK)
    # scout cradles
    for sx in (-1, 1):
        cradle(sx * BAY_X)


def cradle(x):
    for sx in (-1, 1):
        H.box(V((x + sx * 3.7, BERTH_Y - 2.0, DECK_Z + 0.02)), (0.3, 16.0, 0.05), "hazard",
              bevel=0.0)
    H.box(V((x, BERTH_Y - 6.5, DECK_Z + 0.02)), (0.25, 6.0, 0.05), "hull", bevel=0.0)
    H.box(V((x, BERTH_Y, DECK_Z + 0.02)), (3.0, 0.25, 0.05), "hull", bevel=0.0)
    for dy in (-1.8, 2.0):
        H.box(V((x, BERTH_Y + dy, DECK_Z + 0.1)), (3.6, 1.0, 0.3), "dark", bevel=0.0)
        for sx in (-1, 1):
            H.box(V((x + sx * 1.5, BERTH_Y + dy, -2.4)), (0.35, 0.7, 2.2), "hull2", bevel=0.1)
    # service arm with a sensor-calibration head from the outer wall
    side = 1 if x > 0 else -1
    wx = side * (WALL_IN - 0.4)
    H.box(V((wx, BERTH_Y + 1.5, 1.6)), (0.8, 1.2, 1.2), "dark", bevel=0.05)
    H.tube(V((wx, BERTH_Y + 1.5, 1.6)), V((side * (BAY_X + 3.0), BERTH_Y + 0.8, 1.4)), 0.2,
           0.2, "survey", segs=8)
    H.box(V((side * (BAY_X + 3.0), BERTH_Y + 0.8, 1.4)), (0.5, 0.5, 0.5), "mli_gold",
          bevel=0.0)
    lamp((wx - side * 0.45, BERTH_Y + 1.5, 2.35), 0.3, "green")
    SCORCH.append((x, BERTH_Y - 1.0, DECK_Z, 2.6))
    SCORCH.append((x, BERTH_Y - 6.0, DECK_Z, 2.0))


# ---------------------------------------------------------------- roof launch rail
def build_rail():
    x = RAIL_X
    r0, r1 = 6.0, -27.0
    rc, rl = (r0 + r1) / 2, r0 - r1
    zt = RAIL_Z
    # roof pedestals under the rail
    for k in range(6):
        yy = r0 - 0.5 - k * 3.8
        H.box(V((x, yy, (ROOF_TOP + zt - 0.8) / 2)), (1.6, 1.0, zt - 0.8 - ROOF_TOP + 0.1),
              "dark", bevel=0.0)
    # rail deck + tapered cantilever girder past the mouth
    H.box(V((x, rc, zt - 0.4)), (2.6, rl, 0.8), "hull2", bevel=0.04)
    H.slab([(MOUTH_Y + 2.0, ROOF_TOP), (MOUTH_Y + 2.0, zt - 0.7), (r1, zt - 0.7),
            (r1, zt - 1.3)], x - 0.7, x + 0.7, "dark", matrix=parts.SIDE)
    for sx in (-1, 1):
        H.box(V((x + sx * 0.6, rc, zt + 0.12)), (0.25, rl, 0.25), "metal", bevel=0.0)
        H.box(V((x + sx * 1.32, rc, zt - 0.25)), (0.06, rl - 1.0, 0.3), "survey", bevel=0.0)
    # mag coils the sled runs through
    rx90 = Matrix.Rotation(math.pi / 2, 4, "X")
    n_coils = 9
    for k in range(n_coils):
        yy = r1 + 1.2 + k * 3.6
        H.torus(V((x, yy, zt + 1.0)), 1.55, 0.24, "survey" if k % 2 else "hull2", segs=14,
                minor_segs=6, matrix=rx90)
        L.box(V((x, yy, zt + 2.74)), (0.3, 0.3, 0.12), "cyan", bevel=0.0)
    for k in range(8):
        lamp((x, r1 + 0.6 + k * 4.2, zt + 0.04), 0.25, "cyan")
    # launch end: hazard band, red lamps
    H.box(V((x, r1 + 0.4, zt + 0.02)), (2.6, 0.8, 0.06), "hazard", bevel=0.0)
    for sx in (-1, 1):
        lamp((x + sx * 1.1, r1 + 0.2, zt + 0.25), 0.35, "red")
    label("LAUNCH", (x, r1 + 2.6, zt + 0.03), (0, 0, 1), (0, -1, 0), 0.5, wk.INK_LIGHT, 0.7)
    # cable-stay pylon (A-frame) on the roof, stays to the cantilever and back to the roof
    py = MOUTH_Y + 7.0
    peak = V((x, py, zt + 8.5))
    for sx in (-1, 1):
        parts.strut(H, V((x + sx * 2.4, py, ROOF_TOP)), peak, 0.45, 0.45, "hull2")
    H.box(peak + V((0, 0, 0.3)), (1.0, 1.0, 0.8), "dark", bevel=0.0)
    lamp(peak + V((0, 0, 0.9)), 0.4, "red")
    for yy in (-16.0, -20.5, -25.0):
        parts.strut(H, peak, V((x, yy, zt - 0.3)), 0.1, 0.1, "dark")
    for yy in (0.5, 4.5):
        parts.strut(H, peak, V((x, yy, zt - 0.3)), 0.1, 0.1, "dark")
    # sled with a parked scout dart at the back end
    sy = 2.5
    H.box(V((x, sy, zt + 0.45)), (2.2, 3.6, 0.5), "hazard", bevel=0.05)
    H.slab([(x - 1.3, sy + 1.8), (x + 1.3, sy + 1.8), (x, sy - 3.6)], zt + 0.7, zt + 1.3,
           "hull")
    H.slab([(x - 0.5, sy + 1.6), (x + 0.5, sy + 1.6), (x, sy - 2.4)], zt + 1.3, zt + 1.6,
           "survey")
    for sx in (-1, 1):
        lamp((x + sx * 1.2, sy + 1.9, zt + 1.0), 0.25, "cyan")
    # rail control cab at the back end
    H.box(V((x, r0 + 1.0, zt + 0.8)), (3.6, 2.4, 2.4), "hull", bevel=0.06)
    L.box(V((x, r0 - 0.22, zt + 1.3)), (2.8, 0.06, 0.6), "window_cool", bevel=0.0)


# ---------------------------------------------------------------- roof sensor tiles
def build_roof_sensors():
    """Phased-array tiles and whip antennas on the -X half of the hangar roof."""
    tilt = Matrix.Rotation(math.radians(-28), 4, "Y")    # faces up and out to -X
    for row, yy in enumerate((-9.5, -4.0, 1.5)):
        for xx in (-6.0, -2.2):
            c = V((xx, yy + (0.6 if xx > -4 else 0.0), ROOF_TOP + 1.2))
            H.box(c, (3.2, 4.2, 0.3), "survey", r=tilt, bevel=0.04)
            H.box(c + tilt.to_3x3() @ V((0, 0, 0.18)), (2.8, 3.8, 0.08), "glass", r=tilt,
                  bevel=0.0)
            for gx in (-0.7, 0.7):
                for gy in (-1.2, 0.0, 1.2):
                    L.box(c + tilt.to_3x3() @ V((gx, gy, 0.24)), (0.9, 0.7, 0.03),
                          "window_cool" if (row + gx > 0) != (gy > 0) else "glass",
                          r=tilt, bevel=0.0)
            H.box(c + V((0.6, 0, -0.9)), (0.6, 2.4, 1.2), "dark", bevel=0.0)
    for xx, yy, h in ((-8.6, 5.0, 6.0), (-8.6, -12.5, 4.5), (-0.6, 5.5, 3.5)):
        H.cyl(V((xx, yy, ROOF_TOP + h / 2)), 0.1, 0.04, h, "dark", segs=5)
        lamp((xx, yy, ROOF_TOP + h + 0.15), 0.3, "red")
    lamp((-WALL_IN - 1.4, MOUTH_Y + 1.0, ROOF_TOP + 0.3), 0.4, "light")
    lamp((-WALL_IN - 1.4, BACK_Y - 1.0, ROOF_TOP + 0.3), 0.4, "light")


# ---------------------------------------------------------------- apron, pads
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
        SCORCH.append((sx * BAY_X, acy, -3.6, 4.0))
        x = sx * BAY_X
        for k in range(5):
            lamp((x, ay0 - 1.2 - k * 2.0, -3.5), 0.45, "cyan" if k % 2 else "light")
        parts.strut(H, V((x, ay1 + 0.2, -4.3)), V((x, ay1 - 8.0, -4.3)), 0.4, 0.4, "dark")
        for k in range(4):
            yy = ay1 - 1.2 - k * 2.2
            H.box(V((x, yy, -4.0)), (1.6, 0.25, 0.25), "dark", bevel=0.0)
            for dx in (-0.6, 0.0, 0.6):
                lamp((x + dx, yy, -3.8), 0.3, "cyan" if k % 2 else "light")
        lamp((x, ay1 - 8.1, -4.0), 0.45, "red")


def build_pads():
    for px, py in PADS:
        wk.landing_pad(H, L, (px, py, PAD_Z), 6.0, n_lamps=8, lamp_mat="cyan")
        sx = 1 if px > 0 else -1
        H.cyl(V((px, py, PAD_Z - 3.0)), 1.3, 0.9, 3.4, "hull2", segs=8)
        H.beam(V((px - sx * 3.0, py + 3.0, PAD_Z - 1.6)),
               V((sx * (WALL_OUT + 1.0), MOUTH_Y + 2.0, -4.6)), 1.0, 0.9, "dark")
        H.box(V((px, py, PAD_Z + 0.03)), (5.0, 0.4, 0.05), "hull", bevel=0.0)
        H.box(V((px, py, PAD_Z + 0.03)), (0.4, 5.0, 0.05), "hull", bevel=0.0)
        H.box(V((px, py, PAD_Z + 0.035)), (2.4, 2.4, 0.05), "survey", rot_z=math.pi / 4,
              bevel=0.0)
        SCORCH.append((px, py, PAD_Z, 3.6))
        wk.beacon(H, L, (px + sx * 5.2, py - 3.2, PAD_Z + 0.9), 0.4, "red")


# ---------------------------------------------------------------- tracking dish (-X)
def build_tracking_dish():
    c = DISH
    # foundation deck and the DSN control block
    H.box(V((c.x + 1.0, c.y + 1.0, -5.3)), (16.0, 18.0, 1.2), "dark", bevel=0.0)
    H.box(V((c.x + 1.0, c.y + 1.0, -4.6)), (15.0, 17.0, 0.3), "pad", bevel=0.0)
    H.box(c + V((0, 0, -1.6)), (11.0, 11.0, 6.0), "hull2", bevel=0.06)
    H.box(c + V((0, 0, 1.6)), (11.6, 11.6, 0.5), "dark", bevel=0.0)
    for n, (dx, dy) in ((V((0, -1, 0)), (0, -5.52)), (V((-1, 0, 0)), (-5.52, 0)),
                        (V((1, 0, 0)), (5.52, 0))):
        a = c + V((dx, dy, -0.2))
        t = V((-n.y, n.x, 0))
        wk.win_row(L, RNG, a - t * 4.2, a + t * 4.2, n, 6, 0.7, 0.5, "work")
        H.box(a + n * 0.03 + V((0, 0, -2.4)), (8.8 if dx == 0 else 0.06,
                                               0.06 if dx == 0 else 8.8, 0.45),
              "survey", bevel=0.0)
    label("DSN-2", c + V((-2.5, -5.53, -2.9)), (0, -1, 0), (0, 0, 1), 0.8, wk.INK_LIGHT)
    lamp(c + V((-5.3, -5.3, 2.1)), 0.4, "light")
    lamp(c + V((5.3, -5.3, 2.1)), 0.4, "light")
    # azimuth turntable + track ring
    H.cyl(c + V((0, 0, 2.2)), 5.0, 5.0, 0.8, "metal", segs=20)
    H.cyl(c + V((0, 0, 2.9)), 4.2, 3.9, 0.6, "dark", segs=16)
    # yoke: two arms rising to the elevation bearings
    pivot = c + V((0, 0, 9.4))
    ax = V((0, 0, 1)).cross(LOOK).normalized()   # elevation axis (horizontal)
    for s in (-1, 1):
        b = pivot + ax * s * 3.6
        foot = c + V((0, 0, 3.2)) + ax * s * 3.0
        parts.strut(H, foot - LOOK.xy.to_3d().normalized() * 1.2, b, 1.0, 1.4, "hull")
        parts.strut(H, foot + LOOK.xy.to_3d().normalized() * 1.2, b, 1.0, 1.4, "hull")
        q = ax.to_track_quat("Z", "Y").to_matrix().to_4x4()
        H.cyl(b, 1.1, 1.1, 1.2, "dark", segs=10, axis_rot=q)
        H.box(foot + V((0, 0, 0.2)), (2.6, 2.6, 0.8), "survey", bevel=0.05)
    # counterweight behind the bowl and the elevation drive
    cw = pivot - LOOK * 3.0
    H.box(cw, (3.0, 3.0, 2.2), "hull3", r=look_frame(cw).to_3x3().to_4x4(), bevel=0.06)
    H.box(cw - LOOK * 1.2, (3.2, 3.2, 0.3), "hazard", r=look_frame(cw).to_3x3().to_4x4(),
          bevel=0.0)
    parts.strut(H, pivot - ax * 3.0, pivot + ax * 3.0, 0.8, 0.8, "dark")
    dish(pivot + LOOK * 1.6, 9.0, 2.0, 32)
    # aircraft-style obstruction lamps on the rim (top and sides)
    m = look_frame(pivot + LOOK * 1.6)
    for a in (math.pi / 2, 0.0, math.pi):
        lamp(m @ V((math.cos(a) * 9.3, math.sin(a) * 9.3, 2.2)), 0.4, "red")
    # cable trench to the hangar wall
    H.box(V((-15.6, c.y - 2.0, -4.6)), (5.0, 2.0, 1.2), "dark", bevel=0.0)
    H.tube(V((c.x + 5.5, c.y - 2.0, -3.8)), V((-WALL_OUT, c.y - 2.0, -3.8)), 0.3, 0.3,
           "survey", segs=6)


# ---------------------------------------------------------------- back data block + array
def build_back():
    pb = V((0, BACK_Y + 4.6, 0))
    H.box(pb + V((0, 0, -0.5)), (19.0, 7.4, 8.0), "hull2", bevel=0.05)
    H.box(pb + V((0, 0, 3.7)), (17.0, 6.2, 0.6), "dark", bevel=0.0)
    for sx in (-1, 1):
        wk.win_row(L, RNG, pb + V((sx * 9.52, -2.6, 1.0)), pb + V((sx * 9.52, 2.6, 1.0)),
                   (sx, 0, 0), 4, 0.5, 0.5, "work")
    H.box(pb + V((0, 3.72, 2.0)), (14.0, 0.06, 0.6), "survey", bevel=0.0)
    label("#BAR", (0.0, pb.y + 3.73, -2.0), (0, 1, 0), (0, 0, 1), 0.8, wk.INK_DARK)
    # three-dish array on the roof
    for xx in (-6.0, 0.0, 6.0):
        b = pb + V((xx, 0.4, 4.0))
        H.cyl(b + V((0, 0, 0.8)), 1.2, 0.8, 1.6, "hull", segs=10)
        H.cyl(b + V((0, 0, 1.75)), 0.9, 0.9, 0.3, "dark", segs=10)
        piv = b + V((0, 0, 2.6))
        ax = V((0, 0, 1)).cross(LOOK).normalized()
        for s in (-1, 1):
            parts.strut(H, b + V((0, 0, 1.9)) + ax * s * 0.8, piv + ax * s * 1.1, 0.35, 0.5,
                        "hull")
        dish(piv + LOOK * 0.7, 2.7, 0.65, 18, ribs=False)
    # link port on the back face (cargo shuttle side)
    H.cyl(V((LINK_POS[0], LINK_POS[1] - 0.6, LINK_POS[2])), 2.2, 2.2, 1.2, "dark", segs=12,
          axis_rot=ALONG_Y)
    lamp((2.4, LINK_POS[1] - 0.3, LINK_POS[2] + 1.6), 0.35, "red")
    lamp((-2.4, LINK_POS[1] - 0.3, LINK_POS[2] + 1.6), 0.35, "red")
    # radiator rack off the -X end of the block
    H.box(V((-13.0, pb.y, -4.3)), (5.0, 8.0, 0.6), "dark", bevel=0.0)
    for k in range(6):
        H.box(V((-13.0, pb.y - 3.2 + k * 1.3, -1.6)), (3.4, 0.12, 5.4), "radiator", bevel=0.0)
    H.tube(V((-11.2, pb.y - 3.6, 0.9)), V((-11.2, pb.y + 3.6, 0.9)), 0.2, 0.2, "survey",
           segs=6)


# ---------------------------------------------------------------- +X services
def build_services():
    H.box(V((20.5, -1.0, -5.3)), (13.0, 28.0, 1.2), "dark", bevel=0.0)
    H.box(V((20.5, -1.0, -4.6)), (12.0, 27.0, 0.3), "pad", bevel=0.0)
    # observatory / telemetry block: slanted telemetry glazing on the front, dome on top
    t = OBS
    H.box(t + V((0, 1.2, -0.5)), (7.0, 5.6, 8.0), "hull", bevel=0.06)
    H.slab([(-4.6, -4.6), (-4.6, -0.5), (-1.6, 3.5), (-1.6, -4.6)], -3.5, 3.5, "hull2",
           matrix=Matrix.Translation(t) @ parts.SIDE)
    # telemetry wall: grid of cool lit panes on the slanted face (like a star chart)
    d = V((0, -0.6, -0.8))                        # down the slope
    nrm = V((0, -0.8, 0.6))
    a0 = t + V((0, -3.1, 1.5))
    for gx in range(6):
        for gy in range(3):
            c = a0 + V((-2.6 + gx * 1.04, 0, 0)) + d * (-1.3 + gy * 1.3) + nrm * 0.03
            lit = RNG.random()
            parts.window(L, c, nrm, -d, 0.85, 1.05,
                         "window_cool" if lit < 0.6 else ("cyan" if lit < 0.7 else None))
    dc = t + V((0, 1.4, 3.75))
    H.cyl(dc, 2.9, 2.9, 0.5, "dark", segs=16)
    H.sphere(dc + V((0, 0, 0.25)), 2.6, "mli", segs=16, rings=8, scale=(1.0, 1.0, 0.9))
    H.box(dc + V((0, 0, 1.7)), (0.8, 5.5, 1.4), "glass", rot_z=-math.pi / 4, bevel=0.0)
    H.tube(dc + V((0, 0, 1.0)), dc + V((0, 0, 1.0)) + LOOK * 3.0, 0.4, 0.5, "hull2",
           segs=10)
    lamp(dc + V((2.0, 1.4, 0.6)), 0.35, "red")
    wk.win_row(L, RNG, t + V((-3.52, -2.5, -1.0)), t + V((-3.52, 2.5, -1.0)), (-1, 0, 0), 4,
               0.5, 0.6, "hab")
    wk.win_row(L, RNG, t + V((3.52, -2.5, -1.0)), t + V((3.52, 2.5, -1.0)), (1, 0, 0), 4,
               0.5, 0.6, "hab")
    H.box(t + V((3.53, 0, -3.0)), (0.06, 6.0, 0.4), "survey", bevel=0.0)
    # walkway to the hangar wall
    H.box(V((14.6, t.y, 0.6)), (3.4, 2.0, 2.0), "hull2", bevel=0.05)
    L.box(V((14.6, t.y - 1.02, 0.6)), (2.6, 0.06, 0.5), "window", bevel=0.0)
    # scout fuel tanks with a manifold
    for i, (x, y) in enumerate(((17.5, 3.0), (21.0, 3.0), (24.5, 3.0))):
        wk.tank_v(H, (x, y, -4.5), 1.5, 6.0, "hull" if i % 2 else "hull3", "survey", segs=12)
        H.tube(V((x, y, -3.6)), V((x, y + 3.0, -3.6)), 0.2, 0.2, "metal", segs=6)
    H.tube(V((15.0, 6.0, -3.6)), V((24.5, 6.0, -3.6)), 0.25, 0.25, "metal", segs=6)
    label("FUEL", (21.0, 1.48, -1.4), (0, -1, 0), (0, 0, 1), 0.7, wk.INK_DARK)
    build_mast()
    wk.beacon(H, L, (26.2, -13.5, -3.8), 0.4, "red")
    wk.beacon(H, L, (26.2, 12.0, -3.8), 0.4, "red")


def build_mast():
    """Nav beacon mast: lattice tower, cross-arms with nav lamps, a lit ring, lantern."""
    m = MAST
    top = 26.0
    H.box(m + V((0, 0, -3.6)), (4.4, 4.4, 1.6), "hull2", bevel=0.05)
    H.box(m + V((-2.6, 0, -2.0)), (2.6, 3.6, 3.4), "hull", bevel=0.06)
    L.box(m + V((-2.6, -1.82, -1.6)), (1.8, 0.06, 0.5), "window_cool", bevel=0.0)
    label("NAV", m + V((-2.6, -1.83, -3.0)), (0, -1, 0), (0, 0, 1), 0.6, wk.INK_DARK)
    wk.lattice_mast(H, m + V((0, 0, -2.8)), top, 1.4, 0.5, 7, "survey", chord=0.32, brace=0.14)
    # stripe bands so the mast reads from above (alternating white / blue boxes on chords)
    for k, z in enumerate((3.0, 10.0, 17.0)):
        w = 1.4 + (0.5 - 1.4) * (z + 2.8) / (top + 2.8)
        H.box(m + V((0, 0, z)), (2 * w + 0.4, 2 * w + 0.4, 1.0), "hull", bevel=0.0)
    # cross-arms with port (red) / starboard (green) lamps
    for z, span in ((13.5, 4.0), (20.5, 3.0)):
        H.box(m + V((0, 0, z)), (2 * span, 0.4, 0.4), "dark", rot_z=0.4, bevel=0.0)
        d = V((math.cos(0.4), math.sin(0.4), 0))
        lamp(m + d * span + V((0, 0, 0.35)), 0.4, "green")
        lamp(m - d * span + V((0, 0, 0.35)), 0.4, "red")
    # nav ring + lantern at the top
    L.torus(m + V((0, 0, top - 1.5)), 1.6, 0.14, "cyan", segs=16, minor_segs=4)
    H.cyl(m + V((0, 0, top + 0.3)), 0.9, 0.9, 0.6, "dark", segs=10)
    L.cyl(m + V((0, 0, top + 1.2)), 0.7, 0.55, 1.2, "cyan", segs=10)
    H.cyl(m + V((0, 0, top + 2.0)), 0.8, 0.3, 0.4, "dark", segs=10)
    H.cyl(m + V((0, 0, top + 3.4)), 0.08, 0.05, 2.4, "dark", segs=5)
    lamp(m + V((0, 0, top + 4.7)), 0.45, "red")


# ---------------------------------------------------------------- assemble
def build_outpost():
    global H, L
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    H = parts.PanelPart(f"{PRE}_hull", MATS)
    L = parts.PanelPart(f"{PRE}_lights", MATS)
    for b in (build_hangar, build_rail, build_roof_sensors, build_apron, build_pads,
              build_tracking_dish, build_back, build_services):
        b()
    root = parts.make_root(PRE, size=10)
    hull = H.finish(root)
    lights = L.finish(root)
    lights.data.uv_layers.remove(lights.data.uv_layers["panel"])
    for name, pos, rz in (("dock_point", DOCK_POS, math.pi), ("spawn_point", SPAWN_POS, math.pi),
                          ("link_point", LINK_POS, 0.0)):
        parts.add_empty(name, root, pos, rot_z=rz, size=4)
    return root, hull, lights


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, hull, lights = build_outpost()
    if "--no-textures" not in argv:
        wk.texture([hull], MATS, PRE, [(p[0], p[1]) for p in PADS], scorch=SCORCH,
                   decals=DECALS, labels=LABELS, seed0=41)
    wk.stats([hull, lights])
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        wk.previews(PRE, (-2.0, -5.0, 7.0), 90, 76)


main()
