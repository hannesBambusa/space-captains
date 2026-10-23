"""Render the faction scale/contrast shot: merc fighter, miner and scavenger side by side.

Run (after gen_merc_ship.py, gen_miner_ship.py and gen_scavenger_ship.py):
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python /Users/hannesalm/code/games/space-majesty/blender/gen_factions_preview.py
Preview only: imports the exported .glb files, writes
blender/previews/factions_scale_preview.png, exports nothing.
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

SHIPS = os.path.join(common.ROOT, "assets", "models", "ships")
LINEUP = (("merc_fighter", -21.0), ("miner", 0.0), ("scavenger", 20.0))


def main():
    common.reset_scene()
    for name, x in LINEUP:
        path = os.path.join(SHIPS, f"{name}.glb")
        if not os.path.exists(path):
            print("missing", path)
            sys.exit(1)
        bpy.ops.import_scene.gltf(filepath=path)
        root = bpy.data.objects[name]
        # Line up across the view (perpendicular to the camera's ground direction)
        root.location = (x * 0.844, -x * 0.537, 0)
        root.rotation_euler = (0, 0, math.radians(-20))
    common.setup_preview(cam_loc=(-35, -55, 60), cam_target=(0, 0, 0), ortho_scale=58,
                         res=(1800, 1000), key_dir=(-0.5, 0.4, 0.75), key_energy=3.5)
    common.render(os.path.join(common.PREVIEW_DIR, "factions_scale_preview.png"))


main()
