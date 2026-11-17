"""Fleet lineup previews: every ship side by side at true relative scale.
Run after the ship generators:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_fleet_lineup.py
Writes blender/previews/fleet_lineup.png (3/4 view) and fleet_lineup_top.png (top-down).
"""
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

SHIPS = (("colony_ship", -40.0), ("syndicate_gunship", -27.0), ("explorer", -17.0),
         ("miner_hauler", -8.0), ("salvager", 1.0), ("merc_interceptor", 10.5),
         ("corsair_raider", 19.0), ("scavenger", 27.0), ("cargo_shuttle", 35.0),
         ("dropship", 43.0), ("escape_pod", 49.0))


def main():
    common.reset_scene()
    for name, x in SHIPS:
        path = os.path.join(common.ROOT, "assets", "models", "ships", name + ".glb")
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        for r in [o for o in set(bpy.data.objects) - before if o.parent is None]:
            r.location.x += x
    common.setup_preview(cam_loc=(-55, -75, 85), cam_target=(4, 0, 0), ortho_scale=100,
                         res=(2400, 1100), key_dir=(-0.5, -0.4, 0.75), key_energy=3.5)
    common.render(os.path.join(common.PREVIEW_DIR, "fleet_lineup.png"))
    scene = bpy.context.scene
    cam = scene.camera
    cam.location = (4.5, 0, 200)
    cam.rotation_euler = (0, 0, 0)
    cam.data.ortho_scale = 100
    scene.render.resolution_x, scene.render.resolution_y = 2400, 1000
    common.render(os.path.join(common.PREVIEW_DIR, "fleet_lineup_top.png"))


main()
