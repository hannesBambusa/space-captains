"""Generate the miner hauler .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_miner_hauler.py
  Add `-- --no-preview` to skip the PNG renders, `-- --no-textures` to skip the atlas bake
  (fast shape iteration: flat colours only), `-- --extra=<dir>` for debug close-ups.

Design: "Prospector" class mining barge. Every section has a job, front to back:
  bow       quad-line combiner mining laser. Four fibre-amplifier lines, each a gain can
            (pump windows, coolant jackets) feeding a small emitter head on a tip/tilt
            gimbal (collimator, optics, cover-slide drawer, iris shutter, aperture lens),
            sit on a trapezoid optical bench (upper pair narrow, lower pair wide, so the
            four beams stay four lines from the RTS camera). All four are toed in onto a
            2x2 diffractive combiner plate in an armoured ring 2.1 m ahead: four thin
            beams in, one big beam out to the rock. A narrow top spar and a bottom A-frame
            carry the ring. Behind the bench: the laser bay with its spall plate, the pump
            power cabinet (power bus runs forward from the reactor through the spine),
            two chillers and two flat radiator wings. Spall that flies back from the cut
            drops into a catch hopper under the bench and rides the keel conveyor.
  work bay  forward module carrying the spall conveyor (keel housing from the hopper back
            to the crusher), an armoured cockpit offset to port and raised so the crew
            looks down at the cut, behind slit windows and a debris grille; an ore
            scanner dish and lidar ball on a starboard mast.
  refinery  taller block with the crusher intake, side vents, a tailings chute that dumps
            slag downward, and two V radiators on top that shed the refining heat.
  hold      an open spine truss carrying six ore canisters (three a side) on clamp
            cradles, fed by a manifold along the spine; two canisters stand open with ore
            heaped in the hatch. Belly ore-transfer coupling with guide lights for docking.
  stern     reactor drum on top (coolant lines run forward to the radiators), two
            spherical propellant tanks, thrust block with two gimballed bells, RCS quads.
Worn white/grey work paint, orange identity bands, hazard trim, stencils ("MX-14").

Layout (Blender Z up, exported +Y up). Ship centre at origin on the play plane z=0.
The nose points along Blender +Y = Godot -Z (forward), like every other ship.
  length ~15.9 m (bell exits y -7.25 .. range lamp y 8.62), width ~5.5 m over the
  radiator wings, height ~4.4 m (radiator tips z ~3.0 .. hopper z ~-2.0).
Hierarchy: miner_hauler (empty root) -> miner_hauler_hull, engine_glow, drill_point,
  laser_emitter_1..4 (empties, unrotated).
laser_emitter_1..4 sit on the four aperture lenses (EMITTERS at APER_Y); drill_point sits
on the combiner plate centre (FOCUS). DrillBeam draws a thin feeder from each emitter to
drill_point and the thick main beam from drill_point to the rock. Nothing animates.
engine_glow has its origin on the bell exit plane (Blender y = NOZZLE_Y), plume along
Godot local +Z (scale Z to lengthen).
Textures: one 2048 worn atlas (worn_kit / station_textures bake, kinds re-scaled to ship
size), saved as blender/textures/miner_hauler_{albedo,mr,normal}.jpg, material
"miner_hauler_hull". Emissive materials stay flat, named "miner_hauler_*".
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
from parts import ALONG_Y, V, rot  # noqa: E402

PRE = "miner_hauler"
OUT = os.path.join(common.ROOT, "assets", "models", "ships", "miner_hauler.glb")
BLEND = os.path.join(common.ROOT, "blender", "miner_hauler.blend")

ZD = -0.3            # laser axis height (below the keel line: the cockpit looks down on it)
APER_Y = 6.35        # emitter aperture plane
FOCUS = V((0.0, 8.45, ZD))   # combiner plate centre, where the four beams meet (drill_point)
HEAD_LEN = 0.8       # gimbal pivot to aperture, along each head's beam line
BENCH_Y = 5.51       # optical bench members
# Emitter apertures (x, z), laser_emitter_1..4: port upper, starboard upper, starboard
# lower, port lower. Trapezoid: the lower pair sits wider, so the four feeder beams stay
# four separate lines from the tilted top-down camera.
EMITTERS = ((-1.0, 0.3), (1.0, 0.3), (1.45, -0.9), (-1.45, -0.9))
NOZZLE_Y = -7.25
BELL_R = 0.58
BELL_LEN = 0.95
ENG_X = 0.78
ENG_Z = -0.15
CAN_X = 1.45         # ore canister centre, either side of the spine
CAN_YS = (-1.35, -2.6, -3.85)
CAN_W, CAN_L, CAN_H = 1.7, 1.1, 2.0
OPEN_CANS = ((1, -1.35), (-1, -3.85))     # (side, y) of the two open canisters
COCK_X = -0.78       # cockpit offset to port
LABELS = ["MX-14", "#CHEV", "NO STEP", "#BAR", "ORE", "14", "KEEP CLEAR", "LASER"]
ORANGE_INK = (0.6, 0.2, 0.03)

# Front body (refinery + work bay) stations: (y, w, h, chamfer, z centre)
BODY = (
    (-0.8, 2.6, 2.6, 0.55, 0.0),
    (-0.6, 3.2, 3.1, 0.65, 0.05),
    (1.3, 3.2, 3.1, 0.65, 0.05),
    (1.6, 3.4, 2.7, 0.6, -0.1),
    (3.7, 3.4, 2.7, 0.6, -0.1),
    (4.4, 2.4, 1.9, 0.5, -0.3),
)
STERN = (
    (-4.5, 2.4, 2.4, 0.5, 0.0),
    (-4.7, 2.9, 2.8, 0.6, 0.0),
    (-5.0, 2.9, 2.8, 0.6, 0.0),
    (-5.25, 2.95, 2.85, 0.62, 0.0),
    (-5.9, 2.9, 2.8, 0.6, 0.0),
    (-6.25, 2.4, 2.2, 0.5, 0.0),
)
COCKPIT = (
    (1.7, 1.0, 0.7, 0.25, 1.45),
    (1.9, 1.4, 1.1, 0.35, 1.62),
    (3.5, 1.4, 1.1, 0.35, 1.62),
    (4.15, 1.2, 0.62, 0.28, 1.4),
)

MATS = {}
DECALS = []
SCORCH = []
RNG = random.Random(14)

# Worn kinds at ship scale (process-local overrides, same scale as the dropship). The
# miner's main paint is a lighter work white so it reads apart from the military grey.
SHIP_WORN = {
    "hull": dict(big=(1.6, 1.2), plate=(0.8, 0.6),
                 tones=[(0.46, 0.46, 0.44), (0.43, 0.432, 0.425), (0.49, 0.488, 0.47),
                        (0.41, 0.415, 0.41), (0.47, 0.46, 0.44), (0.42, 0.425, 0.42)],
                 plate_var=0.06, rough=(0.55, 0.12), metal=0.05, seam_big=0.45,
                 seam_small=0.18, rivets=True, hatches=0.16, chip=(0.1, 0.1, 0.105),
                 chip_metal=0.8, chip_k=1.2, grime_k=1.0, streak_k=0.3, bleach=0.08),
    "hull2": dict(big=(1.4, 1.0), plate=(0.7, 0.5),
                  tones=[(0.16, 0.165, 0.17), (0.145, 0.15, 0.155), (0.175, 0.18, 0.18),
                         (0.135, 0.14, 0.145), (0.165, 0.16, 0.155), (0.15, 0.155, 0.165)],
                  plate_var=0.08, rough=(0.55, 0.12), metal=0.1, seam_big=0.45,
                  seam_small=0.18, rivets=True, hatches=0.12, chip=(0.30, 0.30, 0.31),
                  chip_metal=0.9, chip_k=0.9, grime_k=0.9, streak_k=0.25, bleach=0.1),
    "hull3": dict(big=(1.2, 1.2), plate=(0.6, 0.6),
                  tones=[(0.32, 0.315, 0.3), (0.3, 0.3, 0.295), (0.335, 0.33, 0.315),
                         (0.29, 0.29, 0.285), (0.31, 0.305, 0.29), (0.295, 0.295, 0.29)],
                  plate_var=0.06, rough=(0.55, 0.12), metal=0.05, seam_big=0.4,
                  seam_small=0.12, rivets=True, hatches=0.14, chip=(0.1, 0.1, 0.105),
                  chip_metal=0.8, chip_k=1.2, grime_k=1.0, streak_k=0.25, bleach=0.08),
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
    "accent": dict(big=(1.2, 0.8), plate=(0.6, 0.4),
                   tones=[(0.62, 0.21, 0.035), (0.56, 0.19, 0.03), (0.66, 0.24, 0.045),
                          (0.52, 0.18, 0.035), (0.6, 0.22, 0.04), (0.58, 0.2, 0.035)],
                   plate_var=0.06, rough=(0.55, 0.1), metal=0.0, seam_big=0.4,
                   seam_small=0.15, rivets=False, hatches=0.0, chip=(0.13, 0.13, 0.135),
                   chip_metal=0.8, chip_k=1.4, grime_k=1.1, streak_k=0.4, bleach=0.2),
    "hazard": dict(big=(1.2, 1.2), plate=(0.6, 0.6),
                   tones=[(0.42, 0.29, 0.04), (0.40, 0.28, 0.035), (0.44, 0.31, 0.045),
                          (0.38, 0.27, 0.04), (0.43, 0.30, 0.04), (0.41, 0.285, 0.04)],
                   plate_var=0.05, rough=(0.6, 0.08), metal=0.0, seam_big=0.3,
                   seam_small=0.1, rivets=False, hatches=0.0, chip=(0.12, 0.12, 0.125),
                   chip_metal=0.7, chip_k=1.8, grime_k=1.2, streak_k=0.45, bleach=0.2,
                   stripes=0.32),
    # abraded cutter steel: bright worn edges, dull flanks
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
}
st.WORN_KINDS.update(SHIP_WORN)


def build_materials():
    m = common.make_material
    MATS.clear()
    MATS["hull"] = m(f"{PRE}_paint_white", (0.46, 0.46, 0.44), roughness=0.55)
    MATS["hull2"] = m(f"{PRE}_paint_dark", (0.16, 0.165, 0.17), roughness=0.55)
    MATS["hull3"] = m(f"{PRE}_paint_patch", (0.32, 0.315, 0.3), roughness=0.55)
    MATS["dark"] = m(f"{PRE}_structure", (0.045, 0.047, 0.05), roughness=0.5, metallic=0.6)
    MATS["metal"] = m(f"{PRE}_bare_metal", (0.3, 0.3, 0.31), roughness=0.36, metallic=0.9)
    MATS["accent"] = m(f"{PRE}_orange", (0.6, 0.21, 0.035), roughness=0.55)
    MATS["hazard"] = m(f"{PRE}_hazard", (0.42, 0.29, 0.04), roughness=0.6)
    MATS["temper"] = m(f"{PRE}_temper", (0.2, 0.15, 0.2), roughness=0.33, metallic=0.92)
    MATS["radiator"] = m(f"{PRE}_radiator", (0.36, 0.365, 0.37), roughness=0.42,
                         metallic=0.2)
    MATS["ore"] = m(f"{PRE}_ore", (0.24, 0.14, 0.07), roughness=0.85)
    glow = (0.03, 0.028, 0.025)
    MATS["glass"] = m(f"{PRE}_canopy", (0.008, 0.011, 0.016), roughness=0.14,
                      emission=(0.16, 0.3, 0.4), emission_strength=0.15)
    MATS["window"] = m(f"{PRE}_window_warm", glow, roughness=0.25,
                       emission=(1.0, 0.62, 0.3), emission_strength=2.2)
    MATS["window_cool"] = m(f"{PRE}_window_cool", glow, roughness=0.25,
                            emission=(0.7, 0.82, 1.0), emission_strength=1.6)
    MATS["light"] = m(f"{PRE}_light_amber", glow, roughness=0.3,
                      emission=(1.0, 0.5, 0.12), emission_strength=5.0)
    MATS["white"] = m(f"{PRE}_light_white", glow, roughness=0.3,
                      emission=(0.9, 0.95, 1.0), emission_strength=6.0)
    MATS["nav_r"] = m(f"{PRE}_nav_red", glow, roughness=0.3,
                      emission=(1.0, 0.05, 0.03), emission_strength=7.0)
    MATS["nav_g"] = m(f"{PRE}_nav_green", glow, roughness=0.3,
                      emission=(0.1, 1.0, 0.25), emission_strength=7.0)
    MATS["lens"] = m(f"{PRE}_emitter", (0.5, 0.8, 0.9), roughness=0.2,
                     emission=(0.55, 0.9, 1.0), emission_strength=8.0)
    MATS["glow"] = m(f"{PRE}_engine_glow", (0.8, 0.95, 1.0), roughness=0.2,
                     emission=(0.65, 0.92, 1.0), emission_strength=6.0)
    for k in ("glass", "window", "window_cool", "light", "white", "nav_r", "nav_g", "lens"):
        MATS[k].use_backface_culling = False


def label(text, centre, normal, up, h, colour, opacity=0.85):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity))


def rings_of(table, x0=0.0):
    return [parts.oct_ring(y, w, h, c, x0=x0, z0=z) for y, w, h, c, z in table]


def frame(n, up=(0, 0, 1)):
    """4x4 rotation: X across, Y = up projected, Z = n (outward)."""
    n = V(n).normalized()
    u = V(up)
    if abs(u.dot(n)) > 0.95:
        u = V((0, 1, 0))
    u = (u - n * u.dot(n)).normalized()
    x = u.cross(n)
    return Matrix((x, u, n)).transposed().to_4x4()


# ---------------------------------------------------------------- hull
def build_hull():
    p = parts.PanelPart("miner_hauler_hull", MATS)
    body(p)
    conveyor(p)
    laser(p)
    cockpit(p)
    scanner(p)
    refinery(p)
    radiators(p)
    spine(p)
    for sx in (-1, 1):
        for y in CAN_YS:
            canister(p, sx, y, (sx, y) in OPEN_CANS)
    coupling(p)
    stern(p)
    engines(p)
    rcs(p)
    lights(p)
    return p


def body(p):
    """Refinery block (tall) stepping down into the work bay, tapering to the boom."""
    def bm(i, j):
        if j == 6:
            return "hull2"
        if i == 0:
            return "hull2"
        if i == 2:
            return "dark"
        if i == 4:
            return "hull2" if j in (5, 7) else "hull3"
        return "hull"
    p.loft(rings_of(BODY), "hull", mat_fn=bm)
    # orange identity band round the work bay, just behind the taper
    r0 = parts.oct_ring(3.25, 3.44, 2.74, 0.61, z0=-0.1)
    r1 = parts.oct_ring(3.55, 3.44, 2.74, 0.61, z0=-0.1)
    p.loft([r0, r1], "accent", cap=False, mat_fn=lambda i, j: "hull2" if j == 6 else "accent")
    # work bay flanks: access panels, vent grilles, hand rails, stencils
    for sx in (-1, 1):
        x = sx * 1.71
        p.box(V((x, 2.2, 0.15)), (0.05, 0.9, 0.8), "hull3", bevel=0.2)
        p.box(V((x + sx * 0.02, 2.2, 0.15)), (0.03, 0.3, 0.08), "dark", bevel=0.0)
        for k in range(5):
            p.box(V((x + sx * 0.01, 2.85 + k * 0.1, -0.55)), (0.04, 0.05, 0.45), "dark",
                  bevel=0.0)
        p.box(V((x, 3.05, -0.55)), (0.03, 0.62, 0.55), "hull2", bevel=0.0)
        for z in (0.85, -0.85):
            p.beam(V((x + sx * 0.08, 1.8, z)), V((x + sx * 0.08, 3.1, z)), 0.04, 0.04,
                   "hazard")
            for y in (1.85, 3.05):
                p.beam(V((x, y, z)), V((x + sx * 0.1, y, z)), 0.04, 0.04, "metal")
        label("MX-14", V((x + sx * 0.03, 2.25, -0.45)), (sx, 0, 0), (0, 0, 1), 0.28,
              wk.INK_DARK, 0.9)
    # top deck of the work bay (starboard of the cockpit): hatch and grip strip
    p.box(V((0.75, 2.4, 1.26)), (0.8, 0.9, 0.06), "hull3", bevel=0.2)
    p.box(V((0.75, 2.4, 1.29)), (0.12, 0.5, 0.03), "dark", bevel=0.0)
    label("NO STEP", V((0.85, 3.3, 1.26)), (0, 0, 1), (0, 1, 0), 0.16, wk.INK_DARK, 0.8)


def conveyor(p):
    """Spall conveyor: keel housing from the catch hopper throat back into the crusher."""
    z = -1.62
    p.box(V((0, 3.2, z)), (0.62, 4.2, 0.5), "hull2", bevel=0.15)
    p.box(V((0, 3.2, z - 0.26)), (0.3, 4.0, 0.06), "dark", bevel=0.0)
    for k in range(9):
        y = 1.4 + k * 0.48
        p.box(V((0, y, z)), (0.7, 0.08, 0.58), "dark", bevel=0.0)
    # entry into the refinery belly
    p.box(V((0, 0.9, -1.55)), (0.9, 0.7, 0.42), "dark", bevel=0.15)
    p.hazard(-0.4, 0.4, 0.12, -0.02, 0.02,
             matrix=Matrix.Translation((0, 1.2, -1.78)) @ rot(rx=math.pi),
             pitch=0.15, cols=("hazard", "dark"))
    SCORCH.append((0.0, 6.0, -1.8, 0.9))


# ---------------------------------------------------------------- quad-line mining laser
def head_axis(x, z):
    """Emitter aperture A, unit beam direction d (towards FOCUS) and gimbal pivot P."""
    a = V((x, APER_Y, z))
    d = (FOCUS - a).normalized()
    return a, d, a - d * HEAD_LEN


def head_frame(d, sx):
    """Rotation with Z along d, plus the across / outboard / up unit vectors of a head."""
    q = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    across = d.cross(V((0, 0, 1))).normalized()
    out_v = across if across.x * sx > 0 else -across
    up_v = across.cross(d).normalized()
    if up_v.z < 0:
        up_v = -up_v
    return q, across, out_v, up_v


def catch_hopper(p):
    """Spall intake under the bench: the slow core of the chip cone falls in here."""
    p.loft([parts.oct_ring(5.25, 0.62, 0.5, 0.12, z0=-1.62),
            parts.oct_ring(5.75, 1.5, 0.7, 0.18, z0=-1.68),
            parts.oct_ring(6.2, 1.9, 0.8, 0.2, z0=-1.72),
            parts.oct_ring(6.2, 1.7, 0.6, 0.15, z0=-1.72),
            parts.oct_ring(5.85, 1.5, 0.5, 0.12, z0=-1.72)], "dark",
           mat_fn=lambda i, j: ("hull2", "hull2", "hazard", "dark")[min(i, 3)])
    for k in range(5):
        x = -0.6 + k * 0.3
        parts.strut(p, V((x, 6.12, -2.0)), V((x, 6.12, -1.44)), 0.05, 0.05, "metal",
                    up=V((0, 1, 0)))
    for sx in (-1, 1):
        p.box(V((sx * 0.85, 6.22, -1.4)), (0.08, 0.06, 0.08), "light", bevel=0.0)


def laser_bay(p):
    """Housing for the pump drivers and fibre runs; its front face is the spall plate."""
    p.loft([parts.oct_ring(4.4, 2.4, 1.9, 0.5, z0=ZD),
            parts.oct_ring(5.3, 2.3, 1.8, 0.48, z0=ZD),
            parts.oct_ring(5.4, 2.1, 1.6, 0.4, z0=ZD)], "hull",
           mat_fn=lambda i, j: "dark" if i == 1 else ("hull2" if j == 6 else "hull"))
    p.loft([parts.oct_ring(4.62, 2.39, 1.89, 0.5, z0=ZD),
            parts.oct_ring(4.8, 2.38, 1.88, 0.5, z0=ZD)], "accent", cap=False,
           mat_fn=lambda i, j: "hull2" if j == 6 else "accent")
    p.box(V((0, 5.41, ZD)), (1.7, 0.03, 1.2), "hull2", bevel=0.0)
    for zc in (ZD + 0.5, ZD - 0.5):
        p.hazard(-0.8, 0.8, 0.12, -0.02, 0.0,
                 matrix=Matrix.Translation((0, 5.43, zc)) @ parts.FRONT,
                 pitch=0.2, cols=("hazard", "dark"))
    label("KEEP CLEAR", V((0, 5.43, ZD - 0.2)), (0, 1, 0), (0, 0, 1), 0.12, wk.INK_DARK, 0.9)
    SCORCH.append((0.0, 5.45, ZD, 1.3))
    for y in (4.7, 5.1):
        p.box(V((0, y, -1.29)), (0.36, 0.1, 0.22), "dark", bevel=0.0)


def power_feed(p):
    """Reactor power to the laser: spine bus, deck conduits, the pump power cabinet."""
    for sx in (-1, 1):
        parts.pipe(p, V((sx * 0.16, -4.5, -0.05)), V((sx * 0.16, -0.8, -0.05)), 0.09, "dark",
                   segs=8)
    for y in (-4.1, -3.2, -2.0, -1.0):
        p.box(V((0, y, -0.05)), (0.5, 0.08, 0.24), "hazard", bevel=0.0)
    p.box(V((0.2, 1.5, 1.4)), (0.5, 0.3, 0.3), "dark", bevel=0.2)
    for x in (0.12, 0.28):
        pts = (V((x, 1.65, 1.31)), V((x, 3.7, 1.31)), V((x, 4.4, 0.72)), V((x, 4.5, 0.72)))
        for a, b in zip(pts, pts[1:]):
            parts.pipe(p, a, b, 0.055, "dark", segs=6)
    for y in (2.2, 3.0, 3.55):
        p.box(V((0.2, y, 1.31)), (0.32, 0.06, 0.13), "hazard", bevel=0.0)
    p.box(V((0, 4.9, 0.73)), (0.9, 0.8, 0.22), "hull2", bevel=0.15)
    for k in range(5):
        p.box(V((0, 4.6 + k * 0.15, 0.87)), (0.8, 0.04, 0.07), "dark", bevel=0.0)
    label("LASER", V((0.3, 4.9, 0.85)), (0, 0, 1), (0, 1, 0), 0.12, wk.INK_DARK, 0.9)
    for sx in (-1, 1):
        parts.pipe(p, V((sx * 0.45, 4.9, 0.72)), V((sx * 1.15, 4.9, 0.56)), 0.045, "dark",
                   segs=6)


def gain_module(p, x, z, sx):
    """Fibre-amplifier can: the lasing medium of one line, cooled, with pump windows."""
    _, _, piv = head_axis(x, z)
    cx, cz = piv.x, piv.z
    p.cyl(V((cx, 4.95, cz)), 0.22, 0.22, 1.0, "hull", segs=12, axis_rot=ALONG_Y)
    p.cyl(V((cx, 4.45, cz)), 0.24, 0.24, 0.08, "dark", segs=12, axis_rot=ALONG_Y)
    for y in (4.62, 5.12):
        p.torus(V((cx, y, cz)), 0.225, 0.03, "dark", segs=10, minor_segs=3,
                matrix=rot(rx=math.pi / 2))
    p.cyl(V((cx, 5.3, cz)), 0.226, 0.226, 0.08, "accent", segs=12, axis_rot=ALONG_Y)
    upper = z > ZD
    if upper:
        p.box(V((cx, 4.87, cz + 0.21)), (0.07, 0.62, 0.04), "window_cool", bevel=0.0)
    for y in (4.75, 5.2):
        if upper:
            p.box(V((sx * 0.985, y, 0.5)), (0.36, 0.14, 0.16), "dark", bevel=0.0)
        else:
            p.box(V((sx * 1.27, y, cz)), (0.86, 0.14, 0.16), "dark", bevel=0.0)


def laser_chiller(p, sx):
    """Heat exchanger between a side's two gain modules, feeding the radiator wing."""
    p.box(V((sx * 1.45, 4.95, ZD)), (0.6, 0.8, 0.6), "hull2", bevel=0.15)
    for y in (4.7, 5.2):
        parts.pipe(p, V((sx * 1.45, y, 0.0)), V((sx * 1.36, y, 0.29)), 0.035, "metal", segs=5)
        parts.pipe(p, V((sx * 1.6, y, -0.6)), V((sx * 1.8, y, -0.88)), 0.035, "metal", segs=5)


def radiator_wing(p, sx):
    """The laser's own flat radiator, edge-on to the spall cone."""
    parts.radiator(p, V((sx * 2.25, 4.75, ZD)), 1.1, 0.96, (0, 0, 1), "radiator", "metal",
                   ribs=5, t=0.05)
    parts.pipe(p, V((sx * 1.79, 4.2, ZD)), V((sx * 1.79, 5.3, ZD)), 0.04, "metal", segs=6)
    p.box(V((sx * 1.5, 4.3, ZD)), (0.6, 0.12, 0.12), "dark", bevel=0.0)
    p.beam(V((sx * 1.77, 5.32, ZD)), V((sx * 2.75, 5.32, ZD)), 0.06, 0.07, "hazard")
    p.beam(V((sx * 2.76, 4.2, ZD)), V((sx * 2.76, 5.32, ZD)), 0.05, 0.08, "dark")


def optical_bench(p):
    """Trapezoid bench holding the four gimbals at fixed spacing, floods, seed unit."""
    piv = [head_axis(x, z)[2] for x, z in EMITTERS]
    up = [q for q in piv if q.z > ZD]
    lo = [q for q in piv if q.z <= ZD]
    ux, uz = max(q.x for q in up), up[0].z
    lx, lz = max(q.x for q in lo), lo[0].z
    y = BENCH_Y
    p.beam(V((-ux, y, uz)), V((ux, y, uz)), 0.22, 0.22, "hull2")
    p.beam(V((-lx, y, lz)), V((lx, y, lz)), 0.22, 0.22, "hull2")
    for sx in (-1, 1):
        p.beam(V((sx * lx, y, lz)), V((sx * ux, y, uz)), 0.22, 0.22, "hull2", up=V((0, 1, 0)))
    for q in piv:
        p.box(V((q.x, 5.5, q.z)), (0.46, 0.3, 0.46), "dark", bevel=0.15)
    for x0, x1 in ((-1.15, -0.28), (0.28, 1.15)):
        p.hazard(x0, x1, 0.18, -0.01, 0.01, matrix=Matrix.Translation((0, y, uz + 0.115)),
                 pitch=0.25, cols=("hazard", "dark"))
    for sx in (-1, 1):
        for zc in (uz, lz):
            p.box(V((sx * 0.75, 5.69, zc)), (0.3, 0.14, 0.2), "dark", bevel=0.0)
            p.box(V((sx * 0.75, 5.765, zc)), (0.22, 0.01, 0.13), "white", bevel=0.0)
    p.box(V((0, y, uz + 0.19)), (0.5, 0.26, 0.24), "hull2", bevel=0.15)
    p.cyl(V((0.17, 5.645, uz + 0.19)), 0.055, 0.055, 0.02, "window_cool", segs=10,
          axis_rot=ALONG_Y)


def emitter_head(p, x, z, sx):
    """One small laser output head: connector, gimbal, cooled collimator, optics,
    cover-slide drawer, iris shutter, glowing aperture lens (front face at A)."""
    a, d, piv = head_axis(x, z)
    q, across, out_v, up_v = head_frame(d, sx)
    p.tube(piv - d * 0.26, piv - d * 0.02, 0.13, 0.15, "dark", segs=10)
    p.torus(piv, 0.24, 0.04, "metal", segs=12, minor_segs=4, matrix=q)
    for s in (-1, 1):
        p.box(piv + across * s * 0.27, (0.1, 0.1, 0.1), "dark", bevel=0.0)
    p.tube(piv, piv + d * 0.5, 0.19, 0.19, "hull", segs=10)
    for t in (0.14, 0.3):
        p.torus(piv + d * t, 0.2, 0.028, "dark", segs=10, minor_segs=3, matrix=q)
    p.tube(piv + d * 0.42, piv + d * 0.48, 0.2, 0.2, "accent", segs=10)
    p.tube(piv + d * 0.5, piv + d * 0.66, 0.19, 0.16, "metal", segs=10)
    p.box(piv + d * 0.58 + out_v * 0.19, (0.07, 0.1, 0.14), "hull3", r=frame(d, (0, 0, 1)),
          bevel=0.0)
    p.tube(piv + d * 0.66, piv + d * 0.74, 0.18, 0.18, "dark", segs=10)
    p.tube(piv + d * 0.74, piv + d * 0.77, 0.17, 0.17, "hazard", segs=10)
    p.tube(piv + d * 0.77, piv + d * 0.795, 0.12, 0.12, "dark", segs=10)
    p.tube(piv + d * 0.795, a, 0.09, 0.09, "lens", segs=10)
    for s in (-1, 1):
        parts.pipe(p, piv - d * 0.1 + up_v * 0.21 + across * s * 0.07,
                   piv + d * 0.62 + up_v * 0.18 + across * s * 0.07, 0.025, "metal", segs=5)
    p.box(piv - d * 0.12 + up_v * 0.2, (0.07, 0.07, 0.07), "light", bevel=0.0)
    for base, tip in ((V((piv.x, 5.65, piv.z + 0.2)), piv + d * 0.32 + up_v * 0.19),
                      (V((piv.x + sx * 0.2, 5.65, piv.z)), piv + d * 0.32 + out_v * 0.19)):
        mid = base.lerp(tip, 0.55)
        p.tube(base, mid, 0.04, 0.04, "dark", segs=6)
        p.tube(mid, tip, 0.025, 0.025, "metal", segs=6)
    SCORCH.append((a.x, a.y, a.z, 0.3))


def combiner_support(p):
    """One narrow spar on top and an A-frame below carry the combiner ring, both in the
    x = 0 plane where the feeder beams only meet at the focus."""
    p.beam(V((0, 5.64, 0.66)), V((0, 8.455, 0.34)), 0.14, 0.16, "hull2")
    p.beam(V((0, 5.9, 0.715)), V((0, 8.2, 0.454)), 0.1, 0.02, "hazard")
    for s in (-1, 1):
        parts.pipe(p, V((s * 0.1, 5.64, 0.66)), V((s * 0.1, 8.40, 0.35)), 0.03, "metal", segs=5)
    p.box(V((0, 8.455, 0.34)), (0.24, 0.26, 0.14), "dark", bevel=0.15)
    p.box(V((0, 8.6, 0.34)), (0.1, 0.04, 0.08), "light", bevel=0.0)
    for sx in (-1, 1):
        p.beam(V((sx * 0.32, 5.62, -1.083)), V((0, 8.455, -0.95)), 0.1, 0.12, "hull3")
    p.beam(V((-0.21, 6.6, -1.035)), V((0.21, 6.6, -1.035)), 0.06, 0.06, "dark")
    p.box(V((0, 8.455, -0.94)), (0.24, 0.26, 0.14), "dark", bevel=0.15)


def beam_combiner(p):
    """The focus: an edge-cooled 2x2 diffractive combiner plate in an armoured ring.
    Four beams hit its back face, one big beam leaves its front; a cover slide takes the
    spall."""
    prof = [(0.34, 0.0), (0.52, 0.0), (0.58, 0.05), (0.58, 0.2), (0.52, 0.25), (0.34, 0.25),
            (0.34, 0.0)]
    p.lathe(prof, 20, lambda i, j: "accent" if j == 2 else ("metal" if j == 5 else "dark"),
            matrix=Matrix.Translation((0, FOCUS.y - 0.12, ZD)) @ ALONG_Y)
    p.cyl(FOCUS, 0.34, 0.34, 0.04, "glass", segs=20, axis_rot=ALONG_Y)
    for s in (-1, 1):
        p.cyl(FOCUS + V((0, s * 0.024, 0)), 0.12, 0.12, 0.006, "lens", segs=12,
              axis_rot=ALONG_Y)
    p.cyl(V((0, FOCUS.y + 0.115, ZD)), 0.34, 0.34, 0.015, "glass", segs=20, axis_rot=ALONG_Y)
    for sx in (-1, 1):
        p.box(V((sx * 0.62, FOCUS.y + 0.005, ZD)), (0.06, 0.08, 0.06), "window_cool", bevel=0.0)
    SCORCH.append((0.0, FOCUS.y + 0.15, ZD, 0.6))


def laser(p):
    """The whole quad-line combiner laser, power feed to focus ring."""
    catch_hopper(p)
    laser_bay(p)
    power_feed(p)
    optical_bench(p)
    for sx in (-1, 1):
        laser_chiller(p, sx)
        radiator_wing(p, sx)
    for x, z in EMITTERS:
        sx = 1 if x > 0 else -1
        gain_module(p, x, z, sx)
        emitter_head(p, x, z, sx)
    combiner_support(p)
    beam_combiner(p)


def cockpit(p):
    """Armoured cab offset to port and raised: slit windows on the front slope behind a
    debris grille, side ports, roof beacon and whip antenna."""
    rings = rings_of(COCKPIT, x0=COCK_X)

    def cm(i, j):
        if i == 2 and j in (1, 2, 3):
            return "glass"
        if i == 0:
            return "hull2"
        return "hull2" if j in (5, 6, 7) else "hull"
    p.loft(rings, "hull", mat_fn=cm)
    # frame mullions over the front slope glass
    for j in (1, 2, 3, 4):
        a, b = rings[2][j], rings[3][j]
        n = V((0, 0.4, 1)).normalized()
        parts.strut(p, a + n * 0.03, b + n * 0.03, 0.07, 0.05, "hull2")
    # debris grille: vertical bars over the slope plus two cross rails, on standoffs
    top_a, top_b = V((0, 3.45, 2.26)), V((0, 4.25, 1.8))
    for k in range(7):
        x = COCK_X - 0.54 + k * 0.18
        parts.strut(p, top_a + V((x, 0, 0)), top_b + V((x, 0, 0)), 0.05, 0.05, "dark")
    for t in (0.15, 0.55, 0.92):
        c = top_a.lerp(top_b, t)
        parts.strut(p, c + V((COCK_X - 0.62, 0, 0.02)), c + V((COCK_X + 0.62, 0, 0.02)), 0.06,
                    0.06, "metal")
    for sx in (-1, 1):
        p.beam(V((COCK_X + sx * 0.6, 3.5, 2.17)), top_a + V((COCK_X + sx * 0.6, 0, 0)), 0.06,
               0.06, "metal")
        p.beam(V((COCK_X + sx * 0.6, 4.12, 1.72)), top_b + V((COCK_X + sx * 0.6, 0, 0)), 0.06,
               0.06, "metal")
    # side ports, warm light inside
    for sx in (-1, 1):
        x = COCK_X + sx * 0.71
        for y in (2.35, 2.85):
            parts.window(p, V((x, y, 1.72)), (sx, 0, 0), (0, 0, 1), 0.28, 0.16, "window")
    # roof: amber rotating beacon, whip antenna, hull number, armoured hatch
    p.cyl(V((COCK_X, 2.2, 2.2)), 0.16, 0.16, 0.06, "dark", segs=10)
    p.cyl(V((COCK_X, 2.2, 2.3)), 0.12, 0.1, 0.16, "light", segs=10)
    p.tube(V((COCK_X - 0.45, 2.0, 2.15)), V((COCK_X - 0.55, 1.6, 3.2)), 0.025, 0.012,
           "dark", segs=4)
    p.box(V((COCK_X + 0.15, 2.85, 2.19)), (0.6, 0.6, 0.06), "hull3", bevel=0.2)
    label("14", V((COCK_X + 0.15, 2.85, 2.23)), (0, 0, 1), (0, 1, 0), 0.38, ORANGE_INK, 0.95)
    # cab-to-deck brace
    p.box(V((COCK_X, 1.85, 1.3)), (1.2, 0.3, 0.3), "dark", bevel=0.2)


def scanner(p):
    """Ore scanner: mast on the starboard deck with a dish aimed at the cut and a lidar."""
    base = V((0.95, 3.75, 1.25))
    p.cyl(base + V((0, 0, 0.05)), 0.28, 0.32, 0.12, "dark", segs=12)
    p.tube(base, base + V((0, 0, 0.75)), 0.08, 0.07, "metal", segs=8)
    head = base + V((0, 0, 0.8))
    p.box(head, (0.3, 0.26, 0.22), "hull2", bevel=0.2)
    parts.dish(p, head + V((0, 0.2, 0.05)), 0.42, V((0, 1, -0.45)), "hull", "dark",
               depth=0.18, segs=14)
    p.sphere(head + V((0.32, -0.05, 0.05)), 0.12, "glass", segs=10, rings=6)
    p.box(head + V((0, -0.16, 0.0)), (0.08, 0.04, 0.06), "nav_g", bevel=0.0)


def refinery(p):
    """Crusher intake hopper on top, side vents, tailings chute, cool-lit ports."""
    # intake hopper on the roof where the elevator from the conveyor arrives
    p.loft([parts.oct_ring(0.0, 0.8, 0.2, 0.05, z0=1.62),
            parts.oct_ring(0.05, 1.0, 0.5, 0.1, z0=1.75),
            parts.oct_ring(0.95, 1.0, 0.5, 0.1, z0=1.75),
            parts.oct_ring(1.0, 0.8, 0.2, 0.05, z0=1.62)], "hull3",
           mat_fn=lambda i, j: "dark" if i == 1 else "hull3")
    p.box(V((0, 0.5, 2.02)), (0.7, 0.6, 0.04), "dark", bevel=0.0)
    p.hazard(-0.45, 0.45, 0.12, -0.02, 0.02, matrix=Matrix.Translation((0, 1.0, 1.95)),
             pitch=0.2, cols=("hazard", "dark"))
    # elevator casing up the front face of the refinery (from the conveyor)
    p.box(V((0.95, 1.42, 0.2)), (0.5, 0.25, 2.6), "hull2", bevel=0.15)
    for k in range(5):
        p.box(V((0.95, 1.55, -0.8 + k * 0.5)), (0.56, 0.05, 0.08), "dark", bevel=0.0)
    for sx in (-1, 1):
        x = sx * 1.61
        # big louvred vents (crusher dust extraction) and a cool-lit inspection port
        for k in range(6):
            p.box(V((x + sx * 0.01, -0.15 + k * 0.12, 0.6)), (0.05, 0.06, 0.7), "dark",
                  bevel=0.0)
        p.box(V((x, 0.15, 0.6)), (0.03, 0.85, 0.85), "hull2", bevel=0.0)
        parts.window(p, V((x + sx * 0.01, 0.95, 0.65)), (sx, 0, 0), (0, 0, 1), 0.22, 0.22,
                     "window_cool")
        p.box(V((x, 0.3, -0.7)), (0.05, 1.5, 0.5), "hull3", bevel=0.2)
        # orange band
        p.box(V((x + sx * 0.005, -0.45, 0.05)), (0.03, 0.18, 3.0), "accent", bevel=0.0)
    # tailings chute (starboard belly): slag goes down, away from the hold
    c = V((1.1, -0.1, -1.55))
    p.box(c, (0.55, 0.7, 0.3), "hull2", bevel=0.15)
    p.tube(c + V((0, 0, -0.1)), c + V((0.25, -0.15, -0.7)), 0.24, 0.3, "dark", segs=10)
    p.torus(c + V((0.25, -0.15, -0.7)), 0.3, 0.04, "hazard", segs=12, minor_segs=4)
    SCORCH.append((1.35, -0.25, -2.0, 0.8))


def radiators(p):
    """Two V radiators on the refinery roof with coolant headers, plus reactor lines."""
    ang = math.radians(22)
    L, H, y_c = 2.1, 1.75, 0.3
    for sx in (-1, 1):
        r = rot(ry=sx * ang)
        base = V((sx * 0.9, y_c, 1.55))
        up = V((sx * math.sin(ang), 0, math.cos(ang)))
        n = V((math.cos(ang), 0, -sx * math.sin(ang))) * sx
        c = base + up * (H / 2 + 0.1)
        p.box(c, (0.06, L, H), "radiator", r=r, bevel=0.0)
        for k in range(7):
            y = -L / 2 + L * (k + 0.5) / 7
            for s in (1, -1):
                p.box(c + V((0, y, 0)) + n * 0.04 * s, (0.04, 0.05, H * 0.96), "metal",
                      r=r, bevel=0.0)
        # top edge frame, header pipe at the root, hinge yokes
        p.box(c + up * (H / 2 + 0.03), (0.1, L + 0.05, 0.06), "dark", r=r, bevel=0.0)
        p.tube(base + up * 0.1 + V((0, -L / 2, 0)), base + up * 0.1 + V((0, L / 2, 0)), 0.07,
               0.07, "metal", segs=8)
        for y in (-L / 2 + 0.3, L / 2 - 0.3):
            p.box(base + V((0, y, 0.0)), (0.25, 0.2, 0.25), "dark", bevel=0.2)
        p.box(c + up * (H / 2 - 0.05) + V((0, L / 2 - 0.05, 0)), (0.1, 0.1, 0.08), "white",
              r=r, bevel=0.0)
    # coolant lines from the reactor forward along the spine to the headers
    for sx in (-1, 1):
        a = V((sx * 0.25, -4.6, 1.5))
        b = V((sx * 0.25, -0.95, 0.62))
        parts.pipe(p, a, V((sx * 0.25, -4.2, 0.62)), 0.06, "accent", segs=6)
        parts.pipe(p, V((sx * 0.25, -4.2, 0.62)), b, 0.06, "accent", segs=6)
        parts.pipe(p, b, V((sx * 0.25, -0.75, 1.62)), 0.06, "accent", segs=6)
        parts.pipe(p, V((sx * 0.25, -0.75, 1.62)), V((sx * 0.9, -0.75, 1.62)), 0.06, "accent",
                   segs=6)


def spine(p):
    """Open spine truss between the refinery and the stern, ore manifold on top."""
    parts.box_truss(p, -4.55, -0.75, 0.5, 0.5, 4, "hull2", "dark", chord=0.2, brace=0.1)
    # keel plate under the truss (spine stiffener + walkway)
    p.box(V((0, -2.65, -0.56)), (0.7, 3.8, 0.08), "dark", bevel=0.0)
    # ore manifold: main line from the refinery along the top, drops into every canister
    for sx in (-1, 1):
        x = sx * 0.32
        parts.pipe(p, V((x, -0.7, 0.68)), V((x, -4.2, 0.68)), 0.09, "metal", segs=8)
        for y in CAN_YS:
            j = V((x, y, 0.68))
            p.sphere(j, 0.13, "dark", segs=8, rings=4)
            parts.pipe(p, j, V((sx * 0.68, y, 0.68)), 0.07, "metal", segs=6)
            p.box(V((sx * 0.5, y, 0.68)), (0.1, 0.18, 0.18), "hazard", bevel=0.0)
        p.box(V((x, -0.85, 0.68)), (0.3, 0.2, 0.3), "dark", bevel=0.2)


def canister(p, sx, y, open_):
    """Ore canister on a clamp cradle; open ones show the hatch up and ore heaped in."""
    x = sx * CAN_X
    hw, hl, hh = CAN_W, CAN_L, CAN_H
    rings = [parts.oct_ring(y - hl / 2, hw - 0.2, hh - 0.2, 0.25, x0=x),
             parts.oct_ring(y - hl / 2 + 0.08, hw, hh, 0.32, x0=x),
             parts.oct_ring(y + hl / 2 - 0.08, hw, hh, 0.32, x0=x),
             parts.oct_ring(y + hl / 2, hw - 0.2, hh - 0.2, 0.25, x0=x)]

    def cm(i, j):
        if i == 1:
            return "hull" if (y, sx) != (CAN_YS[1], -1) else "hull3"
        return "hull2"
    p.loft(rings, "hull2", mat_fn=cm)
    # end frames and a middle reinforcing rib
    for yy, mat in ((y - hl / 2 + 0.12, "dark"), (y + hl / 2 - 0.12, "dark"), (y, "accent")):
        w = 0.07 if mat == "accent" else 0.1
        p.loft([parts.oct_ring(yy - w, hw + 0.06, hh + 0.06, 0.34, x0=x),
                parts.oct_ring(yy + w, hw + 0.06, hh + 0.06, 0.34, x0=x)], mat)
    # outer face: stencil, inspection lamp, hazard skirt
    xo = x + sx * (hw / 2 + 0.035)
    label("ORE", V((xo, y, 0.25)), (sx, 0, 0), (0, 0, 1), 0.22, wk.INK_DARK, 0.9)
    p.box(V((xo, y, -0.75)), (0.04, hl - 0.35, 0.12), "hazard", bevel=0.0)
    p.box(V((xo, y + 0.3, 0.75)), (0.04, 0.1, 0.08), "light", bevel=0.0)
    # cradle: two clamp arms from the spine chords, hazard pads where they bite
    for z in (0.5, -0.5):
        p.beam(V((sx * 0.5, y, z)), V((x - sx * (hw / 2 - 0.05), y, z)), 0.16, 0.2, "dark")
        p.box(V((x - sx * (hw / 2 + 0.02), y, z)), (0.08, 0.36, 0.3), "hazard", bevel=0.0)
    # top: hatch (closed) or open hatch with ore heaped in the mouth
    top = hh / 2
    if not open_:
        p.box(V((x, y, top + 0.02)), (hw - 0.6, hl - 0.4, 0.06), "hull3", bevel=0.2)
        p.box(V((x + sx * 0.25, y, top + 0.06)), (0.06, 0.2, 0.04), "metal", bevel=0.0)
        return
    p.box(V((x, y, top + 0.01)), (hw - 0.55, hl - 0.35, 0.04), "dark", bevel=0.0)
    for k in range(13):
        c = V((x + RNG.uniform(-0.42, 0.42), y + RNG.uniform(-0.24, 0.24),
               top + RNG.uniform(0.04, 0.2)))
        p.rock(c, RNG.uniform(0.13, 0.24), "ore", RNG)
    hinge = V((x + sx * (hw / 2 - 0.28), y, top + 0.04))
    lid = rot(ry=-sx * math.radians(110))
    p.box(hinge + lid @ V((-sx * (hw - 0.6) / 2, 0, 0.0)), (hw - 0.6, hl - 0.4, 0.06), "hull3",
          r=lid, bevel=0.2)
    p.cyl(hinge, 0.05, 0.05, hl - 0.4, "metal", segs=6, axis_rot=ALONG_Y)


def coupling(p):
    """Belly ore-transfer coupling: the stations' pads clamp here to drain the hold."""
    c = V((0, -2.6, -0.62))
    p.cyl(c + V((0, 0, -0.2)), 0.55, 0.6, 0.35, "hull2", segs=16)
    p.cyl(c + V((0, 0, -0.45)), 0.42, 0.42, 0.16, "metal", segs=16)
    p.cyl(c + V((0, 0, -0.55)), 0.28, 0.28, 0.06, "dark", segs=16)
    p.torus(c + V((0, 0, -0.38)), 0.62, 0.05, "hazard", segs=16, minor_segs=4)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        p.box(c + V((math.cos(a) * 0.72, math.sin(a) * 0.72, -0.3)), (0.12, 0.12, 0.08),
              "light", bevel=0.0)
    for sy in (-1, 1):
        p.box(c + V((0, sy * 1.3, 0.0)), (0.9, 0.18, 0.12), "dark", bevel=0.0)


def stern(p):
    """Engineering section: hull, reactor drum, propellant spheres, stern stencils."""
    def sm(i, j):
        if i == 2:
            return "accent" if j != 6 else "hull2"
        if i == 0:
            return "dark"
        return "hull2" if j in (5, 6, 7) else "hull"
    p.loft(rings_of(STERN), "hull", mat_fn=sm)
    for sx in (-1, 1):
        x = sx * 1.46
        p.box(V((x, -5.55, 0.35)), (0.04, 0.45, 0.6), "hull3", bevel=0.2)
        for k in range(4):
            p.box(V((x + sx * 0.01, -5.75 + k * 0.12, -0.65)), (0.04, 0.05, 0.5), "dark",
                  bevel=0.0)
    label("MX-14", V((1.49, -5.55, 0.95)), (1, 0, 0), (0, 0, 1), 0.2, ORANGE_INK, 0.9)
    # reactor drum: banded, shielded, with a hazard collar and a cooling cap
    rc = V((0, -5.3, 1.85))
    p.cyl(rc, 0.6, 0.6, 1.5, "hull3", segs=18, axis_rot=ALONG_Y)
    for y in (-0.55, 0.0, 0.55):
        p.torus(rc + V((0, y, 0)), 0.62, 0.045, "dark", segs=18, minor_segs=4,
                matrix=rot(rx=math.pi / 2))
    p.cyl(rc + V((0, 0.82, 0)), 0.48, 0.4, 0.15, "metal", segs=18, axis_rot=ALONG_Y)
    p.cyl(rc + V((0, -0.82, 0)), 0.5, 0.45, 0.15, "dark", segs=18, axis_rot=ALONG_Y)
    p.cyl(rc + V((0, 0.28, 0)), 0.63, 0.63, 0.2, "hazard", segs=18, axis_rot=ALONG_Y)
    for sx in (-1, 1):
        p.box(rc + V((sx * 0.42, 0.0, -0.45)), (0.18, 1.2, 0.3), "dark", bevel=0.2)
    # propellant spheres either side, strapped, with feed lines to the thrust block
    for sx in (-1, 1):
        c = V((sx * 1.75, -5.25, -0.65))
        p.sphere(c, 0.78, "hull", segs=18, rings=10)
        p.torus(c, 0.79, 0.04, "dark", segs=18, minor_segs=4)
        p.torus(c, 0.79, 0.04, "dark", segs=18, minor_segs=4, matrix=rot(rx=math.pi / 2))
        p.beam(c + V((-sx * 0.6, 0, 0.3)), V((sx * 1.2, -5.25, 0.0)), 0.12, 0.12, "dark")
        p.beam(c + V((-sx * 0.6, 0, -0.35)), V((sx * 1.2, -5.25, -0.9)), 0.12, 0.12, "dark")
        parts.pipe(p, c + V((0, -0.7, 0)), V((sx * 1.0, -6.1, -0.4)), 0.05, "metal", segs=5)
        p.box(c + V((sx * 0.6, 0, 0.3)), (0.08, 0.3, 0.14), "accent", bevel=0.0)
        SCORCH.append((c.x, c.y - 0.6, c.z, 0.5))


def engines(p):
    """Thrust block: chamfered frame, two gimballed bells, actuators, hazard edge."""
    rings = [parts.oct_ring(-6.2, 2.4, 1.7, 0.45, z0=ENG_Z),
             parts.oct_ring(-6.35, 2.9, 1.95, 0.5, z0=ENG_Z),
             parts.oct_ring(-6.75, 2.8, 1.8, 0.45, z0=ENG_Z)]
    p.loft(rings, "hull2", mat_fn=lambda i, j: "dark" if i == 1 else "hull2")
    p.hazard(-1.3, 1.3, 0.16, -0.02, 0.02,
             matrix=Matrix.Translation((0, -6.77, ENG_Z + 0.78)) @ rot(rx=math.pi / 2),
             pitch=0.28, cols=("hazard", "dark"))
    for sx in (-1, 1):
        x = sx * ENG_X
        p.cyl(V((x, -6.8, ENG_Z)), 0.5, 0.5, 0.14, "metal", segs=16, axis_rot=ALONG_Y)
        p.cyl(V((x, -6.9, ENG_Z)), 0.42, 0.4, 0.1, "dark", segs=16, axis_rot=ALONG_Y)
        parts.bell(p, NOZZLE_Y, BELL_R, BELL_LEN - 0.4, "temper", "dark", x=x, z=ENG_Z,
                   segs=20)
        p.torus(V((x, NOZZLE_Y + 0.1, ENG_Z)), BELL_R * 0.97, 0.03, "metal", segs=20,
                minor_segs=4, matrix=rot(rx=math.pi / 2))
        for a in (0.6, 2.4):
            d = V((math.cos(a) * sx, 0, math.sin(a)))
            parts.pipe(p, V((x, -6.75, ENG_Z)) + d * 0.52, V((x, -7.05, ENG_Z)) + d * 0.42,
                       0.04, "metal", segs=5)
        SCORCH.append((x, -6.9, ENG_Z, 0.9))


def rcs(p):
    """RCS quads at the four corners: fine station keeping next to a rock."""
    for sx in (-1, 1):
        for c, out in (((sx * 1.62, 1.75, 1.15), (sx, 0, 0.6)),
                       ((sx * 1.62, 3.55, -1.15), (sx, 0, -0.6)),
                       ((sx * 1.36, -6.0, 1.3), (sx, 0, 0.5)),
                       ((sx * 1.36, -6.0, -1.3), (sx, 0, -0.5))):
            parts.rcs_quad(p, c, out, "hull2", "metal", s=0.26)


def lights(p):
    """Nav lights on the outer canisters, strobes at the stern, docking lamps."""
    for sx in (-1, 1):
        p.box(V((sx * (CAN_X + CAN_W / 2 + 0.05), CAN_YS[0] + 0.4, 0.9)), (0.08, 0.16, 0.08),
              "nav_g" if sx > 0 else "nav_r", bevel=0.0)
        p.box(V((sx * (CAN_X + CAN_W / 2 + 0.05), CAN_YS[-1] - 0.4, 0.9)), (0.08, 0.16, 0.08),
              "white", bevel=0.0)
    p.box(V((0, -6.3, 1.12)), (0.2, 0.12, 0.08), "light", bevel=0.0)
    p.box(V((0, -6.3, -1.12)), (0.2, 0.12, 0.08), "light", bevel=0.0)


def build_glow():
    p = parts.Part("engine_glow", MATS)
    for sx in (-1, 1):
        parts.exhaust_glow(p, BELL_R * 0.85, 1.1, "glow", x=sx * ENG_X, z=ENG_Z, segs=16)
    return p


def build_ship():
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    root = parts.make_root("miner_hauler")
    hull = build_hull().finish(root)
    glow = build_glow().finish(root)
    glow.location = (0, NOZZLE_Y, 0)
    parts.add_empty("drill_point", root, tuple(FOCUS), size=1.0)
    for k, (x, z) in enumerate(EMITTERS, 1):
        parts.add_empty(f"laser_emitter_{k}", root, (x, APER_Y, z), size=0.3)
    return root, hull, glow


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, hull, glow = build_ship()
    bpy.context.view_layer.update()
    if "--no-textures" not in argv:
        glow.hide_render = True
        wk.texture([hull], MATS, PRE, [(0.0, 0.0)], scorch=SCORCH, decals=DECALS,
                   labels=LABELS, seed0=114)
        glow.hide_render = False
    else:
        for o in (hull,):
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    wk.stats([hull, glow])
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews("miner_hauler", 17.0, target=(0, 0.5, 0))
    extra = [a.split("=", 1)[1] for a in argv if a.startswith("--extra=")]
    if extra:
        extra_views(extra[0])


def firing_beams():
    """Debug-only stand-in for the in-game DrillBeam (four feeders into the focus, one main
    beam on), added after the export so it never reaches the .glb."""
    m = common.make_material("debug_beam", (0.5, 0.85, 1.0), roughness=0.2,
                             emission=(0.55, 0.9, 1.0), emission_strength=12.0)
    p = parts.Part("debug_beams", {"beam": m})
    for x, z in EMITTERS:
        p.tube(V((x, APER_Y, z)), FOCUS, 0.05, 0.05, "beam", segs=8)
    p.tube(FOCUS, FOCUS + V((0, 9.0, 0)), 0.2, 0.2, "beam", segs=12)
    p.sphere(FOCUS, 0.28, "beam", segs=12, rings=6)
    return p.finish(None)


def extra_views(out_dir):
    """Debug renders into out_dir (idle, then firing with stand-in beams); not part of the
    previews."""
    scene = bpy.context.scene
    cam = scene.camera
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1200
    views = (("close", (-9, 14, 7), (0, 6.0, -0.3), 7.0),
             ("belly", (-10, 8, -9), (0, 0, -1.0), 17.0),
             ("side", (-30, 0, 0), (0, 0.5, 0), 17.0),
             ("rear", (-9, -16, 8), (0, -3, 0.5), 13.0),
             ("front", (6, 20, 3), (0, 5, -0.3), 7.0),
             ("rts", (-6, -14, 30), (0, 2.5, 0), 26.0))
    for firing in (False, True):
        if firing:
            firing_beams()
        for name, loc, tgt, ortho in views:
            cam.location = loc
            cam.rotation_euler = (V(tgt) - V(loc)).to_track_quat("-Z", "Y").to_euler()
            cam.data.ortho_scale = ortho
            tag = "_firing" if firing else ""
            common.render(os.path.join(out_dir, f"miner_{name}{tag}.png"))


main()
