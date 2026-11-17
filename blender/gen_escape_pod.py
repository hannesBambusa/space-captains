"""Generate the escape pod .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_escape_pod.py
  Add `-- --no-preview` to skip the PNG renders, `-- --no-textures` to skip the atlas bake
  (fast shape iteration: flat colours only), `-- --extra=<dir>` for debug close-ups.

Design: "LB-07" one-person survival pod, the lifeboat a captain rides home after the ship
is gone. Hard sci-fi, built around the thrust axis, no wings. Front to back:
  collar    docking / hatch collar on the nose: armoured ring with three guide petals, a
            recessed hatch door with a yellow pull bar, two amber docking lamps.
  cell      a compact faceted (octagonal) armoured survival cell in pod white, the same
            white as the ejection cell on the mercenary interceptor, with a bold
            rescue-orange band round the shoulder. One small thick viewport sits on the
            upper front slope with its armoured shutter slid open (dark blue glass, the
            cabin instruments glowing through it).
            Yellow handholds lead along the roof edges and down the slopes to the hatch.
            Raised access plates on the flanks carry the RESCUE stencils, chevrons on the
            slopes point at the hatch, "07" on the upper chamfers. An RCS quad ring sits
            on the four chamfers. On the roof: the emergency beacon, recessed in a guard
            cup on a short mast, a whip antenna and a patch antenna. Strobes on the flanks
            and the stern, red / green nav lamps on the shoulders. Umbilical plate on the
            belly, where the pod hung in its mother ship.
  taper     four canted ejection motors on the aft taper, with their scorch fans burnt
            into the paint, then the hazard-striped break ring.
  service   a stub service section: dark octagonal thrust frame, four bare propellant
            bottles strapped to its chamfers with feed lines, one small tempered bell.
Top-down it reads as a white faceted lozenge with an orange band, a dark collar ahead and
a dark stub with two bright bottles and the bell behind.

Layout (Blender Z up, exported +Y up). Centre at origin on the play plane z=0.
Nose along Blender +Y, which the exporter turns into Godot -Z (forward).
  length ~3.8 m (bell exit y -1.9 .. collar petals y 1.92), width ~2.8 m over the flank
  strobes, height ~2.65 m (belly z -1.15 .. beacon dome z 1.5; the whip antenna tip
  reaches z 1.85).
Hierarchy: escape_pod (empty root) -> pod_hull, pod_details, beacon, engine_glow.
engine_glow: origin on the thruster exit plane (Blender y = NOZZLE_Y), plume along
Blender -Y (Godot local +Z), so scaling it on Z lengthens the glow backwards.
beacon: small emissive dome, origin at its own centre (BEACON_POS).
Textures: one 1024 worn atlas for pod_hull + pod_details (worn_kit / station_textures
bake, kinds re-scaled to pod size), saved as blender/textures/escape_pod_{albedo,mr,
normal}.jpg (+ escape_pod_decals.png, the stencil sheet), material "escape_pod_hull".
Emissive materials stay flat, named "escape_pod_*" (window, lamps, beacon, engine glow).
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
import worn_kit as wk  # noqa: E402
import station_textures as st  # noqa: E402
from parts import ALONG_Y, V, rot  # noqa: E402

PRE = "escape_pod"
OUT = os.path.join(common.ROOT, "assets", "models", "ships", "escape_pod.glb")
BLEND = os.path.join(common.ROOT, "blender", "escape_pod.blend")
ATLAS_RES = 1024

NOZZLE_Y = -1.9
NOZZLE_R = 0.36
BELL_LEN = 0.5
BEACON_POS = V((0.0, -0.06, 1.37))
BEACON_R = 0.13
W, H, C = 2.5, 2.2, 0.7           # survival cell section: width, height, corner chamfer
# Cell stations, nose to stern: (y, w, h, chamfer)
CELL = (
    (1.50, 1.20, 1.10, 0.34),     # 0 front face (the collar sits on it)
    (1.40, 1.42, 1.30, 0.41),     # 1
    (0.80, W - 0.12, H - 0.12, C - 0.035),   # 2 shoulder
    (0.70, W, H, C),              # 3
    (0.60, W, H, C),              # 4 band
    (0.34, W, H, C),              # 5
    (-0.30, W, H, C),             # 6
    (-0.40, W - 0.12, H - 0.12, C - 0.035),  # 7
    (-0.86, 1.84, 1.70, 0.52),    # 8 break ring
)
SEG_NOSE, SEG_SLOPE, SEG_BAND, SEG_MAIN, SEG_TAPER = 0, 1, 4, 5, 7
STUB = (1.3, 1.3, 0.38)           # service stub section
STUB_Y0, STUB_Y1 = -1.36, -0.94
BOTTLE_R, BOTTLE_D = 0.23, 0.63    # propellant bottle radius, axis offset on x and z
LABELS = ["RESCUE", "#CHEV", "LB-07", "#BAR", "07", "HATCH", "NO STEP", "EJECT"]
RED_INK = (0.5, 0.05, 0.03)
ORANGE_INK = (0.58, 0.13, 0.02)

MATS = {}
DECALS = []
SCORCH = []

# Worn kinds at pod size (process-local overrides): the miner's and interceptor's family
# with the plates halved, so a 3.8 m craft still shows several panels per face.
POD_WORN = {
    # lifeboat white: the interceptor's survival-cell white
    "hull": dict(big=(1.2, 0.9), plate=(0.6, 0.45),
                 tones=[(0.46, 0.46, 0.44), (0.43, 0.432, 0.425), (0.49, 0.488, 0.47),
                        (0.41, 0.415, 0.41), (0.47, 0.46, 0.44), (0.42, 0.425, 0.42)],
                 plate_var=0.06, rough=(0.55, 0.12), metal=0.05, seam_big=0.45,
                 seam_small=0.13, rivets=True, hatches=0.1, chip=(0.1, 0.1, 0.105),
                 chip_metal=0.8, chip_k=1.2, grime_k=1.0, streak_k=0.3, bleach=0.1),
    # dark grey: collar, service frame
    "hull2": dict(big=(0.8, 0.6), plate=(0.4, 0.3),
                  tones=[(0.16, 0.165, 0.17), (0.145, 0.15, 0.155), (0.175, 0.18, 0.18),
                         (0.135, 0.14, 0.145), (0.165, 0.16, 0.155), (0.15, 0.155, 0.165)],
                  plate_var=0.08, rough=(0.55, 0.12), metal=0.1, seam_big=0.45,
                  seam_small=0.18, rivets=True, hatches=0.0, chip=(0.30, 0.30, 0.31),
                  chip_metal=0.9, chip_k=0.9, grime_k=0.9, streak_k=0.25, bleach=0.1),
    # warm light grey: access plates, hatch door
    "hull3": dict(big=(0.7, 0.7), plate=(0.35, 0.35),
                  tones=[(0.34, 0.335, 0.32), (0.32, 0.32, 0.31), (0.355, 0.35, 0.335),
                         (0.31, 0.31, 0.3), (0.33, 0.325, 0.31), (0.315, 0.315, 0.31)],
                  plate_var=0.06, rough=(0.55, 0.12), metal=0.05, seam_big=0.4,
                  seam_small=0.12, rivets=True, hatches=0.0, chip=(0.1, 0.1, 0.105),
                  chip_metal=0.8, chip_k=1.2, grime_k=1.0, streak_k=0.25, bleach=0.08),
    "dark": dict(big=(0.6, 0.6), plate=(0.3, 0.3),
                 tones=[(0.045, 0.047, 0.05), (0.04, 0.042, 0.045), (0.052, 0.054, 0.056),
                        (0.036, 0.038, 0.04), (0.05, 0.048, 0.046), (0.042, 0.044, 0.048)],
                 plate_var=0.06, rough=(0.5, 0.14), metal=0.6, seam_big=0.35,
                 seam_small=0.15, rivets=False, hatches=0.0, chip=(0.26, 0.26, 0.27),
                 chip_metal=1.0, chip_k=0.8, grime_k=0.5, streak_k=0.2, bleach=0.05),
    "metal": dict(big=(0.6, 0.4), plate=(0.3, 0.4),
                  tones=[(0.30, 0.30, 0.31), (0.27, 0.27, 0.275), (0.33, 0.33, 0.335),
                         (0.25, 0.255, 0.26), (0.31, 0.305, 0.30), (0.28, 0.285, 0.29)],
                  plate_var=0.04, rough=(0.36, 0.1), metal=0.9, seam_big=0.3,
                  seam_small=0.1, rivets=False, hatches=0.0, chip=(0.36, 0.36, 0.37),
                  chip_metal=1.0, chip_k=0.0, grime_k=0.9, streak_k=0.3, bleach=0.0),
    # rescue orange
    "accent": dict(big=(0.8, 0.6), plate=(0.4, 0.3),
                   tones=[(0.64, 0.2, 0.03), (0.58, 0.18, 0.028), (0.68, 0.23, 0.04),
                          (0.55, 0.17, 0.03), (0.62, 0.21, 0.035), (0.6, 0.19, 0.03)],
                   plate_var=0.06, rough=(0.55, 0.1), metal=0.0, seam_big=0.4,
                   seam_small=0.15, rivets=False, hatches=0.0, chip=(0.13, 0.13, 0.135),
                   chip_metal=0.8, chip_k=1.4, grime_k=1.1, streak_k=0.4, bleach=0.2),
    "hazard": dict(big=(0.8, 0.8), plate=(0.4, 0.4),
                   tones=[(0.42, 0.29, 0.04), (0.40, 0.28, 0.035), (0.44, 0.31, 0.045),
                          (0.38, 0.27, 0.04), (0.43, 0.30, 0.04), (0.41, 0.285, 0.04)],
                   plate_var=0.05, rough=(0.6, 0.08), metal=0.0, seam_big=0.3,
                   seam_small=0.1, rivets=False, hatches=0.0, chip=(0.12, 0.12, 0.125),
                   chip_metal=0.7, chip_k=1.8, grime_k=1.2, streak_k=0.45, bleach=0.2,
                   stripes=0.2),
    # heat-tinted bell steel
    "temper": dict(big=(0.6, 0.5), plate=(0.3, 0.5),
                   tones=[(0.20, 0.15, 0.24), (0.26, 0.17, 0.09), (0.13, 0.15, 0.26),
                          (0.30, 0.22, 0.12), (0.17, 0.12, 0.2), (0.22, 0.2, 0.22)],
                   plate_var=0.15, rough=(0.33, 0.1), metal=0.92, seam_big=0.25,
                   seam_small=0.1, rivets=False, hatches=0.0, chip=(0.3, 0.3, 0.3),
                   chip_metal=1.0, chip_k=0.0, grime_k=0.6, streak_k=0.5, bleach=0.0),
}
st.WORN_KINDS.update(POD_WORN)
FLAT = ("glass", "window", "light", "white", "nav_r", "nav_g", "beacon")


def build_materials():
    m = common.make_material
    MATS.clear()
    MATS["hull"] = m(f"{PRE}_paint_white", (0.46, 0.46, 0.44), roughness=0.55)
    MATS["hull2"] = m(f"{PRE}_paint_dark", (0.16, 0.165, 0.17), roughness=0.55)
    MATS["hull3"] = m(f"{PRE}_paint_patch", (0.33, 0.325, 0.31), roughness=0.55)
    MATS["dark"] = m(f"{PRE}_structure", (0.045, 0.047, 0.05), roughness=0.5, metallic=0.6)
    MATS["metal"] = m(f"{PRE}_bare_metal", (0.3, 0.3, 0.31), roughness=0.36, metallic=0.9)
    MATS["accent"] = m(f"{PRE}_orange", (0.62, 0.2, 0.03), roughness=0.55)
    MATS["hazard"] = m(f"{PRE}_hazard", (0.42, 0.29, 0.04), roughness=0.6)
    MATS["temper"] = m(f"{PRE}_temper", (0.2, 0.15, 0.2), roughness=0.33, metallic=0.92)
    glow = (0.03, 0.028, 0.025)
    MATS["glass"] = m(f"{PRE}_glass", (0.008, 0.011, 0.016), roughness=0.14,
                      emission=(0.12, 0.3, 0.5), emission_strength=0.7)
    MATS["window"] = m(f"{PRE}_window", glow, roughness=0.2,
                       emission=(0.6, 0.85, 1.0), emission_strength=2.2)
    MATS["light"] = m(f"{PRE}_light_amber", glow, roughness=0.3,
                      emission=(1.0, 0.5, 0.12), emission_strength=5.0)
    MATS["white"] = m(f"{PRE}_strobe_white", glow, roughness=0.3,
                      emission=(0.9, 0.95, 1.0), emission_strength=6.0)
    MATS["nav_r"] = m(f"{PRE}_nav_red", glow, roughness=0.3,
                      emission=(1.0, 0.05, 0.03), emission_strength=7.0)
    MATS["nav_g"] = m(f"{PRE}_nav_green", glow, roughness=0.3,
                      emission=(0.1, 1.0, 0.25), emission_strength=7.0)
    MATS["beacon"] = m(f"{PRE}_beacon", (1.0, 0.45, 0.05), roughness=0.2,
                       emission=(1.0, 0.36, 0.03), emission_strength=8.0)
    MATS["glow"] = m(f"{PRE}_engine_glow", (0.8, 0.95, 1.0), roughness=0.2,
                     emission=(0.65, 0.92, 1.0), emission_strength=6.0)
    for k in FLAT:
        MATS[k].use_backface_culling = False


# ---------------------------------------------------------------- helpers
def label(text, centre, normal, up, h, colour, opacity=0.9):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity,
                           depth=0.12))


def cell_rings(grow=0.0):
    return [parts.oct_ring(y, w + 2 * grow, h + 2 * grow, c + grow * 0.59)
            for y, w, h, c in CELL]


RINGS = cell_rings()


def face(i, j, t=0.5, s=0.5):
    """Point on cell face (segment i, edge j): t along Y from ring i to i + 1, s across.
    Returns (point, outward unit normal, unit tangent towards the nose)."""
    a, b = RINGS[i][j], RINGS[i][(j + 1) % 8]
    c, d = RINGS[i + 1][j], RINGS[i + 1][(j + 1) % 8]
    p0, p1 = a.lerp(b, s), c.lerp(d, s)
    q = p0.lerp(p1, t)
    fwd = (p0 - p1).normalized()
    n = fwd.cross(b - a).normalized()
    if n.dot(V((q.x, 0, q.z))) < 0:
        n = -n
    return q, n, fwd


def frame(n, up=(0, 0, 1)):
    """4x4 rotation: X across, Y = up projected, Z = n (outward)."""
    n = V(n).normalized()
    u = V(up)
    if abs(u.dot(n)) > 0.95:
        u = V((0, 1, 0))
    u = (u - n * u.dot(n)).normalized()
    x = u.cross(n)
    return Matrix((x, u, n)).transposed().to_4x4()


def rail(p, a, b, out, posts=3, h=0.1, r=0.022, mat="hazard"):
    """Handhold: a round bar from a to b standing `h` off the skin on `posts` stand-offs."""
    a, b, out = V(a), V(b), V(out).normalized()
    parts.pipe(p, a + out * h, b + out * h, r, mat, segs=6)
    for k in range(posts):
        q = a.lerp(b, k / (posts - 1))
        p.tube(q - out * 0.01, q + out * (h + r * 0.5), r * 0.9, r * 0.9, "metal", segs=5)


def lamp(p, c, n, mat, w=0.1, ln=0.14, base="dark"):
    """Small running light: dark bezel block on the skin, emissive lens proud of it."""
    c, n = V(c), V(n).normalized()
    r = frame(n, (0, 1, 0))
    p.box(c + n * 0.02, (w + 0.05, ln + 0.05, 0.05), base, r=r, bevel=0.2)
    p.box(c + n * 0.06, (w, ln, 0.05), mat, r=r, bevel=0.0)


# ---------------------------------------------------------------- survival cell
def build_hull():
    p = parts.PanelPart("pod_hull", MATS)

    def cm(i, j):
        if i == SEG_NOSE:
            return "hull2"
        if i == SEG_BAND:
            return "accent"
        return "hull"
    p.loft(RINGS, "hull", mat_fn=cm)
    # break ring the pod left its mother ship along: hazard collar on a dark frame
    y8, w8, h8, c8 = CELL[8]
    p.loft([parts.oct_ring(y8 + 0.04, w8 + 0.06, h8 + 0.06, c8 + 0.02),
            parts.oct_ring(y8 - 0.01, w8 + 0.12, h8 + 0.12, c8 + 0.035),
            parts.oct_ring(y8 - 0.13, w8 + 0.12, h8 + 0.12, c8 + 0.035),
            parts.oct_ring(y8 - 0.17, w8 - 0.3, h8 - 0.3, c8 - 0.09)], "dark",
           mat_fn=lambda i, j: "hazard" if i == 1 else "dark")
    service(p)
    return p


def service(p):
    """Stub service section: thrust frame, four propellant bottles, one small bell."""
    w, h, c = STUB
    p.loft([parts.oct_ring(-0.98, w, h, c), parts.oct_ring(STUB_Y0, w, h, c),
            parts.oct_ring(STUB_Y0 - 0.1, 0.9, 0.9, 0.26)], "hull2",
           mat_fn=lambda i, j: "dark" if i == 1 else "hull2")
    # frame ribs round the stub
    for y in (-1.06, STUB_Y0 + 0.04):
        p.loft([parts.oct_ring(y - 0.035, w + 0.08, h + 0.08, c + 0.024),
                parts.oct_ring(y + 0.035, w + 0.08, h + 0.08, c + 0.024)], "dark")
    # propellant bottles on the four chamfers, strapped down, with feed lines
    for sx in (-1, 1):
        for sz in (-1, 1):
            x, z = sx * BOTTLE_D, sz * BOTTLE_D
            parts.capsule(p, STUB_Y0 - 0.1, -0.92, BOTTLE_R, lambda i, j: "hull", segs=12,
                          x=x, z=z, dome0=0.8, dome1=0.8, steps=3)
            for y in (-1.06, STUB_Y0 + 0.04):
                p.cyl(V((x, y, z)), BOTTLE_R + 0.012, BOTTLE_R + 0.012, 0.04, "dark", segs=12,
                      axis_rot=ALONG_Y)
            p.cyl(V((x, -1.18, z)), BOTTLE_R + 0.008, BOTTLE_R + 0.008, 0.05, "accent",
                  segs=12, axis_rot=ALONG_Y)
            tip = V((x, STUB_Y0 - 0.1, z))
            p.cyl(tip, 0.05, 0.04, 0.06, "dark", segs=6, axis_rot=ALONG_Y)
            parts.pipe(p, tip, V((sx * 0.3, STUB_Y0 - 0.14, sz * 0.3)), 0.025, "metal", segs=5)
    # thrust plate, gimbal ring, bell
    p.cyl(V((0, STUB_Y0 - 0.12, 0)), 0.34, 0.3, 0.08, "metal", segs=14, axis_rot=ALONG_Y)
    parts.bell(p, NOZZLE_Y, NOZZLE_R, BELL_LEN, "temper", "dark", segs=16)
    p.torus(V((0, NOZZLE_Y + 0.07, 0)), NOZZLE_R * 0.97, 0.022, "metal", segs=16,
            minor_segs=4, matrix=rot(rx=math.pi / 2))
    p.torus(V((0, NOZZLE_Y + 0.3, 0)), 0.27, 0.02, "dark", segs=14, minor_segs=4,
            matrix=rot(rx=math.pi / 2))
    for a in (0.8, 2.35, 3.95, 5.5):   # gimbal actuators
        d = V((math.cos(a), 0, math.sin(a)))
        parts.pipe(p, V((0, STUB_Y0 - 0.1, 0)) + d * 0.36, V((0, NOZZLE_Y + 0.3, 0)) + d * 0.28,
                   0.022, "metal", segs=5)
    SCORCH.append((0.0, -1.55, 0.0, 0.55))


# ---------------------------------------------------------------- fittings
def build_details():
    p = parts.PanelPart("pod_details", MATS)
    collar(p)
    viewport(p)
    handholds(p)
    flanks(p)
    rcs(p)
    ejection_motors(p)
    roof(p)
    belly(p)
    lights(p)
    return p


def collar(p):
    """Docking / hatch collar on the nose."""
    y0 = CELL[0][0]
    prof = [(0.0, y0 - 0.02), (0.5, y0 - 0.02), (0.5, y0 + 0.1), (0.55, y0 + 0.14),
            (0.55, y0 + 0.3), (0.51, y0 + 0.36), (0.43, y0 + 0.36), (0.43, y0 + 0.22),
            (0.0, y0 + 0.22)]
    key = {0: "dark", 1: "accent", 2: "hull2", 3: "hull2", 4: "metal", 5: "metal", 6: "dark",
           7: "hull3"}
    p.lathe(prof, 16, lambda i, j: key[j], matrix=ALONG_Y, start=math.pi / 16)
    face_y = y0 + 0.36
    for k in range(3):      # guide petals
        a = math.pi / 2 + k * 2 * math.pi / 3
        d = V((math.cos(a), 0, math.sin(a)))
        r = frame(d, (0, 1, 0))
        p.box(d * 0.57 + V((0, y0 + 0.27, 0)), (0.2, 0.3, 0.07), "dark", r=r, bevel=0.25)
        p.box(d * 0.5 + V((0, face_y + 0.03, 0)), (0.16, 0.06, 0.1), "metal", r=r, bevel=0.2)
    for k in range(3):      # capture latches between the petals
        a = -math.pi / 2 + k * 2 * math.pi / 3
        d = V((math.cos(a), 0, math.sin(a)))
        p.box(d * 0.47 + V((0, face_y + 0.01, 0)), (0.09, 0.05, 0.09), "dark",
              r=frame(d, (0, 1, 0)), bevel=0.0)
    # hatch door: rim, pull bar, pressure equalisation valve
    door_y = y0 + 0.22
    p.cyl(V((0, door_y + 0.015, 0)), 0.34, 0.36, 0.03, "hull3", segs=16, axis_rot=ALONG_Y)
    p.beam(V((-0.2, door_y + 0.07, -0.08)), V((0.2, door_y + 0.07, -0.08)), 0.035, 0.035,
           "hazard")
    for sx in (-1, 1):
        p.beam(V((sx * 0.2, door_y + 0.02, -0.08)), V((sx * 0.2, door_y + 0.08, -0.08)), 0.035,
               0.035, "metal")
    p.cyl(V((0, door_y + 0.04, 0.16)), 0.06, 0.05, 0.04, "dark", segs=8, axis_rot=ALONG_Y)
    p.cyl(V((0, door_y + 0.065, 0.16)), 0.03, 0.03, 0.02, "nav_g", segs=8, axis_rot=ALONG_Y)
    # amber docking lamps either side of the collar on the nose ring
    for sx in (-1, 1):
        q, n, _ = face(SEG_NOSE, 0 if sx > 0 else 4)
        lamp(p, q, n, "light", w=0.09, ln=0.07)


def viewport(p):
    """The one small thick viewport, on the upper front slope, with its armoured shutter."""
    q, n, fwd = face(SEG_SLOPE, 2, t=0.52)
    p.tube(q - n * 0.03, q + n * 0.075, 0.3, 0.265, "hull2", segs=14)
    p.torus(q + n * 0.075, 0.205, 0.028, "metal", segs=14, minor_segs=4,
            matrix=n.to_track_quat("Z", "Y").to_matrix().to_4x4())
    p.tube(q + n * 0.07, q + n * 0.082, 0.19, 0.19, "glass", segs=14)
    side = fwd.cross(n).normalized()
    # cabin instrument glow seen through the thick pane
    parts.quad(p, q + n * 0.086 - fwd * 0.075, n, fwd, 0.17, 0.04, "window")
    parts.quad(p, q + n * 0.086 + fwd * 0.02 + side * 0.06, n, fwd, 0.05, 0.03, "light")
    for k in range(8):      # bezel bolts
        a = math.pi / 8 + k * math.pi / 4
        d = side * math.cos(a) + fwd * math.sin(a)
        p.tube(q + d * 0.245 + n * 0.07, q + d * 0.245 + n * 0.09, 0.016, 0.016, "metal",
               segs=5)
    # shutter slid open to the rear on two rails
    r = frame(n, fwd)
    p.box(q - fwd * 0.33 + n * 0.035, (0.5, 0.2, 0.05), "hull3", r=r, bevel=0.2)
    for s in (-1, 1):
        p.box(q - fwd * 0.12 + side * s * 0.34 + n * 0.02, (0.04, 0.66, 0.04), "dark", r=r,
              bevel=0.0)


def handholds(p):
    """Yellow handholds: along the roof edges, down the slopes to the hatch, on the flanks."""
    for sx in (-1, 1):
        j = 2 if sx > 0 else 3            # top corner point of the section
        out = V((sx * 0.38, 0, 0.92)).normalized()
        a, b = RINGS[6][j].lerp(RINGS[5][j], 0.12), RINGS[6][j].lerp(RINGS[5][j], 0.95)
        rail(p, a, b, out, posts=3)
        a, b = RINGS[2][j].lerp(RINGS[1][j], 0.08), RINGS[2][j].lerp(RINGS[1][j], 0.9)
        rail(p, a, b, (sx * 0.35, 0.5, 0.8), posts=3)
        # flank rail over the access plate
        x = sx * W / 2
        rail(p, V((x, -0.24, 0.33)), V((x, 0.28, 0.33)), (sx, 0, 0), posts=2, h=0.09)


def flanks(p):
    """Raised access plates on the flanks and slopes; stencils go on them."""
    for sx in (-1, 1):
        x = sx * (W / 2 + 0.012)
        p.box(V((x, 0.02, -0.06)), (0.045, 0.56, 0.58), "hull3", bevel=0.25)
        label("RESCUE", V((x + sx * 0.03, 0.02, 0.04)), (sx, 0, 0), (0, 0, 1), 0.125, RED_INK,
              0.95)
        label("#CHEV", V((x + sx * 0.03, 0.02, -0.19)), (sx, 0, 0), (0, 0, sx), 0.1, RED_INK,
              0.9)
        # recessed pull handle on the plate (the external hatch release)
        p.box(V((x + sx * 0.025, 0.2, -0.29)), (0.03, 0.12, 0.07), "dark", bevel=0.0)
        p.box(V((x + sx * 0.04, 0.2, -0.29)), (0.02, 0.08, 0.025), "hazard", bevel=0.0)
        # hull number on the upper chamfers, "LB-07" on the lower ones
        j = 1 if sx > 0 else 3
        q, n, _ = face(SEG_MAIN, j, t=0.5)
        label("07", q + n * 0.01, n, (0, 0, 1), 0.42, ORANGE_INK, 1.0)
        j = 7 if sx > 0 else 5
        q, n, _ = face(SEG_MAIN, j, t=0.45)
        label("LB-07", q + n * 0.01, n, (0, 0, 1), 0.16, wk.INK_DARK, 0.9)
        # chevrons on the slope chamfers and slope flanks, pointing at the hatch
        j = 1 if sx > 0 else 3
        q, n, fwd = face(SEG_SLOPE, j, t=0.5)
        label("#CHEV", q + n * 0.01, n, n.cross(fwd), 0.13, RED_INK, 0.9)
        q, n, fwd = face(SEG_SLOPE, 0 if sx > 0 else 4, t=0.5)
        label("HATCH", q + n * 0.01, n, (0, 0, 1), 0.09, wk.INK_DARK, 0.9)
        # slope armour plate (lower chamfers), bolted on
        q, n, fwd = face(SEG_SLOPE, 7 if sx > 0 else 5, t=0.5)
        p.box(q + n * 0.012, (0.42, 0.4, 0.04), "hull3", r=frame(n, fwd), bevel=0.25)


def rcs(p):
    """RCS quad ring on the four chamfers of the aft taper, each on a doubler plate."""
    for j in (1, 3, 5, 7):
        q, n, fwd = face(SEG_TAPER, j, t=0.48)
        p.box(q + n * 0.012, (0.36, 0.36, 0.04), "hull2", r=frame(n, fwd), bevel=0.25)
        parts.rcs_quad(p, q + n * 0.1, n, "hull2", "metal", s=0.22)
        SCORCH.append((q.x + n.x * 0.1, q.y, q.z + n.z * 0.1, 0.32))


def ejection_motors(p):
    """Four canted solid motors on the aft taper that kicked the pod clear; burnt out,
    with their scorch fans on the paint."""
    for j in (0, 2, 4, 6):
        q, n, fwd = face(SEG_TAPER, j, t=0.5)
        d = (n * 0.75 - fwd * 0.66).normalized()      # exhaust: outward and aft
        r = frame(n, fwd)
        p.box(q + n * 0.03, (0.3, 0.22, 0.08), "hull2", r=r, bevel=0.25)
        p.tube(q + n * 0.02 + fwd * 0.03, q + d * 0.2, 0.065, 0.1, "dark", segs=8)
        p.tube(q + d * 0.16, q + d * 0.2, 0.105, 0.105, "hazard", segs=8)
        SCORCH.append((q.x, q.y + 0.08, q.z, 0.95))
    for j in (0, 4):
        q, n, _ = face(SEG_TAPER, j, t=0.2, s=0.82)
        label("EJECT", q, n, (0, 0, 1), 0.06, RED_INK, 0.9)


def roof(p):
    """Beacon mast with its guard cup, whip antenna, patch antenna, roof stencil."""
    top = H / 2
    b = BEACON_POS
    p.box(V((b.x, b.y, top + 0.03)), (0.42, 0.42, 0.07), "hull2", bevel=0.3)
    p.cyl(V((b.x, b.y, top + 0.12)), 0.07, 0.055, 0.14, "metal", segs=8)
    cup0 = b.z - 0.07
    prof = [(0.0, cup0 - 0.04), (0.15, cup0 - 0.04), (0.21, cup0), (0.21, cup0 + 0.1),
            (0.175, cup0 + 0.1), (0.175, cup0 + 0.02), (0.0, cup0 + 0.02)]
    key = {0: "dark", 1: "hull2", 2: "accent", 3: "metal", 4: "dark", 5: "dark"}
    p.lathe(prof, 12, lambda i, j: key[j], matrix=Matrix.Translation((b.x, b.y, 0)))
    for k in range(3):      # guard posts over the cup rim
        a = math.pi / 6 + k * 2 * math.pi / 3
        d = V((math.cos(a), math.sin(a), 0))
        p.tube(V((b.x, b.y, cup0 + 0.08)) + d * 0.195, V((b.x, b.y, b.z + 0.1)) + d * 0.195,
               0.018, 0.018, "metal", segs=5)
    # whip antenna and a flat patch antenna ahead of the beacon
    base = V((0.4, -0.2, top))
    p.cyl(base + V((0, 0, 0.03)), 0.05, 0.04, 0.06, "dark", segs=8)
    p.tube(base, base + V((0.04, -0.12, 0.75)), 0.014, 0.008, "metal", segs=5)
    p.box(V((-0.38, -0.06, top + 0.02)), (0.24, 0.24, 0.04), "hull3", bevel=0.25)
    p.box(V((-0.38, -0.06, top + 0.045)), (0.15, 0.15, 0.02), "dark", bevel=0.0)
    label("NO STEP", V((0.38, 0.14, top)), (0, 0, 1), (-1, 0, 0), 0.065, wk.INK_DARK, 0.85)


def belly(p):
    """Umbilical plate where the pod hung in its mother ship, and two rub strakes."""
    bot = -H / 2
    p.box(V((0, -0.1, bot - 0.02)), (0.6, 0.5, 0.06), "hull2", bevel=0.25)
    for x, y in ((-0.16, -0.2), (0.16, -0.2), (0, 0.02)):
        p.cyl(V((x, y, bot - 0.065)), 0.07, 0.06, 0.05, "metal", segs=8)
        p.cyl(V((x, y, bot - 0.09)), 0.035, 0.035, 0.02, "dark", segs=8)
    for sx in (-1, 1):
        p.box(V((sx * 0.42, -0.02, bot - 0.02)), (0.08, 0.9, 0.05), "dark", bevel=0.25)


def lights(p):
    """Strobes on the flanks and the stern, nav lamps on the shoulders."""
    for sx in (-1, 1):
        x = sx * W / 2
        # white strobe on a stub pylon mid flank (the widest point of the pod)
        p.box(V((x + sx * 0.05, 0.47, 0.0)), (0.1, 0.14, 0.14), "dark", bevel=0.2)
        p.box(V((x + sx * 0.125, 0.47, 0.0)), (0.05, 0.1, 0.1), "white", bevel=0.0)
        # nav lamp on the upper chamfer shoulder: red to port, green to starboard
        q, n, _ = face(SEG_BAND, 1 if sx > 0 else 3, t=0.5, s=0.3)
        lamp(p, q, n, "nav_g" if sx > 0 else "nav_r", w=0.08, ln=0.1)
    # stern strobe on top of the service stub, belly strobe under the cell
    p.box(V((0, -1.16, STUB[1] / 2 + 0.03)), (0.12, 0.12, 0.06), "dark", bevel=0.2)
    p.box(V((0, -1.16, STUB[1] / 2 + 0.07)), (0.08, 0.08, 0.04), "white", bevel=0.0)
    p.box(V((0, 0.42, -H / 2 - 0.03)), (0.1, 0.1, 0.05), "white", bevel=0.0)


# ---------------------------------------------------------------- beacon, glow
def build_beacon():
    """Emissive dome, built round its own centre (the object sits at BEACON_POS)."""
    p = parts.Part("beacon", MATS)
    r = BEACON_R
    prof = [(r * math.sin(math.pi / 2 * k / 4), r * math.cos(math.pi / 2 * k / 4))
            for k in range(5)] + [(r, -0.05), (0.0, -0.05)]
    p.lathe(prof, 12, lambda i, j: "beacon")
    return p


def build_glow():
    p = parts.Part("engine_glow", MATS)
    parts.exhaust_glow(p, NOZZLE_R * 0.85, 0.45, "glow", segs=14)
    return p


def build_pod():
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    root = parts.make_root("escape_pod", size=2)
    hull = build_hull().finish(root)
    details = build_details().finish(root)
    beacon = build_beacon().finish(root, sharp_deg=60)
    glow = build_glow().finish(root)
    beacon.location = tuple(BEACON_POS)
    glow.location = (0, NOZZLE_Y, 0)
    return root, hull, details, beacon, glow


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, hull, details, beacon, glow = build_pod()
    bpy.context.view_layer.update()
    if "--no-textures" not in argv:
        for o in (beacon, glow):
            o.hide_render = True
        wk.texture([hull, details], MATS, PRE, [(0.0, 0.0)], scorch=SCORCH, decals=DECALS,
                   labels=LABELS, seed0=107, res=ATLAS_RES, ao_far=1.5, edge_r=0.06)
        for o in (beacon, glow):
            o.hide_render = False
    else:
        for o in (hull, details):
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    wk.stats([hull, details, beacon, glow])
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews("escape_pod", 5.0, target=(0, 0.0, 0.15))
    extra = [a.split("=", 1)[1] for a in argv if a.startswith("--extra=")]
    if extra:
        extra_views(extra[0])


def extra_views(out_dir):
    """Debug renders into out_dir; not part of the previews."""
    if bpy.context.scene.camera is None:
        parts.ship_previews("escape_pod", 5.0, target=(0, 0.0, 0.15))
    scene = bpy.context.scene
    cam = scene.camera
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1200
    views = (("close", (-6, 9, 6), (0, 0.6, 0.2), 4.2),
             ("rear", (-6, -9, 5), (0, -0.6, 0.1), 4.6),
             ("side", (-20, 0, 0), (0, 0, 0.15), 5.2),
             ("front", (4, 12, 3), (0, 0.8, 0.1), 4.2),
             ("belly", (-6, 5, -8), (0, 0, -0.2), 5.2),
             ("rts", (-3, -8, 20), (0, 0, 0), 14.0))
    for name, loc, tgt, ortho in views:
        cam.location = loc
        cam.rotation_euler = (V(tgt) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        cam.data.ortho_scale = ortho
        common.render(os.path.join(out_dir, f"pod_{name}.png"))


main()
