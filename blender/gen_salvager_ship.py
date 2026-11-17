"""Generate the salvager ship .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_salvager_ship.py
  Add `-- --no-preview` to skip the PNG renders, `-- --no-textures` to skip the atlas bake
  (fast shape iteration: flat colours only), `-- --extra=<dir>` for debug close-ups.

Design: "Ragpicker" class Belter salvage tug, the work boat a Salvage Yard hires to cut up
wrecks and haul the scrap home. Built around the thrust axis, every section has a job,
front to back:
  tools     a heavy open tool frame bolted across the bow carries two articulated
            manipulator arms (yaw turret, upper arm, elbow drum, forearm, roll wrist,
            three-finger grapple claw; hydraulic rams, hoses, a work lamp on each forearm)
            and, low on the centre line, the plasma cutter boom: shoulder, knuckle, gas
            bottles, a shielded cutter head behind an octagonal spall shield with a
            viewing port. The glowing tip is tool_point (y = TOOL_Y, matches SalvagerShip
            nose_offset 7.6). Work floodlights on the frame, the cupola brow and the arms.
  crew can  armoured chamfered pressure hull in worn safety orange: a forward work cupola
            overhangs the tool frame so the crew looks down on the cut through slit ports
            behind armour bars; side slit ports, port airlock with handholds, bow hatch,
            docking collar, antenna cluster, flush radiators on the upper chamfers, RCS
            quads on the four corners.
  cradle    an open truss cradle on the keel truss: four U ribs, rails, cross bracing,
            hinged clamps with hazard pads, two winches a side. A torn hull section of
            somebody else's ship (navy paint, pale stripe, broken frames, a deck
            fragment, dangling pipes) sits in it under two ratchet straps.
  stern     two mismatched propellant tanks in strap saddles, helium spheres and exposed
            plumbing between them, a reactor / engineering block with flush radiators and
            RCS quads, a gimballed thrust mount and one big drive bell.
Worn safety orange and grey with hazard-yellow tooling, hull number SV-07, stencils.

Layout (Blender Z up, exported +Y up). Ship centre at origin on the play plane z=0.
The nose points along Blender +Y, which the exporter turns into Godot -Z (forward).
  length 15.0 m (bell exit y -7.4 .. torch tip y 7.6), width ~5.0 m over the arm elbows
  and the port catwalk (cradle 4.3 m), height ~4.2 m (antenna whip z ~2.8, cupola roof
  z 2.2 .. belly z ~-1.4).
  bell y -7.4..-5.95, engineering -6.2..-5.2, tanks -5.35..-3.65, cradle -3.55..0.8,
  crew can 0.95..3.98, tool frame 3.95..4.55, arms and cutter to 7.6.
Hierarchy: salvager (empty root) -> salvager_hull, salvager_rig, salvager_scrap,
  engine_glow, tool_point (empty).
salvager_hull is the crew can, keel, tanks, engineering and bell; salvager_rig the tool
frame, arms, cutter boom and cradle; salvager_scrap the wreck section and its straps (one
node, so the cargo can be hidden as a whole).
engine_glow has its origin on the bell exit plane (Blender y = NOZZLE_Y) and its plume
extends along Godot local +Z, so scaling it on Z lengthens the glow backwards.
tool_point is unrotated, so its Godot -Z points forward out of the torch.
Textures: one 2048 worn atlas shared by hull, rig and scrap (worn_kit / station_textures
bake, kinds re-scaled to ship size), saved as blender/textures/salvager_{albedo,mr,
normal}.jpg (+ salvager_decals.png, the stencil sheet; the three maps are re-saved at a
lower JPEG quality to keep the .glb near 5 MB), material "salvager_hull". Emissive
materials (lamps, windows, torch, engine glow) stay flat, named "salvager_*".
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
import worn_kit as wk  # noqa: E402
import station_textures as st  # noqa: E402
from parts import ALONG_X, ALONG_Y, V, oct_ring, rot  # noqa: E402

PRE = "salvager"
OUT = os.path.join(common.ROOT, "assets", "models", "ships", "salvager.glb")
BLEND = os.path.join(common.ROOT, "blender", "salvager.blend")

TOOL_Y = 7.6
NOZZLE_Y = -7.4
BELL_R = 1.12
BELL_LEN = 1.45
CAN_Z = 0.25                     # crew can centre height
FRAME_Y = 4.25                   # tool frame centre
KEEL_Z = -0.75                   # keel truss centre height
CRADLE_Y0, CRADLE_Y1 = -3.55, 0.8
CRADLE_X = 1.98                  # cradle post centre line
RIBS = (-3.4, -2.05, -0.7, 0.65)
RAIL_Z = 1.3
STRAPS = (-2.72, -0.05)          # winch / strap stations
WRECK_Y = (CRADLE_Y0 + CRADLE_Y1) / 2
WRECK_R = 1.74                   # torn hull section: arc radius, axis height
WRECK_Z = -0.2
TANK_X, TANK_Z, TANK_R = 0.98, 0.1, 0.72
TANK_Y0, TANK_Y1 = -5.35, -3.65
LABELS = ["SV-07", "07", "#CHEV", "#BAR", "NO STEP", "KEEP CLEAR", "CUTTER", "SALVAGE",
          "LOCK 1", "TY-31", "LIFT", "H2"]
INK_WHITE = (0.62, 0.62, 0.58)

# Crew can stations: (y, w, h, chamfer, z centre)
CAN = (
    (0.95, 1.7, 1.6, 0.4, 0.2),
    (1.25, 2.6, 2.4, 0.62, CAN_Z),
    (3.75, 2.6, 2.4, 0.62, CAN_Z),
    (3.98, 2.2, 1.9, 0.5, 0.2),
)
CUPOLA = (
    (2.3, 1.2, 0.3, 0.1, 1.5),
    (2.6, 1.7, 0.86, 0.28, 1.78),
    (3.8, 1.7, 0.86, 0.28, 1.78),
    (4.55, 1.4, 0.44, 0.16, 1.6),
)
ENGINE = (
    (-5.15, 2.0, 1.9, 0.5, 0.0),
    (-5.4, 2.5, 2.3, 0.62, 0.0),
    (-6.0, 2.5, 2.3, 0.62, 0.0),
    (-6.2, 1.9, 1.7, 0.45, 0.0),
)

MATS = {}
DECALS = []
SCORCH = []
RNG = random.Random(4417)

# Worn kinds at ship scale (process-local overrides, same scale as the miner hauler).
# "hull" is the salvager's safety orange so the stencils (which only land on the hull /
# dark / metal / pad kinds) can sit on it; "pad" is reused for the wreck's navy paint for
# the same reason.
SHIP_WORN = {
    "hull": dict(big=(1.4, 1.0), plate=(0.7, 0.5),
                 tones=[(0.60, 0.20, 0.035), (0.55, 0.185, 0.03), (0.64, 0.23, 0.045),
                        (0.50, 0.17, 0.035), (0.58, 0.215, 0.04), (0.53, 0.2, 0.05)],
                 plate_var=0.08, rough=(0.56, 0.12), metal=0.0, seam_big=0.45,
                 seam_small=0.18, rivets=True, hatches=0.14, chip=(0.17, 0.165, 0.16),
                 chip_metal=0.8, chip_k=0.95, grime_k=1.1, streak_k=0.4, bleach=0.22),
    "hull2": dict(big=(1.4, 1.0), plate=(0.7, 0.5),
                  tones=[(0.16, 0.165, 0.17), (0.145, 0.15, 0.155), (0.175, 0.18, 0.18),
                         (0.135, 0.14, 0.145), (0.165, 0.16, 0.155), (0.15, 0.155, 0.165)],
                  plate_var=0.08, rough=(0.55, 0.12), metal=0.1, seam_big=0.45,
                  seam_small=0.18, rivets=True, hatches=0.12, chip=(0.30, 0.30, 0.31),
                  chip_metal=0.9, chip_k=0.9, grime_k=0.9, streak_k=0.25, bleach=0.1),
    "hull3": dict(big=(1.2, 1.2), plate=(0.6, 0.6),
                  tones=[(0.36, 0.36, 0.345), (0.33, 0.335, 0.33), (0.39, 0.385, 0.37),
                         (0.31, 0.315, 0.31), (0.35, 0.345, 0.33), (0.335, 0.335, 0.33)],
                  plate_var=0.07, rough=(0.55, 0.12), metal=0.05, seam_big=0.4,
                  seam_small=0.12, rivets=True, hatches=0.14, chip=(0.1, 0.1, 0.105),
                  chip_metal=0.8, chip_k=1.3, grime_k=1.05, streak_k=0.3, bleach=0.08),
    "dark": dict(big=(1.0, 1.0), plate=(0.5, 0.5),
                 tones=[(0.045, 0.047, 0.05), (0.04, 0.042, 0.045), (0.052, 0.054, 0.056),
                        (0.036, 0.038, 0.04), (0.05, 0.048, 0.046), (0.042, 0.044, 0.048)],
                 plate_var=0.06, rough=(0.5, 0.14), metal=0.6, seam_big=0.35,
                 seam_small=0.15, rivets=False, hatches=0.0, chip=(0.26, 0.26, 0.27),
                 chip_metal=1.0, chip_k=0.8, grime_k=0.5, streak_k=0.2, bleach=0.05),
    "metal": dict(big=(1.0, 0.5), plate=(0.5, 0.5),
                  tones=[(0.30, 0.30, 0.31), (0.27, 0.27, 0.275), (0.33, 0.33, 0.335),
                         (0.25, 0.255, 0.26), (0.31, 0.305, 0.30), (0.28, 0.285, 0.29)],
                  plate_var=0.04, rough=(0.36, 0.1), metal=0.9, seam_big=0.3,
                  seam_small=0.1, rivets=False, hatches=0.0, chip=(0.36, 0.36, 0.37),
                  chip_metal=1.0, chip_k=0.0, grime_k=0.9, streak_k=0.3, bleach=0.0),
    # hazard-yellow tooling paint (plain) and the striped hazard trim
    "accent": dict(big=(1.0, 0.6), plate=(0.5, 0.3),
                   tones=[(0.50, 0.33, 0.035), (0.46, 0.305, 0.03), (0.53, 0.36, 0.045),
                          (0.43, 0.29, 0.035), (0.49, 0.335, 0.04), (0.47, 0.31, 0.04)],
                   plate_var=0.05, rough=(0.55, 0.1), metal=0.0, seam_big=0.3,
                   seam_small=0.12, rivets=False, hatches=0.0, chip=(0.19, 0.185, 0.18),
                   chip_metal=0.85, chip_k=1.0, grime_k=1.1, streak_k=0.45, bleach=0.15),
    "hazard": dict(big=(1.2, 1.2), plate=(0.6, 0.6),
                   tones=[(0.46, 0.31, 0.04), (0.43, 0.295, 0.035), (0.48, 0.33, 0.045),
                          (0.41, 0.28, 0.04), (0.46, 0.32, 0.04), (0.44, 0.3, 0.04)],
                   plate_var=0.05, rough=(0.6, 0.08), metal=0.0, seam_big=0.3,
                   seam_small=0.1, rivets=False, hatches=0.0, chip=(0.12, 0.12, 0.125),
                   chip_metal=0.7, chip_k=1.8, grime_k=1.2, streak_k=0.45, bleach=0.2,
                   stripes=0.3),
    "temper": dict(big=(0.6, 0.5), plate=(0.3, 0.5),
                   tones=[(0.20, 0.15, 0.24), (0.26, 0.17, 0.09), (0.13, 0.15, 0.26),
                          (0.30, 0.22, 0.12), (0.17, 0.12, 0.2), (0.22, 0.2, 0.22)],
                   plate_var=0.15, rough=(0.33, 0.1), metal=0.92, seam_big=0.25,
                   seam_small=0.1, rivets=False, hatches=0.0, chip=(0.3, 0.3, 0.3),
                   chip_metal=1.0, chip_k=0.0, grime_k=0.6, streak_k=0.5, bleach=0.0),
    "radiator": dict(big=(1.6, 0.4), plate=(1.6, 0.2),
                     tones=[(0.36, 0.365, 0.37), (0.34, 0.345, 0.35), (0.38, 0.38, 0.385),
                            (0.33, 0.335, 0.34), (0.37, 0.37, 0.37), (0.35, 0.355, 0.36)],
                     plate_var=0.03, rough=(0.42, 0.08), metal=0.2, seam_big=0.5,
                     seam_small=0.3, rivets=False, hatches=0.0, chip=(0.2, 0.2, 0.2),
                     chip_metal=0.6, chip_k=0.3, grime_k=0.6, streak_k=0.3, bleach=0.0),
    # the wreck: somebody else's navy hull paint, a pale stripe, bare burnt structure
    "pad": dict(big=(1.4, 1.0), plate=(0.7, 0.5),
                tones=[(0.05, 0.085, 0.125), (0.045, 0.075, 0.11), (0.06, 0.095, 0.135),
                       (0.04, 0.07, 0.10), (0.055, 0.08, 0.115), (0.05, 0.09, 0.12)],
                plate_var=0.12, rough=(0.62, 0.14), metal=0.1, seam_big=0.45,
                seam_small=0.2, rivets=True, hatches=0.0, chip=(0.2, 0.19, 0.185),
                chip_metal=0.85, chip_k=1.4, grime_k=1.3, streak_k=0.5, bleach=0.2),
    "stripe": dict(big=(1.4, 1.0), plate=(0.7, 0.5),
                   tones=[(0.42, 0.41, 0.38), (0.39, 0.385, 0.36), (0.44, 0.43, 0.40),
                          (0.37, 0.365, 0.345), (0.41, 0.40, 0.375), (0.40, 0.39, 0.36)],
                   plate_var=0.1, rough=(0.62, 0.14), metal=0.05, seam_big=0.45,
                   seam_small=0.2, rivets=True, hatches=0.0, chip=(0.2, 0.19, 0.185),
                   chip_metal=0.85, chip_k=1.4, grime_k=1.3, streak_k=0.5, bleach=0.15),
    "rust": dict(big=(0.8, 0.6), plate=(0.4, 0.3),
                 tones=[(0.16, 0.07, 0.03), (0.12, 0.055, 0.025), (0.19, 0.09, 0.04),
                        (0.10, 0.06, 0.04), (0.17, 0.08, 0.035), (0.13, 0.07, 0.045)],
                 plate_var=0.12, rough=(0.82, 0.12), metal=0.25, seam_big=0.3,
                 seam_small=0.15, rivets=False, hatches=0.0, chip=(0.22, 0.2, 0.19),
                 chip_metal=0.8, chip_k=1.2, grime_k=1.2, streak_k=0.5, bleach=0.15),
    "scrap": dict(big=(0.8, 0.6), plate=(0.4, 0.3),
                  tones=[(0.13, 0.125, 0.12), (0.09, 0.09, 0.095), (0.17, 0.16, 0.15),
                         (0.07, 0.075, 0.085), (0.15, 0.11, 0.08), (0.11, 0.11, 0.11)],
                  plate_var=0.2, rough=(0.7, 0.2), metal=0.45, seam_big=0.4,
                  seam_small=0.2, rivets=False, hatches=0.0, chip=(0.28, 0.27, 0.27),
                  chip_metal=0.9, chip_k=1.6, grime_k=1.3, streak_k=0.5, bleach=0.1),
}
st.WORN_KINDS.update(SHIP_WORN)


def build_materials():
    m = common.make_material
    MATS.clear()
    MATS["hull"] = m(f"{PRE}_paint_orange", (0.58, 0.2, 0.035), roughness=0.56)
    MATS["hull2"] = m(f"{PRE}_paint_dark", (0.16, 0.165, 0.17), roughness=0.55)
    MATS["hull3"] = m(f"{PRE}_paint_grey", (0.36, 0.36, 0.345), roughness=0.55)
    MATS["dark"] = m(f"{PRE}_structure", (0.045, 0.047, 0.05), roughness=0.5, metallic=0.6)
    MATS["metal"] = m(f"{PRE}_bare_metal", (0.3, 0.3, 0.31), roughness=0.36, metallic=0.9)
    MATS["accent"] = m(f"{PRE}_tool_yellow", (0.5, 0.33, 0.035), roughness=0.55)
    MATS["hazard"] = m(f"{PRE}_hazard", (0.46, 0.31, 0.04), roughness=0.6)
    MATS["temper"] = m(f"{PRE}_temper", (0.2, 0.15, 0.2), roughness=0.33, metallic=0.92)
    MATS["radiator"] = m(f"{PRE}_radiator", (0.36, 0.365, 0.37), roughness=0.42,
                         metallic=0.2)
    MATS["pad"] = m(f"{PRE}_wreck_navy", (0.05, 0.085, 0.125), roughness=0.62)
    MATS["stripe"] = m(f"{PRE}_wreck_stripe", (0.42, 0.41, 0.38), roughness=0.62)
    MATS["rust"] = m(f"{PRE}_wreck_frame", (0.15, 0.07, 0.03), roughness=0.8, metallic=0.25)
    MATS["scrap"] = m(f"{PRE}_wreck_bare", (0.13, 0.125, 0.12), roughness=0.7, metallic=0.45)
    glow = (0.03, 0.028, 0.025)
    MATS["glass"] = m(f"{PRE}_canopy", (0.008, 0.011, 0.016), roughness=0.14,
                      emission=(0.16, 0.3, 0.4), emission_strength=0.15)
    MATS["window"] = m(f"{PRE}_window_warm", glow, roughness=0.25,
                       emission=(1.0, 0.62, 0.3), emission_strength=2.2)
    MATS["light"] = m(f"{PRE}_light_amber", glow, roughness=0.3,
                      emission=(1.0, 0.5, 0.12), emission_strength=5.0)
    MATS["white"] = m(f"{PRE}_light_white", glow, roughness=0.3,
                      emission=(0.9, 0.95, 1.0), emission_strength=6.0)
    MATS["nav_r"] = m(f"{PRE}_nav_red", glow, roughness=0.3,
                      emission=(1.0, 0.05, 0.03), emission_strength=7.0)
    MATS["nav_g"] = m(f"{PRE}_nav_green", glow, roughness=0.3,
                      emission=(0.1, 1.0, 0.25), emission_strength=7.0)
    MATS["torch"] = m(f"{PRE}_torch_glow", (0.6, 0.85, 1.0), roughness=0.2,
                      emission=(0.55, 0.85, 1.0), emission_strength=9.0)
    MATS["glow"] = m(f"{PRE}_engine_glow", (0.8, 0.95, 1.0), roughness=0.2,
                     emission=(0.65, 0.92, 1.0), emission_strength=6.0)
    for k in ("glass", "window", "light", "white", "nav_r", "nav_g", "torch"):
        MATS[k].use_backface_culling = False


# ---------------------------------------------------------------- small shapes
def label(text, centre, normal, up, h, colour, opacity=0.85):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity))


def rings_of(table, x0=0.0):
    return [oct_ring(y, w, h, c, x0=x0, z0=z) for y, w, h, c, z in table]


def dir_rot(d, up=(0, 0, 1)):
    """4x4 rotation: X along d, Z = up made square to it."""
    x = V(d).normalized()
    u = V(up)
    if abs(x.dot(u)) > 0.97:
        u = V((1, 0, 0))
    z = (u - x * u.dot(x)).normalized()
    y = z.cross(x)
    return Matrix((x, y, z)).transposed().to_4x4()


def face_rot(n, along):
    """4x4 rotation: X = along (made square to n), Z = n (outward)."""
    n = V(n).normalized()
    a = V(along)
    a = (a - n * a.dot(n)).normalized()
    return Matrix((a, n.cross(a), n)).transposed().to_4x4()


def axis_rot(axis):
    return V(axis).normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()


def link(p, a, b, w, h, mat, bevel=0.2, up=(0, 0, 1), ext=0.0):
    """Chamfered box member from a to b (w across, h along `up`)."""
    a, b = V(a), V(b)
    d = b - a
    p.box((a + b) / 2, (d.length + ext, w, h), mat, r=dir_rot(d, up), bevel=bevel)


def drum(p, c, axis, r, w, mat="dark", cap="metal", segs=14):
    """Joint drum: a cylinder about `axis` with a raised cap either end."""
    ax = V(axis).normalized()
    q = axis_rot(ax)
    p.cyl(V(c), r, r, w, mat, segs=segs, axis_rot=q)
    for s in (-1, 1):
        p.cyl(V(c) + ax * s * (w / 2 + 0.015), r * 0.62, r * 0.62, 0.05, cap, segs=segs,
              axis_rot=q)
        p.cyl(V(c) + ax * s * (w / 2 + 0.05), r * 0.22, r * 0.22, 0.05, "dark", segs=6,
              axis_rot=q)


def ram(p, a, b, r=0.07, body="hull2"):
    """Hydraulic actuator: cylinder body, gland, polished rod, a clevis either end."""
    a, b = V(a), V(b)
    d = (b - a).normalized()
    m = a.lerp(b, 0.56)
    p.tube(a, m, r, r, body, segs=8)
    p.tube(m - d * 0.05, m + d * 0.03, r * 1.3, r * 1.3, "dark", segs=8)
    p.tube(m, b, r * 0.5, r * 0.5, "metal", segs=6)
    for q in (a, b):
        p.box(q, (r * 2.6, r * 2.6, r * 2.6), "dark", r=dir_rot(d), bevel=0.2)


def hose(p, a, b, sag, r=0.035, n=6, mat="dark", sag_dir=(0, 0, -1)):
    """Sagging hose as a chain of open pipes."""
    a, b = V(a), V(b)
    sd = V(sag_dir)
    pts = [a.lerp(b, k / n) + sd * sag * 4 * (k / n) * (1 - k / n) for k in range(n + 1)]
    for q0, q1 in zip(pts, pts[1:]):
        parts.pipe(p, q0, q1, r, mat, segs=5)


def rail(p, a, b, n, mat="accent", t=0.035, off=0.09):
    """Handhold: a bar on two standoffs, `off` proud of the face with normal n."""
    a, b, n = V(a), V(b), V(n).normalized()
    parts.strut(p, a + n * off, b + n * off, t, t, mat, up=n)
    for q in (a, b):
        parts.strut(p, q, q + n * (off + t / 2), t, t, "metal",
                    up=(b - a).normalized())


def lamp(p, c, n, up, w=0.26, h=0.18, mat="white", depth=0.16):
    """Work lamp: dark housing with a hood, lit lens on the face looking along n."""
    c, n = V(c), V(n).normalized()
    r = face_rot(n, V(up).cross(n))
    p.box(c - n * depth / 2, (w + 0.08, h + 0.08, depth), "dark", r=r, bevel=0.15)
    parts.quad(p, c + n * 0.012, n, up, w, h, mat)


def slit(p, c, n, w, h):
    """Armoured slit port: raised dark frame, glass, a thin lit pane."""
    c, n = V(c), V(n).normalized()
    r = face_rot(n, (0, 1, 0))
    p.box(c, (w + 0.12, h + 0.12, 0.05), "hull2", r=r, bevel=0.2)
    parts.quad(p, c + n * 0.03, n, (0, 0, 1), w, h, "glass")
    parts.quad(p, c + n * 0.034, n, (0, 0, 1), w * 0.86, h * 0.5, "window")


def flush_radiator(p, c, n, along, length, height, ribs=6, t=0.05):
    """Flat radiator panel on a hull face (normal n), coolant ribs across `along`."""
    c, n = V(c), V(n).normalized()
    r = face_rot(n, along)
    a = r.to_3x3() @ V((1, 0, 0))
    u = r.to_3x3() @ V((0, 1, 0))
    p.box(c + n * t / 2, (length, height, t), "radiator", r=r, bevel=0.0)
    for k in range(ribs):
        s = -length / 2 + length * (k + 0.5) / ribs
        p.box(c + a * s + n * t, (0.045, height * 0.94, t * 0.9), "metal", r=r, bevel=0.0)
    for s in (-1, 1):
        p.box(c + u * s * (height / 2 + 0.02) + n * t * 0.6, (length + 0.08, 0.06, t * 1.6),
              "dark", r=r, bevel=0.0)


def bolts(p, a, b, n, nrm, s=0.06, mat="metal"):
    a, b, nrm = V(a), V(b), V(nrm).normalized()
    for k in range(n):
        p.box(a.lerp(b, (k + 0.5) / n) + nrm * s * 0.3, (s, s, s), mat, r=face_rot(nrm, b - a),
              bevel=0.0)


# ---------------------------------------------------------------- hull
def build_hull():
    p = parts.PanelPart("salvager_hull", MATS)
    crew_can(p)
    cupola(p)
    can_fittings(p)
    keel(p)
    tanks(p)
    engineering(p)
    drive(p)
    rcs(p)
    return p


def crew_can(p):
    """Armoured pressure can: chamfered slab hull in safety orange, grey belly."""
    def cm(i, j):
        if i == 0:
            return "hull2"
        if i == 2:
            return "dark"
        if j in (5, 6, 7):
            return "hull2"
        return "hull"
    p.loft(rings_of(CAN), "hull2", mat_fn=cm)
    # collar ring at the aft bulkhead, grey patch band (a replaced hull ring)
    p.loft([oct_ring(1.3, 2.66, 2.46, 0.64, z0=CAN_Z), oct_ring(1.52, 2.66, 2.46, 0.64,
                                                                z0=CAN_Z)], "hull2", cap=False)
    p.loft([oct_ring(2.42, 2.63, 2.43, 0.63, z0=CAN_Z), oct_ring(2.52, 2.63, 2.43, 0.63,
                                                                 z0=CAN_Z)], "dark", cap=False)
    # slab armour on the flanks: starboard carries the hull number, port the airlock
    x = 1.3
    p.box(V((x + 0.03, 3.1, CAN_Z)), (0.08, 1.0, 1.02), "hull", bevel=0.25)
    p.box(V((x + 0.03, 1.98, CAN_Z)), (0.08, 0.78, 1.02), "hull3", bevel=0.25)
    label("SV-07", V((x + 0.07, 3.1, CAN_Z + 0.1)), (1, 0, 0), (0, 0, 1), 0.3, wk.INK_DARK, 0.92)
    label("SALVAGE", V((x + 0.07, 3.1, CAN_Z - 0.28)), (1, 0, 0), (0, 0, 1), 0.12, wk.INK_DARK,
          0.8)
    for k in range(5):      # louvred vent in the grey patch panel
        p.box(V((x + 0.08, 1.78 + k * 0.1, CAN_Z - 0.1)), (0.04, 0.05, 0.5), "dark", bevel=0.0)
    p.box(V((x + 0.075, 1.98, CAN_Z + 0.36)), (0.03, 0.4, 0.1), "hazard", bevel=0.0)
    rail(p, V((x + 0.07, 2.56, CAN_Z + 0.42)), V((x + 0.07, 2.56, CAN_Z - 0.42)), (1, 0, 0))
    # port flank: airlock in a grey frame, handholds, lock lamp
    x = -1.3
    p.box(V((x - 0.03, 3.25, CAN_Z)), (0.08, 0.72, 1.02), "hull", bevel=0.25)
    p.box(V((x - 0.04, 2.1, CAN_Z)), (0.12, 1.0, 1.16), "hull2", bevel=0.2)
    p.box(V((x - 0.09, 2.1, CAN_Z - 0.02)), (0.08, 0.68, 0.94), "hull3", bevel=0.18)
    p.box(V((x - 0.115, 2.1, CAN_Z + 0.53)), (0.04, 0.72, 0.08), "hazard", bevel=0.0)
    parts.window(p, V((x - 0.1, 2.1, CAN_Z + 0.2)), (-1, 0, 0), (0, 0, 1), 0.2, 0.14, "window")
    p.box(V((x - 0.14, 2.32, CAN_Z - 0.1)), (0.05, 0.06, 0.22), "metal", bevel=0.0)
    for y in (1.5, 2.7):
        rail(p, V((x - 0.06, y, CAN_Z + 0.45)), V((x - 0.06, y, CAN_Z - 0.45)), (-1, 0, 0))
    p.box(V((x - 0.1, 2.1, CAN_Z + 0.68)), (0.07, 0.12, 0.07), "light", bevel=0.0)
    label("LOCK 1", V((x - 0.07, 3.25, CAN_Z + 0.1)), (-1, 0, 0), (0, 0, 1), 0.16, wk.INK_DARK,
          0.85)
    # slit ports low on both flanks (the bunk deck)
    for sx in (-1, 1):
        for y in (2.95, 3.4):
            slit(p, V((sx * 1.345, y, CAN_Z - 0.3)), (sx, 0, 0), 0.3, 0.07)
    # belly: keel saddle plates and an equipment pallet
    p.box(V((0, 2.5, CAN_Z - 1.22)), (1.3, 2.3, 0.08), "dark", bevel=0.0)
    p.box(V((0.3, 3.0, CAN_Z - 1.32)), (0.6, 0.9, 0.2), "hull2", bevel=0.2)
    p.box(V((-0.38, 2.2, CAN_Z - 1.3)), (0.4, 0.6, 0.16), "hull3", bevel=0.2)
    # bow face hatch behind the tool frame
    p.cyl(V((0, 3.99, 0.42)), 0.42, 0.42, 0.08, "hull3", segs=14, axis_rot=ALONG_Y)
    p.torus(V((0, 4.02, 0.42)), 0.43, 0.04, "metal", segs=14, minor_segs=4,
            matrix=rot(rx=math.pi / 2))
    p.box(V((0, 4.05, 0.42)), (0.3, 0.04, 0.06), "dark", bevel=0.0)
    for k in range(8):
        a = k * math.pi / 4 + 0.39
        p.box(V((0.34 * math.cos(a), 4.03, 0.42 + 0.34 * math.sin(a))), (0.05, 0.04, 0.05),
              "metal", bevel=0.0)


def cupola(p):
    """Forward work cupola: a faceted blister overhanging the tool frame. The crew looks
    down the front slope at the cut through slits between armour bars."""
    rings = rings_of(CUPOLA)

    def cm(i, j):
        if i == 2 and j in (1, 2, 3):
            return "glass"
        if i == 0:
            return "hull2"
        if j in (5, 6, 7):
            return "hull2"
        return "hull"
    p.loft(rings, "hull2", mat_fn=cm)
    a, b = V((0, 3.8, 2.21)), V((0, 4.55, 1.82))      # top edge of the front slope
    n = (b - a).cross(V((1, 0, 0))).normalized()
    if n.z < 0:
        n = -n
    # armour bars across the slope leave three slits; mullions and corner posts
    for t, w in ((0.03, 1.2), (0.36, 1.26), (0.68, 1.3), (0.98, 1.36)):
        c = a.lerp(b, t) + n * 0.035
        p.box(c, (w, 0.15, 0.08), "hull2", r=face_rot(n, (1, 0, 0)), bevel=0.2)
    for x in (-0.3, 0.3):
        parts.strut(p, a + V((x, 0, 0)) + n * 0.03, b + V((x, 0, 0)) + n * 0.03, 0.07, 0.07,
                    "hull2", up=n)
    for j in (1, 2, 3, 4):
        parts.strut(p, rings[2][j] + n * 0.03, rings[3][j] + n * 0.03, 0.09, 0.07, "hull2", up=n)
    # side slit ports, warm light inside
    for sx in (-1, 1):
        for y in (2.95, 3.4):
            slit(p, V((sx * 0.855, y, 1.82)), (sx, 0, 0), 0.34, 0.08)
        rail(p, V((sx * 0.72, 2.75, 2.1)), V((sx * 0.72, 3.65, 2.1)), (sx * 0.7, 0, 0.7), off=0.07)
    # roof: grey number panel, amber beacon, hatch
    p.box(V((0, 3.15, 2.215)), (0.92, 0.9, 0.05), "hull3", bevel=0.2)
    label("07", V((0, 3.15, 2.245)), (0, 0, 1), (0, 1, 0), 0.4, wk.INK_DARK, 0.95)
    p.cyl(V((0.38, 2.5, 2.24)), 0.12, 0.12, 0.06, "dark", segs=10)
    p.cyl(V((0.38, 2.5, 2.33)), 0.085, 0.07, 0.13, "light", segs=10)
    # brow under the nose: flood bar looking down on the tools
    p.box(V((0, 4.5, 1.32)), (1.3, 0.2, 0.14), "dark", bevel=0.2)
    for x in (-0.45, 0.0, 0.45):
        parts.quad(p, V((x, 4.58, 1.25)), (0, 0.6, -0.8), (0, 0.8, 0.6), 0.26, 0.1, "white")
    p.box(V((0, 4.05, 1.4)), (1.5, 0.9, 0.12), "hull2", bevel=0.2)      # cupola sill


def can_fittings(p):
    """Roof and chamfer gear: docking collar, antenna cluster, flush radiators, pipes."""
    top = CAN_Z + 1.2
    # docking collar aft of the cupola, offset to port
    c = V((-0.32, 1.85, top))
    p.cyl(c + V((0, 0, 0.06)), 0.44, 0.47, 0.12, "hull2", segs=16)
    p.cyl(c + V((0, 0, 0.16)), 0.36, 0.36, 0.1, "metal", segs=16)
    p.cyl(c + V((0, 0, 0.215)), 0.27, 0.27, 0.02, "dark", segs=16)
    p.torus(c + V((0, 0, 0.13)), 0.46, 0.035, "hazard", segs=16, minor_segs=4)
    for k in range(3):
        a = k * 2 * math.pi / 3 + 0.5
        p.box(c + V((math.cos(a) * 0.4, math.sin(a) * 0.4, 0.22)), (0.1, 0.1, 0.08), "dark",
              r=rot(rz=a), bevel=0.0)
    # antenna cluster to starboard: mast, whips, small dish, strobe
    base = V((0.42, 1.62, top))
    p.box(base + V((0, 0, 0.06)), (0.42, 0.42, 0.14), "dark", bevel=0.2)
    p.tube(base + V((0, 0, 0.1)), base + V((0, 0, 0.95)), 0.045, 0.035, "metal", segs=6)
    p.tube(base + V((0.12, 0.1, 0.1)), base + V((0.2, -0.05, 1.35)), 0.02, 0.01, "dark", segs=4)
    p.tube(base + V((-0.12, -0.08, 0.1)), base + V((-0.2, -0.2, 0.9)), 0.02, 0.01, "dark",
           segs=4)
    p.box(base + V((0, 0, 0.98)), (0.08, 0.08, 0.08), "nav_r", bevel=0.0)
    parts.dish(p, base + V((0.06, -0.3, 0.42)), 0.3, V((0.5, -0.6, 0.7)), "hull3", "dark",
               depth=0.12, segs=12)
    p.tube(base + V((0, -0.1, 0.1)), base + V((0.06, -0.3, 0.42)), 0.035, 0.035, "metal",
           segs=5)
    label("NO STEP", V((0.3, 2.22, top)), (0, 0, 1), (0, 1, 0), 0.1, wk.INK_DARK, 0.8)
    # flush radiators on the upper chamfers, aft half of the can
    for sx in (-1, 1):
        n = V((sx, 0, 1)).normalized()
        c = V((sx * (1.3 - 0.31), 1.98, CAN_Z + 1.2 - 0.31))
        flush_radiator(p, c + n * 0.005, n, (0, 1, 0), 0.82, 0.66, ribs=6)
        # coolant feed along the chamfer foot
        parts.pipe(p, V((sx * 1.33, 1.5, CAN_Z + 0.63)), V((sx * 1.33, 3.6, CAN_Z + 0.63)),
                   0.035, "metal", segs=6)
        for y in (1.6, 2.5, 3.5):
            p.box(V((sx * 1.33, y, CAN_Z + 0.63)), (0.09, 0.08, 0.09), "dark", bevel=0.0)
    # grey welded patch on the starboard forward chamfer (Belter repair)
    n = V((1, 0, 1)).normalized()
    p.box(V((0.99, 3.2, CAN_Z + 0.89)) + n * 0.02, (0.7, 0.6, 0.04), "hull3",
          r=face_rot(n, (0, 1, 0)), bevel=0.0)
    bolts(p, V((0.99, 2.9, CAN_Z + 0.89)) + n * 0.04, V((0.99, 3.5, CAN_Z + 0.89)) + n * 0.04, 4,
          n, s=0.05)


def keel(p):
    """Keel truss from the crew can to the engineering block: the thrust path. The cradle
    hangs off it, the feed and power lines run along it."""
    parts.box_truss(p, -5.2, 1.3, 0.42, 0.34, 7, "hull2", "dark", chord=0.18, brace=0.09,
                    z0=KEEL_Z)
    p.box(V((0, -1.4, KEEL_Z + 0.36)), (0.74, 4.4, 0.05), "dark", bevel=0.0)   # cradle floor
    for x, r, mat in ((-0.2, 0.07, "metal"), (0.0, 0.05, "accent"), (0.2, 0.07, "hull3")):
        parts.pipe(p, V((x, -5.2, KEEL_Z - 0.05)), V((x, 1.3, KEEL_Z - 0.05)), r, mat, segs=6)
    for y in (-4.6, -3.0, -1.4, 0.2):
        p.box(V((0, y, KEEL_Z - 0.05)), (0.62, 0.1, 0.2), "dark", bevel=0.0)
    # belly marker lamps and a tow eye
    p.box(V((0, 0.9, KEEL_Z - 0.42)), (0.14, 0.2, 0.08), "light", bevel=0.0)
    p.box(V((0, -3.6, KEEL_Z - 0.42)), (0.14, 0.2, 0.08), "light", bevel=0.0)
    p.torus(V((0, -1.4, KEEL_Z - 0.46)), 0.16, 0.04, "metal", segs=10, minor_segs=4,
            matrix=rot(ry=math.pi / 2))


def tanks(p):
    """Two mismatched propellant tanks in strap saddles, helium spheres and plumbing."""
    for sx, body in ((-1, "hull3"), (1, "hull")):
        x = sx * TANK_X

        def tm(i, j, body=body, sx=sx):
            if j in (0, 6):
                return "metal"
            if j in (1, 2, 4, 5):
                return "hull2" if sx > 0 else body
            return body
        parts.capsule(p, TANK_Y0, TANK_Y1, TANK_R, tm, segs=16, x=x, z=TANK_Z, dome0=0.55,
                      dome1=0.55)
        for y in (-4.95, -4.05):       # strap bands and saddle arms to the keel
            p.torus(V((x, y, TANK_Z)), TANK_R + 0.01, 0.04, "dark", segs=16, minor_segs=4,
                    matrix=rot(rx=math.pi / 2))
            p.beam(V((x - sx * 0.3, y, TANK_Z - TANK_R + 0.1)), V((sx * 0.36, y, KEEL_Z + 0.2)),
                   0.14, 0.14, "dark")
            p.beam(V((x - sx * 0.62, y, TANK_Z + 0.3)), V((sx * 0.1, y, TANK_Z + 0.3)), 0.12,
                   0.12, "dark")
            p.box(V((x + sx * (TANK_R + 0.03), y, TANK_Z)), (0.08, 0.16, 0.2), "metal",
                  bevel=0.0)
        # fill port, relief valve, feed line aft into the engineering block
        p.cyl(V((x, -4.5, TANK_Z + TANK_R + 0.03)), 0.13, 0.13, 0.1, "metal", segs=10)
        p.cyl(V((x, -4.5, TANK_Z + TANK_R + 0.1)), 0.09, 0.09, 0.06, "hazard", segs=10)
        p.box(V((x + sx * 0.3, -4.2, TANK_Z + TANK_R * 0.9)), (0.1, 0.1, 0.12), "accent",
              bevel=0.0)
        parts.pipe(p, V((x, TANK_Y0 + 0.1, TANK_Z)), V((x * 0.8, -5.5, TANK_Z)), 0.07, "metal",
                   segs=6)
        SCORCH.append((x, -4.5, TANK_Z + TANK_R, 0.35))
    label("H2", V((-TANK_X - TANK_R * 0.72, -4.5, TANK_Z + TANK_R * 0.72)), (-1, 0, 1),
          (0, 1, 0), 0.2, wk.INK_DARK, 0.85)
    p.box(V((TANK_X, -4.5, TANK_Z + TANK_R * 0.99)), (0.5, 0.5, 0.04), "hull3", bevel=0.0)
    # helium spheres and the manifold between the tanks
    for y in (-4.05, -4.85):
        c = V((0, y, 0.72))
        p.sphere(c, 0.3, "metal", segs=12, rings=8)
        p.torus(c, 0.305, 0.03, "dark", segs=12, minor_segs=4)
        p.cyl(c + V((0, 0, 0.3)), 0.06, 0.06, 0.1, "accent", segs=6)
    parts.pipe(p, V((0, -3.7, 0.5)), V((0, -5.3, 0.5)), 0.06, "metal", segs=6)
    for y, mat in ((-3.75, "accent"), (-4.45, "hazard"), (-5.2, "accent")):
        p.box(V((0, y, 0.5)), (0.16, 0.14, 0.16), mat, bevel=0.0)
    for sx in (-1, 1):
        parts.pipe(p, V((0, -4.45, 0.5)), V((sx * 0.4, -4.45, 0.62)), 0.04, "metal", segs=5)
    # forward tank bulkhead: a dark frame the cradle butts against
    p.box(V((0, -3.62, -0.1)), (2.6, 0.1, 1.3), "hull2", bevel=0.15)
    p.box(V((0, -3.56, 0.42)), (2.2, 0.04, 0.16), "hazard", bevel=0.0)


def engineering(p):
    """Reactor / engineering block: chamfered slab hull, flush radiators, hazard collar."""
    def em(i, j):
        if i == 0:
            return "dark"
        if i == 2:
            return "dark"
        if j in (5, 6, 7):
            return "hull2"
        return "hull" if j == 2 else "hull2"
    p.loft(rings_of(ENGINE), "hull2", mat_fn=em)
    p.loft([oct_ring(-5.44, 2.54, 2.34, 0.63), oct_ring(-5.54, 2.54, 2.34, 0.63)], "hazard",
           cap=False)
    for sx in (-1, 1):
        flush_radiator(p, V((sx * 1.255, -5.78, 0.0)), (sx, 0, 0), (0, 1, 0), 0.4, 0.9, ribs=4)
        n = V((sx, 0, 1)).normalized()
        flush_radiator(p, V((sx * 0.94, -5.78, 0.84)) + n * 0.005, n, (0, 1, 0), 0.4, 0.62,
                       ribs=4)
    # reactor access hatch and stencil on the roof, stern strobe
    p.box(V((0, -5.78, 1.16)), (0.7, 0.36, 0.05), "hull3", bevel=0.2)
    p.box(V((0, -5.78, 1.2)), (0.1, 0.2, 0.04), "dark", bevel=0.0)
    label("KEEP CLEAR", V((0, -5.3, 1.1)), (0, 0.2, 1), (0, 1, 0), 0.09, wk.INK_DARK, 0.85)
    p.box(V((0, -6.02, 1.13)), (0.16, 0.1, 0.08), "white", bevel=0.0)
    p.box(V((0, -6.02, -1.13)), (0.16, 0.1, 0.08), "light", bevel=0.0)
    # coolant loop: two lines from the roof hatch forward over the manifold, belly pump box
    for sx in (-1, 1):
        parts.pipe(p, V((sx * 0.22, -5.6, 1.17)), V((sx * 0.22, -5.2, 1.0)), 0.04, "accent",
                   segs=5)
        parts.pipe(p, V((sx * 0.22, -5.2, 1.0)), V((sx * 0.22, -5.05, 0.55)), 0.04, "accent",
                   segs=5)
        # stencilled side service panel and a vent
        p.box(V((sx * 1.26, -5.32, -0.5)), (0.04, 0.2, 0.5), "hull3", bevel=0.0)
        for k in range(3):
            p.box(V((sx * 1.27, -5.32, -0.66 + k * 0.16)), (0.04, 0.14, 0.05), "dark",
                  bevel=0.0)
    p.box(V((0.3, -5.7, -1.2)), (0.7, 0.5, 0.16), "hull3", bevel=0.2)


def drive(p):
    """Gimballed thrust mount and the one big bell."""
    p.cyl(V((0, -6.3, 0)), 0.86, 0.7, 0.22, "hull2", segs=18, axis_rot=ALONG_Y)
    p.cyl(V((0, -6.46, 0)), 0.66, 0.56, 0.12, "metal", segs=18, axis_rot=ALONG_Y)
    p.torus(V((0, -6.4, 0)), 0.72, 0.05, "dark", segs=18, minor_segs=4,
            matrix=rot(rx=math.pi / 2))
    parts.bell(p, NOZZLE_Y, BELL_R, BELL_LEN, "temper", "dark", segs=22)
    for y, rr in ((-6.66, 0.79), (-7.0, 0.975), (NOZZLE_Y + 0.07, BELL_R * 0.985)):
        p.torus(V((0, y, 0)), rr, 0.035, "metal", segs=22, minor_segs=4,
                matrix=rot(rx=math.pi / 2))
    for k in range(4):                # gimbal actuators
        a = math.pi / 4 + k * math.pi / 2
        d = V((math.cos(a), 0, math.sin(a)))
        ram(p, V((0, -6.18, 0)) + d * 1.0, V((0, -6.7, 0)) + d * 0.86, r=0.05)
    for a in (0.0, math.pi):          # turbopump exhaust stubs
        d = V((math.cos(a), 0, math.sin(a)))
        parts.pipe(p, V((0, -6.3, 0)) + d * 0.85, V((0, -6.75, 0)) + d * 0.98, 0.045, "metal",
                   segs=6)
    SCORCH.append((0.0, -6.9, 0.0, 1.6))


def rcs(p):
    """RCS quads on the four corners of the can and of the engineering block."""
    for sx in (-1, 1):
        for sz in (-1, 1):
            n = V((sx, 0, sz)).normalized()
            c = V((sx * 0.99, 1.75 if sz < 0 else 3.48, CAN_Z + sz * 0.89)) + n * 0.1
            if sz > 0:
                c = V((sx * 0.99, 1.4, CAN_Z + 0.89)) + n * 0.1
            parts.rcs_quad(p, c, n, "hull2", "metal", s=0.25)
            SCORCH.append((c.x, c.y, c.z, 0.45))
            c = V((sx * 0.94, -5.78, sz * 0.84)) + n * 0.1
            if sz > 0:
                c = V((sx * 0.94, -5.3, 0.84)) + n * 0.02
            parts.rcs_quad(p, c, n, "hull2", "metal", s=0.24)
            SCORCH.append((c.x, c.y, c.z, 0.45))


# ---------------------------------------------------------------- rig: tools
def build_rig():
    p = parts.PanelPart("salvager_rig", MATS)
    tool_frame(p)
    for sx in (-1, 1):
        arm(p, sx)
    cutter(p)
    cradle(p)
    return p


def tool_frame(p):
    """Heavy open frame across the bow: two beams, end posts, shoulder mounts, braces."""
    y = FRAME_Y
    for z in (0.86, -0.66):
        p.box(V((0, y, z)), (3.9, 0.6, 0.4), "hull2", bevel=0.25)
        p.box(V((0, y + 0.305, z)), (3.3, 0.02, 0.2), "hazard", bevel=0.0)
        bolts(p, V((-1.8, y + 0.3, z + 0.15)), V((1.8, y + 0.3, z + 0.15)), 12, (0, 1, 0), s=0.05)
    for sx in (-1, 1):
        p.box(V((sx * 1.75, y, 0.1)), (0.4, 0.56, 1.2), "hull2", bevel=0.2)
        # shoulder mount: orange block between the beams, bolted flange
        p.box(V((sx * 1.3, y + 0.08, 0.1)), (0.7, 0.6, 1.12), "hull", bevel=0.08)
        p.cyl(V((sx * 1.4, y + 0.42, 0.15)), 0.4, 0.4, 0.1, "metal", segs=14, axis_rot=ALONG_Y)
        # braces back to the can flanks and roof
        p.beam(V((sx * 1.85, y - 0.2, 0.1)), V((sx * 1.3, 3.3, 0.1)), 0.16, 0.2, "dark")
        p.beam(V((sx * 1.2, y - 0.25, 1.0)), V((sx * 0.9, 3.5, 1.42)), 0.12, 0.12, "dark")
        # flood lamps on the top beam ends, nav lights on the posts
        lamp(p, V((sx * 1.55, y + 0.36, 1.2)), (sx * 0.15, 0.9, -0.35), (0, 0.35, 0.9), 0.3, 0.2)
        p.box(V((sx * 1.55, y + 0.1, 1.1)), (0.14, 0.4, 0.1), "dark", bevel=0.0)
        p.box(V((sx * 1.97, y, 0.5)), (0.06, 0.2, 0.1), "nav_g" if sx > 0 else "nav_r",
              bevel=0.0)
        rail(p, V((sx * 0.9, y - 0.15, 1.06)), V((sx * 0.3, y - 0.15, 1.06)), (0, 0, 1))
    label("KEEP CLEAR", V((1.95, y, -0.2)), (1, 0, 0), (0, 0, 1), 0.09, INK_WHITE, 0.85)
    # tool locker and cable reel on the top beam
    p.box(V((-0.55, y - 0.05, 1.14)), (0.6, 0.36, 0.2), "hull3", bevel=0.2)
    p.box(V((-0.55, y + 0.14, 1.14)), (0.2, 0.02, 0.06), "dark", bevel=0.0)
    drum(p, V((0.5, y, 1.2)), (1, 0, 0), 0.16, 0.34, mat="accent", cap="dark", segs=10)
    for s in (-1, 1):
        p.box(V((0.5 + s * 0.2, y, 1.14)), (0.04, 0.3, 0.2), "dark", bevel=0.0)


def arm(p, sx):
    """One manipulator arm: yaw turret, upper arm, elbow, forearm, roll wrist, claw."""
    base = V((sx * 1.4, FRAME_Y + 0.47, 0.15))
    s = V((sx * 1.48, 4.98, 0.15))
    e = V((sx * 2.18, 5.8, 0.68))
    w = V((sx * 1.42, 6.48, 0.3))
    f = V((-sx * 0.22, 1.0, -0.08)).normalized()        # claw reach direction
    # yaw turret
    p.tube(base, base + V((0, 0.22, 0)), 0.34, 0.3, "dark", segs=14)
    drum(p, s, (0, 0, 1), 0.34, 0.66, mat="hull2", cap="metal")
    p.torus(s, 0.345, 0.03, "hazard", segs=14, minor_segs=4)
    # upper arm: yellow box section with a dark service cover and a stencil strip
    d1 = (e - s).normalized()
    up1 = V((0, 0, 1))
    link(p, s + d1 * 0.1, e - d1 * 0.05, 0.34, 0.44, "accent", bevel=0.22)
    side = d1.cross(up1).normalized() * sx
    n1 = side.cross(d1).normalized()
    if n1.z < 0:
        n1 = -n1
    mid = s.lerp(e, 0.5)
    p.box(mid + n1 * 0.225, (0.5, 0.2, 0.03), "hull2", r=dir_rot(d1), bevel=0.0)
    p.box(mid + side * 0.175, (0.56, 0.03, 0.2), "hazard", r=dir_rot(d1), bevel=0.0)
    # elbow drum, axis square to both links
    d2 = (w - e).normalized()
    ax = d1.cross(d2).normalized()
    drum(p, e, ax, 0.24, 0.4, mat="hull2", cap="metal")
    for q in (s, w):          # fork cheeks either side of the elbow
        dd = (q - e).normalized()
        for t in (-1, 1):
            p.box(e + dd * 0.18 + ax * t * 0.2, (0.46, 0.26, 0.05), "accent",
                  r=dir_rot(dd, ax), bevel=0.0)
    # forearm
    link(p, e + d2 * 0.12, w - d2 * 0.02, 0.28, 0.34, "accent", bevel=0.22)
    fm = e.lerp(w, 0.55)
    n2 = ax if ax.z > 0 else -ax
    p.box(fm + n2 * 0.175, (0.4, 0.16, 0.03), "hull2", r=dir_rot(d2, n2), bevel=0.0)
    lamp(p, fm + n2 * 0.26 + d2 * 0.12, d2, n2, 0.16, 0.1, depth=0.2)
    # rams: shoulder lift and elbow curl
    ram(p, s + V((0, 0, 0.42)) + d1 * 0.02, s.lerp(e, 0.72) + n1 * 0.26, r=0.065)
    ram(p, s.lerp(e, 0.45) - n1 * 0.27, e.lerp(w, 0.38) - n2 * 0.24, r=0.055)
    # hoses: frame to elbow, elbow to wrist
    hose(p, base + V((sx * 0.3, -0.1, 0.5)), e + n2 * 0.3, 0.16, r=0.035, sag_dir=(sx, 0, -0.4))
    hose(p, e + n2 * 0.3, w + n2 * 0.2, 0.08, r=0.03, sag_dir=(sx, 0, 0.3))
    hose(p, base + V((sx * 0.36, -0.1, 0.36)), e - n2 * 0.3, 0.2, r=0.03, mat="accent",
         sag_dir=(sx, 0, -0.6))
    claw(p, w, f, sx)


def claw(p, w, f, sx):
    """Roll wrist and a three-finger grapple claw reaching along f."""
    side = f.cross(V((0, 0, 1))).normalized()
    up = side.cross(f).normalized()
    p.sphere(w, 0.2, "dark", segs=10, rings=6)
    p.tube(w + f * 0.06, w + f * 0.24, 0.17, 0.17, "hull2", segs=12)
    p.tube(w + f * 0.24, w + f * 0.3, 0.21, 0.21, "metal", segs=12)
    palm = w + f * 0.42
    p.box(palm, (0.26, 0.4, 0.4), "accent", r=dir_rot(f, up), bevel=0.22)
    p.box(palm + f * 0.14, (0.04, 0.2, 0.2), "dark", r=dir_rot(f, up), bevel=0.0)
    for k in range(3):
        a = k * 2 * math.pi / 3 + math.pi / 2
        d = side * math.cos(a) + up * math.sin(a)
        hinge = d.cross(f).normalized()
        b = palm + f * 0.1 + d * 0.2
        knee = b + f * 0.32 + d * 0.22
        tip = knee + f * 0.34 - d * 0.2
        drum(p, b, hinge, 0.085, 0.16, mat="dark", cap="metal", segs=8)
        link(p, b, knee, 0.13, 0.11, "accent", bevel=0.2, up=d)
        drum(p, knee, hinge, 0.07, 0.15, mat="dark", cap="metal", segs=8)
        link(p, knee, tip, 0.1, 0.08, "metal", bevel=0.2, up=d)
        p.tube(tip - (tip - knee).normalized() * 0.02, tip + f * 0.03 - d * 0.14, 0.045, 0.012,
               "temper", segs=5)
        # finger ram from the palm
        p.tube(palm - f * 0.06 + d * 0.21, b.lerp(knee, 0.6) + d * 0.08, 0.025, 0.025, "metal",
               segs=5)


def cutter(p):
    """Plasma cutter boom on the centre line, under the arms. Tip = tool_point."""
    y = FRAME_Y
    # sub-frame hanging from the lower beam, shoulder drum
    p.box(V((0, y + 0.12, -0.62)), (1.0, 0.7, 0.62), "hull2", bevel=0.2)
    p.box(V((0, y + 0.475, -0.62)), (0.8, 0.02, 0.3), "hazard", bevel=0.0)
    sh = V((0, y + 0.62, -0.6))
    kn = V((0, 6.0, -0.62))
    hd = V((0, 6.72, -0.04))
    for sx in (-1, 1):
        p.box(sh + V((sx * 0.22, -0.06, 0)), (0.07, 0.4, 0.44), "hull2", bevel=0.15)
    drum(p, sh, (1, 0, 0), 0.2, 0.36, mat="dark", cap="metal", segs=12)
    # boom: yellow box section, knuckle, short head link
    link(p, sh + V((0, 0.1, 0)), kn - V((0, 0.08, 0)), 0.26, 0.3, "accent", bevel=0.22)
    drum(p, kn, (1, 0, 0), 0.19, 0.42, mat="dark", cap="metal", segs=12)
    d2 = (hd - kn).normalized()
    link(p, kn + d2 * 0.1, hd, 0.2, 0.24, "accent", bevel=0.22)
    ram(p, sh + V((0, 0.05, 0.3)), sh.lerp(kn, 0.75) + V((0, 0, 0.2)), r=0.05)
    ram(p, sh.lerp(kn, 0.5) + V((0, 0, -0.2)), kn.lerp(hd, 0.6) - V((0, -0.1, 0.2)), r=0.045)
    # gas bottles either side of the boom, regulator, hoses to the head
    for sx, mat in ((-1, "hull3"), (1, "hull")):
        a = V((sx * 0.25, y + 0.95, -0.56))
        b = V((sx * 0.25, 5.8, -0.58))
        p.tube(a, b, 0.095, 0.095, mat, segs=10)
        p.sphere(b, 0.095, mat, segs=10, rings=6)
        p.tube(a - V((0, 0.08, 0)), a, 0.05, 0.07, "metal", segs=8)
        for t in (0.25, 0.75):
            q = a.lerp(b, t)
            p.box(V((sx * 0.19, q.y, q.z)), (0.2, 0.06, 0.24), "dark", bevel=0.0)
        hose(p, a - V((0, 0.06, 0)) + V((0, 0, 0.08)), hd + V((sx * 0.12, 0.1, 0.14)), 0.14,
             r=0.028, n=7, mat="dark" if sx < 0 else "accent", sag_dir=(sx * 0.6, 0, 1))
    # cutter head: wrist drum, housing, cooling jacket, spall shield, nozzle, hot tip
    drum(p, hd, (1, 0, 0), 0.15, 0.34, mat="dark", cap="metal", segs=10)
    p.box(V((0, 6.93, 0)), (0.32, 0.36, 0.3), "hull2", bevel=0.2)
    p.box(V((0, 6.93, 0.16)), (0.2, 0.2, 0.04), "hazard", bevel=0.0)
    p.cyl(V((0, 7.14, 0)), 0.13, 0.13, 0.12, "metal", segs=12, axis_rot=ALONG_Y)
    for yy in (7.1, 7.16):
        p.torus(V((0, yy, 0)), 0.135, 0.02, "dark", segs=12, minor_segs=3,
                matrix=rot(rx=math.pi / 2))
    # octagonal spall shield with a dark viewing port and a hazard rim
    p.cyl(V((0, 7.23, 0)), 0.44, 0.44, 0.05, "hull2", segs=8,
          axis_rot=ALONG_Y @ rot(rz=math.pi / 8))
    p.cyl(V((0, 7.2, 0)), 0.47, 0.47, 0.03, "hazard", segs=8,
          axis_rot=ALONG_Y @ rot(rz=math.pi / 8))
    parts.quad(p, V((0, 7.262, 0.27)), (0, 1, 0), (0, 0, 1), 0.3, 0.09, "glass")
    for sx in (-1, 1):
        p.beam(V((sx * 0.16, 6.95, 0.1)), V((sx * 0.3, 7.2, 0.16)), 0.04, 0.04, "metal")
    p.tube(V((0, 7.25, 0)), V((0, 7.46, 0)), 0.12, 0.075, "temper", segs=12)
    p.tube(V((0, 7.46, 0)), V((0, 7.53, 0)), 0.085, 0.06, "dark", segs=12)
    p.tube(V((0, 7.5, 0)), V((0, TOOL_Y, 0)), 0.045, 0.02, "torch", segs=8)
    p.box(V((0.2, 6.93, 0.05)), (0.06, 0.12, 0.08), "light", bevel=0.0)
    for sx in (-1, 1):
        label("CUTTER", V((sx * 0.5, y + 0.12, -0.62)), (sx, 0, 0), (0, 0, 1), 0.12, INK_WHITE,
              0.85)
    SCORCH.append((0.0, 7.3, 0.0, 0.7))


# ---------------------------------------------------------------- rig: cradle
def cradle(p):
    """Open truss cradle on the keel: U ribs, rails, cross bracing, clamps, winches."""
    x = CRADLE_X
    zb = KEEL_Z
    for i, y in enumerate(RIBS):
        p.box(V((0, y, zb)), (2 * x + 0.22, 0.22, 0.24), "hull2", bevel=0.2)
        for sx in (-1, 1):
            link(p, V((sx * x, y, zb - 0.05)), V((sx * x, y, RAIL_Z + 0.06)), 0.2, 0.22,
                 "hull" if i in (0, 3) else "hull2", bevel=0.18, up=(sx, 0, 0))
            # gussets: knee brace and plate at the foot
            p.beam(V((sx * 1.15, y, zb + 0.06)), V((sx * (x - 0.04), y, zb + 0.82)), 0.1, 0.12,
                   "dark")
            p.box(V((sx * (x - 0.2), y, zb + 0.2)), (0.4, 0.04, 0.4), "dark", bevel=0.0)
            # hinged clamp at the post head, hazard pad biting the cargo, small ram
            hp = V((sx * x, y, RAIL_Z + 0.12))
            drum(p, hp, (0, 1, 0), 0.12, 0.3, mat="dark", cap="metal", segs=10)
            tip = V((sx * 1.52, y, RAIL_Z - 0.22))
            link(p, hp, tip, 0.2, 0.12, "accent", bevel=0.2, up=(sx, 0, 1))
            p.box(tip + V((-sx * 0.04, 0, -0.06)), (0.18, 0.3, 0.16), "hazard",
                  r=rot(ry=sx * 0.5), bevel=0.15)
            ram(p, V((sx * (x - 0.02), y + 0.17, RAIL_Z - 0.5)),
                V((sx * 1.7, y + 0.17, RAIL_Z - 0.08)), r=0.04)
            # bumper pad on the inside of the post
            p.box(V((sx * (x - 0.13), y, 0.1)), (0.08, 0.18, 0.5), "dark", bevel=0.2)
    for sx in (-1, 1):
        # rails: orange top rail, dark lower rail, diagonals between the posts
        p.box(V((sx * x, (CRADLE_Y0 + CRADLE_Y1) / 2, RAIL_Z)),
              (0.16, CRADLE_Y1 - CRADLE_Y0, 0.18), "hull", bevel=0.2)
        p.box(V((sx * x, (CRADLE_Y0 + CRADLE_Y1) / 2, zb)),
              (0.16, CRADLE_Y1 - CRADLE_Y0, 0.18), "hull2", bevel=0.2)
        for k, (ya, yb) in enumerate(zip(RIBS, RIBS[1:])):
            za, zc = (zb + 0.1, RAIL_Z - 0.1) if k % 2 == 0 else (RAIL_Z - 0.1, zb + 0.1)
            parts.strut(p, V((sx * x, ya + 0.1, za)), V((sx * x, yb - 0.1, zc)), 0.08, 0.08,
                        "dark", up=V((sx, 0, 0)))
        p.box(V((sx * (x + 0.085), -1.375, RAIL_Z)), (0.02, 2.2, 0.12), "hazard", bevel=0.0)
        label("LIFT", V((sx * (x + 0.08), 0.25, RAIL_Z)), (sx, 0, 0), (0, 0, 1), 0.1, wk.INK_DARK,
              0.85)
        # winches on the rail: drum between flanges, motor, a tag lamp
        for y in STRAPS:
            c = V((sx * (x + 0.02), y, RAIL_Z + 0.24))
            drum(p, c, (0, 1, 0), 0.16, 0.3, mat="accent", cap="dark", segs=10)
            for s in (-1, 1):
                p.box(c + V((0, s * 0.18, -0.04)), (0.36, 0.05, 0.4), "hull2", bevel=0.15)
            p.box(c + V((sx * 0.02, 0.36, -0.06)), (0.24, 0.26, 0.24), "hull3", bevel=0.2)
            p.box(c + V((0, -0.3, -0.12)), (0.2, 0.14, 0.12), "dark", bevel=0.0)
        # tail and bow marker lamps on the rail ends, work lamp looking into the cradle
        p.box(V((sx * x, CRADLE_Y0 - 0.02, RAIL_Z)), (0.1, 0.06, 0.1), "light", bevel=0.0)
        lamp(p, V((sx * (x - 0.12), CRADLE_Y1 - 0.5, RAIL_Z + 0.2)), (-sx * 0.8, -0.3, -0.5),
             (0, 0, 1), 0.16, 0.12, mat="light", depth=0.14)
    # power conduit clipped under the starboard top rail, junction boxes at the winches
    parts.pipe(p, V((x - 0.02, CRADLE_Y0 + 0.1, RAIL_Z - 0.16)),
               V((x - 0.02, CRADLE_Y1 - 0.1, RAIL_Z - 0.16)), 0.035, "dark", segs=5)
    parts.pipe(p, V((-x + 0.02, CRADLE_Y0 + 0.1, RAIL_Z - 0.16)),
               V((-x + 0.02, CRADLE_Y1 - 0.1, RAIL_Z - 0.16)), 0.035, "accent", segs=5)
    # catwalk grating along the port lower rail
    p.box(V((-x - 0.28, -1.375, zb + 0.02)), (0.4, 3.6, 0.04), "dark", bevel=0.0)
    for y in (-3.0, -1.4, 0.2):
        p.beam(V((-x, y, zb - 0.05)), V((-x - 0.46, y, zb - 0.05)), 0.06, 0.08, "hull2")
    rail(p, V((-x - 0.46, -3.1, zb + 0.04)), V((-x - 0.46, 0.3, zb + 0.04)), (0, 0, 1),
         off=0.4)
    for y in (-1.95, -0.8):
        parts.strut(p, V((-x - 0.46, y, zb + 0.04)), V((-x - 0.46, y, zb + 0.44)), 0.035, 0.035,
                    "metal", up=V((0, 1, 0)))


# ---------------------------------------------------------------- scrap
def arc_pt(a, y, r=WRECK_R):
    return V((r * math.cos(a), y, WRECK_Z + r * math.sin(a)))


def build_scrap():
    """Torn hull section of another ship, dome up in the cradle, under two straps."""
    p = parts.PanelPart("salvager_scrap", MATS)
    rng = random.Random(907)
    n_a, n_y = 8, 5
    a0, a1 = math.radians(14), math.radians(166)
    y0, y1 = WRECK_Y - 1.86, WRECK_Y + 1.86
    da, dy = (a1 - a0) / n_a, (y1 - y0) / n_y
    gone = {(0, 0), (1, 0), (7, 0), (7, 1), (0, 4), (6, 4), (7, 4), (3, 4), (4, 2), (5, 2),
            (4, 3), (2, 0)}
    bent = {(3, 0): 0.35, (6, 0): -0.3, (1, 4): 0.4, (5, 4): -0.45, (4, 4): 0.3,
            (3, 2): -0.3, (6, 2): 0.35, (5, 3): 0.4, (3, 3): -0.25, (0, 1): 0.25}
    for i in range(n_a):
        for j in range(n_y):
            if (i, j) in gone:
                continue
            a = a0 + (i + 0.5) * da
            y = y0 + (j + 0.5) * dy
            n = V((math.cos(a), 0, math.sin(a)))
            c = arc_pt(a, y)
            r = face_rot(n, (0, 1, 0))
            mat = "stripe" if i == 5 else ("scrap" if (i * 3 + j * 5) % 11 == 0 else "pad")
            w, ln = WRECK_R * da - 0.03, dy - 0.03
            if (i, j) in bent:
                k = bent[(i, j)]
                r = r @ rot(rx=k * 0.6, ry=k)
                c = c + n * abs(k) * 0.22
                w, ln = w * rng.uniform(0.7, 0.95), ln * rng.uniform(0.7, 0.95)
            else:
                r = r @ rot(rx=rng.uniform(-0.04, 0.04), ry=rng.uniform(-0.05, 0.05),
                            rz=rng.uniform(-0.02, 0.02))
                c = c + n * rng.uniform(-0.02, 0.02)
            p.box(c, (ln, w, 0.07), mat, r=r, bevel=0.0)
    label("TY-31", arc_pt(a0 + 2.5 * da, y0 + 1.5 * dy, WRECK_R + 0.04), (-0.35, 0, 0.94),
          (0, 1, 0), 0.34, INK_WHITE, 0.8)
    # ring frames on the inside (every panel row), broken where the hull tore
    for j in range(n_y + 1):
        y = y0 + j * dy
        for i in range(n_a):
            if rng.random() < 0.12 or (j in (0, n_y) and i in (0, 7)):
                continue
            pa = arc_pt(a0 + i * da, y, WRECK_R - 0.12)
            pb = arc_pt(a0 + (i + 1) * da, y, WRECK_R - 0.12)
            mid = (pa + pb) / 2
            out = V((mid.x, 0, mid.z - WRECK_Z)).normalized()
            p.beam(pa, pb, 0.1, 0.2, "rust", up=out)
    # stringers, some sticking out past the torn ends as bent stubs
    for i in (1, 2, 4, 6, 7):
        a = a0 + i * da
        e0 = y0 - rng.uniform(-0.3, 0.42)
        e1 = y1 + rng.uniform(-0.3, 0.36)
        pa, pb = arc_pt(a, e0, WRECK_R - 0.09), arc_pt(a, e1, WRECK_R - 0.09)
        out = V((math.cos(a), 0, math.sin(a)))
        parts.strut(p, pa, pb, 0.09, 0.12, "scrap", up=out)
        tip = pb + V((rng.uniform(-0.2, 0.2), 0.3, rng.uniform(-0.1, 0.3)))
        if tip.y < CRADLE_Y1 + 0.1:
            p.beam(pb, tip, 0.09, 0.1, "scrap", up=out)
    # torn skin shards curling out round the gash and at the ends
    for a, y, tw, s in ((a0 + 4.1 * da, y0 + 2.1 * dy, 0.5, 0.42),
                        (a0 + 5.9 * da, y0 + 2.9 * dy, -0.6, 0.38),
                        (a0 + 4.6 * da, y0 + 3.95 * dy, 0.7, 0.36),
                        (a0 + 1.6 * da, y0 + 0.2 * dy, -0.5, 0.4)):
        n = V((math.cos(a), 0, math.sin(a)))
        m = Matrix.Translation(arc_pt(a, y) + n * 0.12) @ face_rot(n, (0, 1, 0)) \
            @ rot(rx=tw, ry=tw * 0.7)
        p.slab([(-s, -s * 0.5), (s * 0.9, -s * 0.7), (s * 0.4, s * 0.8)], -0.03, 0.03, "pad",
               matrix=m)
    # deck fragment inside, torn edge, and a dark cavity plate so the gash reads as deep
    deck = [(-1.42, -1.5), (0.6, -1.7), (1.05, -0.6), (0.5, 0.2), (0.9, 1.3), (-0.2, 1.62),
            (-1.42, 1.4)]
    p.slab(deck, -0.04, 0.04, "scrap", matrix=Matrix.Translation((0, WRECK_Y, 0.3)))
    p.box(V((0.2, WRECK_Y + 0.5, 0.36)), (0.5, 0.7, 0.3), "rust", r=rot(rz=0.2), bevel=0.15)
    p.box(V((-0.6, WRECK_Y - 0.7, 0.46)), (0.3, 0.9, 0.24), "scrap", r=rot(rz=-0.1), bevel=0.15)
    # dangling pipes and a broken duct
    for xa, za, r_ in ((-0.9, 1.1, 0.05), (0.5, 1.3, 0.04), (1.0, 0.75, 0.06)):
        parts.pipe(p, V((xa, y0 - 0.25, za)), V((xa + 0.05, y1 - 0.4, za)), r_, "metal", segs=6)
        parts.pipe(p, V((xa + 0.05, y1 - 0.4, za)), V((xa + 0.2, y1 + 0.05, za - 0.3)), r_,
                   "metal", segs=6)
    p.tube(V((-0.3, y0 - 0.2, 0.75)), V((-0.3, y0 + 1.4, 0.75)), 0.2, 0.2, "scrap", segs=8)
    # a porthole frame in the skin (dark glass, long dead)
    a = a0 + 1.5 * da
    n = V((math.cos(a), 0, math.sin(a)))
    c = arc_pt(a, y0 + 2.5 * dy, WRECK_R + 0.04)
    p.cyl(c, 0.2, 0.2, 0.04, "metal", segs=10, axis_rot=axis_rot(n))
    p.cyl(c + n * 0.015, 0.14, 0.14, 0.03, "dark", segs=10, axis_rot=axis_rot(n))
    # salvage tag beacon clamped to a frame
    tag = arc_pt(a0 + 3.5 * da, y0 + 0.9 * dy, WRECK_R + 0.1)
    p.box(tag, (0.16, 0.2, 0.1), "accent", bevel=0.2)
    p.box(tag + V((0, 0, 0.08)), (0.07, 0.07, 0.07), "light", bevel=0.0)
    # ratchet straps over the load, winch to winch
    for y in STRAPS:
        pts = [V((CRADLE_X + 0.02, y, RAIL_Z + 0.36))]
        for k in range(7):
            a = math.radians(38) + k * math.radians(104) / 6
            pts.append(arc_pt(a, y, WRECK_R + 0.07))
        pts.append(V((-CRADLE_X - 0.02, y, RAIL_Z + 0.36)))
        for q0, q1 in zip(pts, pts[1:]):
            mid = (q0 + q1) / 2
            out = V((mid.x, 0, mid.z - WRECK_Z)).normalized()
            link(p, q0, q1, 0.16, 0.03, "accent", bevel=0.0, up=out, ext=0.03)
        b = pts[2]
        out = V((b.x, 0, b.z - WRECK_Z)).normalized()
        p.box(b + out * 0.04, (0.2, 0.22, 0.09), "metal", r=face_rot(out, (0, 1, 0)), bevel=0.2)
    return p


def build_glow():
    p = parts.Part("engine_glow", MATS)
    # Built around the bell exit plane at y = 0 (object origin moved to NOZZLE_Y below).
    parts.exhaust_glow(p, BELL_R * 0.85, 1.0, "glow", segs=16)
    return p


def build_ship():
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    root = parts.make_root("salvager")
    hull = build_hull().finish(root)
    rig = build_rig().finish(root)
    scrap = build_scrap().finish(root)
    glow = build_glow().finish(root)
    glow.location = (0, NOZZLE_Y, 0)
    parts.add_empty("tool_point", root, (0, TOOL_Y, 0), size=1.0)
    return root, [hull, rig, scrap], glow


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs, glow = build_ship()
    bpy.context.view_layer.update()
    if "--no-textures" not in argv:
        glow.hide_render = True
        wk.texture(objs, MATS, PRE, [(0.0, 0.0)], scorch=SCORCH, decals=DECALS,
                   labels=LABELS, seed0=207)
        glow.hide_render = False
        recompress()
    else:
        for o in objs:
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    wk.stats(objs + [glow])
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews("salvager", 17.0, target=(0, 0.1, 0))
    extra = [a.split("=", 1)[1] for a in argv if a.startswith("--extra=")]
    if extra:
        extra_views(extra[0])


def recompress():
    """Re-save the baked maps at a lower JPEG quality. Three objects share this atlas, so
    it is busier than the other ships' and the exporter embeds the files as they are."""
    for img in bpy.data.images:
        name = os.path.basename(img.filepath)
        if not name.startswith(f"{PRE}_") or not name.endswith(".jpg"):
            continue
        img.file_format = "JPEG"
        img.save(quality=84 if "normal" in name else 82)
        img.reload()
        print("RECOMPRESSED", name, os.path.getsize(bpy.path.abspath(img.filepath)))


def extra_views(out_dir):
    """Debug close-ups into out_dir; not part of the previews."""
    scene = bpy.context.scene
    if scene.camera is None:
        common.setup_preview(cam_loc=(-17, 12, 20), cam_target=(0, 0.1, 0), ortho_scale=23.0,
                             res=(1600, 1200), key_dir=(-0.5, 0.4, 0.75), key_energy=3.5)
    cam = scene.camera
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1200
    views = (("tools", (-8, 15, 7), (0, 5.4, 0.2), 6.5),
             ("cradle", (-9, 3, 9), (0, -1.2, 0.2), 7.5),
             ("stern", (-8, -15, 7), (0, -4.6, 0.2), 7.5),
             ("side", (-30, 0, 0), (0, 0.1, 0.3), 17.0),
             ("front", (5, 20, 4), (0, 5, 0.2), 7.5),
             ("belly", (-10, 8, -9), (0, 0, -0.5), 17.0),
             ("rts", (-6, -14, 30), (0, 0.1, 0), 24.0))
    for name, loc, tgt, ortho in views:
        cam.location = loc
        cam.rotation_euler = (V(tgt) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        cam.data.ortho_scale = ortho
        common.render(os.path.join(out_dir, f"salvager_{name}.png"))


main()
