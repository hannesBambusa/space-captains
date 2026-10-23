"""Generate the mining outpost .glb and previews (3/4 view with a docked miner, top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python /Users/hannesalm/code/games/space-majesty/blender/gen_mining_outpost.py
  Add `-- --no-preview` to skip the PNG renders, `-- --no-textures` for flat materials.
Textures are baked by outpost_textures.py (Cycles, a few minutes) into blender/textures/
and embedded in the glb.

Design: an ore receiving yard. Ships back into an open-topped berth; a slewing crane
grabs ore out of the ship's hold and drops it into a big yellow intake hopper beside the
berth; an open cleated conveyor carries it up to a head house that feeds two silos (one
open-topped, showing its fill level); a processing block at the back refines it and a
gallery spills tailings onto an open stockpile bin on the left.

Layout (Blender Z up, exported +Y up; Blender -Y = Godot +Z). Centre at origin, plane z=0.
  berth    x -8..8 open bay, deck top z=-3, walls to z=3.7, mouth at y=-25 (Godot +Z)
  crane    pedestal on the +X wall at PIVOT, boom swings between ship hold and hopper
  hopper   centre HOPPER (x 18.5, y -15.8), rim z 6.8
  belt     hopper -> head house (y 9), silos at y 15.5 (x 13.8 closed, x 23.2 open)
  process  back centre x -8..8, y 6..20, corridor port on the back face at z 12
  stockpile open bin on -X (x -25..-13, y -22..-7), control tower at (-17, 3)
Hierarchy: mining_outpost (empty root)
  -> outpost_hangar (berth), outpost_silos (hopper, belt frame, silos), outpost_crane
     (pedestal), outpost_structure (process block, tower, stockpile), unload_arm,
     ore_conveyor_belt, ore_silo_fill, unload_lights,
     dock_point, spawn_point, link_point, ore_flow_point (empties).
dock_point / spawn_point are rotated 180 deg about up, so their Godot -Z (forward) points
out of the mouth (Godot world +Z). link_point is unrotated: Godot -Z points out the back.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import outpost_textures  # noqa: E402

OUT = os.path.join(common.ROOT, "assets", "models", "buildings", "mining_outpost.glb")
BLEND = os.path.join(common.ROOT, "blender", "mining_outpost.blend")
MINER_BLEND = os.path.join(common.ROOT, "blender", "miner.blend")

V = Vector
DOCK_POS = V((0.0, -14.0, 0.0))      # Blender coords = Godot (0, 0, 14)
SPAWN_POS = V((0.0, -32.0, 0.0))     # Godot (0, 0, 32)
LINK_POS = V((0.0, 24.1, 12.0))      # Godot (0, 12, -24.1)
BAY_Y0, BAY_Y1 = -25.0, 3.0          # berth mouth / back wall face
DECK_Z = -3.0
WALL_TOP = 3.7
HOLD = V((0.0, -15.8, 0.0))          # docked miner's ore hopper (ship local y 1.8, turned 180)
HOPPER = V((18.5, -15.8, 0.0))
PIVOT = V((9.25, -4.5, 7.7))         # crane slewing ring top; equidistant to HOLD and HOPPER
BELT0 = V((18.5, -13.2, -3.2))       # belt tail (under the hopper)
BELT1 = V((18.5, 9.0, 5.6))          # belt head (inside the head house)
SILO_A = V((13.8, 15.5, 0.0))        # closed silo
SILO_B = V((23.2, 15.5, 0.0))        # open-topped silo with the fill mesh
SILO_R = 3.6
FILL_Z0 = -3.0                       # open silo inner floor (ore_silo_fill origin)
ALONG_Y = Matrix.Rotation(-math.pi / 2, 4, "X")
ALONG_X = Matrix.Rotation(math.pi / 2, 4, "Y")
FRONT = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))

MATS = {}


def build_materials():
    m = common.make_material
    MATS["hull"] = m("outpost_hull_white", (0.78, 0.78, 0.76), roughness=0.45, metallic=0.1)
    MATS["hull2"] = m("outpost_hull_grey", (0.50, 0.52, 0.55), roughness=0.5, metallic=0.15)
    MATS["dark"] = m("outpost_structure_dark", (0.06, 0.065, 0.07), roughness=0.55, metallic=0.5)
    MATS["orange"] = m("outpost_accent_orange", (0.85, 0.28, 0.03), roughness=0.45)
    MATS["yellow"] = m("outpost_accent_yellow", (0.95, 0.62, 0.02), roughness=0.45)
    MATS["hazard"] = m("outpost_hazard", (0.8, 0.55, 0.02), roughness=0.5)
    MATS["pad"] = m("outpost_pad_deck", (0.15, 0.15, 0.16), roughness=0.7, metallic=0.2)
    MATS["ore"] = m("outpost_ore", (0.26, 0.15, 0.08), roughness=0.9)
    MATS["window"] = m("outpost_window_warm", (1.0, 0.85, 0.6), roughness=0.3,
                       emission=(1.0, 0.78, 0.5), emission_strength=3.5)
    MATS["light"] = m("outpost_light_orange", (1.0, 0.45, 0.1), roughness=0.3,
                      emission=(1.0, 0.42, 0.08), emission_strength=5.0)
    MATS["amber"] = m("outpost_unload_amber", (1.0, 0.62, 0.12), roughness=0.3,
                      emission=(1.0, 0.55, 0.06), emission_strength=8.0)
    MATS["belt"] = m("ore_belt", (0.05, 0.05, 0.05), roughness=0.8)


class Part:
    """One output mesh, one bmesh, named material slots. Writes the "panel" UV layer
    (metres in each primitive's frame) that the texture bake uses for plate layout."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.slots = []
        self.uv = self.bm.loops.layers.uv.new("panel")
        self.n_prims = 0

    def _offset(self):
        self.n_prims += 1
        k = self.n_prims
        return V(((k * 7) % 31 * 64.0, (k * 13) % 29 * 64.0))

    def mi(self, key):
        mat = MATS[key]
        if mat not in self.slots:
            self.slots.append(mat)
        return self.slots.index(mat)

    def _faces(self, verts):
        return list({f for v in verts for f in v.link_faces})

    def _planar_uv(self, faces, inv, shift):
        off = self._offset()
        rot = inv.to_3x3()
        for f in faces:
            f.normal_update()
            n = rot @ f.normal
            k = max(range(3), key=lambda i: abs(n[i]))
            a, b = ((1, 2), (0, 2), (0, 1))[k]
            for loop in f.loops:
                q = inv @ loop.vert.co + shift
                loop[self.uv].uv = (q[a] + off.x, q[b] + off.y)

    def box(self, center, size, mat, rot_z=0.0, bevel=0.0, frame=None):
        fr = Matrix.Translation(center) @ (frame if frame is not None else Matrix.Rotation(rot_z, 4, "Z"))
        m = fr @ Matrix.Diagonal((*size, 1.0))
        verts = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)["verts"]
        idx = self.mi(mat)
        faces = self._faces(verts)
        for f in faces:
            f.material_index = idx
        if bevel > 0:
            edges = list({e for v in verts for e in v.link_edges})
            res = bmesh.ops.bevel(self.bm, geom=verts + edges, offset=min(size) * bevel,
                                  segments=1, affect="EDGES", profile=0.5, clamp_overlap=True)
            for f in res["faces"]:
                f.material_index = idx
            faces = list({g for f in res["faces"] for v in f.verts for g in v.link_faces})
        self._planar_uv(faces, fr.inverted(), V(size) / 2)

    def beam(self, p0, p1, w, h, mat, up=V((0, 0, 1))):
        p0, p1 = V(p0), V(p1)
        d = p1 - p0
        x = d.normalized()
        if abs(x.dot(up)) > 0.99:
            up = V((1, 0, 0))
        z = (up - x * up.dot(x)).normalized()
        y = z.cross(x)
        rm = Matrix((x, y, z)).transposed().to_4x4()
        self.box((p0 + p1) / 2, (d.length, w, h), mat, frame=rm)

    def cyl(self, center, r1, r2, depth, mat, segs=12, axis_rot=None):
        m = Matrix.Translation(center)
        if axis_rot is not None:
            m = m @ axis_rot
        r = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segs,
                                  radius1=r1, radius2=r2, depth=depth, matrix=m)
        idx = self.mi(mat)
        faces = self._faces(r["verts"])
        for f in faces:
            f.material_index = idx
        inv = m.inverted()
        rot = inv.to_3x3()
        off = self._offset()
        rm, ra = max(r1, r2), (r1 + r2) / 2
        for f in faces:
            f.normal_update()
            pts = [inv @ lp.vert.co for lp in f.loops]
            if abs((rot @ f.normal).z) > 0.7:
                uvs = [(q.x + rm, q.y + rm) for q in pts]
            else:
                th = [math.atan2(q.y, q.x) for q in pts]
                if max(th) - min(th) > math.pi:
                    th = [t + 2 * math.pi if t < 0 else t for t in th]
                uvs = [(t * ra, q.z + depth / 2) for t, q in zip(th, pts)]
            for lp, uv in zip(f.loops, uvs):
                lp[self.uv].uv = (uv[0] + off.x, uv[1] + off.y)

    def tube(self, p0, p1, r1, r2, mat, segs=10):
        p0, p1 = V(p0), V(p1)
        d = p1 - p0
        q = d.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
        self.cyl((p0 + p1) / 2, r1, r2, d.length, mat, segs=segs, axis_rot=q)

    def slab(self, pts, z0, z1, mat, matrix=None):
        """Extrude a convex polygon (local XY) from z0 to z1."""
        m = matrix or Matrix()
        bot = [self.bm.verts.new(m @ V((x, y, z0))) for x, y in pts]
        top = [self.bm.verts.new(m @ V((x, y, z1))) for x, y in pts]
        idx = self.mi(mat)
        faces = [self.bm.faces.new(list(reversed(bot))), self.bm.faces.new(top)]
        n = len(pts)
        for i in range(n):
            j = (i + 1) % n
            faces.append(self.bm.faces.new((bot[i], bot[j], top[j], top[i])))
        for f in faces:
            f.material_index = idx
        self._planar_uv(faces, m.inverted(), V((0, 0, 0)))

    def rock(self, center, r, mat, rng, flat=0.75):
        m = Matrix.Translation(center) @ Matrix.Rotation(rng.uniform(0, 6.3), 4, "Z")
        m = m @ Matrix.Diagonal((r * rng.uniform(0.8, 1.3), r * rng.uniform(0.8, 1.2),
                                 r * rng.uniform(0.6, 0.9) * flat / 0.75, 1.0))
        verts = bmesh.ops.create_icosphere(self.bm, subdivisions=1, radius=1.0, matrix=m)["verts"]
        for v in verts:
            v.co += V((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * r * 0.15
        idx = self.mi(mat)
        faces = self._faces(verts)
        for f in faces:
            f.material_index = idx
        self._planar_uv(faces, Matrix.Translation(center).inverted(), V((0, 0, 0)))

    def mound(self, center, r, h, mat, rng, segs=14, rings=5, jitter=0.12):
        """Lumpy ore heap on a flat floor at center.z; top-projected panel UVs."""
        c = V(center)
        peak = self.bm.verts.new(c + V((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), h)))
        ring_vs = []
        for k in range(1, rings + 1):
            f = k / rings
            ring = []
            for i in range(segs):
                a = 2 * math.pi * (i + (0.5 if k % 2 else 0.0)) / segs
                rr = r * f * (1 + rng.uniform(-jitter, jitter))
                z = h * (1 - f ** 1.6) + (rng.uniform(-0.15, 0.15) * h * 0.3 if k < rings else 0.0)
                ring.append(self.bm.verts.new(c + V((rr * math.cos(a), rr * math.sin(a), max(z, 0.0)))))
            ring_vs.append(ring)
        idx = self.mi(mat)
        faces = []
        for i in range(segs):
            faces.append(self.bm.faces.new((peak, ring_vs[0][i], ring_vs[0][(i + 1) % segs])))
        for k in range(rings - 1):
            a, b = ring_vs[k], ring_vs[k + 1]
            for i in range(segs):
                faces.append(self.bm.faces.new((a[i], b[i], b[(i + 1) % segs], a[(i + 1) % segs])))
        faces.append(self.bm.faces.new(list(reversed(ring_vs[-1]))))
        for f in faces:
            f.material_index = idx
        off = self._offset()
        for f in faces:
            for lp in f.loops:
                q = lp.vert.co - c
                lp[self.uv].uv = (q.x + off.x, q.y + off.y)
        return lambda fr: h * (1 - fr ** 1.6)

    def lathe(self, profile, segs, mat_fn, matrix=None, start=0.0):
        """profile: list of (r, z). mat_fn(seg_i, edge_j) -> material key."""
        m = matrix or Matrix()
        rings = []
        for i in range(segs):
            a = start + 2 * math.pi * i / segs
            ca, sa = math.cos(a), math.sin(a)
            rings.append([self.bm.verts.new(m @ V((r * ca, r * sa, z))) for r, z in profile])
        off = self._offset()
        s_len = [0.0]
        for j in range(len(profile) - 1):
            s_len.append(s_len[-1] + math.hypot(profile[j + 1][0] - profile[j][0],
                                                profile[j + 1][1] - profile[j][1]))
        r_max = max(r for r, _ in profile)
        chunk = max(1, round(segs / max(1, round(2 * math.pi * r_max / 12.0))))
        for i in range(segs):
            a, b = rings[i], rings[(i + 1) % segs]
            cu = off.x + (i // chunk) * 64.0
            for j in range(len(profile) - 1):
                if profile[j][0] < 1e-4 and profile[j + 1][0] < 1e-4:
                    continue
                n_pl = max(1, round(math.pi * (profile[j][0] + profile[j + 1][0]) / 2.0))
                u0, u1 = i / segs * n_pl * 2.0 + cu, (i + 1) / segs * n_pl * 2.0 + cu
                v0, v1 = s_len[j] + off.y, s_len[j + 1] + off.y
                if profile[j][0] < 1e-4:
                    vs, uvs = (a[j], b[j + 1], a[j + 1]), ((u0, v0), (u1, v1), (u0, v1))
                elif profile[j + 1][0] < 1e-4:
                    vs, uvs = (a[j], b[j], a[j + 1]), ((u0, v0), (u1, v0), (u0, v1))
                else:
                    vs = (a[j], b[j], b[j + 1], a[j + 1])
                    uvs = ((u0, v0), (u1, v0), (u1, v1), (u0, v1))
                f = self.bm.faces.new(vs)
                f.material_index = self.mi(mat_fn(i, j))
                for lp, uv in zip(f.loops, uvs):
                    lp[self.uv].uv = uv
        axis = [v for ring in rings for v, (r, _) in zip(ring, profile) if r < 1e-4]
        if axis:
            bmesh.ops.remove_doubles(self.bm, verts=axis, dist=1e-3)

    def finish(self, parent):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        for f in bm.faces:
            f.smooth = True
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        for s in self.slots:
            mesh.materials.append(s)
        mesh.set_sharp_from_angle(angle=math.radians(32))
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj.parent = parent
        return obj


def beacon_base(p, c):
    """Dark housing an unload beacon lens sits on (lens top-centre at c + 0.3 z)."""
    p.box(c + V((0, 0, 0.12)), (0.9, 0.9, 0.25), "dark")


# Unload beacon positions (housing bottom centre). Lenses go into unload_lights.
BEACONS = []


def add_beacon(p, c):
    c = V(c)
    beacon_base(p, c)
    BEACONS.append(c + V((0, 0, 0.25)))


# ---------------------------------------------------------------- berth
def build_hangar(rng):
    p = Part("outpost_hangar")
    y0, y1 = BAY_Y0, BAY_Y1
    cy, ln = (y0 + y1) / 2, y1 - y0
    # Deck and underside
    p.box(V((0, cy, DECK_Z - 1.0)), (16.0, ln, 2.0), "pad", bevel=0.04)
    p.box(V((0, cy, DECK_Z - 2.6)), (13.0, ln - 2, 1.2), "dark")
    for k in range(5):
        p.box(V((0, y0 + 3 + k * 5.5, DECK_Z - 3.5)), (15.0, 1.0, 0.8), "dark")
    # Side walls with walkway cap, hazard edge, inner light strip, outer buttresses
    for sx in (-1, 1):
        p.box(V((sx * 9.25, cy, -0.65)), (2.5, ln, 8.7), "hull", bevel=0.03)
        p.box(V((sx * 9.25, cy, WALL_TOP - 0.1)), (2.8, ln - 0.3, 0.3), "dark")
        p.box(V((sx * 8.2, cy, WALL_TOP + 0.08)), (0.6, ln - 0.3, 0.1), "hazard")
        p.box(V((sx * 7.97, cy, -0.6)), (0.08, ln - 2, 2.4), "dark")
        p.box(V((sx * 7.93, cy, -0.6)), (0.06, ln - 4, 0.3), "light")
        p.box(V((sx * 7.97, cy, 2.2)), (0.08, ln - 2, 0.5), "hull2")
        for k in range(5):
            p.box(V((sx * 10.8, y0 + 3 + k * 5.5, -1.3)), (0.9, 1.3, 8.6), "dark")
        p.box(V((sx * 10.55, cy + 1, 1.6)), (0.1, ln - 8, 0.45), "window")
        p.box(V((sx * 10.55, cy + 1, 2.6)), (0.12, ln - 6, 0.35), "orange")
    # Mouth pylons with hazard faces, glowing inner edges, beacon housings on top
    for sx in (-1, 1):
        px = sx * 9.5
        p.box(V((px, y0 - 0.6, 0.75)), (3.4, 1.6, 11.5), "hull2", bevel=0.04)
        p.box(V((px, y0 - 1.45, 4.3)), (3.42, 0.12, 2.8), "hazard")
        p.box(V((px, y0 - 1.45, -2.3)), (3.42, 0.12, 1.8), "hazard")
        p.box(V((sx * 7.78, y0 - 0.6, 0.6)), (0.1, 1.0, 9.6), "window")
        p.box(V((px, y0 - 0.6, 6.6)), (3.0, 1.4, 0.2), "dark")
        add_beacon(p, V((px, y0 - 0.6, 6.7)))
        p.box(V((px + sx * 1.2, y0 - 0.6, 7.0)), (0.5, 0.5, 0.5), "light")
    # Deck markings: mouth hazard band, guide lines, stop bar, lead-in lights
    p.box(V((0, y0 + 0.8, DECK_Z + 0.03)), (16.0, 1.4, 0.06), "hazard")
    for sx in (-1, 1):
        p.box(V((sx * 3.0, cy + 1.0, DECK_Z + 0.03)), (0.3, ln - 5, 0.05), "yellow")
    p.box(V((0, -5.6, DECK_Z + 0.03)), (6.3, 0.5, 0.05), "yellow")
    p.box(V((0, -4.6, DECK_Z + 0.03)), (6.3, 0.5, 0.05), "hazard")
    for k in range(4):
        p.box(V((0, y0 + 2.4 + k * 1.6, DECK_Z + 0.05)), (1.0, 0.5, 0.1), "light")
    # Docking cradles under the ship
    for sx in (-1, 1):
        for yy in (-17.5, -10.5):
            p.box(V((sx * 2.2, yy, DECK_Z + 0.6)), (1.0, 1.6, 1.2), "dark")
            p.box(V((sx * 2.2, yy, DECK_Z + 1.25)), (1.1, 1.7, 0.1), "yellow")
            p.beam(V((sx * 2.2, yy, DECK_Z + 0.3)), V((sx * 6.0, yy, DECK_Z + 0.1)), 0.4, 0.3, "dark")
    # Back wall: ore intake grate framed in hazard paint, control gallery windows
    p.box(V((0, y1 + 1.0, 0.7)), (21.0, 2.0, 11.4), "hull2", bevel=0.02)
    p.box(V((0, y1 - 0.05, -0.6)), (10.0, 0.1, 4.0), "dark")
    for k in range(9):
        p.box(V((-4 + k, y1 - 0.13, -0.6)), (0.18, 0.08, 3.8), "hull2")
    p.box(V((0, y1 - 0.08, 1.75)), (11.0, 0.1, 0.7), "hazard")
    p.box(V((0, y1 - 0.08, -2.85)), (11.0, 0.1, 0.4), "hazard")
    p.box(V((0, y1 - 0.08, 4.3)), (14.0, 0.1, 0.9), "window")
    p.box(V((0, y1 + 1.0, 6.5)), (21.4, 2.4, 0.3), "dark")
    for sx in (-1, 1):
        p.box(V((sx * 10.0, y1 + 1.0, 6.9)), (0.5, 0.5, 0.5), "light")
    # Beacon housings along the wall tops
    for sx in (-1, 1):
        for yy in (-19.0, -9.0):
            add_beacon(p, V((sx * 10.15, yy, WALL_TOP + 0.05)))
    return p


# ---------------------------------------------------------------- crane pedestal
def build_crane(rng):
    p = Part("outpost_crane")
    c = V((PIVOT.x, PIVOT.y, 0))
    p.box(c + V((0, 0, WALL_TOP + 0.25)), (3.4, 3.4, 0.5), "dark")
    p.cyl(c + V((0, 0, 4.6)), 1.55, 1.55, 0.5, "hull2", segs=16)
    p.cyl(c + V((0, 0, 5.9)), 1.25, 1.1, 2.6, "yellow", segs=16)
    p.cyl(c + V((0, 0, 6.3)), 1.18, 1.18, 0.5, "hazard", segs=16)
    p.cyl(c + V((0, 0, PIVOT.z - 0.25)), 1.7, 1.7, 0.5, "dark", segs=16)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        d = V((math.cos(a), math.sin(a), 0))
        p.beam(c + d * 1.6 + V((0, 0, WALL_TOP + 0.4)), c + d * 1.05 + V((0, 0, 6.8)), 0.25, 0.25, "dark")
    return p


# ---------------------------------------------------------------- unload arm (boom)
def arm_angle():
    d = HOLD - PIVOT
    return math.atan2(d.y, d.x)


def build_arm(rng):
    """Slewing boom, built in place at its rest pose (grab over the ship's hold).
    Local frame: X along the boom, Z up, origin at PIVOT (moved there after the bake)."""
    p = Part("unload_arm")
    ang = arm_angle()
    R = Matrix.Rotation(ang, 4, "Z")
    L = (V((HOLD.x, HOLD.y, 0)) - V((PIVOT.x, PIVOT.y, 0))).length

    def at(x, y, z):
        return PIVOT + R @ V((x, y, z))

    def ab(c, size, mat, bevel=0.0):
        p.box(at(*c), size, mat, frame=R, bevel=bevel)

    # Machinery house, operator cab, counterweight
    ab((-0.8, 0, 0.8), (4.4, 3.4, 1.6), "hull", bevel=0.05)
    ab((-0.8, 0, 1.62), (3.6, 2.6, 0.06), "dark")
    ab((1.3, 1.25, 0.65), (1.5, 1.2, 1.3), "hull2", bevel=0.05)
    ab((2.06, 1.25, 0.8), (0.05, 1.0, 0.5), "window")
    ab((1.3, 1.86, 0.8), (1.2, 0.05, 0.4), "window")
    ab((-3.9, 0, 0.7), (2.4, 3.2, 1.4), "hull2", bevel=0.05)
    ab((-3.9, 0, 1.42), (2.2, 3.0, 0.05), "hazard")
    # Boom: twin yellow chords, dark lacing, tip head
    for s in (-1, 1):
        p.beam(at(0.8, s * 0.65, 0.75), at(L + 0.6, s * 0.45, 0.75), 0.45, 0.9, "yellow")
    n = 8
    for k in range(n):
        x0 = 1.2 + (L - 1.0) * k / n
        x1 = 1.2 + (L - 1.0) * (k + 1) / n
        w0 = 0.65 - 0.2 * k / n
        for zz in (0.35, 1.15):
            p.beam(at(x0, w0, zz), at(x1, -w0, zz), 0.12, 0.12, "dark")
        p.beam(at(x1, -0.6, 0.75), at(x1, 0.6, 0.75), 0.14, 0.14, "dark")
    ab((L + 0.5, 0, 0.75), (1.4, 1.8, 1.1), "dark")
    ab((L + 0.5, 0, 1.33), (1.2, 1.6, 0.05), "hazard")
    ab((L + 1.0, 0, 0.75), (0.25, 0.4, 0.3), "light")
    ab((1.6, 0, 1.45), (0.4, 0.4, 0.3), "light")
    # Hoist trolley, cables, clamshell grab with a load of ore
    gx = L
    ab((gx, 0, 0.05), (1.3, 1.4, 0.5), "dark")
    for s in (-1, 1):
        p.tube(at(gx, s * 0.3, -0.2), at(gx, s * 0.3, -0.78), 0.05, 0.05, "dark", segs=4)
    ab((gx, 0, -0.9), (1.4, 0.9, 0.3), "yellow")
    side = Matrix.Translation(PIVOT) @ R @ FRONT
    for pts, mat in (([(gx - 1.4, -1.05), (gx, -1.05), (gx, -2.4), (gx - 0.7, -2.25)], "yellow"),
                     ([(gx, -1.05), (gx + 1.4, -1.05), (gx + 0.7, -2.25), (gx, -2.4)], "yellow")):
        p.slab(pts, -0.75, 0.75, mat, matrix=side)
    for i in range(5):
        p.rock(at(gx + rng.uniform(-0.8, 0.8), rng.uniform(-0.4, 0.4), -0.95), rng.uniform(0.3, 0.45),
               "ore", rng)
    return p


# ---------------------------------------------------------------- hopper, belt, silos
def silo_profile(open_top):
    R = SILO_R
    prof = [(0, -6.5), (1.0, -6.5), (1.0, -5.6), (R, -3.2), (R, -2.6), (R + 0.15, -2.6),
            (R + 0.15, -2.0), (R, -2.0), (R, 3.0), (R + 0.15, 3.0), (R + 0.15, 3.6), (R, 3.6),
            (R, 6.8), (R + 0.12, 6.8)]
    if open_top:
        prof += [(R + 0.12, 7.9), (R - 0.35, 7.9), (R - 0.35, FILL_Z0), (0, FILL_Z0)]
    else:
        prof += [(R + 0.12, 7.3), (2.6, 8.4), (1.0, 9.0), (0, 9.0)]
    return prof


def build_silos(rng):
    p = Part("outpost_silos")
    hx, hy = HOPPER.x, HOPPER.y
    # ---- Intake hopper: big yellow funnel, hazard rim, worn steel inside, ore heap
    hop = [(0, -5.6), (1.3, -5.6), (1.3, -3.6), (5.7, 5.4), (6.1, 5.6), (6.1, 6.8), (5.4, 6.8),
           (5.2, 6.2), (1.0, -2.4), (0, -2.4)]
    hmat = ["dark", "dark", "yellow", "dark", "hazard", "yellow", "dark", "dark", "dark"]

    def hop_mat(i, j):
        k = hmat[j]
        if k == "yellow" and j == 2 and i % 5 == 0:
            return "orange"
        return k
    p.lathe(hop, 20, hop_mat, matrix=Matrix.Translation((hx, hy, 0)))
    p.lathe([(0, 3.95), (1.5, 3.7), (2.8, 3.25), (3.75, 2.95), (3.4, 1.9), (0, 1.9)], 16,
            lambda i, j: "ore", matrix=Matrix.Translation((hx, hy, 0)))
    for k in range(14):
        a = k * 2.4 + rng.uniform(-0.3, 0.3)
        rr = 2.6 * math.sqrt((k + 0.5) / 14)
        z = 3.95 - 0.8 * (rr / 2.6) ** 1.5
        p.rock(V((hx + rr * math.cos(a), hy + rr * math.sin(a), z)), rng.uniform(0.45, 0.8), "ore", rng)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        d = V((math.cos(a), math.sin(a), 0))
        p.beam(V((hx, hy, 0)) + d * 4.6 + V((0, 0, 3.0)), V((hx, hy, 0)) + d * 4.4 + V((0, 0, -6.5)),
               0.6, 0.6, "dark")
        add_beacon(p, V((hx, hy, 0)) + d * 5.75 + V((0, 0, 6.8)))
    for k in range(4):   # static rim lights between the beacons
        a = k * math.pi / 2
        p.box(V((hx + 5.75 * math.cos(a), hy + 5.75 * math.sin(a), 6.95)), (0.4, 0.4, 0.3), "light")
    p.cyl(V((hx, hy, -0.5)), 4.3, 4.3, 0.5, "dark", segs=12)
    # Feeder under the outlet, belt tail pulley
    p.box(V((hx, hy + 0.8, -4.3)), (3.2, 4.4, 1.4), "hull2", bevel=0.04)
    p.box(V((hx, hy + 0.8, -3.55)), (3.0, 4.0, 0.1), "hazard")
    # ---- Conveyor frame (the moving belt surface is its own object)
    d = (BELT1 - BELT0)
    dn = d.normalized()
    up = (V((0, 0, 1)) - dn * dn.z).normalized()
    ac = V((1, 0, 0))
    for s in (-1, 1):
        p.beam(BELT0 + ac * s * 1.45 - up * 0.3, BELT1 + ac * s * 1.45 - up * 0.3, 0.3, 0.55, "dark", up=up)
        p.beam(BELT0 + ac * s * 1.38 + up * 0.35, BELT1 + ac * s * 1.38 + up * 0.35, 0.12, 0.5, "hull2", up=up)
    n_id = int(d.length / 2.0)
    for k in range(n_id + 1):
        q = BELT0 + d * (k / n_id)
        p.cyl(q - up * 0.25, 0.14, 0.14, 2.7, "hull2", segs=6, axis_rot=ALONG_X)
    # walkway + yellow handrail on the +X side, trestles down to the base
    for s, rail in ((1, True), (-1, False)):
        off = ac * s * 2.3
        if rail:
            p.beam(BELT0 + off - up * 0.25, BELT1 + off - up * 0.25, 1.1, 0.12, "dark", up=up)
        p.beam(BELT0 + off * (1.25 if rail else 0.7) + up * 1.0,
               BELT1 + off * (1.25 if rail else 0.7) + up * 1.0, 0.1, 0.1, "yellow", up=up)
    for k in range(5):
        q = BELT0 + d * (0.12 + 0.2 * k)
        for s in (-1, 1):
            p.beam(q + ac * s * 1.5 - up * 0.5, V((q.x + s * 1.9, q.y, -6.5)), 0.35, 0.35, "dark")
        p.beam(q - ac * 1.5 - up * 0.6, q + ac * 1.5 - up * 0.6, 0.25, 0.25, "dark")
        for s in (1,):
            p.beam(q + ac * 2.9 - up * 0.25, q + ac * 2.9 + up * 1.05, 0.08, 0.08, "yellow")
    # ---- Head house over the belt head, chutes to both silos
    hh = V((BELT1.x, 10.6, 6.6))
    p.box(hh, (5.2, 5.0, 4.4), "hull", bevel=0.04)
    p.box(hh + V((0, 0, 1.2)), (5.3, 5.1, 0.5), "hazard")
    p.box(hh + V((0, 0, 2.35)), (5.6, 5.4, 0.3), "dark")
    p.box(V((hh.x, hh.y - 2.52, BELT1.z - 0.2)), (3.4, 0.1, 2.0), "dark")
    p.box(V((hh.x + 2.62, hh.y, hh.z - 0.6)), (0.1, 3.6, 0.4), "window")
    p.box(V((hh.x - 2.62, hh.y, hh.z - 0.6)), (0.1, 3.6, 0.4), "window")
    for sx in (-1, 1):
        add_beacon(p, V((hh.x + sx * 2.1, hh.y - 2.0, hh.z + 2.5)))
    p.tube(V((hh.x - 2.4, hh.y + 1.6, 7.6)), V((SILO_A.x + 0.6, SILO_A.y - 0.6, 9.0)), 0.55, 0.55,
           "hull2", segs=8)
    p.tube(V((hh.x + 2.4, hh.y + 1.6, 7.6)), V((SILO_B.x - 1.2, SILO_B.y - 1.2, 8.6)), 0.55, 0.5,
           "hull2", segs=8)
    p.box(V((hh.x, hh.y, -0.8)), (3.0, 3.0, 10.8), "dark")
    # ---- Silos
    edge = {0: "dark", 1: "dark", 2: "dark", 3: "hull2", 4: "dark", 5: "dark", 6: "dark",
            7: "hull", 8: "dark", 9: "hazard", 10: "dark", 11: "hull", 12: "dark", 13: "orange",
            14: "hull2", 15: "hull2", 16: "dark"}
    edge_open = {**edge, 13: "hazard", 14: "yellow", 15: "hull2", 16: "dark"}

    def silo_mat(table):
        def f(i, j):
            k = table[j]
            if k == "hull" and i % 4 in (1, 2):
                return "hull2"
            return k
        return f
    p.lathe(silo_profile(False), 20, silo_mat(edge), matrix=Matrix.Translation(SILO_A))
    p.lathe(silo_profile(True), 20, silo_mat(edge_open), matrix=Matrix.Translation(SILO_B))
    p.cyl(SILO_A + V((0, 0, 9.15)), 0.5, 0.5, 0.3, "light", segs=6)
    for sx, sy in ((SILO_A.x, SILO_A.y), (SILO_B.x, SILO_B.y)):
        for k in range(4):
            a = k * math.pi / 2 + math.pi / 4
            q = V((sx + 2.6 * math.cos(a), sy + 2.6 * math.sin(a), 0))
            p.beam(q + V((0, 0, -3.0)), q + V((0, 0, -6.5)), 0.5, 0.5, "dark")
    # pipe bridge silo A -> processing block
    for z in (-1.0, 0.4):
        p.cyl(V((9.2, SILO_A.y, z)), 0.45, 0.45, 2.4, "dark", segs=8, axis_rot=ALONG_X)
    # ---- Base platform under hopper, belt and silos, tied to the berth wall
    p.box(V((18.6, -1.5, -7.0)), (13.6, 41.0, 1.0), "dark")
    p.box(V((11.4, -12.0, -5.8)), (1.6, 10.0, 1.4), "dark")
    return p


def build_belt():
    """ore_conveyor_belt: the troughed belt surface from BELT0 to BELT1.
    UV u across the belt (0..1), v along it in 4.8 m tiles (v = 0 at the hopper end)."""
    d = BELT1 - BELT0
    dn = d.normalized()
    up = (V((0, 0, 1)) - dn * dn.z).normalized()
    ac = V((1, 0, 0))
    sec = [(-1.2, 0.28), (-0.75, 0.02), (0.75, 0.02), (1.2, 0.28)]
    seg_len = [math.hypot(sec[i + 1][0] - sec[i][0], sec[i + 1][1] - sec[i][1]) for i in range(3)]
    tot = sum(seg_len)
    us = [0.0, seg_len[0] / tot, (seg_len[0] + seg_len[1]) / tot, 1.0]
    n = 6
    verts, uvs = [], []
    for k in range(n + 1):
        t = k / n
        base = BELT0 + d * t
        for (x, z), u in zip(sec, us):
            verts.append(base + ac * x + up * z)
            uvs.append((u, d.length * t / outpost_textures.BELT_TILE))
    faces = []
    for k in range(n):
        for i in range(3):
            a = k * 4 + i
            faces.append((a, a + 1, a + 5, a + 4))
    me = bpy.data.meshes.new("ore_conveyor_belt")
    me.from_pydata([tuple(v) for v in verts], [], faces)
    uvl = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li, vi in zip(poly.loop_indices, poly.vertices):
            uvl.data[li].uv = uvs[vi]
    me.materials.append(MATS["belt"])
    # faces must look up (+up)
    me.update()
    if me.polygons[0].normal.dot(up) < 0:
        for poly in me.polygons:
            poly.flip()
        me.update()
    obj = bpy.data.objects.new("ore_conveyor_belt", me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def build_fill(rng):
    """ore_silo_fill: ore column inside the open silo, built from z = 0 up (origin at the
    silo floor after the bake), full height at scale 1."""
    p = Part("ore_silo_fill")
    r = SILO_R - 0.4
    c = V((SILO_B.x, SILO_B.y, FILL_Z0))
    p.lathe([(0, 0.0), (r, 0.0), (r, 9.3), (2.4, 9.85), (1.2, 10.25), (0, 10.4)], 16,
            lambda i, j: "ore", matrix=Matrix.Translation(c))
    for k in range(9):
        a = k * 2.4 + rng.uniform(-0.3, 0.3)
        rr = 2.6 * math.sqrt((k + 0.5) / 9)
        z = 10.4 - 1.1 * (rr / 2.6) ** 1.3
        p.rock(c + V((rr * math.cos(a), rr * math.sin(a), z)), rng.uniform(0.4, 0.65), "ore", rng)
    return p


# ---------------------------------------------------------------- processing, tower, stockpile
def build_structure(rng):
    p = Part("outpost_structure")
    # ---- Processing block (back centre)
    p.box(V((0, 13.0, 1.5)), (16.0, 14.0, 15.0), "hull2", bevel=0.02)
    p.box(V((0, 13.0, 8.9)), (16.2, 14.2, 0.3), "orange")
    p.box(V((0, 13.0, -4.2)), (16.15, 14.15, 0.8), "hazard")
    p.box(V((0, 14.5, 11.6)), (12.0, 11.0, 5.6), "hull", bevel=0.03)
    p.box(V((0, 14.5, 12.4)), (12.08, 11.08, 0.6), "window")
    p.box(V((0, 14.5, 14.55)), (12.4, 11.4, 0.3), "dark")
    for sx in (-1, 1):
        for yy in (10.5, 18.5):
            p.box(V((sx * 5.9, yy, 14.85)), (0.5, 0.5, 0.4), "light")
        p.box(V((sx * 8.03, 13.0, 4.5)), (0.08, 10.0, 0.5), "window")
    # crusher drums and stacks on the front roof deck
    for sx in (-1, 1):
        p.cyl(V((sx * 4.6, 7.6, 9.9)), 1.4, 1.4, 1.8, "hull", segs=14)
        p.cyl(V((sx * 4.6, 7.6, 11.0)), 1.4, 0.9, 0.4, "dark", segs=14)
        p.cyl(V((sx * 6.8, 19.0, 15.5)), 0.5, 0.4, 2.0, "dark", segs=8)
    p.box(V((0, 7.4, 9.6)), (4.0, 2.4, 1.2), "dark")
    # roof deck clutter on the upper hall: vents, hatch, pipe run
    for k in range(3):
        p.box(V((-3.5 + k * 3.5, 12.0, 14.95)), (2.2, 1.6, 0.5), "hull2")
        p.box(V((-3.5 + k * 3.5, 12.0, 15.22)), (1.8, 1.2, 0.06), "dark")
    p.box(V((2.5, 17.5, 14.8)), (3.0, 3.0, 0.2), "hazard")
    p.box(V((2.5, 17.5, 14.92)), (2.4, 2.4, 0.1), "hull2")
    p.cyl(V((-3.0, 17.0, 14.95)), 0.3, 0.3, 9.0, "dark", segs=6, axis_rot=ALONG_Y)
    # Corridor port on the back face, centred at z = 12 (link_point)
    p.box(V((0, 21.8, 12.0)), (7.0, 3.6, 7.0), "hull", bevel=0.04)
    p.cyl(V((0, 23.85, 12.0)), 3.2, 3.2, 0.5, "dark", segs=16, axis_rot=ALONG_Y)
    p.cyl(V((0, 24.05, 12.0)), 2.5, 2.5, 0.1, "orange", segs=16, axis_rot=ALONG_Y)
    p.box(V((0, 23.65, 15.75)), (7.0, 0.1, 0.5), "hazard")
    p.box(V((0, 23.65, 8.25)), (7.0, 0.1, 0.5), "hazard")
    for sx in (-1, 1):
        p.box(V((sx * 3.7, 23.0, 12.0)), (0.4, 0.4, 0.4), "light")
    p.box(V((0, 21.8, 1.25)), (2.2, 2.2, 14.5), "dark")
    # Radiator wing out the back-left
    p.box(V((-17.0, 17.5, 4.0)), (18.0, 0.9, 0.9), "dark")
    for k in range(4):
        x = -11.0 - k * 4.2
        for s in (-1, 1):
            p.box(V((x, 17.5 + s * 2.7, 4.0)), (3.6, 4.4, 0.2), "dark")
            p.box(V((x, 17.5 + s * 2.7, 4.15)), (3.2, 0.3, 0.1), "hull2")
    p.box(V((-26.3, 17.5, 4.0)), (0.9, 0.9, 0.9), "light")
    p.box(V((-8.6, 17.5, 4.0)), (1.6, 2.6, 2.6), "hull2")
    # ---- Control tower and bridge to the berth wall
    tc = V((-17.0, 3.0, 0))
    p.box(tc + V((0, 0, 1.5)), (3.6, 3.6, 15.0), "hull2", bevel=0.03)
    p.box(tc + V((0, 0, -5.0)), (5.4, 5.4, 2.0), "hull")
    p.box(tc + V((0, 0, 10.4)), (6.4, 6.4, 3.2), "hull", bevel=0.04)
    p.box(tc + V((0, 0, 10.6)), (6.5, 6.5, 1.1), "window")
    p.box(tc + V((0, 0, 12.25)), (7.0, 7.0, 0.5), "dark")
    p.box(tc + V((0, 0, 12.55)), (6.4, 1.0, 0.1), "orange")
    p.cyl(tc + V((1.8, 1.8, 15.5)), 0.18, 0.07, 6.0, "dark", segs=6)
    p.box(tc + V((1.8, 1.8, 18.6)), (0.5, 0.5, 0.5), "light")
    dish = Matrix.Translation(tc + V((-1.4, -1.2, 13.6))) @ Matrix.Rotation(math.radians(-40), 4, "X")
    p.lathe([(0, 0), (1.2, 0.25), (2.2, 0.8), (2.4, 0.95), (2.4, 0.75), (2.0, 0.55), (0, -0.15)],
            14, lambda i, j: ("hull", "hull", "orange", "dark", "dark", "dark")[j], matrix=dish)
    p.box(V((-12.85, 1.0, 4.5)), (4.7, 2.2, 1.6), "hull2")
    p.box(V((-12.85, -0.12, 4.6)), (4.0, 0.08, 0.4), "window")
    # ---- Stockpile: open ore bin with heaps
    bx0, bx1, by0, by1 = -25.0, -13.2, -22.0, -7.0
    bc = V(((bx0 + bx1) / 2, (by0 + by1) / 2, 0))
    bw, bl = bx1 - bx0, by1 - by0
    p.box(V((bc.x, bc.y, -4.75)), (bw + 1.6, bl + 1.6, 1.5), "hull2")
    p.box(V((bc.x, bc.y, -5.9)), (bw, bl, 1.0), "dark")
    for (cx, cy, sx_, sy_) in ((bc.x, by0 - 0.4, bw + 1.6, 0.8), (bc.x, by1 + 0.4, bw + 1.6, 0.8),
                               (bx0 - 0.4, bc.y, 0.8, bl), (bx1 + 0.4, bc.y, 0.8, bl)):
        p.box(V((cx, cy, -1.7)), (sx_, sy_, 4.6), "hull2", bevel=0.04)
        p.box(V((cx, cy, 0.64)), (sx_ + 0.04, sy_ + 0.04, 0.12), "yellow")
    for k in range(4):
        for x in (bx0 - 1.0, bx1 + 1.0):
            p.box(V((x, by0 + 2 + k * 3.7, -2.0)), (0.6, 0.9, 4.4), "dark")
    p.box(V((bc.x, by0 - 0.82, -1.7)), (bw, 0.06, 1.0), "hazard")
    heaps = [((-21.0, -17.8), 4.6, 4.0), ((-16.6, -11.6), 4.2, 3.6), ((-22.0, -10.2), 2.8, 2.2),
             ((-16.0, -19.0), 2.6, 1.8)]
    for (hx, hy), r, h in heaps:
        prof = p.mound(V((hx, hy, -4.0)), r, h, "ore", rng)
        for i in range(int(r * 2.5)):
            a = rng.uniform(0, 2 * math.pi)
            f = math.sqrt(rng.uniform(0.0, 0.85))
            q = V((hx + f * r * math.cos(a), hy + f * r * math.sin(a), -4.0 + prof(f) + 0.1))
            p.rock(q, rng.uniform(0.35, 0.7), "ore", rng)
    # Spill gallery from the processing block over the bin, spout, supports
    g0, g1 = V((-8.2, 9.0, 7.5)), V((-17.5, -6.2, 6.2))
    p.beam(g0, g1, 2.0, 2.2, "hull2")
    p.beam(g0 + V((0, 0, 1.15)), g1 + V((0, 0, 1.15)), 0.5, 0.1, "yellow")
    p.tube(g1 + V((0, 0, -0.6)), V((-18.4, -8.6, 3.0)), 0.7, 0.55, "dark", segs=8)
    for t in (0.35, 0.7):
        q = g0.lerp(g1, t)
        p.beam(q - V((0, 0, 1.0)), V((q.x, q.y, -6.0)), 0.5, 0.5, "dark")
    # ---- Base chassis on the left, tying tower, bin and berth together
    p.box(V((-18.5, -6.0, -7.0)), (15.0, 36.0, 1.0), "dark")
    p.box(V((-11.6, -6.0, -6.0)), (2.0, 24.0, 1.2), "dark")
    return p


def build_lights():
    """unload_lights: amber beacon lenses only (housings are in the static meshes)."""
    me_bm = bmesh.new()
    for c in BEACONS:
        bmesh.ops.create_cone(me_bm, cap_ends=True, cap_tris=False, segments=10, radius1=0.42,
                              radius2=0.36, depth=0.55, matrix=Matrix.Translation(c + V((0, 0, 0.275))))
    bmesh.ops.recalc_face_normals(me_bm, faces=me_bm.faces[:])
    me = bpy.data.meshes.new("unload_lights")
    me_bm.to_mesh(me)
    me_bm.free()
    me.materials.append(MATS["amber"])
    obj = bpy.data.objects.new("unload_lights", me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def set_origin(obj, pivot):
    obj.data.transform(Matrix.Translation(-V(pivot)))
    obj.location = V(pivot)


def add_empty(name, parent, pos, rot_z=0.0, size=4.0, kind="SINGLE_ARROW"):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = kind
    e.empty_display_size = size
    e.location = pos
    e.rotation_euler = (0, 0, rot_z)
    bpy.context.scene.collection.objects.link(e)
    e.parent = parent
    return e


DUST_SOURCES = [  # (x, y, radius, strength): ore dust around the handling points
    (HOPPER.x, HOPPER.y, 13.0, 1.0), (0.0, -15.0, 9.0, 0.55), (18.5, -2.0, 7.0, 0.8),
    (18.5, 8.0, 7.0, 0.8), (SILO_B.x, SILO_B.y, 7.0, 0.7), (-19.0, -14.5, 13.0, 1.0),
    (-12.0, 2.0, 6.0, 0.4), (0.0, 4.0, 6.0, 0.6),
]


def build_outpost(textures):
    rng = random.Random(7310)
    build_materials()
    BEACONS.clear()
    root = bpy.data.objects.new("mining_outpost", None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 10
    bpy.context.scene.collection.objects.link(root)
    builders = (build_hangar, build_silos, build_crane, build_structure, build_arm, build_fill)
    objs = [b(rng).finish(root) for b in builders]
    belt = build_belt()
    belt.parent = root
    lights = build_lights()
    lights.parent = root
    if textures:
        outpost_textures.texture_outpost(objs, MATS, belt, [(DOCK_POS.x, DOCK_POS.y)], DUST_SOURCES)
    else:
        for o in objs:
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    arm = next(o for o in objs if o.name == "unload_arm")
    fill = next(o for o in objs if o.name == "ore_silo_fill")
    set_origin(arm, PIVOT)
    set_origin(fill, V((SILO_B.x, SILO_B.y, FILL_Z0)))
    set_origin(belt, BELT0)
    for name, pos in (("dock_point", DOCK_POS), ("spawn_point", SPAWN_POS)):
        add_empty(name, root, pos, rot_z=math.pi)  # Godot -Z of the empty points out of the mouth
    add_empty("link_point", root, LINK_POS)        # Godot -Z = Blender +Y = out of the back face
    add_empty("ore_flow_point", root, V((HOPPER.x, HOPPER.y, 5.3)), size=2.0, kind="PLAIN_AXES")
    return root, objs + [belt, lights]


# ---------------------------------------------------------------- previews
def load_miner():
    with bpy.data.libraries.load(MINER_BLEND, link=False) as (src, dst):
        dst.objects = list(src.objects)
    ship_root = None
    for o in dst.objects:
        if o is None:
            continue
        bpy.context.scene.collection.objects.link(o)
        if o.parent is None and o.type == "EMPTY":
            ship_root = o
    ship_root.location = DOCK_POS
    ship_root.rotation_euler = (0, 0, math.pi)
    return ship_root


def previews():
    load_miner()
    scene = bpy.context.scene
    common.setup_preview(cam_loc=(-52, -82, 78), cam_target=(1.5, -2.5, 0), ortho_scale=74,
                         res=(1600, 1200), key_dir=(-0.55, -0.45, 0.7), key_energy=3.5)
    scene.eevee.taa_render_samples = 64
    common.render(os.path.join(common.PREVIEW_DIR, "mining_outpost_preview.png"))
    cam = scene.camera
    cam.location = (0.0, -0.5, 150.0)
    cam.rotation_euler = (0, 0, 0)
    cam.data.ortho_scale = 64
    scene.render.resolution_x, scene.render.resolution_y = 1200, 1200
    common.render(os.path.join(common.PREVIEW_DIR, "mining_outpost_top.png"))
    # close-up (inspection only)
    cam.data.type = "PERSP"
    cam.data.lens = 32
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1000
    cam.location = (36.0, -42.0, 24.0)
    tgt = V((10.0, -10.0, 0.0))
    cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
    common.render(os.path.join(common.PREVIEW_DIR, "mining_outpost_closeup.png"))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    common.reset_scene()
    root, objs = build_outpost("--no-textures" not in argv)
    total = 0
    for o in objs:
        tris = sum(len(pl.vertices) - 2 for pl in o.data.polygons)
        total += tris
        print(f"STAT {o.name} tris={tris} loc={tuple(round(c, 2) for c in o.location)} "
              f"mats={[m.name for m in o.data.materials]}")
    print(f"STAT total tris={total} beacons={len(BEACONS)}")
    bpy.context.preferences.filepaths.save_version = 0  # no .blend1 on re-run
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_mainfile(filepath=BLEND)
    common.export_glb(root, OUT, export_image_format="AUTO")
    if "--no-preview" not in argv:
        previews()


main()
