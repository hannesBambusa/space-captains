"""Generate the miner hauler .glb from the bought ring-ship model.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_miner_hauler.py
  Add `-- --no-preview` to skip the PNG renders.

Source: assets/models/new/spaceship/spaceship.obj (Blender 3.3 export, 740k tris,
143 pieces, untextured). A long panelled hull with a big wheel ring, side pods and a
socket at the bow (the drill beam fires out of the socket), and a drum section with a
spike at the stern (two round sockets beside the spike carry the engine glow).
The model is decimated piece by piece (DECIMATE), joined, turned nose along Blender
+Y, scaled to LENGTH and centred. Its six source materials are replaced by miner
colours (white/grey hull, orange work markings, lit windows).

Layout (Blender Z up, exported +Y up). Ship centre at origin on the play plane z=0.
The nose points along Blender +Y, which the exporter turns into Godot -Z (forward).
Hierarchy: miner_hauler (empty root) -> miner_hauler_hull, engine_glow, drill_point.
engine_glow has its origin on the nozzle exit plane (Blender y = NOZZLE_Y) and its
plumes extend along Godot local +Z, so scaling it on Z lengthens them.
drill_point (empty, unrotated) sits in the mouth of the bow socket; MinerShip fires
the drill beam from it (nose_offset is the fallback for models without one).
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bmesh  # noqa: E402
import common  # noqa: E402
import import_ship  # noqa: E402
import parts  # noqa: E402

SRC = os.path.join(common.ROOT, "assets", "models", "new", "spaceship", "spaceship.obj")
OUT = os.path.join(common.ROOT, "assets", "models", "ships", "miner_hauler.glb")
YAW = 0.0         # source ring end sits at +Y: it is the bow, the spike the stern
LENGTH = 15.2     # metres, bow at y = 7.6 = MinerShip.nose_offset
# Collapse per source piece kind (name without the .NNN suffix): a float is a ratio,
# an int a triangle budget per piece. The 46 Roundcubes are subdivided blocks holding
# 1.33M of the 1.48M source triangles. About 33k in all, a few times the hand-built
# ships; the panelled hull pieces (Spaceship_main_shape) are cut the least.
DECIMATE = {
    "Roundcube": 160,
    "Plane": 0.25,
    "Spaceship_main_shape": 0.6,
    "Circle": 0.2,
    "Torus": 0.15,
    "Spaceship_engines_side_addons_circular": 0.3,
    "Spaceship_engines_side": 0.35,
    "Spaceship_engines_side_addonside": 0.2,
    "Cube": 0.4,
}
# Nozzles (x, z, exit y, exit radius) in the fitted frame, read off a stern render: the
# two round sockets beside the spike (rim at y = -5.56).
NOZZLES = ((-0.6, -0.9, -5.56, 0.3), (0.6, -0.9, -5.56, 0.3))
NOZZLE_Y = -5.56  # engine_glow origin
# Bow socket: centre (x, z) and mouth y. Rim r 0.2..0.5 reaches y = 7.6, floor ~6.1.
DRILL = (0.0, 7.5, -0.28)

MATS = {}


def build_materials():
    m = common.make_material
    MATS["hull"] = m("miner_hauler_hull", (0.72, 0.72, 0.7), roughness=0.55, metallic=0.3)
    MATS["plate"] = m("miner_hauler_plate", (0.33, 0.35, 0.38), roughness=0.5, metallic=0.45)
    MATS["marking"] = m("miner_hauler_marking", (0.95, 0.45, 0.08), roughness=0.6, metallic=0.1)
    MATS["dark"] = m("miner_hauler_dark", (0.1, 0.11, 0.12), roughness=0.45, metallic=0.6)
    MATS["glass"] = m("miner_hauler_glass", (0.2, 0.35, 0.45), roughness=0.15, metallic=0.2,
                      emission=(1.0, 0.8, 0.5), emission_strength=0.4)
    MATS["glow"] = m("miner_hauler_glow", (0.8, 0.95, 1.0), roughness=0.2,
                     emission=(0.6, 0.85, 1.0), emission_strength=6.0)


# Source material name prefix -> MATS key. Longer names first (prefix match).
SOURCE_MATS = (
    ("Main_deck.001", "plate"),
    ("Main_deck", "hull"),
    ("ENGINE_FLAME.001", "marking"),
    ("ENGINE_FLAME", "dark"),
    ("Glass_material", "glass"),
)


def build_glow():
    p = parts.Part("engine_glow", MATS)
    for x, z, y, r in NOZZLES:
        first = len(p.bm.verts)
        parts.exhaust_glow(p, r, 1.3, "glow", x=x, z=z, segs=12)
        p.bm.verts.ensure_lookup_table()
        bmesh.ops.translate(p.bm, vec=(0, y - NOZZLE_Y, 0), verts=p.bm.verts[first:])
    return p


def piece_ratio(obj, tris):
    rule = DECIMATE.get(re.sub(r"\.\d+$", "", obj.name), 1.0)
    return min(1.0, rule / max(tris, 1)) if isinstance(rule, int) else rule


def build_ship():
    build_materials()
    root = parts.make_root("miner_hauler")
    pieces = import_ship.import_source(SRC)
    print(f"DECIMATED tris={import_ship.decimate_pieces(pieces, piece_ratio)}")
    hull = import_ship.join(pieces, "miner_hauler_hull")
    import_ship.fit(hull, YAW, LENGTH)
    import_ship.set_materials(hull, {k: MATS[v] for k, v in SOURCE_MATS})
    hull.parent = root
    glow = build_glow().finish(root)
    glow.location = (0, NOZZLE_Y, 0)
    objs = [hull, glow]
    parts.add_empty("drill_point", root, DRILL, size=1.0)
    return root, objs


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_ship()
    parts.print_stats(objs)
    parts.save_blend(os.path.join(common.ROOT, "blender", "miner_hauler.blend"))
    common.export_glb(root, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews("miner_hauler", 17.0)


main()
