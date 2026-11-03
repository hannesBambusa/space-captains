"""Generate the mercenary interceptor .glb from the bought low-poly fighter model.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_merc_interceptor.py
  Add `-- --no-preview` to skip the PNG renders.

Source: assets/models/new/low-poly-sci-fi-spaceship/source/model.gltf (Blockbench,
2.4k tris, 6 embedded pixel textures). Black hull, cyan trim, four rear engines.
The model is joined into one mesh, turned nose along Blender +Y, scaled to LENGTH and
centred; the pixel textures keep their nearest-neighbour sampling.

Layout (Blender Z up, exported +Y up). Ship centre at origin on the play plane z=0.
The nose points along Blender +Y, which the exporter turns into Godot -Z (forward).
Hierarchy: merc_interceptor (empty root) -> merc_interceptor_hull, engine_glow,
  muzzle_l (empty), muzzle_r (empty).
engine_glow has its origin on the nozzle exit plane (Blender y = NOZZLE_Y) and
its four plumes extend along Godot local +Z, so scaling it on Z lengthens them.
Muzzle empties sit on the gun rail tips, unrotated, so their Godot -Z points forward.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import import_ship  # noqa: E402
import parts  # noqa: E402

SRC = os.path.join(common.ROOT, "assets", "models", "new", "low-poly-sci-fi-spaceship",
                   "source", "model.gltf")
OUT = os.path.join(common.ROOT, "assets", "models", "ships", "merc_interceptor.glb")
YAW = 0.0        # degrees about Z that turn the source nose onto +Y
LENGTH = 15.0    # metres, like merc_fighter
# Nozzle centres (x, z) in the fitted frame and the exit radius, read off a rear render.
# The outer pair exits at y = -7.5, the inner pair at -7.12; the glow sits between.
NOZZLES = ((-3.22, 0.15), (-1.72, 0.15), (1.72, 0.15), (3.22, 0.15))
NOZZLE_R = 0.45
NOZZLE_Y = -7.3
# Tips of the two forward gun rails (x = +-1.23..1.8, y = 5.03, z = -0.09..0.19).
MUZZLE_X = 1.5
MUZZLE_Y = 5.08
MUZZLE_Z = 0.05

MATS = {}


def build_glow():
    MATS["glow"] = common.make_material("merc_interceptor_glow", (0.55, 0.95, 1.0), roughness=0.2,
                                        emission=(0.45, 0.9, 1.0), emission_strength=6.0)
    p = parts.Part("engine_glow", MATS)
    for x, z in NOZZLES:
        parts.exhaust_glow(p, NOZZLE_R, 1.4, "glow", x=x, z=z, segs=12)
    return p


def build_ship():
    root = parts.make_root("merc_interceptor")
    hull = import_ship.join(import_ship.import_source(SRC), "merc_interceptor_hull")
    import_ship.fit(hull, YAW, LENGTH)
    import_ship.merge_close(hull, 0.0005)
    hull.parent = root
    glow = build_glow().finish(root)
    glow.location = (0, NOZZLE_Y, 0)
    for name, sx in (("muzzle_l", -1), ("muzzle_r", 1)):
        parts.add_empty(name, root, (sx * MUZZLE_X, MUZZLE_Y, MUZZLE_Z), size=1.0)
    return root, [hull, glow]


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_ship()
    parts.print_stats(objs)
    parts.save_blend(os.path.join(common.ROOT, "blender", "merc_interceptor.blend"))
    common.export_glb(root, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews("merc_interceptor", 17.0)


main()
