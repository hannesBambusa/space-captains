"""Generate the scavenger raider .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python /Users/hannesalm/code/games/space-majesty/blender/gen_scavenger_ship.py
  Add `-- --no-preview` to skip the PNG renders.

Design: patched-together belter raider in the same functional language as the player
ships, but cobbled. An olive crew module (an old pressure can, slightly off-centre)
with a welded armour slab and slit windows on its front, an exposed box-truss spine,
a rust-red cargo container welded to the starboard side, bare propellant spheres
strapped to the port side of the truss, a twin autocannon on a turret ring on the
container roof (muzzle_l / muzzle_r at the barrel tips), patch plates, cables, and
one salvaged engine bell with a short red-orange glow. Hostile, but a working ship.

Layout (Blender Z up, exported +Y up). Ship centre at origin on the play plane z=0.
The nose points along Blender +Y, which the exporter turns into Godot -Z (forward).
Hierarchy: scavenger (empty root) -> scav_hull, scav_rig, engine_glow,
  muzzle_l (empty), muzzle_r (empty).
engine_glow has its origin on the bell exit plane (Blender y = NOZZLE_Y, x = ENG_X) and
its plume extends along Godot local +Z, so scaling it on Z lengthens the glow backwards.
Muzzle empties are unrotated, so their Godot -Z points forward along the barrels.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
from parts import ALONG_X, ALONG_Y, V, rot  # noqa: E402

OUT = os.path.join(common.ROOT, "assets", "models", "ships", "scavenger.glb")
ENG_X = -0.3
NOZZLE_Y = -7.0
BELL_R = 1.15
BELL_LEN = 1.5
MOD_X, MOD_Z, MOD_R = -0.45, 0.2, 1.25
MOD_Y0, MOD_Y1 = 2.4, 5.7
SPINE_X, SPINE_Y0, SPINE_Y1 = -0.4, -4.6, 2.6
CONT_POS, CONT_SIZE = V((1.25, -0.9, 0.15)), (1.9, 4.4, 2.0)
GUN = V((1.25, 0.9, 1.75))
BARREL_DX = 0.24
MUZZLE_Y = 6.1

MATS = {}


def build_materials():
    m = common.make_material
    MATS["paint"] = m("scav_container_paint", (0.30, 0.075, 0.025), roughness=0.75, metallic=0.25)
    MATS["rust"] = m("scav_hull_rust", (0.15, 0.065, 0.03), roughness=0.85, metallic=0.3)
    MATS["olive"] = m("scav_plate_olive", (0.10, 0.11, 0.05), roughness=0.8, metallic=0.2)
    MATS["scrap"] = m("scav_plate_scrap", (0.13, 0.115, 0.095), roughness=0.75, metallic=0.4)
    MATS["dark"] = m("scav_frame_dark", (0.045, 0.04, 0.035), roughness=0.6, metallic=0.6)
    MATS["yellow"] = m("scav_hazard_yellow", (0.45, 0.30, 0.03), roughness=0.7, metallic=0.2)
    MATS["window"] = m("scav_window_red", (1.0, 0.25, 0.08), roughness=0.3,
                       emission=(1.0, 0.22, 0.05), emission_strength=3.5)
    MATS["light"] = m("scav_light_red", (1.0, 0.08, 0.03), roughness=0.3,
                      emission=(1.0, 0.06, 0.02), emission_strength=5.0)
    MATS["glow"] = m("scav_engine_glow", (1.0, 0.3, 0.08), roughness=0.2,
                     emission=(1.0, 0.2, 0.035), emission_strength=5.0)


def cable(p, a, b, sag, r=0.07, n=6, mat="dark"):
    """Sagging cable as a chain of tubes (sag along -Z)."""
    pts = []
    for k in range(n + 1):
        t = k / n
        q = a.lerp(b, t)
        q.z -= sag * 4 * t * (1 - t)
        pts.append(q)
    for q0, q1 in zip(pts, pts[1:]):
        p.tube(q0, q1, r, r, mat, segs=5)


def patch(p, c, size, rng, mat="scrap"):
    """Slightly skewed welded patch plate."""
    p.box(c, size, mat, r=rot(rx=rng.uniform(-0.06, 0.06), ry=rng.uniform(-0.06, 0.06),
                               rz=rng.uniform(-0.1, 0.1)), bevel=0.0)


def build_hull(rng):
    p = parts.Part("scav_hull", MATS)
    # --- Crew module: old olive pressure can, rust end caps, off-centre to port
    parts.capsule(p, MOD_Y0, MOD_Y1, MOD_R,
                  lambda i, j: "rust" if j in (0, 1, 5, 6) or i in (3, 4) else "olive",
                  segs=14, x=MOD_X, z=MOD_Z, dome0=0.35, dome1=0.3)
    # Welded armour slab across the front with slit windows
    fc = V((MOD_X, MOD_Y1 + 0.05, MOD_Z + 0.1))
    p.box(fc, (2.3, 0.3, 2.0), "scrap", r=rot(rz=0.04, rx=0.05), bevel=0.06)
    for dx in (-0.55, 0.0, 0.55):
        p.box(fc + V((dx, 0.17, 0.45)), (0.4, 0.04, 0.12), "window", bevel=0.0)
    for k in range(5):  # weld bolts along the slab rim
        p.box(fc + V((-0.95 + k * 0.48, 0.17, -0.8)), (0.12, 0.06, 0.12), "dark", bevel=0.0)
    # Raised cockpit box on top, mismatched grey-brown, red windows
    cp = V((MOD_X - 0.2, 4.6, MOD_Z + 1.25))
    p.box(cp, (1.3, 1.3, 0.6), "scrap", bevel=0.15)
    p.box(cp + V((0, 0.66, 0.05)), (1.0, 0.05, 0.25), "window", bevel=0.0)
    for k in range(4):
        patch(p, V((MOD_X + rng.uniform(-0.6, 0.6), rng.uniform(2.9, 5.0), MOD_Z + MOD_R + 0.02)),
              (rng.uniform(0.5, 0.9), rng.uniform(0.5, 0.9), 0.06), rng,
              mat="rust" if k % 2 else "scrap")
    for sx in (-1, 1):
        patch(p, V((MOD_X + sx * (MOD_R + 0.02), rng.uniform(3.2, 4.8), MOD_Z)),
              (0.06, rng.uniform(0.8, 1.2), rng.uniform(0.6, 0.9)), rng)
    parts.rcs_quad(p, V((MOD_X - MOD_R * 0.75, 5.0, MOD_Z + MOD_R * 0.7)), (-1, 0, 1), "rust",
                   "dark", s=0.26)
    parts.rcs_quad(p, V((MOD_X + MOD_R * 0.75, 5.0, MOD_Z - MOD_R * 0.7)), (1, 0, -1), "olive",
                   "dark", s=0.3)
    # --- Exposed spine truss, some braces missing
    parts.box_truss(p, SPINE_Y0, SPINE_Y1, 0.85, 0.85, 4, "rust", "dark", chord=0.22, brace=0.12,
                    x0=SPINE_X, sides=(False, True, True, False))
    # --- Welded-on cargo container on the starboard side
    p.box(CONT_POS, CONT_SIZE, "paint", r=rot(rz=0.03), bevel=0.03)
    w, ln, h = CONT_SIZE
    for k in range(9):  # corrugation ribs on the outer side and roof
        y = -ln / 2 + 0.3 + k * (ln - 0.6) / 8
        p.box(CONT_POS + V((w / 2 + 0.02, y, 0)), (0.06, 0.12, h - 0.2), "rust", bevel=0.0)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box(CONT_POS + V((sx * w / 2, sy * ln / 2, 0)), (0.18, 0.18, h + 0.04), "dark",
                  bevel=0.0)
    patch(p, CONT_POS + V((w / 2 + 0.06, 0.8, 0.3)), (0.06, 1.1, 0.8), rng, "olive")
    p.hazard(-w / 2, w / 2, 0.2, -0.02, 0.02,
             matrix=parts.Matrix.Translation((CONT_POS.x, CONT_POS.y + ln / 2 + 0.02,
                                              CONT_POS.z - 0.7)) @ rot(rx=math.pi / 2),
             pitch=0.4, cols=("yellow", "dark"))
    for y in (-2.4, 0.6):  # weld straps tying the container to the truss
        p.beam(V((SPINE_X + 0.85, y, 0.85)), V((CONT_POS.x, y, CONT_POS.z + h / 2 + 0.02)),
               0.14, 0.2, "dark")
    # --- Bare propellant spheres strapped to the port side of the truss
    for c, r in ((V((-1.55, -1.0, 0.1)), 0.95), (V((-1.4, -3.3, -0.1)), 0.8)):
        p.sphere(c, r, "olive" if r > 0.9 else "scrap", segs=12, rings=6)
        p.torus(c, r + 0.01, 0.05, "rust", segs=12, minor_segs=4, matrix=rot(ry=math.pi / 2))
        p.beam(c + V((r * 0.6, 0, 0)), V((SPINE_X - 0.85, c.y, c.z)), 0.16, 0.16, "dark")
    # --- Engine section: thrust plate, salvaged bell slightly too big for the ship
    p.box(V((ENG_X, -4.95, 0)), (2.0, 0.6, 2.0), "rust", r=rot(ry=0.05), bevel=0.08)
    p.cyl(V((ENG_X, -5.45, 0)), 0.85, 0.7, 0.4, "dark", segs=12, axis_rot=ALONG_Y)
    parts.bell(p, NOZZLE_Y, BELL_R, BELL_LEN, "scrap", "dark", x=ENG_X, segs=16)
    patch(p, V((ENG_X + 0.6, -6.1, 0.55)), (0.5, 0.6, 0.05), rng, "rust")
    parts.rcs_quad(p, V((ENG_X + 1.05, -4.9, 0.9)), (1, 0, 1), "olive", "dark", s=0.24)
    # --- Cables, antenna, red running lights
    cable(p, V((MOD_X + 0.5, MOD_Y0 + 0.2, MOD_Z + 0.9)), V((CONT_POS.x - 0.4, 1.2, 1.15)), 0.3)
    cable(p, V((SPINE_X + 0.6, -4.3, 0.85)), V((ENG_X + 0.7, -4.8, 1.0)), 0.25, r=0.09)
    p.cyl(V((MOD_X - 0.7, 3.3, MOD_Z + 1.6)), 0.05, 0.03, 1.4, "dark", segs=4,
          axis_rot=rot(rx=-0.15))
    p.box(V((MOD_X - 0.7, 3.2, MOD_Z + 2.3)), (0.18, 0.18, 0.18), "light", bevel=0.0)
    for pos in (V((CONT_POS.x + w / 2, CONT_POS.y + ln / 2 - 0.2, 1.1)),
                V((MOD_X - MOD_R, 4.0, MOD_Z + 0.5)), V((ENG_X - 1.0, -4.95, 0.9))):
        p.box(pos, (0.2, 0.2, 0.2), "light", bevel=0.0)
    return p


def build_rig(rng):
    """Twin autocannon on a turret ring bolted to the container roof."""
    p = parts.Part("scav_rig", MATS)
    g = GUN
    p.cyl(g + V((0, 0, -0.45)), 0.75, 0.8, 0.25, "dark", segs=12)
    p.box(g + V((0, -0.1, -0.05)), (1.1, 1.5, 0.6), "rust", bevel=0.12)
    p.box(g + V((0.75, -0.3, -0.05)), (0.4, 0.9, 0.5), "olive", bevel=0.08)  # ammo box
    p.box(g + V((-0.2, -0.4, 0.3)), (0.5, 0.6, 0.12), "scrap", bevel=0.0)
    y0 = g.y + 0.65
    for sx in (-1, 1):
        x = g.x + sx * BARREL_DX
        p.cyl(V((x, y0 + 0.9, g.z)), 0.2, 0.2, 1.8, "olive", segs=8, axis_rot=ALONG_Y)
        for k in range(4):  # cooling jacket rings
            p.cyl(V((x, y0 + 0.25 + k * 0.45, g.z)), 0.23, 0.23, 0.1, "dark", segs=8,
                  axis_rot=ALONG_Y)
        p.cyl(V((x, (y0 + MUZZLE_Y) / 2, g.z)), 0.12, 0.12, MUZZLE_Y - y0, "dark", segs=8,
              axis_rot=ALONG_Y)
        p.cyl(V((x, MUZZLE_Y - 0.2, g.z)), 0.17, 0.17, 0.4, "scrap", segs=6, axis_rot=ALONG_Y)
    p.box(V((g.x, y0 + 3.2, g.z)), (0.75, 0.2, 0.3), "dark", bevel=0.0)  # barrel clamp
    cable(p, g + V((0.75, -0.6, 0.2)), g + V((0.2, 0.6, 0.2)), 0.15, r=0.05)
    return p


def build_glow(rng):
    p = parts.Part("engine_glow", MATS)
    # Built around the bell exit plane at y = 0; the object origin is moved to NOZZLE_Y.
    parts.exhaust_glow(p, BELL_R * 0.85, 1.0, "glow", segs=16)
    return p


def build_ship():
    rng = random.Random(6613)
    build_materials()
    root = parts.make_root("scavenger")
    objs = [b(rng).finish(root) for b in (build_hull, build_rig, build_glow)]
    objs[-1].location = (ENG_X, NOZZLE_Y, 0)
    for name, sx in (("muzzle_l", -1), ("muzzle_r", 1)):
        parts.add_empty(name, root, (GUN.x + sx * BARREL_DX, MUZZLE_Y + 0.03, GUN.z))
    return root, objs


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_ship()
    parts.print_stats(objs)
    parts.save_blend(os.path.join(common.ROOT, "blender", "scavenger.blend"))
    common.export_glb(root, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews("scavenger", 16.0, target=(0, -0.2, 0))


if __name__ == "__main__":
    main()
