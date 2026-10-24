"""Generate the corsair raider .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_corsair_ship.py
  Add `-- --no-preview` to skip the PNG renders.

Design: fast hit-and-run raider. A long, narrow faceted dagger hull in near-black
graphite with crimson accent panels, a slim canopy, two swept-back blade wings with
crimson leading edges, a dorsal fin, twin engine nacelles with bright crimson-white
glows, and twin cannons on pylons along the nose (muzzle_l / muzzle_r at the tips).
Lightly armoured: thin plates, no bolted-on mass. About 13 m long, 5 m span, so
slightly smaller and much slimmer than the scavenger. Arrowhead silhouette from above.

Layout (Blender Z up, exported +Y up). Ship centre at origin on the play plane z=0.
The nose points along Blender +Y, which the exporter turns into Godot -Z (forward).
Hierarchy: corsair_raider (empty root) -> corsair_hull, engine_glow,
  muzzle_l (empty), muzzle_r (empty).
engine_glow has its origin on the nozzle exit plane (Blender y = NOZZLE_Y * SCALE) and
both plumes extend along Godot local +Z, so scaling it on Z lengthens the glow backwards.
Muzzle empties are unrotated, so their Godot -Z points forward along the barrels.
Same node contract as scavenger.glb (gen_scavenger_ship.py).
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
from mathutils import Matrix  # noqa: E402
from parts import ALONG_Y, SIDE, V, rot  # noqa: E402

OUT = os.path.join(common.ROOT, "assets", "models", "ships", "corsair_raider.glb")
NAC_X = 0.62
NOZZLE_Y = -6.35
BELL_R = 0.42
GUN_X, GUN_Z = 0.78, -0.18
MUZZLE_Y = 6.55
SCALE = 0.9   # whole ship scaled down at the end; the constants above are pre-scale

MATS = {}


def build_materials():
    m = common.make_material
    MATS["hull"] = m("corsair_hull_graphite", (0.055, 0.055, 0.065), roughness=0.4, metallic=0.7)
    MATS["plate"] = m("corsair_plate_black", (0.028, 0.026, 0.032), roughness=0.5, metallic=0.6)
    MATS["crimson"] = m("corsair_paint_crimson", (0.42, 0.012, 0.03), roughness=0.45,
                        metallic=0.3)
    MATS["dark"] = m("corsair_frame_dark", (0.018, 0.017, 0.02), roughness=0.6, metallic=0.6)
    MATS["metal"] = m("corsair_bare_metal", (0.2, 0.19, 0.2), roughness=0.35, metallic=0.9)
    MATS["window"] = m("corsair_canopy_red", (1.0, 0.12, 0.16), roughness=0.2,
                       emission=(1.0, 0.07, 0.12), emission_strength=3.5)
    MATS["light"] = m("corsair_light_crimson", (1.0, 0.05, 0.1), roughness=0.3,
                      emission=(1.0, 0.03, 0.08), emission_strength=5.0)
    MATS["glow"] = m("corsair_engine_glow", (1.0, 0.45, 0.55), roughness=0.2,
                     emission=(1.0, 0.25, 0.35), emission_strength=7.0)


def hull_ring(y, w, top, bot, z0=0.0):
    """Faceted hexagonal cross-section: ridge on top, keel below."""
    pts = [(0.0, top), (w * 0.62, top * 0.55), (w, 0.0), (w * 0.55, -bot), (-w * 0.55, -bot),
           (-w, 0.0), (-w * 0.62, top * 0.55)]
    return [V((x, y, z0 + z)) for x, z in pts]


# (y, half width, top, bottom): needle nose to the engine block
STATIONS = [(6.7, 0.04, 0.04, 0.03), (5.4, 0.36, 0.3, 0.2), (3.6, 0.66, 0.52, 0.34),
            (1.6, 0.88, 0.68, 0.42), (-0.8, 1.0, 0.74, 0.46), (-3.4, 0.98, 0.66, 0.46),
            (-5.1, 0.84, 0.56, 0.42)]


def build_hull(rng):
    p = parts.Part("corsair_hull", MATS)
    rings = [hull_ring(*s) for s in STATIONS]
    # top facets crimson on the forward half (edges j 0 and 6 = the two upper planes)
    p.loft(rings, "hull", mat_fn=lambda i, j: "crimson" if (j in (0, 6) and 1 <= i <= 2)
           else ("plate" if j in (3,) else "hull"))
    # Canopy: low faceted blister, glowing crimson slit
    can = [hull_ring(4.4, 0.05, 0.05, 0.0, 0.42), hull_ring(3.3, 0.34, 0.3, 0.0, 0.5),
           hull_ring(1.7, 0.4, 0.32, 0.0, 0.6), hull_ring(0.9, 0.2, 0.12, 0.0, 0.68)]
    p.loft(can, "plate")
    p.box(V((0, 2.7, 0.92)), (0.42, 1.2, 0.05), "window", r=rot(rx=0.12), bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 0.3, 2.3, 0.82)), (0.06, 1.0, 0.12), "window", r=rot(rx=0.12, ry=sx * 0.5),
              bevel=0.0)
    # Spine stripe and armour seams
    p.box(V((0, -2.2, 0.73)), (0.16, 4.8, 0.05), "crimson", bevel=0.0)
    for y in (-0.2, -2.0, -3.8):
        p.box(V((0, y, 0.68)), (1.3, 0.06, 0.06), "dark", bevel=0.0)
    # Swept blade wings, crimson leading edge and tip
    for sx in (-1, 1):
        pts = [(0.8, 0.2), (2.45, -4.6), (2.5, -5.7), (0.8, -4.3)]
        pts = [(sx * x, y) for x, y in pts]
        if sx < 0:
            pts.reverse()
        p.slab(pts, -0.08, 0.08, "hull")
        # leading edge strip
        a, b = V((sx * 0.85, 0.05, 0.0)), V((sx * 2.45, -4.55, 0.0))
        p.beam(a, b, 0.22, 0.2, "crimson")
        p.box(V((sx * 2.5, -5.15, 0.0)), (0.14, 1.2, 0.3), "crimson", bevel=0.0)
        p.box(V((sx * 1.6, -3.4, 0.1)), (0.5, 1.1, 0.04), "plate", r=rot(rz=sx * 0.35),
              bevel=0.0)
        # wingtip running light
        p.box(V((sx * 2.52, -4.5, 0.0)), (0.18, 0.18, 0.18), "light", bevel=0.0)
        # ventral strake under each wing root
        p.slab([(1.8, -0.3), (-3.6, -0.3), (-4.4, -0.75), (-3.0, -0.75)], sx * 0.62 - 0.04,
               sx * 0.62 + 0.04, "plate", matrix=SIDE)
    # Dorsal fin (side profile: local x = world y, local y = world z)
    p.slab([(-1.6, 0.7), (-4.9, 0.55), (-5.6, 1.85), (-4.6, 1.9)], -0.06, 0.06, "plate",
           matrix=SIDE)
    p.slab([(-4.7, 1.55), (-5.5, 1.5), (-5.6, 1.88), (-4.62, 1.92)], -0.08, 0.08, "crimson",
           matrix=SIDE)
    p.box(V((0, -5.15, 1.98)), (0.16, 0.3, 0.16), "light", bevel=0.0)
    # Engine nacelles: slim cans, crimson rings, short bells
    for sx in (-1, 1):
        x = sx * NAC_X
        p.cyl(V((x, -4.4, -0.02)), 0.5, 0.5, 2.6, "hull", segs=12, axis_rot=ALONG_Y)
        p.cyl(V((x, -3.0, -0.02)), 0.44, 0.5, 0.3, "dark", segs=12, axis_rot=ALONG_Y)
        p.cyl(V((x, -5.0, -0.02)), 0.53, 0.53, 0.22, "crimson", segs=12, axis_rot=ALONG_Y)
        p.cyl(V((x, -5.75, -0.02)), 0.47, 0.5, 0.2, "dark", segs=12, axis_rot=ALONG_Y)
        parts.bell(p, NOZZLE_Y, BELL_R, 0.55, "metal", "dark", x=x, z=-0.02, segs=14,
                   throat=0.6)
    # Twin nose cannons on pylons, muzzle brakes at the tips
    for sx in (-1, 1):
        x = sx * GUN_X
        p.beam(V((sx * 0.45, 2.2, -0.15)), V((x, 2.2, GUN_Z)), 0.6, 0.12, "plate")
        p.cyl(V((x, 1.6, GUN_Z)), 0.16, 0.16, 2.2, "plate", segs=8, axis_rot=ALONG_Y)
        p.cyl(V((x, (2.7 + MUZZLE_Y) / 2, GUN_Z)), 0.08, 0.08, MUZZLE_Y - 2.7, "dark", segs=8,
              axis_rot=ALONG_Y)
        p.cyl(V((x, MUZZLE_Y - 0.15, GUN_Z)), 0.12, 0.12, 0.3, "metal", segs=6,
              axis_rot=ALONG_Y)
        p.cyl(V((x, 2.85, GUN_Z)), 0.19, 0.19, 0.14, "crimson", segs=8, axis_rot=ALONG_Y)
    # Nose light and side lights
    p.box(V((0, 6.0, 0.08)), (0.12, 0.3, 0.12), "light", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 1.0, -1.2, 0.05)), (0.08, 0.5, 0.1), "light", bevel=0.0)
    parts.rcs_quad(p, V((0.0, 4.2, -0.38)), (0, 0, -1), "plate", "dark", s=0.2)
    return p


def build_glow(rng):
    p = parts.Part("engine_glow", MATS)
    # Built around the exit plane at y = 0; the object origin is moved to NOZZLE_Y.
    for sx in (-1, 1):
        parts.exhaust_glow(p, BELL_R * 0.92, 1.7, "glow", x=sx * NAC_X, z=-0.02, segs=14)
    return p


def build_ship():
    rng = random.Random(4471)
    build_materials()
    root = parts.make_root("corsair_raider")
    objs = [b(rng).finish(root) for b in (build_hull, build_glow)]
    objs[-1].location = (0, NOZZLE_Y, 0)
    for name, sx in (("muzzle_l", -1), ("muzzle_r", 1)):
        parts.add_empty(name, root, (sx * GUN_X, MUZZLE_Y + 0.03, GUN_Z))
    # Bake SCALE into mesh data and child positions (no object scale in the export)
    for o in root.children:
        if o.type == "MESH":
            o.data.transform(Matrix.Scale(SCALE, 4))
        o.location = o.location * SCALE
    return root, objs


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_ship()
    parts.print_stats(objs)
    parts.save_blend(os.path.join(common.ROOT, "blender", "corsair_raider.blend"))
    common.export_glb(root, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews("corsair_raider", 15.0, target=(0, 0, 0))


if __name__ == "__main__":
    main()
