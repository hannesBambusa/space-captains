"""Generate the syndicate fortress .glb and a 45 degree preview.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_syndicate_fortress.py
  Add `-- --no-preview` to skip the PNG render.

Design: an organised, fortified base, not a hideout. A flattened anchor asteroid
carries a stepped octagonal armoured core (gunmetal, buttresses, hazard-yellow bands,
amber slits), an armoured gatehouse with the hangar mouth on Blender -Y (= Godot +Z),
four outrigger gun platforms with twin turrets on the flanks, point-defence mounts on
the core and a tall lattice comms mast with dishes at the back. About 150 x 115 m
(1.5x scavenger_den). From above: a hard octagon with four square-ish pads on arms,
nothing like the round scavenger rock or the corsair ring of shards.

Layout (Blender Z up, exported +Y up). Core centre at origin, play plane z=0.
Hierarchy: syndicate_fortress (empty root)
  -> den_rock (anchor rock, vertex coloured, plus the core and gatehouse shell),
     den_salvage, den_hangar_glow, den_lights, spawn_point (empty).
Node names match scavenger_den.glb so ScavengerDen-style code can swap the path.
den_rock is what stays when the base is ruined (rock + burnt core shell); den_salvage
holds the platforms, turrets, mast and armour detail (hidden on the ruined look).
den_lights holds only the small amber lights (material syn_light_amber), so Godot can
flicker them as one mesh. den_hangar_glow is the amber hangar glow (material
syn_hangar_glow), separate so it can pulse.
spawn_point sits on the play plane in front of the hangar mouth, rotated 180 deg about
up, so its Godot -Z (forward) points out of the opening (Godot world +Z).
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
from parts import ALONG_Y, V, rot  # noqa: E402

OUT = os.path.join(common.ROOT, "assets", "models", "buildings", "syndicate_fortress.glb")
SEED = 7719
ROCK = (62.0, 52.0, 16.0)               # anchor rock semi-axes
ROCK_Z = -22.0
# Core tiers: (vertex radius, z0, z1)
TIERS = [(40.0, -14.0, 5.0), (30.0, 5.0, 14.0), (17.0, 14.0, 22.0)]
GATE_Y0, GATE_Y1 = -35.0, -50.0         # gatehouse back (core face) / front plane
GATE_W, GATE_H = 26.0, 14.0             # hangar opening, centred on z=0
SPAWN_POS = (0.0, -54.0, 0.0)
PLATFORMS = [(28.0, 72.0), (152.0, 72.0), (208.0, 70.0), (332.0, 70.0)]  # (angle deg, radius)
MAST = V((0.0, 14.0, 22.0))

MATS = {}


def build_materials():
    m = common.make_material
    MATS["rock"] = m("fort_rock", (0.12, 0.115, 0.11), roughness=0.92, use_vertex_color=True)
    MATS["gun"] = m("syn_hull_gunmetal", (0.14, 0.15, 0.16), roughness=0.5, metallic=0.75)
    MATS["armour"] = m("syn_armour_dark", (0.075, 0.08, 0.085), roughness=0.55, metallic=0.7)
    MATS["dark"] = m("syn_frame_dark", (0.03, 0.03, 0.032), roughness=0.6, metallic=0.6)
    MATS["yellow"] = m("syn_hazard_yellow", (0.6, 0.42, 0.02), roughness=0.55, metallic=0.2)
    MATS["metal"] = m("syn_bare_metal", (0.22, 0.22, 0.22), roughness=0.35, metallic=0.9)
    MATS["window"] = m("syn_window_amber", (1.0, 0.65, 0.2), roughness=0.3,
                       emission=(1.0, 0.55, 0.12), emission_strength=3.5)
    MATS["light"] = m("syn_light_amber", (1.0, 0.6, 0.1), roughness=0.3,
                      emission=(1.0, 0.5, 0.05), emission_strength=5.0)
    MATS["glow"] = m("syn_hangar_glow", (1.0, 0.6, 0.15), roughness=0.3,
                     emission=(1.0, 0.5, 0.1), emission_strength=4.5)


def octagon(r, x=0.0, y=0.0):
    return [(x + r * math.cos(math.radians(22.5 + 45 * k)),
             y + r * math.sin(math.radians(22.5 + 45 * k))) for k in range(8)]


def apothem(r):
    return r * math.cos(math.radians(22.5))


# ---------------------------------------------------------------- rock + core shell
def add_rock(part, rng):
    noise.seed_set(SEED)
    off = Vector((rng.uniform(-100, 100), rng.uniform(-100, 100), rng.uniform(-100, 100)))
    res = bmesh.ops.create_icosphere(part.bm, subdivisions=5, radius=1.0)
    idx = part.mi("rock")
    for v in res["verts"]:
        n = v.co.normalized()
        p = n * 1.3 + off
        lump = (0.22 * noise.noise(p * 0.9) + 0.08 * noise.noise(p * 2.1 + Vector((7, 3, 1)))
                + 0.03 * noise.noise(p * 4.5))
        r = 1.0 + lump
        if n.z > 0.3:   # flattened top where the core was dug in
            r = min(r, 0.75 / n.z) if n.z > 0.75 else r
        v.co = Vector((n.x * r * ROCK[0], n.y * r * ROCK[1], ROCK_Z + n.z * r * ROCK[2]))
    for f in {f for v in res["verts"] for f in v.link_faces}:
        f.material_index = idx
    return res["verts"]


def build_shell(root, rng):
    """den_rock: anchor rock, stepped octagonal core and the gatehouse shell."""
    p = parts.Part("den_rock", MATS)
    rock_verts = set(add_rock(p, rng))
    for k, (r, z0, z1) in enumerate(TIERS):
        p.slab(octagon(r), z0, z1, ("armour", "gun", "armour")[k])
        # chamfer lip on each tier top
        p.slab(octagon(r - 1.5), z1, z1 + 0.8, "gun" if k != 1 else "armour")
    # Gatehouse: roof, side walls, sill, around the hangar opening
    hw, hh = GATE_W / 2, GATE_H / 2
    gy = (GATE_Y0 + GATE_Y1) / 2
    depth = GATE_Y0 - GATE_Y1 + 2.0
    p.box(V((0, gy, hh + 3.5)), (GATE_W + 16, depth, 7.0), "gun", bevel=0.03)
    for sx in (-1, 1):
        p.box(V((sx * (hw + 4.0), gy, -2.0)), (8.0, depth, GATE_H + 4.0), "armour", bevel=0.03)
    p.box(V((0, gy, -hh - 2.0)), (GATE_W + 16, depth, 4.0), "armour", bevel=0.0)
    obj = p.finish(root)
    mesh = obj.data
    col = mesh.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    rock_idx = [i for i, m in enumerate(mesh.materials) if m.name == "fort_rock"][0]
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            if poly.material_index != rock_idx:
                col.data[li].color = (1.0, 1.0, 1.0, 1.0)
                continue
            co = mesh.vertices[mesh.loops[li].vertex_index].co
            hgt = max(0.0, min(1.0, (co.z - ROCK_Z + 10.0) / 30.0))
            var = noise.noise(co * 0.05 + Vector((11, 5, 2)))
            k = 0.75 + 0.25 * hgt + 0.07 * var
            col.data[li].color = (min(1, k), min(1, k), min(1, k * 0.97), 1.0)
    mesh.color_attributes.active_color = col
    del rock_verts
    return obj


# ---------------------------------------------------------------- hangar
def build_hangar(sal, glow, lights):
    hw, hh = GATE_W / 2, GATE_H / 2
    fy = GATE_Y1
    # Tunnel liner and glowing back wall / floor strips
    tl = GATE_Y0 - GATE_Y1
    for sx in (-1, 1):
        sal.box(V((sx * (hw + 0.3), fy + tl / 2, 0)), (0.6, tl, GATE_H), "dark", bevel=0.0)
        glow.box(V((sx * (hw - 0.05), fy + tl / 2, -hh + 1.5)), (0.12, tl - 2, 0.5), "glow",
                 bevel=0.0)
    sal.box(V((0, fy + tl / 2, hh + 0.3)), (GATE_W, tl, 0.6), "dark", bevel=0.0)
    sal.box(V((0, fy + tl / 2, -hh - 0.05)), (GATE_W, tl, 0.3), "dark", bevel=0.0)
    glow.box(V((0, GATE_Y0 - 0.4, 0)), (GATE_W - 2, 0.2, GATE_H - 2), "glow", bevel=0.0)
    for k in range(4):
        glow.box(V((0, fy + 2.0 + k * 3.2, -hh + 0.15)), (GATE_W - 6, 0.6, 0.12), "glow",
                 bevel=0.0)
        sal.box(V((0, fy + 2.0 + k * 3.2, hh)), (GATE_W - 2, 0.6, 0.5), "armour", bevel=0.0)
    # Heavy blast-door frame with hazard chevrons, doors retracted into the roof
    sal.box(V((0, fy - 0.8, hh + 1.2)), (GATE_W + 6, 1.6, 2.4), "gun")
    sal.box(V((0, fy - 0.8, -hh - 1.0)), (GATE_W + 6, 1.6, 2.0), "gun")
    for sx in (-1, 1):
        sal.box(V((sx * (hw + 1.6), fy - 0.8, 0)), (3.2, 1.6, GATE_H + 4.4), "gun")
    m = Matrix.Translation(V((0, fy - 1.65, 0))) @ parts.FRONT
    sal.hazard(-hw - 3.0, hw + 3.0, 1.6, 0.0, 0.08, matrix=m @ Matrix.Translation((0, hh + 1.2, 0)),
               cols=("yellow", "dark"), pitch=2.0)
    sal.hazard(-hw - 3.0, hw + 3.0, 1.4, 0.0, 0.08, matrix=m @ Matrix.Translation((0, -hh - 1.0, 0)),
               cols=("yellow", "dark"), pitch=2.0)
    glow.box(V((0, fy - 1.7, hh - 0.1)), (GATE_W - 0.5, 0.12, 0.3), "glow", bevel=0.0)
    for sx in (-1, 1):
        glow.box(V((sx * (hw - 0.1), fy - 1.7, 0)), (0.3, 0.12, GATE_H - 0.5), "glow", bevel=0.0)
        lights.box(V((sx * (hw + 3.6), fy - 1.8, hh + 2.6)), (1.0, 1.0, 1.0), "light", bevel=0.0)
        lights.box(V((sx * (hw + 3.6), fy - 1.8, -hh - 2.2)), (0.9, 0.9, 0.9), "light",
                   bevel=0.0)
    # Approach apron: a landing deck sticking out of the sill with guide lights
    sal.box(V((0, fy - 6.0, -hh - 2.6)), (GATE_W + 4, 10.0, 1.2), "armour", bevel=0.0)
    sal.hazard(-hw - 2.0, hw + 2.0, 0.9, 0.0, 0.06,
               matrix=Matrix.Translation((0, fy - 10.6, -hh - 2.0)), cols=("yellow", "dark"),
               pitch=1.6)
    for sx in (-1, 1):
        for k in range(3):
            lights.box(V((sx * (hw + 0.5), fy - 2.5 - k * 3.0, -hh - 1.9)), (0.6, 0.6, 0.3),
                       "light", bevel=0.0)


# ---------------------------------------------------------------- core detail
def build_core_detail(sal, lights):
    # Buttresses on the lower tier faces (skip the front face, the gatehouse is there)
    r0, z0, z1 = TIERS[0]
    a0 = apothem(r0)
    for k in range(8):
        ang = math.radians(45 * k)
        if abs(math.degrees(ang) - 270) < 1:
            continue
        d = V((math.cos(ang), math.sin(ang), 0))
        t = V((-d.y, d.x, 0))
        for s in (-1, 1):
            c = d * (a0 + 1.5) + t * s * 9.0
            sal.box(V((c.x, c.y, (z0 + z1) / 2 + 1.0)), (3.0, 3.0, z1 - z0 - 2.0), "gun",
                    rot_z=ang, bevel=0.05)
        # amber slit row and a yellow band per face
        c = d * (a0 + 0.1)
        sal.box(V((c.x, c.y, z1 - 3.0)), (0.2, 10.0, 0.6), "window", rot_z=ang, bevel=0.0)
        m = Matrix.Translation(V((c.x, c.y, z1 - 1.2))) @ Matrix.Rotation(ang + math.pi / 2, 4,
                                                                           "Z") @ parts.FRONT
        sal.hazard(-6.0, 6.0, 1.2, -0.12, 0.0, matrix=m, cols=("yellow", "dark"), pitch=1.5)
    # Tier 2: yellow deck band, point-defence mounts on four corners
    r1, _, z1b = TIERS[1]
    for k in range(4):
        ang = math.radians(45 + 90 * k)
        c = V((math.cos(ang) * (r1 - 5.0), math.sin(ang) * (r1 - 5.0), z1b + 0.8))
        sal.cyl(c + V((0, 0, 0.6)), 2.2, 2.4, 1.2, "armour", segs=10)
        sal.box(c + V((0, 0, 2.0)), (2.6, 2.6, 1.6), "gun", rot_z=ang, bevel=0.1)
        d = V((math.cos(ang), math.sin(ang), 0))
        for s in (-1, 1):
            side = V((-d.y, d.x, 0)) * s * 0.5
            sal.tube(c + V((0, 0, 2.1)) + side, c + V((0, 0, 2.6)) + side + d * 5.0, 0.22, 0.18,
                     "dark", segs=6)
        lights.box(c + V((0, 0, 3.1)), (0.6, 0.6, 0.6), "light", bevel=0.0)
    for k in range(8):  # tier-2 edge hazard ring
        a = math.radians(22.5 + 45 * k)
        b = math.radians(22.5 + 45 * (k + 1))
        pa = V((math.cos(a), math.sin(a), 0)) * (r1 - 1.5)
        pb = V((math.cos(b), math.sin(b), 0)) * (r1 - 1.5)
        mid = (pa + pb) / 2
        ang = math.atan2(pb.y - pa.y, pb.x - pa.x)
        ln = (pb - pa).length
        m = Matrix.Translation(V((mid.x, mid.y, z1b + 0.8))) @ Matrix.Rotation(ang, 4, "Z") \
            @ Matrix.Translation((0, -1.2, 0))
        sal.hazard(-ln / 2 + 1.0, ln / 2 - 1.0, 2.0, 0.0, 0.08, matrix=m,
                   cols=("yellow", "dark"), pitch=2.4)
    # Tier 3: command block with an amber window band and roof plant
    r2, _, z2 = TIERS[2]
    for k in range(8):
        ang = math.radians(45 * k)
        c = V((math.cos(ang), math.sin(ang), 0)) * (apothem(r2) + 0.05)
        sal.box(V((c.x, c.y, z2 - 2.5)), (0.2, 7.0, 1.0), "window", rot_z=ang, bevel=0.0)
    sal.box(V((-6.0, -4.0, z2 + 2.0)), (6.0, 5.0, 3.0), "armour", bevel=0.05)
    sal.box(V((5.0, -6.0, z2 + 1.5)), (4.0, 4.0, 2.0), "gun", bevel=0.05)
    sal.box(V((0, -10.0, z2 + 0.85)), (12.0, 0.4, 0.12), "yellow", bevel=0.0)
    for k in range(8):
        a = math.radians(22.5 + 45 * k)
        for (r, _, z) in TIERS[1:]:
            lights.box(V((math.cos(a) * (r - 0.8), math.sin(a) * (r - 0.8), z + 1.2)),
                       (0.8, 0.8, 0.8), "light", bevel=0.0)


def lattice_mast(p, base, top_z, w0, w1, mat="dark"):
    n = max(3, int((top_z - base.z) / 5.0))
    pts = []
    for k in range(n + 1):
        t = k / n
        w = w0 + (w1 - w0) * t
        z = base.z + (top_z - base.z) * t
        pts.append([base + V((dx * w, dy * w, z - base.z)) for dx, dy in
                    ((-1, -1), (1, -1), (1, 1), (-1, 1))])
    for c in range(4):
        for k in range(n):
            p.beam(pts[k][c], pts[k + 1][c], 0.6, 0.6, mat)
            p.beam(pts[k][c], pts[k + 1][(c + 1) % 4], 0.3, 0.3, mat)
    for k in range(1, n + 1):
        for c in range(4):
            p.beam(pts[k][c], pts[k][(c + 1) % 4], 0.35, 0.35, mat)
    return pts


def build_mast(sal, lights):
    top = 50.0
    pts = lattice_mast(sal, MAST, top, 3.2, 1.0)
    sal.box(MAST + V((0, 0, 0.8)), (9.0, 9.0, 1.6), "armour", bevel=0.05)
    sal.cyl(V((MAST.x, MAST.y, top + 5.0)), 0.25, 0.1, 10.0, "metal", segs=6)
    lights.box(V((MAST.x, MAST.y, top + 10.3)), (1.2, 1.2, 1.2), "light", bevel=0.0)
    for k in (len(pts) // 3, 2 * len(pts) // 3):
        z = pts[k][0].z
        sal.box(V((MAST.x, MAST.y, z)), (14.0, 1.0, 0.8), "gun", bevel=0.0)
        for sx in (-1, 1):
            lights.box(V((MAST.x + sx * 7.2, MAST.y, z)), (0.8, 0.8, 0.8), "light", bevel=0.0)
            sal.box(V((MAST.x + sx * 6.0, MAST.y, z - 1.8)), (0.2, 0.6, 3.6), "yellow",
                    bevel=0.0)
    # dishes on stub arms
    zd = pts[len(pts) // 2][0].z
    parts.dish(sal, V((MAST.x - 5.5, MAST.y - 1.0, zd)), 4.0, (-0.6, -0.5, 0.6), "metal", "dark",
               depth=1.2, segs=14)
    sal.beam(V((MAST.x - 1.5, MAST.y, zd)), V((MAST.x - 5.0, MAST.y - 1.0, zd)), 0.6, 0.6,
             "dark")
    zd2 = pts[len(pts) // 4][0].z
    parts.dish(sal, V((MAST.x + 5.0, MAST.y + 1.0, zd2)), 3.0, (0.6, 0.3, 0.7), "metal", "dark",
               depth=0.9, segs=12)
    sal.beam(V((MAST.x + 2.0, MAST.y, zd2)), V((MAST.x + 4.6, MAST.y + 1.0, zd2)), 0.6, 0.6,
             "dark")


def build_platform(sal, lights, ang_deg, radius):
    a = math.radians(ang_deg)
    d = V((math.cos(a), math.sin(a), 0))
    side = V((-d.y, d.x, 0))
    c = d * radius
    pz = 0.0
    # Armoured arm from the core to the pad: box girder with yellow stripe
    start = d * (apothem(TIERS[0][0]) - 2.0)
    for s in (-1, 1):
        sal.beam(start + side * s * 2.2 + V((0, 0, pz - 1.0)), c + side * s * 2.2
                 + V((0, 0, pz - 1.0)), 1.6, 2.4, "gun")
    for k in range(6):
        t0 = 0.1 + k * 0.14
        q0 = start.lerp(c, t0)
        q1 = start.lerp(c, t0 + 0.14)
        sal.beam(q0 + side * 2.2 + V((0, 0, pz - 2.0)), q1 - side * 2.2 + V((0, 0, pz - 2.0)),
                 0.5, 0.5, "dark")
    sal.beam(start + V((0, 0, pz + 0.3)), c + V((0, 0, pz + 0.3)), 1.2, 0.2, "yellow")
    # Octagonal pad, hazard rim
    R = 11.0
    sal.slab(octagon(R, c.x, c.y), pz - 3.0, pz + 0.5, "armour")
    sal.slab(octagon(R - 3.0, c.x, c.y), pz - 5.0, pz - 3.0, "dark")
    for k in range(8):
        a0 = math.radians(22.5 + 45 * k)
        a1 = math.radians(22.5 + 45 * (k + 1))
        pa = V((c.x + math.cos(a0) * (R - 1.0), c.y + math.sin(a0) * (R - 1.0), 0))
        pb = V((c.x + math.cos(a1) * (R - 1.0), c.y + math.sin(a1) * (R - 1.0), 0))
        mid = (pa + pb) / 2
        e = math.atan2(pb.y - pa.y, pb.x - pa.x)
        ln = (pb - pa).length
        sal.hazard(-ln / 2, ln / 2, 1.4, 0.0, 0.08,
                   matrix=Matrix.Translation(V((mid.x, mid.y, pz + 0.5))) @ Matrix.Rotation(
                       e, 4, "Z"), cols=("yellow", "dark"), pitch=1.4)
        if k % 2 == 0:
            lights.box(V((c.x + math.cos(a0) * R, c.y + math.sin(a0) * R, pz + 0.9)),
                       (0.8, 0.8, 0.8), "light", bevel=0.0)
    # Twin heavy turret, barrels outward
    t = c + V((0, 0, pz + 0.5))
    sal.cyl(t + V((0, 0, 0.7)), 5.0, 5.2, 1.4, "dark", segs=16)
    sal.box(t + V((0, 0, 2.8)) - d * 0.5, (7.0, 7.5, 3.0), "gun", rot_z=a - math.pi / 2,
            bevel=0.12)
    sal.box(t + V((0, 0, 4.4)) - d * 0.8, (5.6, 4.0, 0.3), "armour", rot_z=a - math.pi / 2,
            bevel=0.0)
    m = Matrix.Translation(t + V((0, 0, 4.36)) - d * 2.5) @ Matrix.Rotation(a - math.pi / 2, 4,
                                                                             "Z")
    sal.hazard(-2.6, 2.6, 1.0, 0.0, 0.06, matrix=m, cols=("yellow", "dark"), pitch=0.9)
    for s in (-1, 1):
        b0 = t + V((0, 0, 3.0)) + side * s * 1.5 + d * 3.0
        b1 = b0 + d * 11.0 + V((0, 0, 1.0))
        sal.tube(b0, b1, 0.6, 0.45, "gun", segs=10)
        sal.tube(b0, b0 + d * 2.0, 0.9, 0.9, "armour", segs=10)
        sal.tube(b1 - d * 1.2, b1 + d * 0.2, 0.7, 0.7, "dark", segs=8)
        sal.tube(b0 + d * 4.0, b0 + d * 4.6, 0.75, 0.75, "yellow", segs=10)
    lights.box(t + V((0, 0, 4.9)) - d * 3.0, (0.7, 0.7, 0.7), "light", bevel=0.0)


def build_fortress():
    rng = random.Random(SEED)
    build_materials()
    root = parts.make_root("syndicate_fortress", size=20)
    shell = build_shell(root, rng)
    sal = parts.Part("den_salvage", MATS)
    glow = parts.Part("den_hangar_glow", MATS)
    lights = parts.Part("den_lights", MATS)
    build_hangar(sal, glow, lights)
    build_core_detail(sal, lights)
    build_mast(sal, lights)
    for ang, rad in PLATFORMS:
        build_platform(sal, lights, ang, rad)
    objs = [shell] + [p.finish(root) for p in (sal, glow, lights)]
    parts.add_empty("spawn_point", root, SPAWN_POS, rot_z=math.pi, size=6)
    return root, objs


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_fortress()
    parts.print_stats(objs)
    parts.save_blend(os.path.join(common.ROOT, "blender", "syndicate_fortress.blend"))
    common.export_glb(root, OUT)
    if "--no-preview" not in argv:
        common.setup_preview(cam_loc=(-135, -225, 240), cam_target=(0, -8, 0), ortho_scale=215,
                             res=(1600, 1200), key_dir=(-0.6, -0.35, 0.7), key_energy=3.5)
        common.render(os.path.join(common.PREVIEW_DIR, "syndicate_fortress_preview.png"))


main()
