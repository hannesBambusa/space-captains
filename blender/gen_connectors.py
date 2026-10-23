"""Generate the modular connector-corridor kit (segment, collar, junction) + previews.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python /Users/hannesalm/code/games/space-majesty/blender/gen_connectors.py
  Add `-- --no-preview` to skip the PNG renders, `-- --no-textures` for flat materials.

Axis convention (Blender Z up, exported +Y up, so Blender +Y = Godot -Z):
  corridor_segment   tube centre line x = 0, z = 0 (Godot y = 0), Blender y 0..20
                     = Godot z 0..-20. Tiles end to end every 20 m (ends are identical).
  corridor_collar    flange plane at Blender y = 0 facing -Y (Godot +Z, the building
                     side), neck end at Blender y = 5 (Godot z = -5), where a segment starts.
  corridor_junction  centred on the origin, port faces at +-5 m on Blender X and Y
                     (Godot +-X and +-Z). A segment rotated to face out of a port starts
                     at the port face.
Every piece is one mesh under an empty root. The roots carry glTF extras:
  segment_length = 20.0, collar_length = 5.0, port_offset = 5.0.
All three share one baked 1024 atlas (station_textures.py surface kinds).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
import station_textures as st  # noqa: E402

OUT_DIR = os.path.join(common.ROOT, "assets", "models", "buildings", "connectors")
BLEND = os.path.join(common.ROOT, "blender", "connectors.blend")
SEG_LEN = 20.0
COLLAR_LEN = 5.0
PORT = 5.0          # junction port face distance from centre
R_TUBE = 2.6        # pressure tube radius
R_RIB = 2.88        # ring rib outer radius
TRUSS_IN, TRUSS_OUT, TRUSS_H = 2.85, 3.75, 0.6   # side truss chord x and half height
ATLAS_RES = 1024
ALONG_Y = Matrix.Rotation(-math.pi / 2, 4, "X")  # lathe/cyl local Z -> world +Y
TUBE_START = math.radians(15)   # 12-gon with a flat face on top (shared by every port)

MATS = {}


def build_materials():
    m = common.make_material
    MATS["hull"] = m("conn_hull_white", (0.78, 0.78, 0.76), roughness=0.45, metallic=0.1)
    MATS["hull2"] = m("conn_hull_grey", (0.50, 0.52, 0.55), roughness=0.5, metallic=0.15)
    MATS["dark"] = m("conn_structure_dark", (0.06, 0.065, 0.07), roughness=0.55, metallic=0.5)
    MATS["orange"] = m("conn_accent_orange", (0.85, 0.28, 0.03), roughness=0.45)
    MATS["mli"] = m("conn_mli_white", (0.8, 0.8, 0.78), roughness=0.85)
    MATS["mli_gold"] = m("conn_mli_gold", (0.8, 0.52, 0.15), roughness=0.4, metallic=0.9)
    MATS["hazard"] = m("conn_hazard", (0.8, 0.55, 0.02), roughness=0.5)
    MATS["window"] = m("conn_window_warm", (1.0, 0.85, 0.6), roughness=0.3,
                       emission=(1.0, 0.78, 0.5), emission_strength=3.5)
    MATS["light"] = m("conn_light_orange", (1.0, 0.45, 0.1), roughness=0.3,
                      emission=(1.0, 0.42, 0.08), emission_strength=5.0)


class Part:
    """gen_station.Part with a full-matrix box/beam. Writes the "panel" UV layer
    (metres per primitive) that station_textures uses for plate layout."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.slots = []
        self.uv = self.bm.loops.layers.uv.new("panel")
        self.n_prims = 0

    def _offset(self):
        self.n_prims += 1
        k = self.n_prims
        return Vector(((k * 7) % 31 * 64.0, (k * 13) % 29 * 64.0))

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

    def box(self, center, size, mat, frame=None, bevel=0.0):
        """Box of `size` at `center`, oriented by the 4x4 rotation `frame`."""
        fr = Matrix.Translation(center) @ (frame or Matrix())
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
        self._planar_uv(faces, fr.inverted(), Vector(size) / 2)

    def beam(self, p0, p1, w, h, mat, up=Vector((0, 0, 1))):
        """Square beam p0 -> p1, w across, h along `up`."""
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        x = d.normalized()
        if abs(x.dot(up)) > 0.99:
            up = Vector((1, 0, 0))
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

    def lathe(self, profile, segs, mat_fn, matrix=None, start=0.0):
        """profile: list of (r, z). mat_fn(seg_i, edge_j) -> material key."""
        m = matrix or Matrix()
        rings = []
        for i in range(segs):
            a = start + 2 * math.pi * i / segs
            ca, sa = math.cos(a), math.sin(a)
            rings.append([self.bm.verts.new(m @ Vector((r * ca, r * sa, z))) for r, z in profile])
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


def face_frame(theta, y):
    """Frame on the tube's 12-gon face centred at angle theta (radians, world XZ plane,
    0 = +X, pi/2 = +Z top). Local X = along Y, local Y = tangent, local Z = outward."""
    n = Vector((math.cos(theta), 0, math.sin(theta)))
    ax = Vector((0, 1, 0))
    t = n.cross(ax)
    return Matrix((ax, t, n)).transposed().to_4x4(), n


def tube_lathe_matrix(origin=(0, 0, 0), rz=0.0):
    """Lathe frame for a 12-gon tube along local +Y, rotated about world Z by rz."""
    return Matrix.Translation(origin) @ Matrix.Rotation(rz, 4, "Z") @ ALONG_Y


# ---------------------------------------------------------------- segment
def build_segment(root):
    p = Part("corridor_segment_mesh")
    L = SEG_LEN
    bays = [0.0, 5.0, 10.0, 15.0, 20.0]
    # lathe angle a (local XY of ALONG_Y frame) maps to world (r cos a, 0, -r sin a):
    # face i is centred at a = 30 * (i + 1) deg, so i = 8 is the top face (a = 270)
    # and i in 2..4 are the bottom faces.
    up_faces = {6, 7, 8, 9, 10}

    def tube_mat(i, j):
        if j in (0, 5):
            return "dark"                      # end bulkheads (hidden when joined)
        if i not in up_faces and i not in (5, 11):
            return "hull2"
        return "mli" if j % 2 == 0 else "hull"
    # closed profile: bulkhead discs at both ends so a dangling end is not a hole
    p.lathe([(0.0, 0.0)] + [(R_TUBE, y) for y in bays] + [(0.0, L)], 12, tube_mat,
            matrix=ALONG_Y, start=TUBE_START)
    top = R_TUBE * math.cos(math.radians(15))
    p.box((0, L / 2, top + 0.02), (0.5, L, 0.05), "orange")      # orange spine stripe

    # ring ribs every 5 m; halves at the ends so a joint reads as one full rib
    def rib(y0, y1):
        prof = [(R_TUBE, y0), (R_RIB, y0 + 0.04), (R_RIB, y1 - 0.04), (R_TUBE, y1)]
        p.lathe(prof, 12, lambda i, j: "hull2" if j == 1 else "dark", matrix=ALONG_Y,
                start=TUBE_START)
    rib(0.0, 0.3)
    for y in (5.0, 10.0, 15.0):
        rib(y - 0.3, y + 0.3)
    rib(L - 0.3, L)

    # side box trusses: 4 chords per side, posts at the ribs, Warren diagonals on the
    # outer face and a zigzag on the top face (reads as a truss from the RTS camera)
    e = 0.06     # keep diagonal corners inside 0..L so the ends stay flush
    for sx in (-1, 1):
        xi, xo = sx * TRUSS_IN, sx * TRUSS_OUT
        for x in (xi, xo):
            for z in (-TRUSS_H, TRUSS_H):
                p.beam((x, 0, z), (x, L, z), 0.18, 0.18, "hull2")
        for k, y in enumerate(bays):
            y0, y1 = max(0.0, y - 0.09), min(L, y + 0.09)
            for x in (xi, xo):
                p.box((x, (y0 + y1) / 2, 0), (0.14, y1 - y0, 2 * TRUSS_H), "hull2")
            # yoke arm from the rib out through the truss (rung)
            yw0, yw1 = max(0.0, y - 0.2), min(L, y + 0.2)
            p.box((sx * (R_RIB + TRUSS_OUT) / 2, (yw0 + yw1) / 2, 0),
                  (TRUSS_OUT - R_RIB + 0.1, yw1 - yw0, 0.45), "dark")
        for k in range(4):
            ya, yb = (bays[k], bays[k + 1]) if k % 2 == 0 else (bays[k + 1], bays[k])
            ya, yb = min(max(ya, e), L - e), min(max(yb, e), L - e)
            p.beam((xo, ya, -TRUSS_H), (xo, yb, TRUSS_H), 0.1, 0.1, "dark",
                   up=Vector((1, 0, 0)))
        for k in range(8):
            ya, yb = k * 2.5, (k + 1) * 2.5
            ya, yb = min(max(ya, e), L - e), min(max(yb, e), L - e)
            xa, xb = (xi, xo) if k % 2 == 0 else (xo, xi)
            p.beam((xa, ya, TRUSS_H), (xb, yb, TRUSS_H), 0.1, 0.1, "dark")
    # cable tray inside the +X truss (on the bottom chords), two cable runs in it
    xc = (TRUSS_IN + TRUSS_OUT) / 2
    p.box((xc, L / 2, -TRUSS_H + 0.12), (TRUSS_OUT - TRUSS_IN - 0.2, L, 0.08), "dark")
    p.cyl(Vector((xc - 0.17, L / 2, -TRUSS_H + 0.28)), 0.13, 0.13, L, "orange", segs=6,
          axis_rot=ALONG_Y)
    p.cyl(Vector((xc + 0.17, L / 2, -TRUSS_H + 0.26)), 0.11, 0.11, L, "hull", segs=6,
          axis_rot=ALONG_Y)
    # pipes inside the -X truss: an insulated (gold MLI) line and a white coolant line
    p.cyl(Vector((-xc + 0.08, L / 2, 0.05)), 0.27, 0.27, L, "mli_gold", segs=8,
          axis_rot=ALONG_Y)
    p.cyl(Vector((-xc - 0.22, L / 2, -0.32)), 0.12, 0.12, L, "hull", segs=6,
          axis_rot=ALONG_Y)

    # window strips on the upper flanks (faces at 30 deg elevation), one per bay per side
    for theta in (math.radians(30), math.radians(150)):
        for k in range(4):
            y = bays[k] + 2.5
            fr, n = face_frame(theta, y)
            c = n * (R_TUBE * math.cos(math.radians(15)) + 0.02) + Vector((0, y, 0))
            p.box(c, (3.0, 0.32, 0.06), "window", frame=fr)
    # nav lights: orange on the truss ends at mid span, warm strip lights on top ribs
    for sx in (-1, 1):
        p.box((sx * (TRUSS_OUT + 0.12), 10.0, 0.0), (0.22, 0.5, 0.5), "light")
    for y in (5.0, 15.0):
        p.box((0, y, R_RIB + 0.04), (1.0, 0.36, 0.1), "window")
    obj = p.finish(root)
    return obj


# ---------------------------------------------------------------- collar
def build_collar(root):
    p = Part("corridor_collar_mesh")
    prof = [(0, 0.22), (2.05, 0.22), (2.3, 0.0), (3.5, 0.0), (3.5, 0.5), (3.2, 0.72),
            (3.2, 1.3), (3.2, 1.6), (3.2, 2.6), (2.85, 3.2), (0, 3.2)]
    edge = {0: "dark", 1: "dark", 2: "hazard", 3: "hazard", 4: "hull2", 5: "hull2",
            6: "dark", 7: "hazard", 8: "hull2", 9: "hull2"}

    def cm(i, j):
        k = edge[j]
        if k == "hull" and i % 4 in (1, 2):
            return "mli"
        return k
    p.lathe(prof, 16, cm, matrix=ALONG_Y)
    # lit ring in the dark band
    p.lathe([(3.18, 1.33), (3.3, 1.38), (3.3, 1.52), (3.18, 1.57)], 16, lambda i, j: "window",
            matrix=ALONG_Y)
    # neck: same 12-gon as the corridor tube, end rib half matches the segment's half rib
    neck = [(R_TUBE, 3.0), (R_TUBE, COLLAR_LEN - 0.3), (R_RIB, COLLAR_LEN - 0.26),
            (R_RIB, COLLAR_LEN - 0.0), (0, COLLAR_LEN)]
    nm = {0: "hull", 1: "dark", 2: "hull2", 3: "dark"}
    p.lathe(neck, 12, lambda i, j: "orange" if (j == 0 and i == 8) else nm[j], matrix=ALONG_Y,
            start=TUBE_START)
    # truss shoes where the corridor's side trusses land
    xc = (TRUSS_IN + TRUSS_OUT) / 2
    for sx in (-1, 1):
        p.box((sx * xc, 3.5, 0), (TRUSS_OUT - TRUSS_IN + 0.16, 3.0, 2 * TRUSS_H + 0.16), "dark",
              bevel=0.05)
        p.box((sx * (TRUSS_OUT + 0.1), 4.0, 0), (0.2, 0.5, 0.5), "light")
    # airlock control node on top, with a window strip and an antenna
    p.box((0, 2.0, 3.55), (2.4, 2.2, 1.2), "hull", bevel=0.06)
    p.box((0, 2.0, 4.2), (2.0, 1.8, 0.16), "dark")
    for sx in (-1, 1):
        p.box((sx * 1.21, 2.0, 3.7), (0.06, 1.6, 0.28), "window")
    p.cyl(Vector((0.7, 2.5, 5.2)), 0.07, 0.04, 2.0, "dark", segs=6)
    p.cyl(Vector((0.7, 2.5, 6.25)), 0.16, 0.16, 0.18, "light", segs=6)
    p.box((-0.6, 1.4, 4.45), (0.6, 0.6, 0.35), "hull2", bevel=0.08)
    # hazard chevron plate on top of the flange, orange lights on the flange rim
    for k in range(4):
        a = math.radians(45 + 90 * k)
        x, z = 3.55 * math.cos(a), 3.55 * math.sin(a)
        n = Vector((math.cos(a), 0, math.sin(a)))
        fr = Matrix((Vector((0, 1, 0)), n.cross(Vector((0, 1, 0))), n)).transposed().to_4x4()
        p.box((x, 0.25, z), (0.3, 0.45, 0.14), "light", frame=fr)
    # under-slung gas tanks
    for sx in (-1, 1):
        p.cyl(Vector((sx * 1.5, 2.0, -3.25)), 0.5, 0.5, 1.8, "mli_gold", segs=8, axis_rot=ALONG_Y)
        p.box((sx * 1.5, 2.0, -2.85), (0.3, 0.3, 0.6), "dark")
    return p.finish(root)


# ---------------------------------------------------------------- junction
def build_junction(root):
    p = Part("corridor_junction_mesh")
    ap = 4.5                                   # apothem: 9 m across the flats
    rv = ap / math.cos(math.pi / 8)            # octagon vertex radius
    prof = [(0, 4.25), (1.5, 4.25), (1.75, 4.0), (3.3, 4.0), (rv, 2.7), (rv, 2.25),
            (rv, -2.6), (3.3, -3.9), (0, -3.9)]
    # faces centred at 45 + 45 i deg; odd i are the port faces (+-X, +-Y)
    edge = {0: "dark", 1: "dark", 2: "mli", 3: "hull", 4: "orange", 5: "hull", 6: "hull2",
            7: "dark"}

    def jm(i, j):
        k = edge[j]
        if k == "hull" and i % 2 == 1:
            return "hull2" if j == 5 else "hull"
        if k == "mli" and i % 2 == 1:
            return "hull2"
        return k
    p.lathe(prof, 8, jm, start=math.pi / 8)
    # ports: 12-gon sleeves exactly matching the corridor tube, rib half at the port face
    port_prof = [(R_TUBE, 3.3), (R_TUBE, PORT - 0.3), (R_RIB, PORT - 0.26), (R_RIB, PORT),
                 (0, PORT)]
    pm = {0: "hazard", 1: "dark", 2: "hull2", 3: "dark"}
    xc = (TRUSS_IN + TRUSS_OUT) / 2
    for rz in (0.0, math.pi / 2, math.pi, -math.pi / 2):
        M = tube_lathe_matrix(rz=rz)
        p.lathe(port_prof, 12, lambda i, j: pm[j], matrix=M, start=TUBE_START)
        p.lathe([(R_TUBE - 0.02, 4.05), (2.7, 4.08), (2.7, 4.32), (R_TUBE - 0.02, 4.35)], 12,
                lambda i, j: "window", matrix=M, start=TUBE_START)
        R = Matrix.Rotation(rz, 4, "Z")
        for sx in (-1, 1):   # truss shoes
            p.box(R @ Vector((sx * xc, 4.45, 0)), (TRUSS_OUT - TRUSS_IN + 0.16, 1.1,
                  2 * TRUSS_H + 0.16), "dark", frame=R, bevel=0.05)
        p.box(R @ Vector((0, 4.6, R_RIB + 0.05)), (0.8, 0.3, 0.12), "light", frame=R)
    # corner blocks between ports (RCS / utility boxes) with lights
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        R = Matrix.Rotation(a - math.pi / 2, 4, "Z")
        c = Vector((math.cos(a), math.sin(a), 0)) * 4.75
        p.box(c, (1.7, 1.2, 1.6), "hull2", frame=R, bevel=0.06)
        p.box(c + Vector((0, 0, 0.85)), (1.3, 0.9, 0.12), "dark", frame=R)
        p.box(c + Vector((math.cos(a), math.sin(a), 0)) * 0.62 + Vector((0, 0, 0.5)),
              (0.4, 0.1, 0.25), "light", frame=R)
        # window strip on the diagonal faces above the block
        p.box(Vector((math.cos(a), math.sin(a), 0)) * (ap + 0.02) + Vector((0, 0, 1.55)),
              (2.6, 0.06, 0.32), "window", frame=R)
    # top: hatch, beacon, greebles, antenna
    p.cyl(Vector((0, 0, 4.42)), 0.55, 0.45, 0.35, "light", segs=8)
    p.box(Vector((2.3, 0.9, 4.25)), (1.0, 1.4, 0.55), "hull2", bevel=0.08)
    p.box(Vector((-2.0, -1.4, 4.2)), (1.4, 0.8, 0.45), "dark", bevel=0.08)
    p.box(Vector((-1.4, 2.2, 4.15)), (0.9, 0.9, 0.35), "hull", bevel=0.08)
    p.cyl(Vector((1.9, -2.0, 5.3)), 0.08, 0.04, 2.6, "dark", segs=6)
    p.cyl(Vector((1.9, -2.0, 6.65)), 0.17, 0.17, 0.2, "light", segs=6)
    # under-slung tank
    p.cyl(Vector((0, 0, -4.3)), 1.4, 1.0, 0.9, "mli_gold", segs=8)
    return p.finish(root)


# ---------------------------------------------------------------- textures
def texture_kit(objs, offsets):
    """Bake one shared atlas for all pieces. Pieces are moved apart (mesh data) while
    baking so AO and the buried-face test do not see each other."""
    st.ATLAS_RES = ATLAS_RES
    for o, off in zip(objs, offsets):
        o.data.transform(Matrix.Translation(off))
    atlas_keys = [k for k in st.KINDS if k in MATS]
    atlas_mats = {MATS[k] for k in atlas_keys}
    st.unwrap_atlas(objs, atlas_mats)
    for o in objs:
        st.zero_uvs(o, {MATS[k] for k in st.EMISSIVE})
    st.setup_cycles(8)
    dummy = st.new_image("bake_dummy", 8, False)
    for k in st.EMISSIVE:
        st.add_dummy_target(MATS[k], dummy)

    masks = st.new_image("conn_masks", ATLAS_RES, True)
    bms = {}
    for k in atlas_keys:
        nb = st.NB(MATS[k])
        geo = nb.n("ShaderNodeNewGeometry")
        aon = nb.n("ShaderNodeAmbientOcclusion", samples=16)
        aon.inputs["Distance"].default_value = 0.8
        aof = nb.n("ShaderNodeAmbientOcclusion", samples=16)
        aof.inputs["Distance"].default_value = 4.0
        bev = nb.n("ShaderNodeBevel", samples=8)
        bev.inputs["Radius"].default_value = 0.2
        edge = nb.m("MULTIPLY", nb.inv(nb.v("DOT_PRODUCT", bev.outputs["Normal"],
                                            geo.outputs["Normal"])), 14.0, clamp=True)
        col = nb.comb(aon.outputs["AO"], aof.outputs["AO"], edge)
        bm = st.BakeMat(MATS[k], dict(masks=col), nb)
        bm.set_pass("masks", masks)
        bms[k] = bm
    st.bake(objs, "EMIT", 16, masks)

    albedo = st.new_image("connectors_albedo", ATLAS_RES, False)
    mr = st.new_image("connectors_mr", ATLAS_RES, True)
    normal = st.new_image("connectors_normal", ATLAS_RES, True)
    for i, k in enumerate(atlas_keys):
        nb = st.NB(MATS[k])
        outs = st.build_surface(nb, k, st.KINDS[k], masks, i + 1, [])
        bms[k] = st.BakeMat(MATS[k], outs, nb)
    for name, img, kind in (("albedo", albedo, "EMIT"), ("mr", mr, "EMIT"),
                            ("normal", normal, "NORMAL")):
        for bm in bms.values():
            bm.set_pass(name, img)
        st.bake(objs, kind, 8, img)
    p_alb = st.save_image(albedo, "connectors_albedo.jpg", "JPEG", 92)
    p_mr = st.save_image(mr, "connectors_mr.png", "PNG")
    p_nrm = st.save_image(normal, "connectors_normal.png", "PNG")
    for k in st.EMISSIVE:
        st.remove_dummy_target(MATS[k])

    hull = st.pbr_material("connector_hull", st.load_saved(p_alb, False),
                           st.load_saved(p_mr, True), st.load_saved(p_nrm, True))
    mapping = {m: hull for m in atlas_mats}
    for o, off in zip(objs, offsets):
        st.remap_materials(o, mapping)
        o.data.uv_layers.remove(o.data.uv_layers["panel"])
        o.data.transform(Matrix.Translation(-Vector(off)))
    for img in (dummy, masks, albedo, mr, normal):
        bpy.data.images.remove(img)
    for m in atlas_mats:
        if m.users == 0:
            bpy.data.materials.remove(m)


# ---------------------------------------------------------------- previews
def instance(obj, loc, rz=0.0):
    o = bpy.data.objects.new(obj.name + "_inst", obj.data)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = (0, 0, rz)
    return o


def previews(seg, col, jun):
    for o in (seg, col, jun):
        o.hide_render = True
    # collar A (flange to -Y at y=0), 4 segments, collar B turned around
    instance(col, (0, 0, 0))
    for k in range(4):
        instance(seg, (0, COLLAR_LEN + k * SEG_LEN, 0))
    end = COLLAR_LEN + 4 * SEG_LEN
    instance(col, (0, end + COLLAR_LEN, 0), math.pi)
    # junction beside, with one segment on its -X port and one on its +Y port
    jc = Vector((34.0, 40.0, 0))
    instance(jun, jc)
    instance(seg, jc + Vector((-PORT, 0, 0)), math.pi / 2)       # runs toward -X
    instance(seg, jc + Vector((0, PORT, 0)))                     # runs toward +Y
    # stand-in building walls the collars dock to
    for y, s in ((-0.6, 1), (end + COLLAR_LEN + 0.6, -1)):
        me = bpy.data.meshes.new("wall")
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((0, y - s * 4, 0))
                              @ Matrix.Diagonal((16, 8, 10, 1)))
        bm.to_mesh(me)
        bm.free()
        me.materials.append(common.make_material("prev_wall", (0.25, 0.26, 0.28), 0.6, 0.2))
        w = bpy.data.objects.new("wall", me)
        bpy.context.scene.collection.objects.link(w)
    target = (14.0, 45.0, 0.0)
    common.setup_preview(cam_loc=(target[0] - 95, target[1] - 70, 95), cam_target=target,
                         ortho_scale=120, res=(1600, 1200), key_dir=(-0.6, -0.35, 0.7),
                         key_energy=3.5)
    common.render(os.path.join(common.PREVIEW_DIR, "connectors_preview.png"))
    scene = bpy.context.scene
    cam = scene.camera
    cam.location = (target[0], target[1], 120)
    cam.rotation_euler = (0, 0, 0)
    cam.data.ortho_scale = 115
    scene.render.resolution_x, scene.render.resolution_y = 1200, 1200
    common.render(os.path.join(common.PREVIEW_DIR, "connectors_top.png"))
    # close-ups (inspection only): the junction, and a collar at its building wall
    cam.data.type = "PERSP"
    cam.data.lens = 35
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1000
    for name, loc, tgt in (("connectors_closeup", jc + Vector((-16, -20, 15)), jc + Vector((-5, 2, 0))),
                           ("connectors_collar_closeup", Vector((-15, 15, 9)), Vector((0, 2.5, 0)))):
        cam.location = loc
        cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
        common.render(os.path.join(common.PREVIEW_DIR, name + ".png"))


def make_root(name, **props):
    root = bpy.data.objects.new(name, None)
    root.empty_display_type = "PLAIN_AXES"
    bpy.context.scene.collection.objects.link(root)
    for k, v in props.items():
        root[k] = v
    return root


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    build_materials()
    r_seg = make_root("corridor_segment", segment_length=SEG_LEN)
    r_col = make_root("corridor_collar", collar_length=COLLAR_LEN)
    r_jun = make_root("corridor_junction", port_offset=PORT)
    seg, col, jun = build_segment(r_seg), build_collar(r_col), build_junction(r_jun)
    objs = [seg, col, jun]
    if "--no-textures" not in argv:
        texture_kit(objs, [(0, 0, 0), (30, 0, 0), (-30, 0, 0)])
    for o in objs:
        tris = sum(len(pl.vertices) - 2 for pl in o.data.polygons)
        bb = [Vector(c) for c in o.bound_box]
        lo = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
        hi = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
        print(f"STAT {o.name} tris={tris} mats={[m.name for m in o.data.materials]} "
              f"bbox={tuple(round(c, 3) for c in lo)}..{tuple(round(c, 3) for c in hi)}")
    parts.save_blend(BLEND)
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_mainfile(filepath=BLEND)
    for root, name in ((r_seg, "corridor_segment"), (r_col, "corridor_collar"),
                       (r_jun, "corridor_junction")):
        common.export_glb(root, os.path.join(OUT_DIR, name + ".glb"), extras=True,
                          export_image_format="JPEG", export_image_quality=90)
    if "--no-preview" not in argv:
        previews(seg, col, jun)


main()
