"""Generate the explorer (long-range survey ship) .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_explorer_ship.py
  Add `-- --no-preview` to skip the PNG renders, `-- --no-textures` to skip the atlas bake
  (fast shape iteration: flat colours only), `-- --extra=<dir>` for debug close-ups.

Design: "Pathfinder" class survey vessel, hull SV-07. A long lean needle stacked along the
thrust axis, every section with a job, front to back:
  sensor head  instrument bus on the boom tip: a lidar can with a cyan aperture (scan_point
               in front of it), a hooded survey telescope on top, two foil-wrapped
               spectrometer cans on the flanks, a cooled-detector radiator plate below,
               swept magnetometer rods and a calibration lamp.
  boom         slim lattice boom with a data conduit, a star tracker and a particle
               detector, keeps the instruments clear of the hull and the drive.
  command/lab  compact chamfered armoured module: small viewports on the forward slope,
               side ports, port airlock with hand rails, dorsal docking hatch, comms array
               (dish, phased panel, whips), flush radiators on the upper chamfers, ventral
               ground radar panel and survey camera ball, RCS quads on the four corners,
               two swept whisker antennas with nav lights on the tips.
  spine        open truss with a power / data conduit and a cable tray: two cryo propellant
               tanks forward with a foil-wrapped cold sample store between them, a rack of
               six sample canisters to port, an equipment crate and three survey probes in
               cradles to starboard, pressurant bottles under the keel, the survey dish on
               its mast on top (sensor_dish: turns in game).
  drive        jump-drive coil: a faceted ring with eight coil housings and a cyan emitter
               band on its inner face, around the coil core; shadow shield, banded reactor
               drum with two edge-on radiators (top and bottom, so the needle stays a
               needle from above), thrust frame, turbopumps, thrust truss and one long
               hooped bell.
Science-agency white over a navy belly, survey-blue bands, gold foil on the instruments,
cyan survey lights. Lightly worn. Stencils: "SV-07", "07", "SURVEY", "CRYO", "NO STEP".

Layout (Blender Z up, exported +Y up). Ship centre at origin on the play plane z=0.
The nose points along Blender +Y = Godot -Z (forward), like every other ship.
  length ~19.6 m (bell exit y -8.6 .. lidar aperture y 11.0), width ~3.5 m over the jump
  ring (whisker tips +-2.45), height ~4.0 m over the radiators (z +-2.0; the dish feed
  reaches z ~2.8).
  bell y -8.6..-6.9, reactor y -6.3..-5.0, jump ring y -4.25, spine y -3.5..2.6,
  command/lab y 2.6..6.95, boom y 6.95..9.85, sensor head y 9.85..11.0.
Hierarchy: explorer (empty root) -> explorer_hull, explorer_drive, sensor_dish,
  engine_glow, scan_point (empty).
sensor_dish is its own object with its origin on the mast pivot (DISH_PIVOT, top of the
spine); ExplorerShip turns it about its local Y (Godot up) while surveying, so everything
in it clears the hull at any angle.
engine_glow has its origin on the bell exit plane (Blender y = NOZZLE_Y) and its plume
extends along Godot local +Z, so scaling it on Z lengthens the glow backwards.
scan_point is unrotated, so its Godot -Z points forward out of the lidar aperture.
Textures: one 2048 worn atlas shared by explorer_hull, explorer_drive and sensor_dish
(worn_kit / station_textures bake, kinds re-scaled to ship size and toned down: this ship
is kept cleaner than the miners), saved as blender/textures/explorer_ship_{albedo,mr,
normal}.jpg, material "explorer_ship_hull". Emissive materials stay flat, named
"explorer_ship_*".
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
from parts import ALONG_X, ALONG_Y, V, rot  # noqa: E402

PRE = "explorer_ship"
OUT = os.path.join(common.ROOT, "assets", "models", "ships", "explorer.glb")
BLEND = os.path.join(common.ROOT, "blender", "explorer_ship.blend")

SCAN_Y = 11.0                    # lidar aperture / scan_point
BOOM_Z = -0.15                   # boom and sensor head axis height
HEAD_Y0 = 9.85                   # rear of the sensor head
NOSE_Y = 6.95                    # front of the command module
CMD_Y0 = 2.6                     # rear of the command module
SPINE_Y0 = -3.5                  # spine truss runs SPINE_Y0..CMD_Y0
SPINE_H = 0.45                   # truss half width / height
RING_Y = -4.25                   # jump drive coil ring
RING_R = 1.47                    # ring mid radius
NOZZLE_Y = -8.6
BELL_R = 0.88
BELL_LEN = 1.7
TANK_X, TANK_Z, TANK_R = 1.08, -0.1, 0.58
TANK_Y0, TANK_Y1 = 0.05, 2.35
DISH_PIVOT = (0.0, -1.3, 0.72)   # top of the spine, where the dish mast turns
DISH_R = 1.45
LABELS = ["SV-07", "SURVEY", "#CHEV", "NO STEP", "#BAR", "07", "KEEP CLEAR", "CRYO"]
INK_NAVY = (0.025, 0.05, 0.14)

# Command / lab module stations: (y, w, h, chamfer, z centre)
CMD = (
    (2.6, 1.5, 1.4, 0.38, 0.0),
    (2.85, 2.6, 2.2, 0.6, 0.0),
    (5.0, 2.6, 2.2, 0.6, 0.0),
    (5.9, 2.2, 1.6, 0.52, -0.1),
    (6.6, 1.5, 1.05, 0.34, BOOM_Z),
    (6.95, 1.1, 0.78, 0.24, BOOM_Z),
)

MATS = {}
DECALS = []
SCORCH = []

# Worn kinds at ship scale (process-local overrides). Clean science white, navy, a survey
# blue for the bands; wear is kept low: this hull is looked after.
SHIP_WORN = {
    "hull": dict(big=(1.6, 1.2), plate=(0.8, 0.6),
                 tones=[(0.56, 0.565, 0.56), (0.53, 0.538, 0.54), (0.59, 0.59, 0.58),
                        (0.51, 0.52, 0.525), (0.57, 0.565, 0.55), (0.54, 0.545, 0.545)],
                 plate_var=0.05, rough=(0.5, 0.1), metal=0.05, seam_big=0.45,
                 seam_small=0.18, rivets=True, hatches=0.16, chip=(0.12, 0.125, 0.13),
                 chip_metal=0.8, chip_k=0.6, grime_k=0.6, streak_k=0.18, bleach=0.06),
    "hull2": dict(big=(1.4, 1.0), plate=(0.7, 0.5),
                  tones=[(0.03, 0.062, 0.165), (0.026, 0.054, 0.145), (0.036, 0.072, 0.185),
                         (0.024, 0.05, 0.135), (0.034, 0.064, 0.16), (0.028, 0.058, 0.155)],
                  plate_var=0.08, rough=(0.5, 0.1), metal=0.1, seam_big=0.45,
                  seam_small=0.18, rivets=True, hatches=0.12, chip=(0.32, 0.33, 0.35),
                  chip_metal=0.9, chip_k=0.6, grime_k=0.7, streak_k=0.2, bleach=0.1),
    "hull3": dict(big=(1.2, 1.2), plate=(0.6, 0.6),
                  tones=[(0.33, 0.34, 0.355), (0.31, 0.32, 0.335), (0.35, 0.355, 0.37),
                         (0.3, 0.31, 0.325), (0.335, 0.34, 0.35), (0.315, 0.325, 0.34)],
                  plate_var=0.06, rough=(0.52, 0.1), metal=0.05, seam_big=0.4,
                  seam_small=0.12, rivets=True, hatches=0.14, chip=(0.1, 0.1, 0.105),
                  chip_metal=0.8, chip_k=0.6, grime_k=0.45, streak_k=0.12, bleach=0.08),
    "dark": dict(big=(1.0, 1.0), plate=(0.5, 0.5),
                 tones=[(0.045, 0.047, 0.05), (0.04, 0.042, 0.045), (0.052, 0.054, 0.056),
                        (0.036, 0.038, 0.04), (0.05, 0.048, 0.046), (0.042, 0.044, 0.048)],
                 plate_var=0.06, rough=(0.5, 0.14), metal=0.6, seam_big=0.35,
                 seam_small=0.15, rivets=False, hatches=0.0, chip=(0.26, 0.26, 0.27),
                 chip_metal=1.0, chip_k=0.6, grime_k=0.5, streak_k=0.2, bleach=0.05),
    "metal": dict(big=(1.0, 0.5), plate=(0.5, 0.5),
                  tones=[(0.32, 0.32, 0.33), (0.29, 0.29, 0.295), (0.35, 0.35, 0.355),
                         (0.27, 0.275, 0.28), (0.33, 0.325, 0.32), (0.3, 0.305, 0.31)],
                  plate_var=0.04, rough=(0.34, 0.1), metal=0.9, seam_big=0.3,
                  seam_small=0.1, rivets=False, hatches=0.0, chip=(0.36, 0.36, 0.37),
                  chip_metal=1.0, chip_k=0.0, grime_k=0.7, streak_k=0.25, bleach=0.0),
    "accent": dict(big=(1.2, 0.8), plate=(0.6, 0.4),
                   tones=[(0.05, 0.19, 0.44), (0.045, 0.17, 0.4), (0.06, 0.21, 0.47),
                          (0.04, 0.16, 0.38), (0.055, 0.195, 0.43), (0.05, 0.18, 0.41)],
                   plate_var=0.05, rough=(0.5, 0.1), metal=0.0, seam_big=0.4,
                   seam_small=0.15, rivets=False, hatches=0.0, chip=(0.4, 0.4, 0.4),
                   chip_metal=0.6, chip_k=0.8, grime_k=0.8, streak_k=0.3, bleach=0.12),
    "hazard": dict(big=(1.2, 1.2), plate=(0.6, 0.6),
                   tones=[(0.42, 0.29, 0.04), (0.40, 0.28, 0.035), (0.44, 0.31, 0.045),
                          (0.38, 0.27, 0.04), (0.43, 0.30, 0.04), (0.41, 0.285, 0.04)],
                   plate_var=0.05, rough=(0.6, 0.08), metal=0.0, seam_big=0.3,
                   seam_small=0.1, rivets=False, hatches=0.0, chip=(0.12, 0.12, 0.125),
                   chip_metal=0.7, chip_k=1.2, grime_k=0.9, streak_k=0.3, bleach=0.15,
                   stripes=0.26),
    # heat-tinted bell alloy
    "temper": dict(big=(0.6, 0.5), plate=(0.3, 0.5),
                   tones=[(0.20, 0.16, 0.25), (0.25, 0.17, 0.1), (0.13, 0.16, 0.27),
                          (0.28, 0.21, 0.13), (0.17, 0.13, 0.21), (0.22, 0.2, 0.23)],
                   plate_var=0.15, rough=(0.33, 0.1), metal=0.92, seam_big=0.25,
                   seam_small=0.1, rivets=False, hatches=0.0, chip=(0.3, 0.3, 0.3),
                   chip_metal=1.0, chip_k=0.0, grime_k=0.6, streak_k=0.5, bleach=0.0),
    "radiator": dict(big=(1.6, 0.4), plate=(1.6, 0.2),
                     tones=[(0.30, 0.31, 0.325), (0.28, 0.29, 0.305), (0.32, 0.325, 0.34),
                            (0.27, 0.28, 0.295), (0.31, 0.315, 0.325), (0.29, 0.3, 0.315)],
                     plate_var=0.03, rough=(0.42, 0.08), metal=0.2, seam_big=0.5,
                     seam_small=0.3, rivets=False, hatches=0.0, chip=(0.2, 0.2, 0.2),
                     chip_metal=0.6, chip_k=0.3, grime_k=0.6, streak_k=0.3, bleach=0.0),
    "mli_gold": dict(big=(0.8, 0.6), plate=(0.4, 0.3),
                     tones=[(0.60, 0.39, 0.12), (0.55, 0.35, 0.10), (0.64, 0.43, 0.15),
                            (0.52, 0.34, 0.11), (0.58, 0.38, 0.13), (0.56, 0.36, 0.115)],
                     plate_var=0.05, rough=(0.30, 0.10), metal=1.0, seam_big=0.2,
                     seam_small=0.06, rivets=False, hatches=0.0, chip=(0.6, 0.6, 0.6),
                     chip_metal=1.0, chip_k=0.0, grime_k=0.6, streak_k=0.2, bleach=0.0,
                     quilt=0.45, foil=True),
}
st.WORN_KINDS.update(SHIP_WORN)


def build_materials():
    m = common.make_material
    MATS.clear()
    MATS["hull"] = m(f"{PRE}_paint_white", (0.56, 0.565, 0.56), roughness=0.5)
    MATS["hull2"] = m(f"{PRE}_paint_navy", (0.03, 0.062, 0.165), roughness=0.5)
    MATS["hull3"] = m(f"{PRE}_paint_grey", (0.33, 0.34, 0.355), roughness=0.52)
    MATS["dark"] = m(f"{PRE}_structure", (0.045, 0.047, 0.05), roughness=0.5, metallic=0.6)
    MATS["metal"] = m(f"{PRE}_bare_metal", (0.32, 0.32, 0.33), roughness=0.34, metallic=0.9)
    MATS["accent"] = m(f"{PRE}_survey_blue", (0.05, 0.19, 0.44), roughness=0.5)
    MATS["hazard"] = m(f"{PRE}_hazard", (0.42, 0.29, 0.04), roughness=0.6)
    MATS["temper"] = m(f"{PRE}_temper", (0.2, 0.16, 0.22), roughness=0.33, metallic=0.92)
    MATS["radiator"] = m(f"{PRE}_radiator", (0.3, 0.31, 0.325), roughness=0.42,
                         metallic=0.2)
    MATS["mli_gold"] = m(f"{PRE}_foil_gold", (0.58, 0.38, 0.13), roughness=0.3,
                         metallic=1.0)
    glow = (0.03, 0.028, 0.025)
    MATS["glass"] = m(f"{PRE}_glass_dark", (0.008, 0.011, 0.016), roughness=0.14,
                      emission=(0.16, 0.3, 0.4), emission_strength=0.15)
    MATS["window"] = m(f"{PRE}_window_cool", glow, roughness=0.25,
                       emission=(0.62, 0.84, 1.0), emission_strength=2.2)
    MATS["cyan"] = m(f"{PRE}_light_cyan", glow, roughness=0.3,
                     emission=(0.12, 0.85, 1.0), emission_strength=6.0)
    MATS["drive"] = m(f"{PRE}_coil_emitter", (0.1, 0.4, 0.6), roughness=0.3,
                      emission=(0.1, 0.62, 1.0), emission_strength=4.0)
    MATS["white"] = m(f"{PRE}_light_white", glow, roughness=0.3,
                      emission=(0.9, 0.95, 1.0), emission_strength=6.0)
    MATS["nav_r"] = m(f"{PRE}_nav_red", glow, roughness=0.3,
                      emission=(1.0, 0.05, 0.03), emission_strength=7.0)
    MATS["nav_g"] = m(f"{PRE}_nav_green", glow, roughness=0.3,
                      emission=(0.1, 1.0, 0.25), emission_strength=7.0)
    MATS["lens"] = m(f"{PRE}_lidar_lens", (0.4, 0.8, 0.9), roughness=0.2,
                     emission=(0.35, 0.9, 1.0), emission_strength=7.0)
    MATS["glow"] = m(f"{PRE}_engine_glow", (0.8, 0.95, 1.0), roughness=0.2,
                     emission=(0.62, 0.9, 1.0), emission_strength=6.0)
    for k in ("glass", "window", "cyan", "drive", "white", "nav_r", "nav_g", "lens"):
        MATS[k].use_backface_culling = False


# ---------------------------------------------------------------- helpers
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


class Face:
    """One loft face (between rings r0 and r1, edge j): centre, outward normal, the unit
    vector along the hull, the unit vector across, and both lengths."""

    def __init__(self, r0, r1, j, axis_z=0.0):
        a, b, c, d = r0[j], r0[(j + 1) % 8], r1[(j + 1) % 8], r1[j]
        self.c = (a + b + c + d) / 4
        al = (c + d) / 2 - (a + b) / 2
        ac = (b + c) / 2 - (a + d) / 2
        self.len, self.wid = al.length, ac.length
        self.along, self.across = al.normalized(), ac.normalized()
        n = self.across.cross(self.along).normalized()
        if n.dot(V((self.c.x, 0, self.c.z - axis_z))) < 0:
            n = -n
        self.n = n
        self.r = frame(n, self.along)

    def at(self, u=0.0, v=0.0, out=0.0):
        """Point at u metres across, v metres along from the centre, `out` off the face."""
        return self.c + self.across * u + self.along * v + self.n * out

    def plate(self, p, u, v, w, ln, t, mat, bevel=0.2):
        """Raised plate lying on the face (w across, ln along, t thick)."""
        p.box(self.at(u, v, t * 0.4), (w, ln, t), mat, r=self.r, bevel=bevel)


def rail(p, a, b, n, off=0.09, mat="metal"):
    """Hand rail from a to b standing `off` proud of the surface along n."""
    a, b, n = V(a), V(b), V(n).normalized()
    parts.strut(p, a + n * off, b + n * off, 0.035, 0.035, mat, up=n)
    for q in (a, b):
        parts.strut(p, q, q + n * (off + 0.015), 0.035, 0.035, mat, up=(b - a))


def radiator_panel(p, c, ln, h, ribs=7, up=(0, 0, 1)):
    """Edge-on radiator in the x = 0 plane: `ln` along Y, `h` along up, ribbed both sides,
    dark frame on the three free edges."""
    c, up = V(c), V(up)
    p.box(c, (0.05, ln, h), "radiator", bevel=0.0)
    for k in range(ribs):
        y = -ln / 2 + ln * (k + 0.5) / ribs
        for s in (1, -1):
            p.box(c + V((s * 0.035, y, 0)), (0.03, 0.05, h * 0.96), "metal", bevel=0.0)
    p.box(c + up * (h / 2 + 0.03), (0.09, ln + 0.1, 0.06), "dark", bevel=0.0)
    for s in (1, -1):
        p.box(c + V((0, s * (ln / 2 + 0.025), 0)), (0.09, 0.05, h), "dark", bevel=0.0)


def flush_radiator(p, f, u, v, w, ln, ribs=6):
    """Flush radiator tile on a loft face: panel with coolant ribs across it."""
    f.plate(p, u, v, w, ln, 0.04, "radiator", bevel=0.0)
    for k in range(ribs):
        dv = -ln / 2 + ln * (k + 0.5) / ribs
        p.box(f.at(u, v + dv, 0.045), (w * 0.94, 0.04, 0.03), "metal", r=f.r, bevel=0.0)
    for s in (-1, 1):
        p.box(f.at(u + s * (w / 2 + 0.02), v, 0.03), (0.05, ln + 0.06, 0.05), "dark", r=f.r,
              bevel=0.0)


# ---------------------------------------------------------------- hull
def build_hull():
    p = parts.PanelPart("explorer_hull", MATS)
    command_module(p)
    comms(p)
    whiskers(p)
    boom(p)
    sensor_head(p)
    spine(p)
    tanks(p)
    sample_rack(p)
    pallets(p)
    return p


def command_module(p):
    """Armoured command / lab module: navy belly, blue band, viewports, ports, airlock."""
    rings = rings_of(CMD)

    def cm(i, j):
        if i == 0:
            return "dark"
        if j in (5, 6, 7):
            return "hull2"
        if i == 4:
            return "hull3"
        return "hull"
    p.loft(rings, "hull", mat_fn=cm)
    # survey-blue identity band round the module, just ahead of the neck
    band = [parts.oct_ring(y, 2.64, 2.24, 0.61) for y in (3.02, 3.26)]
    p.loft(band, "accent", cap=False, mat_fn=lambda i, j: "hull2" if j in (5, 6, 7) else "accent")
    # mounting collar where the boom meets the prow
    p.cyl(V((0, NOSE_Y + 0.04, BOOM_Z)), 0.34, 0.3, 0.14, "dark", segs=12, axis_rot=ALONG_Y)
    # --- forward slope: small viewports with armoured brows
    top, cl, cr = (Face(rings[2], rings[3], j) for j in (2, 3, 1))
    for u in (-0.36, 0.0, 0.36):
        parts.window(p, top.at(u, 0.02), top.n, top.along, 0.24, 0.15, "window")
    for f in (cl, cr):
        parts.window(p, f.at(0, 0.02), f.n, f.along, 0.26, 0.15, "window")
    for f, w in ((top, 1.3), (cl, 0.52), (cr, 0.52)):
        p.box(f.at(0, -0.2, 0.05), (w, 0.07, 0.1), "hull3", r=f.r, bevel=0.0)
        p.box(f.at(0, 0.3, 0.02), (w, 0.05, 0.05), "dark", r=f.r, bevel=0.0)
    # prow: armour plates and a forward docking lamp pair
    for j in (1, 2, 3):
        f = Face(rings[3], rings[4], j, axis_z=BOOM_Z)
        f.plate(p, 0, 0, f.wid * 0.62, f.len * 0.7, 0.05, "hull", bevel=0.15)
    for sx in (-1, 1):
        p.box(V((sx * 0.42, NOSE_Y + 0.02, BOOM_Z + 0.2)), (0.1, 0.05, 0.07), "white", bevel=0.0)
        p.box(V((sx * 0.42, NOSE_Y + 0.01, BOOM_Z + 0.2)), (0.18, 0.04, 0.14), "dark", bevel=0.0)
    # --- flanks
    main = {j: Face(rings[1], rings[2], j) for j in range(8)}
    for sx, j in ((1, 0), (-1, 4)):
        f = main[j]
        x = sx * 1.3
        for y in (4.35, 4.75):   # side ports
            parts.window(p, V((x, y, 0.38)), (sx, 0, 0), (0, 0, 1), 0.2, 0.13, "window")
        # lower armour slab with a vent grille
        p.box(V((x, 3.95, -0.28)), (0.06, 1.5, 0.42), "hull", bevel=0.15)
        for k in range(5):
            p.box(V((x + sx * 0.02, 4.45 + k * 0.09, -0.28)), (0.05, 0.04, 0.3), "dark",
                  bevel=0.0)
        rail(p, V((x, 3.45, 0.68)), V((x, 4.95, 0.68)), (sx, 0, 0))
    # port airlock: door in a dark frame, hazard sill, status lamp, grab rails
    x = -1.3
    p.box(V((x, 3.75, 0.18)), (0.07, 0.74, 0.92), "dark", bevel=0.12)
    p.box(V((x - 0.03, 3.75, 0.18)), (0.05, 0.56, 0.74), "hull3", bevel=0.15)
    parts.window(p, V((x - 0.035, 3.75, 0.36)), (-1, 0, 0), (0, 0, 1), 0.1, 0.1, None)
    p.box(V((x - 0.02, 3.75, -0.34)), (0.05, 0.7, 0.08), "hazard", bevel=0.0)
    p.box(V((x - 0.03, 4.2, 0.55)), (0.04, 0.06, 0.06), "cyan", bevel=0.0)
    for y in (3.3, 4.2):
        rail(p, V((x, y, -0.15)), V((x, y, 0.5)), (-1, 0, 0), off=0.1)
    # hull number on the starboard armour slab, agency stencil to port
    label("SV-07", V((1.34, 3.95, -0.28)), (1, 0, 0), (0, 0, 1), 0.27, INK_NAVY, 0.92)
    label("SURVEY", V((-1.31, 4.55, 0.02)), (-1, 0, 0), (0, 0, 1), 0.13, INK_NAVY, 0.85)
    # --- roof: docking hatch, hull number, grip strips
    f = main[2]
    p.cyl(V((0, 3.55, 1.13)), 0.4, 0.44, 0.1, "dark", segs=16)
    p.cyl(V((0, 3.55, 1.19)), 0.33, 0.33, 0.06, "hull3", segs=16)
    p.cyl(V((0, 3.55, 1.23)), 0.12, 0.12, 0.03, "metal", segs=10)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        p.box(V((math.cos(a) * 0.52, 3.55 + math.sin(a) * 0.52, 1.12)), (0.09, 0.09, 0.05),
              "cyan" if k % 2 else "dark", bevel=0.0)
    label("07", V((-0.02, 4.52, 1.1)), (0, 0, 1), (0, 1, 0), 0.42, INK_NAVY, 0.92)
    for sx in (-1, 1):   # grab rails either side of the number, towards the slope
        rail(p, V((sx * 0.62, 4.55, 1.1)), V((sx * 0.62, 4.95, 1.1)), (0, 0, 1))
    # --- upper chamfers: flush radiators (lab heat) and a NO STEP stencil
    for j in (1, 3):
        f = main[j]
        flush_radiator(p, f, 0.0, 0.25, 0.56, 1.25)
        p.box(f.at(0, -0.62, 0.03), (0.3, 0.2, 0.06), "dark", r=f.r, bevel=0.2)
    label("NO STEP", main[1].at(0, -0.82, 0.01), main[1].n, (0, 1, 0), 0.1, INK_NAVY, 0.8)
    # --- belly: ground radar panel, keel conduit, docking lamps
    p.box(V((0, 4.0, -1.13)), (1.0, 1.5, 0.08), "dark", bevel=0.15)
    for k in range(5):
        p.box(V((0, 3.4 + k * 0.3, -1.18)), (0.86, 0.12, 0.04), "hull3", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 0.62, 4.95, -1.12)), (0.1, 0.1, 0.06), "white", bevel=0.0)
    # ventral survey camera: gimbal ball under the forward slope
    c = V((0, 5.5, -0.99))
    p.cyl(c + V((0, 0, 0.04)), 0.3, 0.26, 0.14, "dark", segs=12)
    p.sphere(c + V((0, 0, -0.12)), 0.2, "hull3", segs=12, rings=6)
    p.cyl(c + V((0, 0.17, -0.16)), 0.09, 0.09, 0.06, "glass", segs=10, axis_rot=ALONG_Y)
    # --- lower chamfers: equipment lockers
    for j in (5, 7):
        f = main[j]
        f.plate(p, 0, -0.35, 0.5, 0.9, 0.06, "hull2", bevel=0.15)
        p.box(f.at(0.12, -0.35, 0.06), (0.05, 0.3, 0.04), "metal", r=f.r, bevel=0.0)
    # --- RCS quads on the four corners, fore and aft
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.rcs_quad(p, V((sx * 1.06, 4.82, sz * 0.86)), (sx, 0, sz), "hull3", "metal",
                           s=0.22)
        SCORCH.append((sx * 1.2, 4.82, 0.95, 0.35))
    # --- rear neck: bulkhead ring, spine root clamps
    p.cyl(V((0, CMD_Y0 - 0.02, 0)), 0.86, 0.86, 0.1, "dark", segs=16, axis_rot=ALONG_Y)
    # navigation strobe on the roof aft edge
    p.cyl(V((0, 2.98, 1.14)), 0.07, 0.07, 0.1, "dark", segs=8)
    p.cyl(V((0, 2.98, 1.22)), 0.055, 0.045, 0.07, "white", segs=8)


def comms(p):
    """Comms array on the lab roof: high-gain dish, phased panel, whip cluster."""
    base = V((0.62, 3.95, 1.1))
    p.box(base + V((0, 0, 0.04)), (0.42, 0.42, 0.08), "dark", bevel=0.2)
    p.tube(base, base + V((0, 0, 0.42)), 0.05, 0.045, "metal", segs=8)
    head = base + V((0, 0, 0.45))
    p.box(head, (0.2, 0.18, 0.16), "hull3", bevel=0.2)
    parts.dish(p, head + V((0, -0.02, 0.06)), 0.36, V((0.35, -0.5, 1.0)), "hull", "dark",
               depth=0.13, segs=14)
    # phased array panel, tilted, on the port side
    c = V((-0.62, 4.05, 1.16))
    p.box(c, (0.5, 0.7, 0.05), "hull2", r=rot(ry=-0.2), bevel=0.0)
    for k in range(4):
        p.box(c + V((0.0, -0.24 + k * 0.16, 0.035)), (0.42, 0.08, 0.02), "metal",
              r=rot(ry=-0.2), bevel=0.0)
    p.box(c + V((0.18, 0, -0.07)), (0.12, 0.5, 0.1), "dark", bevel=0.0)
    # whip antennas
    for x, y, h, lean in ((-0.75, 3.1, 1.25, -0.2), (-0.55, 3.0, 0.8, -0.1),
                          (0.8, 3.1, 1.0, 0.15)):
        b = V((x, y, 1.1))
        p.box(b + V((0, 0, 0.03)), (0.12, 0.12, 0.08), "dark", bevel=0.0)
        p.tube(b, b + V((lean, -h * 0.25, h)), 0.02, 0.01, "metal", segs=5)


def whiskers(p):
    """Two long swept whisker antennas (low-frequency survey receivers), nav lights."""
    for sx in (-1, 1):
        root = V((sx * 1.32, 3.12, 0.12))
        tip = V((sx * 2.45, -0.1, 0.36))
        p.box(root, (0.2, 0.44, 0.34), "hull3", bevel=0.2)
        p.box(root + V((sx * 0.08, -0.05, 0)), (0.14, 0.2, 0.2), "dark", bevel=0.2)
        p.tube(root + V((sx * 0.1, -0.1, 0)), tip, 0.05, 0.022, "metal", segs=6)
        for t in (0.3, 0.62):
            q = root.lerp(tip, t)
            p.tube(q - V((sx * 0.03, -0.08, 0)) * 1.0, q + V((sx * 0.03, -0.08, 0)), 0.065,
                   0.065, "dark", segs=6)
        # bracing stay back to the neck
        parts.pipe(p, root.lerp(tip, 0.3), V((sx * 0.72, 2.62, 0.3)), 0.015, "dark", segs=4)
        p.box(tip, (0.07, 0.12, 0.07), "nav_g" if sx > 0 else "nav_r", bevel=0.0)


def boom(p):
    """Slim lattice instrument boom from the prow to the sensor head."""
    y0, y1 = NOSE_Y + 0.08, HEAD_Y0
    parts.box_truss(p, y0, y1, 0.17, 0.17, 6, "hull3", "dark", chord=0.055, brace=0.035,
                    z0=BOOM_Z)
    parts.pipe(p, V((0, y0, BOOM_Z)), V((0, y1, BOOM_Z)), 0.06, "metal", segs=6)
    parts.pipe(p, V((0.09, y0, BOOM_Z + 0.1)), V((0.09, y1, BOOM_Z + 0.1)), 0.02, "dark",
               segs=4)
    # star tracker (top) and particle detector (port), survey light
    c = V((0, 7.9, BOOM_Z + 0.27))
    p.box(c, (0.26, 0.34, 0.2), "hull", bevel=0.2)
    p.tube(c + V((0.0, 0.05, 0.08)), c + V((0.0, 0.2, 0.3)), 0.07, 0.09, "dark", segs=8)
    c = V((-0.27, 8.75, BOOM_Z))
    p.box(c, (0.2, 0.4, 0.24), "mli_gold", bevel=0.2)
    p.cyl(c + V((-0.12, 0, 0)), 0.07, 0.07, 0.06, "dark", segs=8, axis_rot=ALONG_X)
    p.box(V((0, 9.2, BOOM_Z + 0.2)), (0.07, 0.1, 0.04), "cyan", bevel=0.0)
    p.box(V((0, 7.35, BOOM_Z + 0.2)), (0.07, 0.1, 0.04), "cyan", bevel=0.0)


def sensor_head(p):
    """Instrument bus on the boom tip: lidar, telescope, spectrometers, magnetometers."""
    z = BOOM_Z
    y0 = HEAD_Y0
    p.box(V((0, y0 + 0.03, z)), (0.96, 0.08, 0.84), "dark", bevel=0.15)
    rings = [parts.oct_ring(y0 + 0.06, 0.7, 0.62, 0.18, z0=z),
             parts.oct_ring(y0 + 0.14, 0.82, 0.72, 0.2, z0=z),
             parts.oct_ring(y0 + 0.62, 0.82, 0.72, 0.2, z0=z),
             parts.oct_ring(y0 + 0.72, 0.62, 0.54, 0.15, z0=z)]
    p.loft(rings, "hull", mat_fn=lambda i, j: ("hull2" if j in (5, 6, 7) else
                                               ("hull3" if i != 1 else "hull")))
    p.box(V((0, y0 + 0.38, z + 0.37)), (0.3, 0.3, 0.03), "accent", bevel=0.0)
    # lidar: can, baffle rings, glowing aperture (scan_point just ahead)
    p.cyl(V((0, y0 + 0.9, z)), 0.2, 0.2, 0.4, "hull", segs=14, axis_rot=ALONG_Y)
    for y in (y0 + 0.78, y0 + 0.98):
        p.cyl(V((0, y, z)), 0.225, 0.225, 0.05, "dark", segs=14, axis_rot=ALONG_Y)
    p.cyl(V((0, SCAN_Y - 0.06, z)), 0.235, 0.21, 0.08, "dark", segs=14, axis_rot=ALONG_Y)
    p.cyl(V((0, SCAN_Y - 0.025, z)), 0.16, 0.16, 0.03, "lens", segs=14, axis_rot=ALONG_Y)
    # survey telescope on top: tube, sun hood cut on the slant, dark objective
    tz = z + 0.52
    p.cyl(V((0, y0 + 0.5, tz)), 0.15, 0.15, 0.8, "hull", segs=12, axis_rot=ALONG_Y)
    p.cyl(V((0, y0 + 0.14, tz)), 0.17, 0.17, 0.1, "mli_gold", segs=12, axis_rot=ALONG_Y)
    p.cyl(V((0, y0 + 0.86, tz)), 0.165, 0.165, 0.06, "dark", segs=12, axis_rot=ALONG_Y)
    p.cyl(V((0, y0 + 0.905, tz)), 0.125, 0.125, 0.01, "glass", segs=12, axis_rot=ALONG_Y)
    p.box(V((0, y0 + 0.98, tz + 0.15)), (0.26, 0.3, 0.03), "dark", r=rot(rx=0.12), bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 0.1, y0 + 0.45, tz - 0.14)), (0.06, 0.5, 0.08), "dark", bevel=0.0)
    # spectrometer cans on the flanks, gold foil, cooled: lines to the radiator plate
    for sx in (-1, 1):
        x = sx * 0.52
        p.cyl(V((x, y0 + 0.45, z + 0.02)), 0.11, 0.11, 0.62, "mli_gold", segs=10,
              axis_rot=ALONG_Y)
        p.cyl(V((x, y0 + 0.79, z + 0.02)), 0.12, 0.1, 0.08, "dark", segs=10, axis_rot=ALONG_Y)
        p.cyl(V((x, y0 + 0.835, z + 0.02)), 0.075, 0.075, 0.01, "glass", segs=10,
              axis_rot=ALONG_Y)
        p.box(V((sx * 0.44, y0 + 0.4, z + 0.02)), (0.1, 0.12, 0.12), "dark", bevel=0.0)
        parts.pipe(p, V((x, y0 + 0.2, z - 0.08)), V((sx * 0.3, y0 + 0.2, z - 0.42)), 0.02,
                   "metal", segs=4)
        # magnetometer rods, swept back and out
        b = V((sx * 0.42, y0 + 0.1, z + 0.3))
        p.tube(b, b + V((sx * 0.75, -0.75, 0.25)), 0.02, 0.01, "metal", segs=5)
        p.box(b + V((sx * 0.75, -0.75, 0.25)), (0.06, 0.1, 0.06), "dark", bevel=0.0)
    # cooled-detector radiator plate under the bus
    p.box(V((0, y0 + 0.36, z - 0.42)), (0.7, 0.56, 0.04), "radiator", bevel=0.0)
    for k in range(4):
        p.box(V((0, y0 + 0.15 + k * 0.14, z - 0.445)), (0.66, 0.03, 0.03), "metal", bevel=0.0)
    # calibration lamps
    for sx in (-1, 1):
        p.box(V((sx * 0.3, y0 + 0.74, z - 0.2)), (0.07, 0.04, 0.07), "cyan", bevel=0.0)


def spine(p):
    """Open spine truss with conduit, cable tray, keel plate and survey lights."""
    h = SPINE_H
    parts.box_truss(p, SPINE_Y0, CMD_Y0, h, h, 6, "hull3", "dark", chord=0.14, brace=0.07)
    yc, ln = (SPINE_Y0 + CMD_Y0) / 2, CMD_Y0 - SPINE_Y0
    p.cyl(V((0, yc, 0)), 0.2, 0.2, ln, "metal", segs=10, axis_rot=ALONG_Y)
    for y in (-2.9, -1.9, -0.9, 0.1, 1.1, 2.1):   # conduit clamps
        p.cyl(V((0, y + 0.3, 0)), 0.23, 0.23, 0.1, "dark", segs=10, axis_rot=ALONG_Y)
    # cable tray along the top, keel plate along the bottom
    p.box(V((0.2, yc, h + 0.08)), (0.26, ln - 0.3, 0.05), "dark", bevel=0.0)
    for k in (-1, 1):
        parts.pipe(p, V((0.2 + k * 0.06, SPINE_Y0 + 0.2, h + 0.13)),
                   V((0.2 + k * 0.06, CMD_Y0 - 0.2, h + 0.13)), 0.025,
                   "accent" if k > 0 else "metal", segs=5)
    p.box(V((0, yc, -h - 0.09)), (0.6, ln - 0.4, 0.05), "hull2", bevel=0.0)
    # cold sample store on the roof between the tanks: foil box with its own radiator
    c = V((-0.05, 1.45, h + 0.25))
    p.box(c, (0.56, 0.9, 0.34), "mli_gold", bevel=0.15)
    p.box(c + V((0, 0, 0.19)), (0.4, 0.7, 0.04), "radiator", bevel=0.0)
    for k in range(4):
        p.box(c + V((0, -0.24 + k * 0.16, 0.215)), (0.36, 0.04, 0.03), "metal", bevel=0.0)
    p.box(c + V((0, -0.5, -0.05)), (0.3, 0.12, 0.2), "dark", bevel=0.0)
    # dish mast base (the dish object sits on DISH_PIVOT)
    px, py, pz = DISH_PIVOT
    p.box(V((px, py, h + 0.1)), (1.04, 0.5, 0.1), "dark", bevel=0.0)
    p.cyl(V((px, py, pz - 0.1)), 0.36, 0.3, 0.2, "hull3", segs=14)
    p.torus(V((px, py, pz - 0.02)), 0.3, 0.03, "metal", segs=14, minor_segs=4)
    # junction boxes on the upper chords, pressurant bottles under the aft keel
    for y, sx in ((2.0, 1), (0.3, -1), (-0.5, 1), (-2.9, -1)):
        p.box(V((sx * h, y, h + 0.03)), (0.2, 0.3, 0.16), "hull2", bevel=0.2)
    for y in (-2.55, -3.08):
        c = V((0, y, -h - 0.35))
        p.sphere(c, 0.23, "mli_gold", segs=12, rings=6)
        p.torus(c, 0.235, 0.025, "dark", segs=12, minor_segs=4, matrix=rot(rx=math.pi / 2))
        p.cyl(c + V((0, 0, 0.22)), 0.05, 0.05, 0.12, "metal", segs=6)
    # survey lights along the roof
    for y in (2.2, 0.55, -3.1):
        p.box(V((-0.25, y, h + 0.09)), (0.09, 0.14, 0.04), "cyan", bevel=0.0)


def tanks(p):
    """Two cryo propellant tanks slung either side of the forward spine."""
    def tm(i, j):
        return "hull" if j == 3 else "hull3"
    ym = (TANK_Y0 + TANK_Y1) / 2
    for sx in (-1, 1):
        x = sx * TANK_X
        parts.capsule(p, TANK_Y0, TANK_Y1, TANK_R, tm, segs=16, x=x, z=TANK_Z, dome0=0.7,
                      dome1=0.7, steps=3)
        p.cyl(V((x, ym + 0.1, TANK_Z)), TANK_R + 0.012, TANK_R + 0.012, 0.3, "accent", segs=16,
              axis_rot=ALONG_Y)
        for y in (TANK_Y0 + 0.62, TANK_Y1 - 0.62):   # straps and saddles to the truss
            p.cyl(V((x, y, TANK_Z)), TANK_R + 0.035, TANK_R + 0.035, 0.09, "dark", segs=16,
                  axis_rot=ALONG_Y)
            for z in (0.36, -0.42):
                p.beam(V((sx * 0.45, y, z)), V((sx * 0.68, y, z)), 0.12, 0.12, "dark")
        # fill / vent fittings on top, feed line aft along the spine to the drive
        p.cyl(V((x, ym - 0.45, TANK_Z + TANK_R + 0.03)), 0.09, 0.09, 0.1, "metal", segs=8)
        p.box(V((x, ym + 0.75, TANK_Z + TANK_R + 0.02)), (0.16, 0.2, 0.07), "dark", bevel=0.2)
        a = V((x, TANK_Y0 + 0.02, TANK_Z))
        b = V((sx * 0.3, TANK_Y0 - 0.35, -0.6))
        parts.pipe(p, a, b, 0.045, "metal", segs=6)
        parts.pipe(p, b, V((sx * 0.3, SPINE_Y0, -0.6)), 0.045, "metal", segs=6)
        label("CRYO", V((x + sx * 0.1, ym - 0.5, TANK_Z + TANK_R * 0.99)), (0, 0, 1),
              (0, 1, 0), 0.12, INK_NAVY, 0.85)


def sample_rack(p):
    """Port side: six sealed sample canisters standing in a two-shelf rack."""
    ys = (-0.85, -1.7, -2.55)
    xs = (-0.84, -1.36)
    xc, yc = (xs[0] + xs[1]) / 2, ys[1]
    p.box(V((xc, yc, -0.36)), (1.12, 2.5, 0.06), "dark", bevel=0.0)
    for x in (xs[0] + 0.3, xc, xs[1] - 0.3):       # open top shelf: rails and cross bars
        p.beam(V((x, yc - 1.25, 0.3)), V((x, yc + 1.25, 0.3)), 0.07, 0.06, "hull3")
    for y in (ys[0] + 0.42, yc + 0.42, yc - 0.42, ys[2] - 0.42):
        p.beam(V((xs[0] + 0.3, y, 0.3)), V((xs[1] - 0.3, y, 0.3)), 0.07, 0.06, "hull3")
    for y in (ys[0] + 0.42, ys[2] - 0.42):
        for z in (0.3, -0.36):
            p.beam(V((-SPINE_H, y, z)), V((xs[0] + 0.2, y, z)), 0.12, 0.1, "dark")
    for sy in (-1, 1):   # end posts
        for x in (xs[0] + 0.4, xs[1] - 0.2):
            parts.strut(p, V((x, yc + sy * 1.22, -0.36)), V((x, yc + sy * 1.22, 0.3)), 0.06,
                        0.06, "dark", up=V((0, 1, 0)))
    for i, y in enumerate(ys):
        for k, x in enumerate(xs):
            body = "hull" if (i + k) % 3 else "hull3"
            p.cyl(V((x, y, 0.0)), 0.235, 0.235, 0.92, body, segs=12)
            p.cyl(V((x, y, 0.18)), 0.243, 0.243, 0.1, "accent", segs=12)
            p.cyl(V((x, y, 0.49)), 0.2, 0.17, 0.07, "metal", segs=12)
            p.box(V((x, y, 0.545)), (0.22, 0.05, 0.04), "dark", bevel=0.0)
            if (i + k) % 2 == 0:
                p.box(V((x + 0.12, y + 0.12, 0.5)), (0.05, 0.05, 0.05), "cyan", bevel=0.0)


def pallets(p):
    """Starboard side: an equipment crate and three survey probes in launch cradles."""
    # crate on a latch plate
    c = V((1.02, -0.9, 0.0))
    p.box(V((0.75, -0.9, 0.0)), (0.5, 0.9, 0.5), "dark", bevel=0.0)
    p.box(c, (0.92, 1.05, 0.84), "hull3", bevel=0.08)
    for sy in (-1, 1):
        p.box(c + V((0, sy * 0.46, 0)), (0.98, 0.1, 0.9), "dark", bevel=0.0)
    p.box(c + V((0, 0.08, 0)), (0.94, 0.16, 0.86), "accent", bevel=0.0)
    p.box(c + V((0.1, -0.2, 0.43)), (0.4, 0.3, 0.04), "hull", bevel=0.2)
    p.box(c + V((0.47, -0.2, 0.1)), (0.04, 0.2, 0.08), "metal", bevel=0.0)
    # probe cradle: three probes nose forward, clamp bars over them
    y0, y1 = -3.1, -1.85
    xs = (0.78, 1.14, 1.5)
    p.box(V((1.1, (y0 + y1) / 2, -0.24)), (1.16, 1.3, 0.08), "hull3", bevel=0.0)
    for y in (y0 + 0.3, y1 - 0.35):
        p.beam(V((SPINE_H, y, -0.24)), V((0.7, y, -0.24)), 0.14, 0.1, "dark")
        p.box(V((1.14, y, 0.14)), (1.1, 0.08, 0.05), "hazard", bevel=0.0)
        for x in (0.6, 0.96, 1.32, 1.68):
            parts.strut(p, V((x, y, -0.22)), V((x, y, 0.14)), 0.05, 0.05, "dark",
                        up=V((0, 1, 0)))
    for k, x in enumerate(xs):
        parts.capsule(p, y0, y1, 0.15, lambda i, j: "hull2" if j < 2 else "hull", segs=10,
                      x=x, z=-0.04, dome0=0.3, dome1=1.2, steps=2)
        p.cyl(V((x, y0 + 0.02, -0.04)), 0.1, 0.12, 0.08, "dark", segs=8, axis_rot=ALONG_Y)
        p.box(V((x, y1 - 0.62, 0.12)), (0.05, 0.08, 0.04), "cyan" if k != 1 else "dark",
              bevel=0.0)


# ---------------------------------------------------------------- survey dish
def build_dish():
    """Survey dish on a short mast, built around DISH_PIVOT (the object origin) so the game
    can turn the object about its local up axis."""
    p = parts.PanelPart("sensor_dish", MATS)
    p.cyl(V((0, 0, 0.05)), 0.27, 0.27, 0.1, "dark", segs=14)             # turntable
    p.tube(V((0, 0, 0.1)), V((0, 0, 0.72)), 0.1, 0.085, "metal", segs=10)   # mast
    p.box(V((0, 0, 0.74)), (0.62, 0.22, 0.26), "hull2", bevel=0.2)          # elevation yoke
    for sx in (-1, 1):
        p.cyl(V((sx * 0.33, 0, 0.76)), 0.1, 0.1, 0.06, "metal", segs=10, axis_rot=ALONG_X)
    n = V((0, 0.5, 1)).normalized()
    c = V((0, 0.06, 0.98))
    m = Matrix.Translation(c) @ n.to_track_quat("Z", "Y").to_matrix().to_4x4()
    r, d = DISH_R, 0.36
    prof = [(0.0, 0.0), (r * 0.33, d * 0.11), (r * 0.66, d * 0.44), (r, d),
            (r + 0.03, d - 0.03), (r * 0.66, d * 0.44 - 0.06), (r * 0.33, d * 0.11 - 0.07),
            (0.0, -0.08)]

    def dm(i, j):
        if j == 3:
            return "accent"
        if j > 3:
            return "hull3"
        return "hull3" if j == 0 else "hull"
    p.lathe(prof, 24, dm, matrix=m)
    # back structure: hub, radial ribs, a ring stiffener, elevation actuator
    p.cyl(m @ V((0, 0, -0.14)), 0.34, 0.3, 0.16, "hull2", segs=14, axis_rot=m.to_3x3().to_4x4())
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        ca, sa = math.cos(a), math.sin(a)
        parts.strut(p, m @ V((0.28 * ca, 0.28 * sa, -0.14)),
                    m @ V((0.9 * r * ca, 0.9 * r * sa, d * 0.81 - 0.08)), 0.05, 0.07, "dark",
                    up=n)
    p.torus(m @ V((0, 0, d * 0.44 - 0.1)), r * 0.66, 0.03, "dark", segs=24, minor_segs=4,
            matrix=m.to_3x3().to_4x4())
    p.tube(V((0, -0.1, 0.62)), m @ V((0, -0.5 * r, 0.02)), 0.035, 0.03, "metal", segs=6)
    # feed: tripod, subreflector, receiver can with a cyan status light
    tip = m @ V((0, 0, d + r * 0.52))
    for k in range(3):
        a = k * 2 * math.pi / 3 + math.pi / 2
        parts.strut(p, m @ V((0.92 * r * math.cos(a), 0.92 * r * math.sin(a), d - 0.02)), tip,
                    0.03, 0.03, "dark", up=n)
    p.tube(tip - n * 0.16, tip + n * 0.04, 0.16, 0.1, "hull2", segs=10)
    p.tube(tip + n * 0.04, tip + n * 0.1, 0.07, 0.07, "cyan", segs=8)
    p.tube(m @ V((0, 0, 0.0)), m @ V((0, 0, 0.2)), 0.1, 0.06, "dark", segs=10)
    return p


# ---------------------------------------------------------------- drive
def build_drive():
    p = parts.PanelPart("explorer_drive", MATS)
    jump_coil(p)
    reactor(p)
    engine(p)
    return p


def jump_coil(p):
    """Jump-drive coil: faceted ring, eight coil housings, cyan emitter band inside."""
    c = V((0, RING_Y, 0))
    p.cyl(V((0, SPINE_Y0 - 0.06, 0)), 0.82, 0.82, 0.12, "dark", segs=16, axis_rot=ALONG_Y)
    # coil core through the ring
    p.cyl(V((0, RING_Y - 0.03, 0)), 0.52, 0.52, 1.3, "hull", segs=16, axis_rot=ALONG_Y)
    for dy in (-0.42, 0.42):
        p.cyl(c + V((0, dy, 0)), 0.55, 0.55, 0.1, "dark", segs=16, axis_rot=ALONG_Y)
    p.cyl(c, 0.545, 0.545, 0.34, "hull2", segs=16, axis_rot=ALONG_Y)
    p.cyl(c, 0.56, 0.56, 0.08, "drive", segs=16, axis_rot=ALONG_Y)
    # ring body: chamfered box section; emitter strips on the inner face
    ri, ro, hw = RING_R - 0.17, RING_R + 0.15, 0.25
    prof = [(ri, -hw + 0.07), (ri + 0.07, -hw), (ro - 0.07, -hw), (ro, -hw + 0.07),
            (ro, hw - 0.07), (ro - 0.07, hw), (ri + 0.07, hw), (ri, hw - 0.07),
            (ri, -hw + 0.07)]

    def rm(i, j):
        if j == 7:
            return "dark" if i % 3 == 0 else "drive"
        return "hull2"
    p.lathe(prof, 24, rm, matrix=Matrix.Translation(c) @ ALONG_Y)
    for dy in (-hw - 0.02, hw + 0.02):   # conduit hoops on both faces
        p.torus(c + V((0, dy, 0)), RING_R + 0.02, 0.035, "metal", segs=24, minor_segs=4,
                matrix=rot(rx=math.pi / 2))
    # coil housings round the ring
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        d = V((math.cos(a), 0, math.sin(a)))
        r = frame(d, (0, 1, 0))
        q = c + d * (RING_R + 0.03)
        p.box(q, (0.56, 0.74, 0.46), "hull" if k % 2 else "hull3", r=r, bevel=0.14)
        for s in (-1, 0, 1):   # cooling ribs on the outer face
            p.box(q + d * 0.235 + V((0, s * 0.2, 0)), (0.42, 0.06, 0.04), "dark", r=r,
                  bevel=0.0)
        if k % 2:
            p.box(q + V((0, 0.375, 0)), (0.4, 0.02, 0.1), "hazard", r=r, bevel=0.0)
    # struts from the core to the ring, with power lines
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        d = V((math.cos(a), 0, math.sin(a)))
        p.beam(c + d * 0.5, c + d * (ri + 0.03), 0.18, 0.12, "hull3", up=V((0, 1, 0)))
        parts.pipe(p, c + d * 0.5 + V((0, 0.13, 0)), c + d * ri + V((0, 0.13, 0)), 0.03,
                   "metal", segs=5)
        p.box(c + d * 0.62, (0.22, 0.26, 0.22), "dark", r=frame(d, (0, 1, 0)), bevel=0.2)


def reactor(p):
    """Shadow shield, banded reactor drum, heat exchangers, edge-on radiators, RCS."""
    p.cyl(V((0, -4.97, 0)), 0.9, 0.84, 0.12, "dark", segs=18, axis_rot=ALONG_Y)
    rc = V((0, -5.65, 0))
    p.cyl(rc, 0.7, 0.7, 1.24, "hull3", segs=18, axis_rot=ALONG_Y)
    for dy in (-0.42, 0.0, 0.42):
        p.torus(rc + V((0, dy, 0)), 0.71, 0.04, "dark", segs=18, minor_segs=4,
                matrix=rot(rx=math.pi / 2))
    p.cyl(rc + V((0, 0.22, 0)), 0.72, 0.72, 0.16, "hazard", segs=18, axis_rot=ALONG_Y)
    p.cyl(rc + V((0, -0.2, 0)), 0.715, 0.715, 0.2, "hull", segs=18, axis_rot=ALONG_Y)
    # heat exchangers on the flanks, with coolant lines up to the radiator roots
    for sx in (-1, 1):
        q = rc + V((sx * 0.74, -0.05, 0))
        p.box(q, (0.26, 0.86, 0.52), "hull2", bevel=0.2)
        for k in range(4):
            p.box(q + V((sx * 0.135, -0.27 + k * 0.18, 0)), (0.03, 0.07, 0.4), "dark",
                  bevel=0.0)
        p.box(q + V((sx * 0.135, 0.36, 0.15)), (0.03, 0.06, 0.06), "cyan", bevel=0.0)
        for sz in (-1, 1):
            parts.pipe(p, q + V((0, -0.3, sz * 0.2)), V((sx * 0.06, -5.95, sz * 0.8)), 0.035,
                       "accent", segs=5)
    # radiators top and bottom, edge-on from above
    for sz in (-1, 1):
        up = V((0, 0, sz))
        radiator_panel(p, V((0, -5.9, sz * 1.42)), 2.0, 1.12, ribs=8, up=up)
        parts.pipe(p, V((0, -6.9, sz * 0.82)), V((0, -4.9, sz * 0.82)), 0.05, "metal", segs=6)
        for y in (-5.3, -6.0):
            p.box(V((0, y, sz * 0.76)), (0.22, 0.2, 0.2), "dark", bevel=0.2)
        p.box(V((0, -4.86, sz * 1.95)), (0.08, 0.08, 0.08), "cyan", bevel=0.0)
        p.box(V((0, -6.94, sz * 1.95)), (0.08, 0.08, 0.08), "white", bevel=0.0)
    # RCS quads on the diagonals
    for sx in (-1, 1):
        for sz in (-1, 1):
            d = V((sx, 0, sz)).normalized()
            parts.rcs_quad(p, V((0, -6.08, 0)) + d * 0.79, d, "hull3", "metal", s=0.22)
        SCORCH.append((sx * 0.7, -6.08, 0.7, 0.35))


def engine(p):
    """Thrust frame, turbopumps, gimbal actuators and the one long bell."""
    y_throat = NOZZLE_Y + BELL_LEN
    p.cyl(V((0, -6.3, 0)), 0.62, 0.56, 0.1, "dark", segs=18, axis_rot=ALONG_Y)
    p.loft([parts.oct_ring(-6.34, 1.2, 1.2, 0.35), parts.oct_ring(-6.62, 1.1, 1.1, 0.32),
            parts.oct_ring(y_throat + 0.02, 0.74, 0.74, 0.22)], "hull2",
           mat_fn=lambda i, j: "hull2" if i == 0 else "dark")
    p.box(V((0, -6.48, 0.61)), (0.6, 0.12, 0.03), "hazard", bevel=0.0)
    p.box(V((0, -6.48, -0.61)), (0.6, 0.12, 0.03), "hazard", bevel=0.0)
    # turbopumps either side of the throat, feed lines
    for sx in (-1, 1):
        q = V((sx * 0.5, -6.95, 0))
        p.cyl(q, 0.13, 0.13, 0.4, "metal", segs=10, axis_rot=ALONG_Y)
        p.cyl(q + V((0, 0.1, 0)), 0.15, 0.15, 0.08, "dark", segs=10, axis_rot=ALONG_Y)
        parts.pipe(p, q + V((0, -0.2, 0)), V((sx * 0.4, -7.3, 0)), 0.04, "metal", segs=5)
        parts.pipe(p, V((sx * 0.4, -7.3, 0)), V((sx * 0.36, -7.3, 0)), 0.04, "metal", segs=5)
    for sz in (-1, 1):   # gimbal actuators
        p.tube(V((0, -6.7, sz * 0.42)), V((0, -7.35, sz * 0.5)), 0.045, 0.03, "metal", segs=6)
        p.box(V((0, -7.35, sz * 0.52)), (0.12, 0.1, 0.08), "dark", bevel=0.0)
    parts.bell(p, NOZZLE_Y, BELL_R, BELL_LEN, "temper", "dark", segs=20)
    rt = BELL_R * 0.42

    def bell_r(y):
        return rt + (BELL_R - rt) * ((y_throat - y) / BELL_LEN) ** 0.65
    for y, minor, mat in ((-7.35, 0.045, "dark"), (-7.65, 0.025, "metal"),
                          (-7.95, 0.035, "dark"), (-8.25, 0.025, "metal"),
                          (NOZZLE_Y + 0.06, 0.035, "dark")):
        p.torus(V((0, y, 0)), bell_r(y) + 0.01, minor, mat, segs=20, minor_segs=4,
                matrix=rot(rx=math.pi / 2))
    for k in range(4):   # thrust truss from the frame to the first bell hoop
        a = k * math.pi / 2 + math.pi / 4
        d = V((math.cos(a), 0, math.sin(a)))
        parts.strut(p, V((0, -6.55, 0)) + d * 0.6, V((0, -7.35, 0)) + d * (bell_r(-7.35) + 0.03),
                    0.05, 0.05, "metal", up=d)
    for sx in (-1, 1):   # propellant feed lines from the spine past the reactor
        pts = (V((sx * 0.3, SPINE_Y0, -0.6)), V((sx * 0.3, -4.95, -0.6)),
               V((sx * 0.36, -5.1, -0.7)), V((sx * 0.36, -6.3, -0.7)),
               V((sx * 0.3, -6.5, -0.5)))
        for a, b in zip(pts, pts[1:]):
            parts.pipe(p, a, b, 0.045, "metal", segs=6)
    p.cyl(V((0, y_throat - 0.02, 0)), rt + 0.08, rt + 0.04, 0.16, "metal", segs=16,
          axis_rot=ALONG_Y)
    SCORCH.append((0.0, NOZZLE_Y + 0.3, 0.0, 1.0))


def build_glow():
    p = parts.Part("engine_glow", MATS)
    # Built around the bell exit plane at y = 0 (object origin moved to NOZZLE_Y below).
    parts.exhaust_glow(p, BELL_R * 0.85, 1.2, "glow", segs=16)
    return p


def build_ship():
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    root = parts.make_root("explorer")
    hull = build_hull().finish(root)
    drive = build_drive().finish(root)
    dish = build_dish().finish(root)
    glow = build_glow().finish(root)
    dish.location = DISH_PIVOT
    glow.location = (0, NOZZLE_Y, 0)
    parts.add_empty("scan_point", root, (0, SCAN_Y, BOOM_Z), size=1.0)
    return root, hull, drive, dish, glow


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, hull, drive, dish, glow = build_ship()
    bpy.context.view_layer.update()
    skinned = [hull, drive, dish]
    if "--no-textures" not in argv:
        glow.hide_render = True
        wk.texture(skinned, MATS, PRE, [(0.0, 0.0)], scorch=SCORCH, decals=DECALS,
                   labels=LABELS, seed0=207)
        glow.hide_render = False
    else:
        for o in skinned:
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    wk.stats(skinned + [glow])
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews("explorer", 21.0, target=(0, 1.0, 0))
    extra = [a.split("=", 1)[1] for a in argv if a.startswith("--extra=")]
    if extra:
        extra_views(extra[0])


def extra_views(out_dir):
    """Debug renders into out_dir (close-ups, side, belly, RTS angle); not part of the
    previews. Needs the preview camera, so it does nothing with --no-preview."""
    scene = bpy.context.scene
    cam = scene.camera
    if cam is None:
        return
    os.makedirs(out_dir, exist_ok=True)
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1200
    views = (("nose", (-7, 15, 6), (0, 8.0, 0.0), 8.0),
             ("lab", (-8, 9, 8), (0, 3.5, 0.2), 8.0),
             ("stbd", (9, 8, 6), (0, 3.2, 0.0), 9.0),
             ("spine", (-9, 2, 9), (0, -0.8, 0.3), 9.0),
             ("drive", (-8, -13, 7), (0, -5.6, 0.0), 9.0),
             ("side", (-30, 1.2, 0), (0, 1.2, 0), 22.0),
             ("belly", (-10, 9, -10), (0, 1.0, -0.5), 22.0),
             ("rts", (-6, -13, 30), (0, 1.5, 0), 30.0))
    for name, loc, tgt, ortho in views:
        cam.location = loc
        cam.rotation_euler = (V(tgt) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        cam.data.ortho_scale = ortho
        common.render(os.path.join(out_dir, f"explorer_{name}.png"))


main()
