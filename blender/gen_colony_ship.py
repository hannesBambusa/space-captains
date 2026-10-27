"""Generate the colony ship .glb and previews.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_colony_ship.py
  Args after `--`:
    --no-preview      skip the PNG renders
    --out-dir DIR     write colony_quarter.png, colony_side.png, colony_top.png and
                      colony_lineup.png there (default blender/previews)

Design: slow heavy colony ship, functional hard sci-fi, about 35 m long. It flies from
home through the jump gates and unfolds into a forward station. A small chamfered command
module at the nose, a docking collar with three ports, then a long open spine truss with
the station modules clamped along it, folded for transit:
  module_hab_1   twin habitat cans straddling the spine (cream, green colony band)
  module_dish    comms dish with its six petals folded shut into a tulip, on the spine top
  module_wing_l  folded solar wing cassette (stacked PV panels in a strapped frame), port
  module_wing_r  the same, starboard
Behind them a radiation shadow shield and the big drive section: a reactor core flanked
by four propellant tanks, flush radiators, and three engine bells in a triangle.
Hazard stripes on the collar, clamps and drive; running lights (red port, green starboard,
white strobes, amber spine markers).

Layout (Blender Z up, exported +Y up). Ship centre at origin. The nose points along
Blender +Y, which the exporter turns into Godot -Z (forward).
Hierarchy: colony_ship (empty root) -> colony_hull, colony_drive, module_hab_1,
  module_dish, module_wing_l, module_wing_r, engine_glow, and empties deploy_point,
  module_1..4.
Each module object has its origin on its clamp/hinge point on the spine, which is also
where its module_N empty sits (module_1 hab, module_2 dish, module_3 wing_l,
module_4 wing_r), so Godot can move or rotate a module about its mount.
engine_glow is one mesh with all three plumes; its origin is on the shared bell exit plane
(Blender y = NOZZLE_Y) and the plumes extend along Godot local +Z, so scaling it on Z
lengthens every glow backwards (same contract as the other ships, ship.gd finds one node).
"""
import math
import os
import sys

import bpy
from mathutils import Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
from parts import ALONG_Y, V, rot  # noqa: E402

OUT = os.path.join(common.ROOT, "assets", "models", "ships", "colony_ship.glb")
BLEND = os.path.join(common.ROOT, "blender", "colony_ship.blend")

NOSE_Y = 17.4
CMD_Y0 = 13.0          # rear of the command module
COLLAR_Y = 11.9        # docking collar centre
SPINE_Y0 = -8.6        # spine truss runs SPINE_Y0..SPINE_Y1
SPINE_Y1 = 11.2
SPINE_HW = 0.8         # spine half width / half height
SHIELD_Y = -8.9        # shadow shield plate
DRIVE_Y0, DRIVE_Y1 = -14.4, -9.2
NOZZLE_Y = -17.5       # bell exit plane
BELL_R = 1.2
BELL_LEN = 2.5
BELLS = ((-1.55, -0.6), (1.55, -0.6), (0.0, 1.5))   # (x, z) of each bell axis
TANKS = [(sx * 2.55, sz * 1.75) for sx in (-1, 1) for sz in (-1, 1)]

# Module mounts (Blender coords). Module objects have their origin here.
HAB_Y0, HAB_Y1 = 4.4, 10.9
HAB_X, HAB_R = 2.25, 1.35
HAB_ANCHOR = (0.0, (HAB_Y0 + HAB_Y1) / 2, 0.0)
DISH_ANCHOR = (0.0, 1.8, SPINE_HW)
WING_Y0, WING_Y1 = -7.6, -0.6
WING_X0, WING_X1 = 0.95, 3.75       # cassette spans |x| WING_X0..WING_X1
WING_ANCHOR = {-1: (-SPINE_HW, (WING_Y0 + WING_Y1) / 2, 0.0),
               1: (SPINE_HW, (WING_Y0 + WING_Y1) / 2, 0.0)}
DEPLOY_POINT = (0.0, 1.8, 0.0)

MATS = {}


def build_materials():
    m = common.make_material
    MATS["hull"] = m("colony_hull_cream", (0.74, 0.71, 0.64), roughness=0.5, metallic=0.1)
    MATS["hull2"] = m("colony_hull_grey", (0.42, 0.44, 0.47), roughness=0.5, metallic=0.3)
    MATS["steel"] = m("colony_steel", (0.26, 0.28, 0.30), roughness=0.45, metallic=0.6)
    MATS["dark"] = m("colony_structure_dark", (0.06, 0.065, 0.07), roughness=0.55, metallic=0.5)
    MATS["green"] = m("colony_band_green", (0.07, 0.36, 0.2), roughness=0.45, metallic=0.1)
    MATS["yellow"] = m("colony_hazard_yellow", (0.95, 0.66, 0.03), roughness=0.45)
    MATS["black"] = m("colony_hazard_black", (0.03, 0.03, 0.035), roughness=0.6)
    MATS["pv"] = m("colony_solar_cells", (0.03, 0.06, 0.18), roughness=0.25, metallic=0.6)
    MATS["pv_grid"] = m("colony_solar_grid", (0.55, 0.58, 0.62), roughness=0.35, metallic=0.7)
    MATS["foil"] = m("colony_foil_gold", (0.7, 0.5, 0.17), roughness=0.3, metallic=0.9)
    MATS["dish"] = m("colony_dish_white", (0.84, 0.85, 0.86), roughness=0.4, metallic=0.05)
    MATS["window"] = m("colony_window_warm", (1.0, 0.86, 0.62), roughness=0.3,
                       emission=(1.0, 0.8, 0.52), emission_strength=3.5)
    MATS["amber"] = m("colony_light_amber", (1.0, 0.55, 0.1), roughness=0.3,
                      emission=(1.0, 0.5, 0.08), emission_strength=5.0)
    MATS["strobe"] = m("colony_light_white", (1.0, 1.0, 1.0), roughness=0.3,
                       emission=(0.95, 0.97, 1.0), emission_strength=7.0)
    MATS["nav_r"] = m("colony_nav_red", (1.0, 0.05, 0.03), roughness=0.3,
                      emission=(1.0, 0.05, 0.03), emission_strength=6.0)
    MATS["nav_g"] = m("colony_nav_green", (0.1, 1.0, 0.25), roughness=0.3,
                      emission=(0.1, 1.0, 0.25), emission_strength=6.0)
    MATS["glow"] = m("colony_engine_glow", (0.8, 0.9, 1.0), roughness=0.2,
                     emission=(0.62, 0.85, 1.0), emission_strength=6.0)


# --- small helpers ------------------------------------------------------------------

def hazard_ring(p, y, r, width, n=16, thick=0.06):
    """Yellow/black stripe band around the Y axis at y (annulus r..r+thick, width along Y)."""
    for k in range(n):
        a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        r0, r1 = r, r + thick
        pts = [(r0 * math.cos(a0), r0 * math.sin(a0)), (r1 * math.cos(a0), r1 * math.sin(a0)),
               (r1 * math.cos(a1), r1 * math.sin(a1)), (r0 * math.cos(a1), r0 * math.sin(a1))]
        p.slab(pts, -width / 2, width / 2, "yellow" if k % 2 else "black",
               matrix=Matrix.Translation((0, y, 0)) @ ALONG_Y)


def light(p, pos, mat, s=0.2):
    p.box(V(pos), (s, s, s), mat, bevel=0.0)


def clamp_band(p, y, x0, x1, z, hazard=True):
    """Clamp strap across the top of a module from x0 to x1 at y, with a hazard plate."""
    p.box(V(((x0 + x1) / 2, y, z)), (abs(x1 - x0), 0.34, 0.12), "steel", bevel=0.0)
    if hazard:
        p.hazard(min(x0, x1), max(x0, x1), 0.3, 0.06, 0.1,
                 matrix=Matrix.Translation((0, y, z)), pitch=0.3, cols=("yellow", "black"))


# --- hull: command module, collar, spine, shadow shield ------------------------------

def cmd_mat(i, j):
    """Command module loft: grey belly, cream top and flanks."""
    return "hull2" if j in (5, 6, 7) else "hull"


def build_hull():
    p = parts.Part("colony_hull", MATS)
    # Command module: chamfered box tapering into a blunt nose
    rings = [parts.oct_ring(CMD_Y0, 3.0, 2.8, 0.75),
             parts.oct_ring(CMD_Y0 + 0.5, 3.6, 3.2, 0.85),
             parts.oct_ring(NOSE_Y - 1.4, 3.6, 3.2, 0.85),
             parts.oct_ring(NOSE_Y - 0.4, 3.0, 2.6, 0.7, z0=0.1),
             parts.oct_ring(NOSE_Y, 2.3, 1.9, 0.5, z0=0.15)]
    p.loft(rings, "hull", mat_fn=cmd_mat)
    # Green colony band and roof stripe
    parts.prism(p, CMD_Y0 + 1.1, CMD_Y0 + 1.5, (3.66, 3.26, 0.87), (3.66, 3.26, 0.87), "green")
    p.box(V((0, CMD_Y0 + 2.8, 1.61)), (0.6, 2.2, 0.04), "green", bevel=0.0)
    # Flight deck window band on the nose face and front taper
    for k in range(5):
        p.box(V((-0.8 + k * 0.4, NOSE_Y - 0.25, 0.65)), (0.3, 0.3, 0.2), "window",
              r=rot(rx=-0.9), bevel=0.0)
    for sx in (-1, 1):
        for k in range(4):  # cabin portholes
            p.box(V((sx * 1.81, CMD_Y0 + 1.9 + k * 0.5, 0.45)), (0.05, 0.22, 0.18), "window",
                  bevel=0.0)
    # Antenna mast and strobe on the command roof
    p.cyl(V((0.7, CMD_Y0 + 1.4, 1.95)), 0.05, 0.04, 0.8, "dark", segs=6)
    light(p, (0.7, CMD_Y0 + 1.4, 2.4), "strobe", 0.16)
    p.cyl(V((-0.7, CMD_Y0 + 3.2, 1.66)), 0.3, 0.3, 0.12, "steel", segs=10)
    # RCS quads on the command module corners
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.rcs_quad(p, V((sx * 1.55, CMD_Y0 + 3.0, sz * 1.35)), (sx, 0, sz), "steel",
                           "dark", s=0.32)
    # Nav lights on the command flanks
    for sx, mat in ((-1, "nav_r"), (1, "nav_g")):
        light(p, (sx * 1.86, CMD_Y0 + 3.3, 1.0), mat)
    # Rear bulkhead and neck to the collar
    p.cyl(V((0, CMD_Y0 - 0.1, 0)), 1.2, 1.2, 0.2, "steel", segs=16, axis_rot=ALONG_Y)
    p.cyl(V((0, (CMD_Y0 + COLLAR_Y) / 2, 0)), 0.9, 0.9, CMD_Y0 - COLLAR_Y, "hull2", segs=12,
          axis_rot=ALONG_Y)
    # Docking collar: drum with three radial ports (top, port, starboard), hazard bands
    p.cyl(V((0, COLLAR_Y, 0)), 1.55, 1.55, 1.1, "hull2", segs=16, axis_rot=ALONG_Y)
    hazard_ring(p, COLLAR_Y + 0.42, 1.55, 0.2, n=20)
    hazard_ring(p, COLLAR_Y - 0.42, 1.55, 0.2, n=20)
    for d in (V((0, 0, 1)), V((1, 0, 0)), V((-1, 0, 0))):
        c = V((0, COLLAR_Y, 0)) + d * 1.55
        p.tube(c, c + d * 0.45, 0.48, 0.48, "steel", segs=12)
        p.tube(c + d * 0.45, c + d * 0.55, 0.58, 0.58, "yellow", segs=12)
        p.tube(c + d * 0.55, c + d * 0.6, 0.38, 0.38, "dark", segs=12)
    light(p, (0, COLLAR_Y + 0.62, 1.6), "amber", 0.16)

    # Spine: open box truss with a pressurised crew tube through it
    parts.box_truss(p, SPINE_Y0, SPINE_Y1, SPINE_HW, SPINE_HW, 11, "steel", "dark",
                    chord=0.24, brace=0.12)
    p.cyl(V((0, (SPINE_Y0 + SPINE_Y1) / 2, 0)), 0.42, 0.42, SPINE_Y1 - SPINE_Y0, "hull2",
          segs=10, axis_rot=ALONG_Y)
    # Amber marker lights along the top chords
    for k in range(5):
        y = SPINE_Y0 + 1.0 + k * (SPINE_Y1 - SPINE_Y0 - 2.0) / 4
        for sx in (-1, 1):
            light(p, (sx * SPINE_HW, y, SPINE_HW + 0.16), "amber", 0.14)
    # Clamp saddles where the modules mount (rings around the spine)
    for y in (HAB_Y0 + 1.0, HAB_Y1 - 1.0, DISH_ANCHOR[1], WING_Y0 + 1.2, WING_Y1 - 1.2):
        parts.prism(p, y - 0.2, y + 0.2, (1.95, 1.95, 0.4), (1.95, 1.95, 0.4), "hull2")
    # Shadow shield: wide octagonal plate between the drive and the crew, hazard edge
    p.cyl(V((0, SHIELD_Y, 0)), 3.6, 3.6, 0.45, "steel", segs=8, axis_rot=ALONG_Y)
    p.cyl(V((0, SHIELD_Y + 0.3, 0)), 2.6, 3.2, 0.2, "hull2", segs=8, axis_rot=ALONG_Y)
    p.hazard(-2.6, 2.6, 0.32, 0.0, 0.05,
             matrix=Matrix.Translation((0, SHIELD_Y + 0.25, 3.15)) @ rot(rx=math.pi / 2),
             pitch=0.4, cols=("yellow", "black"))
    return p


# --- drive: reactor core, tanks, radiators, bells ------------------------------------

def build_drive():
    p = parts.Part("colony_drive", MATS)
    # Reactor core block
    parts.prism(p, DRIVE_Y0, DRIVE_Y1, (3.4, 3.2, 0.8), (3.0, 2.8, 0.7), "hull2",
                mat_fn=lambda i, j: "hull" if j == 2 else "hull2")
    parts.prism(p, DRIVE_Y1, SHIELD_Y - 0.2, (2.4, 2.4, 0.6), (2.0, 2.0, 0.5), "steel")
    # Green band and hazard on the core roof
    parts.prism(p, -10.6, -10.2, (3.12, 2.92, 0.73), (3.1, 2.9, 0.73), "green")
    p.hazard(-1.2, 1.2, 0.5, 0.0, 0.05, matrix=Matrix.Translation((0, -12.8, 1.6)),
             pitch=0.4, cols=("yellow", "black"))
    # Four propellant tanks on the core corners, foil wrapped, with straps
    for x, z in TANKS:
        parts.capsule(p, DRIVE_Y0 + 0.2, DRIVE_Y1 - 0.2, 1.05,
                      lambda i, j: "foil", segs=14, x=x, z=z, dome0=0.4, dome1=0.4)
        for y in (DRIVE_Y0 + 1.2, DRIVE_Y1 - 1.2):
            p.cyl(V((x, y, z)), 1.09, 1.09, 0.2, "dark", segs=14, axis_rot=ALONG_Y)
        # Tie beam to the core
        p.beam(V((x * 0.4, (DRIVE_Y0 + DRIVE_Y1) / 2, z * 0.4)),
               V((x * 0.75, (DRIVE_Y0 + DRIVE_Y1) / 2, z * 0.75)), 0.3, 0.3, "steel")
    # Flush radiators on the core flanks, between the tanks
    for sx in (-1, 1):
        parts.radiator(p, V((sx * 1.72, (DRIVE_Y0 + DRIVE_Y1) / 2, 0)), 4.4, 1.2, (sx, 0, 0),
                       "dark", "steel", ribs=9)
    # Thrust frame: aft plate, hazard stripes, gimbal collars and bells
    plate_y = DRIVE_Y0 - 0.25
    p.box(V((0, plate_y, 0.3)), (6.4, 0.5, 5.2), "steel", bevel=0.06)
    p.hazard(-3.0, 3.0, 0.35, 0.0, 0.05,
             matrix=Matrix.Translation((0, plate_y - 0.26, -2.05)) @ rot(rx=math.pi / 2),
             pitch=0.45, cols=("yellow", "black"))
    throat_y = NOZZLE_Y + BELL_LEN
    for x, z in BELLS:
        p.tube(V((x, plate_y - 0.25, z)), V((x, throat_y - 0.05, z)), 0.75, 0.6, "dark", segs=12)
        p.cyl(V((x, throat_y + 0.05, z)), 0.72, 0.72, 0.2, "yellow", segs=12, axis_rot=ALONG_Y)
        parts.bell(p, NOZZLE_Y, BELL_R, BELL_LEN, "steel", "dark", x=x, z=z, segs=18)
        p.torus(V((x, NOZZLE_Y + 0.7, z)), BELL_R * 0.84, 0.06, "dark", segs=18, minor_segs=4,
                matrix=rot(rx=math.pi / 2))
    # RCS quads on the drive corners
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.rcs_quad(p, V((sx * 3.2, DRIVE_Y0 - 0.25, sz * 2.4 + 0.3)), (sx, 0, sz),
                           "steel", "dark", s=0.36)
    # Running lights: nav on the outboard tanks, strobes on the aft plate top corners
    for sx, mat in ((-1, "nav_r"), (1, "nav_g")):
        light(p, (sx * 3.63, -11.8, 0), mat, 0.22)
        light(p, (sx * 3.0, plate_y, 2.95), "strobe", 0.2)
    light(p, (0, DRIVE_Y1 - 0.5, 1.47), "amber", 0.18)
    return p


# --- modules --------------------------------------------------------------------------

def build_hab():
    """Twin habitat cans straddling the spine, clamped to it fore and aft."""
    p = parts.Part("module_hab_1", MATS)
    for sx in (-1, 1):
        x = sx * HAB_X

        def mf(i, j):
            return "hull"
        parts.capsule(p, HAB_Y0, HAB_Y1, HAB_R, mf, segs=16, x=x, dome0=0.35, dome1=0.35)
        # Green band, panel rings
        p.cyl(V((x, (HAB_Y0 + HAB_Y1) / 2, 0)), HAB_R + 0.04, HAB_R + 0.04, 0.5, "green",
              segs=16, axis_rot=ALONG_Y)
        for y in (HAB_Y0 + 1.1, HAB_Y1 - 1.1):
            p.cyl(V((x, y, 0)), HAB_R + 0.03, HAB_R + 0.03, 0.12, "hull2", segs=16,
                  axis_rot=ALONG_Y)
        # Portholes on the outboard flank (two decks), lit
        for row_z in (0.45, -0.25):
            for k in range(6):
                y = HAB_Y0 + 1.3 + k * 0.8
                if abs(y - (HAB_Y0 + HAB_Y1) / 2) < 0.4:
                    continue
                p.box(V((x + sx * (HAB_R - 0.02), y, row_z)), (0.08, 0.26, 0.2), "window",
                      bevel=0.0)
        # Roof hatch and end-dome docking ports
        p.cyl(V((x, HAB_Y1 - 2.0, HAB_R - 0.02)), 0.36, 0.36, 0.14, "steel", segs=10)
        for y, d in ((HAB_Y1 + 0.05, 1), (HAB_Y0 - 0.05, -1)):
            p.cyl(V((x, y, 0)), 0.35, 0.35, 0.25, "steel", segs=10, axis_rot=ALONG_Y)
        # Clamps to the spine: arms from the saddle to the can, yellow/black straps on top
        for y in (HAB_Y0 + 1.0, HAB_Y1 - 1.0):
            p.box(V((sx * 1.1, y, 0)), (0.5, 0.3, 0.6), "steel", bevel=0.1)
            clamp_band(p, y, sx * 1.0, sx * (HAB_X + 0.4), HAB_R - 0.05)
        light(p, (x + sx * 0.3, HAB_Y1 - 0.6, HAB_R * 0.9), "amber", 0.14)
    return p


def build_dish():
    """Comms dish folded shut: six petals hinged on a hub rim, closed into a bud (about
    5 m across once the petals open flat)."""
    p = parts.Part("module_dish", MATS)
    ax, ay, az = DISH_ANCHOR
    # Turret base on the spine top and a short mast
    p.box(V((ax, ay, az + 0.12)), (1.4, 1.4, 0.24), "steel", bevel=0.08)
    clamp_band(p, ay - 0.55, -0.7, 0.7, az + 0.24)
    p.cyl(V((ax, ay, az + 0.55)), 0.3, 0.3, 0.6, "hull2", segs=10)
    hub_z = az + 0.95
    hub_r = 0.9
    p.cyl(V((ax, ay, hub_z)), hub_r, hub_r * 0.85, 0.3, "dish", segs=12)
    fold = math.radians(98)   # past vertical: the petals lean in and close the bud
    length = 1.6
    t30 = math.tan(math.radians(30))
    for k in range(6):
        a = k * math.pi / 3
        u = V((math.cos(a), math.sin(a), 0))
        t = V((-math.sin(a), math.cos(a), 0))
        hinge = V((ax, ay, hub_z + 0.1)) + u * hub_r
        d = u * math.cos(fold) + V((0, 0, 1)) * math.sin(fold)   # along the petal
        n = d.cross(t)                                            # petal outward normal
        frame = Matrix((d, t, -n)).transposed().to_4x4()
        m = Matrix.Translation(hinge) @ frame
        w0 = hub_r * t30
        w1 = (hub_r + length * math.cos(fold)) * t30
        p.slab([(0, -w0), (length, -w1), (length, w1), (0, w0)], 0.0, 0.06, "dish", matrix=m)
        # Back rib (dark) down the petal centre line
        p.beam(hinge + n * 0.06, hinge + d * length * 0.95 + n * 0.06, 0.08, 0.08, "dark")
    # Feed horn poking up out of the closed petals
    tip_z = hub_z + 0.1 + length * math.sin(fold)
    p.cyl(V((ax, ay, tip_z - 0.3)), 0.08, 0.06, 1.0, "dark", segs=6)
    light(p, (ax, ay, tip_z + 0.25), "strobe", 0.14)
    return p


def build_wing(sx):
    """Folded solar wing cassette: stacked PV panels in a strapped frame, hinge on the spine."""
    name = "module_wing_l" if sx < 0 else "module_wing_r"
    p = parts.Part(name, MATS)
    x0, x1 = sx * WING_X0, sx * WING_X1
    xc, w = (x0 + x1) / 2, WING_X1 - WING_X0
    yc, length = (WING_Y0 + WING_Y1) / 2, WING_Y1 - WING_Y0
    # Panel stack: 6 leaves with thin dark gaps
    n = 6
    th = 0.12
    z_base = -0.45
    for k in range(n):
        z = z_base + k * (th + 0.04) + th / 2
        p.box(V((xc, yc, z)), (w - 0.2, length - 0.2, th), "pv", bevel=0.0)
    top = z_base + n * (th + 0.04)
    # Cell grid on the top leaf (silver bus lines)
    for k in range(1, 7):
        y = WING_Y0 + 0.1 + (length - 0.2) * k / 7
        p.box(V((xc, y, top - 0.02)), (w - 0.3, 0.05, 0.03), "pv_grid", bevel=0.0)
    p.box(V((xc, yc, top - 0.02)), (0.05, length - 0.3, 0.03), "pv_grid", bevel=0.0)
    # Cassette frame: bottom tray and corner posts
    p.box(V((xc, yc, z_base - 0.08)), (w, length, 0.14), "steel", bevel=0.0)
    for xx in (x0 + sx * 0.05, x1 - sx * 0.05):
        for yy in (WING_Y0 + 0.05, WING_Y1 - 0.05):
            p.box(V((xx, yy, (z_base + top) / 2)), (0.16, 0.16, top - z_base + 0.2), "steel",
                  bevel=0.0)
    # Launch-lock straps across the stack, hazard striped
    for y in (WING_Y0 + 1.2, yc, WING_Y1 - 1.2):
        clamp_band(p, y, x0, x1, top + 0.04)
        for xx in (x0, x1):
            p.box(V((xx, y, (z_base + top) / 2)), (0.1, 0.34, top - z_base + 0.2), "steel",
                  bevel=0.0)
    # Hinge: knuckle along the spine side and two arms to the saddles
    p.cyl(V((sx * (SPINE_HW + 0.05), yc, 0)), 0.16, 0.16, length - 1.0, "dark", segs=8,
          axis_rot=ALONG_Y)
    for y in (WING_Y0 + 1.2, WING_Y1 - 1.2):
        p.box(V((sx * (SPINE_HW + WING_X0) / 2 + sx * 0.05, y, 0)),
              (WING_X0 - SPINE_HW + 0.3, 0.3, 0.3), "steel", bevel=0.0)
    # Wingtip light (nav colour) at the outboard front corner
    light(p, (x1 + sx * 0.1, WING_Y1 - 0.2, top), "nav_r" if sx < 0 else "nav_g", 0.2)
    return p


def build_glow():
    p = parts.Part("engine_glow", MATS)
    # Built around the bell exit plane at y = 0 (object origin moved to NOZZLE_Y below).
    for x, z in BELLS:
        parts.exhaust_glow(p, BELL_R * 0.85, 1.8, "glow", x=x, z=z, segs=16)
    return p


def anchored(obj, anchor):
    """Move the object origin to `anchor` without moving the mesh."""
    obj.data.transform(Matrix.Translation(-V(anchor)))
    obj.location = anchor
    return obj


def build_ship():
    build_materials()
    root = parts.make_root("colony_ship", size=6)
    hull = build_hull().finish(root)
    drive = build_drive().finish(root)
    hab = anchored(build_hab().finish(root), HAB_ANCHOR)
    dish = anchored(build_dish().finish(root), DISH_ANCHOR)
    wing_l = anchored(build_wing(-1).finish(root), WING_ANCHOR[-1])
    wing_r = anchored(build_wing(1).finish(root), WING_ANCHOR[1])
    glow = build_glow().finish(root)
    glow.location = (0, NOZZLE_Y, 0)
    parts.add_empty("deploy_point", root, DEPLOY_POINT, size=2.0)
    for i, anchor in enumerate((HAB_ANCHOR, DISH_ANCHOR, WING_ANCHOR[-1], WING_ANCHOR[1])):
        parts.add_empty(f"module_{i + 1}", root, anchor, size=1.5)
    return root, [hull, drive, hab, dish, wing_l, wing_r, glow]


# --- previews -----------------------------------------------------------------------

def previews(out_dir):
    from mathutils import Vector
    os.makedirs(out_dir, exist_ok=True)
    target = Vector((0, 0, 0))
    common.setup_preview(cam_loc=(-30, 22, 34), cam_target=tuple(target), ortho_scale=40,
                         res=(1600, 1200), key_dir=(-0.5, 0.4, 0.75), key_energy=3.5)
    common.render(os.path.join(out_dir, "colony_quarter.png"))
    scene = bpy.context.scene
    cam = scene.camera
    cam.location = (60, 0, 0.5)
    cam.rotation_euler = (math.pi / 2, 0, math.pi / 2)
    cam.data.ortho_scale = 38
    scene.render.resolution_x, scene.render.resolution_y = 1600, 700
    common.render(os.path.join(out_dir, "colony_side.png"))
    cam.location = (0, 0, 60)
    cam.rotation_euler = (0, 0, 0)
    cam.data.ortho_scale = 38
    scene.render.resolution_x, scene.render.resolution_y = 900, 1200
    common.render(os.path.join(out_dir, "colony_top.png"))


def lineup(out_dir):
    """Colony ship next to the other ships at true scale (3/4 view)."""
    common.reset_scene()
    ships = (("colony_ship", 0.0), ("merc_fighter", 10.0), ("miner", 17.0),
             ("explorer", 24.0), ("syndicate_gunship", 33.0), ("cargo_shuttle", 42.0))
    for name, x in ships:
        path = os.path.join(common.ROOT, "assets", "models", "ships", name + ".glb")
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        new = set(bpy.data.objects) - before
        for r in [o for o in new if o.parent is None]:
            r.location.x += x
        meshes = [o for o in new if o.type == "MESH"]
        bpy.context.view_layer.update()
        ys = [(o.matrix_world @ V(c)).y for o in meshes for c in o.bound_box]
        print(f"LINEUP {name} length={max(ys) - min(ys):.1f}")
    common.setup_preview(cam_loc=(-18, 30, 38), cam_target=(19, 0, 0), ortho_scale=58,
                         res=(1800, 1100), key_dir=(-0.5, 0.4, 0.75), key_energy=3.5)
    common.render(os.path.join(out_dir, "colony_lineup.png"))


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_ship()
    parts.print_stats(objs)
    for o in [root] + list(root.children):
        print(f"NODE {o.name} {o.type} loc={tuple(round(c, 2) for c in o.location)}")
    parts.save_blend(BLEND)
    common.export_glb(root, OUT)
    if "--no-preview" in argv:
        return
    out_dir = argv[argv.index("--out-dir") + 1] if "--out-dir" in argv else common.PREVIEW_DIR
    previews(out_dir)
    lineup(out_dir)


main()
