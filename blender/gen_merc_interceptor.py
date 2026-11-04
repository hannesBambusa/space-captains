"""Generate the mercenary interceptor .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_merc_interceptor.py
  Add `-- --no-preview` to skip the PNG renders, `-- --no-textures` to skip the atlas bake
  (fast shape iteration: flat colours only), `-- --extra=<dir>` for debug close-ups (and a
  scale check beside the miner).

Design: FL-27 "Jackal" freelance gun interceptor. A one-seat gun platform a hired pilot
owns, patches and refits from their own wallet. Every part has a home in the stock merc
loadout, front to back:
  guns      Twin Autocannon (slot 0): two quick-release gun pods on cheek pylons, one gun
            a side (the game fires muzzle_l and muzzle_r in turn). Receiver with coolant
            radiator and case port, cooled shroud, recoil buffer, a glowing heat ring and
            a muzzle brake. From above the two barrels make a fork past the nose.
  ammo      Ammo Rack (slot 1): a quick-change drum magazine behind each receiver with an
            open feed chute (the port drum is a primer-grey replacement).
  sensors   Combat Sensors (slot 4): a swappable red radome nose, an IRST ball on top and
            a ventral lidar, both with red lenses, looking down the 14 deg gun cone.
  cockpit   The Ejection Rig: a bubble canopy on a pod-white survival cell (the same white
            as the escape pod that flies off in game), with a hazard break ring, pyro
            bolts, two ejection motor ports and an amber rescue beacon.
  defence   Deflector (slot 2): a bolted dorsal module with two capacitor drums wired to
            four emitter lenses (both wingtips, dorsal, ventral). Armor Plating shows as
            blued bolt-on steel on the cheeks and belly.
  wings     Not airfoils: swept outrigger spars that put the roll and yaw thrusters and
            the shield emitters far from the centre of mass, with flush radiators, the
            deflector conduit and, on starboard, a primer replacement section with a
            splice strap. Propellant rides in two saddle tanks under the wing roots.
  stern     a warp field-coil collar with cool-blue windows just ahead of the engines, and
            the Combat Thrusters (slot 3): a bolt-flanged swappable twin-bell thrust pack;
            heavy RCS quads at the nose, the stern and the wingtips.
Gunmetal over a charcoal belly, the Mercenary Outpost's oxide red, khaki primer on
replaced parts, gouged armour patches, callsign RED DOG, a kill tally and the hull number
27. Same worn atlas, stencils, hazard trim and grime as the MX-14 miner.

Layout (Blender Z up, exported +Y up). Ship centre at origin on the play plane z=0.
The nose points along Blender +Y = Godot -Z (forward), like every other ship.
  length ~13.8 m (bell exits y -6.75 .. muzzle brakes y 7.06), span ~8.1 m over the
  wingtip pods (fits the outpost's 10 m berths), height ~3.3 m (ventral lens z -1.23 ..
  whip antenna z 2.05).
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
BELL_R = 0.5
BELL_LEN = 0.62
ENG_X = 0.62
ENG_Z = -0.05
GUN_X = 1.32         # gun axis, either side
GUN_Z = -0.35
MUZZLE_Y = 7.06      # muzzle brake front face (+0.01)
POD_X = 3.75         # wingtip pod axis
LABELS = ["FL-27", "#CHEV", "NO STEP", "#BAR", "AMMO", "27", "EJECT", "IIII IIII II",
          "RED DOG", "DANGER"]
RED_INK = (0.32, 0.05, 0.035)

# Fuselage stations (y, half width W, belly z, top z), stern to nose.
FUS = (
    (-5.0, 1.15, -0.8, 0.85),
    (-4.7, 1.38, -1.0, 1.05),
    (-2.0, 1.42, -1.05, 1.1),
    (0.0, 1.32, -1.0, 1.05),
    (1.6, 1.15, -0.95, 0.95),
    (3.3, 0.95, -0.85, 0.78),
    (4.7, 0.72, -0.7, 0.5),
    (5.6, 0.5, -0.55, 0.25),
    (5.9, 0.38, -0.47, 0.13),
    (6.2, 0.22, -0.37, 0.0),
    (6.42, 0.07, -0.25, -0.12),
)
# Bubble canopy over the survival cell, same section shape.
CANOPY = (
    (1.1, 0.55, 0.7, 1.05),
    (1.6, 0.68, 0.7, 1.42),
    (2.6, 0.7, 0.62, 1.55),
    (3.5, 0.6, 0.5, 1.32),
    (4.2, 0.38, 0.4, 0.82),
    (4.55, 0.16, 0.38, 0.55),
)
# Outrigger spar stations (x, leading-edge y, trailing-edge y, z centre, thickness).
WING = (
    (1.0, 1.0, -4.5, 0.05, 0.34),
    (2.3, -0.85, -4.75, 0.02, 0.26),
    (3.55, -2.6, -5.0, 0.0, 0.2),
)
# Section shape: right half (x / W, z fraction of height), mirrored to the left.
SEC = ((0.6, 0.0), (1.0, 0.34), (0.9, 0.62), (0.66, 0.86), (0.34, 1.0))
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


def wing_ring(x, y_le, y_te, zc, t):
    """Six-point chamfered spar section at span station x (chord along Y). Faces j:
    0 upper LE chamfer, 1 top, 2 upper TE chamfer, 3 lower TE chamfer, 4 bottom,
    5 lower LE chamfer."""
    return [V((x, y, z)) for y, z in ((y_le, zc), (y_le - 0.25, zc + t / 2),
                                      (y_te + 0.15, zc + t / 2), (y_te, zc),
                                      (y_te + 0.15, zc - t / 2), (y_le - 0.25, zc - t / 2))]


# ---------------------------------------------------------------- hull
def build_hull():
    p = parts.PanelPart("merc_interceptor_hull", MATS)
    fuselage(p)
    canopy_cell(p)
    nose_sensors(p)
    for sx in (-1, 1):
        gun_pod(p, sx)
        drum(p, sx)
        wing(p, sx)
        tip_pod(p, sx)
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
    """Lofted gunmetal wedge: radome sensor nose, cockpit, reactor, warp section."""
    def fm(i, j):
        if i >= 7:
            return "accent"                 # red radome, the swappable sensor cone
        if i == 0 or j in (9, 0, 8):
            return "hull2"
        if i == 2 and j == 6:
            return "primer"                 # port replacement panel
        return "hull"
    p.loft([sec_ring(*row) for row in FUS], "hull", mat_fn=fm)
    p.loft([sec_ring(5.55, *table_at(FUS, 5.55), grow=0.02),
            sec_ring(5.65, *table_at(FUS, 5.65), grow=0.02)], "dark", cap=False)
    p.loft([sec_ring(0.70, *table_at(FUS, 0.70), grow=0.025),
            sec_ring(0.88, *table_at(FUS, 0.88), grow=0.025)], "accent", cap=False,
           mat_fn=lambda i, j: "hull2" if j in (9, 0, 8) else "accent")
    # Armor Plating: bolt-on cheek armour over the gun pylons
    for sx in (-1, 1):
        on_hull(p, FUS, 3.6, 1 if sx > 0 else 7, 0.6, (0.32, 1.0, 0.06), "armor", bevel=0.25)
    c, r = face_frame(FUS, 2.2, 6, 0.5)
    label("RED DOG", c + r.col[2].xyz * 0.02, r.col[2].xyz, (0, 0, 1), 0.18, wk.INK_LIGHT, 0.9)
    c, r = face_frame(FUS, 2.2, 2, 0.5)
    label("IIII IIII II", c + r.col[2].xyz * 0.02, r.col[2].xyz, (0, 0, 1), 0.2, wk.INK_LIGHT,
          0.9)


def canopy_cell(p):
    """Bubble canopy on the pod-white ejectable survival cell (Ejection Rig)."""
    rings = [sec_ring(*row) for row in CANOPY]

    def cm(i, j):
        if i in (1, 2, 3) and j in (2, 3, 4, 5, 6):
            return "glass"
        if j == 9:
            return "hull2"
        if i == 4:
            return "hull"                   # nose fairing ahead of the glass
        return "hull3"
    p.loft(rings, "hull3", mat_fn=cm)
    for i in (1, 2, 3):
        for j in range(2, 7):
            a, b = rings[i][j], rings[i][j + 1]
            n = ((a + b) / 2 - V((0, a.y, 0.9))).normalized()
            parts.strut(p, a + n * 0.03, b + n * 0.03, 0.07, 0.05, "hull2")
    for k in (2, 7):
        for i in (1, 2, 3):
            a, b = rings[i][k], rings[i + 1][k]
            n = V((1 if a.x > 0 else -1, 0, 0.4)).normalized()
            parts.strut(p, a + n * 0.03, b + n * 0.03, 0.06, 0.05, "hull2")
    for sx in (-1, 1):
        c, r = face_frame(CANOPY, 2.1, 2 if sx > 0 else 6, 0.5)
        parts.quad(p, c + r.col[2].xyz * 0.035, r.col[2].xyz, (0, 0, 1), 0.28, 0.1, "window")
    # break ring the cell separates along, pyro bolts, ejection motors, rescue beacon
    p.loft([sec_ring(0.98, *table_at(FUS, 0.98), grow=0.02),
            sec_ring(1.08, *table_at(FUS, 1.08), grow=0.02)], "dark", cap=False,
           mat_fn=lambda i, j: "hazard" if j in (2, 3, 4, 5, 6) else "dark")
    for sx in (-1, 1):
        p.box(V((sx * 0.25, 1.03, 1.03)), (0.08, 0.12, 0.05), "metal", bevel=0.0)
        p.tube(V((sx * 0.18, 1.4, 1.2)), V((sx * 0.18, 1.1, 1.1)), 0.05, 0.07, "dark", segs=8)
        p.tube(V((sx * 0.18, 1.13, 1.11)), V((sx * 0.18, 1.1, 1.1)), 0.075, 0.075, "hazard",
               segs=8)
        c, r = face_frame(CANOPY, 1.35, 2 if sx > 0 else 6, 0.5)
        label("EJECT", c + r.col[2].xyz * 0.015, r.col[2].xyz, (0, 0, 1), 0.07, RED_INK, 0.95)
    p.cyl(V((0, 1.35, 1.255)), 0.07, 0.07, 0.04, "dark", segs=8)
    p.cyl(V((0, 1.35, 1.3)), 0.05, 0.04, 0.08, "light", segs=8)
    SCORCH.append((0.0, 1.15, 1.1, 0.3))


def nose_sensors(p):
    """Combat Sensors: IRST ball on top, ventral lidar (red lenses), pitot probe."""
    p.cyl(V((0, 4.95, 0.47)), 0.14, 0.14, 0.08, "dark", segs=12)
    p.sphere(V((0, 4.95, 0.6)), 0.12, "glass", segs=12, rings=6)
    p.box(V((0, 5.07, 0.6)), (0.06, 0.02, 0.04), "target", bevel=0.0)
    p.box(V((0, 5.0, -0.68)), (0.3, 0.4, 0.12), "dark", bevel=0.15)
    p.box(V((0, 5.21, -0.7)), (0.12, 0.02, 0.05), "target", bevel=0.0)
    p.tube(V((0, 6.38, -0.18)), V((0, 6.75, -0.18)), 0.025, 0.012, "metal", segs=6)
    SCORCH.append((0.85, 3.9, 0.1, 0.35))


def gun_pod(p, sx):
    """Twin Autocannon, one gun a side: pylon, receiver, shroud, buffer, heat ring, brake."""
    x, z = sx * GUN_X, GUN_Z
    p.box(V((sx * 1.12, 2.6, -0.32)), (0.5, 2.2, 0.2), "hull2", bevel=0.12)
    p.box(V((x, 3.2, z)), (0.46, 1.3, 0.42), "hull2", bevel=0.15)
    p.box(V((x, 3.25, z + 0.215)), (0.3, 0.9, 0.03), "dark", bevel=0.0)
    p.box(V((x, 3.0, z - 0.22)), (0.16, 0.3, 0.04), "dark", bevel=0.0)
    p.box(V((x + sx * 0.235, 3.0, z)), (0.03, 0.3, 0.08), "hazard", bevel=0.0)
    parts.radiator(p, V((x + sx * 0.245, 3.45, z)), 0.6, 0.22, (sx, 0, 0), "radiator", "metal",
                   ribs=4, t=0.03)
    p.box(V((x, 2.6, z + 0.215)), (0.1, 0.06, 0.04), "light", bevel=0.0)
    p.sphere(V((x, 3.86, z + 0.23)), 0.05, "glass", segs=8, rings=4)
    p.cyl(V((x, 3.91, z)), 0.2, 0.2, 0.12, "accent", segs=12, axis_rot=ALONG_Y)
    p.tube(V((x, 3.85, z)), V((x, 5.6, z)), 0.13, 0.13, "metal", segs=10)
    for y in (4.1, 4.5, 4.9, 5.3):
        p.cyl(V((x, y, z)), 0.15, 0.15, 0.06, "dark", segs=10, axis_rot=ALONG_Y)
    p.tube(V((x, 3.9, z - 0.21)), V((x, 5.2, z - 0.21)), 0.05, 0.05, "metal", segs=6)
    p.box(V((x, 5.25, z - 0.1)), (0.14, 0.1, 0.24), "dark", bevel=0.0)
    p.tube(V((x, 5.6, z)), V((x, 6.75, z)), 0.065, 0.065, "dark", segs=8)
    p.cyl(V((x, 6.68, z)), 0.078, 0.078, 0.06, "heat", segs=8, axis_rot=ALONG_Y)
    p.cyl(V((x, 6.9, z)), 0.1, 0.1, 0.3, "temper", segs=8, axis_rot=ALONG_Y)
    for y in (6.84, 6.96):
        p.box(V((x, y, z)), (0.24, 0.05, 0.05), "dark", bevel=0.0)
    p.cyl(V((x, 7.052, z)), 0.045, 0.045, 0.005, "dark", segs=8, axis_rot=ALONG_Y)
    SCORCH.append((x, 6.9, z, 0.5))
    SCORCH.append((x, 3.0, z - 0.25, 0.4))


def drum(p, sx):
    """Ammo Rack: quick-change drum magazine with an open feed chute."""
    x, z = sx * GUN_X, GUN_Z
    p.cyl(V((x, 1.75, z)), 0.34, 0.34, 1.3, "primer" if sx < 0 else "hull2", segs=18,
          axis_rot=ALONG_Y)
    p.cyl(V((x, 1.3, z)), 0.35, 0.35, 0.05, "dark", segs=18, axis_rot=ALONG_Y)
    p.cyl(V((x, 2.25, z)), 0.35, 0.35, 0.1, "hazard", segs=18, axis_rot=ALONG_Y)
    p.cyl(V((x, 1.07, z)), 0.3, 0.3, 0.06, "metal", segs=18, axis_rot=ALONG_Y)
    p.box(V((x, 1.03, z)), (0.3, 0.05, 0.05), "dark", bevel=0.0)
    p.beam(V((x, 2.3, -0.02)), V((x, 2.5, 0.0)), 0.12, 0.1, "dark")
    p.beam(V((x, 2.5, 0.0)), V((x, 2.75, -0.12)), 0.12, 0.1, "dark")
    if sx > 0:
        label("AMMO", V((1.665, 1.75, z)), (1, 0, 0), (0, 0, 1), 0.12, wk.INK_LIGHT, 0.9)


def wing(p, sx):
    """Outrigger spar: lever arm for the tip RCS and emitters, radiator, conduit."""
    rings = [wing_ring(sx * x, yl, yt, zc, t) for x, yl, yt, zc, t in WING]

    def wm(i, j):
        patched = sx > 0 and i == 1
        if j == 1:
            return "primer" if patched else "hull"
        if j == 4:
            return "primer" if patched else "hull2"
        if j in (0, 5):
            return "hull2"
        return "dark"
    p.loft(rings, "hull", mat_fn=wm)
    parts.radiator(p, V((sx * 1.8, -2.6, 0.19)), 1.8, 0.7, (0, 0, 1), "radiator", "metal",
                   ribs=6, t=0.04)
    a, b = V((sx * 1.3, 0.22, 0.25)), V((sx * 3.45, -2.81, 0.15))
    parts.pipe(p, a, b, 0.045, "metal", segs=6)
    for t in (0.25, 0.5, 0.75):
        p.box(a.lerp(b, t), (0.14, 0.1, 0.1), "hazard", bevel=0.0)
    p.box(b, (0.2, 0.2, 0.14), "dark", bevel=0.1)
    if sx > 0:
        p.box(V((2.3, -3.1, 0.175)), (0.18, 3.0, 0.05), "armor", bevel=0.2)
    else:
        # Stencils sit on the thick root section, aft of the radiator: the thin outer spar
        # reads as all edge to the wear bake, which chips any stencil off it.
        label("27", V((-1.68, -4.0, 0.19)), (0, 0, 1), (0, 1, 0), 0.45, wk.INK_LIGHT, 0.95)
        label("#CHEV", V((-2.16, -4.0, 0.175)), (0, 0, 1), (-1, 0, 0), 0.25, RED_INK, 0.9)
        SCORCH.append((-2.9, -4.3, 0.12, 0.45))
    label("NO STEP", V((sx * 1.75, -1.3, 0.2)), (0, 0, 1), (0, 1, 0), 0.12, wk.INK_DARK, 0.8)


def tip_pod(p, sx):
    """Wingtip pod: deflector emitter lens, roll/yaw RCS, nav and formation lights."""
    x = sx * POD_X
    p.cyl(V((x, -3.85, 0)), 0.26, 0.26, 2.5, "hull2", segs=14, axis_rot=ALONG_Y)
    p.cyl(V((x, -3.1, 0)), 0.275, 0.275, 0.16, "accent", segs=14, axis_rot=ALONG_Y)
    p.cyl(V((x, -2.45, 0)), 0.26, 0.2, 0.3, "metal", segs=14, axis_rot=ALONG_Y)
    p.cyl(V((x, -2.32, 0)), 0.21, 0.21, 0.04, "dark", segs=14, axis_rot=ALONG_Y)
    p.sphere(V((x, -2.28, 0)), 0.16, "lens", segs=12, rings=6, scale=(1, 0.75, 1))
    p.cyl(V((x, -5.25, 0)), 0.15, 0.26, 0.3, "dark", segs=14, axis_rot=ALONG_Y)
    p.box(V((x, -5.43, 0)), (0.1, 0.06, 0.1), "white", bevel=0.0)
    parts.rcs_quad(p, V((x, -3.9, 0.3)), (0, 0, 1), "hull2", "metal", s=0.24)
    parts.rcs_quad(p, V((x, -3.9, -0.3)), (0, 0, -1), "hull2", "metal", s=0.24)
    parts.rcs_quad(p, V((sx * 3.98, -4.6, 0)), (sx, 0, 0), "hull2", "metal", s=0.2)
    p.box(V((sx * 4.03, -2.75, 0)), (0.06, 0.16, 0.08), "nav_g" if sx > 0 else "nav_r",
          bevel=0.0)
    p.box(V((sx * 4.015, -3.55, 0)), (0.02, 0.4, 0.05), "window_cool", bevel=0.0)
    SCORCH.append((x, -2.3, 0.0, 0.3))
    SCORCH.append((x, -3.9, 0.4, 0.25))


def saddle_tank(p, sx):
    """Combat-thruster propellant under the wing root."""
    x = sx * 1.38
    parts.capsule(p, -3.5, -0.8, 0.3, lambda i, j: "hull2", segs=12, x=x, z=-0.5, dome0=0.6,
                  dome1=0.8, steps=3)
    for y in (-2.9, -2.0, -1.2):
        p.torus(V((x, y, -0.5)), 0.305, 0.03, "dark", segs=12, minor_segs=3,
                matrix=rot(rx=math.pi / 2))
    p.box(V((x, -3.55, -0.5)), (0.14, 0.12, 0.14), "metal", bevel=0.1)
    p.box(V((sx * 1.69, -2.45, -0.5)), (0.03, 0.3, 0.1), "hazard", bevel=0.0)


def defence_module(p):
    """Deflector slot: bolted dorsal bay, two capacitor drums wired to the emitters."""
    p.box(V((0, -0.45, 1.06)), (1.06, 2.3, 0.06), "dark", bevel=0.0)
    p.box(V((0, -0.45, 1.2)), (0.92, 2.1, 0.32), "hull2", bevel=0.15)
    for sx in (-1, 1):
        c = V((sx * 0.22, -0.4, 1.45))
        p.cyl(c, 0.15, 0.15, 1.5, "metal", segs=10, axis_rot=ALONG_Y)
        for s in (-1, 1):
            p.cyl(c + V((0, s * 0.78, 0)), 0.16, 0.16, 0.06, "dark", segs=10, axis_rot=ALONG_Y)
            p.box(V((sx * 0.46, -0.45 + s * 0.95, 1.3)), (0.14, 0.14, 0.1), "dark", bevel=0.0)
        p.cyl(c, 0.16, 0.16, 0.1, "accent", segs=10, axis_rot=ALONG_Y)
        parts.pipe(p, V((sx * 0.46, -0.2, 1.15)), V((sx * 0.95, -0.05, 0.75)), 0.04, "dark",
                   segs=6)
        parts.pipe(p, V((sx * 0.95, -0.05, 0.75)), V((sx * 1.3, 0.2, 0.25)), 0.04, "dark",
                   segs=6)
    p.cyl(V((0, -1.36, 1.4)), 0.1, 0.1, 0.08, "dark", segs=10)
    p.sphere(V((0, -1.36, 1.5)), 0.085, "lens", segs=10, rings=5)
    p.box(V((0, -1.515, 1.2)), (0.5, 0.02, 0.14), "dark", bevel=0.0)
    label("DANGER", V((0, -1.53, 1.2)), (0, -1, 0), (0, 0, 1), 0.09, wk.INK_LIGHT, 0.9)
    p.box(V((0, -1.515, 1.08)), (0.8, 0.02, 0.05), "hazard", bevel=0.0)


def reactor_deck(p):
    """Reactor under the spine: heat grilles, red spine bar, comms whip."""
    for sx in (-1, 1):
        p.box(V((sx * 0.33, -2.6, 1.1)), (0.22, 1.3, 0.04), "dark", bevel=0.0)
        for k in range(5):
            p.box(V((sx * 0.33, -3.1 + k * 0.25, 1.125)), (0.2, 0.05, 0.04), "metal", bevel=0.0)
    label("#BAR", V((0, -2.6, 1.095)), (0, 0, 1), (-1, 0, 0), 0.3, RED_INK, 0.9)
    p.box(V((0.33, -3.45, 1.1)), (0.1, 0.1, 0.06), "dark", bevel=0.0)
    p.tube(V((0.33, -3.45, 1.1)), V((0.4, -3.95, 2.0)), 0.022, 0.01, "dark", segs=4)
    p.box(V((0.4, -3.95, 2.02)), (0.06, 0.06, 0.06), "white", bevel=0.0)


def warp_collar(p):
    """Warp field coils just ahead of the engines, cool-blue coil windows."""
    rings = [sec_ring(y, *table_at(FUS, y), grow=g)
             for y, g in ((-4.45, 0.04), (-4.35, 0.12), (-3.75, 0.12), (-3.65, 0.04))]
    p.loft(rings, "hull2", cap=False, mat_fn=lambda i, j: "hull2" if i == 1 else "dark")
    for x in (-0.3, -0.1, 0.1, 0.3):
        p.box(V((x, -4.05, 1.215)), (0.12, 0.5, 0.02), "window_cool", bevel=0.0)
    for sx in (-1, 1):
        c, r = face_frame(FUS, -4.05, 1 if sx > 0 else 7, 0.5)
        p.box(c + r.col[2].xyz * 0.135, (0.3, 0.5, 0.02), "window_cool", r=r, bevel=0.0)


def thrust_pack(p):
    """Combat Thrusters: bolt-flanged swappable twin-bell block, gimbal actuators."""
    p.loft([parts.oct_ring(-5.0, 2.3, 1.6, 0.45, z0=ENG_Z),
            parts.oct_ring(-5.08, 2.6, 1.85, 0.5, z0=ENG_Z),
            parts.oct_ring(-5.18, 2.6, 1.85, 0.5, z0=ENG_Z),
            parts.oct_ring(-5.25, 2.5, 1.7, 0.48, z0=ENG_Z),
            parts.oct_ring(-5.95, 2.3, 1.5, 0.42, z0=ENG_Z)], "hull2",
           mat_fn=lambda i, j: "dark" if i == 1 else "hull2")
    for q in parts.oct_ring(-5.13, 2.62, 1.87, 0.5, z0=ENG_Z):
        p.box(q, (0.07, 0.05, 0.07), "metal", bevel=0.0)
    p.hazard(-0.8, 0.8, 0.16, -0.02, 0.02,
             matrix=Matrix.Translation((0, -5.97, ENG_Z + 0.62)) @ rot(rx=math.pi / 2),
             pitch=0.25, cols=("hazard", "dark"))
    for sx in (-1, 1):
        x = sx * ENG_X
        p.cyl(V((x, -6.0, ENG_Z)), 0.44, 0.44, 0.12, "metal", segs=18, axis_rot=ALONG_Y)
        p.cyl(V((x, -6.1, ENG_Z)), 0.36, 0.36, 0.1, "dark", segs=18, axis_rot=ALONG_Y)
        parts.bell(p, NOZZLE_Y, BELL_R, BELL_LEN, "temper", "dark", x=x, z=ENG_Z, segs=20)
        p.torus(V((x, NOZZLE_Y + 0.1, ENG_Z)), BELL_R * 0.97, 0.03, "metal", segs=20,
                minor_segs=4, matrix=rot(rx=math.pi / 2))
        for a in (0.785, 2.356, 3.927, 5.498):
            d = V((math.cos(a), 0, math.sin(a)))
            parts.pipe(p, V((x, -5.98, ENG_Z)) + d * 0.46, V((x, -6.3, ENG_Z)) + d * 0.4, 0.035,
                       "metal", segs=5)
        label("FL-27", V((sx * 1.215, -5.6, ENG_Z)), (sx, 0, 0), (0, 0, 1), 0.16, wk.INK_LIGHT,
              0.9)
        SCORCH.append((x, -6.1, ENG_Z, 0.8))
    p.box(V((0, -5.45, 0.79)), (0.16, 0.12, 0.06), "light", bevel=0.0)
    SCORCH.append((0.0, -5.95, 0.5, 0.6))


def body_rcs(p):
    """Pitch and yaw quads at the nose and stern: dive/climb passes, aiming in the cone."""
    for sx in (-1, 1):
        parts.rcs_quad(p, V((sx * 0.75, 4.4, 0.1)), (sx, 0, 0.35), "hull2", "metal", s=0.2)
        parts.rcs_quad(p, V((sx * 0.97, -5.6, 0.62)), (sx, 0, 1), "hull2", "metal", s=0.22)
        SCORCH.append((sx * 0.75, 4.4, 0.1, 0.3))
        SCORCH.append((sx * 0.97, -5.6, 0.65, 0.3))


def belly(p):
    """Cradle lock plates, bolt-on belly armour, ventral emitter, approach lamps."""
    for y, z in ((4.2, -0.765), (-3.6, -1.035)):
        p.box(V((0, y, z)), (0.96, 0.86, 0.03), "hazard", bevel=0.0)
        p.box(V((0, y, z - 0.025)), (0.7, 0.6, 0.05), "metal", bevel=0.0)
        SCORCH.append((0.0, y, z - 0.03, 0.55))
    on_hull(p, FUS, 0.2, 9, 0.5, (1.0, 1.8, 0.07), "armor", bevel=0.25)
    on_hull(p, FUS, -2.0, 9, 0.5, (1.1, 1.6, 0.07), "armor", bevel=0.25)
    on_hull(p, FUS, -2.4, 9, 0.3, (0.5, 0.6, 0.05), "primer", lift=0.07)
    p.cyl(V((0, -1.0, -1.06)), 0.12, 0.12, 0.1, "dark", segs=10)
    p.sphere(V((0, -1.0, -1.14)), 0.09, "lens", segs=10, rings=5)
    for sx in (-1, 1):
        p.box(V((sx * 0.5, 3.0, -0.88)), (0.2, 0.14, 0.05), "light", bevel=0.0)
        p.box(V((sx * 0.6, -4.3, -1.02)), (0.2, 0.14, 0.05), "light", bevel=0.0)


def service_details(p):
    """The hands-on parts of a ship its pilot maintains: leading-edge armour, reactor
    louvres, the rearm/refuel port, wing and thrust-pack access hatches, IFF blades under
    the nose, ammo loading doors, boarding grips."""
    for sx in (-1, 1):
        # leading-edge armour caps: the edge that meets fire head-on
        le = [V((sx * x, yl - 0.02, zc)) for x, yl, _, zc, _ in WING]
        le[0] = le[0].lerp(le[1], 0.12)
        le[-1] = le[-1].lerp(le[-2], 0.08)
        for a, b in zip(le, le[1:]):
            p.beam(a, b, 0.14, 0.1, "armor")
            for t in (0.3, 0.7):
                p.box(a.lerp(b, t) + V((0, 0, 0.055)), (0.06, 0.06, 0.03), "metal",
                      bevel=0.0)
        # reactor heat-exchanger louvres on the upper flanks
        c, r = on_hull(p, FUS, -3.1, 2 if sx > 0 else 6, 0.45, (0.34, 0.9, 0.03), "dark",
                       bevel=0.0)
        n = r.col[2].xyz
        for k in range(6):
            p.box(c + n * 0.025 + r.col[1].xyz * (-0.36 + k * 0.144), (0.3, 0.05, 0.03),
                  "metal", r=r, bevel=0.0)
        # wing maintenance hatch with latches
        h = V((sx * 2.95, -3.9, 0.135))
        p.box(h, (0.5, 0.45, 0.03), "hull2", bevel=0.2)
        for dx in (-0.2, 0.2):
            p.box(h + V((dx, 0.18, 0.02)), (0.06, 0.04, 0.02), "metal", bevel=0.0)
        # IFF / comms blades under the nose
        p.beam(V((sx * 0.3, 3.5, -0.8)), V((sx * 0.34, 3.2, -1.08)), 0.03, 0.18, "dark",
               up=V((0, 1, 0)))
        # ammo loading door under each drum
        c, r = on_hull(p, FUS, 1.75, 0 if sx > 0 else 8, 0.5, (0.3, 0.7, 0.03), "hull3",
                       bevel=0.2)
        p.box(c + r.col[2].xyz * 0.02 + r.col[1].xyz * 0.28, (0.12, 0.05, 0.02), "hazard",
              r=r, bevel=0.0)
        # thrust-pack side access panel
        p.box(V((sx * 1.255, -5.6, ENG_Z - 0.42)), (0.03, 0.5, 0.3), "hull", bevel=0.2)
    # rearm / refuel port, starboard upper flank (port side has the primer panel)
    c, r = face_frame(FUS, -0.9, 2, 0.45)
    n = r.col[2].xyz
    p.tube(c - n * 0.02, c + n * 0.03, 0.15, 0.15, "hazard", segs=12)
    p.tube(c + n * 0.03, c + n * 0.06, 0.11, 0.11, "metal", segs=12)
    p.box(c + n * 0.07, (0.14, 0.03, 0.02), "dark", r=r, bevel=0.0)
    # boarding grips below the port canopy sill, behind the callsign
    for k in range(3):
        a = V((-0.86, 1.25 + k * 0.18, 0.55))
        parts.strut(p, a, a + V((0, 0.12, 0)), 0.03, 0.03, "metal")
    SCORCH.append((c.x, c.y, c.z, 0.2))


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
    else:
        hull.data.uv_layers.remove(hull.data.uv_layers["panel"])
    wk.stats([hull, glow])
    wk.save_and_export(root, BLEND, OUT)
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
