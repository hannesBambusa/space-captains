"""Shared mesh-building kit for the faction generators (merc + scavenger).

Same Part API as the Part class copied into gen_mining_outpost.py / gen_miner_ship.py,
but the material table is passed in, `box` takes an optional full rotation matrix,
`hazard` takes its two stripe colours, and `loft` builds tapered hulls from rings.
The older generators keep their own copy on purpose (they are not touched).
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

V = Vector
ALONG_Y = Matrix.Rotation(-math.pi / 2, 4, "X")   # cylinder axis Z -> +Y
ALONG_X = Matrix.Rotation(math.pi / 2, 4, "Y")    # cylinder axis Z -> +X
# Side-profile frame: local X = world Y (length), local Y = world Z (height),
# extrusion local Z = world X (width).
SIDE = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
# Front frame: local X = world X, local Y = world Z, extrusion along world -Y.
FRONT = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def rot(rx=0.0, ry=0.0, rz=0.0):
    """Euler XYZ rotation (radians) as a 4x4 matrix."""
    return (Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(ry, 4, "Y")
            @ Matrix.Rotation(rx, 4, "X"))


class Part:
    """One output mesh object, built in a single bmesh with named material slots."""

    def __init__(self, name, mats):
        self.name = name
        self.mats = mats
        self.bm = bmesh.new()
        self.slots = []

    def mi(self, key):
        mat = self.mats[key]
        if mat not in self.slots:
            self.slots.append(mat)
        return self.slots.index(mat)

    def _faces(self, verts):
        return list({f for v in verts for f in v.link_faces})

    def box(self, center, size, mat, rot_z=0.0, bevel=0.12, r=None):
        m = Matrix.Translation(center) @ (r if r is not None else Matrix.Rotation(rot_z, 4, "Z"))
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
        rm = Matrix((x, y, z)).transposed().to_4x4()
        m = Matrix.Translation((p0 + p1) / 2) @ rm @ Matrix.Diagonal((d.length, w, h, 1.0))
        verts = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)["verts"]
        idx = self.mi(mat)
        for f in self._faces(verts):
            f.material_index = idx

    def cyl(self, center, r1, r2, depth, mat, segs=12, axis_rot=None):
        m = Matrix.Translation(center)
        if axis_rot is not None:
            m = m @ axis_rot
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segs,
                                    radius1=r1, radius2=r2, depth=depth, matrix=m)
        idx = self.mi(mat)
        for f in self._faces(res["verts"]):
            f.material_index = idx

    def tube(self, p0, p1, r1, r2, mat, segs=10):
        """Cylinder/cone from p0 (radius r1) to p1 (radius r2)."""
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        q = d.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
        self.cyl((p0 + p1) / 2, r1, r2, d.length, mat, segs=segs, axis_rot=q)

    def slab(self, pts, z0, z1, mat, matrix=None):
        """Extrude a convex polygon (local XY) from z0 to z1."""
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

    def loft(self, rings, mat, cap=True, mat_fn=None):
        """Skin a list of equal-length 3D point rings. mat_fn(ring_i, edge_j) -> key."""
        vr = [[self.bm.verts.new(Vector(p)) for p in ring] for ring in rings]
        n = len(rings[0])
        faces = []
        for i in range(len(vr) - 1):
            for j in range(n):
                k = (j + 1) % n
                f = self.bm.faces.new((vr[i][j], vr[i][k], vr[i + 1][k], vr[i + 1][j]))
                f.material_index = self.mi(mat_fn(i, j) if mat_fn else mat)
                faces.append(f)
        if cap:
            for ring in (vr[0], vr[-1]):
                f = self.bm.faces.new(ring)
                f.material_index = self.mi(mat)

    def hazard(self, x0, x1, w, z0, z1, matrix=None, pitch=1.2, cols=("yellow", "dark")):
        """Diagonal two-colour stripe band along local X (x0..x1), width w across Y."""
        n = max(2, int(round((x1 - x0) / pitch)))
        s = (x1 - x0) / n
        skew = w * 0.7
        for i in range(-1, n + 1):
            a, b = x0 + i * s, x0 + (i + 1) * s
            q = [(a, -w / 2), (b, -w / 2), (b + skew, w / 2), (a + skew, w / 2)]
            q = [(min(max(x, x0), x1), y) for x, y in q]
            if abs(q[1][0] - q[0][0]) < 1e-3 and abs(q[2][0] - q[3][0]) < 1e-3:
                continue
            pts = []
            for pt in q:
                if not pts or (Vector(pt) - Vector(pts[-1])).length > 1e-3:
                    pts.append(pt)
            if len(pts) > 2 and (Vector(pts[0]) - Vector(pts[-1])).length < 1e-3:
                pts.pop()
            if len(pts) < 3:
                continue
            self.slab(pts, z0, z1, cols[i % 2], matrix)

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

    # --- Added for the player ships (merc / miner / salvager). Existing methods untouched.

    def sphere(self, center, radius, mat, segs=16, rings=8, scale=(1.0, 1.0, 1.0)):
        """UV sphere, optionally squashed by `scale` (x, y, z)."""
        m = Matrix.Translation(center) @ Matrix.Diagonal((*scale, 1.0))
        verts = bmesh.ops.create_uvsphere(self.bm, u_segments=segs, v_segments=rings,
                                          radius=radius, matrix=m)["verts"]
        idx = self.mi(mat)
        for f in self._faces(verts):
            f.material_index = idx

    def torus(self, center, major, minor, mat, segs=24, minor_segs=8, matrix=None):
        """Closed torus around local Z (use matrix to orient), centred at `center`."""
        m = Matrix.Translation(center) @ (matrix or Matrix())
        rings = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            ca, sa = math.cos(a), math.sin(a)
            ring = []
            for j in range(minor_segs):
                b = 2 * math.pi * j / minor_segs
                r = major + minor * math.cos(b)
                ring.append(self.bm.verts.new(m @ Vector((r * ca, r * sa, minor * math.sin(b)))))
            rings.append(ring)
        idx = self.mi(mat)
        for i in range(segs):
            a, b = rings[i], rings[(i + 1) % segs]
            for j in range(minor_segs):
                k = (j + 1) % minor_segs
                f = self.bm.faces.new((a[j], b[j], b[k], a[k]))
                f.material_index = idx

    def ring_segment(self, center, r0, r1, a0, a1, z0, z1, mat, steps=2):
        """Flat annular sector (local XY, angles in radians) extruded z0..z1 as convex
        quads, so it builds with slab(). Used for segmented armour collars."""
        idx_steps = max(1, steps)
        for s in range(idx_steps):
            b0 = a0 + (a1 - a0) * s / idx_steps
            b1 = a0 + (a1 - a0) * (s + 1) / idx_steps
            pts = [(r0 * math.cos(b0), r0 * math.sin(b0)), (r1 * math.cos(b0), r1 * math.sin(b0)),
                   (r1 * math.cos(b1), r1 * math.sin(b1)), (r0 * math.cos(b1), r0 * math.sin(b1))]
            self.slab(pts, z0, z1, mat, matrix=Matrix.Translation(center))

    def rock(self, center, r, mat, rng):
        """Lumpy low-poly rock (ore / scrap filler)."""
        m = Matrix.Translation(center) @ Matrix.Rotation(rng.uniform(0, 6.3), 4, "Z")
        m = m @ Matrix.Diagonal((r * rng.uniform(0.8, 1.3), r * rng.uniform(0.8, 1.2),
                                 r * rng.uniform(0.6, 0.9), 1.0))
        verts = bmesh.ops.create_icosphere(self.bm, subdivisions=1, radius=1.0, matrix=m)["verts"]
        for v in verts:
            v.co += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * r * 0.15
        idx = self.mi(mat)
        for f in self._faces(verts):
            f.material_index = idx

    def finish(self, parent, sharp_deg=32):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        for f in bm.faces:
            f.smooth = True
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        for s in self.slots:
            mesh.materials.append(s)
        mesh.set_sharp_from_angle(angle=math.radians(sharp_deg))
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj.parent = parent
        return obj


def make_root(name, size=4):
    root = bpy.data.objects.new(name, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = size
    bpy.context.scene.collection.objects.link(root)
    return root


def add_empty(name, parent, pos, rot_z=0.0, size=1.0):
    """Arrow empty. rot_z=0 -> its Godot -Z points along Blender +Y (ship forward);
    rot_z=pi -> Godot -Z points along Blender -Y (Godot +Z)."""
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = "SINGLE_ARROW"
    e.empty_display_size = size
    e.location = pos
    e.rotation_euler = (0, 0, rot_z)
    bpy.context.scene.collection.objects.link(e)
    e.parent = parent
    return e


def print_stats(objs):
    total = 0
    for o in objs:
        tris = sum(len(pl.vertices) - 2 for pl in o.data.polygons)
        total += tris
        print(f"STAT {o.name} tris={tris} mats={[m.name for m in o.data.materials]}")
    print(f"STAT total tris={total}")
    return total


def save_blend(path):
    bpy.context.preferences.filepaths.save_version = 0  # no .blend1 on re-run
    bpy.ops.wm.save_as_mainfile(filepath=path)


def script_args(argv):
    return argv[argv.index("--") + 1:] if "--" in argv else []


# --- Extra shape helpers (part_hull etc). Existing methods untouched.

def part_hull(part, points, mat):
    """Convex hull of `points` added to Part `part` (faceted crystals, blunt shards)."""
    bm = part.bm
    verts = [bm.verts.new(Vector(p)) for p in points]
    res = bmesh.ops.convex_hull(bm, input=verts)
    junk = list({v for v in res["geom_interior"] + res["geom_unused"]
                 if isinstance(v, bmesh.types.BMVert)})
    if junk:
        bmesh.ops.delete(bm, geom=junk, context="VERTS")
    idx = part.mi(mat)
    for f in res["geom"]:
        if isinstance(f, bmesh.types.BMFace):
            f.material_index = idx


# --- Added for the functional hard sci-fi fleet (gen_*_ship.py, gen_escape_pod.py).
# Existing methods untouched. All helpers take a Part and material keys.

def oct_ring(y, w, h, c, x0=0.0, z0=0.0):
    """Chamfered rectangle (w across X, h across Z, corner chamfer c) as 8 points at y."""
    hw, hh = w / 2, h / 2
    pts = [(hw, -hh + c), (hw, hh - c), (hw - c, hh), (-hw + c, hh),
           (-hw, hh - c), (-hw, -hh + c), (-hw + c, -hh), (hw - c, -hh)]
    return [Vector((x0 + x, y, z0 + z)) for x, z in pts]


def prism(part, y0, y1, d0, d1, mat, mat_fn=None, x0=0.0, z0=0.0):
    """Chamfered-box hull section along Y. d0/d1 = (w, h, chamfer) at y0 / y1."""
    part.loft([oct_ring(y0, *d0, x0=x0, z0=z0), oct_ring(y1, *d1, x0=x0, z0=z0)], mat,
              mat_fn=mat_fn)


def capsule(part, y0, y1, r, mat_fn, segs=16, x=0.0, z=0.0, dome0=0.5, dome1=0.5, steps=3):
    """Pressure-hull cylinder along Y from y0 (rear) to y1 (front) with elliptic end domes
    (dome depth = dome0/dome1 * r). mat_fn(seg_i, edge_j) -> material key."""
    prof = []
    for k in range(steps + 1):  # front dome, tip -> shoulder
        a = math.pi / 2 * (1 - k / steps)
        prof.append((r * math.cos(a), y1 - dome1 * r * (1 - math.sin(a))))
    for k in range(steps + 1):  # rear dome, shoulder -> tip
        a = math.pi / 2 * k / steps
        prof.append((r * math.cos(a), y0 + dome0 * r * (1 - math.cos(math.pi / 2 - a))))
    # local z of the lathe = world y (ALONG_Y), so the profile z values are world y
    part.lathe(prof, segs, mat_fn, matrix=Matrix.Translation((x, 0, z)) @ ALONG_Y)
    return prof


def bell(part, exit_y, r_exit, length, mat_out, mat_in, x=0.0, z=0.0, segs=16, throat=0.42):
    """Rocket engine bell, throat forward (+Y) at exit_y + length, open exit at exit_y."""
    rt = r_exit * throat
    n = 5
    prof = [(0.0, exit_y + length), (rt, exit_y + length)]
    for k in range(1, n + 1):
        t = k / n
        prof.append((rt + (r_exit - rt) * t ** 0.65, exit_y + length * (1 - t)))
    lip = r_exit * 0.08
    prof.append((r_exit - lip, exit_y))
    for k in range(n - 1, 1, -1):
        t = k / n
        prof.append((rt * 0.85 + (r_exit - lip - rt * 0.85) * t ** 0.65,
                     exit_y + length * (1 - t)))
    prof.append((0.0, exit_y + length * 0.55))
    n_out = n + 1

    def mf(i, j):
        return mat_out if j < n_out else mat_in
    part.lathe(prof, segs, mf, matrix=Matrix.Translation((x, 0, z)) @ ALONG_Y)


def exhaust_glow(part, r, length, mat, x=0.0, z=0.0, segs=16):
    """Short rounded exhaust glow, built with its exit plane at y = 0, plume toward -Y.
    Object origin should sit on the bell exit plane so Godot can scale it on Z."""
    prof = [(0.0, 0.04), (r * 0.95, 0.04), (r * 0.72, -length * 0.3), (r * 0.46, -length * 0.7),
            (r * 0.2, -length * 0.94), (0.0, -length)]
    part.lathe(prof, segs, lambda i, j: mat, matrix=Matrix.Translation((x, 0, z)) @ ALONG_Y)


def rcs_quad(part, center, out, mat_block, mat_noz, s=0.28, fwd=Vector((0, 1, 0))):
    """RCS thruster quad: small block on the hull, four nozzles tangent to it."""
    out = Vector(out).normalized()
    f = Vector(fwd)
    if abs(out.dot(f)) > 0.9:
        f = Vector((0, 0, 1))
    t = out.cross(f).normalized()
    f = t.cross(out).normalized()
    c = Vector(center)
    r_blk = Matrix((t, f, out)).transposed().to_4x4()
    part.box(c, (s, s, s * 0.8), mat_block, r=r_blk, bevel=0.1)
    for d in (t, -t, f, -f):
        part.tube(c + d * s * 0.45, c + d * s * 0.95, s * 0.12, s * 0.22, mat_noz, segs=6)


def box_truss(part, y0, y1, hw, hh, n, chord_mat, brace_mat, chord=0.22, brace=0.12, z0=0.0,
              x0=0.0, sides=(True, True, True, True)):
    """Open box truss along Y: 4 longerons, n bays of frames, alternating diagonals on the
    sides (+-X) and top/bottom faces (sides = (px, nx, top, bottom))."""
    corners = [(sx * hw, sz * hh) for sx in (-1, 1) for sz in (-1, 1)]
    for x, z in corners:
        part.beam(Vector((x0 + x, y0, z0 + z)), Vector((x0 + x, y1, z0 + z)), chord, chord,
                  chord_mat)
    ys = [y0 + (y1 - y0) * i / n for i in range(n + 1)]
    for i, y in enumerate(ys):
        for sz in (-1, 1):
            part.beam(Vector((x0 - hw, y, z0 + sz * hh)), Vector((x0 + hw, y, z0 + sz * hh)),
                      brace * 1.2, brace * 1.2, chord_mat)
        for sx in (-1, 1):
            part.beam(Vector((x0 + sx * hw, y, z0 - hh)), Vector((x0 + sx * hw, y, z0 + hh)),
                      brace * 1.2, brace * 1.2, chord_mat, up=Vector((1, 0, 0)))
        if i == n:
            continue
        ya, yb = (y, ys[i + 1]) if i % 2 == 0 else (ys[i + 1], y)
        for sx, on in ((1, sides[0]), (-1, sides[1])):
            if on:
                part.beam(Vector((x0 + sx * hw, ya, z0 - hh)), Vector((x0 + sx * hw, yb, z0 + hh)),
                          brace, brace, brace_mat, up=Vector((1, 0, 0)))
        for sz, on in ((1, sides[2]), (-1, sides[3])):
            if on:
                part.beam(Vector((x0 - hw, ya, z0 + sz * hh)), Vector((x0 + hw, yb, z0 + sz * hh)),
                          brace, brace, brace_mat)


def dish(part, center, r, normal, mat, mat_feed, depth=0.3, segs=12):
    """Parabolic comms dish facing `normal`, with a feed horn on three struts."""
    q = Vector(normal).normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    m = Matrix.Translation(center) @ q
    prof = [(0.0, 0.0), (r * 0.5, depth * 0.25), (r, depth), (r * 0.92, depth + 0.03),
            (0.0, 0.06)]
    part.lathe(prof, segs, lambda i, j: mat, matrix=m)
    tip = m @ Vector((0, 0, depth + r * 0.6))
    for k in range(3):
        a = k * 2 * math.pi / 3
        part.beam(m @ Vector((r * 0.85 * math.cos(a), r * 0.85 * math.sin(a), depth)), tip,
                  0.03, 0.03, mat_feed)
    part.box(tip, (0.12, 0.12, 0.12), mat_feed, bevel=0.0)


def radiator(part, center, length, height, normal, mat_panel, mat_rib, ribs=6, t=0.06):
    """Thin flat radiator panel lying flush on a hull face: `length` along Y, `height` along
    the face, `normal` the face normal (X or Z axis). Coolant ribs run across it."""
    nrm = Vector(normal).normalized()
    c = Vector(center)
    if abs(nrm.x) > 0.5:
        size = (t, length, height)
        rib = (t * 1.6, 0.06, height * 0.96)
    else:
        size = (height, length, t)
        rib = (height * 0.96, 0.06, t * 1.6)
    part.box(c, size, mat_panel, bevel=0.0)
    for k in range(ribs):
        y = -length / 2 + length * (k + 0.5) / ribs
        part.box(c + Vector((0, y, 0)) + nrm * t * 0.4, rib, mat_rib, bevel=0.0)


def ship_previews(name, span, target=(0.0, 0.0, 0.0)):
    """3/4 view <name>_preview.png and top-down <name>_top.png for a ship of ~span metres."""
    import common  # local: common imports bpy, parts stays importable on its own
    tx, ty, tz = target
    d = span * 1.15
    common.setup_preview(cam_loc=(tx - d * 0.85, ty + d * 0.6, tz + d * 1.0), cam_target=target,
                         ortho_scale=span * 1.35, res=(1600, 1200), key_dir=(-0.5, 0.4, 0.75),
                         key_energy=3.5)
    common.render(f"{common.PREVIEW_DIR}/{name}_preview.png")
    scene = bpy.context.scene
    cam = scene.camera
    cam.location = (tx, ty, 60)
    cam.rotation_euler = (0, 0, 0)
    cam.data.ortho_scale = span * 1.35
    scene.render.resolution_x, scene.render.resolution_y = 1200, 1200
    common.render(f"{common.PREVIEW_DIR}/{name}_top.png")


# --- Added for the factory (gen_factory.py). Existing methods untouched.

class PanelPart(Part):
    """Part that also writes the "panel" UV layer (metres in each primitive's own frame)
    that station_textures bakes plates, seams and rivets from. box/beam/cyl/tube use
    their own frame, lathe unrolls like gen_station.Part. Anything else (slab, loft,
    sphere, torus, rock, part_hull) gets a per-face world box projection in finish().
    Box bevel offset is capped at `bevel_max` metres so big blocks keep crisp edges."""

    bevel_max = 0.35

    def __init__(self, name, mats):
        super().__init__(name, mats)
        self.uv = self.bm.loops.layers.uv.new("panel")
        self.n_prims = 0

    def _offset(self):
        self.n_prims += 1
        k = self.n_prims
        return Vector(((k * 7) % 31 * 64.0, (k * 13) % 29 * 64.0))

    def _planar_uv(self, faces, inv, shift):
        off = self._offset()
        r3 = inv.to_3x3()
        for f in faces:
            f.normal_update()
            n = r3 @ f.normal
            k = max(range(3), key=lambda i: abs(n[i]))
            a, b = ((1, 2), (0, 2), (0, 1))[k]
            for lp in f.loops:
                q = inv @ lp.vert.co + shift
                lp[self.uv].uv = (q[a] + off.x, q[b] + off.y)

    def box(self, center, size, mat, rot_z=0.0, bevel=0.12, r=None):
        fr = Matrix.Translation(center) @ (r if r is not None else Matrix.Rotation(rot_z, 4, "Z"))
        m = fr @ Matrix.Diagonal((*size, 1.0))
        verts = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)["verts"]
        idx = self.mi(mat)
        faces = self._faces(verts)
        for f in faces:
            f.material_index = idx
        if bevel > 0:
            edges = list({e for v in verts for e in v.link_edges})
            res = bmesh.ops.bevel(self.bm, geom=verts + edges,
                                  offset=min(min(size) * bevel, self.bevel_max), segments=1,
                                  affect="EDGES", profile=0.5, clamp_overlap=True)
            for f in res["faces"]:
                f.material_index = idx
            faces = list({g for f in res["faces"] for v in f.verts for g in v.link_faces})
        self._planar_uv(faces, fr.inverted(), Vector(size) / 2)

    def beam(self, p0, p1, w, h, mat, up=Vector((0, 0, 1))):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        x = d.normalized()
        if abs(x.dot(up)) > 0.99:
            up = Vector((1, 0, 0))
        z = (up - x * up.dot(x)).normalized()
        y = z.cross(x)
        rm = Matrix((x, y, z)).transposed().to_4x4()
        self.box((p0 + p1) / 2, (d.length, w, h), mat, r=rm, bevel=0.0)

    def cyl(self, center, r1, r2, depth, mat, segs=12, axis_rot=None):
        m = Matrix.Translation(center)
        if axis_rot is not None:
            m = m @ axis_rot
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segs,
                                    radius1=r1, radius2=r2, depth=depth, matrix=m)
        idx = self.mi(mat)
        faces = self._faces(res["verts"])
        for f in faces:
            f.material_index = idx
        inv = m.inverted()
        r3 = inv.to_3x3()
        off = self._offset()
        rm, ra = max(r1, r2), (r1 + r2) / 2
        for f in faces:
            f.normal_update()
            pts = [inv @ lp.vert.co for lp in f.loops]
            if abs((r3 @ f.normal).z) > 0.7:
                uvs = [(q.x + rm, q.y + rm) for q in pts]
            else:
                th = [math.atan2(q.y, q.x) for q in pts]
                if max(th) - min(th) > math.pi:
                    th = [t + 2 * math.pi if t < 0 else t for t in th]
                uvs = [(t * ra, q.z + depth / 2) for t, q in zip(th, pts)]
            for lp, uv in zip(f.loops, uvs):
                lp[self.uv].uv = (uv[0] + off.x, uv[1] + off.y)

    def lathe(self, profile, segs, mat_fn, matrix=None, start=0.0):
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

    def finish(self, parent, sharp_deg=32):
        # faces no helper projected (all UVs still 0, 0): world box projection
        off = Vector((17 * 64.0, 23 * 64.0))
        for f in self.bm.faces:
            if all(lp[self.uv].uv.length < 1e-6 for lp in f.loops):
                f.normal_update()
                n = f.normal
                k = max(range(3), key=lambda i: abs(n[i]))
                a, b = ((1, 2), (0, 2), (0, 1))[k]
                for lp in f.loops:
                    q = lp.vert.co
                    lp[self.uv].uv = (q[a] + off.x, q[b] + off.y)
        return super().finish(parent, sharp_deg)
