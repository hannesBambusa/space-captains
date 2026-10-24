"""Fleet lineup previews: all five ships side by side at true relative scale.
Run after the ship generators:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_fleet_lineup.py
Writes blender/previews/fleet_lineup.png (3/4 view) and fleet_lineup_top.png
(small top-down, about 100 px per ship).
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

SHIPS = (("merc_fighter", -16.0), ("scavenger", -8.0), ("miner", 0.0), ("salvager", 8.0),
         ("escape_pod", 14.5))


def main():
    common.reset_scene()
    for name, x in SHIPS:
        path = os.path.join(common.ROOT, "assets", "models", "ships", name + ".glb")
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        for r in [o for o in set(bpy.data.objects) - before if o.parent is None]:
            r.location.x += x
    common.setup_preview(cam_loc=(-27, 28, 30), cam_target=(1.5, -2.5, 0), ortho_scale=44,
                         res=(1800, 1000), key_dir=(-0.5, 0.4, 0.75), key_energy=3.5)
    common.render(os.path.join(common.PREVIEW_DIR, "fleet_lineup.png"))
    scene = bpy.context.scene
    cam = scene.camera
    cam.location = (-0.75, 0, 60)
    cam.rotation_euler = (0, 0, 0)
    cam.data.ortho_scale = 40
    scene.render.resolution_x, scene.render.resolution_y = 500, 220
    common.render(os.path.join(common.PREVIEW_DIR, "fleet_lineup_top.png"))


main()
