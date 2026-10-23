"""Generate the mining outpost .glb and a 45 degree preview.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python /Users/hannesalm/code/games/space-majesty/blender/gen_mining_outpost.py
  Add `-- --no-preview` to skip the PNG render.

Layout (Blender Z up, exported +Y up). Building centre at origin, play plane z=0.
The hangar mouth faces Blender -Y, which the exporter turns into Godot +Z.
  hangar  x -9..9, y -15..9, bay floor z=-3, bay ceiling z=5.5 (ships at z=0 fit inside)
  apron   in front of the mouth, y -15..-24
  silos   2x2 cluster on +X, ore hoppers in front of them
  crane   yellow boom on the -X side with a hanging container
  tower   control tower back-left, processing block + radiators at the back (+Y)
Hierarchy: mining_outpost (empty root)
  -> outpost_hangar, outpost_silos, outpost_crane, outpost_structure,
     dock_point (empty), spawn_point (empty).
dock_point / spawn_point are rotated 180 deg about up, so their Godot -Z (forward)
points out of the hangar mouth (Godot world +Z). A ship given their transform faces out.
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

OUT = os.path.join(common.ROOT, "assets", "models", "buildings", "mining_outpost.glb")
MOUTH_Y = -15.0              # hangar mouth plane (Blender y)
DOCK_POS = (0.0, -14.0, 0.0)     # Blender coords, just inside the mouth, on the play plane
SPAWN_POS = (0.0, -32.0, 0.0)    # Blender coords, past the apron

MATS = {}


def build_materials():
    m = common.make_material
    MATS["hull"] = m("outpost_hull_white", (0.78, 0.78, 0.76), roughness=0.45, metallic=0.1)
    MATS["hull2"] = m("outpost_hull_grey", (0.50, 0.52, 0.55), roughness=0.5, metallic=0.15)
    MATS["dark"] = m("outpost_structure_dark", (0.06, 0.065, 0.07), roughness=0.55, metallic=0.5)
    MATS["orange"] = m("outpost_accent_orange", (0.85, 0.28, 0.03), roughness=0.45, metallic=0.0)
    MATS["yellow"] = m("outpost_accent_yellow", (0.95, 0.62, 0.02), roughness=0.45, metallic=0.0)
    MATS["window"] = m("outpost_window_warm", (1.0, 0.85, 0.6), roughness=0.3,
                       emission=(1.0, 0.78, 0.5), emission_strength=3.5)
    MATS["light"] = m("outpost_light_orange", (1.0, 0.45, 0.1), roughness=0.3,
                      emission=(1.0, 0.42, 0.08), emission_strength=5.0)
    MATS["ore"] = m("outpost_ore", (0.22, 0.17, 0.13), roughness=0.9, metallic=0.1)


class Part:
    """One output mesh object, built in a single bmesh with named material slots.
    Same API as gen_station.Part, plus beam / slab / rock helpers."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.slots = []

    def mi(self, key):
        mat = MATS[key]
        if mat not in self.slots:
            self.slots.append(mat)
        return self.slots.index(mat)

    def _faces(self, verts):
        return list({f for v in verts for f in v.link_faces})

    def box(self, center, size, mat, rot_z=0.0, bevel=0.12):
        m = Matrix.Translation(center) @ Matrix.Rotation(rot_z, 4, "Z")
        m = m @ Matrix.Diagonal((*size, 1.0))
        verts = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)["verts"]
        idx = self.mi(mat)
        for f in self._faces(verts):
            f.material_index = idx
        if bevel > 0:
            edges = list({e for v in verts for e in v.link_edges})
            res = bmesh.ops.bevel(self.bm, geom=verts + edges, offset=min(size) * bevel,
                                  segments=1, affect="EDGES", profile=0.5, clamp_overlap=True)
            for f in res["faces"]:
                f.material_index = idx

    def beam(self, p0, p1, w, h, mat, up=Vector((0, 0, 1))):
        """Square beam from p0 to p1; h measured along `up`."""
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        x = d.normalized()
        if abs(x.dot(up)) > 0.99:
            up = Vector((1, 0, 0))
        z = (up - x * up.dot(x)).normalized()
        y = z.cross(x)
        rot = Matrix((x, y, z)).transposed().to_4x4()
        m = Matrix.Translation((p0 + p1) / 2) @ rot @ Matrix.Diagonal((d.length, w, h, 1.0))
        verts = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)["verts"]
        idx = self.mi(mat)
        for f in self._faces(verts):
            f.material_index = idx

    def cyl(self, center, r1, r2, depth, mat, segs=12, axis_rot=None):
        m = Matrix.Translation(center)
        if axis_rot is not None:
            m = m @ axis_rot
        r = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segs,
                                  radius1=r1, radius2=r2, depth=depth, matrix=m)
        idx = self.mi(mat)
        for f in self._faces(r["verts"]):
            f.material_index = idx

    def slab(self, pts, z0, z1, mat, matrix=None):
        """Extrude a convex CCW polygon (local XY) from z0 to z1."""
        m = matrix or Matrix()
        bot = [self.bm.verts.new(m @ Vector((x, y, z0))) for x, y in pts]
        top = [self.bm.verts.new(m @ Vector((x, y, z1))) for x, y in pts]
        idx = self.mi(mat)
        faces = [self.bm.faces.new(list(reversed(bot))), self.bm.faces.new(top)]
        n = len(pts)
        for i in range(n):
            j = (i + 1) % n
            faces.append(self.bm.faces.new((bot[i], bot[j], top[j], top[i])))
        for f in faces:
            f.material_index = idx

    def hazard(self, x0, x1, w, z0, z1, matrix=None, pitch=1.2):
        """Diagonal yellow/dark stripe band along local X (x0..x1), width w across Y."""
        n = max(2, int(round((x1 - x0) / pitch)))
        s = (x1 - x0) / n
        skew = w * 0.7
        for i in range(-1, n + 1):
            a, b = x0 + i * s, x0 + (i + 1) * s
            q = [(a, -w / 2), (b, -w / 2), (b + skew, w / 2), (a + skew, w / 2)]
            q = [(min(max(x, x0), x1), y) for x, y in q]
            if abs(q[1][0] - q[0][0]) < 1e-3 and abs(q[2][0] - q[3][0]) < 1e-3:
                continue
            # drop degenerate corners from clamping
            pts = []
            for pt in q:
                if not pts or (Vector(pt) - Vector(pts[-1])).length > 1e-3:
                    pts.append(pt)
            if len(pts) > 2 and (Vector(pts[0]) - Vector(pts[-1])).length < 1e-3:
                pts.pop()
            if len(pts) < 3:
                continue
            self.slab(pts, z0, z1, "yellow" if i % 2 == 0 else "dark", matrix)

    def rock(self, center, r, mat, rng):
        m = Matrix.Translation(center) @ Matrix.Rotation(rng.uniform(0, 6.3), 4, "Z")
        m = m @ Matrix.Diagonal((r * rng.uniform(0.8, 1.3), r * rng.uniform(0.8, 1.2),
                                 r * rng.uniform(0.6, 0.9), 1.0))
        verts = bmesh.ops.create_icosphere(self.bm, subdivisions=1, radius=1.0, matrix=m)["verts"]
        for v in verts:
            v.co += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * r * 0.15
        idx = self.mi(mat)
        for f in self._faces(verts):
            f.material_index = idx

    def lathe(self, profile, segs, mat_fn, matrix=None, start=0.0):
        """profile: list of (r, z) from axis to axis. mat_fn(seg_i, edge_j) -> material key."""
        m = matrix or Matrix()
        rings = []
        for i in range(segs):
            a = start + 2 * math.pi * i / segs
            ca, sa = math.cos(a), math.sin(a)
            rings.append([self.bm.verts.new(m @ Vector((r * ca, r * sa, z))) for r, z in profile])
        for i in range(segs):
            a, b = rings[i], rings[(i + 1) % segs]
            for j in range(len(profile) - 1):
                if profile[j][0] < 1e-4 and profile[j + 1][0] < 1e-4:
                    continue
                if profile[j][0] < 1e-4:
                    vs = (a[j], b[j + 1], a[j + 1])
                elif profile[j + 1][0] < 1e-4:
                    vs = (a[j], b[j], a[j + 1])
                else:
                    vs = (a[j], b[j], b[j + 1], a[j + 1])
                f = self.bm.faces.new(vs)
                f.material_index = self.mi(mat_fn(i, j))
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


V = Vector
# Frame for hazard bands on the vertical front face of the mouth (band local X = world X,
# band local Y = world Z, extrusion along world -Y).
FRONT = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


# ---------------------------------------------------------------- hangar
def build_hangar(rng):
    p = Part("outpost_hangar")
    y0, y1 = MOUTH_Y, 9.0
    cy, ln = (y0 + y1) / 2, y1 - y0
    # Shell: floor, side walls, roof, back wall. Bay interior x -6..6, z -3..5.5.
    p.box(V((0, cy, -4.0)), (18, ln, 2.0), "hull2")
    for sx in (-1, 1):
        p.box(V((sx * 7.5, cy, 0.25)), (3.0, ln, 10.5), "hull")
    p.box(V((0, cy, 6.75)), (18.6, ln, 2.5), "hull")
    p.box(V((0, y1 - 1.0, 1.25)), (12.2, 2.0, 8.5), "dark", bevel=0.0)
    # Bay interior: warm glow back panel, ceiling light strips, floor guide lights
    p.box(V((0, y1 - 2.1, 1.25)), (11.0, 0.2, 7.0), "window", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 5.95, cy + 1, 4.6)), (0.12, ln - 4, 0.5), "window", bevel=0.0)
        p.box(V((sx * 5.95, cy + 1, -1.5)), (0.12, ln - 4, 0.3), "light", bevel=0.0)
        for k in range(6):
            p.box(V((sx * 3.2, y0 + 2 + k * 3.6, -2.95)), (0.7, 1.4, 0.1), "light", bevel=0.0)
    p.box(V((0, cy + 1, 5.45)), (2.0, ln - 4, 0.1), "window", bevel=0.0)

    # Mouth frame: heavy grey surround with hazard stripes on the front face
    fy = y0 - 0.8
    p.box(V((0, fy, 7.0)), (19.6, 1.6, 3.4), "hull2")
    p.box(V((0, fy, -4.2)), (19.6, 1.6, 2.4), "hull2")
    for sx in (-1, 1):
        p.box(V((sx * 8.0, fy, 1.4)), (3.6, 1.6, 13.0), "hull2")
    m = Matrix.Translation(V((0, fy - 0.8, 0))) @ FRONT
    p.hazard(-9.4, 9.4, 1.6, 0.0, 0.08, matrix=m @ Matrix.Translation((0, 7.4, 0)))
    p.hazard(-9.4, 9.4, 1.2, 0.0, 0.08, matrix=m @ Matrix.Translation((0, -4.3, 0)))
    # Glowing inner lip of the mouth
    p.box(V((0, fy - 0.75, 5.35)), (12.0, 0.2, 0.3), "window", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 6.05, fy - 0.75, 1.2)), (0.3, 0.2, 8.4), "window", bevel=0.0)
        p.box(V((sx * 9.3, fy - 0.6, 8.4)), (0.7, 0.7, 0.7), "light", bevel=0.0)
        p.box(V((sx * 9.3, fy - 0.6, -5.0)), (0.7, 0.7, 0.7), "light", bevel=0.0)

    # Roof: dark ribs, orange spine stripe, hazard band on the front lip, vents, lights
    rz = 8.0
    for k in range(6):
        p.box(V((0, y0 + 3.0 + k * 4.0, rz + 0.3)), (19.0, 0.9, 0.6), "dark", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 4.2, cy + 1.5, rz + 0.08)), (1.0, ln - 6, 0.16), "orange", bevel=0.0)
    p.hazard(-9.6, 9.6, 2.0, rz + 0.6, rz + 0.75,
             matrix=Matrix.Translation((0, fy, 0)))
    p.box(V((0, y1 - 5.0, rz + 1.0)), (6.0, 5.0, 2.0), "hull2")
    p.box(V((0, y1 - 5.0, rz + 2.05)), (4.4, 3.6, 0.2), "dark", bevel=0.0)
    for k in range(3):
        p.box(V((-1.6 + k * 1.6, y1 - 5.0, rz + 2.2)), (0.9, 3.0, 0.15), "hull2", bevel=0.0)
    for sx in (-1, 1):
        for yy in (y0 + 1.0, y1 - 0.6):
            p.box(V((sx * 8.8, yy, rz + 0.3)), (0.6, 0.6, 0.6), "light", bevel=0.0)
    # Side wall buttresses + window strips
    for sx in (-1, 1):
        for k in range(4):
            p.box(V((sx * 9.3, y0 + 4.5 + k * 5.5, 0.0)), (1.2, 1.4, 9.0), "dark", bevel=0.0)
        p.box(V((sx * 9.03, cy + 1.5, 3.2)), (0.1, ln - 8, 0.45), "window", bevel=0.0)

    # Apron: landing deck in front of the mouth, hazard edges, centre guide lights
    ay0, ay1 = y0 - 1.6, y0 - 9.6
    acy = (ay0 + ay1) / 2
    p.box(V((0, acy, -4.3)), (15.0, ay0 - ay1, 1.4), "hull2")
    p.box(V((0, acy, -5.4)), (11.0, ay0 - ay1 - 1.0, 1.0), "dark", bevel=0.0)
    for sx in (-1, 1):
        rot = Matrix.Translation((sx * 6.8, acy, 0)) @ Matrix.Rotation(math.pi / 2, 4, "Z")
        p.hazard(ay1 - acy + 0.2, ay0 - acy, 1.2, -3.6, -3.45, matrix=rot)
    p.hazard(-7.5, 7.5, 1.0, -3.6, -3.45, matrix=Matrix.Translation((0, ay1 + 0.6, 0)))
    for k in range(4):
        p.box(V((0, ay1 + 1.8 + k * 1.9, -3.55)), (1.4, 0.6, 0.12), "light", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 7.3, ay1 + 0.2, -3.2)), (0.7, 0.7, 0.7), "light", bevel=0.0)
        p.cyl(V((sx * 7.3, ay1 + 0.2, -1.5)), 0.12, 0.06, 2.8, "dark", segs=5)
        p.box(V((sx * 7.3, ay1 + 0.2, 0.0)), (0.4, 0.4, 0.4), "window", bevel=0.0)
    return p


# ---------------------------------------------------------------- silos + hoppers
SILOS = [(14.5, -3.5), (21.0, -3.5), (14.5, 3.5), (21.0, 3.5)]


def build_silos(rng):
    p = Part("outpost_silos")
    R = 3.0
    prof = [(0, -11.0), (0.8, -11.0), (0.8, -9.6), (R, -6.0), (R, -5.4), (R + 0.15, -5.4),
            (R + 0.15, -4.6), (R, -4.6), (R, 1.0), (R + 0.15, 1.0), (R + 0.15, 1.8), (R, 1.8),
            (R, 6.2), (R, 7.6), (R + 0.1, 7.6), (R + 0.1, 8.0), (2.4, 9.0), (1.2, 9.6),
            (1.2, 10.2), (0, 10.2)]
    edge = {0: "dark", 1: "dark", 2: "dark", 3: "dark", 4: "dark", 5: "dark", 6: "dark",
            7: "hull", 8: "dark", 9: "dark", 10: "dark", 11: "hull", 12: "yellow", 13: "dark",
            14: "dark", 15: "hull", 16: "hull2", 17: "dark", 18: "dark"}

    def silo_mat(i, j):
        k = edge[j]
        if k == "hull" and i % 4 in (1, 2):
            return "hull2"
        if k == "yellow" and i % 2 == 1:
            return "dark"
        return k
    for sx, sy in SILOS:
        p.lathe(prof, 16, silo_mat, matrix=Matrix.Translation((sx, sy, 0)))
        p.cyl(V((sx, sy, 10.4)), 0.5, 0.5, 0.4, "light", segs=6)
    # Support frame under the silos, tied to the hangar floor
    p.box(V((17.75, 0, -6.0)), (11.0, 11.5, 1.2), "dark", bevel=0.0)
    p.box(V((11.5, 0, -4.6)), (4.0, 3.0, 1.6), "hull2")
    for sx, sy in SILOS:
        p.box(V((sx, sy, -5.2)), (1.6, 1.6, 0.8), "hull2", bevel=0.0)
    # Top catwalk cross + conveyor tube from the hangar roof to the silo tops
    p.box(V((17.75, 0, 9.4)), (8.0, 1.2, 0.5), "dark", bevel=0.0)
    p.box(V((17.75, 0, 9.4)), (1.2, 8.5, 0.5), "dark", bevel=0.0)
    p.box(V((17.75, 0, 9.9)), (2.2, 2.2, 1.2), "hull2")
    p.beam(V((9.0, 0, 7.2)), V((16.6, 0, 9.9)), 1.4, 1.4, "hull2")
    p.beam(V((9.0, 0, 7.95)), V((16.6, 0, 10.65)), 0.6, 0.12, "yellow")
    for k in range(3):
        x = 10.5 + k * 2.2
        z = 7.2 + (x - 9.0) * (2.7 / 7.6)
        p.box(V((x, 0, z - 0.2)), (0.4, 1.8, 0.4), "dark", bevel=0.0)

    # Ore hoppers in front of the silos: yellow-rimmed bowls full of ore
    hop = [(0, -6.5), (1.1, -6.5), (1.1, -4.6), (3.6, 0.6), (3.9, 1.0), (3.9, 1.4), (3.4, 1.4),
           (0, 0.2)]
    hmat = {0: "dark", 1: "dark", 2: "hull2", 3: "dark", 4: "yellow", 5: "yellow", 6: "dark"}
    for hx, hy in ((14.0, -11.0), (21.5, -11.0)):
        p.lathe(hop, 12, lambda i, j: ("dark" if hmat[j] == "yellow" and i % 2 else hmat[j]),
                matrix=Matrix.Translation((hx, hy, 0)))
        p.cyl(V((hx, hy, 0.9)), 3.4, 3.4, 0.3, "ore", segs=12)
        for k in range(13):
            a = k * 2.4 + rng.uniform(-0.3, 0.3)
            rr = 2.5 * math.sqrt((k + 0.5) / 13)
            p.rock(V((hx + rr * math.cos(a), hy + rr * math.sin(a), 1.3 + (2.5 - rr) * 0.35)),
                   rng.uniform(0.8, 1.25), "ore", rng)
        p.box(V((hx, hy + 4.4, -2.0)), (1.2, 2.4, 1.2), "hull2", bevel=0.0)
        p.box(V((hx, hy, -7.0)), (1.8, 1.8, 1.0), "dark", bevel=0.0)
    p.beam(V((14.0, -11.0, -6.8)), V((21.5, -11.0, -6.8)), 1.0, 1.0, "dark")
    p.beam(V((17.75, -11.0, -6.8)), V((17.75, -5.0, -6.0)), 1.0, 1.0, "dark")
    p.beam(V((9.0, -11.0, -4.0)), V((14.0, -11.0, -6.0)), 1.0, 1.0, "dark")
    return p


# ---------------------------------------------------------------- crane
def build_crane(rng):
    p = Part("outpost_crane")
    base = V((-13.0, -8.0, 0))
    top = 13.0
    # Lattice tower: 4 dark posts with cross braces
    for dx in (-1, 1):
        for dy in (-1, 1):
            p.box(base + V((dx * 1.1, dy * 1.1, (top - 6.0) / 2 - 3.0)), (0.5, 0.5, top + 0.0),
                  "dark", bevel=0.0)
    for k in range(4):
        z0, z1 = -4.5 + k * 4.0, -0.5 + k * 4.0
        for side in range(4):
            a = side * math.pi / 2
            n = V((math.cos(a), math.sin(a), 0)) * 1.1
            t = V((-math.sin(a), math.cos(a), 0)) * 1.1
            p.beam(base + n - t + V((0, 0, z0)), base + n + t + V((0, 0, z1)), 0.25, 0.25, "dark")
    p.box(base + V((0, 0, -5.0)), (4.0, 4.0, 1.4), "hull2")
    p.box(base + V((-0.0, 0, top - 2.6)), (2.8, 2.8, 0.6), "yellow", bevel=0.0)
    # Slewing cab
    p.box(base + V((0, 0, top - 1.2)), (3.6, 3.6, 2.2), "hull")
    p.box(base + V((0, -1.85, top - 0.9)), (2.6, 0.1, 0.6), "window", bevel=0.0)
    # Boom: twin yellow chords along `d`, dark lacing, counter-jib with weight
    ang = math.radians(198)
    d = V((math.cos(ang), math.sin(ang), 0))
    side = V((-d.y, d.x, 0))
    z = top + 0.4
    L = 18.0
    for s in (-1, 1):
        p.beam(base + side * s * 0.8 + V((0, 0, z)), base + d * L + side * s * 0.5 + V((0, 0, z)),
               0.6, 0.9, "yellow")
        p.beam(base + side * s * 0.8 + V((0, 0, z)), base - d * 7.0 + side * s * 0.8 + V((0, 0, z)),
               0.6, 0.9, "yellow")
    for k in range(9):
        t0, t1 = 1.0 + k * 1.9, 2.0 + k * 1.9
        w0 = 0.8 - 0.3 * t0 / L
        p.beam(base + d * t0 + side * w0 + V((0, 0, z)), base + d * t1 - side * w0 + V((0, 0, z)),
               0.2, 0.3, "dark")
    p.beam(base + V((0, 0, top + 3.5)), base + d * (L - 1) + V((0, 0, z + 0.3)), 0.2, 0.2, "dark")
    p.beam(base + V((0, 0, top + 3.5)), base - d * 6.5 + V((0, 0, z + 0.3)), 0.2, 0.2, "dark")
    p.box(base + V((0, 0, top + 2.0)), (0.6, 0.6, 3.4), "dark", bevel=0.0)
    p.box(base + V((0, 0, top + 3.8)), (0.6, 0.6, 0.6), "light", bevel=0.0)
    p.box(base - d * 6.0 + V((0, 0, z - 0.3)), (3.0, 3.0, 2.2), "hull2", rot_z=ang)
    p.hazard(-1.4, 1.4, 1.0, 0.0, 0.1,
             matrix=Matrix.Translation(base - d * 6.0 + V((0, 0, z + 0.82))) @
             Matrix.Rotation(ang + math.pi / 2, 4, "Z"))
    p.box(base + d * L + V((0, 0, z)), (0.6, 0.6, 0.6), "light", bevel=0.0)
    # Trolley, cable, spreader and a hanging ore container
    tp = base + d * (L - 3.0)
    p.box(tp + V((0, 0, z - 0.6)), (1.4, 1.6, 0.5), "dark", bevel=0.0)
    p.cyl(tp + V((0, 0, z - 4.4)), 0.08, 0.08, 7.4, "dark", segs=4)
    p.box(tp + V((0, 0, z - 8.2)), (3.6, 1.6, 0.4), "yellow", rot_z=ang, bevel=0.0)
    p.box(tp + V((0, 0, z - 10.0)), (4.0, 2.4, 2.6), "orange", rot_z=ang)
    p.box(tp + V((0, 0, z - 8.65)), (4.1, 2.5, 0.2), "dark", rot_z=ang, bevel=0.0)
    for k in (-1, 0, 1):
        p.box(tp + d * k * 1.2 + V((0, 0, z - 10.0)), (0.2, 2.5, 2.4), "dark", rot_z=ang, bevel=0.0)
    return p


# ---------------------------------------------------------------- structure
def build_structure(rng):
    p = Part("outpost_structure")
    # Spine deck under hangar + crane foot + tower foot
    p.box(V((-13.0, 0, -6.0)), (8.0, 22.0, 1.2), "dark", bevel=0.0)
    p.box(V((-10.0, 0, -5.0)), (2.5, 16.0, 1.6), "hull2")
    # Control tower back-left
    tc = V((-13.0, 7.5, 0))
    p.box(tc + V((0, 0, 2.5)), (3.4, 3.4, 15.0), "hull2")
    p.box(tc + V((0, 0, -4.5)), (5.0, 5.0, 2.0), "hull")
    p.box(tc + V((0, 0, 11.4)), (6.0, 6.0, 3.0), "hull")
    p.box(tc + V((0, 0, 11.6)), (6.1, 6.1, 1.1), "window", bevel=0.0)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        p.box(tc + V((math.cos(a) * 4.25, math.sin(a) * 4.25, 11.6)), (0.5, 0.5, 1.3), "hull2",
              rot_z=a, bevel=0.0)
    p.box(tc + V((0, 0, 13.2)), (6.6, 6.6, 0.6), "dark", bevel=0.0)
    p.box(tc + V((0, 0, 13.6)), (6.0, 1.0, 0.12), "orange", bevel=0.0)
    p.cyl(tc + V((1.6, 1.6, 17.0)), 0.18, 0.07, 7.0, "dark", segs=6)
    p.box(tc + V((1.6, 1.6, 20.6)), (0.5, 0.5, 0.5), "light", bevel=0.0)
    dish = Matrix.Translation(tc + V((-1.4, -1.0, 14.8))) @ Matrix.Rotation(math.radians(-40), 4, "X")
    p.lathe([(0, 0), (1.2, 0.25), (2.2, 0.8), (2.4, 0.95), (2.4, 0.75), (2.0, 0.55), (0, -0.15)],
            14, lambda i, j: ("hull", "hull", "orange", "dark", "dark", "dark")[j], matrix=dish)
    p.cyl(tc + V((-1.4, -1.0, 13.9)), 0.2, 0.2, 1.0, "dark", segs=6)
    # Walkway tower -> hangar
    p.box(V((-10.2, 7.5, 3.0)), (3.0, 2.2, 2.0), "hull2")
    p.box(V((-10.2, 6.38, 3.0)), (2.2, 0.08, 0.4), "window", bevel=0.0)

    # Processing block behind the hangar, with pipes and radiator wings
    pb = V((0, 13.0, 0))
    p.box(pb + V((0, 0, -0.5)), (13.0, 7.0, 8.0), "hull2")
    p.box(pb + V((0, 0, 3.7)), (11.0, 5.4, 0.6), "dark", bevel=0.0)
    p.box(pb + V((0, 0, 4.05)), (11.4, 0.9, 0.12), "orange", bevel=0.0)
    for sx in (-1, 1):
        p.cyl(pb + V((sx * 3.2, 0.4, 5.0)), 1.5, 1.5, 2.4, "hull", segs=12)
        p.cyl(pb + V((sx * 3.2, 0.4, 6.3)), 1.5, 1.0, 0.4, "hull", segs=12)
        p.cyl(pb + V((sx * 3.2, 0.4, 6.6)), 0.45, 0.45, 0.3, "light", segs=6)
        p.box(pb + V((sx * 6.53, 0, 0.5)), (0.08, 5.0, 0.4), "window", bevel=0.0)
    p.hazard(-6.5, 6.5, 1.0, 0.0, 0.08,
             matrix=Matrix.Translation(pb + V((0, 3.55, -2.6))) @
             Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1))))
    # Radiator wings out the back
    for sx in (-1, 1):
        p.box(pb + V((sx * 4.0, 7.5, -0.5)), (0.8, 9.0, 0.8), "dark", bevel=0.0)
        for k in range(4):
            p.box(pb + V((sx * 4.0 + sx * 2.6, 4.6 + k * 2.2, -0.5)), (4.6, 1.8, 0.2), "dark",
                  bevel=0.0)
            p.box(pb + V((sx * 4.0 + sx * 2.6, 4.6 + k * 2.2, -0.35)), (4.2, 0.25, 0.1), "hull2",
                  bevel=0.0)
        p.box(pb + V((sx * 4.0, 12.2, -0.5)), (0.9, 0.9, 0.9), "light", bevel=0.0)
    # Fuel / ore pipes between hangar side and silo frame
    for z in (-1.0, 0.4):
        p.cyl(V((10.5, 7.0, z)), 0.45, 0.45, 3.2, "dark", segs=8,
              axis_rot=Matrix.Rotation(math.pi / 2, 4, "Y"))
    return p


def build_outpost():
    rng = random.Random(7310)
    build_materials()
    root = bpy.data.objects.new("mining_outpost", None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 10
    bpy.context.scene.collection.objects.link(root)
    objs = [b(rng).finish(root) for b in (build_hangar, build_silos, build_crane, build_structure)]
    for name, pos in (("dock_point", DOCK_POS), ("spawn_point", SPAWN_POS)):
        e = bpy.data.objects.new(name, None)
        e.empty_display_type = "SINGLE_ARROW"
        e.empty_display_size = 4
        e.location = pos
        e.rotation_euler = (0, 0, math.pi)  # Godot -Z of the empty points out of the mouth
        bpy.context.scene.collection.objects.link(e)
        e.parent = root
    return root, objs


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    common.reset_scene()
    root, objs = build_outpost()
    total = 0
    for o in objs:
        tris = sum(len(pl.vertices) - 2 for pl in o.data.polygons)
        total += tris
        print(f"STAT {o.name} tris={tris} mats={[m.name for m in o.data.materials]}")
    print(f"STAT total tris={total}")
    bpy.context.preferences.filepaths.save_version = 0  # no .blend1 on re-run
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(common.ROOT, "blender", "mining_outpost.blend"))
    common.export_glb(root, OUT)
    if "--no-preview" not in argv:
        common.setup_preview(cam_loc=(-45, -75, 80), cam_target=(2, -1, 0), ortho_scale=72,
                             res=(1600, 1200), key_dir=(-0.6, -0.35, 0.7), key_energy=3.5)
        common.render(os.path.join(common.PREVIEW_DIR, "mining_outpost_preview.png"))


main()
