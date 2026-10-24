"""Generate the corsair nest .glb and a 45 degree preview.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_corsair_nest.py
  Add `-- --no-preview` to skip the PNG render.

Design: a hidden raider nest. A broken ring of jagged rock shards (~100 x 84 m, same
lumpy style as gen_scavenger_den.py, but a crown of spikes around a hollow instead of
one round rock) on a flat rock floor, open on Blender -Y (= Godot +Z). Camo netting
draped over the rear two thirds of the hollow, with rock plates laid on it. Inside:
docking clamps holding parked raider darts, a crimson-lit landing lane and a bunker
door at the back. The forward half of a big dagger-shaped wreck lies across the port
rim. Crimson running lights on spikes, clamps and the mouth.

Layout (Blender Z up, exported +Y up). Nest centre at origin, play plane z=0.
Hierarchy: corsair_nest (empty root)
  -> den_rock (vertex coloured), den_salvage, den_hangar_glow, den_lights,
     spawn_point (empty).
Node names match scavenger_den.glb so ScavengerDen-style code can swap the path:
den_lights holds only the small crimson lights (material corsair_light_crimson), so
Godot can flicker them as one mesh. den_hangar_glow is the crimson lane / bunker glow
(material nest_hangar_glow), separate so it can pulse. den_salvage is everything that
is not rock (netting, wreck, clamps), hidden on the ruined look.
spawn_point sits on the play plane in the mouth, rotated 180 deg about up, so its
Godot -Z (forward) points out of the opening (Godot world +Z).
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
from parts import ALONG_Y, V, rot  # noqa: E402

OUT = os.path.join(common.ROOT, "assets", "models", "buildings", "corsair_nest.glb")
SEED = 5307
RING_RX, RING_RY = 35.0, 30.0           # shard ring radii (m)
FLOOR_Z = -5.0                          # top of the rock floor inside the hollow
SPAWN_POS = (0.0, -34.0, 0.0)
NET_Y0, NET_Y1 = 11.0, 32.0              # netting covers the rear of the hollow
NET_Z = 12.0
# Shards: (angle deg from +X, tangential, radial, vertical semi-axes, centre z, tilt out)
SHARDS = [(-38, 13, 9, 11, 0.0, 0.35), (2, 15, 10, 13, 1.0, 0.25), (45, 14, 10, 16, 2.0, 0.2),
          (88, 17, 11, 17, 2.0, 0.15), (132, 14, 10, 15, 2.0, 0.22),
          (178, 15, 10, 12, 1.0, 0.28), (-142, 13, 9, 10, 0.0, 0.38)]

MATS = {}


def build_materials():
    m = common.make_material
    MATS["rock"] = m("nest_rock", (0.075, 0.072, 0.085), roughness=0.92, use_vertex_color=True)
    MATS["rock_dark"] = m("nest_rock_dark", (0.045, 0.043, 0.052), roughness=0.95,
                          use_vertex_color=True)
    MATS["hull"] = m("corsair_hull_graphite", (0.055, 0.055, 0.065), roughness=0.4,
                     metallic=0.7)
    MATS["plate"] = m("corsair_plate_black", (0.028, 0.026, 0.032), roughness=0.5,
                      metallic=0.6)
    MATS["crimson"] = m("corsair_paint_crimson", (0.42, 0.012, 0.03), roughness=0.45,
                        metallic=0.3)
    MATS["dark"] = m("corsair_frame_dark", (0.018, 0.017, 0.02), roughness=0.6, metallic=0.6)
    MATS["net"] = m("nest_camo_net", (0.1, 0.11, 0.08), roughness=0.95)
    MATS["net_dark"] = m("nest_camo_net_dark", (0.065, 0.07, 0.055), roughness=0.95)
    MATS["rplate"] = m("nest_rock_plating", (0.09, 0.085, 0.082), roughness=0.9, metallic=0.1)
    MATS["window"] = m("corsair_canopy_red", (1.0, 0.12, 0.16), roughness=0.2,
                       emission=(1.0, 0.07, 0.12), emission_strength=3.5)
    MATS["light"] = m("corsair_light_crimson", (1.0, 0.05, 0.1), roughness=0.3,
                      emission=(1.0, 0.03, 0.08), emission_strength=5.0)
    MATS["glow"] = m("nest_hangar_glow", (1.0, 0.06, 0.12), roughness=0.3,
                     emission=(1.0, 0.04, 0.1), emission_strength=4.5)


# ---------------------------------------------------------------- rock
def shard_centre(ang_deg):
    a = math.radians(ang_deg)
    return V((math.cos(a) * RING_RX, math.sin(a) * RING_RY, 0.0)), a


def add_lump(bm, centre, axes, rotm, rng, sub=4, sharp=0.0):
    """Noisy ellipsoid into bm. sharp > 0 pulls the top into a spike."""
    off = Vector((rng.uniform(-100, 100), rng.uniform(-100, 100), rng.uniform(-100, 100)))
    res = bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    for v in res["verts"]:
        n = v.co.normalized()
        p = n * 1.4 + off
        lump = (0.26 * noise.noise(p * 0.9) + 0.1 * noise.noise(p * 2.3 + Vector((7, 3, 1)))
                + 0.04 * noise.noise(p * 5.0))
        r = 1.0 + lump
        if sharp and n.z > 0:
            r *= 1.0 + sharp * n.z ** 3
        # facet it a little: flatten into planes for a fractured look
        q = Vector((n.x * axes[0], n.y * axes[1], n.z * axes[2])) * r
        v.co = centre + rotm @ q


def build_rock(parent, rng):
    noise.seed_set(SEED)
    bm = bmesh.new()
    # Floor: wide flat slab of rock the shards stand on
    add_lump(bm, V((0, 2.0, -14.0)), (RING_RX + 6, RING_RY + 4, 9.0), Matrix.Identity(3), rng,
             sub=5)
    for ang, t, rr, h, z, tilt in SHARDS:
        c, a = shard_centre(ang)
        c.z = z
        # local x tangential, y radial outward, z up; tilt the top outward
        rz = Matrix.Rotation(a - math.pi / 2, 3, "Z")
        rx = Matrix.Rotation(-tilt, 3, "X")
        add_lump(bm, c, (t, rr, h), rz @ rx, rng, sub=4, sharp=0.4)
    # Small loose boulders around the outside
    for _ in range(9):
        a = rng.uniform(0, 2 * math.pi)
        if abs(math.degrees(a) - 270) < 40:
            continue
        c = V((math.cos(a) * (RING_RX + 9), math.sin(a) * (RING_RY + 8), rng.uniform(-10, 2)))
        s = rng.uniform(3.0, 6.0)
        add_lump(bm, c, (s, s * 0.8, s * 0.7), Matrix.Rotation(a, 3, "Z"), rng, sub=2)
    mesh = bpy.data.meshes.new("den_rock")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(MATS["rock"])
    mesh.materials.append(MATS["rock_dark"])
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f in bm.faces:
        c = f.calc_center_median()
        inner = math.hypot(c.x / RING_RX, c.y / RING_RY) < 0.8 and c.z < 6
        f.material_index = 1 if (inner or f.normal.z < -0.5) else 0
        f.smooth = True
    bvh = BVHTree.FromBMesh(bm)
    bm.to_mesh(mesh)
    bm.free()
    mesh.set_sharp_from_angle(angle=math.radians(35))
    col = mesh.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            co = mesh.vertices[mesh.loops[li].vertex_index].co
            hgt = max(0.0, min(1.0, (co.z + 10.0) / 30.0))
            var = noise.noise(co * 0.06 + Vector((11, 5, 2)))
            k = 0.72 + 0.28 * hgt + 0.08 * var
            cool = 0.03 * noise.noise(co * 0.03 + Vector((3, 9, 1)))
            col.data[li].color = (min(1, k - cool), min(1, k), min(1, k + cool), 1.0)
    mesh.color_attributes.active_color = col
    obj = bpy.data.objects.new("den_rock", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    return obj, bvh


class Surface:
    """Ray queries against the rock, to bolt things onto it."""

    def __init__(self, bvh):
        self.bvh = bvh

    def top(self, x, y, default=0.0):
        hit = self.bvh.ray_cast(Vector((x, y, 200.0)), Vector((0, 0, -1)))
        return hit[0].z if hit[0] is not None else default

    def toward(self, origin, direction):
        hit = self.bvh.ray_cast(Vector(origin), Vector(direction).normalized())
        return hit[0], hit[1]


# ---------------------------------------------------------------- netting
def build_netting(sal, lights, surf, rng):
    """Draped camo net over the rear of the hollow, holes torn in it, rock plates on top."""
    nx, ny = 18, 9
    x0, x1 = -30.0, 30.0
    verts, buried = {}, {}
    bm = sal.bm
    for i in range(nx + 1):
        for j in range(ny + 1):
            u, w = i / nx, j / ny
            x = x0 + (x1 - x0) * u
            y = NET_Y0 + (NET_Y1 - NET_Y0) * w
            sag = 5.0 * math.sin(u * math.pi) * math.sin(min(1.0, w * 1.4) * math.pi * 0.5 + 0.3)
            z = NET_Z + 3.0 * w - sag + 0.8 * noise.noise(V((x * 0.15, y * 0.15, 3.0)))
            rock = surf.top(x, y, default=-50.0)
            verts[i, j] = bm.verts.new(V((x, y, max(z, rock + 0.6))))
            buried[i, j] = rock > z + 1.5   # the net ends where it meets the rock
    for i in range(nx):
        for j in range(ny):
            if all(buried[i + a, j + b] for a in (0, 1) for b in (0, 1)):
                continue
            if rng.random() < 0.12 and 0 < i < nx - 1:
                continue  # torn hole
            f = bm.faces.new((verts[i, j], verts[i + 1, j], verts[i + 1, j + 1], verts[i, j + 1]))
            f.material_index = sal.mi("net_dark" if rng.random() < 0.35 else "net")
    # Front edge rope and poles holding it up
    for i in range(0, nx + 1, 3):
        a = verts[i, 0].co.copy()
        base_z = surf.top(a.x, a.y, default=FLOOR_Z)
        if a.z - base_z > 2.0:
            sal.beam(V((a.x, a.y, base_z)), a, 0.5, 0.5, "dark")
        lights.box(a + V((0, -0.3, 0.4)), (0.6, 0.6, 0.6), "light", bevel=0.0)
    for i in range(nx):
        sal.beam(verts[i, 0].co, verts[i + 1, 0].co, 0.35, 0.35, "dark")
    # Rock plates laid on the net: from above it reads as more rock
    for _ in range(22):
        i, j = rng.randrange(1, nx - 1), rng.randrange(1, ny)
        if buried[i, j]:
            continue
        c = (verts[i, j].co + verts[i + 1, j].co) / 2
        sal.box(c + V((0, 0, 0.35)), (rng.uniform(3, 6), rng.uniform(3, 6), 0.7), "rplate",
                r=rot(rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15),
                      rng.uniform(0, math.pi)), bevel=0.0)


# ---------------------------------------------------------------- hangar / interior
def build_interior(sal, glow, lights, surf, rng):
    # Landing lane on the floor from the mouth inward, crimson strips both sides
    for sx in (-1, 1):
        for k in range(7):
            y = -30.0 + k * 4.6
            z = surf.top(sx * 7.0, y, default=FLOOR_Z) + 0.2
            glow.box(V((sx * 7.0, y, z)), (0.6, 2.4, 0.3), "glow", bevel=0.0)
            sal.box(V((sx * 7.0, y, z - 0.3)), (1.4, 3.0, 0.4), "dark", bevel=0.0)
    for k in range(4):
        y = -20.0 + k * 6.0
        z = surf.top(0.0, y, default=FLOOR_Z) + 0.15
        sal.box(V((0, y, z)), (10.0, 4.0, 0.3), "plate", r=rot(rz=rng.uniform(-0.05, 0.05)),
                bevel=0.0)
    # Bunker built into the back shard: armoured face with a glowing bay door
    by = 14.0
    bz = surf.top(0.0, by - 4.0, default=FLOOR_Z)
    sal.box(V((0, by + 3.0, bz + 6.0)), (26.0, 8.0, 13.0), "hull", bevel=0.02)
    sal.box(V((0, by - 1.2, bz + 12.8)), (28.0, 2.0, 1.6), "plate", bevel=0.0)
    for sx in (-1, 1):
        sal.box(V((sx * 10.0, by - 1.1, bz + 6.0)), (3.0, 2.2, 13.0), "plate", bevel=0.0)
        sal.box(V((sx * 10.0, by - 2.25, bz + 6.0)), (0.6, 0.1, 11.0), "crimson", bevel=0.0)
    sal.box(V((0, by - 0.9, bz + 5.5)), (17.0, 0.4, 10.0), "dark", bevel=0.0)
    glow.box(V((0, by - 1.2, bz + 5.5)), (15.0, 0.2, 8.5), "glow", bevel=0.0)
    for k in range(4):
        sal.box(V((0, by - 1.4, bz + 2.0 + k * 2.2)), (15.5, 0.25, 0.35), "dark", bevel=0.0)
    for sx in (-1, 1):
        lights.box(V((sx * 13.5, by - 1.3, bz + 13.2)), (0.9, 0.9, 0.9), "light", bevel=0.0)
    # Mouth markers: lights on the shard faces either side of the opening
    for sx in (-1, 1):
        for k in range(3):
            o = V((sx * 30.0, -32.0 + k * 3.0, 4.0 + k * 3.0))
            hit, nrm = surf.toward(o, V((-sx, 0.2, 0)))
            if hit is not None:
                lights.box(hit + nrm * 0.4, (0.9, 0.9, 0.9), "light", bevel=0.0)


def dart(p, c, rz, length=12.0):
    """Parked raider dart (low-detail corsair hull) along local +Y rotated by rz."""
    m = Matrix.Translation(c) @ Matrix.Rotation(rz, 4, "Z")
    L = length
    st = [(0.5, 0.04, 0.04, 0.03), (0.3, 0.4, 0.35, 0.2), (0.0, 0.85, 0.6, 0.4),
          (-0.35, 0.95, 0.6, 0.45), (-0.5, 0.8, 0.5, 0.4)]
    rings = []
    for y, w, top, bot in st:
        pts = [(0.0, top), (w * 0.62, top * 0.55), (w, 0.0), (w * 0.55, -bot),
               (-w * 0.55, -bot), (-w, 0.0), (-w * 0.62, top * 0.55)]
        rings.append([m @ V((x, y * L, z)) for x, z in pts])
    p.loft(rings, "hull", mat_fn=lambda i, j: "crimson" if j in (0, 6) and i == 1 else "hull")
    for sx in (-1, 1):
        pts = [(0.8, 0.0), (2.4, -0.4 * L), (2.45, -0.5 * L), (0.8, -0.36 * L)]
        pts = [(sx * x, y) for x, y in pts]
        if sx < 0:
            pts.reverse()
        p.slab(pts, -0.08, 0.08, "plate", matrix=m)


def build_clamps(sal, lights, surf, rng):
    """Docking clamp arms reaching in from the shards, each holding a parked dart."""
    for ang, length, z in ((-20, 14.0, 3.0), (-160, 14.0, 2.0), (25, 12.0, 8.0)):
        a = math.radians(ang)
        outer = V((math.cos(a) * RING_RX * 0.95, math.sin(a) * RING_RY * 0.95, z))
        inward = V((-math.cos(a), -math.sin(a), 0)).normalized()
        hit, _ = surf.toward(V((0, -2.0, z)) + inward * 0.0, -inward)
        base = hit if hit is not None else outer
        tip = base + inward * length
        sal.box(base, (4.0, 4.0, 4.0), "plate", rot_z=a, bevel=0.05)
        sal.beam(base, tip, 1.6, 1.4, "hull")
        sal.beam(base + V((0, 0, 1.3)), tip + V((0, 0, 0.6)), 0.5, 0.5, "dark")
        side = V((-inward.y, inward.x, 0))
        hub = tip + inward * 0.8
        sal.box(hub, (2.4, 2.4, 2.0), "dark", rot_z=a, bevel=0.0)
        for s in (-1, 1):  # C-jaw prongs straddling the dart
            j0 = hub + side * s * 1.0
            j1 = hub + side * s * 2.4 + inward * 1.4 + V((0, 0, -1.2))
            sal.beam(j0, j1, 0.6, 0.6, "crimson")
            lights.box(j1, (0.6, 0.6, 0.6), "light", bevel=0.0)
        # dart parked in the jaws, nose pointing into the hollow
        dart(sal, hub + inward * 1.0 + V((0, 0, 0.4)), a + math.pi / 2, 12.0)


def build_wreck(sal, lights, rng):
    """Forward half of a big dagger hull lying across the port rim, broken at the back."""
    m = (Matrix.Translation(V((-40.0, 6.0, 14.0))) @ rot(rx=0.1, ry=-0.3, rz=0.3)
         @ Matrix.Diagonal((1.35, 1.35, 1.35, 1.0)))
    st = [(22.0, 0.3, 0.3, 0.2), (14.0, 3.2, 2.6, 1.6), (4.0, 5.0, 3.6, 2.4),
          (-6.0, 5.6, 3.8, 2.6)]
    rings = []
    for y, w, top, bot in st:
        pts = [(0.0, top), (w * 0.62, top * 0.55), (w, 0.0), (w * 0.55, -bot),
               (-w * 0.55, -bot), (-w, 0.0), (-w * 0.62, top * 0.55)]
        rings.append([m @ V((x, y, z)) for x, z in pts])
    # jagged broken end: push the last ring's verts back by random amounts
    end = []
    for q in rings[-1]:
        end.append(q + (m.to_3x3() @ V((0, -rng.uniform(0.5, 4.5), 0))))
    rings.append(end)
    sal.loft(rings, "hull", cap=True,
             mat_fn=lambda i, j: "crimson" if j in (0, 6) and i == 1 else (
                 "plate" if i == 3 else "hull"))
    # torn ribs sticking out of the break, and a dead cockpit slit
    for k in range(5):
        x = -4.0 + k * 2.0
        p0 = m @ V((x, -7.0, rng.uniform(-1.5, 2.5)))
        p1 = m @ V((x * 1.2, -11.0 - rng.uniform(0, 3), rng.uniform(-2.5, 3.5)))
        sal.beam(p0, p1, 0.5, 0.5, "dark")
    sal.box(m @ V((0, 13.0, 2.4)), (2.4, 4.0, 0.3), "dark", r=m.to_3x3().to_4x4(), bevel=0.0)
    # its blade wing, snapped short
    pts = [(5.0, 4.0), (14.0, -3.0), (14.5, -7.0), (5.0, -5.0)]
    sal.slab(pts, -0.3, 0.3, "plate", matrix=m)
    lights.box(m @ V((14.5, -5.0, 0.6)), (0.9, 0.9, 0.9), "light", bevel=0.0)
    lights.box(m @ V((0.0, 22.0, 0.6)), (0.9, 0.9, 0.9), "light", bevel=0.0)


def build_spikes(sal, lights, surf, rng):
    """Crimson beacons and antenna spikes on the shard tops, plating on the outer rock."""
    for ang, t, rr, h, z, tilt in SHARDS:
        c, a = shard_centre(ang)
        top = surf.top(c.x, c.y, default=z + h)
        lights.box(V((c.x, c.y, top + 0.6)), (1.0, 1.0, 1.0), "light", bevel=0.0)
    for ang in (45, 132):
        c, a = shard_centre(ang)
        top = surf.top(c.x, c.y)
        sal.cyl(V((c.x, c.y, top + 5.0)), 0.25, 0.08, 10.0, "dark", segs=5)
        sal.box(V((c.x, c.y, top + 3.0)), (2.0, 0.2, 0.2), "dark", rot_z=a, bevel=0.0)
        lights.box(V((c.x, c.y, top + 10.3)), (0.8, 0.8, 0.8), "light", bevel=0.0)
    # Rock plating bolted on the outer slopes (camouflaged armour)
    for _ in range(18):
        a = rng.uniform(0, 2 * math.pi)
        if abs(math.degrees(a) - 270) < 45:
            continue
        x, y = math.cos(a) * RING_RX * 1.05, math.sin(a) * RING_RY * 1.05
        z = surf.top(x, y, default=None)
        if z is None:
            continue
        sal.box(V((x, y, z + 0.1)), (rng.uniform(3, 6), rng.uniform(3, 6), 0.6), "rplate",
                r=rot(rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), rng.uniform(0, 3)),
                bevel=0.0)


def build_nest():
    rng = random.Random(SEED)
    build_materials()
    root = parts.make_root("corsair_nest", size=20)
    rock, bvh = build_rock(root, rng)
    surf = Surface(bvh)
    sal = parts.Part("den_salvage", MATS)
    glow = parts.Part("den_hangar_glow", MATS)
    lights = parts.Part("den_lights", MATS)
    build_interior(sal, glow, lights, surf, random.Random(SEED + 1))
    build_clamps(sal, lights, surf, rng)
    build_wreck(sal, lights, rng)
    build_netting(sal, lights, surf, rng)
    build_spikes(sal, lights, surf, rng)
    objs = [rock] + [p.finish(root) for p in (sal, glow, lights)]
    net_up(objs[1])
    parts.add_empty("spawn_point", root, SPAWN_POS, rot_z=math.pi, size=6)
    return root, objs


def net_up(obj):
    """The net is an open sheet, so recalc_face_normals in Part.finish can point it down
    (backface culled from the RTS camera). Force every net face to face up."""
    mesh = obj.data
    net = {i for i, m in enumerate(mesh.materials) if m.name.startswith("nest_camo_net")}
    bm = bmesh.new()
    bm.from_mesh(mesh)
    for f in bm.faces:
        if f.material_index in net and f.normal.z < 0:
            f.normal_flip()
    bm.to_mesh(mesh)
    bm.free()


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_nest()
    parts.print_stats(objs)
    parts.save_blend(os.path.join(common.ROOT, "blender", "corsair_nest.blend"))
    common.export_glb(root, OUT)
    if "--no-preview" not in argv:
        common.setup_preview(cam_loc=(-90, -150, 160), cam_target=(0, -6, 0), ortho_scale=150,
                             res=(1600, 1200), key_dir=(-0.6, -0.35, 0.7), key_energy=3.5)
        common.render(os.path.join(common.PREVIEW_DIR, "corsair_nest_preview.png"))


main()
