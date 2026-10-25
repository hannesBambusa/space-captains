"""Generate the planet raider dropship .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_dropship.py
  Add `-- --no-preview` to skip the PNG renders.

Design: chunky atmospheric dropship that drops into a planet's air, grabs cargo and
climbs back out. Blunt lifting-body fuselage (8-sided lofted hull) with a stepped
flight deck, heat-scarred chin and belly tiles from re-entry, short stub wings carrying
two lift-engine nacelles (vertical thrust nozzles underneath, fan grilles on top), two
main engine bells at the stern, four landing legs folded flat against the belly,
a chin gun turret, and a big cargo pod clamped underneath.

Layout (Blender Z up, exported +Y up). Ship centre at origin on the play plane z=0.
The nose points along Blender +Y = Godot -Z (forward), like every other ship.
  length 13.35 m (bell exits y -6.6 .. gun muzzles y 6.75), width 7.9 m over the nacelles,
  height 6.6 m (pod bottom z -3.3 .. tail fin tips z 3.3).
Hierarchy: dropship (empty root) -> dropship_hull, dropship_pod, engine_glow,
  muzzle_l, muzzle_r (empties).
engine_glow has its origin on the bell exit plane (Blender y = NOZZLE_Y), plume along
Godot local +Z (scale Z to lengthen). dropship_pod has its origin at the clamp plane
(top of the pod, Blender z = POD_TOP), so Godot can detach or hide it.
Materials are flat (like the other ships), names prefixed "drop_".
"""
import math
import os
import shutil
import sys

from mathutils import Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
from parts import ALONG_Y, V, rot  # noqa: E402

OUT = os.path.join(common.ROOT, "assets", "models", "ships", "dropship.glb")
SCRATCH = "/private/tmp/claude-501/-Users-hannesalm-code-games/559853a4-05f8-403b-881d-863d1678ad65/scratchpad"
NOZZLE_Y = -6.6
BELL_R = 0.72
BELL_LEN = 1.35
ENG_X = 1.05
ENG_Z = 0.35
NAC_X = 3.05
NAC_Z = 0.35
POD_TOP = -1.42
GUN = V((0.0, 5.0, -1.05))
MUZZLE_Y = 6.75

# fuselage rings: (y, (w, h, chamfer), z centre)
RINGS = (
    (-5.25, (3.4, 2.5, 0.75), 0.35),
    (-4.6, (4.1, 3.0, 0.9), 0.3),
    (-1.0, (4.5, 3.25, 0.95), 0.3),
    (2.6, (4.4, 3.2, 0.95), 0.28),
    (4.4, (3.9, 2.55, 0.85), 0.0),
    (5.7, (3.0, 1.7, 0.6), -0.3),
    (6.35, (2.1, 1.05, 0.38), -0.45),
)

MATS = {}


def build_materials():
    m = common.make_material
    MATS["hull"] = m("drop_hull_sand", (0.25, 0.235, 0.2), roughness=0.66, metallic=0.1)
    MATS["hull3"] = m("drop_hull_patch", (0.31, 0.3, 0.27), roughness=0.6, metallic=0.1)
    MATS["hull2"] = m("drop_hull_olive", (0.11, 0.115, 0.095), roughness=0.62, metallic=0.15)
    MATS["dark"] = m("drop_structure_dark", (0.05, 0.053, 0.056), roughness=0.55, metallic=0.5)
    MATS["gun"] = m("drop_gunmetal", (0.12, 0.125, 0.135), roughness=0.4, metallic=0.75)
    MATS["burn"] = m("drop_heat_scar", (0.075, 0.045, 0.03), roughness=0.85, metallic=0.2)
    MATS["burn2"] = m("drop_heat_tile", (0.12, 0.10, 0.09), roughness=0.9, metallic=0.05)
    MATS["temper"] = m("drop_heat_tint", (0.2, 0.15, 0.22), roughness=0.35, metallic=0.85)
    MATS["accent"] = m("drop_accent_orange", (0.55, 0.19, 0.035), roughness=0.55)
    MATS["hazard"] = m("drop_hazard_yellow", (0.62, 0.43, 0.03), roughness=0.55)
    MATS["pod"] = m("drop_pod_steel", (0.30, 0.29, 0.26), roughness=0.6, metallic=0.25)
    MATS["window"] = m("drop_window_warm", (1.0, 0.85, 0.6), roughness=0.3,
                       emission=(1.0, 0.72, 0.42), emission_strength=1.6)
    MATS["light"] = m("drop_light_amber", (1.0, 0.5, 0.15), roughness=0.3,
                      emission=(1.0, 0.5, 0.12), emission_strength=5.0)
    MATS["nav_r"] = m("drop_nav_red", (1.0, 0.05, 0.03), roughness=0.3,
                      emission=(1.0, 0.05, 0.03), emission_strength=6.0)
    MATS["nav_g"] = m("drop_nav_green", (0.1, 1.0, 0.25), roughness=0.3,
                      emission=(0.1, 1.0, 0.25), emission_strength=6.0)
    MATS["glow"] = m("drop_engine_glow", (0.8, 0.95, 1.0), roughness=0.2,
                     emission=(0.65, 0.92, 1.0), emission_strength=6.0)


def hull_mat(i, j):
    """Loft face material: belly heat-scarred, chin burnt, top + flanks painted."""
    y_front = RINGS[i + 1][0]
    if j == 6:
        return "burn2"
    if j in (5, 7):
        return "burn" if y_front > -4.0 else "hull2"
    if j in (0, 4):
        return "hull2" if y_front < -4.0 else "hull"
    return "hull"


def build_hull():
    p = parts.Part("dropship_hull", MATS)
    rings = [parts.oct_ring(y, *d, z0=z) for y, d, z in RINGS]
    p.loft(rings, "hull", mat_fn=hull_mat)

    # Flight deck: stepped canopy on the nose slope, dark frame, warm panes
    a = math.atan2(1.275 - 0.55, 5.7 - 4.4)
    cz = (1.275 + 0.55) / 2 + 0.04
    canopy = rot(rx=-a)
    p.box(V((0, 5.05, cz)), (2.5, 1.55, 0.18), "dark", r=canopy, bevel=0.1)
    for k, x in enumerate((-0.75, -0.25, 0.25, 0.75)):
        p.box(V((x, 5.25, cz + 0.08)), (0.34, 0.55, 0.06), "window", r=canopy, bevel=0.0)
    # dorsal hull patches in a second paint tone (old replacement plates)
    for x, y, w, l in ((1.25, -3.0, 1.0, 1.8), (-1.3, 0.6, 0.9, 1.4), (1.2, 1.6, 0.8, 1.0)):
        p.box(V((x, y, 1.93)), (w, l, 0.06), "hull3", bevel=0.0)
    for sx in (-1, 1):   # side cheek windows
        p.box(V((sx * 1.82, 4.7, 0.7)), (0.1, 0.55, 0.22), "window", r=rot(rz=sx * 0.2),
              bevel=0.0)
    # Heat scarring: chin tiles in two tones, scorch streaks running back along the flanks
    for k in range(5):
        for s in range(-2, 3):
            mat = "burn" if (k + s) % 3 else "burn2"
            p.box(V((s * 0.42, 4.2 + k * 0.42, -1.33 + k * 0.1)), (0.38, 0.38, 0.06), mat,
                  bevel=0.0)
    # lower flanks scorched from re-entry: ragged burn band, heaviest at the front
    for sx in (-1, 1):
        for k in range(9):
            y = 3.4 - k * 0.85
            top = 0.25 - 0.06 * k - (0.22 if k % 2 else 0.0)
            p.box(V((sx * 2.265, y, (top - 0.38) / 2)), (0.04, 0.9, top + 0.38), "burn",
                  bevel=0.0)
    # Painted identity: orange band behind the flight deck, hazard chevrons on the stern
    parts.prism(p, 2.75, 3.05, (4.46, 3.26, 0.97), (4.46, 3.26, 0.97), "accent", z0=0.28)
    p.hazard(-1.4, 1.4, 0.35, -0.03, 0.03,
             matrix=Matrix.Translation((0, -5.27, 1.25)) @ rot(rx=math.pi / 2), pitch=0.4,
             cols=("hazard", "dark"))

    # Dorsal spine: armoured hump, intake, antenna, comms blister
    parts.prism(p, -4.3, 2.2, (1.8, 0.7, 0.3), (1.6, 0.6, 0.25), "hull2", z0=2.18)
    for k in range(4):
        p.box(V((0, -3.6 + k * 1.6, 2.56)), (1.5, 0.2, 0.08), "dark", bevel=0.0)
    p.box(V((0, 2.6, 2.0)), (1.2, 0.8, 0.35), "dark", bevel=0.1)
    p.cyl(V((0.55, -4.0, 2.55)), 0.05, 0.03, 1.0, "dark", segs=5)
    p.box(V((0.55, -4.0, 3.05)), (0.12, 0.12, 0.12), "light", bevel=0.0)
    p.sphere(V((-0.5, -2.2, 2.55)), 0.3, "hull", segs=10, rings=5, scale=(1, 1, 0.55))
    # Side armour plates and access hatches
    for sx in (-1, 1):
        for y in (-3.2, -0.9, 1.4):
            p.box(V((sx * 2.27, y, 0.55)), (0.12, 2.0, 1.15), "hull", bevel=0.1)
            p.box(V((sx * 2.33, y + 0.6, 0.9)), (0.04, 0.5, 0.35), "dark", bevel=0.0)
        p.box(V((sx * 2.3, 0.3, -0.35)), (0.06, 6.0, 0.1), "accent", bevel=0.0)
    # Stub wings to the nacelles (thick, with a dark leading edge)
    for sx in (-1, 1):
        p.slab([(sx * 2.1, -3.6), (sx * (NAC_X - 0.3), -3.4), (sx * (NAC_X - 0.3), 0.4),
                (sx * 2.1, 1.4)][::sx], NAC_Z - 0.22, NAC_Z + 0.22, "hull2")
        p.beam(V((sx * 2.2, 1.35, NAC_Z)), V((sx * (NAC_X - 0.4), 0.45, NAC_Z)), 0.2, 0.46,
               "dark")
        nacelle(p, sx)

    tail_fins(p)
    # Main engines: thrust frame, gimbal collars, bells with heat-tinted lips
    p.box(V((0, -5.45, ENG_Z)), (3.2, 0.5, 1.9), "dark", bevel=0.1)
    for sx in (-1, 1):
        x = sx * ENG_X
        p.cyl(V((x, -5.75, ENG_Z)), 0.62, 0.58, 0.3, "gun", segs=14, axis_rot=ALONG_Y)
        p.cyl(V((x, -5.95, ENG_Z)), 0.5, 0.5, 0.12, "accent", segs=14, axis_rot=ALONG_Y)
        parts.bell(p, NOZZLE_Y, BELL_R, BELL_LEN - 0.4, "temper", "dark", x=x, z=ENG_Z,
                   segs=16)
    # Folded landing legs: strut + knee + foot pad lying flat under the stub wings
    for sx in (-1, 1):
        for y0, y1 in ((-3.4, -1.2), (1.0, 3.0)):
            x = sx * 1.85
            p.box(V((x, y0, -1.25)), (0.5, 0.5, 0.4), "dark", bevel=0.1)        # hinge
            p.beam(V((x, y0, -1.3)), V((x, y1, -1.42)), 0.32, 0.26, "gun")       # strut
            p.beam(V((x - sx * 0.25, y0 + 0.3, -1.25)), V((x - sx * 0.25, y1 - 0.3, -1.38)),
                   0.12, 0.12, "hull2")                                           # actuator
            p.cyl(V((x, y1, -1.48)), 0.42, 0.42, 0.14, "hull2", segs=10)         # foot pad
            p.box(V((x, y1, -1.41)), (0.18, 0.18, 0.1), "hazard", bevel=0.0)
    # Pod clamps: two saddle yokes on the belly
    for y in (-2.6, 1.9):
        p.box(V((0, y, -1.35)), (2.6, 0.5, 0.2), "dark", bevel=0.05)
        for sx in (-1, 1):
            p.box(V((sx * 1.3, y, -1.55)), (0.25, 0.55, 0.5), "gun", bevel=0.1)
    # Chin gun turret: ball mount, twin barrels
    p.sphere(GUN, 0.42, "gun", segs=10, rings=6)
    p.cyl(GUN + V((0, 0, 0.28)), 0.46, 0.46, 0.14, "dark", segs=10)
    for sx in (-1, 1):
        p.cyl(GUN + V((sx * 0.17, 0.9, -0.02)), 0.07, 0.07, 1.6, "dark", segs=6,
              axis_rot=ALONG_Y)
        p.cyl(GUN + V((sx * 0.17, 1.6, -0.02)), 0.1, 0.1, 0.3, "gun", segs=6, axis_rot=ALONG_Y)
    # RCS quads on the corners
    for y in (4.0, -4.4):
        for sx in (-1, 1):
            parts.rcs_quad(p, V((sx * 1.85, y, 1.55)), (sx, 0, 1), "gun", "dark", s=0.26)
    # Nav lights, landing lamps
    p.box(V((-NAC_X - 0.9, 0.2, NAC_Z + 0.3)), (0.16, 0.22, 0.14), "nav_r", bevel=0.0)
    p.box(V((NAC_X + 0.9, 0.2, NAC_Z + 0.3)), (0.16, 0.22, 0.14), "nav_g", bevel=0.0)
    p.box(V((0, -5.3, 1.9)), (0.2, 0.15, 0.15), "light", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 0.7, 6.1, -0.98)), (0.3, 0.2, 0.08), "light", bevel=0.0)
    return p


def nacelle(p, sx):
    """Lift-engine pod: armoured box nacelle, ducted fan on top, thrust nozzle underneath."""
    x = sx * NAC_X
    z = NAC_Z
    secs = ((-4.1, -3.4, (1.2, 1.2, 0.35), (1.75, 1.75, 0.5), "dark"),
            (-3.4, 1.0, (1.75, 1.75, 0.5), (1.75, 1.75, 0.5), "hull"),
            (1.0, 1.3, (1.79, 1.79, 0.5), (1.79, 1.79, 0.5), "accent"),
            (1.3, 2.3, (1.75, 1.75, 0.5), (1.3, 1.1, 0.38), "hull2"))

    def nm(base):
        return lambda i, j: "burn" if j in (5, 6, 7) and base == "hull" else base
    for y0, y1, d0, d1, mat in secs:
        parts.prism(p, y0, y1, d0, d1, mat, mat_fn=nm(mat), x0=x, z0=z)
    # ducted fan on top: raised ring, dark well, grille bars, hub
    p.torus(V((x, -1.1, z + 0.95)), 0.72, 0.1, "hull2", segs=14, minor_segs=4)
    p.cyl(V((x, -1.1, z + 0.88)), 0.68, 0.68, 0.06, "dark", segs=14)
    for k in range(4):
        a = k * math.pi / 4
        d = V((math.cos(a), math.sin(a), 0)) * 0.66
        p.beam(V((x, -1.1, z + 0.95)) - d, V((x, -1.1, z + 0.95)) + d, 0.06, 0.05, "gun")
    p.cyl(V((x, -1.1, z + 0.97)), 0.16, 0.16, 0.08, "hull2", segs=8)
    # vertical thrust nozzle underneath, heat-tinted
    p.cyl(V((x, -1.1, z - 1.0)), 0.6, 0.5, 0.3, "temper", segs=12)
    p.cyl(V((x, -1.1, z - 1.16)), 0.45, 0.45, 0.04, "dark", segs=12)
    # intake grille on the front face, aft cap
    p.box(V((x, 2.31, z + 0.05)), (0.8, 0.06, 0.55), "dark", bevel=0.0)
    for k in range(3):
        p.box(V((x, 2.34, z - 0.15 + k * 0.2)), (0.82, 0.05, 0.05), "gun", bevel=0.0)
    p.cyl(V((x, -4.25, z)), 0.42, 0.3, 0.3, "dark", segs=10, axis_rot=ALONG_Y)
    # side armour plate with hatch
    p.box(V((x + sx * 0.9, -1.2, z + 0.1)), (0.08, 2.6, 0.8), "hull3", bevel=0.1)


def tail_fins(p):
    """Two canted dorsal stabilisers at the stern."""
    for sx in (-1, 1):
        m = (Matrix.Translation((sx * 0.95, 0, 0)) @ Matrix.Rotation(sx * 0.38, 4, "Y")
             @ parts.SIDE)
        p.slab([(-5.25, 1.5), (-3.0, 1.5), (-4.3, 3.1), (-5.5, 3.2)], -0.09, 0.09, "hull2",
               matrix=m)
        p.slab([(-5.3, 2.75), (-4.55, 2.75), (-4.3, 3.12), (-5.5, 3.22)], -0.11, 0.11,
               "accent", matrix=m)
        tip = m @ V((-5.45, 3.2, 0))
        p.box(tip + V((0, 0, 0.06)), (0.14, 0.14, 0.12), "nav_r" if sx < 0 else "nav_g",
              bevel=0.0)


def build_pod():
    """Underslung cargo pod, built with its clamp plane at z = 0 (origin moved later)."""
    p = parts.Part("dropship_pod", MATS)
    L, W, H = 7.0, 3.4, 1.9
    cy = -0.35
    p.box(V((0, cy, -H / 2)), (W - 0.15, L - 0.4, H - 0.12), "pod", bevel=0.08)
    for sy in (-1, 1):   # end frames
        p.box(V((0, cy + sy * (L / 2 - 0.2), -H / 2)), (W, 0.4, H), "dark", bevel=0.05)
    for k in range(5):   # corrugation ribs
        y = cy - L / 2 + 0.9 + k * (L - 1.8) / 4
        p.box(V((0, y, -H / 2)), (W + 0.04, 0.12, H - 0.1), "hull2", bevel=0.0)
    p.box(V((0, cy + 1.4, -H / 2)), (W + 0.06, 0.5, H + 0.02), "accent", bevel=0.0)
    for sx in (-1, 1):
        p.hazard(cy - 2.8, cy - 1.0, 0.45, -0.02, 0.02,
                 matrix=Matrix.Translation((sx * (W / 2 + 0.01), 0, -H / 2))
                 @ Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1))),
                 pitch=0.4, cols=("hazard", "dark"))
    # lifting eyes on top, scuffed skid rails underneath
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box(V((sx * 1.3, cy + sy * 2.9, 0.05)), (0.25, 0.25, 0.15), "hazard", bevel=0.0)
        p.box(V((sx * 1.2, cy, -H - 0.04)), (0.25, L - 0.6, 0.1), "burn", bevel=0.0)
    p.box(V((0, cy - L / 2 - 0.01, -H / 2)), (0.4, 0.04, 0.3), "light", bevel=0.0)
    return p


def build_glow():
    p = parts.Part("engine_glow", MATS)
    for sx in (-1, 1):
        parts.exhaust_glow(p, BELL_R * 0.85, 1.1, "glow", x=sx * ENG_X, z=ENG_Z, segs=14)
    return p


def build_ship():
    build_materials()
    root = parts.make_root("dropship")
    objs = [b().finish(root) for b in (build_hull, build_pod, build_glow)]
    objs[1].location = (0, 0, POD_TOP)
    objs[2].location = (0, NOZZLE_Y, 0)
    for name, sx in (("muzzle_l", -1), ("muzzle_r", 1)):
        parts.add_empty(name, root, (sx * 0.17, MUZZLE_Y, GUN.z - 0.02), size=1.0)
    return root, objs


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_ship()
    parts.print_stats(objs)
    parts.save_blend(os.path.join(common.ROOT, "blender", "dropship.blend"))
    common.export_glb(root, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews("dropship", 15.0, target=(0, 0, -0.4))
        if os.path.isdir(SCRATCH):
            for n in ("dropship_preview.png", "dropship_top.png"):
                shutil.copy(os.path.join(common.PREVIEW_DIR, n), SCRATCH)


main()
