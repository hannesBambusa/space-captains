"""Merc ship concept sheet: 4 non-aircraft designs, previews only (no .glb export).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python /Users/hannesalm/code/games/space-majesty/blender/gen_merc_concepts.py

Writes blender/previews/merc_concepts.png (3/4 view) and merc_concepts_top.png
(straight top-down, ~120 px per ship). Blender Z up, guns face +Y.
  A gyroscope: armoured sphere in a 3-ring gimbal, inner ring is the drive.
  B crystal: asymmetric cluster of faceted basalt columns with glowing seams,
    a floating weapon shard beside it.
  C sail: hub under a big backward-tilted petal sail, 3 radial gun arms.
  D honeycomb: 7-cell hex frame of bolted pods/tanks, turret on top, hover pads.
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
from parts import ALONG_Y, V, rot  # noqa: E402
from mathutils import Matrix  # noqa: E402

MATS = {}
SPACING = 20.0


def build_materials():
    m = common.make_material
    MATS["steel"] = m("merc_hull_steel", (0.17, 0.19, 0.22), roughness=0.5, metallic=0.5)
    MATS["steel2"] = m("merc_plate_steel_light", (0.31, 0.33, 0.37), roughness=0.5, metallic=0.35)
    MATS["gun"] = m("merc_gunmetal", (0.13, 0.14, 0.16), roughness=0.38, metallic=0.7)
    MATS["dark"] = m("merc_structure_dark", (0.06, 0.065, 0.07), roughness=0.55, metallic=0.5)
    MATS["red"] = m("merc_accent_red", (0.42, 0.02, 0.025), roughness=0.4, metallic=0.1)
    MATS["orange"] = m("merc_accent_orange", (0.85, 0.28, 0.03), roughness=0.45, metallic=0.0)
    MATS["window"] = m("merc_window_warm", (1.0, 0.85, 0.6), roughness=0.3,
                       emission=(1.0, 0.78, 0.5), emission_strength=3.5)
    MATS["light"] = m("merc_light_orange", (1.0, 0.45, 0.1), roughness=0.3,
                      emission=(1.0, 0.42, 0.08), emission_strength=5.0)
    MATS["glow"] = m("merc_engine_glow", (0.8, 0.95, 1.0), roughness=0.2,
                     emission=(0.65, 0.92, 1.0), emission_strength=5.0)
    MATS["membrane"] = m("merc_sail_membrane", (0.3, 0.7, 0.9), roughness=0.3,
                         emission=(0.3, 0.8, 1.0), emission_strength=0.8)
    MATS["label"] = m("concept_label", (1, 1, 1), emission=(1, 1, 1), emission_strength=2.0)


def twin_gun(p, base, direction, length=2.6, spread=0.32, z=0.0):
    """Small turret: round base, boxy mantlet, two barrels along `direction` (XY unit)."""
    d = V((direction[0], direction[1], 0)).normalized()
    side = V((-d.y, d.x, 0))
    p.cyl(base, 0.9, 0.8, 0.4, "gun", segs=12)
    p.cyl(base + V((0, 0, 0.25)), 0.7, 0.6, 0.12, "red", segs=12)
    a = math.atan2(d.y, d.x)
    p.box(base + V((0, 0, 0.6)) + d * 0.2, (1.3, 1.1, 0.6), "steel", rot_z=a, bevel=0.15)
    for s in (-1, 1):
        o = base + V((0, 0, 0.6 + z)) + side * (s * spread)
        p.tube(o + d * 0.6, o + d * length, 0.13, 0.13, "dark", segs=8)
        p.tube(o + d * (length - 0.45), o + d * length, 0.2, 0.2, "gun", segs=8)
        p.tube(o + d * length, o + d * (length + 0.04), 0.1, 0.1, "light", segs=8)


# ---------------------------------------------------------------- A gyroscope
def build_gyro():
    p = parts.Part("A_gyro", MATS)
    zc = 1.0
    c = V((0, 0, zc))
    # Armoured core sphere with a red equator belt and lit portholes
    p.sphere(c, 2.4, "steel", segs=20, rings=12)
    p.cyl(c, 2.5, 2.5, 0.55, "red", segs=24)
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        p.box(c + V((2.52 * math.cos(a), 2.52 * math.sin(a), 0)), (0.12, 0.45, 0.25),
              "window", rot_z=a, bevel=0.0)
    p.cyl(c + V((0, 0, 2.3)), 1.1, 0.9, 0.35, "steel2", segs=12)
    p.cyl(c + V((0, 0, 2.5)), 0.5, 0.5, 0.25, "light", segs=8)
    p.cyl(c + V((0, 0, -2.3)), 1.0, 0.8, 0.3, "gun", segs=12)
    # Gimbal: middle ring pivots in the outer frame on Y, inner (drive) ring pivots in
    # the middle ring on X', sphere pivots in the inner ring.
    m_mid = rot(ry=math.radians(38))
    m_in = m_mid @ rot(rx=math.radians(62))
    r_in, r_mid, r_out = 3.6, 5.2, 7.0
    p.torus(c, r_in, 0.34, "steel2", segs=32, minor_segs=6, matrix=m_in)
    p.torus(c, r_in - 0.3, 0.16, "glow", segs=32, minor_segs=6, matrix=m_in)
    p.torus(c, r_in + 0.3, 0.12, "red", segs=32, minor_segs=4, matrix=m_in)
    p.torus(c, r_mid, 0.3, "gun", segs=36, minor_segs=4, matrix=m_mid)
    p.torus(c, r_mid - 0.25, 0.1, "glow", segs=36, minor_segs=4, matrix=m_mid)
    ax_y = (m_in.to_3x3() @ V((0, 1, 0))).normalized()
    ax_x = (m_mid.to_3x3() @ V((1, 0, 0))).normalized()
    for s in (-1, 1):
        p.tube(c + ax_y * s * 2.2, c + ax_y * s * (r_in - 0.1), 0.35, 0.3, "gun", segs=8)
        p.tube(c + ax_x * s * (r_in + 0.1), c + ax_x * s * (r_mid - 0.1), 0.32, 0.32, "steel",
               segs=8)
        p.sphere(c + ax_x * s * r_in, 0.5, "red", segs=8, rings=4)
        p.tube(c + V((0, s * (r_mid + 0.1), 0)), c + V((0, s * (r_out - 0.4), 0)), 0.35, 0.35,
               "steel", segs=8)
        p.sphere(c + V((0, s * r_mid, 0)), 0.5, "red", segs=8, rings=4)
    # Outer frame: horizontal segmented armour ring
    gap = math.radians(3)
    for k in range(12):
        a0 = k * math.pi / 6 + gap
        a1 = a0 + math.pi / 6 - 2 * gap
        p.ring_segment(c, r_out - 0.5, r_out + 0.55, a0, a1, -0.35, 0.35, "steel2", steps=1)
        p.ring_segment(c, r_out - 0.3, r_out + 0.35, a0 + 0.03, a1 - 0.03, 0.35, 0.45,
                       "red" if k % 3 == 0 else "gun", steps=1)
        if k % 3 == 1:
            am = (a0 + a1) / 2
            p.box(c + V(((r_out + 0.56) * math.cos(am), (r_out + 0.56) * math.sin(am), 0)),
                  (0.2, 0.6, 0.3), "light", rot_z=am, bevel=0.0)
    p.ring_segment(c, r_out - 0.62, r_out - 0.45, 0, 2 * math.pi, -0.25, 0.25, "glow", steps=36)
    # Under-frame drive emitters, 4 glowing discs
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        q = c + V((r_out * math.cos(a), r_out * math.sin(a), -0.55))
        p.cyl(q, 0.75, 0.55, 0.3, "dark", segs=10)
        p.cyl(q + V((0, 0, -0.18)), 0.5, 0.5, 0.06, "glow", segs=10)
    # Guns: two turrets on the frame's forward shoulders, sensor block aft
    for a in (math.radians(60), math.radians(120)):
        twin_gun(p, c + V((r_out * math.cos(a), r_out * math.sin(a), 0.45)), (0, 1), length=2.2)
    p.box(c + V((0, -r_out, 0.6)), (1.4, 0.9, 0.5), "steel", bevel=0.15)
    p.cyl(c + V((0, -r_out, 1.2)), 0.05, 0.05, 1.0, "dark", segs=4)
    p.box(c + V((0, -r_out, 1.75)), (0.18, 0.18, 0.18), "light", bevel=0.0)
    return [p]


# ---------------------------------------------------------------- B crystal
def column(p, rng, base, az, el, length, r, cap_mat, sides=6):
    d = V((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))
    up = V((0, 0, 1))
    u = d.cross(up).normalized()
    w = u.cross(d).normalized()
    spin = rng.uniform(0, 6.3)

    def ring(t, rad, jit=0.12):
        pts = []
        for i in range(sides):
            a = spin + 2 * math.pi * i / sides
            rr = rad * (1 + rng.uniform(-jit, jit))
            pts.append(base + d * (t * length) + (u * math.cos(a) + w * math.sin(a)) * rr)
        return pts

    parts.part_hull(p, ring(0.0, r * 1.05) + ring(0.5, r), "steel")
    parts.part_hull(p, ring(0.47, r * 0.82, 0.0) + ring(0.6, r * 0.82, 0.0), "glow")
    parts.part_hull(p, ring(0.57, r * 0.97) + ring(0.9, r * 0.92), "steel2")
    # Blunt, slanted end facet (never a point)
    parts.part_hull(p, ring(0.87, r * 0.9, 0.05) + ring(1.0, r * 0.55, 0.2), cap_mat)
    return base + d * length


def build_crystal():
    p = parts.Part("B_crystal", MATS)
    rng = random.Random(7)
    # Monolith: a thick gem-cut slab split in two by a glowing crack. Each half is a
    # lower pavilion, a glowing girdle seam and an upper crown with a slanted table.
    halves = [
        ([(-6.6, -1.8), (-4.0, -4.3), (0.2, -4.0), (-1.1, 3.5), (-5.2, 3.7)], 0.0, 2.0, "steel"),
        ([(0.9, -3.9), (3.6, -3.7), (7.0, -0.6), (5.4, 3.1), (-0.3, 3.5)], 0.45, 3.4, "gun"),
    ]
    for outline, lift, h, mat in halves:
        cx = sum(x for x, _ in outline) / len(outline)
        cy = sum(y for _, y in outline) / len(outline)

        def ring(k, z, tilt=0.0):
            return [V((cx + (x - cx) * k, cy + (y - cy) * k, z + lift + tilt * (x - cx)))
                    for x, y in outline]

        parts.part_hull(p, ring(0.72, -1.4) + ring(1.0, -0.2), "dark")
        parts.part_hull(p, ring(0.97, -0.22) + ring(0.97, 0.22), "glow")
        parts.part_hull(p, ring(1.0, 0.2) + ring(0.62, h, tilt=0.12), mat)
        parts.part_hull(p, ring(0.4, h + 0.25, tilt=0.12) + ring(0.5, h + 0.05, tilt=0.12), "red")
        for x, y in outline:
            p.box(V((x, y, lift)), (0.4, 0.4, 0.5), "light", bevel=0.0)
    # The crack: a glowing blade standing in the gap between the halves
    parts.part_hull(p, [V((0.55, -3.9, -1.0)), V((-0.7, 3.5, -1.0)),
                        V((0.45, -3.4, 2.4)), V((-0.6, 3.0, 2.4)),
                        V((0.7, -3.9, -1.0)), V((-0.55, 3.5, -1.0))], "glow")
    p.cyl(V((0.5, -0.2, -1.5)), 2.2, 2.2, 0.06, "glow", segs=7)
    # Orbiting debris fragments with glow cores
    for k, (x, y, z, r) in enumerate(((-7.3, 2.6, 2.0, 0.7), (7.2, -3.0, 2.4, 0.6),
                                      (-2.5, -6.0, 1.5, 0.55))):
        p.rock(V((x, y, z)), r, "steel" if k % 2 else "gun", rng)
        p.sphere(V((x, y, z - r - 0.3)), 0.18, "glow", segs=8, rings=4)
    # Floating weapon shard: separate blunt prism with an orange core, held in a glow halo
    s = parts.Part("B_shard", MATS)
    sc = V((0.2, 5.6, 4.0))
    ring_a = [sc + V((0.9 * math.cos(a), -1.6, 0.9 * math.sin(a)))
              for a in [i * math.pi / 3 for i in range(6)]]
    ring_b = [sc + V((0.65 * math.cos(a), 1.6, 0.65 * math.sin(a)))
              for a in [i * math.pi / 3 + 0.3 for i in range(6)]]
    parts.part_hull(s, ring_a + ring_b, "gun")
    parts.part_hull(s, [sc + V((0.4 * math.cos(a), 1.5, 0.4 * math.sin(a)))
                        for a in [i * math.pi / 3 for i in range(6)]]
                    + [sc + V((0.25 * math.cos(a), 2.4, 0.25 * math.sin(a)))
                       for a in [i * math.pi / 3 for i in range(6)]], "light")
    s.torus(sc, 1.5, 0.1, "glow", segs=20, minor_segs=4, matrix=rot(rx=math.pi / 2))
    s.torus(sc + V((0, -1.0, 0)), 1.25, 0.08, "red", segs=20, minor_segs=4,
            matrix=rot(rx=math.pi / 2))
    for k in range(3):
        a = k * 2 * math.pi / 3
        s.sphere(sc + V((2.1 * math.cos(a), 0.3, 2.1 * math.sin(a))), 0.22, "glow", segs=8,
                 rings=4)
    return [p, s]


# ---------------------------------------------------------------- C sail
def build_sail():
    p = parts.Part("C_sail", MATS)
    hub = V((0, 0, 0.6))
    # Hexagonal hub drum
    hexp = [(2.0 * math.cos(a), 2.0 * math.sin(a)) for a in [i * math.pi / 3 for i in range(6)]]
    p.slab(hexp, -0.9, 1.0, "steel", matrix=Matrix.Translation(hub))
    p.slab([(x * 1.05, y * 1.05) for x, y in hexp], 0.1, 0.5, "red", matrix=Matrix.Translation(hub))
    p.cyl(hub + V((0, 0, -1.2)), 1.3, 0.9, 0.6, "gun", segs=12)
    # Sail: 14 petals on a shallow cone, the whole dish tipped to face up and back
    m = Matrix.Translation(hub + V((0, -0.6, 1.6))) @ rot(rx=math.radians(-22))
    n = 14
    r0, r1 = 1.6, 7.6
    cone = 0.32  # z rise per metre of radius

    def pt(r, a, dz=0.0):
        return m @ V((r * math.cos(a), r * math.sin(a), r * cone + dz))

    for i in range(n):
        a0 = 2 * math.pi * i / n + 0.035
        a1 = 2 * math.pi * (i + 1) / n - 0.035
        am = (a0 + a1) / 2
        quad = [pt(r0, a0), pt(r1, a0 + 0.02), pt(r1 + 0.4, am), pt(r1, a1 - 0.02), pt(r0, a1)]
        verts = [p.bm.verts.new(v) for v in quad]
        f = p.bm.faces.new(verts)
        f.material_index = p.mi("membrane")
        back = [p.bm.verts.new(v + (m.to_3x3() @ V((0, 0, -0.08)))) for v in reversed(quad)]
        f2 = p.bm.faces.new(back)
        f2.material_index = p.mi("dark")
        # Rib between petals
        ar = 2 * math.pi * i / n
        p.beam(pt(r0 - 0.2, ar, 0.05), pt(r1 + 0.3, ar, 0.05), 0.22, 0.25, "steel2")
        if i % 2 == 0:
            p.box(pt(r1 + 0.35, ar, 0.1), (0.35, 0.35, 0.35), "light", bevel=0.0)
    # Rim and inner collar
    rim_c = m @ V((0, 0, r1 * cone))
    p.torus(rim_c, r1 + 0.05, 0.2, "red", segs=42, minor_segs=4, matrix=m.to_3x3().to_4x4())
    p.torus(m @ V((0, 0, r0 * cone)), r0, 0.35, "gun", segs=14, minor_segs=6,
            matrix=m.to_3x3().to_4x4())
    # Focal emitter on a tripod above the dish centre
    focus = m @ V((0, 0, 4.2))
    for k in range(3):
        a = k * 2 * math.pi / 3 + 0.5
        p.beam(m @ V((3.8 * math.cos(a), 3.8 * math.sin(a), 3.8 * cone)), focus, 0.15, 0.15,
               "dark")
    p.sphere(focus, 0.6, "glow", segs=12, rings=6)
    p.torus(focus, 0.95, 0.08, "orange", segs=16, minor_segs=4, matrix=m.to_3x3().to_4x4())
    # Three radial gun arms from the hub, under the sail
    for k in range(3):
        a = math.pi / 2 + k * 2 * math.pi / 3
        d = V((math.cos(a), math.sin(a), 0))
        p.beam(hub + d * 1.6, hub + d * 4.6, 0.6, 0.5, "gun")
        p.beam(hub + d * 1.8 + V((0, 0, 0.3)), hub + d * 4.2 + V((0, 0, 0.3)), 0.3, 0.1, "red")
        twin_gun(p, hub + d * 5.0 + V((0, 0, -0.5)), (d.x, d.y), length=2.4)
    return [p]


# ---------------------------------------------------------------- D honeycomb
def build_comb():
    p = parts.Part("D_comb", MATS)
    R = 2.6
    pitch = math.sqrt(3) * R
    cells = [V((0, 0, 0))] + [V((pitch * math.cos(math.radians(30 + 60 * k)),
                                 pitch * math.sin(math.radians(30 + 60 * k)), 0))
                              for k in range(6)]
    zt, zb = 1.0, -0.6
    edges = {}
    for cc in cells:
        corners = [cc + V((R * math.cos(math.radians(60 * i)), R * math.sin(math.radians(60 * i)), 0))
                   for i in range(6)]
        for i in range(6):
            a, b = corners[i], corners[(i + 1) % 6]
            key = tuple(sorted([tuple(round(x, 2) for x in a), tuple(round(x, 2) for x in b)]))
            edges[key] = (a, b)
    corners_all = {}
    for a, b in edges.values():
        for q in (a, b):
            corners_all[tuple(round(x, 2) for x in q)] = q
        p.beam(a + V((0, 0, zt)), b + V((0, 0, zt)), 0.32, 0.32, "gun")
        p.beam(a + V((0, 0, zb)), b + V((0, 0, zb)), 0.32, 0.32, "dark")
    outer = []
    for q in corners_all.values():
        p.beam(q + V((0, 0, zb)), q + V((0, 0, zt)), 0.4, 0.4, "steel2")
        p.box(q + V((0, 0, zt + 0.1)), (0.5, 0.5, 0.2), "dark", bevel=0.0)
        if q.length > 6.5:
            outer.append(q)
    # Outer-corner emitter nodes (station-keeping), every second one lit orange
    for i, q in enumerate(sorted(outer, key=lambda v: math.atan2(v.y, v.x))):
        if i % 2 == 0:
            p.sphere(q + V((0, 0, zt + 0.4)), 0.3, "light", segs=8, rings=4)
    # Modules, one per cell
    c0, cells_o = cells[0], cells[1:]
    hexp = [(2.1 * math.cos(a), 2.1 * math.sin(a)) for a in [i * math.pi / 3 for i in range(6)]]
    p.slab(hexp, -0.5, 1.9, "steel", matrix=Matrix.Translation(c0))
    p.slab([(x * 0.8, y * 0.8) for x, y in hexp], 1.9, 2.1, "red", matrix=Matrix.Translation(c0))
    for k in range(6):
        a = k * math.pi / 3 + math.pi / 6
        p.box(c0 + V((1.83 * math.cos(a), 1.83 * math.sin(a), 1.3)), (0.08, 0.7, 0.2), "window",
              rot_z=a, bevel=0.0)
    twin_gun(p, c0 + V((0, 0, 2.15)), (0, 1), length=3.2, spread=0.38)
    # cell 1 (front-right): vertical tank
    q = cells_o[0]
    p.cyl(q + V((0, 0, 0.6)), 1.8, 1.8, 2.6, "steel2", segs=16)
    p.cyl(q + V((0, 0, 2.0)), 1.5, 1.0, 0.3, "gun", segs=16)
    p.cyl(q + V((0, 0, 1.2)), 1.85, 1.85, 0.4, "red", segs=16)
    # cell 2 (front): open cell with glowing drive core
    q = cells_o[1]
    p.torus(q + V((0, 0, 0.2)), 1.5, 0.25, "gun", segs=20, minor_segs=6)
    p.sphere(q + V((0, 0, 0.2)), 0.95, "glow", segs=14, rings=7)
    for k in range(3):
        a = k * 2 * math.pi / 3
        p.beam(q + V((0, 0, 0.2)) + V((math.cos(a), math.sin(a), 0)) * 1.1,
               q + V((0, 0, 0.2)) + V((math.cos(a), math.sin(a), 0)) * 2.2, 0.2, 0.2, "dark")
    # cell 3 (front-left): spherical tank with orange band
    q = cells_o[2]
    p.sphere(q + V((0, 0, 0.4)), 1.9, "steel", segs=16, rings=8)
    p.cyl(q + V((0, 0, 0.4)), 1.95, 1.95, 0.35, "orange", segs=16)
    # cell 4 (back-left): cargo container
    q = cells_o[3]
    p.box(q + V((0, 0, 0.5)), (3.0, 2.2, 2.0), "red", rot_z=math.radians(30), bevel=0.06)
    for t in (-1.0, 0.0, 1.0):
        d = V((math.cos(math.radians(30)), math.sin(math.radians(30)), 0))
        p.box(q + d * t + V((0, 0, 0.5)), (0.12, 2.3, 2.1), "dark", rot_z=math.radians(30),
              bevel=0.0)
    # cell 5 (back): twin horizontal capsules
    q = cells_o[4]
    for s in (-1, 1):
        p.tube(q + V((s * 0.8, -1.4, 0.4)), q + V((s * 0.8, 1.4, 0.4)), 0.75, 0.75, "steel2",
               segs=12)
        for e in (-1.4, 1.4):
            p.sphere(q + V((s * 0.8, e, 0.4)), 0.75, "steel2", segs=12, rings=6)
        p.cyl(q + V((s * 0.8, 0, 0.4)), 0.8, 0.8, 0.3, "red", segs=12, axis_rot=ALONG_Y)
    # cell 6 (back-right): radiator stack
    q = cells_o[5]
    p.box(q + V((0, 0, 0.0)), (2.4, 2.4, 1.0), "gun", bevel=0.1)
    for k in range(5):
        p.box(q + V((-1.0 + k * 0.5, 0, 1.0)), (0.1, 2.2, 1.0), "steel2", bevel=0.0)
    # Hover pads under every cell
    for cc in cells:
        p.cyl(cc + V((0, 0, zb - 0.4)), 1.4, 1.1, 0.4, "dark", segs=14)
        p.cyl(cc + V((0, 0, zb - 0.62)), 0.95, 0.95, 0.05, "glow", segs=14)
        p.torus(cc + V((0, 0, zb - 0.45)), 1.45, 0.08, "glow", segs=16, minor_segs=4)
    return [p]


# ---------------------------------------------------------------- scene
def label(text, loc, rot_euler, size):
    cu = bpy.data.curves.new("lbl_" + text, "FONT")
    cu.body = text
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    ob = bpy.data.objects.new("lbl_" + text, cu)
    ob.data.materials.append(MATS["label"])
    ob.location = loc
    ob.rotation_euler = rot_euler
    bpy.context.scene.collection.objects.link(ob)
    return ob


def main():
    common.reset_scene()
    build_materials()
    roots = []
    for i, (tag, fn) in enumerate((("A", build_gyro), ("B", build_crystal),
                                   ("C", build_sail), ("D", build_comb))):
        root = parts.make_root("concept_" + tag)
        root.location = ((i - 1.5) * SPACING, 0, 0)
        objs = [q.finish(root) for q in fn()]
        print("CONCEPT", tag)
        parts.print_stats(objs)
        roots.append((tag, root))

    # 3/4 view: camera in front (+Y) and above, ships yawed so we see front and side
    common.setup_preview(cam_loc=(0, 70, 55), cam_target=(0, 0, 0), ortho_scale=80,
                         res=(1600, 900), key_dir=(-0.4, 0.6, 0.7), key_energy=3.5)
    scene = bpy.context.scene
    cam = scene.camera
    for tag, root in roots:
        root.location.x = -root.location.x
        root.rotation_euler = (0, 0, math.radians(-150))
    labels = [label(tag, (root.location.x, 14, -5), cam.rotation_euler.copy(), 3.0)
              for tag, root in roots]
    common.render(os.path.join(common.PREVIEW_DIR, "merc_concepts.png"))

    # Top-down, small: ~120 px per ship
    for lb in labels:
        lb.hide_render = True
    for tag, root in roots:
        root.location.x = -root.location.x
        root.rotation_euler = (0, 0, 0)
        label(tag, (root.location.x - 8.5, 8.5, 5), (0, 0, 0), 2.2)
    cam.location = (0, 0, 60)
    cam.rotation_euler = (0, 0, 0)
    cam.data.ortho_scale = 84
    scene.render.resolution_x, scene.render.resolution_y = 640, 160
    common.render(os.path.join(common.PREVIEW_DIR, "merc_concepts_top.png"))


main()
