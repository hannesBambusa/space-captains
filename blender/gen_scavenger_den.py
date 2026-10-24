"""Generate the scavenger den .glb and a 45 degree preview.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_scavenger_den.py
  Add `-- --no-preview` to skip the PNG render.

Layout (Blender Z up, exported +Y up). Rock centre at origin, play plane z=0.
A hollowed asteroid (~100 x 80 x 48 m, same lumpy style as gen_asteroids.py) with a
deep crater on Blender -Y (= Godot +Z). A salvaged station hangar frame sits at the
crater floor (front plane y = FRAME_Y) with a red-lit tunnel behind it.
  bolted on top: salvaged habitat module, broken ring segment, container stacks,
  scaffold towers, a crude gun emplacement; docking crane on the starboard rim
  reaching over the approach; struts and lights around the crater lip.
Hierarchy: scavenger_den (empty root)
  -> den_rock (vertex coloured), den_salvage, den_hangar_glow, den_lights,
     spawn_point (empty).
den_lights holds only the small red warning lights, so Godot can flicker them as one
mesh (material scav_light_red). den_hangar_glow is the red hangar opening glow
(material den_hangar_glow), separate so it can pulse.
spawn_point sits on the play plane in the hangar opening, rotated 180 deg about up,
so its Godot -Z (forward) points out of the opening (Godot world +Z).
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

OUT = os.path.join(common.ROOT, "assets", "models", "buildings", "scavenger_den.glb")
SEED = 8821
SX, SY, SZ = 50.0, 40.0, 24.0           # rock semi-axes (m)
OPEN_DIR = Vector((0, -1, 0.42)).normalized()  # crater direction (sphere space), tilted up
#                                        so the RTS camera looks into the cave
CRATER_ANG = 0.72                       # crater angular radius (rad)
CRATER_DEPTH = 0.55                     # fraction of radius carved out at the floor
FRAME_Y = -21.0                         # hangar frame front plane (Blender y)
FRAME_W, FRAME_H = 20.0, 11.0           # opening size, centred on z=0
SPAWN_POS = (0.0, -24.0, 0.0)
TUNNEL_DEPTH = 7.0
TUNNEL_BACK = FRAME_Y + TUNNEL_DEPTH + 1.0

MATS = {}


def build_materials():
    m = common.make_material
    MATS["rock"] = m("den_rock", (0.13, 0.115, 0.1), roughness=0.92, use_vertex_color=True)
    MATS["scorch"] = m("den_rock_scorched", (0.075, 0.062, 0.055), roughness=0.95,
                       use_vertex_color=True)
    MATS["rust"] = m("scav_hull_rust", (0.15, 0.065, 0.03), roughness=0.85, metallic=0.3)
    MATS["olive"] = m("scav_plate_olive", (0.10, 0.11, 0.05), roughness=0.8, metallic=0.2)
    MATS["scrap"] = m("scav_plate_scrap", (0.13, 0.115, 0.095), roughness=0.75, metallic=0.4)
    MATS["dark"] = m("scav_frame_dark", (0.045, 0.04, 0.035), roughness=0.6, metallic=0.6)
    MATS["oxred"] = m("scav_paint_oxide_red", (0.22, 0.035, 0.02), roughness=0.8, metallic=0.2)
    MATS["window"] = m("scav_window_red", (1.0, 0.25, 0.08), roughness=0.3,
                       emission=(1.0, 0.22, 0.05), emission_strength=3.5)
    MATS["light"] = m("scav_light_red", (1.0, 0.08, 0.03), roughness=0.3,
                      emission=(1.0, 0.06, 0.02), emission_strength=5.0)
    MATS["glow"] = m("den_hangar_glow", (1.0, 0.12, 0.04), roughness=0.3,
                     emission=(1.0, 0.1, 0.03), emission_strength=4.5)


# ---------------------------------------------------------------- rock
def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def build_rock(parent, rng):
    noise.seed_set(SEED)
    off = Vector((rng.uniform(-100, 100), rng.uniform(-100, 100), rng.uniform(-100, 100)))
    craters = []
    while len(craters) < 5:
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1) * 0.6)).normalized()
        if d.angle(OPEN_DIR) > CRATER_ANG * 2.2:
            craters.append((d, rng.uniform(0.18, 0.32), rng.uniform(0.07, 0.13)))
    chips = []
    while len(chips) < 6:
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        if d.angle(OPEN_DIR) > 1.4:
            chips.append((d, rng.uniform(0.8, 0.9)))

    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=5, radius=1.0)  # 5120 tris
    for v in bm.verts:
        n = v.co.normalized()
        a = n.angle(OPEN_DIR)
        inside = 1.0 - smooth((a / CRATER_ANG - 0.55) / 0.45)   # 1 on the crater floor
        p = n * 1.3 + off
        lump = (0.3 * noise.noise(p * 0.9) + 0.09 * noise.noise(p * 2.1 + Vector((7, 3, 1)))
                + 0.035 * noise.noise(p * 4.5))
        r = 1.0 + lump * (1.0 - 0.75 * inside)
        r -= CRATER_DEPTH * inside
        t = a / CRATER_ANG
        if 1.0 < t < 1.45:
            r += 0.07 * math.sin((t - 1.0) / 0.45 * math.pi)     # raised rim
        for d, ang, depth in craters:
            ca = n.angle(d)
            if ca < ang * 1.4:
                ct = ca / ang
                r += -depth * (1 - ct * ct) if ct < 1 else depth * 0.5 * math.sin(
                    (ct - 1) / 0.4 * math.pi)
        for d, o in chips:
            dn = n.dot(d)
            if dn > 0.05 and r * dn > o:
                r = o / dn
        v.co = Vector((n.x * r * SX, n.y * r * SY, n.z * r * SZ))
    mesh = bpy.data.meshes.new("den_rock")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("den_rock", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    cut_hangar(obj)
    mesh.materials.clear()  # the boolean leaves an empty slot behind
    mesh.materials.append(MATS["rock"])
    mesh.materials.append(MATS["scorch"])

    bm = bmesh.new()
    bm.from_mesh(mesh)
    for f in bm.faces:
        c = f.calc_center_median()
        cn = Vector((c.x / SX, c.y / SY, c.z / SZ)).normalized()
        in_cut = abs(c.x) < FRAME_W / 2 + 4.5 and c.y < TUNNEL_BACK + 0.5 and c.z < 30
        f.material_index = 1 if (cn.angle(OPEN_DIR) < CRATER_ANG * 0.95 or in_cut) else 0
        f.smooth = True
    bvh = BVHTree.FromBMesh(bm)
    bm.to_mesh(mesh)
    bm.free()
    mesh.set_sharp_from_angle(angle=math.radians(35))
    col = mesh.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            co = mesh.vertices[mesh.loops[li].vertex_index].co
            rad = Vector((co.x / SX, co.y / SY, co.z / SZ)).length
            cav = max(0.0, min(1.0, (rad - 0.7) / 0.5))
            var = noise.noise(co * 0.05 + Vector((11, 5, 2)))
            k = 0.78 + 0.22 * cav + 0.07 * var
            warm = 0.04 * noise.noise(co * 0.03 + Vector((3, 9, 1)))
            col.data[li].color = (min(1, k + warm), min(1, k), min(1, k - warm), 1.0)
    mesh.color_attributes.active_color = col
    return obj, bvh


def cut_hangar(obj):
    """Boolean-cut the tunnel behind the frame and an open approach trench in front of it,
    so the play plane (z=0) is clear from the opening out to space and the RTS camera
    sees the whole lit doorway."""
    hw, hh = FRAME_W / 2, FRAME_H / 2
    boxes = [  # (min corner, max corner)
        ((-hw - 1.0, FRAME_Y - 2.5, -hh - 1.0), (hw + 1.0, TUNNEL_BACK, hh + 1.0)),
        ((-hw - 4.0, -80.0, -hh - 3.0), (hw + 4.0, FRAME_Y - 2.0, 40.0)),
    ]
    for i, (lo, hi) in enumerate(boxes):
        lo, hi = Vector(lo), Vector(hi)
        cm = bpy.data.meshes.new(f"den_cutter_{i}")
        cbm = bmesh.new()
        bmesh.ops.create_cube(cbm, size=1.0, matrix=Matrix.Translation((lo + hi) / 2)
                              @ Matrix.Diagonal((*(hi - lo), 1.0)))
        cbm.to_mesh(cm)
        cbm.free()
        cutter = bpy.data.objects.new(f"den_cutter_{i}", cm)
        bpy.context.scene.collection.objects.link(cutter)
        mod = obj.modifiers.new(f"cut_{i}", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.solver = "EXACT"
        mod.object = cutter
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cutter)
        bpy.data.meshes.remove(cm)


class Surface:
    """Ray queries against the rock, to bolt things onto it."""

    def __init__(self, bvh):
        self.bvh = bvh

    def top(self, x, y, default=0.0):
        hit = self.bvh.ray_cast(Vector((x, y, 200.0)), Vector((0, 0, -1)))
        return hit[0].z if hit[0] is not None else default

    def toward(self, origin, direction):
        hit = self.bvh.ray_cast(Vector(origin), Vector(direction).normalized())
        return hit[0]


# ---------------------------------------------------------------- hangar
def build_hangar(sal, glow, lights, surf, rng):
    fy = FRAME_Y
    hw, hh = FRAME_W / 2, FRAME_H / 2
    depth = TUNNEL_DEPTH
    # Tunnel into the rock: dark walls, glowing red back wall and floor strips
    sal.box(V((0, fy + depth / 2, -hh - 0.6)), (FRAME_W + 2, depth, 1.2), "dark", bevel=0.0)
    sal.box(V((0, fy + depth / 2, hh + 0.6)), (FRAME_W + 2, depth, 1.2), "dark", bevel=0.0)
    for sx in (-1, 1):
        sal.box(V((sx * (hw + 0.6), fy + depth / 2, 0)), (1.2, depth, FRAME_H + 2.4), "dark",
                bevel=0.0)
        glow.box(V((sx * (hw - 0.05), fy + depth / 2 + 1, -hh + 1.2)), (0.12, depth - 4, 0.5),
                 "glow", bevel=0.0)
    glow.box(V((0, fy + depth - 0.3, 0)), (FRAME_W - 1, 0.2, FRAME_H - 1), "glow", bevel=0.0)
    glow.box(V((0, fy + depth / 2, -hh + 0.05)), (FRAME_W - 4, depth - 1, 0.1), "glow",
             bevel=0.0)
    for k in range(3):
        sal.box(V((0, fy + 1.5 + k * 2.0, -hh + 0.15)), (FRAME_W - 3, 0.5, 0.12), "dark",
                bevel=0.0)
        glow.box(V((0, fy + 1.5 + k * 2.0, hh - 0.05)), (FRAME_W - 3, 0.4, 0.1), "glow",
                 bevel=0.0)
    # Salvaged station door frame: chunky rusty surround with oxide-red stripes
    sal.box(V((0, fy - 0.8, hh + 1.6)), (FRAME_W + 7, 2.4, 3.2), "rust")
    sal.box(V((0, fy - 0.8, -hh - 1.4)), (FRAME_W + 7, 2.4, 2.8), "scrap")
    for sx in (-1, 1):
        sal.box(V((sx * (hw + 1.9), fy - 0.8, 0)), (3.8, 2.4, FRAME_H + 6.0), "scrap")
        sal.box(V((sx * (hw + 1.9), fy - 2.05, 0)), (1.0, 0.12, FRAME_H + 3.0), "oxred",
                bevel=0.0)
    m = Matrix.Translation(V((0, fy - 2.0, 0))) @ parts.FRONT
    sal.hazard(-hw - 3.0, hw + 3.0, 1.4, 0.0, 0.1, matrix=m @ Matrix.Translation((0, hh + 1.8, 0)),
               cols=("oxred", "dark"), pitch=1.8)
    glow.box(V((0, fy - 2.05, hh + 0.05)), (FRAME_W - 0.5, 0.15, 0.3), "glow", bevel=0.0)
    for sx in (-1, 1):
        glow.box(V((sx * (hw - 0.1), fy - 2.05, 0)), (0.3, 0.15, FRAME_H - 0.5), "glow",
                 bevel=0.0)
    # Broken blast door leaf hanging askew on one side
    sal.box(V((-hw - 4.6, fy - 2.6, -1.0)), (4.0, 0.6, FRAME_H + 1.0), "olive",
            r=rot(ry=0.18, rz=0.25))
    # Scrap-plate landing deck in front of the frame
    for k in range(4):
        sal.box(V((rng.uniform(-1.5, 1.5), fy - 4.0 - k * 3.4, -hh - 1.6 + rng.uniform(-0.2, 0.2))),
                (FRAME_W - 2 + rng.uniform(-3, 2), 3.6, 0.5),
                ("scrap", "rust", "olive", "scrap")[k],
                r=rot(rng.uniform(-0.04, 0.04), rng.uniform(-0.05, 0.05),
                      rng.uniform(-0.06, 0.06)), bevel=0.0)
    for sx in (-1, 1):
        for k in range(3):
            lights.box(V((sx * (hw - 1.0), fy - 4.0 - k * 4.0, -hh - 1.1)), (0.6, 0.6, 0.4),
                       "light", bevel=0.0)
    for sx in (-1, 1):
        lights.box(V((sx * (hw + 3.6), fy - 2.2, hh + 3.4)), (0.9, 0.9, 0.9), "light", bevel=0.0)
        lights.box(V((sx * (hw + 3.6), fy - 2.2, -hh - 2.6)), (0.8, 0.8, 0.8), "light", bevel=0.0)
    # Struts from the frame out to the crater lip
    for ang in (0.35, 1.2, 1.95, 2.8, 3.6, 5.8):
        d = V((math.cos(ang) * 1.0, -0.85, math.sin(ang) * 0.55)).normalized()
        start = V((math.cos(ang) * (hw + 2.5), fy - 1.0, math.sin(ang) * (hh + 2.0)))
        hit = surf.toward(start, d)
        if hit is not None and (hit - start).length < 30 and hit.z > -12:
            sal.beam(start, hit + d * 1.0, 0.8, 0.8, "dark")
            sal.box(hit, (2.2, 2.2, 2.2), "rust", bevel=0.0)


# ---------------------------------------------------------------- bolted-on parts
def container(p, c, rz, mat, size=(6.0, 2.6, 2.6)):
    p.box(c, size, mat, rot_z=rz, bevel=0.05)
    for k in (-1, 0, 1):
        off = Matrix.Rotation(rz, 4, "Z") @ V((k * size[0] * 0.33, 0, 0))
        p.box(c + off, (0.2, size[1] + 0.1, size[2] + 0.1), "dark", rot_z=rz, bevel=0.0)


def lattice_tower(p, base, top_z, w, mat="dark"):
    for dx in (-1, 1):
        for dy in (-1, 1):
            p.beam(base + V((dx * w, dy * w, 0)), V((base.x + dx * w, base.y + dy * w, top_z)),
                   0.4, 0.4, mat)
    n = max(2, int((top_z - base.z) / 4.0))
    for k in range(n):
        z0 = base.z + k * (top_z - base.z) / n
        z1 = base.z + (k + 1) * (top_z - base.z) / n
        p.beam(V((base.x - w, base.y - w, z0)), V((base.x + w, base.y - w, z1)), 0.25, 0.25, mat)
        p.beam(V((base.x + w, base.y + w, z0)), V((base.x - w, base.y + w, z1)), 0.25, 0.25, mat)


def build_topside(sal, lights, surf, rng):
    # Salvaged habitat module lying across the top, rusty bands, red windows
    hc = V((-14.0, 4.0, 0))
    hc.z = surf.top(hc.x, hc.y) + 3.6
    hab = Matrix.Rotation(0.35, 4, "Z") @ ALONG_Y
    hab_r = Matrix.Rotation(0.35, 4, "Z")
    sal.cyl(hc, 5.0, 5.0, 22.0, "scrap", segs=14, axis_rot=hab)
    for k in (-1, 0, 1):
        sal.cyl(hc + hab_r @ V((0, k * 8.0, 0)), 5.3, 5.3, 1.2, "rust", segs=14, axis_rot=hab)
    for k in (-1, 1):
        sal.cyl(hc + hab_r @ V((0, k * 11.6, 0)), 3.2, 4.6, 1.2, "dark", segs=14, axis_rot=hab)
    for k in range(4):
        sal.box(hc + hab_r @ V((-4.6, -6 + k * 4.0, 1.8)), (0.3, 2.2, 0.6), "window",
                r=hab_r @ rot(ry=-0.5), bevel=0.0)
    sal.box(hc + hab_r @ V((0, 0, 5.2)), (3.0, 10.0, 0.6), "oxred", r=hab_r, bevel=0.0)
    for k in (-1, 1):
        lights.box(hc + hab_r @ V((0, k * 10.0, 5.4)), (0.8, 0.8, 0.8), "light", r=hab_r,
                   bevel=0.0)
    # Clamp brackets bolting it to the rock
    for k in (-1, 1):
        b = hc + hab_r @ V((0, k * 6.0, 0))
        sal.box(V((b.x, b.y, (b.z + surf.top(b.x, b.y)) / 2 - 1.5)), (12.0, 1.4, 6.0), "dark",
                r=hab_r, bevel=0.0)

    # Broken station ring segment on the starboard side, arcing up out of the rock
    rc = V((22.0, 6.0, surf.top(22.0, 6.0) - 4.0))
    R = 16.0
    prev = None
    for k in range(7):
        a = math.radians(20 + k * 17)
        pt = rc + V((math.cos(a) * R * 0.25, math.cos(a) * R, math.sin(a) * R * 0.55))
        if prev is not None:
            sal.beam(prev, pt, 4.2, 3.0, "rust" if k % 2 else "scrap", up=V((1, 0, 0)))
            mid = (prev + pt) / 2
            sal.box(mid + V((0, 0, 1.6)), (4.4, 1.0, 0.4), "dark", bevel=0.0)
        prev = pt
    lights.box(prev + V((0, 0, 2.0)), (1.0, 1.0, 1.0), "light", bevel=0.0)

    # Container stacks on flat-ish spots (scrap platform under each)
    stacks = [(-30.0, -8.0, 0.2, ("rust", "olive", "oxred")),
              (4.0, 16.0, 1.4, ("olive", "scrap", "rust")),
              (30.0, -14.0, -0.5, ("oxred", "rust"))]
    for x, y, rz, cols in stacks:
        z = surf.top(x, y)
        sal.box(V((x, y, z + 0.2)), (10.0, 8.0, 1.0), "dark", rot_z=rz, bevel=0.0)
        for i, mat in enumerate(cols):
            o = Matrix.Rotation(rz, 4, "Z") @ V(((i % 2) * 1.2 - 0.6, (i % 2) * 3.0 - 1.5, 0))
            container(sal, V((x, y, z + 2.0 + (i // 2) * 2.7)) + o, rz + (i - 1) * 0.12, mat)
        lights.box(V((x, y, z + 1.0)) + Matrix.Rotation(rz, 4, "Z") @ V((4.8, 3.8, 0)),
                   (0.6, 0.6, 0.6), "light", bevel=0.0)

    # Scaffold towers with platforms and beacons
    for x, y, h in ((-4.0, -14.0, 14.0), (14.0, -20.0, 10.0), (-24.0, 16.0, 12.0)):
        z0 = surf.top(x, y) - 1.0
        lattice_tower(sal, V((x, y, z0)), z0 + h, 1.5)
        sal.box(V((x, y, z0 + h + 0.3)), (5.0, 5.0, 0.6), "scrap", bevel=0.0)
        sal.box(V((x + 1.2, y, z0 + h + 1.6)), (2.4, 2.4, 2.2), "rust", bevel=0.05)
        sal.box(V((x + 1.2, y - 1.25, z0 + h + 1.9)), (1.6, 0.1, 0.4), "window", bevel=0.0)
        sal.cyl(V((x - 1.6, y + 1.6, z0 + h + 3.6)), 0.12, 0.06, 6.0, "dark", segs=4)
        lights.box(V((x - 1.6, y + 1.6, z0 + h + 6.8)), (0.7, 0.7, 0.7), "light", bevel=0.0)

    # Crude gun emplacement on the port top, barrels toward the approach
    gx, gy = -26.0, -16.0
    gz = surf.top(gx, gy)
    sal.cyl(V((gx, gy, gz + 1.0)), 4.0, 3.0, 2.4, "scrap", segs=10)
    sal.box(V((gx, gy, gz + 3.4)), (4.4, 5.0, 2.6), "rust", rot_z=0.25)
    for s in (-1, 1):
        sal.tube(V((gx + s * 1.0, gy - 1.0, gz + 3.6)),
                 V((gx + s * 1.0 + 2.5, gy - 11.0, gz + 4.2)), 0.45, 0.4, "dark", segs=8)
    lights.box(V((gx, gy + 2.6, gz + 4.9)), (0.7, 0.7, 0.7), "light", bevel=0.0)

    # Scrap solar / radiator wings stuck on the back
    for x, rz in ((-10.0, 0.2), (12.0, -0.3)):
        y = 34.0
        z = surf.top(x, y - 6.0)
        sal.beam(V((x, y - 8.0, z)), V((x, y + 6.0, z + 3.0)), 0.8, 0.8, "dark")
        for k in range(3):
            sal.box(V((x, y - 3.0 + k * 4.0, z + 1.2 + k * 0.6)), (9.0, 3.4, 0.25),
                    ("olive", "scrap", "dark")[k], r=rot(rx=0.2, rz=rz), bevel=0.0)

    # Random bolted hull plates over the rock surface
    for _ in range(16):
        a = rng.uniform(0, 2 * math.pi)
        rr = rng.uniform(0.3, 0.85)
        x, y = math.cos(a) * SX * rr, math.sin(a) * SY * rr
        if y < -10 and abs(x) < 26:
            continue
        z = surf.top(x, y)
        sal.box(V((x, y, z + 0.1)), (rng.uniform(3, 7), rng.uniform(3, 7), 0.5),
                rng.choice(("rust", "scrap", "olive", "oxred")),
                r=rot(rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), rng.uniform(0, 3)),
                bevel=0.0)


def build_crane(sal, lights, surf):
    # Docking crane on the starboard crater rim, boom out over the approach lane
    bx, by = 30.0, -26.0
    bz = surf.top(bx, by, default=-8.0) - 1.0
    top = 18.0
    lattice_tower(sal, V((bx, by, bz)), top, 1.8, mat="dark")
    sal.box(V((bx, by, bz + 0.5)), (6.0, 6.0, 1.6), "scrap", bevel=0.0)
    sal.box(V((bx, by, top + 1.0)), (4.4, 4.4, 2.2), "rust")
    sal.box(V((bx - 2.25, by - 0.8, top + 1.2)), (0.1, 2.2, 0.7), "window", bevel=0.0)
    ang = math.radians(235)
    d = V((math.cos(ang), math.sin(ang), 0))
    side = V((-d.y, d.x, 0))
    z = top + 2.6
    L = 26.0
    base = V((bx, by, 0))
    for s in (-1, 1):
        sal.beam(base + side * s * 1.0 + V((0, 0, z)), base + d * L + side * s * 0.5 + V((0, 0, z)),
                 0.7, 1.0, "oxred")
        sal.beam(base + side * s * 1.0 + V((0, 0, z)), base - d * 8.0 + side * s + V((0, 0, z)),
                 0.7, 1.0, "oxred")
    for k in range(10):
        t0, t1 = 1.0 + k * 2.4, 2.2 + k * 2.4
        sal.beam(base + d * t0 + side * 0.9 + V((0, 0, z)), base + d * t1 - side * 0.9 + V((0, 0, z)),
                 0.25, 0.35, "dark")
    sal.box(base + V((0, 0, z + 2.5)), (0.8, 0.8, 4.6), "dark", bevel=0.0)
    sal.beam(base + V((0, 0, z + 4.6)), base + d * (L - 1) + V((0, 0, z + 0.4)), 0.25, 0.25, "dark")
    sal.beam(base + V((0, 0, z + 4.6)), base - d * 7.5 + V((0, 0, z + 0.4)), 0.25, 0.25, "dark")
    sal.box(base - d * 7.0 + V((0, 0, z - 0.6)), (4.0, 4.0, 3.0), "scrap", rot_z=ang)
    lights.box(base + V((0, 0, z + 5.0)), (0.8, 0.8, 0.8), "light", bevel=0.0)
    lights.box(base + d * L + V((0, 0, z)), (0.8, 0.8, 0.8), "light", bevel=0.0)
    # Trolley, cable and a three-finger grab claw
    tp = base + d * (L - 4.0)
    sal.box(tp + V((0, 0, z - 0.8)), (1.8, 2.0, 0.6), "dark", bevel=0.0)
    sal.cyl(tp + V((0, 0, z - 6.0)), 0.12, 0.12, 10.0, "dark", segs=4)
    hub = tp + V((0, 0, z - 11.2))
    sal.cyl(hub, 1.2, 0.8, 1.4, "rust", segs=8)
    for k in range(3):
        a = k * 2 * math.pi / 3
        o = V((math.cos(a), math.sin(a), 0))
        p1 = hub + o * 2.4 + V((0, 0, -1.6))
        p2 = hub + o * 1.4 + V((0, 0, -3.6))
        sal.beam(hub, p1, 0.5, 0.5, "dark")
        sal.beam(p1, p2, 0.45, 0.45, "dark")


def build_gantry(sal, lights, surf):
    """Big salvaged truss arch over the crater mouth: the den's silhouette marker."""
    pts = []
    for k in range(7):
        t = k / 6
        x = -30 + 60 * t
        y = -24.0 - 4.0 * math.sin(t * math.pi)
        base = surf.top(x, y, default=0.0)
        arch = 14.0 * math.sin(t * math.pi)
        pts.append(V((x, y, max(base, 6.0) + arch if 0 < k < 6 else base - 1.0)))
    for a, b in zip(pts, pts[1:]):
        for dz in (0.0, 2.6):
            sal.beam(a + V((0, 0, dz)), b + V((0, 0, dz)), 1.0, 0.8, "rust", up=V((0, 1, 0)))
        sal.beam(a, b + V((0, 0, 2.6)), 0.4, 0.4, "dark", up=V((0, 1, 0)))
    for k, pt in enumerate(pts):
        sal.box(pt + V((0, 0, 1.3)), (1.6, 2.0, 3.4), "scrap" if k % 2 else "dark", bevel=0.0)
        if 0 < k < 6:
            lights.box(pt + V((0, -1.2, -0.6)), (0.8, 0.8, 0.8), "light", bevel=0.0)
    # Hanging signal lamps and a cable down to the frame
    mid = pts[3]
    sal.cyl(mid + V((0, 0, -4.0)), 0.1, 0.1, 8.0, "dark", segs=4)
    lights.box(mid + V((0, 0, -8.4)), (1.2, 1.2, 1.2), "light", bevel=0.0)


def build_den():
    rng = random.Random(SEED)
    build_materials()
    root = parts.make_root("scavenger_den", size=20)
    rock, bvh = build_rock(root, rng)
    surf = Surface(bvh)
    sal = parts.Part("den_salvage", MATS)
    glow = parts.Part("den_hangar_glow", MATS)
    lights = parts.Part("den_lights", MATS)
    build_hangar(sal, glow, lights, surf, random.Random(SEED + 1))
    build_topside(sal, lights, surf, rng)
    build_crane(sal, lights, surf)
    build_gantry(sal, lights, surf)
    objs = [rock] + [p.finish(root) for p in (sal, glow, lights)]
    parts.add_empty("spawn_point", root, SPAWN_POS, rot_z=math.pi, size=6)
    return root, objs



def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_den()
    parts.print_stats(objs)
    parts.save_blend(os.path.join(common.ROOT, "blender", "scavenger_den.blend"))
    common.export_glb(root, OUT)
    if "--no-preview" not in argv:
        common.setup_preview(cam_loc=(-90, -150, 160), cam_target=(0, -6, 0), ortho_scale=150,
                             res=(1600, 1200), key_dir=(-0.6, -0.35, 0.7), key_energy=3.5)
        common.render(os.path.join(common.PREVIEW_DIR, "scavenger_den_preview.png"))


main()
