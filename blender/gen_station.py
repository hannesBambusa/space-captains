"""Generate the home station .glb and a 45 degree preview.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python /Users/hannesalm/code/games/space-majesty/blender/gen_station.py
  Add `-- --no-preview` to skip the PNG renders, `-- --no-textures` for flat materials.
Textures are baked by station_textures.py (Cycles, a few minutes) into blender/textures/
and embedded in the glb.

Layout (Blender Z up, exported +Y up). Hub centre at origin, play plane z=0.
  core drum r~13.5, habitation ring r 32..40, 4 spokes, 2 docking arms with pads
  (45 and 225 deg), 2 solar wings (135 and 315 deg), comm dish on the tower.
Hierarchy: station_home (empty root) -> station_core, station_ring, station_docks, station_solar.
station_ring has its origin at the hub centre so Godot can spin it.
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
import station_textures  # noqa: E402

OUT = os.path.join(common.ROOT, "assets", "models", "station", "station_home.glb")

MATS = {}


def build_materials():
    m = common.make_material
    MATS["hull"] = m("station_hull_white", (0.78, 0.78, 0.76), roughness=0.45, metallic=0.1)
    MATS["hull2"] = m("station_hull_grey", (0.50, 0.52, 0.55), roughness=0.5, metallic=0.15)
    MATS["dark"] = m("station_structure_dark", (0.06, 0.065, 0.07), roughness=0.55, metallic=0.5)
    MATS["orange"] = m("station_accent_orange", (0.85, 0.28, 0.03), roughness=0.45, metallic=0.0)
    MATS["window"] = m("station_window_warm", (1.0, 0.85, 0.6), roughness=0.3,
                       emission=(1.0, 0.78, 0.5), emission_strength=3.5)
    MATS["light"] = m("station_light_orange", (1.0, 0.45, 0.1), roughness=0.3,
                      emission=(1.0, 0.42, 0.08), emission_strength=5.0)
    MATS["solar"] = m("station_solar_panel", (0.025, 0.06, 0.2), roughness=0.28, metallic=0.55)
    # Surface kinds added for the baked textures (flat stand-ins until station_textures runs)
    MATS["mli"] = m("station_mli_white", (0.8, 0.8, 0.78), roughness=0.85)
    MATS["mli_gold"] = m("station_mli_gold", (0.8, 0.52, 0.15), roughness=0.4, metallic=0.9)
    MATS["hazard"] = m("station_hazard", (0.8, 0.55, 0.02), roughness=0.5)
    MATS["pad"] = m("station_pad_deck", (0.15, 0.15, 0.16), roughness=0.7, metallic=0.2)


class Part:
    """One output mesh object, built in a single bmesh with named material slots."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.slots = []
        # "panel" UVs are metres in each primitive's own frame. The texture bake uses them
        # to lay out hull plates, seams and rivets; they are dropped before export.
        self.uv = self.bm.loops.layers.uv.new("panel")
        self.n_prims = 0

    def _offset(self):
        """Per-primitive panel-space offset (multiples of 64 m keep plate grids aligned).
        Counter based, so the geometry rng sequence is untouched."""
        self.n_prims += 1
        k = self.n_prims
        return Vector(((k * 7) % 31 * 64.0, (k * 13) % 29 * 64.0))

    def _planar_uv(self, faces, inv, shift):
        """Box-style panel UVs: each face projected on its dominant local axis."""
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

    def mi(self, key):
        mat = MATS[key]
        if mat not in self.slots:
            self.slots.append(mat)
        return self.slots.index(mat)

    def _faces(self, verts):
        return list({f for v in verts for f in v.link_faces})

    def box(self, center, size, mat, rot_z=0.0, bevel=0.12, matrix=None):
        m = (matrix or Matrix()) @ Matrix.Translation(center) @ Matrix.Rotation(rot_z, 4, "Z")
        m = m @ Matrix.Diagonal((*size, 1.0))
        r = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        verts = r["verts"]
        idx = self.mi(mat)
        faces = self._faces(verts)
        for f in faces:
            f.material_index = idx
        if bevel > 0:
            edges = list({e for v in verts for e in v.link_edges})
            off = min(size) * bevel
            res = bmesh.ops.bevel(self.bm, geom=verts + edges, offset=off, segments=1,
                                  affect="EDGES", profile=0.5, clamp_overlap=True)
            for f in res["faces"]:
                f.material_index = idx
            # bevel rebuilds the original faces; the box is an isolated island, so its
            # faces are the bevel faces plus everything sharing their verts
            faces = list({g for f in res["faces"] for v in f.verts for g in v.link_faces})
        frame = (matrix or Matrix()) @ Matrix.Translation(center) @ Matrix.Rotation(rot_z, 4, "Z")
        self._planar_uv(faces, frame.inverted(), Vector(size) / 2)

    def cyl(self, center, r1, r2, depth, mat, segs=12, matrix=None, axis_rot=None):
        m = (matrix or Matrix()) @ Matrix.Translation(center)
        if axis_rot is not None:
            m = m @ axis_rot
        r = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segs,
                                  radius1=r1, radius2=r2, depth=depth, matrix=m)
        idx = self.mi(mat)
        faces = self._faces(r["verts"])
        for f in faces:
            f.material_index = idx
        # panel UVs: caps planar, sides unrolled (arc length x height)
        inv = m.inverted()
        rot = inv.to_3x3()
        off = self._offset()
        rm = max(r1, r2)
        ra = (r1 + r2) / 2
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

    def lathe(self, profile, segs, mat_fn, matrix=None, start=0.0):
        """profile: list of (r, z). mat_fn(seg_i, edge_j) -> material key."""
        m = matrix or Matrix()
        rings = []
        for i in range(segs):
            a = start + 2 * math.pi * i / segs
            ca, sa = math.cos(a), math.sin(a)
            rings.append([self.bm.verts.new(m @ Vector((r * ca, r * sa, z))) for r, z in profile])
        # panel UVs: u = arc length (whole 2 m plates per turn), v = length along the profile
        off = self._offset()
        s_len = [0.0]
        for j in range(len(profile) - 1):
            s_len.append(s_len[-1] + math.hypot(profile[j + 1][0] - profile[j][0],
                                                profile[j + 1][1] - profile[j][1]))
        # strips are cut into ~12 m chunks (64 m apart in panel space, grid stays aligned)
        # so the atlas packer gets short rectangles instead of whole rings
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
                    vs = (a[j], b[j + 1], a[j + 1])
                    uvs = ((u0, v0), (u1, v1), (u0, v1))
                elif profile[j + 1][0] < 1e-4:
                    vs = (a[j], b[j], a[j + 1])
                    uvs = ((u0, v0), (u1, v0), (u0, v1))
                else:
                    vs = (a[j], b[j], b[j + 1], a[j + 1])
                    uvs = ((u0, v0), (u1, v0), (u1, v1), (u0, v1))
                f = self.bm.faces.new(vs)
                f.material_index = self.mi(mat_fn(i, j))
                for lp, uv in zip(f.loops, uvs):
                    lp[self.uv].uv = uv
        # weld axis verts
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


def polar(r, a, z=0.0):
    return Vector((r * math.cos(a), r * math.sin(a), z))


# ---------------------------------------------------------------- core
def build_core(rng):
    p = Part("station_core")
    prof = [(0, -17), (2.5, -17), (3.2, -15.5), (6, -12.5), (10, -9), (12.5, -7.2),
            (13.5, -5.8), (13.5, -1.0), (13.5, 1.0), (13.5, 4.6), (12.6, 6.0),
            (11.2, 6.4), (9.6, 6.4), (9.2, 7.0), (9.2, 8.6), (9.2, 9.8), (8.8, 11.0),
            (6.0, 12.4), (4.6, 12.6), (4.6, 16.8), (3.8, 17.8), (0, 17.8)]
    # edge index -> material ; per-segment panel variation on drum
    edge_mat = {0: "dark", 1: "dark", 2: "dark", 3: "hull2", 4: "hull2", 5: "orange",
                6: "hull", 7: "window", 8: "hull", 9: "hull", 10: "orange", 11: "dark",
                12: "dark", 13: "hull", 14: "window", 15: "hull", 16: "hull", 17: "dark",
                18: "hull2", 19: "orange", 20: "hull"}

    def core_mat(i, j):
        k = edge_mat[j]
        if k == "hull" and (i // 4) % 2 == 1:
            return "hull2"
        if k == "window" and i % 5 == 0:
            return "hull"
        return k
    p.lathe(prof, 40, core_mat)

    # Spoke collars on drum and spokes out to the ring
    for s in range(4):
        a = s * math.pi / 2
        p.box(polar(14.0, a), (3.0, 5.0, 4.0), "hull2", rot_z=a)
        p.box(polar(23.0, a), (19.5, 2.6, 2.6), "dark", rot_z=a, bevel=0.15)
        p.box(polar(23.0, a, 1.7), (17.0, 1.5, 0.9), "hull", rot_z=a)
        p.box(polar(23.0, a, 2.2), (2.0, 1.6, 0.25), "orange", rot_z=a, bevel=0.0)
        for rr in (17.0, 29.0):
            p.box(polar(rr, a, 2.25), (0.5, 0.5, 0.3), "light", rot_z=a, bevel=0.0)

    # Habitat pods between the spokes: chunky silhouette breakers on the drum
    for s in range(4):
        a = s * math.pi / 2 + math.pi / 4
        p.box(polar(15.0, a, 0.5), (5.0, 7.0, 8.0), "mli", rot_z=a)
        p.box(polar(17.55, a, 0.5), (0.1, 5.2, 0.7), "window", rot_z=a, bevel=0.0)
        p.box(polar(15.0, a, 4.65), (4.2, 6.2, 0.5), "dark", rot_z=a)
        p.box(polar(15.0, a, 4.95), (4.6, 1.0, 0.12), "orange", rot_z=a, bevel=0.0)

    # Ledge greebles on the drum top (z 6.4) between r 9.6 and 12.6
    for i in range(14):
        a = 2 * math.pi * (i + rng.uniform(-0.2, 0.2)) / 14
        w, d, h = rng.uniform(1.2, 2.2), rng.uniform(1.0, 2.0), rng.uniform(0.6, 1.8)
        p.box(polar(11.0, a, 6.4 + h / 2), (d, w, h), rng.choice(["hull2", "dark", "hull"]), rot_z=a)
    # Tier-2 radiators (dark fins) on the upper drum
    for i in range(6):
        a = 2 * math.pi * i / 6 + 0.25
        p.box(polar(10.6, a, 9.0), (2.6, 0.35, 2.6), "dark", rot_z=a, bevel=0.0)

    # Tanks on the underside cone
    for i in range(6):
        a = 2 * math.pi * i / 6 + 0.5
        p.cyl(polar(8.2, a, -10.0), 1.6, 1.6, 4.0, "mli_gold", segs=10)
        p.cyl(polar(8.2, a, -7.7), 1.6, 1.1, 0.6, "mli_gold", segs=10)

    # Tower top: dish mast + dish + antenna
    p.cyl(Vector((0, 0, 19.5)), 0.7, 0.5, 3.4, "dark", segs=10)
    p.box(Vector((0, 0, 18.3)), (3.2, 3.2, 1.0), "hull2")
    dish_m = Matrix.Translation((0, 0, 21.5)) @ Matrix.Rotation(math.radians(-38), 4, "X")
    dish_prof = [(0, 0.0), (2.0, 0.2), (4.0, 0.85), (5.9, 2.0), (6.2, 2.0), (6.0, 1.7),
                 (4.0, 0.55), (1.6, -0.2), (0, -0.35)]
    dish_mats = {0: "hull", 1: "hull", 2: "hull", 3: "orange", 4: "dark", 5: "dark",
                 6: "dark", 7: "dark"}
    p.lathe(dish_prof, 20, lambda i, j: dish_mats[j], matrix=dish_m)
    dish_axis = dish_m.to_3x3().to_4x4()
    p.cyl(dish_m @ Vector((0, 0, 2.2)), 0.2, 0.08, 4.4, "dark", segs=6, axis_rot=dish_axis)
    p.cyl(dish_m @ Vector((0, 0, 4.5)), 0.4, 0.4, 0.5, "light", segs=6, axis_rot=dish_axis)
    # Long antenna spike off the tower side
    p.cyl(Vector((3.8, 0, 20.5)), 0.22, 0.08, 9.0, "dark", segs=6)
    p.cyl(Vector((3.8, 0, 25.2)), 0.35, 0.35, 0.5, "light", segs=6)
    p.cyl(Vector((-3.4, 1.6, 19.5)), 0.15, 0.06, 5.0, "dark", segs=6)
    # Underside reactor glow
    p.cyl(Vector((0, 0, -17.4)), 2.2, 1.6, 0.8, "light", segs=16)
    return p


# ---------------------------------------------------------------- ring
def build_ring(rng):
    p = Part("station_ring")
    prof = [(32.0, -2.0), (33.0, -3.0), (39.0, -3.0), (40.0, -2.0), (40.0, -0.4),
            (40.0, 0.4), (40.0, 2.0), (39.2, 3.0), (38.0, 3.0), (37.5, 3.0),
            (36.6, 3.0), (35.6, 3.0), (35.0, 3.0), (33.0, 3.0), (32.0, 2.0),
            (32.0, 0.5), (32.0, -0.5), (32.0, -2.0)]
    base = {0: "dark", 1: "hull2", 2: "dark", 3: "hull", 4: "window", 5: "hull",
            6: "hull", 7: "hull", 8: "window", 9: "hull", 10: "orange", 11: "hull",
            12: "hull", 13: "hull", 14: "hull", 15: "window", 16: "hull"}
    segs = 64

    def ring_mat(i, j):
        k = base[j]
        if k == "window" and i % 4 == 0:
            return "hull2"
        if k == "hull" and (i // 2) % 4 == 3:
            return "hull2"
        # bulkhead bands every 8 segments
        if i % 8 == 0 and j in (5, 6, 7, 9, 11, 12, 13):
            return "dark"
        return k
    p.lathe(prof, segs, ring_mat)

    # Spoke junction modules on the ring
    for s in range(4):
        a = s * math.pi / 2
        p.box(polar(36.0, a, 0.0), (9.5, 5.0, 7.4), "hull2", rot_z=a)
        p.box(polar(36.0, a, 3.8), (6.0, 3.0, 0.6), "dark", rot_z=a)
        p.box(polar(36.0, a, 4.15), (1.2, 3.2, 0.12), "orange", rot_z=a, bevel=0.0)
    for s in range(4):
        a = s * math.pi / 2 + math.pi / 4
        p.box(polar(36.0, a, 0.0), (10.0, 6.5, 8.0), "mli", rot_z=a)
        p.box(polar(36.0, a, 4.1), (7.0, 4.6, 0.7), "dark", rot_z=a)
        p.box(polar(36.0, a, 4.5), (7.4, 0.9, 0.12), "orange", rot_z=a, bevel=0.0)
        for sgn in (-1, 1):
            off = Vector((-math.sin(a), math.cos(a), 0)) * sgn * 3.27
            p.box(polar(36.0, a, 1.0) + off, (7.0, 0.08, 0.5), "window", rot_z=a, bevel=0.0)
    # Top greebles: containers / radiators / small dish
    for i in range(segs):
        if i % 8 in (2, 5) and rng.random() < 0.8:
            a = 2 * math.pi * (i + 0.5) / segs
            w, d, h = rng.uniform(1.4, 2.4), rng.uniform(1.2, 1.8), rng.uniform(0.5, 1.2)
            p.box(polar(rng.choice([34.0, 38.4]), a, 3.0 + h / 2), (d, w, h),
                  rng.choice(["hull2", "dark", "hull2", "orange"]), rot_z=a)
    # Underside fins
    for i in range(16):
        a = 2 * math.pi * (i + 0.25) / 16
        p.box(polar(36.0, a, -3.6), (5.0, 0.4, 1.2), "dark", rot_z=a, bevel=0.0)
    # Small secondary dish on ring top
    a = math.radians(100)
    m = Matrix.Translation(polar(36.0, a, 4.6)) @ Matrix.Rotation(math.radians(30), 4, "Y")
    p.lathe([(0, 0), (1.2, 0.25), (2.0, 0.7), (2.0, 0.5), (0, -0.1)], 14,
            lambda i, j: "hull" if j < 2 else "dark", matrix=m)
    p.cyl(polar(36.0, a, 3.6), 0.3, 0.3, 1.4, "dark", segs=6)
    return p


# ---------------------------------------------------------------- docks
def build_docks(rng):
    p = Part("station_docks")
    for a_deg in (45, 225):
        a = math.radians(a_deg)
        # Arm: dark truss + hull walkway with window strips + orange chevrons
        p.box(polar(45.5, a, -0.4), (12.0, 3.2, 2.2), "dark", rot_z=a)
        p.box(polar(45.0, a, 1.1), (11.0, 2.0, 1.2), "hull", rot_z=a)
        for side in (-1, 1):
            off = Vector((-math.sin(a), math.cos(a), 0)) * side * 1.02
            p.box(polar(45.0, a, 1.1) + off, (9.0, 0.08, 0.35), "window", rot_z=a, bevel=0.0)
        for k in range(3):
            p.box(polar(42.5 + k * 2.4, a, 1.75), (0.6, 1.6, 0.1), "hazard", rot_z=a, bevel=0.0)
        # Truss cross braces under the arm
        for k in range(4):
            p.box(polar(41.5 + k * 2.7, a, -1.7), (0.4, 3.6, 0.5), "dark", rot_z=a, bevel=0.0)
        # Docking collar
        p.cyl(polar(51.0, a, 0.0), 2.2, 2.2, 3.6, "hull2", segs=12)
        # Pad: octagonal platform centred at r=57
        c = polar(57.5, a, 0.2)
        mtx = Matrix.Translation(c) @ Matrix.Rotation(a + math.pi / 8, 4, "Z")
        prof = [(0, 0.7), (4.6, 0.7), (5.4, 0.7), (6.6, 0.7), (7.2, 0.4), (7.2, -0.4),
                (6.4, -0.9), (3.0, -1.4), (0, -1.6)]
        pad_mats = {0: "pad", 1: "hazard", 2: "dark", 3: "dark", 4: "hull2", 5: "dark",
                    6: "dark", 7: "dark"}
        p.lathe(prof, 8, lambda i, j: pad_mats[j], matrix=mtx)
        # Landing mark: orange bar cross + centre light
        p.box(c + Vector((0, 0, 0.75)), (5.0, 0.6, 0.1), "orange", rot_z=a, bevel=0.0)
        p.box(c + Vector((0, 0, 0.75)), (0.6, 5.0, 0.1), "orange", rot_z=a, bevel=0.0)
        p.cyl(c + Vector((0, 0, 0.8)), 0.6, 0.6, 0.15, "window", segs=8)
        # Rim lights alternating orange / warm white
        for k in range(8):
            ang = a + math.pi / 8 + k * math.pi / 4
            lp = c + Vector((math.cos(ang), math.sin(ang), 0)) * 6.5 + Vector((0, 0, 0.8))
            p.box(lp, (0.6, 0.6, 0.25), "light" if k % 2 == 0 else "window", rot_z=ang, bevel=0.0)
        # Under-pad support strut
        p.cyl(c + Vector((0, 0, -2.6)), 1.6, 0.8, 2.4, "dark", segs=8)
        # Small control tower beside the pad
        side = Vector((-math.sin(a), math.cos(a), 0))
        tc = polar(51.0, a, 0.0) + side * 3.6
        p.box(tc + Vector((0, 0, 1.2)), (2.0, 2.0, 2.6), "hull", rot_z=a)
        p.box(tc + Vector((0, 0, 2.2)), (2.08, 2.08, 0.4), "window", rot_z=a, bevel=0.0)
        p.box(tc + Vector((0, 0, 2.75)), (2.4, 2.4, 0.4), "dark", rot_z=a)
    return p


# ---------------------------------------------------------------- solar
def build_solar(rng):
    p = Part("station_solar")
    for a_deg in (135, 315):
        a = math.radians(a_deg)
        side = Vector((-math.sin(a), math.cos(a), 0))
        p.box(polar(58.0, a, 0.0), (37.0, 1.6, 1.6), "dark", rot_z=a, bevel=0.15)
        p.box(polar(42.5, a, 0.0), (4.0, 3.6, 3.6), "hull2", rot_z=a)
        p.box(polar(42.5, a, 1.85), (1.0, 3.7, 0.12), "orange", rot_z=a, bevel=0.0)
        p.cyl(polar(77.0, a, 0.0), 1.2, 1.2, 2.0, "hull2", segs=10)
        p.cyl(polar(77.0, a, 1.1), 0.4, 0.4, 0.3, "light", segs=6)
        for k in range(4):
            r = 48.0 + k * 7.5
            for sgn in (-1, 1):
                pc = polar(r, a, 0.15) + side * sgn * 6.4
                p.box(polar(r, a, 0.0) + side * sgn * 1.5, (0.6, 1.8, 0.5), "dark", rot_z=a, bevel=0.0)
                p.box(pc, (6.6, 9.8, 0.3), "dark", rot_z=a, bevel=0.0)
                # 2 x 3 cell grid of solar plates
                for cx in range(2):
                    for cy in range(3):
                        lx = (cx - 0.5) * 3.2
                        ly = (cy - 1) * 3.2
                        off = Vector((math.cos(a), math.sin(a), 0)) * lx + side * ly
                        p.box(pc + off + Vector((0, 0, 0.2)), (3.0, 3.0, 0.12), "solar",
                              rot_z=a, bevel=0.0)
    return p


def build_station():
    rng = random.Random(4242)
    build_materials()
    root = bpy.data.objects.new("station_home", None)
    root.empty_display_type = "PLAIN_AXES"
    bpy.context.scene.collection.objects.link(root)
    objs = [b(rng).finish(root) for b in (build_core, build_ring, build_docks, build_solar)]
    return root, objs


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    common.reset_scene()
    root, objs = build_station()
    if "--no-textures" not in argv:
        pads = [tuple(polar(57.5, math.radians(d))[:2]) for d in (45, 225)]
        station_textures.texture_station(objs, MATS, pads)
    total = 0
    for o in objs:
        tris = sum(len(pl.vertices) - 2 for pl in o.data.polygons)
        total += tris
        print(f"STAT {o.name} tris={tris} mats={[m.name for m in o.data.materials]}")
    print(f"STAT total tris={total}")
    blend = os.path.join(common.ROOT, "blender", "station_home.blend")
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    bpy.ops.file.make_paths_relative()      # textures as //textures/...
    bpy.ops.wm.save_mainfile(filepath=blend)
    # AUTO keeps each image's own format: JPEG albedo, PNG normal and metal/rough
    common.export_glb(root, OUT, export_image_format="AUTO")
    if "--no-preview" not in argv:
        common.setup_preview(cam_loc=(0, -120, 120), cam_target=(0, 0, 0), ortho_scale=175,
                             res=(1600, 1200), key_dir=(-0.6, -0.35, 0.7), key_energy=3.5)
        common.render(os.path.join(common.PREVIEW_DIR, "station_home_preview.png"))
        # close-up: perspective view over a docking pad toward the ring and core
        scene = bpy.context.scene
        cam = scene.camera
        cam.data.type = "PERSP"
        cam.data.lens = 35
        cam.location = (66.0, 18.0, 30.0)
        target = Vector((30.0, 32.0, 0.0))
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        common.render(os.path.join(common.PREVIEW_DIR, "station_home_closeup.png"))


main()
