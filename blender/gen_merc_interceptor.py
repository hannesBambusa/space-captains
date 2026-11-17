"""Generate the mercenary interceptor .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_merc_interceptor.py
  Add `-- --no-preview` to skip the PNG renders, `-- --no-textures` to skip the atlas bake
  (fast shape iteration: flat colours only), `-- --extra=<dir>` for debug close-ups (and a
  scale check beside the miner), `-- --out-dir=<dir>` to write the .glb, .blend and
  previews there instead of into the project (shape iteration without touching the game).

Design: FL-27 "Jackal" freelance gun corvette, a one-seat heavy interceptor a hired pilot
owns, patches and refits from their own wallet. No wings, no canopy: an armoured hull built
along the thrust axis, a stepped wedge of slab-armour blocks that widens from a blunt
sensor head to a heavy drive, with two outrigger sponsons at the stern. Every part has a
home in the stock merc loadout, front to back:
  sensors   Combat Sensors (slot 4): a blunt, swappable red sensor head. Its flat face is
            a tiled phased-array panel, with an IRST ball on top and a ventral lidar, both
            with red lenses, looking down the 14 deg gun cone.
  guns      Twin Autocannon (slot 0): two quick-release gun pods on cheek pylons, one gun
            a side (the game fires muzzle_l and muzzle_r in turn). Receiver with coolant
            radiator and case port, cooled shroud, recoil buffer, a glowing heat ring and
            a muzzle brake. From above the two barrels make a fork past the sensor head.
  ammo      Ammo Rack (slot 1): a quick-change drum magazine behind each receiver with an
            open feed chute, nested ahead of the main block's shoulder (the port drum is
            a primer-grey replacement).
  crew      The Ejection Rig: a faceted armoured cupola on the neck, the pod-white
            survival cell (the same white as the escape pod that flies off in game). A
            thick-framed visor slit and two side slits instead of a canopy, a blued
            glacis, a hazard break ring, pyro bolts, two ejection motor ports, an egress
            hatch and an amber rescue beacon.
  defence   Deflector (slot 2): a bolted dorsal module with two capacitor drums wired to
            four emitter lenses (both sponsons, dorsal, ventral). Armor Plating shows as
            blued bolt-on steel on the cheeks, the flanks, the sponsons and the belly.
  hull      Three armour blocks: the neck (crew, guns), the tapered deflector deck and the
            wide reactor block behind a blued glacis. Flush radiators lie on the upper
            flank slopes, reactor louvres on the side walls. Propellant rides in two
            saddle tanks under the reactor block's chines.
  sponsons  Not wings: a long faceted armour block a side, as thick as it is wide, toed
            out from the hull toward the stern and held off the reactor block by two box
            pylons with cross braces (open, you see space through the gap). They put the
            roll and yaw thrusters at their stern ends and a shield emitter at each
            armoured prow, far from the centre of mass, and carry the nav lights; the
            deflector conduit crosses the gap. The starboard one is a primer replacement.
            With the hull they make the arrowhead you see from above.
  stern     a warp field-coil collar with cool-blue windows just ahead of the engines, and
            the Combat Thrusters (slot 3): a bolt-flanged swappable twin-bell thrust pack,
            wider than the neck is; heavy RCS quads at the nose, the stern and the
            sponsons.
Gunmetal over a charcoal belly, the Mercenary Outpost's oxide red, khaki primer on
replaced parts, gouged armour patches, callsign RED DOG, a kill tally and the hull number
27. Same worn atlas, stencils, hazard trim and grime as the MX-14 miner.

Layout (Blender Z up, exported +Y up). Ship centre at origin on the play plane z=0.
The nose points along Blender +Y = Godot -Z (forward), like every other ship.
  length ~13.8 m (bell exits y -6.75 .. muzzle brakes y 7.06), width ~7.7 m over the
  sponson thrusters (x +-3.85; hull 4.0 m, thrust pack flange 4.2 m; fits the outpost's
  10 m berths), height ~3.3 m (ventral lens z -1.23 .. whip antenna z 2.05).
Hierarchy: merc_interceptor (empty root) -> merc_interceptor_hull, engine_glow,
  muzzle_l, muzzle_r (empties, unrotated, at the muzzle brake tips; tracers start there).
engine_glow has its origin on the bell exit plane (Blender y = NOZZLE_Y), plumes along
Godot local +Z (scale Z to lengthen); WarpVisuals brightens it while the warp spools.
Textures: one 2048 worn atlas (worn_kit / station_textures bake, kinds re-scaled to ship
size), saved as blender/textures/merc_interceptor_{albedo,mr,normal}.jpg, material
"merc_interceptor_hull". Emissive materials stay flat, named "merc_interceptor_*".
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

PRE = "merc_interceptor"
OUT = os.path.join(common.ROOT, "assets", "models", "ships", "merc_interceptor.glb")
BLEND = os.path.join(common.ROOT, "blender", "merc_interceptor.blend")
MINER_GLB = os.path.join(common.ROOT, "assets", "models", "ships", "miner_hauler.glb")

NOZZLE_Y = -6.75
BELL_R = 0.8
BELL_LEN = 0.95
ENG_X = 0.98
ENG_Z = -0.05
GUN_X = 1.32         # gun axis, either side
GUN_Z = -0.35
MUZZLE_Y = 7.06      # muzzle brake front face (+0.01)
POD_X = 3.25          # sponson axis at its stern end
POD_Y = (-4.3, 0.35)   # sponson body: stern end, prow tip
POD_K = -0.2         # sponson toe-out: axis dx per metre of y         # sponson axis
POD_Z = -0.1
PYLON_Y = (-2.5, -3.6)
LABELS = ["FL-27", "#CHEV", "NO STEP", "#BAR", "AMMO", "27", "EJECT", "IIII IIII II",
          "RED DOG", "DANGER"]
RED_INK = (0.32, 0.05, 0.035)
ATLAS_JPEG_Q = 88    # the bake saves at 92; the .glb embeds the files as they are

# Hull stations (y, half width W, belly z, top z), stern to nose: reactor block (its stern
# is inside the thrust pack), armoured glacis, tapered deflector deck, shoulder step, neck,
# sensor head.
FUS = (
    (-4.8, 2.0, -1.08, 1.1),
    (-1.55, 2.0, -1.08, 1.1),
    (-1.1, 1.7, -1.03, 1.04),
    (0.9, 1.52, -1.0, 1.0),
    (1.0, 1.0, -0.9, 0.86),
    (4.85, 0.9, -0.82, 0.7),
    (5.15, 0.78, -0.7, 0.56),
    (5.8, 0.72, -0.64, 0.5),
)
# Armoured cupola of the survival cell, same section shape (its belly is inside the neck).
CANOPY = (
    (1.55, 0.5, 0.45, 1.0),
    (1.85, 0.62, 0.38, 1.26),
    (3.45, 0.62, 0.32, 1.2),
    (3.72, 0.57, 0.31, 1.08),
    (4.25, 0.42, 0.3, 0.84),
    (4.5, 0.3, 0.3, 0.7),
)
# Section shape: right half (x / W, z fraction of height), mirrored to the left. A slab:
# flat belly, lower chine, vertical side wall, upper slope, shoulder, flat top.
SEC = ((0.62, 0.0), (1.0, 0.3), (1.0, 0.58), (0.62, 0.92), (0.38, 1.0))
N_SEC = 10

MATS = {}
DECALS = []
SCORCH = []
RNG = random.Random(27)

# Worn kinds at ship scale (process-local overrides, same family as the miner).
SHIP_WORN = {
    # gunmetal blue-grey, the main upper paint
    "hull": dict(big=(1.6, 1.2), plate=(0.8, 0.6),
                 tones=[(0.215, 0.228, 0.245), (0.2, 0.213, 0.23), (0.23, 0.24, 0.255),
                        (0.19, 0.2, 0.215), (0.222, 0.228, 0.236), (0.205, 0.218, 0.238)],
                 plate_var=0.07, rough=(0.5, 0.12), metal=0.15, seam_big=0.45,
                 seam_small=0.18, rivets=True, hatches=0.18, chip=(0.1, 0.1, 0.105),
                 chip_metal=0.85, chip_k=1.3, grime_k=0.9, streak_k=0.3, bleach=0.06),
    # charcoal: belly, chines, pods, fairings
    "hull2": dict(big=(1.4, 1.0), plate=(0.7, 0.5),
                  tones=[(0.09, 0.095, 0.105), (0.08, 0.085, 0.095), (0.1, 0.105, 0.112),
                         (0.075, 0.08, 0.088), (0.095, 0.092, 0.09), (0.085, 0.09, 0.1)],
                  plate_var=0.08, rough=(0.55, 0.12), metal=0.1, seam_big=0.45,
                  seam_small=0.18, rivets=True, hatches=0.12, chip=(0.30, 0.30, 0.31),
                  chip_metal=0.9, chip_k=0.9, grime_k=0.9, streak_k=0.25, bleach=0.1),
    # survival-cell white: the miner's work white, the escape pod's lifeboat white
    "hull3": dict(big=(1.6, 1.2), plate=(0.8, 0.6),
                  tones=[(0.46, 0.46, 0.44), (0.43, 0.432, 0.425), (0.49, 0.488, 0.47),
                         (0.41, 0.415, 0.41), (0.47, 0.46, 0.44), (0.42, 0.425, 0.42)],
                  plate_var=0.06, rough=(0.55, 0.12), metal=0.05, seam_big=0.45,
                  seam_small=0.18, rivets=True, hatches=0.16, chip=(0.1, 0.1, 0.105),
                  chip_metal=0.8, chip_k=1.2, grime_k=1.0, streak_k=0.3, bleach=0.1),
    # khaki zinc primer on replaced parts, little wear yet
    "primer": dict(big=(1.2, 1.2), plate=(0.6, 0.6),
                   tones=[(0.26, 0.255, 0.19), (0.24, 0.24, 0.18), (0.275, 0.27, 0.2),
                          (0.235, 0.232, 0.178), (0.25, 0.245, 0.185), (0.265, 0.26, 0.2)],
                   plate_var=0.05, rough=(0.7, 0.1), metal=0.0, seam_big=0.4,
                   seam_small=0.12, rivets=True, hatches=0.0, chip=(0.3, 0.3, 0.31),
                   chip_metal=0.9, chip_k=0.7, grime_k=0.5, streak_k=0.15, bleach=0.0),
    # gouged blued bolt-on armour steel
    "armor": dict(big=(0.9, 0.7), plate=(0.45, 0.35),
                  tones=[(0.11, 0.115, 0.12), (0.1, 0.104, 0.11), (0.125, 0.128, 0.132),
                         (0.095, 0.098, 0.103), (0.118, 0.115, 0.112), (0.105, 0.11, 0.118)],
                  plate_var=0.1, rough=(0.45, 0.14), metal=0.7, seam_big=0.5,
                  seam_small=0.25, rivets=True, hatches=0.0, chip=(0.38, 0.38, 0.39),
                  chip_metal=1.0, chip_k=1.6, grime_k=0.8, streak_k=0.35, bleach=0.0),
    # merc oxide red, the Mercenary Outpost paint
    "accent": dict(big=(1.2, 0.8), plate=(0.6, 0.4),
                   tones=[(0.30, 0.045, 0.035), (0.27, 0.04, 0.03), (0.33, 0.055, 0.04),
                          (0.25, 0.04, 0.032), (0.31, 0.05, 0.038), (0.28, 0.045, 0.036)],
                   plate_var=0.06, rough=(0.55, 0.1), metal=0.0, seam_big=0.4,
                   seam_small=0.15, rivets=False, hatches=0.0, chip=(0.13, 0.13, 0.135),
                   chip_metal=0.8, chip_k=1.4, grime_k=1.1, streak_k=0.4, bleach=0.3),
    # the next five are the miner's, verbatim (same family)
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
    "hazard": dict(big=(1.2, 1.2), plate=(0.6, 0.6),
                   tones=[(0.42, 0.29, 0.04), (0.40, 0.28, 0.035), (0.44, 0.31, 0.045),
                          (0.38, 0.27, 0.04), (0.43, 0.30, 0.04), (0.41, 0.285, 0.04)],
                   plate_var=0.05, rough=(0.6, 0.08), metal=0.0, seam_big=0.3,
                   seam_small=0.1, rivets=False, hatches=0.0, chip=(0.12, 0.12, 0.125),
                   chip_metal=0.7, chip_k=1.8, grime_k=1.2, streak_k=0.45, bleach=0.2,
                   stripes=0.32),
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
    MATS["hull"] = m(f"{PRE}_paint_gunmetal", (0.215, 0.228, 0.245), roughness=0.5,
                     metallic=0.15)
    MATS["hull2"] = m(f"{PRE}_paint_dark", (0.09, 0.095, 0.105), roughness=0.55)
    MATS["hull3"] = m(f"{PRE}_cell_white", (0.46, 0.46, 0.44), roughness=0.55)
    MATS["primer"] = m(f"{PRE}_primer", (0.26, 0.255, 0.19), roughness=0.7)
    MATS["armor"] = m(f"{PRE}_armor", (0.11, 0.115, 0.12), roughness=0.45, metallic=0.7)
    MATS["dark"] = m(f"{PRE}_structure", (0.045, 0.047, 0.05), roughness=0.5, metallic=0.6)
    MATS["metal"] = m(f"{PRE}_bare_metal", (0.3, 0.3, 0.31), roughness=0.36, metallic=0.9)
    MATS["accent"] = m(f"{PRE}_merc_red", (0.3, 0.045, 0.035), roughness=0.55)
    MATS["hazard"] = m(f"{PRE}_hazard", (0.42, 0.29, 0.04), roughness=0.6)
    MATS["temper"] = m(f"{PRE}_temper", (0.2, 0.15, 0.2), roughness=0.33, metallic=0.92)
    MATS["radiator"] = m(f"{PRE}_radiator", (0.36, 0.365, 0.37), roughness=0.42,
                         metallic=0.2)
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
    MATS["lens"] = m(f"{PRE}_deflector_lens", (0.5, 0.8, 0.9), roughness=0.2,
                     emission=(0.55, 0.9, 1.0), emission_strength=8.0)
    MATS["target"] = m(f"{PRE}_target_lens", glow, roughness=0.2,
                       emission=(1.0, 0.18, 0.06), emission_strength=5.0)
    MATS["heat"] = m(f"{PRE}_barrel_heat", glow, roughness=0.3,
                     emission=(1.0, 0.38, 0.08), emission_strength=2.5)
    MATS["glow"] = m(f"{PRE}_engine_glow", (0.8, 0.95, 1.0), roughness=0.2,
                     emission=(0.65, 0.92, 1.0), emission_strength=6.0)
    for k in ("glass", "window", "window_cool", "light", "white", "nav_r", "nav_g", "lens",
              "target", "heat"):
        MATS[k].use_backface_culling = False


def label(text, centre, normal, up, h, colour, opacity=0.85):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity))


# ---------------------------------------------------------------- section helpers
def sec_ring(y, W, zb, zt, grow=0.0, x0=0.0):
    """10-point section at y: flat belly, chine, wall, upper slope, shoulder, flat top.
    `grow` pushes every point outward (paint bands, collars)."""
    H = zt - zb
    right = [(W * fx + grow, zb + H * fz) for fx, fz in SEC]
    right[0] = (right[0][0], right[0][1] - grow)
    right[-1] = (right[-1][0], right[-1][1] + grow)
    pts = right + [(-x, z) for x, z in reversed(right)]
    return [V((x0 + x, y, z)) for x, z in pts]


def table_at(table, y):
    """Interpolated (W, zb, zt) of a section table at y."""
    if y <= table[0][0]:
        return table[0][1:]
    for a, b in zip(table, table[1:]):
        if a[0] <= y <= b[0]:
            t = (y - a[0]) / (b[0] - a[0])
            return tuple(a[k] + (b[k] - a[k]) * t for k in (1, 2, 3))
    return table[-1][1:]


def face_frame(table, y, j, v, x0=0.0):
    """Point on section face j (between ring points j and j+1) at fraction v, and a frame
    with X along the face edge, Y along the ship, Z the outward face normal."""
    W, zb, zt = table_at(table, y)
    r0 = sec_ring(y, W, zb, zt, x0=x0)
    W1, zb1, zt1 = table_at(table, y + 0.05)
    r1 = sec_ring(y + 0.05, W1, zb1, zt1, x0=x0)
    a, b = r0[j], r0[(j + 1) % N_SEC]
    p = a.lerp(b, v)
    q = r1[j].lerp(r1[(j + 1) % N_SEC], v)
    ex = (b - a).normalized()
    ey = (q - p).normalized()
    n = ex.cross(ey).normalized()
    if n.dot(p - V((x0, y, (zb + zt) / 2))) < 0:
        n = -n
        ex = -ex
    ey = n.cross(ex)
    return p, Matrix((ex, ey, n)).transposed().to_4x4()


def on_hull(p, table, y, j, v, size, mat, lift=0.0, bevel=0.12, dy=0.0, x0=0.0):
    """Box lying on a hull face (size = across edge, along ship, thickness)."""
    c, r = face_frame(table, y, j, v, x0)
    n = r.col[2].xyz
    c = c + n * (size[2] / 2 - 0.02 + lift) + r.col[1].xyz * dy
    p.box(c, size, mat, r=r, bevel=bevel)
    return c, r


def frame(n, up=(0, 0, 1)):
    """4x4 rotation: X across, Y = up projected, Z = n (outward)."""
    n = V(n).normalized()
    u = V(up)
    if abs(u.dot(n)) > 0.95:
        u = V((0, 1, 0))
    u = (u - n * u.dot(n)).normalized()
    x = u.cross(n)
    return Matrix((x, u, n)).transposed().to_4x4()


def ring_pt(table, y, k, sx=1, lift=0.0):
    """Section point k (0 belly edge, 1 wall foot, 2 wall top, 3 shoulder, 4 top edge) on
    side sx at y, pushed outward by lift."""
    r = sec_ring(y, *table_at(table, y), grow=lift)
    return r[k if sx > 0 else N_SEC - 1 - k]


def side(sx, j):
    """Section face on side sx for the starboard face j (0 chine, 1 wall, 2 slope,
    3 shoulder)."""
    return j if sx > 0 else 8 - j


def band(p, y0, y1, grow, mat, table=FUS):
    """Collar around a section table from y0 to y1, standing `grow` proud of it."""
    fn = mat if callable(mat) else (lambda i, j: mat)
    p.loft([sec_ring(y0, *table_at(table, y0), grow=grow),
            sec_ring(y1, *table_at(table, y1), grow=grow)], "dark", cap=False, mat_fn=fn)


def hull_radiator(p, y, j, v, across, along, ribs):
    """Flush radiator panel on hull face j, coolant ribs across it."""
    c, r = on_hull(p, FUS, y, j, v, (across, along, 0.04), "radiator", bevel=0.0)
    n, ey = r.col[2].xyz, r.col[1].xyz
    for k in range(ribs):
        p.box(c + n * 0.02 + ey * (-along / 2 + along * (k + 0.5) / ribs),
              (across * 0.96, 0.06, 0.04), "metal", r=r, bevel=0.0)
    return c, r


# ---------------------------------------------------------------- hull
def build_hull():
    p = parts.PanelPart("merc_interceptor_hull", MATS)
    fuselage(p)
    crew_cell(p)
    sensor_head(p)
    for sx in (-1, 1):
        gun_pod(p, sx)
        drum(p, sx)
        sponson(p, sx)
        saddle_tank(p, sx)
    defence_module(p)
    reactor_deck(p)
    warp_collar(p)
    thrust_pack(p)
    body_rcs(p)
    belly(p)
    service_details(p)
    return p


def fuselage(p):
    """Slab-armour hull, a stepped wedge: reactor block, tapered deflector deck, neck,
    blunt red sensor head."""
    def fm(i, j):
        if i >= 5:
            return "accent"                 # red sensor head, the swappable unit
        if i == 3 or j in (9, 0, 8):
            return "hull2"
        if i == 1:
            return "armor"                  # glacis between the deck and the reactor block
        if i == 2 and j == 7:
            return "primer"                 # port replacement side plate
        return "hull"
    p.loft([sec_ring(*row) for row in FUS], "accent", mat_fn=fm)
    band(p, 4.76, 4.86, 0.02, "dark")
    band(p, 1.25, 1.43, 0.025, lambda i, j: "hull2" if j in (9, 0, 8) else "accent")
    # Armor Plating: bolt-on slabs on the cheeks, the deflector deck flanks and the head
    for sx in (-1, 1):
        on_hull(p, FUS, 4.28, side(sx, 1), 0.5, (0.36, 0.86, 0.06), "armor", bevel=0.25)
        on_hull(p, FUS, 5.5, side(sx, 1), 0.5, (0.24, 0.46, 0.05), "armor", bevel=0.25)
    on_hull(p, FUS, -0.1, 1, 0.5, (0.48, 1.6, 0.07), "armor", bevel=0.25)
    on_hull(p, FUS, -0.6, 7, 0.5, (0.42, 0.7, 0.06), "armor", bevel=0.25)
    c, r = face_frame(FUS, 2.3, 6, 0.5)
    label("RED DOG", c + r.col[2].xyz * 0.02, r.col[2].xyz, (0, 0, 1), 0.18, wk.INK_LIGHT, 0.9)
    c, r = face_frame(FUS, 2.3, 2, 0.5)
    label("IIII IIII II", c + r.col[2].xyz * 0.02, r.col[2].xyz, (0, 0, 1), 0.2, wk.INK_LIGHT,
          0.9)
    # hull number and chevrons on the port slope of the deflector deck
    # (read from the port side, like RED DOG: the slope is too narrow for upright digits)
    c, r = face_frame(FUS, -0.5, 6, 0.5)
    label("27", c + r.col[2].xyz * 0.02, r.col[2].xyz, (0, 0, 1), 0.72, wk.INK_LIGHT, 0.95)
    c, r = face_frame(FUS, 0.45, 6, 0.5)
    label("#CHEV", c + r.col[2].xyz * 0.02, r.col[2].xyz, (-1, 0, 0), 0.2, RED_INK, 0.9)
    SCORCH.append((-1.7, -0.8, 0.5, 0.45))


def crew_cell(p):
    """Armoured cupola on the pod-white ejectable survival cell (Ejection Rig): a visor
    slit and two side slits, thick frames, a blued glacis."""
    rings = [sec_ring(*row) for row in CANOPY]

    def cm(i, j):
        if i == 2 and 2 <= j <= 6:
            return "glass"                  # the visor slit
        if i >= 3:
            return "armor"                  # glacis ahead of the visor
        return "hull3"
    p.loft(rings, "hull3", mat_fn=cm)
    for i in (2, 3):
        for j in range(2, 7):
            a, b = rings[i][j], rings[i][j + 1]
            n = ((a + b) / 2 - V((0, a.y, 0.7))).normalized()
            parts.strut(p, a + n * 0.035, b + n * 0.035, 0.09, 0.07, "hull2")
    for k in range(2, 8):
        a, b = rings[2][k], rings[3][k]
        n = (a - V((0, a.y, 0.7))).normalized()
        parts.strut(p, a + n * 0.035, b + n * 0.035, 0.08, 0.07, "hull2")
    zt = table_at(CANOPY, 3.36)[2]
    p.box(V((0, 3.36, zt + 0.03)), (0.6, 0.16, 0.07), "armor", bevel=0.2)
    for sx in (-1, 1):
        c, r = face_frame(CANOPY, 2.75, side(sx, 2), 0.5)
        n, ey = r.col[2].xyz, r.col[1].xyz
        p.box(c + n * 0.005, (0.24, 1.1, 0.05), "hull2", r=r, bevel=0.0)
        parts.quad(p, c + n * 0.036, n, (0, 0, 1), 0.92, 0.11, "glass")
        parts.quad(p, c + n * 0.042 + ey * 0.22, n, (0, 0, 1), 0.28, 0.06, "window")
        c, r = face_frame(CANOPY, 2.2, side(sx, 2), 0.25)
        label("EJECT", c + r.col[2].xyz * 0.015, r.col[2].xyz, (0, 0, 1), 0.07, RED_INK, 0.95)
    # break ring the cell separates along, pyro bolts, ejection motors, hatch, beacon
    band(p, 1.9, 2.02, 0.025, lambda i, j: "hazard" if 1 <= j <= 7 else "dark", table=CANOPY)
    zt = table_at(CANOPY, 1.96)[2]
    for sx in (-1, 1):
        p.box(V((sx * 0.16, 1.96, zt + 0.04)), (0.08, 0.14, 0.05), "metal", bevel=0.0)
        p.tube(V((sx * 0.18, 1.66, 1.02)), V((sx * 0.18, 1.3, 0.9)), 0.05, 0.07, "dark", segs=8)
        p.tube(V((sx * 0.18, 1.33, 0.91)), V((sx * 0.18, 1.3, 0.9)), 0.075, 0.075, "hazard",
               segs=8)
    zt = table_at(CANOPY, 2.9)[2]
    p.box(V((0, 2.9, zt + 0.005)), (0.36, 0.52, 0.04), "hull3", bevel=0.2)
    for dx in (-0.12, 0.12):
        p.box(V((dx, 2.62, zt + 0.02)), (0.06, 0.05, 0.03), "metal", bevel=0.0)
    zt = table_at(CANOPY, 2.3)[2]
    p.cyl(V((0, 2.3, zt + 0.02)), 0.07, 0.07, 0.04, "dark", segs=8)
    p.cyl(V((0, 2.3, zt + 0.07)), 0.05, 0.04, 0.08, "light", segs=8)
    SCORCH.append((0.0, 1.3, 0.92, 0.3))


def sensor_head(p):
    """Combat Sensors: phased-array face, IRST ball on top, ventral lidar (red lenses)."""
    y, W, zb, zt = FUS[-1]
    zc = (zb + zt) / 2
    p.box(V((0, y + 0.015, zc)), (0.98, 0.05, 0.66), "dark", bevel=0.0)
    for ix in range(3):
        for iz in range(2):
            p.box(V((-0.3 + ix * 0.3, y + 0.045, zc - 0.15 + iz * 0.3)), (0.27, 0.02, 0.27),
                  "radiator", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 0.3, y + 0.02, zc - 0.44)), (0.12, 0.04, 0.06), "target", bevel=0.0)
    zt = table_at(FUS, 5.45)[2]
    p.cyl(V((0, 5.45, zt + 0.02)), 0.14, 0.14, 0.08, "dark", segs=12)
    p.sphere(V((0, 5.45, zt + 0.15)), 0.12, "glass", segs=10, rings=5)
    p.box(V((0, 5.57, zt + 0.15)), (0.06, 0.02, 0.04), "target", bevel=0.0)
    zb = table_at(FUS, 5.45)[1]
    p.box(V((0, 5.45, zb - 0.03)), (0.3, 0.4, 0.12), "dark", bevel=0.15)
    p.box(V((0, 5.66, zb - 0.05)), (0.12, 0.02, 0.05), "target", bevel=0.0)
    p.tube(V((-0.5, y, 0.2)), V((-0.5, y + 0.6, 0.2)), 0.025, 0.012, "metal", segs=6)
    SCORCH.append((0.85, 3.9, 0.1, 0.35))


def gun_pod(p, sx):
    """Twin Autocannon, one gun a side: pylon, receiver, shroud, buffer, heat ring, brake."""
    x, z = sx * GUN_X, GUN_Z
    p.box(V((sx * (GUN_X - 0.2), 2.6, -0.32)), (0.5, 2.2, 0.2), "hull2", bevel=0.12)
    p.box(V((x, 3.2, z)), (0.46, 1.3, 0.42), "hull2", bevel=0.15)
    p.box(V((x, 3.25, z + 0.215)), (0.3, 0.9, 0.03), "dark", bevel=0.0)
    p.box(V((x, 3.0, z - 0.22)), (0.16, 0.3, 0.04), "dark", bevel=0.0)
    p.box(V((x + sx * 0.235, 3.0, z)), (0.03, 0.3, 0.08), "hazard", bevel=0.0)
    parts.radiator(p, V((x + sx * 0.245, 3.45, z)), 0.6, 0.22, (sx, 0, 0), "radiator", "metal",
                   ribs=4, t=0.03)
    p.box(V((x, 2.6, z + 0.215)), (0.1, 0.06, 0.04), "light", bevel=0.0)
    p.sphere(V((x, 3.86, z + 0.23)), 0.05, "glass", segs=8, rings=4)
    p.cyl(V((x, 3.91, z)), 0.2, 0.2, 0.12, "accent", segs=12, axis_rot=ALONG_Y)
    p.tube(V((x, 3.85, z)), V((x, 5.6, z)), 0.15, 0.15, "metal", segs=10)
    for y in (4.1, 4.5, 4.9, 5.3):
        p.cyl(V((x, y, z)), 0.17, 0.17, 0.06, "dark", segs=10, axis_rot=ALONG_Y)
    p.tube(V((x, 3.9, z - 0.22)), V((x, 5.2, z - 0.22)), 0.05, 0.05, "metal", segs=6)
    p.box(V((x, 5.25, z - 0.1)), (0.14, 0.1, 0.24), "dark", bevel=0.0)
    p.tube(V((x, 5.6, z)), V((x, 6.75, z)), 0.075, 0.075, "dark", segs=8)
    p.cyl(V((x, 6.68, z)), 0.088, 0.088, 0.06, "heat", segs=8, axis_rot=ALONG_Y)
    p.cyl(V((x, 6.9, z)), 0.115, 0.115, 0.3, "temper", segs=8, axis_rot=ALONG_Y)
    for y in (6.84, 6.96):
        p.box(V((x, y, z)), (0.28, 0.05, 0.06), "dark", bevel=0.0)
    p.cyl(V((x, 7.052, z)), 0.05, 0.05, 0.005, "dark", segs=8, axis_rot=ALONG_Y)
    SCORCH.append((x, 6.9, z, 0.5))
    SCORCH.append((x, 3.0, z - 0.25, 0.4))


def drum(p, sx):
    """Ammo Rack: quick-change drum magazine with an open feed chute."""
    x, z = sx * GUN_X, GUN_Z
    p.cyl(V((x, 1.75, z)), 0.34, 0.34, 1.3, "primer" if sx < 0 else "hull2", segs=14,
          axis_rot=ALONG_Y)
    p.cyl(V((x, 1.3, z)), 0.35, 0.35, 0.05, "dark", segs=14, axis_rot=ALONG_Y)
    p.cyl(V((x, 2.25, z)), 0.35, 0.35, 0.1, "hazard", segs=14, axis_rot=ALONG_Y)
    p.cyl(V((x, 1.07, z)), 0.3, 0.3, 0.06, "metal", segs=14, axis_rot=ALONG_Y)
    p.box(V((x, 1.03, z)), (0.3, 0.05, 0.05), "dark", bevel=0.0)
    p.beam(V((x, 2.3, -0.02)), V((x, 2.5, 0.0)), 0.12, 0.1, "dark")
    p.beam(V((x, 2.5, 0.0)), V((x, 2.75, -0.12)), 0.12, 0.1, "dark")
    if sx > 0:
        label("AMMO", V((1.665, 1.75, z)), (1, 0, 0), (0, 0, 1), 0.12, wk.INK_LIGHT, 0.9)


def pod_x(y):
    """Sponson centreline x at y: toed out toward the stern."""
    return POD_X + (y - POD_Y[0]) * POD_K


def sponson(p, sx):
    """Outrigger sponson: a long armoured block toed out from the hull on two box pylons,
    open to space between them. It puts the roll/yaw RCS at its stern end and a deflector
    emitter at its prow far from the centre of mass, and carries the nav lights."""
    z = POD_Z
    body = (1.0, 0.8, 0.22)
    rz = rot(rz=sx * math.atan(-POD_K))           # the block's own frame, Y along its axis
    out = rz.to_3x3() @ V((sx, 0, 0))

    def at(y, dx=0.0, dz=0.0):
        return V((sx * (pod_x(y) + dx), y, z + dz))

    def ring(y, d):
        return parts.oct_ring(y, *d, x0=sx * pod_x(y), z0=z)
    skin = "primer" if sx > 0 else "hull2"       # the starboard one is a replacement
    y0, y1 = POD_Y
    p.loft([ring(y0 - 0.3, (0.6, 0.48, 0.12)), ring(y0, body), ring(-1.7, body)], skin,
           mat_fn=lambda i, j: "dark" if i == 0 else skin)
    p.loft([ring(-1.7, body), ring(y1 - 0.55, body), ring(y1, (0.56, 0.5, 0.12))], "armor")
    band_d = (1.04, 0.84, 0.23)
    p.loft([ring(-1.9, band_d), ring(-1.74, band_d)], "accent")
    tip = at(y1)
    p.cyl(tip + V((0, 0.06, 0)), 0.19, 0.19, 0.16, "metal", segs=10, axis_rot=ALONG_Y)
    p.cyl(tip + V((0, 0.15, 0)), 0.2, 0.2, 0.04, "dark", segs=10, axis_rot=ALONG_Y)
    p.sphere(tip + V((0, 0.18, 0)), 0.16, "lens", segs=10, rings=5, scale=(1, 0.75, 1))
    p.box(at(y0 - 0.33), (0.1, 0.06, 0.1), "white", bevel=0.0)
    parts.rcs_quad(p, at(-3.75, dz=0.47), (0, 0, 1), "hull2", "metal", s=0.24)
    parts.rcs_quad(p, at(-3.75, dz=-0.47), (0, 0, -1), "hull2", "metal", s=0.24)
    parts.rcs_quad(p, at(-4.05) + out * 0.57, out, "hull2", "metal", s=0.2)
    # bolt-on armour slab on the outer face with the formation strip, nav light ahead
    p.box(at(-3.0) + out * 0.515, (0.05, 1.2, 0.34), "armor", r=rz, bevel=0.25)
    p.box(at(-3.0) + out * 0.545, (0.02, 0.4, 0.05), "window_cool", r=rz, bevel=0.0)
    p.box(at(-1.2) + out * 0.52, (0.07, 0.16, 0.08), "nav_g" if sx > 0 else "nav_r", r=rz,
          bevel=0.0)
    # bolt-on slab over the prow, top access hatch with latches
    p.box(at(-0.95, dz=0.4), (0.46, 1.1, 0.05), "armor", r=rz, bevel=0.25)
    h = at(-2.75, dz=0.405)
    p.box(h, (0.3, 0.4, 0.03), "hull2" if sx > 0 else "hull", r=rz, bevel=0.2)
    for dx in (-0.09, 0.09):
        p.box(h + rz.to_3x3() @ V((dx, 0.16, 0.02)), (0.05, 0.04, 0.02), "metal", r=rz,
              bevel=0.0)
    # pylons: two box beams with root and tip plates, cross braces between them
    xi = table_at(FUS, -3.0)[0] - 0.04
    zp = z - 0.02
    ends = []
    for y in PYLON_Y:
        xo = pod_x(y) - 0.46
        p.box(V((sx * (xi + xo) / 2, y, zp)), (xo - xi, 0.36, 0.26), "hull2", bevel=0.0)
        p.box(V((sx * (xi + 0.07), y, zp)), (0.1, 0.56, 0.4), "dark", bevel=0.0)
        p.box(V((sx * (xo - 0.03), y, zp)), (0.08, 0.5, 0.36), "dark", r=rz, bevel=0.0)
        ends.append(xo - 0.05)
    ya, yb = PYLON_Y[0] - 0.16, PYLON_Y[1] + 0.16
    for a, b in (((xi + 0.1, ya), (ends[1], yb)), ((ends[0], ya), (xi + 0.1, yb))):
        parts.strut(p, V((sx * a[0], a[1], zp)), V((sx * b[0], b[1], zp)), 0.07, 0.07, "metal")
    if sx > 0:
        p.box(V((sx * (xi + ends[0]) / 2, PYLON_Y[0], zp + 0.14)), (0.2, 0.42, 0.04), "armor",
              bevel=0.2)                          # splice strap on the replaced pylon
    # deflector conduit: capacitor bay, down the flank slope, across the gap to the emitter
    a = ring_pt(FUS, -1.75, 3, sx, 0.05)
    b = ring_pt(FUS, -1.75, 2, sx, 0.05)
    c = at(-1.45, dx=-0.15, dz=0.39)
    parts.pipe(p, V((sx * 0.46, -0.85, a.z + 0.02)), a, 0.04, "dark", segs=6)
    parts.pipe(p, a, b, 0.045, "metal", segs=6)
    parts.pipe(p, b, c, 0.045, "metal", segs=6)
    p.box(a, (0.14, 0.14, 0.1), "dark", bevel=0.0)
    p.box(b, (0.16, 0.16, 0.12), "dark", bevel=0.0)
    p.box(a.lerp(b, 0.5), (0.12, 0.1, 0.12), "hazard", bevel=0.0)
    p.box(b.lerp(c, 0.55), (0.1, 0.12, 0.1), "hazard", bevel=0.0)
    p.box(c, (0.22, 0.22, 0.14), "dark", r=rz, bevel=0.1)
    SCORCH.append((tip.x, tip.y + 0.2, z, 0.3))
    SCORCH.append((sx * pod_x(-3.75), -3.75, z + 0.55, 0.25))


def saddle_tank(p, sx):
    """Combat-thruster propellant, slung under the reactor block's chine."""
    x, z = sx * 1.76, -0.93
    parts.capsule(p, -3.6, -2.0, 0.22, lambda i, j: "hull2", segs=8, x=x, z=z, dome0=0.6,
                  dome1=0.8, steps=2)
    for y in (-3.25, -2.35):
        p.torus(V((x, y, z)), 0.225, 0.025, "dark", segs=8, minor_segs=3,
                matrix=rot(rx=math.pi / 2))
    p.box(V((x, -3.63, z)), (0.12, 0.12, 0.12), "metal", bevel=0.1)
    p.box(V((x + sx * 0.215, -2.8, z)), (0.03, 0.3, 0.1), "hazard", bevel=0.0)


def defence_module(p):
    """Deflector slot: bolted dorsal bay, two capacitor drums wired to the emitters."""
    y0 = -0.1
    zt = table_at(FUS, y0)[2]
    p.box(V((0, y0, zt + 0.01)), (1.06, 1.8, 0.06), "dark", bevel=0.0)
    p.box(V((0, y0, zt + 0.15)), (0.92, 1.6, 0.32), "hull2", bevel=0.15)
    for sx in (-1, 1):
        c = V((sx * 0.22, y0 + 0.05, zt + 0.4))
        p.cyl(c, 0.15, 0.15, 1.1, "metal", segs=10, axis_rot=ALONG_Y)
        for s in (-1, 1):
            p.cyl(c + V((0, s * 0.58, 0)), 0.16, 0.16, 0.06, "dark", segs=10, axis_rot=ALONG_Y)
            p.box(V((sx * 0.46, y0 + s * 0.72, zt + 0.25)), (0.14, 0.14, 0.1), "dark", bevel=0.0)
        p.cyl(c, 0.16, 0.16, 0.1, "accent", segs=10, axis_rot=ALONG_Y)
    p.cyl(V((0, y0 - 0.66, zt + 0.35)), 0.1, 0.1, 0.08, "dark", segs=10)
    p.sphere(V((0, y0 - 0.66, zt + 0.45)), 0.085, "lens", segs=10, rings=5)
    p.box(V((0, y0 - 0.815, zt + 0.15)), (0.5, 0.02, 0.14), "dark", bevel=0.0)
    label("DANGER", V((0, y0 - 0.83, zt + 0.15)), (0, -1, 0), (0, 0, 1), 0.09, wk.INK_LIGHT, 0.9)
    p.box(V((0, y0 - 0.815, zt + 0.03)), (0.8, 0.02, 0.05), "hazard", bevel=0.0)


def reactor_deck(p):
    """Reactor block top: heat grilles, red spine bar, access hatches, comms whip."""
    zt = table_at(FUS, -2.75)[2]
    for sx in (-1, 1):
        p.box(V((sx * 0.3, -2.65, zt + 0.005)), (0.22, 1.3, 0.04), "dark", bevel=0.0)
        for k in range(5):
            p.box(V((sx * 0.3, -3.15 + k * 0.25, zt + 0.03)), (0.2, 0.05, 0.04), "metal",
                  bevel=0.0)
        h = V((sx * 0.58, -2.45, zt + 0.0))
        p.box(h, (0.3, 0.5, 0.03), "hull2", bevel=0.2)
        for dy in (-0.18, 0.18):
            p.box(h + V((sx * 0.1, dy, 0.02)), (0.04, 0.06, 0.02), "metal", bevel=0.0)
    label("#BAR", V((0, -2.65, zt + 0.0)), (0, 0, 1), (-1, 0, 0), 0.3, RED_INK, 0.9)
    p.box(V((0.58, -3.3, zt)), (0.1, 0.1, 0.06), "dark", bevel=0.0)
    p.tube(V((0.58, -3.3, zt)), V((0.65, -3.8, 2.0)), 0.022, 0.01, "dark", segs=4)
    p.box(V((0.65, -3.8, 2.02)), (0.06, 0.06, 0.06), "white", bevel=0.0)


def warp_collar(p):
    """Warp field coils just ahead of the engines, cool-blue coil windows."""
    rings = [sec_ring(y, *table_at(FUS, y), grow=g)
             for y, g in ((-4.68, 0.04), (-4.58, 0.12), (-4.08, 0.12), (-3.98, 0.04))]
    p.loft(rings, "hull2", cap=False, mat_fn=lambda i, j: "hull2" if i == 1 else "dark")
    zt = table_at(FUS, -4.33)[2]
    for x in (-0.51, -0.17, 0.17, 0.51):
        p.box(V((x, -4.33, zt + 0.125)), (0.24, 0.4, 0.02), "window_cool", bevel=0.0)
    for sx in (-1, 1):
        for j, w in ((1, 0.34), (2, 0.7)):
            c, r = face_frame(FUS, -4.33, side(sx, j), 0.5)
            n, ex = r.col[2].xyz, r.col[0].xyz
            for k in (-1, 1):
                p.box(c + n * 0.125 + ex * k * w * 0.27, (w * 0.42, 0.4, 0.02), "window_cool",
                      r=r, bevel=0.0)


def thrust_pack(p):
    """Combat Thrusters: bolt-flanged swappable twin-bell block, gimbal actuators."""
    p.loft([parts.oct_ring(-4.75, 3.7, 2.0, 0.5, z0=ENG_Z),
            parts.oct_ring(-4.83, 4.2, 2.2, 0.55, z0=ENG_Z),
            parts.oct_ring(-4.97, 4.2, 2.2, 0.55, z0=ENG_Z),
            parts.oct_ring(-5.04, 3.95, 2.06, 0.52, z0=ENG_Z),
            parts.oct_ring(-5.7, 3.7, 1.86, 0.46, z0=ENG_Z)], "hull2",
           mat_fn=lambda i, j: "dark" if i == 1 else "hull2")
    for q in parts.oct_ring(-4.9, 4.22, 2.22, 0.55, z0=ENG_Z):
        p.box(q, (0.07, 0.05, 0.07), "metal", bevel=0.0)
    p.hazard(-1.2, 1.2, 0.14, -0.02, 0.02,
             matrix=Matrix.Translation((0, -5.72, ENG_Z + 0.82)) @ rot(rx=math.pi / 2),
             pitch=0.25, cols=("hazard", "dark"))
    for sx in (-1, 1):
        x = sx * ENG_X
        p.cyl(V((x, -5.73, ENG_Z)), 0.68, 0.68, 0.1, "metal", segs=16, axis_rot=ALONG_Y)
        p.cyl(V((x, -5.8, ENG_Z)), 0.55, 0.55, 0.08, "dark", segs=16, axis_rot=ALONG_Y)
        parts.bell(p, NOZZLE_Y, BELL_R, BELL_LEN, "temper", "dark", x=x, z=ENG_Z, segs=20)
        p.torus(V((x, NOZZLE_Y + 0.12, ENG_Z)), BELL_R * 0.97, 0.035, "metal", segs=20,
                minor_segs=3, matrix=rot(rx=math.pi / 2))
        for a in (0.785, 2.356, 3.927, 5.498):
            d = V((math.cos(a), 0, math.sin(a)))
            parts.pipe(p, V((x, -5.72, ENG_Z)) + d * 0.7, V((x, -6.2, ENG_Z)) + d * 0.6, 0.04,
                       "metal", segs=5)
        label("FL-27", V((sx * 1.925, -5.4, ENG_Z + 0.1)), (sx, 0, 0), (0, 0, 1), 0.16,
              wk.INK_LIGHT, 0.9)
        SCORCH.append((x, -5.9, ENG_Z, 1.1))
    p.box(V((0, -5.4, ENG_Z + 0.96)), (0.16, 0.12, 0.06), "light", bevel=0.0)
    SCORCH.append((0.0, -5.7, 0.6, 0.7))


def body_rcs(p):
    """Pitch and yaw quads at the nose and stern: dive/climb passes, aiming in the cone."""
    for sx in (-1, 1):
        c, r = face_frame(FUS, 4.5, side(sx, 2), 0.45)
        n = r.col[2].xyz
        parts.rcs_quad(p, c + n * 0.06, n, "hull2", "metal", s=0.2)
        parts.rcs_quad(p, V((sx * 1.7, -5.4, 0.72)), (sx, 0, 1), "hull2", "metal", s=0.22)
        SCORCH.append((c.x, c.y, c.z, 0.3))
        SCORCH.append((sx * 1.7, -5.4, 0.74, 0.3))


def belly(p):
    """Cradle lock plates, bolt-on belly armour, ventral emitter, approach lamps."""
    for y in (4.2, -3.6):
        z = table_at(FUS, y)[1] - 0.005
        p.box(V((0, y, z)), (0.96, 0.86, 0.03), "hazard", bevel=0.0)
        p.box(V((0, y, z - 0.025)), (0.7, 0.6, 0.05), "metal", bevel=0.0)
        SCORCH.append((0.0, y, z - 0.03, 0.55))
    on_hull(p, FUS, -0.1, 9, 0.5, (1.5, 1.5, 0.07), "armor", bevel=0.25)
    on_hull(p, FUS, -2.4, 9, 0.5, (1.7, 1.3, 0.07), "armor", bevel=0.25)
    on_hull(p, FUS, -2.6, 9, 0.3, (0.5, 0.6, 0.05), "primer", lift=0.07)
    p.cyl(V((0, -1.0, -1.08)), 0.12, 0.12, 0.1, "dark", segs=10)
    p.sphere(V((0, -1.0, -1.14)), 0.09, "lens", segs=10, rings=5)
    for sx in (-1, 1):
        p.box(V((sx * 0.4, 3.0, table_at(FUS, 3.0)[1] - 0.01)), (0.2, 0.14, 0.05), "light",
              bevel=0.0)
        p.box(V((sx * 0.8, -4.3, table_at(FUS, -4.3)[1] - 0.01)), (0.2, 0.14, 0.05), "light",
              bevel=0.0)


def service_details(p):
    """The hands-on parts of a ship its pilot maintains: flank radiators, reactor louvres,
    the rearm/refuel port, access panels, IFF blades under the nose, ammo loading doors,
    boarding grips."""
    for sx in (-1, 1):
        # flush radiators on the reactor block's upper slopes
        c, r = hull_radiator(p, -2.72, side(sx, 2), 0.5, 0.88, 1.5, 6)
        label("NO STEP", c + r.col[2].xyz * 0.03 - r.col[1].xyz * 0.45, r.col[2].xyz,
              (0, 1, 0), 0.12, wk.INK_DARK, 0.8)
        # reactor heat-exchanger louvres on the side walls, between the pylons
        c, r = on_hull(p, FUS, -3.05, side(sx, 1), 0.5, (0.4, 0.46, 0.03), "dark", bevel=0.0)
        n = r.col[2].xyz
        for k in range(4):
            p.box(c + n * 0.025 + r.col[1].xyz * (-0.165 + k * 0.11), (0.36, 0.05, 0.03),
                  "metal", r=r, bevel=0.0)
        # IFF / comms blades under the nose
        zb = table_at(FUS, 3.5)[1]
        p.beam(V((sx * 0.3, 3.5, zb + 0.02)), V((sx * 0.34, 3.2, zb - 0.24)), 0.03, 0.18, "dark",
               up=V((0, 1, 0)))
        # ammo loading door under each drum
        c, r = on_hull(p, FUS, 1.75, side(sx, 0), 0.5, (0.3, 0.7, 0.03), "hull3", bevel=0.2)
        p.box(c + r.col[2].xyz * 0.02 + r.col[1].xyz * 0.28, (0.12, 0.05, 0.02), "hazard",
              r=r, bevel=0.0)
        # thrust-pack side access panel
        p.box(V((sx * 1.92, -5.4, ENG_Z - 0.38)), (0.03, 0.4, 0.3), "hull", bevel=0.2)
    # the deflector deck's starboard slope: radiator and the rearm / refuel port; the port
    # slope carries the hull number
    hull_radiator(p, -0.4, 2, 0.5, 0.74, 1.1, 5)
    c, r = face_frame(FUS, 0.55, 2, 0.45)
    n = r.col[2].xyz
    p.tube(c - n * 0.02, c + n * 0.03, 0.15, 0.15, "hazard", segs=12)
    p.tube(c + n * 0.03, c + n * 0.06, 0.11, 0.11, "metal", segs=12)
    p.box(c + n * 0.07, (0.14, 0.03, 0.02), "dark", r=r, bevel=0.0)
    SCORCH.append((c.x, c.y, c.z, 0.2))
    # boarding grips up the port slope to the cell hatch
    for k in range(3):
        c, r = face_frame(FUS, 3.1, 6, 0.25 + k * 0.25)
        a = c + r.col[2].xyz * 0.03
        parts.strut(p, a - V((0, 0.07, 0)), a + V((0, 0.07, 0)), 0.03, 0.03, "metal")


def build_glow():
    p = parts.Part("engine_glow", MATS)
    for sx in (-1, 1):
        parts.exhaust_glow(p, BELL_R * 0.85, 1.3, "glow", x=sx * ENG_X, z=ENG_Z, segs=16)
    return p


def build_ship():
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    root = parts.make_root("merc_interceptor")
    hull = build_hull().finish(root)
    glow = build_glow().finish(root)
    glow.location = (0, NOZZLE_Y, 0)
    for name, sx in (("muzzle_l", -1), ("muzzle_r", 1)):
        parts.add_empty(name, root, (sx * GUN_X, MUZZLE_Y, GUN_Z), size=0.6)
    return root, hull, glow


def recompress_atlas(hull):
    """Save the atlas JPEGs again at ATLAS_JPEG_Q. This hull has more painted area than the
    old airframe had, so at the bake's quality the .glb would outgrow it."""
    seen = set()
    for mat in hull.data.materials:
        if not mat.use_nodes:
            continue
        for node in mat.node_tree.nodes:
            img = getattr(node, "image", None)
            if node.type != "TEX_IMAGE" or img is None or img.name in seen:
                continue
            seen.add(img.name)
            path = bpy.path.abspath(img.filepath)
            if path.lower().endswith(".jpg"):
                img.file_format = "JPEG"
                img.save(filepath=path, quality=ATLAS_JPEG_Q)
                img.reload()


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, hull, glow = build_ship()
    bpy.context.view_layer.update()
    if "--no-textures" not in argv:
        glow.hide_render = True
        wk.texture([hull], MATS, PRE, [(0.0, 0.0)], scorch=SCORCH, decals=DECALS,
                   labels=LABELS, seed0=127)
        glow.hide_render = False
        recompress_atlas(hull)
    else:
        hull.data.uv_layers.remove(hull.data.uv_layers["panel"])
    wk.stats([hull, glow])
    blend, out = BLEND, OUT
    out_dir = [a.split("=", 1)[1] for a in argv if a.startswith("--out-dir=")]
    if out_dir:
        blend = os.path.join(out_dir[0], os.path.basename(BLEND))
        out = os.path.join(out_dir[0], os.path.basename(OUT))
        common.PREVIEW_DIR = out_dir[0]
    wk.save_and_export(root, blend, out)
    if "--no-preview" not in argv:
        parts.ship_previews("merc_interceptor", 15.0, target=(0, 0.2, 0.2))
    extra = [a.split("=", 1)[1] for a in argv if a.startswith("--extra=")]
    if extra:
        extra_views(extra[0])


def extra_views(out_dir):
    """Debug renders into out_dir (close-ups, then a scale check beside the miner);
    not part of the previews and never exported."""
    scene = bpy.context.scene
    cam = scene.camera
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1200
    views = (("close", (-8, 12, 6), (0, 3.5, 0.2), 6.5),
             ("belly", (-9, 7, -8), (0, 0, -0.6), 15.0),
             ("side", (-30, 0, 0), (0, 0.2, 0), 15.0),
             ("rear", (-8, -15, 7), (0, -4, 0.3), 11.0),
             ("front", (5, 20, 3), (0, 4, 0), 8.0),
             ("rts", (-6, -14, 30), (0, 0, 0), 24.0))
    for name, loc, tgt, ortho in views:
        cam.location = loc
        cam.rotation_euler = (V(tgt) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        cam.data.ortho_scale = ortho
        common.render(os.path.join(out_dir, f"merc_{name}.png"))
    if os.path.exists(MINER_GLB):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=MINER_GLB)
        for o in set(bpy.data.objects) - before:
            if o.parent is None:
                o.location.x += 9.0
        cam.location = (-6, -20, 40)
        cam.rotation_euler = (V((4.5, 0, 0)) - V((-6, -20, 40))).to_track_quat("-Z", "Y").to_euler()
        cam.data.ortho_scale = 30.0
        common.render(os.path.join(out_dir, "merc_pair.png"))


main()
