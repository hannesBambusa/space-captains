"""Generate the 12 asteroid .glb files and a row preview.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_asteroids.py
  Add `-- --no-preview` to skip the PNG render.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector, Matrix, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

OUT_DIR = os.path.join(common.ROOT, "assets", "models", "asteroids")

# kind, index, seed
ASTEROIDS = (
    [("rock", i, 100 + i * 17) for i in range(1, 6)]
    + [("iron", i, 300 + i * 23) for i in range(1, 3)]
    + [("titanium", i, 500 + i * 29) for i in range(1, 3)]
    + [("crystal", i, 700 + i * 31) for i in range(1, 3)]
)

# Rock base tints (linear). Kept fairly mid so the RTS camera reads form, not murk.
ROCK_TINTS = {
    "rock": [(0.17, 0.15, 0.125), (0.15, 0.145, 0.14), (0.19, 0.155, 0.12),
             (0.13, 0.125, 0.12), (0.18, 0.165, 0.145)],
    "iron": [(0.15, 0.12, 0.10), (0.14, 0.115, 0.10)],
    "titanium": [(0.13, 0.135, 0.15), (0.115, 0.12, 0.135)],
    "crystal": [(0.075, 0.07, 0.085), (0.07, 0.072, 0.08)],
}


def materials_for(kind, idx):
    tint = ROCK_TINTS[kind][idx - 1]
    mats = []
    base_name = {"rock": "asteroid_rock", "iron": "asteroid_iron_rock",
                 "titanium": "asteroid_titanium_rock", "crystal": "asteroid_crystal_rock"}[kind]
    mats.append(common.make_material(f"{base_name}_{idx:02d}", tint, roughness=0.92,
                                     metallic=0.0, use_vertex_color=True))
    if kind == "iron":
        mats.append(common.make_material("asteroid_iron_ore", (0.62, 0.26, 0.08),
                                         roughness=0.45, metallic=0.75, use_vertex_color=True))
    elif kind == "titanium":
        mats.append(common.make_material("asteroid_titanium_ore", (0.70, 0.80, 0.92),
                                         roughness=0.35, metallic=0.65, use_vertex_color=True))
    elif kind == "crystal":
        col = (0.15, 0.85, 1.0) if idx == 1 else (0.6, 0.25, 1.0)
        mats.append(common.make_material(f"asteroid_crystal_glow_{idx:02d}", tuple(c * 0.6 for c in col),
                                         roughness=0.15, metallic=0.0, emission=col,
                                         emission_strength=3.0))
    return mats


def rock_shape(bm, rng, kind):
    """Displace an icosphere into a lumpy rock with craters. Returns per-vert noise for vcol."""
    seed_off = Vector((rng.uniform(-100, 100), rng.uniform(-100, 100), rng.uniform(-100, 100)))
    # Elongation, varied per rock
    sx = rng.uniform(1.0, 1.55)
    sy = rng.uniform(0.75, 1.1)
    sz = rng.uniform(0.6, 0.95)
    if kind == "crystal":
        sx, sy, sz = rng.uniform(0.95, 1.2), rng.uniform(0.85, 1.05), rng.uniform(0.7, 0.9)
    # Craters: (direction, angular radius, depth)
    craters = []
    for _ in range(rng.randint(3, 6)):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        craters.append((d, rng.uniform(0.25, 0.5), rng.uniform(0.14, 0.26)))

    # Planar chips: clamp the surface against a few planes for chunky flat facets.
    chips = []
    for _ in range(rng.randint(2, 4)):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        chips.append((d, rng.uniform(0.72, 0.88)))

    for v in bm.verts:
        n = v.co.normalized()
        p = n * 1.3 + seed_off
        # Big lumps + medium bumps; small detail is wasted at RTS distance.
        r = 1.0
        r += 0.34 * noise.noise(p * 0.9, noise_basis="PERLIN_ORIGINAL")
        r += 0.12 * noise.noise(p * 2.1 + Vector((7, 3, 1)), noise_basis="PERLIN_ORIGINAL")
        r += 0.04 * noise.noise(p * 4.5, noise_basis="PERLIN_ORIGINAL")
        # A couple of flat-ish facets / chips give it a chunky stylized look
        for d, ang, depth in craters:
            a = n.angle(d)
            if a < ang * 1.4:
                t = a / ang
                if t < 1.0:
                    r -= depth * (1.0 - t * t)          # bowl
                else:
                    r += depth * 0.5 * math.sin((t - 1.0) / 0.4 * math.pi)  # rim
        for d, off in chips:
            dn = n.dot(d)
            if dn > 0.05 and r * dn > off:
                r = off / dn
        v.co = Vector((n.x * r * sx, n.y * r * sy, n.z * r * sz))

    # Normalize mean radius to ~1 m
    mean = sum(v.co.length for v in bm.verts) / len(bm.verts)
    for v in bm.verts:
        v.co /= mean


def add_shard(bm, base, direction, length, radius, rng, mat_index):
    """Faceted hexagonal crystal: prism body + pointed tip. ~24 tris."""
    sides = 6 if rng.random() < 0.6 else 5
    rot = direction.to_track_quat("Z", "Y").to_matrix()
    twist = rng.uniform(0, math.pi)
    body = length * rng.uniform(0.55, 0.7)
    ring_b, ring_t = [], []
    for i in range(sides):
        a = twist + i * 2 * math.pi / sides
        off = Vector((math.cos(a) * radius, math.sin(a) * radius, 0))
        ring_b.append(bm.verts.new(base + rot @ (off * 0.85 - Vector((0, 0, length * 0.25)))))
        ring_t.append(bm.verts.new(base + rot @ (off + Vector((0, 0, body)))))
    tip = bm.verts.new(base + rot @ Vector((rng.uniform(-0.2, 0.2) * radius,
                                             rng.uniform(-0.2, 0.2) * radius, length)))
    faces = []
    for i in range(sides):
        j = (i + 1) % sides
        faces.append(bm.faces.new((ring_b[i], ring_b[j], ring_t[j], ring_t[i])))
        faces.append(bm.faces.new((ring_t[i], ring_t[j], tip)))
    faces.append(bm.faces.new(list(reversed(ring_b))))
    for f in faces:
        f.material_index = mat_index
        f.smooth = False


def build_asteroid(kind, idx, seed):
    rng = random.Random(seed)
    noise.seed_set(seed)
    name = f"asteroid_{kind}_{idx:02d}"
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for m in materials_for(kind, idx):
        mesh.materials.append(m)

    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=4, radius=1.0)
    rock_shape(bm, rng, kind)
    bm.normal_update()

    # Ore patches: material 1 on faces where a ridged noise field is high.
    ore_off = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))
    if kind in ("iron", "titanium"):
        for f in bm.faces:
            c = f.calc_center_median().normalized() * 1.6 + ore_off
            if kind == "iron":
                # Veins: thin bands where |noise| ~ 0
                val = 1.0 - abs(noise.noise(c, noise_basis="PERLIN_ORIGINAL"))
                hit = val > 0.86
            else:
                # Blobby patches
                val = noise.noise(c * 0.9, noise_basis="PERLIN_ORIGINAL")
                hit = val > 0.28
            if hit:
                f.material_index = 1

    for f in bm.faces:
        f.smooth = True
    # Crystal clusters
    if kind == "crystal":
        # Decimate the rock so rock + shards stays under 1500 tris
        bm.to_mesh(mesh)
        bm.free()
        mod = obj.modifiers.new("dec", "DECIMATE")
        mod.ratio = 0.6
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bm.normal_update()
        n_clusters = 4 if idx == 1 else 5
        cluster_dirs = []
        for _ in range(n_clusters):
            d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), abs(rng.gauss(0, 1)) + 0.3)).normalized()
            cluster_dirs.append(d)
        bvh_src = [(v.co.copy(), v.normal.copy()) for v in bm.verts]
        for ci, d in enumerate(cluster_dirs):
            # Snap cluster center to the nearest surface vertex in that direction
            co, nrm = max(bvh_src, key=lambda cv: cv[0].normalized().dot(d))
            n_shards = rng.randint(4, 6)
            big = 1.0 if ci == 0 else rng.uniform(0.55, 0.85)
            for s in range(n_shards):
                spread = Vector((rng.gauss(0, 0.35), rng.gauss(0, 0.35), rng.gauss(0, 0.35)))
                sd = (nrm + spread).normalized()
                tang = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).cross(nrm)
                if tang.length > 0:
                    tang.normalize()
                base = co + tang * rng.uniform(0.0, 0.18) - nrm * 0.05
                length = big * (rng.uniform(0.85, 1.25) if s == 0 else rng.uniform(0.4, 0.8))
                add_shard(bm, base, sd, length, length * rng.uniform(0.15, 0.22), rng, 1)

    bm.to_mesh(mesh)
    bm.free()
    # Lightly smoothed: smooth shading, hard edges above 35 degrees (chips, shards).
    mesh.set_sharp_from_angle(angle=math.radians(35))

    # Vertex color: near-1 multiplier, darker in crevices (low radius), dusty variation.
    col = mesh.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            v = mesh.vertices[mesh.loops[li].vertex_index].co
            if poly.material_index == 1 and kind == "crystal":
                k = 1.0
                c = (k, k, k)
            else:
                rad = v.length
                cav = max(0.0, min(1.0, (rad - 0.7) / 0.5))
                var = noise.noise(v * 2.3 + Vector((11, 5, 2)), noise_basis="PERLIN_ORIGINAL")
                k = 0.78 + 0.22 * cav + 0.07 * var
                warm = 0.04 * noise.noise(v * 1.2 + Vector((3, 9, 1)))
                c = (min(1, k + warm), min(1, k), min(1, k - warm))
            col.data[li].color = (*c, 1.0)
    mesh.color_attributes.active_color = col
    return obj


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    do_preview = "--no-preview" not in argv

    built = []
    for kind, idx, seed in ASTEROIDS:
        common.reset_scene()
        obj = build_asteroid(kind, idx, seed)
        common.export_glb(obj, os.path.join(OUT_DIR, f"{obj.name}.glb"))
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        print(f"STAT {obj.name} tris={tris} mats={[m.name for m in obj.data.materials]}")
        built.append((kind, idx, seed))

    if do_preview:
        common.reset_scene()
        objs = []
        for i, (kind, idx, seed) in enumerate(built):
            o = build_asteroid(kind, idx, seed)
            row, colm = divmod(i, 6)
            o.location = ((colm - 2.5) * 2.8, -row * 3.6, 0)
            objs.append(o)
        common.setup_preview(cam_loc=(0, -12, 12), cam_target=(0, -1.8, 0), ortho_scale=17.5,
                             res=(1800, 1000), key_dir=(-0.8, 0.25, 0.5), key_energy=3.5)
        common.render(os.path.join(common.PREVIEW_DIR, "asteroids_preview.png"))


main()
