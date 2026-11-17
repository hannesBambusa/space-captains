"""Generate the colony ship .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_colony_ship.py
  Options after `--`: --no-preview (skip the PNG renders), --no-textures (flat colours, no
  Cycles bake: fast shape iteration), --extra=<dir> (debug close-ups into <dir>).

Design: "Longhaul" class station carrier CV-07, a slow heavy hauler that flies a folded
forward station through the jump gates (the MobileStation's drive tug). Hard sci-fi, built
along the thrust axis, no wings or fairings. Front to back:
  command    armoured faceted command module: slab plates, slit viewports on the nose
             slopes under armour brows, side airlock with handrails, nose docking ring and
             headlamps, comms array on the roof (dish on a mast, whips, phased array panel,
             sensor dome), RCS quads on four outriggers, colony green band.
  collar     docking collar drum with three radial ports (top, port, starboard), hazard
             rims and guide lamps.
  spine      massive braced box truss around a pressurised transfer tube, keel plate, cable
             tray, coolant lines, saddle frames at every module mount, amber marker lamps.
             The station kit rides on it, folded for transit and held by clamps with hazard
             pads:
               module_hab_1   twin habitat cans straddling the spine (the forward station's
                              prefab can modules: ribbed, green band, mostly dark ports)
               module_dish    comms dish folded shut, six petals closed into a bud on a
                              pallet on the spine top, restraint band round the petals
               module_wing_l  folded solar wing cassette: stacked blanket leaves in a
                              strapped frame beside its mast canister, port
               module_wing_r  the same, starboard
             Station stores ride along as plain cargo (part of colony_hull): two pods
             on the spine flanks beside the dish, two pods and a strapped girder bundle
             under the spine.
  shield     thick layered radiation shadow shield (elongated octagon, ribbed front face,
             hazard rim) on four struts, between the reactor and everything forward.
  drive      reactor block with flush radiators top and bottom, four big ribbed propellant
             tanks (reaction mass, "H2O") on cradles, two edge-on radiator panels on truss
             booms, a heavy thrust bulkhead with three large gimballed bells (pump packs,
             actuators, stiffener rings), RCS quads on four outriggers.
Worn work white and grey, colony green bands, hazard trim, hull number and stencils,
running lights (red port, green starboard, white strobes, amber spine markers).

Layout (Blender Z up, exported +Y up). Ship centre at origin. The nose points along
Blender +Y, which the exporter turns into Godot -Z (forward).
  length 34.9 m (bell exits y -17.5 .. nose probe y 17.4), width 10.2 m over the radiator
  panels (8.7 m over the hab cans), height 7.5 m (shield rim z -3.4 .. dish bud z 4.1).
Hierarchy: colony_ship (empty root) -> colony_hull, colony_drive, module_hab_1,
  module_dish, module_wing_l, module_wing_r, engine_glow, and empties deploy_point,
  module_1..4.
Each module object has its origin on its clamp/hinge point on the spine, which is also
where its module_N empty sits (module_1 hab, module_2 dish, module_3 wing_l,
module_4 wing_r), so Godot can move or rotate a module about its mount.
engine_glow is one mesh with all three plumes; its origin is on the shared bell exit plane
(Blender y = NOZZLE_Y) and the plumes extend along Godot local +Z, so scaling it on Z
lengthens every glow backwards (same contract as the other ships, ship.gd finds one node).
Textures: one 2048 worn atlas shared by the hull, the drive and the four modules
(worn_kit / station_textures bake, kinds re-scaled to ship size plus local "pv" and
"petal" kinds; panel space scaled by PANEL_K so seams and rivets read at ~29 px per metre),
saved as blender/textures/colony_ship_{albedo,mr,normal}.jpg + colony_ship_decals.png,
material "colony_ship_hull". The bake runs with every mesh in ship coordinates; the module
origins move to their mounts afterwards. Emissive materials stay flat, named
"colony_ship_*".
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
from parts import ALONG_Y, V, rot  # noqa: E402

PRE = "colony_ship"
OUT = os.path.join(common.ROOT, "assets", "models", "ships", "colony_ship.glb")
BLEND = os.path.join(common.ROOT, "blender", "colony_ship.blend")

NOSE_Y = 17.4            # tip of the nose probe
# Command module stations: (y, w, h, chamfer, z centre)
CMD = ((12.4, 3.0, 2.6, 0.8, 0.0), (12.9, 4.2, 3.4, 1.0, 0.0), (15.4, 4.2, 3.4, 1.0, 0.0),
       (16.45, 3.0, 2.2, 0.7, -0.12), (17.0, 2.3, 1.5, 0.5, -0.15))
COLLAR_Y = 11.25         # docking collar centre
SPINE_Y0, SPINE_Y1 = -8.5, 10.65
SPINE_HW = 0.95          # spine truss half width / half height
SADDLE_HW = 1.25         # saddle frame half width
SHIELD_Y = -8.9          # shadow shield centre (0.7 thick)
CORE_Y0, CORE_Y1 = -14.1, -9.6
TANK_Y0, TANK_Y1 = -14.0, -9.75
TANK_R = 1.2
TANKS = [(sx * 2.5, sz * 1.55) for sx in (-1, 1) for sz in (-1, 1)]
PLATE_Y0, PLATE_Y1 = -14.55, -14.1      # thrust bulkhead
NOZZLE_Y = -17.5         # bell exit plane
BELL_R = 1.45
BELL_LEN = 2.5
BELLS = ((-1.85, -0.9), (1.85, -0.9), (0.0, 1.55))   # (x, z) of each bell axis
RAD_X0, RAD_X1 = 3.9, 5.0               # edge-on radiator panels
RAD_Y0, RAD_Y1 = -13.8, -10.0

# Module mounts (Blender coords). Module objects have their origin here.
HAB_Y0, HAB_Y1 = 4.3, 10.1
HAB_X, HAB_R = 2.95, 1.4
HAB_CLAMPS = (HAB_Y0 + 1.25, HAB_Y1 - 1.25)
HAB_ANCHOR = (0.0, (HAB_Y0 + HAB_Y1) / 2, 0.0)
DISH_Y = 2.0
DISH_ANCHOR = (0.0, DISH_Y, SPINE_HW)
WING_Y0, WING_Y1 = -7.5, -0.5
WING_X0, WING_X1 = 1.9, 4.3             # blanket stack spans |x| WING_X0..WING_X1
WING_CLAMPS = (WING_Y0 + 1.2, WING_Y1 - 1.2)
WING_ANCHOR = {-1: (-SPINE_HW, (WING_Y0 + WING_Y1) / 2, 0.0),
               1: (SPINE_HW, (WING_Y0 + WING_Y1) / 2, 0.0)}
DEPLOY_POINT = (0.0, DISH_Y, 0.0)

LABELS = ["CV-07", "07", "SOLACE", "HAB-A", "HAB-B", "PV-1", "PV-2", "COM-1", "H2O",
          "CAUTION", "NO STEP", "FS KIT", "#CHEV", "KEEP CLEAR"]
GREEN_INK = (0.05, 0.24, 0.12)

MATS = {}
DECALS = []
SCORCH = []
RNG = random.Random(707)

# Worn kinds at ship scale (process-local overrides). Work white, greys, colony green.
SHIP_WORN = {
    "hull": dict(big=(2.4, 1.8), plate=(1.2, 0.9),
                 tones=[(0.47, 0.47, 0.45), (0.44, 0.442, 0.435), (0.50, 0.498, 0.48),
                        (0.42, 0.425, 0.42), (0.48, 0.47, 0.45), (0.43, 0.435, 0.43)],
                 plate_var=0.06, rough=(0.55, 0.12), metal=0.05, seam_big=0.45,
                 seam_small=0.18, rivets=True, hatches=0.14, chip=(0.1, 0.1, 0.105),
                 chip_metal=0.8, chip_k=1.2, grime_k=0.85, streak_k=0.32, bleach=0.08),
    "hull2": dict(big=(2.2, 1.6), plate=(1.1, 0.8),
                  tones=[(0.17, 0.175, 0.18), (0.155, 0.16, 0.165), (0.185, 0.19, 0.19),
                         (0.145, 0.15, 0.155), (0.175, 0.17, 0.165), (0.16, 0.165, 0.175)],
                  plate_var=0.08, rough=(0.55, 0.12), metal=0.1, seam_big=0.45,
                  seam_small=0.18, rivets=True, hatches=0.12, chip=(0.30, 0.30, 0.31),
                  chip_metal=0.9, chip_k=0.9, grime_k=0.9, streak_k=0.25, bleach=0.1),
    "hull3": dict(big=(2.0, 2.0), plate=(1.0, 1.0),
                  tones=[(0.33, 0.325, 0.3), (0.31, 0.31, 0.295), (0.345, 0.34, 0.315),
                         (0.30, 0.30, 0.285), (0.32, 0.315, 0.29), (0.305, 0.305, 0.29)],
                  plate_var=0.06, rough=(0.56, 0.12), metal=0.05, seam_big=0.4,
                  seam_small=0.12, rivets=True, hatches=0.12, chip=(0.1, 0.1, 0.105),
                  chip_metal=0.8, chip_k=1.2, grime_k=1.0, streak_k=0.3, bleach=0.08),
    "dark": dict(big=(2.0, 2.0), plate=(1.0, 1.0),
                 tones=[(0.045, 0.047, 0.05), (0.04, 0.042, 0.045), (0.052, 0.054, 0.056),
                        (0.036, 0.038, 0.04), (0.05, 0.048, 0.046), (0.042, 0.044, 0.048)],
                 plate_var=0.06, rough=(0.5, 0.14), metal=0.6, seam_big=0.35,
                 seam_small=0.15, rivets=False, hatches=0.0, chip=(0.26, 0.26, 0.27),
                 chip_metal=1.0, chip_k=0.8, grime_k=0.5, streak_k=0.2, bleach=0.05),
    "metal": dict(big=(2.0, 1.0), plate=(1.0, 1.0),
                  tones=[(0.30, 0.30, 0.31), (0.27, 0.27, 0.275), (0.33, 0.33, 0.335),
                         (0.25, 0.255, 0.26), (0.31, 0.305, 0.30), (0.28, 0.285, 0.29)],
                  plate_var=0.04, rough=(0.36, 0.1), metal=0.9, seam_big=0.3,
                  seam_small=0.1, rivets=False, hatches=0.0, chip=(0.36, 0.36, 0.37),
                  chip_metal=1.0, chip_k=0.0, grime_k=0.9, streak_k=0.3, bleach=0.0),
    # colony green identity paint
    "accent": dict(big=(2.4, 1.6), plate=(1.2, 0.8),
                   tones=[(0.06, 0.27, 0.14), (0.052, 0.24, 0.125), (0.07, 0.30, 0.16),
                          (0.05, 0.22, 0.12), (0.062, 0.26, 0.15), (0.056, 0.25, 0.13)],
                   plate_var=0.06, rough=(0.55, 0.1), metal=0.0, seam_big=0.4,
                   seam_small=0.15, rivets=False, hatches=0.0, chip=(0.13, 0.13, 0.135),
                   chip_metal=0.8, chip_k=1.4, grime_k=1.1, streak_k=0.4, bleach=0.2),
    "hazard": dict(big=(2.4, 2.4), plate=(1.2, 1.2),
                   tones=[(0.44, 0.30, 0.04), (0.42, 0.29, 0.035), (0.46, 0.32, 0.045),
                          (0.40, 0.28, 0.04), (0.45, 0.31, 0.04), (0.43, 0.295, 0.04)],
                   plate_var=0.05, rough=(0.6, 0.08), metal=0.0, seam_big=0.3,
                   seam_small=0.1, rivets=False, hatches=0.0, chip=(0.12, 0.12, 0.125),
                   chip_metal=0.7, chip_k=1.8, grime_k=1.2, streak_k=0.45, bleach=0.2,
                   stripes=0.42),
    # heat-tinted bell metal
    "temper": dict(big=(1.6, 1.2), plate=(0.8, 1.2),
                   tones=[(0.20, 0.15, 0.24), (0.26, 0.17, 0.09), (0.13, 0.15, 0.26),
                          (0.30, 0.22, 0.12), (0.17, 0.12, 0.2), (0.22, 0.2, 0.22)],
                   plate_var=0.15, rough=(0.33, 0.1), metal=0.92, seam_big=0.25,
                   seam_small=0.1, rivets=False, hatches=0.0, chip=(0.3, 0.3, 0.3),
                   chip_metal=1.0, chip_k=0.0, grime_k=0.6, streak_k=0.5, bleach=0.0),
    # coolant fins run across the panel (panel v), section joints every 1.05 m
    "radiator": dict(big=(64.0, 1.05), plate=(64.0, 0.2),
                     tones=[(0.36, 0.365, 0.37), (0.34, 0.345, 0.35), (0.38, 0.38, 0.385),
                            (0.33, 0.335, 0.34), (0.37, 0.37, 0.37), (0.35, 0.355, 0.36)],
                     plate_var=0.03, rough=(0.42, 0.08), metal=0.2, seam_big=0.5,
                     seam_small=0.3, rivets=False, hatches=0.0, chip=(0.2, 0.2, 0.2),
                     chip_metal=0.6, chip_k=0.3, grime_k=0.6, streak_k=0.3, bleach=0.0,
                     fins=True),
    # dish petals: thin sheet, so little edge chipping (the edge mask covers a whole petal)
    "petal": dict(big=(2.4, 1.8), plate=(1.2, 0.9),
                  tones=[(0.47, 0.47, 0.45), (0.44, 0.442, 0.435), (0.50, 0.498, 0.48),
                         (0.42, 0.425, 0.42), (0.48, 0.47, 0.45), (0.43, 0.435, 0.43)],
                  plate_var=0.05, rough=(0.5, 0.1), metal=0.05, seam_big=0.4,
                  seam_small=0.15, rivets=True, hatches=0.0, chip=(0.1, 0.1, 0.105),
                  chip_metal=0.8, chip_k=0.22, grime_k=0.45, streak_k=0.25, bleach=0.08),
    # folded photovoltaic blanket: cell strings along the leaf, panel joints across it
    "pv": dict(big=(64.0, 1.7), plate=(0.3, 64.0),
               tones=[(0.012, 0.024, 0.075), (0.010, 0.020, 0.065), (0.015, 0.03, 0.09),
                      (0.009, 0.018, 0.06), (0.013, 0.026, 0.08), (0.011, 0.022, 0.07)],
               plate_var=0.1, rough=(0.22, 0.08), metal=0.6, seam_big=0.6,
               seam_small=0.45, rivets=False, hatches=0.0, chip=(0.3, 0.3, 0.32),
               chip_metal=0.9, chip_k=0.15, grime_k=0.5, streak_k=0.15, bleach=0.0),
}
# The ship is twice the size of the other new ships and shares their 2048 atlas size, so
# the panel space is scaled by PANEL_K: seams, rivets and hatches come out 1 / PANEL_K
# bigger on the hull and still read at ~30 px per metre. The sizes above are in metres.
PANEL_K = 0.5
for _cfg in SHIP_WORN.values():
    _cfg["big"] = tuple(v * PANEL_K for v in _cfg["big"])
    _cfg["plate"] = tuple(v * PANEL_K for v in _cfg["plate"])
    if "stripes" in _cfg:
        _cfg["stripes"] *= PANEL_K
st.WORN_KINDS.update(SHIP_WORN)


def build_materials():
    m = common.make_material
    MATS.clear()
    MATS["hull"] = m(f"{PRE}_paint_white", (0.47, 0.47, 0.45), roughness=0.55)
    MATS["hull2"] = m(f"{PRE}_paint_dark", (0.17, 0.175, 0.18), roughness=0.55)
    MATS["hull3"] = m(f"{PRE}_paint_warm", (0.33, 0.325, 0.3), roughness=0.56)
    MATS["dark"] = m(f"{PRE}_structure", (0.045, 0.047, 0.05), roughness=0.5, metallic=0.6)
    MATS["metal"] = m(f"{PRE}_bare_metal", (0.3, 0.3, 0.31), roughness=0.36, metallic=0.9)
    MATS["accent"] = m(f"{PRE}_green", (0.06, 0.27, 0.14), roughness=0.55)
    MATS["hazard"] = m(f"{PRE}_hazard", (0.44, 0.30, 0.04), roughness=0.6)
    MATS["temper"] = m(f"{PRE}_temper", (0.2, 0.15, 0.2), roughness=0.33, metallic=0.92)
    MATS["radiator"] = m(f"{PRE}_radiator", (0.36, 0.365, 0.37), roughness=0.42,
                         metallic=0.2)
    MATS["petal"] = m(f"{PRE}_dish_white", (0.47, 0.47, 0.45), roughness=0.5)
    MATS["pv"] = m(f"{PRE}_solar_cells", (0.012, 0.024, 0.075), roughness=0.22, metallic=0.6)
    glow = (0.03, 0.028, 0.025)
    MATS["glass"] = m(f"{PRE}_glass_dark", (0.008, 0.011, 0.016), roughness=0.12)
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
    MATS["glow"] = m(f"{PRE}_engine_glow", (0.8, 0.95, 1.0), roughness=0.2,
                     emission=(0.65, 0.92, 1.0), emission_strength=6.0)
    for k in ("glass", "window", "window_cool", "light", "white", "nav_r", "nav_g"):
        MATS[k].use_backface_culling = False


# ---------------------------------------------------------------- small helpers
def label(text, centre, normal, up, h, colour=wk.INK_DARK, opacity=0.88):
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


def plate(p, c, n, up, w, h, mat, t=0.07):
    """Raised armour / access plate lying on a face: w across, h along up, centre c on the
    face."""
    n = V(n).normalized()
    p.box(V(c) + n * (t / 2 - 0.01), (w, h, t), mat, r=frame(n, up), bevel=0.3)


def lamp(p, pos, mat, s=0.14):
    p.box(V(pos), (s, s, s), mat, bevel=0.0)


def rail(p, a, b, n, off=0.12, mat="metal"):
    """Handrail from a to b standing `off` proud of the face along n, on two standoffs."""
    a, b, n = V(a), V(b), V(n).normalized()
    parts.strut(p, a + n * off, b + n * off, 0.045, 0.045, mat, up=n)
    for q in (a.lerp(b, 0.06), a.lerp(b, 0.94)):
        parts.strut(p, q - n * 0.02, q + n * off, 0.04, 0.04, mat,
                    up=(b - a).normalized())


def lathe_y(p, x, z, pts, segs, start=0.0, squash=1.0):
    """Lathe around the Y axis through (x, z). pts: (r, y, mat of the edge to the next
    point). squash scales the world Z radius (elongated sections)."""
    prof = [(r, y) for r, y, _ in pts]
    mats = [m for _, _, m in pts]
    mtx = Matrix.Translation((x, 0, z)) @ ALONG_Y @ Matrix.Diagonal((1.0, squash, 1.0, 1.0))
    p.lathe(prof, segs, lambda i, j: mats[j], matrix=mtx, start=start)


def band(p, x, z, y, r, t, w, mat, segs=18):
    """Annular strap round the Y axis through (x, z): radius r..r+t, width w, centred y."""
    r0 = r - 0.03
    lathe_y(p, x, z, [(r0, y - w / 2, mat), (r + t, y - w / 2, mat), (r + t, y + w / 2, mat),
                      (r0, y + w / 2, mat), (r0, y - w / 2, mat)], segs)


def dome(y_tip, r, depth, sign, mat, steps=3, tip_first=True):
    """Elliptic end dome points. sign +1: tip at higher y. Listed tip -> shoulder, or
    shoulder -> tip."""
    pts = []
    for k in range(steps + 1):
        a = math.pi / 2 * k / steps
        pts.append((r * math.sin(a), y_tip - sign * depth * (1 - math.cos(a)), mat))
    return pts if tip_first else list(reversed(pts))


def sections(y, r, spec, rib_h=0.06, rib_mat="metal"):
    """Cylinder wall from y towards -Y: spec = [(length, mat)], mat "rib" = raised ring
    frame. Returns (points, end y); the last edge still needs a closing point."""
    pts = []
    for ln, mat in spec:
        if mat == "rib":
            pts += [(r, y, rib_mat), (r + rib_h, y - 0.02, rib_mat),
                    (r + rib_h, y - ln + 0.02, rib_mat)]
        else:
            pts.append((r, y, mat))
        y -= ln
    return pts, y


def rib_frame(p, y, w, h, c, mat, bar=0.3, depth=0.3, z0=0.0):
    """Open chamfered ring frame (8 beams) around the ship axis at y."""
    ring = parts.oct_ring(y, w, h, c, z0=z0)
    for i in range(8):
        a, b = ring[i], ring[(i + 1) % 8]
        mid = (a + b) / 2
        out = V((mid.x, 0, mid.z - z0)).normalized()
        ext = (b - a).normalized() * bar * 0.4
        p.beam(a - ext, b + ext, depth, bar, mat, up=out)


def hard_loft(p, rings, cap_mat, mat_fn):
    """Loft with every station ring split, so each band of facets keeps hard edges."""
    for i in range(len(rings) - 1):
        p.loft([rings[i], rings[i + 1]], cap_mat, cap=False,
               mat_fn=lambda _, j, i=i: mat_fn(i, j))
    for ring in (rings[0], rings[-1]):
        p.bm.faces.new([p.bm.verts.new(v) for v in ring]).material_index = p.mi(cap_mat)


def face_frame(r0, r1, j, z0=0.0):
    """Centre, outward normal, along (r0 -> r1) and across unit vectors of loft face j."""
    a, b = r0[j], r0[(j + 1) % 8]
    d, c = r1[j], r1[(j + 1) % 8]
    centre = (a + b + c + d) / 4
    along = ((c + d) / 2 - (a + b) / 2).normalized()
    across = (b - a).normalized()
    n = across.cross(along).normalized()
    if n.dot(V((centre.x, 0, centre.z - z0))) < 0:
        n = -n
    return centre, n, along, across


def rcs_boom(p, base, out, length=0.85, s=0.32):
    """RCS thruster quad on a braced outrigger."""
    out = V(out).normalized()
    base = V(base)
    tip = base + out * length
    p.beam(base - out * 0.25, tip, 0.16, 0.16, "hull2", up=V((0, 1, 0)))
    for sy in (-1, 1):
        parts.strut(p, base + V((0, sy * 0.55, 0)) - out * 0.2, tip - out * 0.1, 0.06, 0.06,
                    "dark")
    parts.rcs_quad(p, tip + out * s * 0.35, out, "hull3", "metal", s=s)
    p.box(tip - out * 0.12, (0.26, 0.26, 0.1), "hazard", r=frame(out, (0, 1, 0)), bevel=0.0)
    SCORCH.append((tip.x, tip.y, tip.z, 0.8))


# ---------------------------------------------------------------- hull: command module
def command(p):
    rings = rings_of(CMD)

    def cm(i, j):
        if i == 0 or i == 3:
            return "hull2"
        return "hull2" if j in (5, 6, 7) else "hull"
    hard_loft(p, rings, "hull2", cm)
    # colony green band behind the nose slopes (belly stays grey)
    r0 = parts.oct_ring(14.95, 4.25, 3.45, 1.01)
    r1 = parts.oct_ring(15.32, 4.25, 3.45, 1.01)
    p.loft([r0, r1], "accent", cap=False, mat_fn=lambda i, j: "hull2" if j in (5, 6, 7)
           else "accent")
    # slab armour: roof, upper chamfers, flanks, belly keel
    plate(p, (0, 14.35, 1.7), (0, 0, 1), (0, 1, 0), 1.9, 1.0, "hull")
    plate(p, (0, 13.4, 1.7), (0, 0, 1), (0, 1, 0), 1.7, 0.75, "hull2", t=0.1)
    for sx in (-1, 1):
        n = (sx, 0, 1)
        plate(p, (sx * 1.6, 14.3, 1.2), n, (0, 1, 0), 1.05, 1.1, "hull")
        plate(p, (sx * 1.6, 13.25, 1.2), n, (0, 1, 0), 0.8, 0.5, "hull3")
        plate(p, (sx * 1.6, 14.0, -1.2), (sx, 0, -1), (0, 1, 0), 1.0, 1.9, "hull2")
    plate(p, (2.1, 14.0, 0.0), (1, 0, 0), (0, 0, 1), 1.75, 1.05, "hull")
    plate(p, (0, 14.1, -1.7), (0, 0, -1), (0, 1, 0), 1.3, 1.7, "dark", t=0.14)
    for x, y in ((-0.35, 13.6), (0.3, 14.5), (-0.1, 14.9)):
        p.box(V((x, y, -1.86)), (0.4, 0.5, 0.18), "hull2", bevel=0.2)
    # hull number and stencils
    label("CV-07", (2.16, 14.0, 0.0), (1, 0, 0), (0, 0, 1), 0.55)
    label("CV-07", (-2.11, 13.4, 0.0), (-1, 0, 0), (0, 0, 1), 0.34)
    label("07", (0, 14.35, 1.77), (0, 0, 1), (0, 1, 0), 0.62, GREEN_INK, 0.95)
    for sx in (-1, 1):
        nn = V((sx, 0, 1)).normalized()
        label("SOLACE", V((sx * 1.6, 14.3, 1.2)) + nn * 0.07, nn, (0, 1, 0), 0.24)
    # slit viewports on the nose slopes, each under an armour brow
    ra, rb = rings[2], rings[3]
    for j, xs, w in ((2, (-0.62, 0.0, 0.62), 0.48), (1, (0.0,), 0.72), (3, (0.0,), 0.72)):
        c, n, along, across = face_frame(ra, rb, j, z0=-0.06)
        for dx in xs:
            q = c + across * dx - along * 0.12
            parts.quad(p, q + n * 0.04, n, along, w + 0.1, 0.2, "glass")
            parts.quad(p, q + n * 0.06, n, along, w, 0.08, "window")
            p.box(q - along * 0.2 + n * 0.05, (w + 0.16, 0.12, 0.14), "hull2",
                  r=frame(n, along), bevel=0.0)
        plate(p, c + along * 0.33, n, along, (1.1 if j == 2 else 0.7), 0.3, "hull")
    # side ports on the flanks (two a side, mostly shuttered)
    for sx in (-1, 1):
        parts.window(p, V((sx * 2.1, 15.65, 0.2)), V((sx, 0.48, 0)), (0, 0, 1), 0.3, 0.14,
                     "window" if sx > 0 else None)
    # nose: docking ring, hatch, headlamps, probe
    zn = CMD[-1][4]
    p.cyl(V((0, 17.1, zn)), 0.6, 0.6, 0.26, "metal", segs=16, axis_rot=ALONG_Y)
    band(p, 0, zn, 17.06, 0.6, 0.05, 0.1, "hazard", segs=16)
    p.cyl(V((0, 17.25, zn)), 0.42, 0.42, 0.04, "dark", segs=16, axis_rot=ALONG_Y)
    for sx in (-1, 1):
        p.box(V((sx * 0.78, 17.04, zn + 0.1)), (0.22, 0.12, 0.22), "dark", bevel=0.15)
        p.box(V((sx * 0.78, 17.105, zn + 0.1)), (0.15, 0.02, 0.15), "white", bevel=0.0)
    p.tube(V((0.55, 16.9, 0.42)), V((0.55, NOSE_Y, 0.42)), 0.035, 0.02, "metal", segs=5)
    p.box(V((0.55, 16.95, 0.42)), (0.14, 0.2, 0.14), "dark", bevel=0.0)
    # port airlock: frame, door, sill, lamp, handrails
    x = -2.1
    p.box(V((x - 0.04, 14.45, 0.0)), (0.14, 1.0, 1.25), "hull2", bevel=0.2)
    p.box(V((x - 0.1, 14.45, -0.03)), (0.08, 0.68, 0.98), "hull3", bevel=0.2)
    parts.quad(p, V((x - 0.16, 14.45, 0.2)), (-1, 0, 0), (0, 0, 1), 0.2, 0.2, "window_cool")
    p.box(V((x - 0.1, 14.45, -0.6)), (0.2, 0.9, 0.08), "hazard", bevel=0.0)
    lamp(p, (x - 0.12, 14.45, 0.66), "light", 0.1)
    for y in (13.88, 15.02):
        rail(p, (x, y, -0.5), (x, y, 0.5), (-1, 0, 0))
    rail(p, (2.1, 13.0, 0.62), (2.1, 14.9, 0.62), (1, 0, 0))
    # roof: hatch, grab rails
    p.box(V((0.55, 15.0, 1.73)), (0.7, 0.55, 0.08), "hull3", bevel=0.25)
    p.box(V((0.55, 15.0, 1.78)), (0.1, 0.3, 0.04), "metal", bevel=0.0)
    for sx in (-1, 1):
        rail(p, (sx * 1.0, 13.9, 1.7), (sx * 1.0, 14.8, 1.7), (0, 0, 1), off=0.1)
    label("NO STEP", (-0.45, 15.0, 1.71), (0, 0, 1), (0, 1, 0), 0.13, opacity=0.8)
    comms(p)
    # RCS quads on outriggers off the four chamfers
    for sx in (-1, 1):
        for sz in (-1, 1):
            rcs_boom(p, (sx * 1.6, 13.55, sz * 1.2), (sx, 0, sz))
    # nav lights
    for sx, mat in ((-1, "nav_r"), (1, "nav_g")):
        p.box(V((sx * 2.14, 15.15, 0.52)), (0.1, 0.22, 0.12), mat, bevel=0.0)


def comms(p):
    """Comms array on the command roof: dish on a mast, whips, phased array, sensor dome."""
    z = 1.8
    mast = V((-0.4, 13.35, z))
    p.cyl(mast + V((0, 0, 0.08)), 0.2, 0.24, 0.16, "dark", segs=10)
    p.tube(mast, mast + V((0, 0, 1.7)), 0.06, 0.04, "metal", segs=6)
    head = mast + V((0, 0, 0.95))
    p.box(head, (0.24, 0.24, 0.2), "hull2", bevel=0.2)
    parts.dish(p, head + V((0, 0.16, 0.08)), 0.62, V((0.25, 0.75, 0.6)), "hull", "dark",
               depth=0.2, segs=16)
    lamp(p, mast + V((0, 0, 1.72)), "white", 0.09)
    for dx, dy, hgt, rake in ((0.55, -0.2, 1.7, 0.35), (0.75, 0.05, 1.25, 0.25),
                              (0.4, 0.15, 0.95, 0.2)):
        b = V((dx, 13.3 + dy, z))
        p.tube(b, b + V((0, -rake, hgt)), 0.024, 0.012, "dark", segs=4)
        p.box(b + V((0, 0, 0.04)), (0.1, 0.1, 0.1), "dark", bevel=0.0)
    # phased array panel on a tilt bracket
    c = V((0.45, 13.72, z + 0.2))
    p.box(c, (0.62, 0.5, 0.06), "dark", r=rot(rx=0.6), bevel=0.0)
    p.box(c + V((0, 0, 0.035)), (0.5, 0.38, 0.03), "metal", r=rot(rx=0.6), bevel=0.0)
    p.box(c + V((0, -0.12, -0.12)), (0.12, 0.12, 0.26), "hull2", bevel=0.0)
    p.sphere(V((-0.75, 13.75, z + 0.08)), 0.17, "hull", segs=10, rings=6)
    p.cyl(V((-0.75, 13.75, z)), 0.2, 0.2, 0.06, "dark", segs=10)


def collar(p):
    """Neck and docking collar drum with three radial ports."""
    parts.prism(p, 11.8, 12.45, (2.3, 2.3, 0.65), (2.6, 2.4, 0.7), "hull2")
    y0, y1 = COLLAR_Y - 0.6, COLLAR_Y + 0.6
    lathe_y(p, 0, 0, [(0.9, y0, "dark"), (1.56, y0, "hull2"), (1.7, y0 + 0.14, "hull"),
                      (1.7, y1 - 0.14, "hull2"), (1.56, y1, "dark"), (0.9, y1, "dark")],
            16, start=math.pi / 16)
    for y in (y0 + 0.24, y1 - 0.24):
        band(p, 0, 0, y, 1.68, 0.035, 0.14, "hazard", segs=16)
    for d in (V((0, 0, 1)), V((1, 0, 0)), V((-1, 0, 0))):
        c = V((0, COLLAR_Y, 0)) + d * 1.6
        p.tube(c, c + d * 0.5, 0.6, 0.6, "hull3", segs=14)
        p.tube(c + d * 0.42, c + d * 0.56, 0.7, 0.7, "hazard", segs=14)
        p.tube(c + d * 0.56, c + d * 0.62, 0.5, 0.5, "dark", segs=14)
        p.tube(c + d * 0.62, c + d * 0.64, 0.2, 0.2, "metal", segs=8)
        for sy in (-1, 1):
            lamp(p, c + d * 0.3 + V((0, sy * 0.52, 0)), "light", 0.09)
    p.box(V((0, COLLAR_Y, -1.75)), (0.9, 0.8, 0.4), "dark", bevel=0.2)   # umbilical pack
    p.box(V((0, COLLAR_Y, -1.97)), (0.5, 0.5, 0.08), "metal", bevel=0.0)


# ---------------------------------------------------------------- hull: spine and cargo
def spine(p):
    """Braced box truss around the transfer tube, with the module saddles."""
    hw = SPINE_HW
    parts.prism(p, SPINE_Y1 - 0.5, SPINE_Y1 + 0.05, (2.3, 2.3, 0.55), (2.6, 2.6, 0.7), "hull2")
    parts.box_truss(p, SPINE_Y0, SPINE_Y1 - 0.4, hw, hw, 8, "hull2", "dark", chord=0.3,
                    brace=0.15)
    L = SPINE_Y1 - SPINE_Y0
    yc = (SPINE_Y0 + SPINE_Y1) / 2
    # pressurised transfer tube with ring frames
    p.cyl(V((0, yc, 0)), 0.52, 0.52, L, "hull3", segs=12, axis_rot=ALONG_Y)
    for k in range(9):
        y = SPINE_Y0 + 0.9 + k * (L - 1.6) / 8
        band(p, 0, 0, y, 0.52, 0.05, 0.14, "dark", segs=12)
    # keel plate, top cable tray, coolant lines (green) and a service pipe
    p.box(V((0, yc, -hw - 0.02)), (1.2, L - 0.6, 0.09), "dark", bevel=0.0)
    p.box(V((0, yc - 0.3, hw + 0.02)), (0.6, L - 1.4, 0.08), "hull2", bevel=0.0)
    for sx in (-1, 1):
        parts.pipe(p, V((sx * 0.68, SPINE_Y0 + 0.3, 0.6)), V((sx * 0.68, SPINE_Y1 - 0.5, 0.6)),
                   0.07, "accent", segs=6)
    parts.pipe(p, V((-0.66, SPINE_Y0 + 0.3, -0.62)), V((-0.66, SPINE_Y1 - 0.5, -0.62)), 0.09,
               "metal", segs=6)
    parts.pipe(p, V((0.62, SPINE_Y0 + 0.3, -0.66)), V((0.62, SPINE_Y1 - 0.5, -0.66)), 0.05,
               "metal", segs=6)
    # saddle frames at the module mounts, hazard bite pads on their flanks
    ys = HAB_CLAMPS + (DISH_Y - 0.8, DISH_Y + 0.8) + WING_CLAMPS + (-8.0,)
    for y in ys:
        rib_frame(p, y, 2 * SADDLE_HW, 2 * SADDLE_HW, 0.55, "hull2")
        if y in HAB_CLAMPS or y in WING_CLAMPS:
            for sx in (-1, 1):
                p.box(V((sx * (SADDLE_HW + 0.14), y, 0)), (0.06, 0.42, 0.9), "hazard",
                      bevel=0.0)
        for sx in (-1, 1):
            lamp(p, (sx * (SADDLE_HW - 0.2), y, SADDLE_HW + 0.16), "light", 0.1)
    # handrail along the starboard top chord between the saddles
    for ya, yb in ((-0.2, 0.9), (3.1, 5.3)):
        rail(p, (hw, ya, hw + 0.14), (hw, yb, hw + 0.14), (0, 0, 1), off=0.14)
    # junction boxes on the tray
    for y in (-3.9, 0.2, 3.9, 7.1):
        p.box(V((0.0, y, hw + 0.11)), (0.44, 0.5, 0.14), "dark", bevel=0.15)


def cargo(p):
    """Station stores slung under the spine: cargo pods on cradles, a girder bundle."""
    zt = -SPINE_HW - 0.18          # underside of the bottom chords
    for y, body, band_mat in ((8.55, "hull3", "accent"), (5.75, "hull", "hull2")):
        w, ln, h = 1.9, 2.5, 1.45
        c = V((0, y, zt - 0.1 - h / 2))
        wk.cargo_pod(p, c, (w, ln, h), body=body, band=band_mat, frame="dark")
        for sy in (-1, 1):
            yy = y + sy * (ln / 2 - 0.5)
            p.box(V((0, yy, zt - 0.05)), (2.3, 0.22, 0.14), "hull2", bevel=0.0)
            for sx in (-1, 1):
                p.box(V((sx * (w / 2 + 0.07), yy, c.z + 0.1)), (0.1, 0.24, h * 0.8), "dark",
                      bevel=0.0)
                p.box(V((sx * (w / 2 + 0.09), yy, c.z + h * 0.38)), (0.12, 0.3, 0.26),
                      "hazard", bevel=0.0)
        for sx in (-1, 1):
            label("FS KIT", (sx * (w / 2 - 0.04), y - 0.25, c.z), (sx, 0, 0), (0, 0, 1), 0.3)
    # two more pods on the spine flanks beside the dish pallet, on the dish saddles
    for sx, body, band_mat in ((-1, "hull", "accent"), (1, "hull3", "hull2")):
        w, ln, h = 1.6, 2.7, 1.6
        c = V((sx * (SADDLE_HW + 0.2 + w / 2), DISH_Y, 0.0))
        wk.cargo_pod(p, c, (w, ln, h), body=body, band=band_mat, frame="dark")
        for yy in (DISH_Y - 0.8, DISH_Y + 0.8):
            p.box(V((sx * (SADDLE_HW + 0.2), yy, 0)), (0.3, 0.4, 1.3), "hull2", bevel=0.15)
            for sz in (-1, 1):
                p.box(V((c.x, yy, sz * (h / 2 + 0.04))), (w + 0.16, 0.2, 0.07), "metal",
                      bevel=0.0)
                p.box(V((c.x + sx * (w / 2 - 0.15), yy, sz * (h / 2 + 0.07))), (0.34, 0.3, 0.08),
                      "hazard", bevel=0.0)
            p.box(V((c.x + sx * (w / 2 + 0.05), yy, 0)), (0.07, 0.2, h + 0.1), "metal",
                  bevel=0.0)
        label("FS KIT", (c.x, DISH_Y - 0.3, h / 2 - 0.06), (0, 0, 1), (0, 1, 0), 0.26)
        label("FS KIT", (c.x + sx * (w / 2 - 0.07), DISH_Y - 0.3, 0.0), (sx, 0, 0), (0, 0, 1),
              0.3)
        lamp(p, (c.x + sx * (w / 2 + 0.02), DISH_Y + ln / 2 - 0.2, h / 2), "light", 0.1)
    # girder bundle (ring truss kit): two layers of beams, strapped
    y0, y1 = -7.2, -1.0
    for row in range(2):   # two layers, each one block with dark gaps between the girders
        z = zt - 0.3 - row * 0.42
        ya, yb = y0 - row * 0.2, y1 - row * 0.2
        p.box(V((0, (ya + yb) / 2, z)), (1.72, yb - ya, 0.34), "metal" if row else "hull2",
              bevel=0.0)
        for x in (-0.46, 0.0, 0.46):
            for zz in (z + 0.172, z - 0.172):
                parts.strut(p, V((x, ya - 0.005, zz)), V((x, yb + 0.005, zz)), 0.1, 0.02, "dark")
        for x in (-0.46, 0.0, 0.46):
            for yy in (ya - 0.004, yb + 0.004):
                parts.strut(p, V((x, yy, z - 0.17)), V((x, yy, z + 0.17)), 0.1, 0.02, "dark",
                            up=V((0, 1, 0)))
    for y in (-6.4, -4.1, -1.8):
        p.box(V((0, y, zt - 0.5)), (2.1, 0.2, 1.02), "dark", bevel=0.0)
        p.box(V((0, y, zt - 1.03)), (1.5, 0.24, 0.06), "hazard", bevel=0.0)


def shield(p):
    """Radiation shadow shield: thick layered slab, an elongated octagon across the axis."""
    y = SHIELD_Y
    sq = 0.75
    r = 4.9
    pts = [(0.0, y + 0.52, "hull2"), (1.9, y + 0.52, "hull2"), (2.5, y + 0.35, "hull"),
           (r - 0.5, y + 0.35, "accent"), (r - 0.28, y + 0.35, "hull"),
           (r - 0.2, y + 0.3, "hull2"), (r, y + 0.22, "dark"), (r, y - 0.22, "hull2"),
           (r - 0.3, y - 0.35, "dark"), (0.0, y - 0.35, "dark")]
    lathe_y(p, 0, 0, pts, 8, start=math.pi / 8, squash=sq)
    ap = r * math.cos(math.pi / 8)          # flat-to-flat half width
    # stiffener ribs on the front face, radial, plus a ring
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        d = V((math.cos(a), 0, math.sin(a) * sq))
        p.beam(V((0, y + 0.4, 0)) + d * 2.4, V((0, y + 0.4, 0)) + d * (r - 0.55), 0.16, 0.12,
               "hull2", up=V((0, 1, 0)))
    # hazard blocks on the rim flats (top and the two sides read from the RTS camera)
    for x in (-1.1, 0.0, 1.1):
        p.box(V((x, y, ap * sq + 0.0)), (0.8, 0.46, 0.06), "hazard", bevel=0.0)
    for sx in (-1, 1):
        for z in (-0.7, 0.7):
            p.box(V((sx * ap, y, z)), (0.06, 0.46, 0.8), "hazard", bevel=0.0)
        lamp(p, (sx * (ap - 0.25), y + 0.4, 0.0), "light", 0.14)
    lamp(p, (0, y + 0.4, ap * sq - 0.25), "white", 0.14)
    label("CAUTION", (0, y + 0.36, 2.55), (0, 1, 0), (0, 0, 1), 0.3)
    label("#CHEV", (-2.9, y + 0.36, 1.2), (0, 1, 0), (0, 0, 1), 0.3, (0.45, 0.3, 0.04), 0.9)
    label("#CHEV", (2.9, y + 0.36, 1.2), (0, 1, 0), (0, 0, 1), 0.3, (0.45, 0.3, 0.04), 0.9)
    # four struts from the last saddle out to the slab
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.beam(V((sx * 1.1, -6.3, sz * 1.1)), V((sx * 2.9, y + 0.36, sz * 2.1)), 0.2, 0.2,
                   "dark")
    rib_frame(p, -6.3, 2 * SADDLE_HW, 2 * SADDLE_HW, 0.55, "hull2")


def build_hull():
    p = parts.PanelPart("colony_hull", MATS)
    command(p)
    collar(p)
    spine(p)
    cargo(p)
    shield(p)
    return p


# ---------------------------------------------------------------- drive
def bell_r(t):
    """Outer bell radius at t (0 throat .. 1 exit), as parts.bell builds it."""
    rt = BELL_R * 0.42
    return rt + (BELL_R - rt) * t ** 0.65


def tank(p, x, z, k):
    """Ribbed propellant tank on a cradle: green band forward, fill valve, feed line aft."""
    r = TANK_R
    d = 0.5 * r
    spec = [(0.3, "hull"), (0.1, "rib"), (0.4, "accent"), (0.1, "rib"), (0.5, "hull"),
            (0.1, "rib"), (0.5, "hull3" if k % 2 else "hull"), (0.1, "rib"), (0.5, "hull"),
            (0.1, "rib"), (0.35, "hull3" if k == 1 else "hull")]
    pts = dome(TANK_Y1, r, d, 1, "hull")
    wall, y = sections(TANK_Y1 - d, r, spec)
    pts = pts[:-1] + wall + dome(TANK_Y0, r, d, -1, "hull2", tip_first=False)
    lathe_y(p, x, z, pts, 18)
    sx, sz = (1 if x > 0 else -1), (1 if z > 0 else -1)
    # cradle straps and struts to the reactor block
    for yy in (TANK_Y1 - d - 0.4, TANK_Y0 + d + 0.35):
        band(p, x, z, yy, r + 0.05, 0.05, 0.2, "dark", segs=18)
        p.beam(V((sx * 1.1, yy, sz * 1.1)), V((x - sx * 0.75, yy, z - sz * 0.75)), 0.3, 0.3,
               "dark")
    out = V((sx, 0, sz)).normalized()
    # outboard: fill valve box, vent stub, feed line down to the thrust bulkhead
    c = V((x, -11.9, z)) + out * (r + 0.05)
    p.box(c, (0.4, 0.5, 0.2), "hull2", r=frame(out, (0, 1, 0)), bevel=0.2)
    p.tube(c + out * 0.08, c + out * 0.26, 0.07, 0.07, "metal", segs=6)
    a = V((x, TANK_Y0 + 0.35, z)) + out * (r * 0.75)
    parts.pipe(p, a, V((a.x, PLATE_Y1 + 0.02, a.z)), 0.08, "metal", segs=6)
    parts.pipe(p, V((x, TANK_Y0 + 0.2, z)), V((x * 0.8, PLATE_Y1 + 0.02, z * 0.8)), 0.11, "metal",
               segs=6)
    if sz > 0:
        label("H2O", (x, -12.45, z + r + 0.01), (0, 0, 1), (0, 1, 0), 0.42)
        p.box(V((x, -11.0, z + r + 0.03)), (0.5, 0.5, 0.06), "hull3", bevel=0.25)
        rail(p, (x - sx * 0.45, -13.3, z + r * 0.89), (x - sx * 0.45, -11.6, z + r * 0.89),
             (-sx * 0.38, 0, 0.92), off=0.1)


def radiator_panel(p, sx):
    """Edge-on radiator in the tank gap: two finned panels in a frame on a truss boom."""
    x0, x1 = sx * RAD_X0, sx * RAD_X1
    xc, w = (x0 + x1) / 2, RAD_X1 - RAD_X0
    yc, ln = (RAD_Y0 + RAD_Y1) / 2, RAD_Y1 - RAD_Y0
    p.box(V((xc, yc, 0)), (w, ln, 0.07), "radiator", bevel=0.0)
    # frame, mid divider, headers
    for xx in (x0, x1):
        p.beam(V((xx, RAD_Y0 - 0.05, 0)), V((xx, RAD_Y1 + 0.05, 0)), 0.1, 0.14, "dark")
    for yy in (RAD_Y0, yc, RAD_Y1):
        p.beam(V((x0, yy, 0)), V((x1, yy, 0)), 0.1, 0.14, "dark")
    for dz in (-0.09, 0.09):
        parts.pipe(p, V((x0 - sx * 0.12, RAD_Y0, dz)), V((x0 - sx * 0.12, RAD_Y1, dz)), 0.055,
                   "metal", segs=6)
    # truss boom and coolant feeds through the gap between the upper and lower tank
    for yy in (RAD_Y0 + 0.7, yc, RAD_Y1 - 0.7):
        p.beam(V((sx * 1.4, yy, 0)), V((x0, yy, 0)), 0.16, 0.2, "hull2")
    for ya, yb in ((RAD_Y0 + 0.7, yc), (yc, RAD_Y1 - 0.7)):
        parts.strut(p, V((sx * 1.5, ya, 0)), V((x0, yb, 0)), 0.08, 0.08, "dark")
    for yy in (yc - 0.35, yc + 0.35):
        parts.pipe(p, V((sx * 1.4, yy, 0.16)), V((x0 - sx * 0.1, yy, 0.1)), 0.05, "accent",
                   segs=6)
    p.box(V((x1 + sx * 0.02, RAD_Y1 - 0.5, 0)), (0.08, 0.6, 0.1), "hazard", bevel=0.0)
    lamp(p, (x1 + sx * 0.04, RAD_Y1 + 0.02, 0.0), "nav_g" if sx > 0 else "nav_r", 0.16)
    lamp(p, (x1 + sx * 0.04, RAD_Y0 - 0.02, 0.0), "white", 0.12)


def engine(p, x, z):
    """Gimballed main engine: mount cone, pump pack, gimbal ring, bell with stiffeners."""
    throat = NOZZLE_Y + BELL_LEN
    p.tube(V((x, PLATE_Y0 + 0.02, z)), V((x, throat + 0.12, z)), 0.95, 0.62, "hull2", segs=14)
    p.tube(V((x, throat + 0.14, z)), V((x, throat - 0.05, z)), 0.56, 0.56, "metal", segs=14)
    p.torus(V((x, throat + 0.12, z)), 0.72, 0.07, "dark", segs=16, minor_segs=5,
            matrix=rot(rx=math.pi / 2))
    parts.bell(p, NOZZLE_Y, BELL_R, BELL_LEN, "temper", "dark", x=x, z=z, segs=24)
    for t in (0.3, 0.62, 0.97):
        p.torus(V((x, throat - BELL_LEN * t, z)), bell_r(t) + 0.01, 0.04, "metal", segs=24,
                minor_segs=4, matrix=rot(rx=math.pi / 2))
    # coolant manifold round the throat and its feed
    p.torus(V((x, throat - 0.25, z)), bell_r(0.12) + 0.09, 0.06, "dark", segs=16, minor_segs=5,
            matrix=rot(rx=math.pi / 2))
    # three gimbal actuators, bulkhead to the first stiffener ring
    for k in range(3):
        a = k * 2 * math.pi / 3 + (math.pi / 2 if z > 0 else -math.pi / 2)
        d = V((math.cos(a), 0, math.sin(a)))
        b0 = V((x, PLATE_Y0, z)) + d * 1.02
        b1 = V((x, throat - BELL_LEN * 0.3, z)) + d * (bell_r(0.3) + 0.03)
        mid = b0.lerp(b1, 0.55)
        p.tube(b0, mid, 0.07, 0.07, "dark", segs=6)
        p.tube(mid, b1, 0.04, 0.04, "metal", segs=6)
        p.box(b0 + V((0, 0.02, 0)), (0.22, 0.14, 0.22), "hull2", bevel=0.0)
    # turbopump pack on the mount cone, outboard
    out = V((x, 0, z - 0.2)).normalized()
    c = V((x, PLATE_Y0 - 0.2, z)) + out * 0.95
    p.box(c, (0.5, 0.42, 0.4), "dark", r=frame(out, (0, 1, 0)), bevel=0.2)
    p.tube(c + out * 0.1, c + out * 0.1 + V((0, -0.36, 0)), 0.11, 0.11, "metal", segs=8)
    SCORCH.append((x, NOZZLE_Y + 0.4, z, 2.2))


def build_drive():
    p = parts.PanelPart("colony_drive", MATS)
    # reactor block and its neck up to the shield
    def cm(i, j):
        return "hull2" if j in (5, 6, 7) else "hull"
    parts.prism(p, CORE_Y0, CORE_Y1, (3.0, 3.0, 0.8), (3.0, 3.0, 0.8), "hull2", mat_fn=cm)
    parts.prism(p, CORE_Y1 - 0.02, SHIELD_Y - 0.3, (2.3, 2.3, 0.6), (2.0, 2.0, 0.5), "dark")
    p.loft([parts.oct_ring(-10.4, 3.05, 3.05, 0.81), parts.oct_ring(-10.0, 3.05, 3.05, 0.81)],
           "accent", cap=False, mat_fn=lambda i, j: "hull2" if j in (5, 6, 7) else "accent")
    # flush radiators on the block's top and bottom faces, service hatch, reactor cap
    for sz in (-1, 1):
        p.box(V((0, -12.3, sz * 1.52)), (1.3, 3.2, 0.07), "radiator", bevel=0.0)
        for xx in (-0.69, 0.69):
            p.beam(V((xx, -13.9, sz * 1.53)), V((xx, -10.7, sz * 1.53)), 0.08, 0.1, "dark")
        for yy in (-13.9, -12.3, -10.7):
            p.beam(V((-0.69, yy, sz * 1.53)), V((0.69, yy, sz * 1.53)), 0.08, 0.1, "dark")
    p.cyl(V((0, -10.2, 1.56)), 0.42, 0.46, 0.14, "hull2", segs=12)
    p.cyl(V((0, -10.2, 1.65)), 0.3, 0.3, 0.06, "hazard", segs=12)
    lamp(p, (0, -9.8, 1.56), "light", 0.14)
    # chamfer faces: coolant pipes from the block to the tank gap, access plates
    for sx in (-1, 1):
        for sz in (-1, 1):
            n = V((sx, 0, sz)).normalized()
            plate(p, V((sx * 1.1, -10.2, sz * 1.1)), n, (0, 1, 0), 0.7, 0.5, "hull3")
        p.box(V((sx * 1.5, -11.9, 0)), (0.1, 3.4, 0.9), "hull2", bevel=0.2)
        for yy in (-13.2, -11.9, -10.6):
            p.box(V((sx * 1.56, yy, 0)), (0.08, 0.5, 0.6), "dark", bevel=0.0)
    for k, (x, z) in enumerate(TANKS):
        tank(p, x, z, k)
    for sx in (-1, 1):
        radiator_panel(p, sx)
    # thrust bulkhead: chamfered slab, hazard edge, stiffener webs on the forward face
    pw, ph, pc = 7.0, 5.7, 1.7
    def pm(i, j):
        return "dark" if i == 1 else "hull2"
    p.loft([parts.oct_ring(PLATE_Y1, pw - 0.5, ph - 0.5, pc - 0.15),
            parts.oct_ring(PLATE_Y1 - 0.12, pw, ph, pc),
            parts.oct_ring(PLATE_Y0, pw, ph, pc)], "hull2", mat_fn=pm)
    ym = (PLATE_Y0 + PLATE_Y1 - 0.12) / 2
    for x0, x1 in ((-1.7, -0.3), (0.3, 1.7)):
        p.box(V(((x0 + x1) / 2, ym, ph / 2 + 0.01)), (x1 - x0, 0.3, 0.05), "hazard", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * (pw / 2 + 0.01), ym, 0)), (0.05, 0.3, 1.6), "hazard", bevel=0.0)
    label("KEEP CLEAR", (0, PLATE_Y0 - 0.01, -2.45), (0, -1, 0), (0, 0, 1), 0.22,
          wk.INK_LIGHT)
    for x, z in BELLS:
        engine(p, x, z)
        # heat shield ring round each mount, on the bulkhead's aft face
        lathe_y(p, x, z, [(1.0, PLATE_Y0 + 0.02, "metal"), (1.0, PLATE_Y0 - 0.06, "metal"),
                          (1.42, PLATE_Y0 - 0.06, "metal"), (1.5, PLATE_Y0 + 0.02, "metal")],
                16)
    # aft face: stiffener webs, propellant cross-feed, access hatch
    ya = PLATE_Y0 - 0.05
    for a, b in (((-3.3, 0.6), (-0.6, 2.7)), ((3.3, 0.6), (0.6, 2.7)), ((-3.3, -0.2), (3.3, -0.2)),
                 ((-2.6, -2.7), (-3.3, -0.6)), ((2.6, -2.7), (3.3, -0.6)),
                 ((-1.5, 2.7), (-1.5, 0.2)), ((1.5, 2.7), (1.5, 0.2))):
        p.beam(V((a[0], ya, a[1])), V((b[0], ya, b[1])), 0.14, 0.16, "hull2", up=V((0, 1, 0)))
    for a, b in (((-1.85, -0.9), (0.0, 1.55)), ((1.85, -0.9), (0.0, 1.55)),
                 ((-1.85, -0.9), (1.85, -0.9))):
        parts.pipe(p, V((a[0], ya - 0.12, a[1])), V((b[0], ya - 0.12, b[1])), 0.07, "metal",
                   segs=6)
    p.box(V((0, ya, -1.9)), (0.9, 0.1, 0.7), "hull3", bevel=0.2)
    p.box(V((0, ya - 0.05, -1.9)), (0.3, 0.06, 0.1), "metal", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 2.75, ya, 1.7)), (0.6, 0.1, 0.5), "dark", bevel=0.2)
        lamp(p, (sx * 3.2, ya, -0.6), "light", 0.12)
    # thrust struts from the reactor block's aft end out to the bulkhead rim
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.beam(V((sx * 0.9, -12.9, sz * 0.2)), V((sx * 3.1, PLATE_Y1 - 0.05, sz * 0.25)),
                   0.2, 0.2, "dark")
            rcs_boom(p, (sx * 2.65, (PLATE_Y0 + PLATE_Y1) / 2 - 0.05, sz * 2.0), (sx, 0, sz))
    # running lights on the bulkhead
    for sx in (-1, 1):
        lamp(p, (sx * 1.9, ym, ph / 2 + 0.05), "white", 0.16)
    lamp(p, (0, ym, -ph / 2 - 0.05), "light", 0.16)
    lamp(p, (0, ym, ph / 2 + 0.05), "light", 0.16)
    return p


# ---------------------------------------------------------------- modules
def build_hab():
    """Twin habitat cans straddling the spine, held by clamp claws fore and aft."""
    p = parts.PanelPart("module_hab_1", MATS)
    R = HAB_R
    for sx, name in ((-1, "HAB-A"), (1, "HAB-B")):
        x = sx * HAB_X
        spec = [(0.1, "rib"), (1.15, "hull"), (0.1, "rib"), (0.4, "accent"), (0.1, "rib"),
                (1.1, "hull3" if sx > 0 else "hull"), (0.1, "rib"), (0.95, "hull"),
                (0.1, "rib")]
        pts = [(0.0, HAB_Y1, "dark"), (0.5, HAB_Y1, "metal"), (0.5, HAB_Y1 - 0.2, "hull2"),
               (0.66, HAB_Y1 - 0.2, "hull2")]
        wall, y = sections(HAB_Y1 - 0.85, R, spec, rib_mat="hull2")
        pts += wall + [(R, y, "hull2"), (0.66, HAB_Y0 + 0.2, "hull2"),
                       (0.5, HAB_Y0 + 0.2, "metal"), (0.5, HAB_Y0, "dark"), (0.0, HAB_Y0, "dark")]
        lathe_y(p, x, 0, pts, 20)
        for yy in (HAB_Y1 - 0.12, HAB_Y0 + 0.12):   # transit covers on the end ports
            band(p, x, 0, yy, 0.5, 0.04, 0.1, "hazard", segs=14)
        # ports on the outboard flank and the roof line, mostly dark in transit
        for row_z, row_n in ((0.38, V((sx, 0, 0.28))), (-0.42, V((sx, 0, -0.31)))):
            nn = row_n.normalized()
            for yy in (9.0, 8.45, 7.9, 6.5, 5.95, 5.4):
                lit = RNG.random() < 0.3
                parts.window(p, V((x, yy, 0)) + nn * (R - 0.005), nn, (0, 1, 0), 0.2, 0.12,
                             "window" if lit else None)
        # roof: hatch, grapple fixture, handrails, stencil
        p.cyl(V((x, 5.85, R + 0.02)), 0.4, 0.4, 0.1, "hull3", segs=12)
        p.cyl(V((x, 5.85, R + 0.08)), 0.28, 0.28, 0.05, "dark", segs=12)
        p.cyl(V((x, 7.55, R + 0.06)), 0.16, 0.2, 0.18, "metal", segs=8)
        for a in (-0.42, 0.42):
            n = V((math.sin(a), 0, math.cos(a)))
            rail(p, V((x, 7.95, 0)) + n * R, V((x, 9.1, 0)) + n * R, n, off=0.1)
            rail(p, V((x, 5.35, 0)) + n * R, V((x, 6.6, 0)) + n * R, n, off=0.1)
        label(name, (x, 8.52, R + 0.01), (0, 0, 1), (0, 1, 0), 0.34)
        # clamp bands with hazard bite pads, claws and the launch-lock arm to the saddle
        for yy in HAB_CLAMPS:
            band(p, x, 0, yy, R + 0.05, 0.06, 0.32, "dark", segs=20)
            p.box(V((x, yy, R + 0.13)), (0.55, 0.36, 0.07), "hazard", bevel=0.0)
            p.box(V((x + sx * (R + 0.13), yy, 0)), (0.07, 0.36, 0.55), "hazard", bevel=0.0)
            p.box(V((sx * (SADDLE_HW + 0.2), yy, 0)), (0.5, 0.46, 0.8), "hull2", bevel=0.2)
            for sz in (-1, 1):
                p.beam(V((sx * (SADDLE_HW - 0.1), yy, sz * 1.0)),
                       V((x - sx * R * 0.72, yy, sz * R * 0.72)), 0.3, 0.18, "dark")
                p.box(V((x - sx * R * 0.74, yy, sz * R * 0.74)), (0.3, 0.38, 0.3), "hazard",
                      r=rot(ry=math.pi / 4), bevel=0.0)
        # antenna stub and marker lamps
        p.tube(V((x + sx * 0.5, HAB_Y1 - 1.0, R * 0.86)), V((x + sx * 0.6, HAB_Y1 - 1.2, R + 0.9)),
               0.025, 0.012, "dark", segs=4)
        lamp(p, (x + sx * (R + 0.04), HAB_Y1 - 0.9, 0.0), "nav_g" if sx > 0 else "nav_r", 0.14)
        lamp(p, (x + sx * (R + 0.04), HAB_Y0 + 0.9, 0.0), "light", 0.12)
    return p


def build_dish():
    """Comms dish folded shut: six petals hinged on a hub rim, closed into a bud (about
    6 m across once the petals open flat), on a pallet clamped to the spine top."""
    p = parts.PanelPart("module_dish", MATS)
    ax, ay, az = DISH_ANCHOR
    # pallet with hazard clamp shoes, azimuth drum, yoke
    p.box(V((ax, ay, az + 0.17)), (2.3, 2.6, 0.22), "hull3", bevel=0.2)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box(V((ax + sx * 1.08, ay + sy * 0.8, az + 0.1)), (0.34, 0.4, 0.36), "hazard",
                  bevel=0.0)
        # stowed boom segments along the pallet edges
        p.cyl(V((ax + sx * 0.92, ay, az + 0.4)), 0.11, 0.11, 2.2, "metal", segs=8,
              axis_rot=ALONG_Y)
        for sy in (-1, 1):
            p.box(V((ax + sx * 0.92, ay + sy * 0.85, az + 0.38)), (0.3, 0.14, 0.26), "dark",
                  bevel=0.0)
    label("COM-1", (ax, ay + 1.12, az + 0.285), (0, 0, 1), (0, 1, 0), 0.14)
    p.cyl(V((ax, ay, az + 0.45)), 0.6, 0.54, 0.36, "hull2", segs=14)
    p.cyl(V((ax, ay, az + 0.62)), 0.4, 0.4, 0.2, "metal", segs=12)
    hub_z = az + 0.85
    hub_r = 1.2
    lathe_m = Matrix.Translation((ax, ay, 0))
    p.lathe([(0.0, hub_z - 0.18), (hub_r * 0.8, hub_z - 0.18), (hub_r, hub_z + 0.02),
             (hub_r, hub_z + 0.14), (hub_r * 0.9, hub_z + 0.14), (0.0, hub_z + 0.1)], 12,
            lambda i, j: "hull2" if j in (2, 3) else "hull", matrix=lathe_m)
    fold = math.radians(99)   # past vertical: the petals lean in and close the bud
    length = 2.0
    t30 = math.tan(math.radians(30))
    tips = []
    for k in range(6):
        a = k * math.pi / 3
        u = V((math.cos(a), math.sin(a), 0))
        t = V((-math.sin(a), math.cos(a), 0))
        hinge = V((ax, ay, hub_z + 0.1)) + u * hub_r
        d = u * math.cos(fold) + V((0, 0, 1)) * math.sin(fold)   # along the petal
        n = d.cross(t)                                            # petal back (outward)
        if n.dot(u) < 0:
            n = -n
        frm = Matrix((d, t, -n)).transposed().to_4x4()
        m = Matrix.Translation(hinge) @ frm
        w0 = hub_r * t30 * 0.93
        w1 = (hub_r + length * math.cos(fold)) * t30 * 0.9
        p.slab([(0, -w0), (length, -w1), (length, w1), (0, w0)], 0.0, 0.05,
               "petal", matrix=m)
        # back structure: centre rib, two cross ribs, hinge knuckle, tip latch
        p.beam(hinge + n * 0.05, hinge + d * length * 0.96 + n * 0.05, 0.09, 0.09, "dark",
               up=n)
        for f in (0.38, 0.76):
            wf = (w0 + (w1 - w0) * f) * 0.92
            c = hinge + d * length * f + n * 0.04
            p.beam(c - t * wf, c + t * wf, 0.06, 0.06, "dark", up=n)
        p.cyl(hinge, 0.09, 0.09, w0 * 1.5, "metal", segs=6,
              axis_rot=Matrix((t.cross(V((0, 0, 1))), V((0, 0, 1)), t)).transposed().to_4x4())
        p.box(hinge + d * length * 0.97 + n * 0.07, (0.14, 0.2, 0.12), "hazard", r=frm,
              bevel=0.0)
        tips.append(hinge + d * length * 0.62 + n * 0.11)
    # restraint band round the closed petals
    for k in range(6):
        a, b = tips[k], tips[(k + 1) % 6]
        mid = (a + b) / 2
        out = V((mid.x - ax, mid.y - ay, 0)).normalized()
        ext = (b - a).normalized() * 0.08
        p.beam(a - ext, b + ext, 0.05, 0.16, "hazard", up=V((0, 0, 1)))
    # feed horn poking out of the bud
    tip_z = hub_z + 0.1 + length * math.sin(fold)
    p.cyl(V((ax, ay, tip_z - 0.35)), 0.09, 0.06, 0.9, "dark", segs=6)
    p.cyl(V((ax, ay, tip_z + 0.05)), 0.14, 0.14, 0.12, "metal", segs=8)
    lamp(p, (ax, ay, tip_z + 0.2), "white", 0.12)
    return p


def build_wing(sx):
    """Folded solar wing cassette: blanket leaves stacked in a strapped frame, the wing's
    mast canister on the spine side, hinge arms on the saddles."""
    name = "module_wing_l" if sx < 0 else "module_wing_r"
    p = parts.PanelPart(name, MATS)
    x0, x1 = sx * WING_X0, sx * WING_X1
    xc, w = (x0 + x1) / 2, WING_X1 - WING_X0
    yc, length = (WING_Y0 + WING_Y1) / 2, WING_Y1 - WING_Y0
    z_base = -0.5
    n, th, gap = 9, 0.065, 0.03
    # tray and leaf stack (the top leaf shows its cells)
    p.box(V((xc, yc, z_base - 0.05)), (w, length, 0.1), "hull2", bevel=0.0)
    top = z_base + n * (th + gap)
    p.box(V((xc, yc, (z_base + top) / 2)), (w - 0.3, length - 0.38, top - z_base), "dark",
          bevel=0.0)
    hw_, hl_ = (w - 0.22) / 2, (length - 0.3) / 2
    for k in range(0, n, 2):   # every other leaf shows its frame edge round the stack
        z = z_base + k * (th + gap) + th / 2
        cs = [V((xc - hw_, yc - hl_, z)), V((xc + hw_, yc - hl_, z)),
              V((xc + hw_, yc + hl_, z)), V((xc - hw_, yc + hl_, z))]
        for a, b in zip(cs, cs[1:] + cs[:1]):
            e = (b - a).normalized() * 0.04
            parts.strut(p, a - e, b + e, 0.08, th, "metal")
    p.box(V((xc, yc, top + 0.03)), (w - 0.22, length - 0.3, 0.06), "pv", bevel=0.0)
    for k in range(1, 4):   # bus bars across the top leaf at the panel joints
        y = WING_Y0 + 0.15 + (length - 0.3) * k / 4
        p.box(V((xc, y, top + 0.065)), (w - 0.26, 0.07, 0.02), "metal", bevel=0.0)
    p.box(V((xc, yc, top + 0.065)), (0.06, length - 0.34, 0.02), "metal", bevel=0.0)
    # end frames (white, stencilled) and corner posts
    h = top - z_base + 0.3
    zc = (top + z_base) / 2
    for yy in (WING_Y0 + 0.08, WING_Y1 - 0.08):
        p.box(V((xc, yy, zc)), (w + 0.06, 0.16, h), "hull", bevel=0.1)
    for xx in (x0 + sx * 0.04, x1 - sx * 0.04):
        p.beam(V((xx, WING_Y0 + 0.1, top + 0.1)), V((xx, WING_Y1 - 0.1, top + 0.1)), 0.1, 0.1,
               "hull2")
    tag = "PV-1" if sx < 0 else "PV-2"
    label(tag, (xc, WING_Y1 + 0.01, zc), (0, 1, 0), (0, 0, 1), 0.3)
    label(tag, (xc, WING_Y0 - 0.01, zc), (0, -1, 0), (0, 0, 1), 0.3)
    # launch-lock straps over the stack, hazard shoes where they latch
    for y in (WING_Y0 + 1.2, yc, WING_Y1 - 1.2):
        p.box(V((xc, y, top + 0.1)), (w + 0.1, 0.22, 0.05), "metal", bevel=0.0)
        p.box(V((x1 + sx * 0.03, y, zc)), (0.06, 0.22, h), "metal", bevel=0.0)
        p.box(V((x1 - sx * 0.12, y, top + 0.13)), (0.4, 0.34, 0.08), "hazard", bevel=0.0)
        p.box(V((x0 + sx * 0.12, y, top + 0.13)), (0.4, 0.34, 0.08), "hazard", bevel=0.0)
    # mast canister between the spine and the stack, banded
    xm = sx * 1.52
    p.cyl(V((xm, yc, 0)), 0.3, 0.3, length - 0.6, "hull3", segs=12, axis_rot=ALONG_Y)
    for y in (WING_Y0 + 0.5, yc - 1.1, yc + 1.1, WING_Y1 - 0.5):
        band(p, xm, 0, y, 0.3, 0.04, 0.16, "dark", segs=12)
    band(p, xm, 0, WING_Y1 - 0.34, 0.3, 0.03, 0.1, "hazard", segs=12)
    p.cyl(V((xm, WING_Y1 - 0.25, 0)), 0.2, 0.2, 0.14, "metal", segs=10, axis_rot=ALONG_Y)
    # hinge arms onto the saddles, drive box
    for y in WING_CLAMPS:
        p.box(V((sx * (SADDLE_HW + 0.28), y, 0)), (0.6, 0.44, 0.5), "hull2", bevel=0.2)
        p.beam(V((xm, y, 0.25)), V((x0 + sx * 0.2, y, top + 0.05)), 0.3, 0.12, "dark")
    p.box(V((xm, yc, 0.36)), (0.36, 0.7, 0.2), "hull2", bevel=0.2)
    # wingtip lights at the outboard corners
    lamp(p, (x1 + sx * 0.06, WING_Y1 - 0.25, top + 0.05), "nav_r" if sx < 0 else "nav_g", 0.16)
    lamp(p, (x1 + sx * 0.06, WING_Y0 + 0.25, top + 0.05), "light", 0.12)
    return p


def build_glow():
    p = parts.Part("engine_glow", MATS)
    # Built around the bell exit plane at y = 0 (object origin moved to NOZZLE_Y below).
    for x, z in BELLS:
        parts.exhaust_glow(p, BELL_R * 0.85, 1.9, "glow", x=x, z=z, segs=16)
    return p


def finish(p, root):
    """Part.finish plus the PANEL_K scale on the panel UVs (see PANEL_K)."""
    obj = p.finish(root)
    uvd = obj.data.uv_layers["panel"].data
    buf = [0.0] * (len(uvd) * 2)
    uvd.foreach_get("uv", buf)
    uvd.foreach_set("uv", [v * PANEL_K for v in buf])
    return obj


def anchored(obj, anchor):
    """Move the object origin to `anchor` without moving the mesh."""
    obj.data.transform(Matrix.Translation(-V(anchor)))
    obj.location = anchor
    return obj


MODULE_ANCHORS = (("module_hab_1", HAB_ANCHOR), ("module_dish", DISH_ANCHOR),
                  ("module_wing_l", WING_ANCHOR[-1]), ("module_wing_r", WING_ANCHOR[1]))


def build_ship():
    """All meshes in ship coordinates (origins at the root); main() anchors the modules
    after the bake."""
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    root = parts.make_root("colony_ship", size=6)
    hull = finish(build_hull(), root)
    drive = finish(build_drive(), root)
    mods = [finish(b, root) for b in (build_hab(), build_dish(), build_wing(-1),
                                      build_wing(1))]
    glow = build_glow().finish(root)
    glow.location = (0, NOZZLE_Y, 0)
    parts.add_empty("deploy_point", root, DEPLOY_POINT, size=2.0)
    for i, (_, anchor) in enumerate(MODULE_ANCHORS):
        parts.add_empty(f"module_{i + 1}", root, anchor, size=1.5)
    return root, [hull, drive] + mods, glow


def extra_views(out_dir):
    """Debug close-ups into out_dir; not part of the previews."""
    scene = bpy.context.scene
    if scene.camera is None:
        common.setup_preview(cam_loc=(-30, 22, 34), cam_target=(0, 0, 0), ortho_scale=40,
                             res=(1600, 1200), key_dir=(-0.5, 0.4, 0.75), key_energy=3.5)
    cam = scene.camera
    os.makedirs(out_dir, exist_ok=True)
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1200
    views = (("nose", (-9, 27, 9), (0, 13.5, 0), 11.0),
             ("mid", (-12, 14, 12), (0, 4.5, 0), 15.0),
             ("wings", (-12, 4, 12), (0, -4.5, 0), 15.0),
             ("drive", (-13, -4, 11), (0, -12.5, 0), 15.0),
             ("rear", (-11, -30, 9), (0, -13, 0), 15.0),
             ("side", (-60, 0, 0), (0, 0, 0), 38.0),
             ("belly", (-16, 10, -20), (0, 0, -1.0), 40.0),
             ("rts", (0, -22, 46), (0, 0, 0), 44.0))
    for name, loc, tgt, ortho in views:
        cam.location = loc
        cam.rotation_euler = (V(tgt) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        cam.data.ortho_scale = ortho
        common.render(os.path.join(out_dir, f"colony_{name}.png"))


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs, glow = build_ship()
    bpy.context.view_layer.update()
    if "--no-textures" not in argv:
        glow.hide_render = True
        wk.texture(objs, MATS, PRE, [(0.0, 0.0)], scorch=SCORCH, decals=DECALS, labels=LABELS,
                   seed0=207, res=2048)
        glow.hide_render = False
    else:
        for o in objs:
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    by_name = {o.name: o for o in objs}
    for name, anchor in MODULE_ANCHORS:
        anchored(by_name[name], anchor)
    bpy.context.view_layer.update()
    wk.stats(objs + [glow])
    for o in [root] + list(root.children):
        print(f"NODE {o.name} {o.type} loc={tuple(round(c, 2) for c in o.location)}")
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews(PRE, 37.0, target=(0, 0, 0))
    extra = [a.split("=", 1)[1] for a in argv if a.startswith("--extra=")]
    if extra:
        extra_views(extra[0])


if __name__ == "__main__":
    main()
