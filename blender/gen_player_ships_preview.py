"""Small top-down lineup of the player ships (merc, miner, salvager) to judge the
silhouettes at RTS size. Run after the three ship generators:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python /Users/hannesalm/code/games/space-majesty/blender/gen_player_ships_preview.py
Writes blender/previews/player_ships_small.png (top-down, ~200 px tall) and
player_ships_small_tilted.png (RTS-like tilted view).
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

SHIPS = (("merc_fighter", -13.0), ("miner", 0.0), ("salvager", 13.0))


def main():
    common.reset_scene()
    for name, x in SHIPS:
        path = os.path.join(common.ROOT, "assets", "models", "ships", name + ".glb")
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        roots = [o for o in set(bpy.data.objects) - before if o.parent is None]
        for r in roots:
            r.location.x += x
    common.setup_preview(cam_loc=(0, 0, 60), cam_target=(0, 0, 0), ortho_scale=40,
                         res=(400, 200), key_dir=(-0.5, 0.4, 0.75), key_energy=3.5)
    cam = bpy.context.scene.camera
    cam.rotation_euler = (0, 0, 0)
    common.render(os.path.join(common.PREVIEW_DIR, "player_ships_small.png"))
    cam.location = (0, -45, 55)
    cam.rotation_euler = (math.radians(40), 0, 0)
    common.render(os.path.join(common.PREVIEW_DIR, "player_ships_small_tilted.png"))


main()
