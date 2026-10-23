"""Generate the jump gate .glb and a 45 degree preview.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python /Users/hannesalm/code/games/space-majesty/blender/gen_jump_gate.py
  Add `-- --no-preview` to skip the PNG render.

Layout. Built in a "ring frame" (ring axis = local Z, like the station lathe), then every
mesh is rotated +90 deg about X so the ring stands vertical in Blender XZ with its axis
along Blender -Y, which the exporter turns into Godot +Z. Ships fly through along Z.
In the ring frame angle 90 deg is up (Godot +Y), 0 deg is Godot +X.
  hull r 90..104, depth +-9; 8 pylons (22.5 + 45k deg) reaching r 110 (220 m outer diam);
  emitter band inner face r EMITTER_R; control module on the +X side.
Hierarchy: jump_gate (empty root, origin at ring centre)
  -> gate_ring, gate_pylons, gate_structure, gate_emitter, portal_anchor (empty).
portal_anchor sits at the ring centre with identity rotation (its local Z is the ring axis)
and carries the custom property inner_radius (glTF extras -> Godot node metadata).
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

OUT = os.path.join(common.ROOT, "assets", "models", "gate", "jump_gate.glb")
EMITTER_R = 86.0          # inner face of the emitter band = portal radius
SEGS = 96                 # ring lathe segments (12 per pylon bay)
N_PYLONS = 8
PYLON_A0 = math.pi / 8    # pylons at 22.5 + 45k deg, so the top and +X side stay open
TO_VERTICAL = Matrix.Rotation(math.radians(90), 4, "X")

MATS = {}


def build_materials():
    m = common.make_material
    MATS["hull"] = m("gate_hull_white", (0.78, 0.78, 0.76), roughness=0.45, metallic=0.1)
    MATS["hull2"] = m("gate_hull_grey", (0.50, 0.52, 0.55), roughness=0.5, metallic=0.15)
    MATS["dark"] = m("gate_structure_dark", (0.06, 0.065, 0.07), roughness=0.55, metallic=0.5)
    MATS["orange"] = m("gate_accent_orange", (0.85, 0.28, 0.03), roughness=0.45, metallic=0.0)
    MATS["window"] = m("gate_window_warm", (1.0, 0.85, 0.6), roughness=0.3,
                       emission=(1.0, 0.78, 0.5), emission_strength=3.5)
    MATS["light"] = m("gate_light_orange", (1.0, 0.45, 0.1), roughness=0.3,
                      emission=(1.0, 0.42, 0.08), emission_strength=5.0)
    MATS["emitter"] = m("gate_emitter_cyan", (0.35, 0.8, 1.0), roughness=0.2,
                        emission=(0.25, 0.75, 1.0), emission_strength=5.0)


class Part:
    """One output mesh object, built in a single bmesh with named material slots.
    Same API as gen_station.Part, plus finish() rotates the ring frame to vertical."""

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
        d = p1 - p0
        x = d.normalized()
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

    def lathe(self, profile, segs, mat_fn, matrix=None):
        """Closed profile of (r, z) around Z. mat_fn(seg_i, edge_j) -> material key."""
        m = matrix or Matrix()
        rings = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
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
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-4)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bmesh.ops.transform(bm, matrix=TO_VERTICAL, verts=bm.verts[:])
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


def pylon_angles():
    return [PYLON_A0 + k * 2 * math.pi / N_PYLONS for k in range(N_PYLONS)]


def seg_of(a):
    return int(round((a % (2 * math.pi)) / (2 * math.pi) * SEGS)) % SEGS


# ---------------------------------------------------------------- ring hull
def build_ring(rng):
    p = Part("gate_ring")
    # Closed cross-section, counter-clockwise in (r, z). Edges listed for the material map.
    prof = [(88.0, -4.8), (90.0, -8.0), (92.0, -11.0), (95.5, -11.0), (96.7, -11.0),
            (102.0, -11.0), (104.0, -9.0), (104.0, -1.5), (104.0, 1.5), (104.0, 9.0),
            (102.0, 11.0), (96.7, 11.0), (95.5, 11.0), (92.0, 11.0), (90.0, 8.0),
            (88.0, 4.8), (88.0, -4.8)]
    base = {0: "dark", 1: "hull2", 2: "hull", 3: "orange", 4: "hull", 5: "hull2",
            6: "hull", 7: "window", 8: "hull", 9: "hull2", 10: "hull", 11: "orange",
            12: "hull", 13: "hull2", 14: "dark", 15: "dark"}
    pylon_segs = {seg_of(a) for a in pylon_angles()}
    bay = SEGS // N_PYLONS

    def ring_mat(i, j):
        k = base[j]
        local = (i - min(pylon_segs)) % bay   # 0 = pylon centre segment
        if local == bay // 2 and j not in (0, 14, 15):
            return "dark"                      # segment joint band mid-bay
        if k == "window" and local not in (3, 9):
            return "hull2"
        if k == "hull" and (local in (3, 4, 8, 9)):
            return "hull2"
        return k
    p.lathe(prof, SEGS, ring_mat)
    return p


# ---------------------------------------------------------------- pylons / clamps
def build_pylons(rng):
    p = Part("gate_pylons")
    for a in pylon_angles():
        tan = Vector((-math.sin(a), math.cos(a), 0))
        # Outer clamp body wrapping the hull, sticking out to r 110
        p.box(polar(105.0, a), (10.0, 14.0, 30.0), "hull2", rot_z=a)
        p.box(polar(108.6, a), (3.4, 11.0, 22.0), "hull", rot_z=a)
        p.box(polar(110.4, a), (0.4, 8.0, 3.0), "dark", rot_z=a, bevel=0.0)
        for sz in (-1, 1):
            # Front and back jaws gripping the hull faces, reaching in past the inner lip
            p.box(polar(95.0, a, sz * 12.6), (22.0, 10.0, 3.2), "hull", rot_z=a)
            p.box(polar(96.0, a, sz * 14.25), (12.0, 2.4, 0.15), "orange", rot_z=a, bevel=0.0)
            p.box(polar(86.5, a, sz * 14.25), (3.0, 7.0, 0.2), "dark", rot_z=a, bevel=0.0)
            # Inner emitter prongs framing the cyan band
            p.box(polar(85.0, a, sz * 8.2), (8.0, 7.0, 6.0), "dark", rot_z=a)
            p.box(polar(81.8, a, sz * 6.0), (2.0, 5.0, 2.4), "hull2", rot_z=a)
            # Radiator fins on the outer clamp
            for t in (-1, 1):
                p.box(polar(103.5, a, sz * 15.4) + tan * t * 4.0, (7.0, 0.6, 2.0), "dark",
                      rot_z=a, bevel=0.0)
            # Beacon lights: tip pair and jaw corners
            p.box(polar(110.6, a, sz * 8.0), (0.8, 2.0, 2.0), "light", rot_z=a, bevel=0.0)
            p.box(polar(84.6, a, sz * 14.35) , (1.2, 1.2, 0.3), "light", rot_z=a, bevel=0.0)
    return p


def arc_beam(p, r, a0, a1, z, w, h, mat, n=4, ties=None):
    """Polyline of beams along an arc; optional tie boxes at the joints."""
    pts = [polar(r, a0 + (a1 - a0) * i / n, z) for i in range(n + 1)]
    for i in range(n):
        p.beam(pts[i], pts[i + 1], w, h, mat)
    if ties:
        size, tmat = ties
        for i in range(1, n):
            aa = a0 + (a1 - a0) * i / n
            p.box(pts[i], size, tmat, rot_z=aa, bevel=0.0)


# ---------------------------------------------------------------- struts, control module
def build_structure(rng):
    p = Part("gate_structure")
    angs = pylon_angles()
    step = 2 * math.pi / N_PYLONS
    for a in angs:
        b = a + step
        mid = a + step / 2
        for sz in (-1, 1):
            # Raised truss rails on both faces between pylon jaws, with tie blocks
            arc_beam(p, 100.8, a + 0.075, b - 0.075, sz * 11.8, 1.3, 1.6, "dark", n=6,
                     ties=((2.0, 3.6, 1.0), "dark"))
            arc_beam(p, 91.6, a + 0.06, b - 0.06, sz * 11.5, 0.8, 1.0, "dark", n=6)
            # Mid-bay brace collar with a light
            p.box(polar(97.0, mid, sz * 11.6), (12.0, 4.0, 1.6), "hull2", rot_z=mid)
            p.box(polar(97.0, mid, sz * 12.45), (1.4, 2.4, 0.12), "light", rot_z=mid, bevel=0.0)
        # Outer spine strut along the hull outer face between pylons
        arc_beam(p, 105.0, a + 0.07, b - 0.07, 0.0, 1.6, 3.4, "dark", n=6,
                 ties=((2.4, 1.0, 5.0), "hull2"))
    # Docking guide lights on the inner lip, both faces, alternating orange / warm
    for i in range(SEGS // 2):
        aa = 2 * math.pi * (i + 0.5) / (SEGS // 2)
        if any(abs(math.remainder(aa - pa, 2 * math.pi)) < 0.09 for pa in angs):
            continue
        for sz in (-1, 1):
            p.box(polar(89.0, aa, sz * 6.4), (0.7, 1.4, 0.5),
                  "light" if i % 2 == 0 else "window", rot_z=aa, bevel=0.0)

    # Control module on the +X side (ring angle 0), outside the hull
    a = 0.0
    p.box(polar(108.0, a), (10.0, 24.0, 20.0), "hull", rot_z=a)
    p.box(polar(113.4, a), (1.4, 18.0, 14.0), "hull2", rot_z=a)
    for sz in (-1, 1):
        p.box(polar(108.0, a, sz * 10.1), (9.0, 22.0, 0.6), "dark", rot_z=a)
        p.box(polar(108.0, a, sz * 10.45), (2.0, 20.0, 0.12), "orange", rot_z=a, bevel=0.0)
        p.box(polar(111.0, a, sz * 10.45), (1.2, 18.0, 0.12), "window", rot_z=a, bevel=0.0)
    for t in (-1, 1):
        p.box(polar(108.5, a) + Vector((0, t * 12.02, 0)), (5.0, 0.1, 14.0), "window", bevel=0.0)
        p.box(polar(108.0, a) + Vector((0, t * 12.3, 0)), (10.4, 0.6, 2.0), "orange", bevel=0.0)
    # Docking port pointing outward along +X, with ring lights
    rx = Matrix.Rotation(math.radians(90), 4, "Y")
    p.cyl(polar(115.2, a), 3.0, 3.0, 2.4, "dark", segs=12, axis_rot=rx)
    p.cyl(polar(116.8, a), 2.2, 2.2, 0.8, "orange", segs=12, axis_rot=rx)
    for i in range(6):
        ang = i * math.pi / 3
        p.box(polar(117.3, a) + Vector((0, math.cos(ang), math.sin(ang))) * 3.4,
              (0.5, 0.8, 0.8), "light", bevel=0.0)
    # Antenna masts on the module corners
    for t in (-1, 1):
        base = polar(110.0, a, 0.0) + Vector((0, t * 9.0, 0))
        p.beam(base, base + Vector((8.0, t * 3.0, 0)), 0.5, 0.5, "dark")
        p.box(base + Vector((8.2, t * 3.1, 0)), (1.0, 1.0, 1.0), "light", bevel=0.0)
    # Small dish on the front face of the module
    dm = Matrix.Translation(polar(107.0, a, 10.4) + Vector((0, 6.5, 0))) @ \
        Matrix.Rotation(math.radians(25), 4, "Y")
    dish_prof = [(0, 0.0), (2.0, 0.3), (3.6, 1.1), (3.8, 1.1), (1.6, -0.1), (0, -0.3)]
    p.lathe(dish_prof, 16, lambda i, j: "hull" if j < 2 else ("orange" if j == 2 else "dark"),
            matrix=dm)
    # Tanks either side of the module along the hull
    for t in (-1, 1):
        aa = t * 0.15
        p.cyl(polar(106.6, aa, 0.0), 2.6, 2.6, 14.0, "hull2", segs=10)
        p.cyl(polar(106.6, aa, 7.3), 2.6, 1.8, 0.6, "dark", segs=10)
        p.cyl(polar(106.6, aa, -7.3), 1.8, 2.6, 0.6, "dark", segs=10)
    # Top beacon mast at 12 o'clock, the tallest point in the silhouette
    top = math.pi / 2
    p.box(polar(105.5, top), (5.0, 7.0, 10.0), "hull2", rot_z=top)
    p.box(polar(105.5, top, 5.1), (3.0, 5.0, 0.15), "orange", rot_z=top, bevel=0.0)
    p.beam(polar(107.5, top), polar(113.5, top), 0.6, 0.6, "dark")
    p.box(polar(113.8, top), (1.6, 1.6, 1.6), "light", rot_z=top, bevel=0.0)
    return p

# ---------------------------------------------------------------- emitter
def build_emitter(rng):
    p = Part("gate_emitter")
    r0 = EMITTER_R
    prof = [(r0 + 2.2, -3.2), (r0 + 0.4, -3.0), (r0, -2.2), (r0, 2.2), (r0 + 0.4, 3.0),
            (r0 + 2.2, 3.2), (r0 + 2.2, -3.2)]
    p.lathe(prof, SEGS, lambda i, j: "emitter")
    # Emitter nodes on the pylon prongs (pulse with the band)
    for a in pylon_angles():
        p.box(polar(80.6, a), (0.6, 3.6, 10.0), "emitter", rot_z=a, bevel=0.0)
    return p


def build_gate():
    rng = random.Random(7331)
    build_materials()
    root = bpy.data.objects.new("jump_gate", None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 20
    bpy.context.scene.collection.objects.link(root)
    objs = [b(rng).finish(root) for b in (build_ring, build_pylons, build_structure, build_emitter)]
    anchor = bpy.data.objects.new("portal_anchor", None)
    anchor.empty_display_type = "SPHERE"
    anchor.empty_display_size = EMITTER_R
    anchor["inner_radius"] = EMITTER_R
    bpy.context.scene.collection.objects.link(anchor)
    anchor.parent = root
    return root, objs


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    common.reset_scene()
    root, objs = build_gate()
    total = 0
    for o in objs:
        tris = sum(len(pl.vertices) - 2 for pl in o.data.polygons)
        total += tris
        print(f"STAT {o.name} tris={tris} mats={[m.name for m in o.data.materials]}")
    print(f"STAT total tris={total} inner_radius={EMITTER_R}")
    bpy.context.preferences.filepaths.save_version = 0  # no .blend1 on re-run
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(common.ROOT, "blender", "jump_gate.blend"))
    common.export_glb(root, OUT, extras=True)
    if "--no-preview" not in argv:
        common.setup_preview(cam_loc=(170, -300, 345), cam_target=(0, 0, 0), ortho_scale=270,
                             res=(1600, 1200), key_dir=(0.55, -0.6, 0.65), key_energy=3.5)
        common.render(os.path.join(common.PREVIEW_DIR, "jump_gate_preview.png"))


main()
