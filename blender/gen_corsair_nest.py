"""Generate the corsair nest "Cleft roost" .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_corsair_nest.py
  Options after `--`: --no-preview, --no-textures, --no-ao (skip the rock AO bake), --extra[=DIR] (close-ups and an RTS
  camera view with a 15 m ship for scale, written to DIR, default the system temp dir).
Textures: one 2048 worn-industrial atlas (worn_kit / station_textures) over den_hull,
den_salvage and den_pdc_1..4, saved as blender/textures/corsair_nest_*. The rock is not
atlased: two vertex-coloured materials (outer rock in the asteroid cluster tint, laser cut
faces with striations and launch soot); Cycles AO of the rock plus all hardware is baked into
that vertex colour, so crevices, slot walls and the ground under the kit darken. The faction magenta is baked in, never tinted.

Design: the corsairs took a ~80 m cluster rock, cut it lengthwise with a mining laser and
jacked the two halves apart (the east half sits 2.5 m lower). The nest is the straight
18 m canyon between the halves, so from outside it is just another rock in the belt, with
three tethered boulders around it. Down the canyon floor runs a stolen military twin
linear catapult, one rail per raider, because corsairs hunt in pairs. The rails run out
of the bow on a 19 m boom through a square launch collar. An overhead catcher crane
plucks a returning raider out of the lane over painted catch rings, a rearm bridge
hoists an ammo cassette and drops reaction-mass hoses onto the ready pair clamped on
their sleds. At the stern a portal gantry cross-docks stolen ISO pods (owners' stencils,
one code blacked out, one pod re-sprayed magenta) and cranes them out over a fence's
docking collar. Two tension ties and two hydraulic spreader jacks hold the halves at
their spacing. The base runs dark: a stolen pearl-white yacht hab sunk in a trench on the
west summit (ARIADNE scratched out, SHRIKE sprayed on), a few warm ports in the cliff
walls, the fusion bunker in an east pit under black quilted thermal blankets, radiators
standing in a trench below the rim, passive sensors only (IR/optical ball, comm laser).
Four stolen naval rotary PDCs on steel plinths cover the bow and stern quarters.

Layout (Blender Z up, exported +Y up; Blender -Y = Godot +Z, the launch direction).
  rock      almond ~77 x 81 m, z -17..14.4, slot half-gap 9.0 (10.5 at the flared bow)
  deck      slot floor, top z -2.5, y -36..40; keel girders run on to y -55 (boom)
  rails     x +-4.2, y -55..26, cap top z -0.9; ready pair on sleds at y 12
  cranes    catcher bridge y -16, rearm bridge y 12, runways z 5.3..6.7 on both walls
  ties      y -2 and 22 at z 9; spreader jacks at y -26 (z 3.5 and -7.5)
  hab       x -25, y -10..16, z 10.7 (west summit trench); tanks x -17 / -23, y 23.5
  bunker    x 15..29, y -9..3 (east pit); radiators x 16..26, y 11..23 (east trench)
  stern     gantry y 34, runway beam to y 49, fence dock collar y 45.4
  mouth     launch collar y -52.5, opening x +-7.4, z -4..4
  PDCs      (-18,-25) (18,-24) (-19,31.5) (19,30), muzzles about 14 m above the deck
  overall   about 108 x 104 x 33 m
Hierarchy: corsair_nest (empty root) -> den_rock (both halves and 3 boulders), den_hull
  (all fixed hardware, burns and stays as the ruin), den_salvage (loose kit hidden on
  destruction: raiders, hanging claw kit, ammo cassette and hoses, pods, thermal tent,
  sensor mast, boulder tethers), den_pdc_1..4 (turrets, static in their world pose),
  den_hangar_glow (rail charge strips, collar rim, arrestor emitters; material
  den_hangar_glow, pulsed by Godot), den_lights (62 small blobs only, flickered by
  Godot), spawn_point and den_gun_1..4 (empties).
Hooks: spawn_point at (0, -50, 0.5) between the rails inside the collar, rot_z = pi so
  its Godot -Z points out of the mouth. den_gun_N sits at the muzzle tip of PDC N,
  rotated so its Godot -Z runs down the 12 degree elevated barrels.
"""
import math
import os
import random
import sys
import tempfile

import bmesh
import bpy
from mathutils import Matrix, Vector, noise
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
import station_textures as st  # noqa: E402
import worn_kit as wk  # noqa: E402
from parts import ALONG_X, ALONG_Y  # noqa: E402

V = Vector
PRE = "corsair_nest"
OUT = os.path.join(common.ROOT, "assets", "models", "buildings", "corsair_nest.glb")
BLEND = os.path.join(common.ROOT, "blender", "corsair_nest.blend")
SEED = 5307
RNG = random.Random(SEED)

DECK_TOP = -2.5
RAIL_X = 4.2
RAIDER_Z = 0.6
SLED_Y = 12.0
CATCH_Y = -16.0
REARM_Y = 12.0
TIES_Y = (-2.0, 22.0)
TIE_Z = 9.0
JACK_Y = -26.0
COLLAR_Y = -52.5
SPAWN_POS = (0.0, -50.0, 0.5)
PDC_S = 1.2
PDC_EL = math.radians(12)
# (x, y, site z, aim azimuth deg)
PDCS = [(-18.0, -25.0, 8.5, 235.0), (18.0, -24.0, 6.0, -55.0), (-19.0, 31.5, 7.0, 125.0),
        (19.0, 30.0, 5.0, 55.0)]
PDC_TIP = V((0.0, 9.062, 4.310))          # local muzzle tip, before PDC_S
BOULDERS = [((-47.0, -8.0, -6.0), (6.0, 5.0, 4.5)), ((45.0, 12.0, -7.0), (5.5, 5.0, 4.0)),
            ((27.0, -46.0, -7.0), (5.0, 4.5, 4.0))]
CRATERS = [((0.8, -0.3, 0.5), 0.22, 0.06), ((-0.7, 0.2, 0.6), 0.26, 0.07),
           ((0.9, 0.35, -0.1), 0.18, 0.05), ((-0.85, -0.45, 0.1), 0.2, 0.06),
           ((0.5, 0.7, 0.5), 0.24, 0.06), ((-0.4, 0.75, 0.45), 0.2, 0.05)]
# laser-cut flats (x0, x1, y0, y1, zmax)
CARVES = [(-30.0, -20.0, -13.0, 19.0, 7.5), (-27.0, -13.0, 20.0, 27.0, 6.0),
          (14.0, 30.0, -10.0, 4.0, 4.0), (14.0, 30.0, 9.0, 25.0, 1.5)]
CARVES += [(x - 4.2, x + 4.2, y - 4.2, y + 4.2, sz) for x, y, sz, _ in PDCS]

LABELS = ["#CHEV", "#BAR", "RAIL A", "RAIL B", "HOT RAIL", "KEEP CLEAR", "LAUNCH", "NO STEP",
          "DANGER", "REMASS", "SOLACE", "OSTRA 14", "ARIADNE", "SHRIKE", "CN-7", "PD 1",
          "PD 2", "PD 3", "PD 4"]
MAG_INK = (0.48, 0.05, 0.22)

MATS = {}
ROCK_MATS = {}
DECALS = []
SCORCH = [(-4.2, -50.0, -0.9, 5.0), (4.2, -50.0, -0.9, 5.0), (0.0, -34.0, -2.5, 6.0),
          (0.0, -16.0, -2.5, 4.0), (-4.2, 20.0, -1.0, 3.0), (4.2, 20.0, -1.0, 3.0),
          (0.0, 45.9, -0.3, 2.5)]
H = S = G = L = None
surf = None


def CLEFT(y):
    """Half-gap of the slot at y: 9.0 for y >= -20, flaring to 10.5 at the bow."""
    t = max(0.0, min(1.0, (-y - 20.0) / 20.0))
    return 9.0 + 1.5 * t


# ---------------------------------------------------------------- worn kinds
def _kind(base, **kw):
    d = dict(st.WORN_KINDS[base])
    d.update(kw)
    return d


MAG_TONES = [(0.50, 0.06, 0.23), (0.46, 0.05, 0.21), (0.54, 0.075, 0.26), (0.43, 0.055, 0.20),
             (0.52, 0.065, 0.24), (0.48, 0.06, 0.22)]
NEST_WORN = {
    # stolen military graphite: the main hardware
    "hull": _kind("hull", big=(3.0, 2.0), plate=(1.5, 1.0),
                  tones=[(0.13, 0.132, 0.145), (0.12, 0.122, 0.134), (0.14, 0.142, 0.155),
                         (0.115, 0.117, 0.128), (0.135, 0.133, 0.14), (0.125, 0.128, 0.14)],
                  plate_var=0.06, rough=(0.42, 0.1), metal=0.25, seam_big=0.4,
                  seam_small=0.14, rivets=False, hatches=0.12, chip=(0.32, 0.32, 0.33),
                  chip_metal=0.9, chip_k=0.9, grime_k=0.7, streak_k=0.25, bleach=0.08),
    # charcoal structure paint
    "hull2": _kind("hull2", tones=[(0.082, 0.085, 0.09), (0.075, 0.078, 0.083),
                                   (0.09, 0.092, 0.097), (0.077, 0.08, 0.086),
                                   (0.086, 0.087, 0.09), (0.08, 0.083, 0.089)],
                   rivets=True, hatches=0.1, seam_big=0.4),
    # pearl yacht white (hab, SOLACE pods)
    # (sun-faded, grimed: a stolen hull that has lived in a rock for years, not a showroom)
    "hull3": _kind("hull3", tones=[(0.43, 0.42, 0.405), (0.40, 0.395, 0.385), (0.46, 0.45, 0.43),
                                   (0.385, 0.38, 0.37), (0.44, 0.43, 0.41), (0.415, 0.41, 0.4)],
                   plate_var=0.05, rough=(0.38, 0.1), metal=0.05, seam_big=0.35,
                   seam_small=0.1, rivets=False, hatches=0.12, chip=(0.12, 0.12, 0.13),
                   chip_metal=0.8, chip_k=0.9, grime_k=1.3, streak_k=0.6, bleach=0.05),
    # corsair magenta, sRGB (1, 0.36, 0.72) as worn linear paint
    "accent": _kind("accent", tones=MAG_TONES, plate_var=0.06, rough=(0.5, 0.1), metal=0.0,
                    seam_big=0.35, seam_small=0.12, rivets=False, hatches=0.0,
                    chip=(0.1, 0.1, 0.11), chip_metal=0.8, chip_k=1.5, grime_k=1.0,
                    streak_k=0.4, bleach=0.25),
    # magenta / black stripes (no yellow anywhere)
    "hazard": _kind("hazard", tones=MAG_TONES, stripes=0.9, chip_k=1.6, bleach=0.2),
    # black quilted thermal blanket
    "shroud": _kind("mli", tones=[(0.035, 0.035, 0.037), (0.03, 0.03, 0.032),
                                  (0.04, 0.04, 0.041), (0.032, 0.032, 0.034),
                                  (0.037, 0.036, 0.036), (0.033, 0.033, 0.035)],
                    rough=(0.9, 0.05), metal=0.0, rivets=False, chip_k=0.0, grime_k=0.6,
                    streak_k=0.2, bleach=0.1, quilt=0.7),
    # stolen freight paint, only on pods
    "cargo": _kind("hull", big=(3.0, 2.0), plate=(1.5, 1.0),
                   tones=[(0.62, 0.21, 0.035), (0.56, 0.19, 0.03), (0.66, 0.24, 0.045),
                          (0.52, 0.18, 0.035), (0.6, 0.22, 0.04), (0.58, 0.2, 0.035)],
                   rivets=True, hatches=0.2, chip_k=1.2),
    "cargo2": _kind("hull", big=(3.0, 2.0), plate=(1.5, 1.0),
                    tones=[(0.07, 0.19, 0.19), (0.065, 0.175, 0.18), (0.075, 0.2, 0.2),
                           (0.06, 0.165, 0.17), (0.072, 0.185, 0.19), (0.068, 0.18, 0.185)],
                    rivets=True, hatches=0.2, chip_k=1.2),
}
st.WORN_KINDS.update(NEST_WORN)


def build_materials():
    wk.build_materials(PRE, MATS, extra=("rust",))
    m = common.make_material
    MATS["shroud"] = m(f"{PRE}_shroud", (0.035, 0.035, 0.04), roughness=0.9)
    MATS["cargo"] = m(f"{PRE}_cargo_orange", (0.62, 0.2, 0.03), roughness=0.6)
    MATS["cargo2"] = m(f"{PRE}_cargo_teal", (0.07, 0.19, 0.19), roughness=0.6)
    base = (0.03, 0.028, 0.025)
    MATS["magenta"] = m(f"{PRE}_light_magenta", base, roughness=0.3,
                        emission=(1.0, 0.12, 0.55), emission_strength=8.0)
    MATS["den_glow"] = m("den_hangar_glow", (0.05, 0.01, 0.03), roughness=0.3,
                         emission=(1.0, 0.2, 0.62), emission_strength=6.5)
    MATS["strobe"] = m(f"{PRE}_light_strobe", base, roughness=0.3,
                       emission=(0.9, 0.95, 1.0), emission_strength=7.0)
    MATS["target"] = m(f"{PRE}_target", base, roughness=0.3,
                       emission=(1.0, 0.25, 0.6), emission_strength=6.0)
    MATS["window_pink"] = m(f"{PRE}_window_pink", base, roughness=0.25,
                            emission=(1.0, 0.25, 0.62), emission_strength=2.2)
    for k in ("magenta", "den_glow", "strobe", "target", "window_pink"):
        MATS[k].use_backface_culling = False
    # first tone as base colour, so --no-textures previews read right
    for k in ("hull", "hull2", "hull3", "accent", "hazard"):
        bsdf = next(n for n in MATS[k].node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = (*NEST_WORN[k]["tones"][0], 1.0)
    ROCK_MATS.clear()
    ROCK_MATS["rock"] = m(f"{PRE}_rock", (0.17, 0.155, 0.135), roughness=0.92,
                          use_vertex_color=True)
    ROCK_MATS["cut"] = m(f"{PRE}_rock_cut", (0.2, 0.19, 0.18), roughness=0.8,
                         use_vertex_color=True)


def label(text, c, n, up, h, col, op=0.85):
    DECALS.append(st.decal(LABELS.index(text), c, n, up, h, col, op))


def girder(p, a, b, w, h, n, mat="dark", chord=0.45, brace=0.25):
    """Open box girder from a to b (w across, h up), n bays of X-braced frames."""
    a, b = V(a), V(b)
    x = (b - a).normalized()
    side = x.cross(V((0, 0, 1))).normalized()
    up = side.cross(x).normalized()
    cs = [side * sx * w / 2 + up * sz * h / 2 for sx in (-1, 1) for sz in (-1, 1)]
    for c in cs:
        parts.strut(p, a + c, b + c, chord, chord, mat)
    for k in range(n):
        p0 = a.lerp(b, k / n)
        p1 = a.lerp(b, (k + 1) / n)
        for sz in (-1, 1):   # top/bottom diagonals
            parts.strut(p, p0 + side * w / 2 + up * sz * h / 2, p1 - side * w / 2 + up * sz * h / 2,
                        brace, brace, mat)
        for sx in (-1, 1):   # side diagonals
            parts.strut(p, p0 + side * sx * w / 2 - up * h / 2, p1 + side * sx * w / 2 + up * h / 2,
                        brace, brace, mat)
        parts.strut(p, p1 + side * w / 2 + up * h / 2, p1 - side * w / 2 + up * h / 2, brace,
                    brace, mat)


def track(d):
    """Rotation matrix taking local +Z onto direction d."""
    return V(d).normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()


# ---------------------------------------------------------------- rock
class Surface:
    """Ray queries against the rock (both halves and the boulders)."""

    def __init__(self, bvh):
        self.bvh = bvh

    def top(self, x, y, default=0.0):
        hit = self.bvh.ray_cast(V((x, y, 200.0)), V((0, 0, -1)))
        return hit[0].z if hit[0] is not None else default

    def toward(self, o, d):
        hit = self.bvh.ray_cast(V(o), V(d).normalized())
        return hit[0], hit[1]


def wall(y, z, s):
    """Point on the slot wall of side s (-1 west, +1 east) at (y, z)."""
    hit = surf.toward((0.0, y, z), (s, 0.0, 0.0))[0]
    if hit is None or abs(hit.x) > CLEFT(y) + 3.0:
        return V((s * CLEFT(y), y, z))
    return hit


def rock_shape(co):
    n = co.normalized()
    p = n * 1.3 + V((31.7, -12.2, 57.9))
    r = (1.0 + 0.20 * noise.noise(p * 0.9) + 0.08 * noise.noise(p * 2.4 + V((7, 3, 1)))
         + 0.035 * noise.noise(p * 5.5))
    # crags: sharp ridges and fracture steps, so the rock reads as broken stone, not clay
    ridge = 1.0 - abs(noise.noise(p * 3.2 + V((4.1, 9.3, 2.7))))
    r += 0.05 * (ridge ** 3 - 0.3)
    step = noise.noise(p * 1.7 + V((8.2, 1.5, 6.6)))
    r += 0.025 * math.floor(step * 3.0) / 3.0
    r += 0.012 * noise.noise(p * 11.0 + V((2.2, 5.1, 7.3)))
    for d, ang, depth in CRATERS:
        dd = n.angle(V(d).normalized()) / ang
        if dd < 1.0:
            r -= depth * (1.0 - dd * dd)
        elif dd < 1.4:
            r += 0.02 * (1.0 - (dd - 1.0) / 0.4)
    q = V((n.x * 30.0, n.y * 40.0, n.z * 15.0)) * r
    if q.z > 0:   # lumpier summits, so the rock is not a flat-topped cake at 45 degrees
        q.z *= 1.0 + 0.22 * max(0.0, noise.noise(p * 1.3 + V((6.4, 2.8, 9.9))))
    if n.y < 0:
        k = 1.0 - 0.3 * n.y * n.y
        q.x *= k
        q.z *= k
    if q.z < 0:
        q.z *= 0.85
    return V((0, 0, -1.5)) + q


def lump_verts(centre, axes, seed):
    """Noisy ellipsoid (icosphere, 1280 tris): returns (verts, faces) as python lists."""
    tmp = bmesh.new()
    bmesh.ops.create_icosphere(tmp, subdivisions=4, radius=1.0)
    rng = random.Random(seed)
    off = V((rng.uniform(-100, 100), rng.uniform(-100, 100), rng.uniform(-100, 100)))
    rotm = Matrix.Rotation(rng.uniform(0, 6.28), 3, "Z") @ Matrix.Rotation(rng.uniform(-0.4, 0.4), 3, "X")
    vs = []
    for v in tmp.verts:
        n = v.co.normalized()
        p = n * 1.4 + off
        r = 1.0 + 0.26 * noise.noise(p * 0.9) + 0.1 * noise.noise(p * 2.3 + V((7, 3, 1)))
        r += 0.08 * ((1.0 - abs(noise.noise(p * 3.0 + V((2, 8, 5))))) ** 3 - 0.3)
        vs.append(rotm @ V((n.x * axes[0], n.y * axes[1], n.z * axes[2])) * r)
    fs = [[v.index for v in f.verts] for f in tmp.faces]
    tmp.free()
    return vs, fs


def build_rock(root):
    noise.seed_set(SEED)
    src = bmesh.new()
    bmesh.ops.create_icosphere(src, subdivisions=6, radius=1.0)
    for v in src.verts:
        v.co = rock_shape(v.co)
    bm = bmesh.new()
    cut = bm.verts.layers.int.new("cut")
    for s in (-1, 1):
        vmap = {}
        for v in src.verts:
            co = v.co
            xs = s * co.x
            flat = xs < 0
            if flat:
                xs = 0.0
            if flat or xs < 0.3:
                xs += 0.35 * abs(noise.noise(co * 0.25 + V((5, 1, 9)))) + 0.12 * noise.noise(co * 1.1)
                xs = max(xs, -0.05)
            nv = bm.verts.new((s * (xs + CLEFT(co.y)), co.y, co.z + (-2.5 if s > 0 else 0.0)))
            nv[cut] = 1 if flat else 0
            vmap[v] = nv
        for f in src.faces:
            bm.faces.new([vmap[v] for v in f.verts])
    src.free()
    for v in bm.verts:   # laser-cut flats
        for x0, x1, y0, y1, zmax in CARVES:
            if x0 <= v.co.x <= x1 and y0 <= v.co.y <= y1 and v.co.z > zmax:
                v.co.z = zmax + 0.12 * noise.noise(v.co * 0.3)
                v[cut] = 1
    for f in bm.faces:
        f.material_index = 1 if all(v[cut] for v in f.verts) else 0
    mesh = bpy.data.meshes.new("den_rock")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(ROCK_MATS["rock"])
    mesh.materials.append(ROCK_MATS["cut"])
    obj = bpy.data.objects.new("den_rock", mesh)
    bpy.context.scene.collection.objects.link(obj)
    mod = obj.modifiers.new("dec", "DECIMATE")
    mod.ratio = 0.3
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.select_set(False)
    mesh = obj.data

    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    main_bvh = BVHTree.FromBMesh(bm)

    def inside(p):
        loc, nrm, _, _ = main_bvh.find_nearest(p)
        return loc is not None and (p - loc).dot(nrm) < 0.0

    for i, (c, axes) in enumerate(BOULDERS):
        c = V(c)
        vs, fs = lump_verts(c, axes, SEED + 11 * i)
        out = V((c.x, c.y, 0.0)).normalized()
        for _ in range(20):
            if not any(inside(c + v) for v in vs):
                break
            c += out * 2.0
        BOULDERS[i] = (tuple(c), axes)
        bv = [bm.verts.new(c + v) for v in vs]
        for f in fs:
            bm.faces.new([bv[k] for k in f]).material_index = 0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f in bm.faces:
        f.smooth = True
    bvh = BVHTree.FromBMesh(bm)
    bm.to_mesh(mesh)
    bm.free()
    mesh.set_sharp_from_angle(angle=math.radians(35))
    col = mesh.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            co = mesh.vertices[mesh.loops[li].vertex_index].co
            if poly.material_index == 0:
                hgt = max(0.0, min(1.0, (co.z + 15.0) / 30.0))
                var = noise.noise(co * 0.06 + V((11, 5, 2)))
                mott = noise.noise(co * 0.18 + V((2, 7, 4)))
                grit = noise.noise(co * 0.5 + V((9, 3, 6)))
                # dust settles on the up-facing flats, bare darker stone on the steep crags
                up = max(0.0, poly.normal.z)
                k = (0.66 + 0.2 * hgt + 0.1 * var + 0.1 * mott + 0.05 * grit) * (0.82 + 0.24 * up)
                w = 0.03 * noise.noise(co * 0.03 + V((3, 9, 1)))
                c = (k + w, k, k - w)
            else:
                k = 0.86 + 0.1 * math.sin(co.z * 2 * math.pi / 1.6)
                if co.z < -1.0:
                    k *= 0.65
                c = (k, k, k)
            col.data[li].color = (*(max(0.0, min(1.0, x)) for x in c), 1.0)
    mesh.color_attributes.active_color = col
    obj.parent = root
    return obj, bvh


# ---------------------------------------------------------------- deck + keel
def build_deck():
    H.box((0, 2, -2.7), (17.6, 76, 0.4), "pad", bevel=0.02)
    for s in (-1, 1):
        H.box((s * 8.7, 2, -2.35), (0.6, 76, 0.3), "hull2", bevel=0.0)
        girder(H, (s * RAIL_X, -55, -4.4), (s * RAIL_X, 40, -4.4), 2.0, 3.0, 19, "dark",
               chord=0.45, brace=0.25)
        parts.pipe(H, (s * 1.5, -36, -4.3), (s * 1.5, 40, -4.3), 0.35, "metal", segs=8)
    for k in range(13):
        y = -36.0 + 6.0 * k
        xw = {s: abs(wall(y, -3.3, s).x) for s in (-1, 1)}
        H.beam((-xw[-1], y, -3.3), (xw[1], y, -3.3), 0.8, 0.8, "hull2")
        for s in (-1, 1):
            H.box((s * (xw[s] - 0.25), y, -3.3), (0.5, 2.4, 2.4), "dark", bevel=0.0)
            for dy in (-0.7, 0.7):
                H.cyl((s * (xw[s] - 0.55), y + dy, -3.3), 0.15, 0.15, 0.3, "metal", segs=6,
                      axis_rot=ALONG_X)


# ---------------------------------------------------------------- catapult
def build_rails():
    for s in (-1, 1):
        x = s * RAIL_X
        H.box((x, -14.5, -1.7), (2.2, 81, 1.2), "hull2", bevel=0.03)
        H.box((x, -14.5, -1.0), (1.0, 81, 0.2), "metal", bevel=0.0)
        H.box((x, -45.5, -2.6), (3.4, 19, 0.6), "hull2", bevel=0.02)
        H.box((x, 26.9, -0.9), (2.4, 1.2, 1.6), "hazard", bevel=0.05)
        for dx in (-0.6, 0.6):
            H.cyl((x + dx, 26.1, -0.6), 0.25, 0.25, 1.2, "metal", segs=8, axis_rot=ALONG_Y)
        # sled arrestors at the boom tip
        H.box((x, -54.2, -1.6), (3.0, 1.6, 2.6), "hull2", bevel=0.05)
        H.box((x, -53.6, -1.6), (3.1, 0.4, 2.7), "accent", bevel=0.0)
        H.box((x, -55.03, -1.6), (2.8, 0.06, 2.4), "hazard", bevel=0.0)
        G.box((x, -55.08, -0.9), (1.6, 0.06, 0.3), "den_glow", bevel=0.0)
        for k in range(20):   # charge strips on the beam shoulders
            yc = 24.0 - 4.0 * k
            for dx in (-0.8, 0.8):
                G.box((x + dx, yc, -1.04), (0.26, 2.6, 0.12), "den_glow", bevel=0.0)
        # capacitor banks for the coils, HV busway
        for y in (20, 14, 8, 2, -4, -10, -16, -22, -28):
            cx = s * 7.2
            for z in (-1.85, -0.65):
                H.cyl((cx, y, z), 0.6, 0.6, 3.6, "hull", segs=10, axis_rot=ALONG_Y)
                for dy in (-1.9, 1.9):
                    H.cyl((cx, y + dy, z), 0.62, 0.62, 0.25, "accent", segs=10,
                          axis_rot=ALONG_Y)
            for dy in (-1.5, 1.5):
                H.box((cx, y + dy, -2.2), (1.6, 0.6, 0.6), "dark", bevel=0.0)
            H.box((s * 6.55, y, -1.2), (0.6, 0.3, 0.3), "metal", bevel=0.0)
        H.box((s * 6.1, -3, -1.2), (0.3, 52, 0.3), "metal", bevel=0.0)
    for k in range(11):
        H.box((0, -36.0 + 6.0 * k, -2.4), (11.6, 0.8, 0.2), "dark", bevel=0.0)


def parked_raider(P, c, tilt=0.0):
    """Corsair raider (corsair_raider.glb style), nose toward Blender -Y, ~11.5 m long."""
    Ln = 12.8
    rot4 = Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Rotation(tilt, 4, "X")
    m = Matrix.Translation(c) @ rot4 @ Matrix.Scale(0.9, 4)
    rings = []
    for yf, w, top, bot in ((0.5, 0.04, 0.04, 0.03), (0.3, 0.4, 0.35, 0.2), (0.0, 0.85, 0.6, 0.4),
                            (-0.35, 0.95, 0.6, 0.45), (-0.5, 0.8, 0.5, 0.4)):
        pts = [(0.0, top), (w * 0.62, top * 0.55), (w, 0.0), (w * 0.55, -bot),
               (-w * 0.55, -bot), (-w, 0.0), (-w * 0.62, top * 0.55)]
        rings.append([m @ V((x, yf * Ln, z)) for x, z in pts])
    P.loft(rings, "hull", mat_fn=lambda i, j: "accent" if i in (1, 2) and j in (0, 6) else "hull")
    for sx in (-1, 1):
        pts = [(sx * x, y) for x, y in ((0.8, 0.0), (2.4, -0.4 * Ln), (2.45, -0.5 * Ln),
                                         (0.8, -0.36 * Ln))]
        if sx < 0:
            pts.reverse()
        P.slab(pts, -0.08, 0.08, "hull", matrix=m)
        P.beam(m @ V((sx * 0.85, 0.02 * Ln, 0)), m @ V((sx * 2.4, -0.4 * Ln, 0)), 0.18, 0.2,
               "accent")
        ny = -0.5 * Ln - 0.6
        P.cyl(m @ V((sx * 0.62, ny, -0.05)), 0.42, 0.42, 2.6, "metal", segs=8,
              axis_rot=rot4 @ ALONG_Y)
        P.cyl(m @ V((sx * 0.62, ny - 1.35, -0.05)), 0.48, 0.48, 0.3, "dark", segs=8,
              axis_rot=rot4 @ ALONG_Y)
        P.box(m @ V((sx * 0.55, 0.16 * Ln, -0.15)), (0.4, 1.6, 0.12), "dark", r=rot4, bevel=0.0)
        P.cyl(m @ V((sx * 0.72, 0.33 * Ln, -0.16)), 0.08, 0.08, 3.0, "metal", segs=6,
              axis_rot=rot4 @ ALONG_Y)
    P.slab([(-0.18 * Ln, 0.5), (-0.46 * Ln, 0.45), (-0.5 * Ln, 1.15), (-0.36 * Ln, 1.15)][::-1],
           -0.06, 0.06, "hull2", matrix=m @ parts.SIDE)
    yc = 0.22 * Ln
    cm = m @ Matrix.Translation((0, yc, 0.42)) @ Matrix.Rotation(-0.065, 4, "X")
    P.slab([(-0.2, -0.9), (0.2, -0.9), (0.2, 0.9), (-0.2, 0.9)], -0.04, 0.05, "window_pink",
           matrix=cm)


def build_sleds():
    for s in (-1, 1):
        x = s * RAIL_X
        H.box((x, SLED_Y, -0.45), (3.0, 4.2, 0.9), "hull", bevel=0.06)
        for dx in (-0.65, 0.65):
            H.box((x + dx, SLED_Y, -1.15), (0.3, 4.0, 0.5), "metal", bevel=0.0)
        for side in (-1, 1):
            for yy in (10.6, 13.4):
                H.beam((x + side * 1.3, yy, -0.2), (x + side * 0.6, yy, 0.35), 0.3, 0.3, "accent")
                H.box((x + side * 0.6, yy, 0.4), (0.5, 0.6, 0.2), "dark", bevel=0.0)
        parked_raider(S, (x, SLED_Y, RAIDER_Z))


# ---------------------------------------------------------------- cranes
def bridge(y, trolley_size, trolley_z):
    girder(H, (-8.6, y, 7.4), (8.6, y, 7.4), 1.6, 1.6, 4, "dark")
    for s in (-1, 1):
        H.box((s * 8.6, y, 7.1), (1.6, 3.0, 1.2), "hull", bevel=0.05)
    H.box((0, y, trolley_z), trolley_size, "hull2", bevel=0.05)


def build_cranes():
    for s in (-1, 1):
        H.box((s * 8.6, 1, 6.0), (1.0, 46, 1.4), "hull2", bevel=0.03)
        for y in (-18, -10, -2, 6, 14, 22):
            H.beam((s * abs(wall(y, 4.6, s).x), y, 4.6), (s * 8.6, y, 5.3), 0.6, 0.6, "dark")
    # catcher: plucks a returning raider out of the lane
    bridge(CATCH_Y, (2.8, 2.4, 1.4), 5.9)
    S.box((0, CATCH_Y, 4.95), (1.0, 1.0, 0.5), "metal", bevel=0.0)
    S.box((0, CATCH_Y, 4.4), (1.6, 1.6, 0.6), "dark", bevel=0.0)
    for sx in (-1, 1):
        for sy in (-1, 1):
            S.beam((sx * 0.8, CATCH_Y + sy * 0.8, 4.1), (sx * 0.9, CATCH_Y + sy * 1.4, 3.3), 0.3,
                   0.3, "accent")
    parked_raider(S, (0, CATCH_Y, 3.0), tilt=0.04)
    # rearm bridge over the ready pair
    bridge(REARM_Y, (3.2, 2.6, 1.6), 5.8)
    for s in (-1, 1):
        H.cyl((s * 2.3, REARM_Y, 5.8), 0.8, 0.8, 1.2, "metal", segs=12, axis_rot=ALONG_X)
    S.box((0, REARM_Y, 2.9), (1.6, 2.6, 1.2), "hazard", bevel=0.05)
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.strut(S, (sx * 0.6, REARM_Y + sy * 0.9, 5.0), (sx * 0.6, REARM_Y + sy * 0.9, 3.5),
                        0.08, 0.08, "dark")
    for s in (-1, 1):
        pts = [V((s * 2.3, 12.0, 5.0)), V((s * 3.4, 12.3, 3.6)), V((s * 4.0, 12.6, 2.2)),
               V((s * 4.2, 12.8, 1.35))]
        for a, b in zip(pts, pts[1:]):
            parts.pipe(S, a, b, 0.14, "dark", segs=6)


# ---------------------------------------------------------------- ties + jacks
def build_ties():
    for y in TIES_Y:
        xw = {s: abs(wall(y, TIE_Z, s).x) for s in (-1, 1)}
        girder(H, (-xw[-1], y, TIE_Z), (xw[1], y, TIE_Z), 2.4, 2.4, 4, "dark")
        for s in (-1, 1):
            H.box((s * (xw[s] + 0.5), y, TIE_Z), (2.6, 3.4, 3.4), "hull2", bevel=0.06)
            for dy in (-1.1, 1.1):
                for dz in (-1.1, 1.1):
                    H.cyl((s * (xw[s] - 0.85), y + dy, TIE_Z + dz), 0.18, 0.18, 0.3, "metal",
                          segs=6, axis_rot=ALONG_X)
            L.box((s * (xw[s] + 0.5), y, TIE_Z + 1.9), (0.7, 0.7, 0.42), "magenta", bevel=0.0)
        H.cyl((0, y, TIE_Z), 0.9, 0.9, 3.0, "metal", segs=10, axis_rot=ALONG_X)
        for dx in (-1.1, 1.1):
            H.cyl((dx, y, TIE_Z), 0.95, 0.95, 0.4, "accent", segs=10, axis_rot=ALONG_X)
    for z, r in ((3.5, 1.1), (-7.5, 0.8)):
        xw = {s: abs(wall(JACK_Y, z, s).x) - 0.2 for s in (-1, 1)}
        for s in (-1, 1):
            H.box((s * (xw[s] + 0.2), JACK_Y, z), (1.0, 4.2, 4.2), "rust", bevel=0.03)
            for dy in (-1.5, 1.5):
                for dz in (-1.5, 1.5):
                    H.cyl((s * (xw[s] - 0.35), JACK_Y + dy, z + dz), 0.22, 0.22, 0.3, "metal",
                          segs=6, axis_rot=ALONG_X)
            H.cyl((s * (xw[s] - 0.9), JACK_Y, z), r * 1.08, r * 1.08, 0.5, "hazard", segs=12,
                  axis_rot=ALONG_X)
        H.tube((-xw[-1] + 0.5, JACK_Y, z), (0.6, JACK_Y, z), r, r, "hull2", segs=12)
        H.cyl((0.6, JACK_Y, z), r * 1.25, r * 1.25, 0.7, "dark", segs=12, axis_rot=ALONG_X)
        H.tube((0.6, JACK_Y, z), (xw[1] - 0.5, JACK_Y, z), r * 0.55, r * 0.55, "metal", segs=10)
        parts.pipe(H, (-xw[-1] + 1.0, JACK_Y, z + r + 0.15), (0.4, JACK_Y, z + r + 0.15), 0.12,
                   "dark")


# ---------------------------------------------------------------- wall fit-out
def build_walls():
    for s in (-1, 1):
        H.box((s * 8.4, 1, 2.5), (1.0, 46, 0.15), "pad", bevel=0.0)
        for y in range(-22, 25, 4):
            H.beam((s * abs(wall(y, 1.6, s).x), y, 1.6), (s * 7.95, y, 2.42), 0.25, 0.25, "dark")
        for y in range(-22, 25, 3):
            parts.strut(H, (s * 7.95, y, 2.58), (s * 7.95, y, 3.6), 0.08, 0.08, "dark")
        parts.strut(H, (s * 7.95, -22, 3.6), (s * 7.95, 24, 3.6), 0.08, 0.08, "metal")
        parts.pipe(H, (s * 8.65, -22, 0.8), (s * 8.65, 24, 0.8), 0.3, "metal", segs=8)
        parts.pipe(H, (s * 8.75, -22, 7.6), (s * 8.75, 24, 7.6), 0.3, "hull2", segs=8)
        for y in range(-20, 25, 6):
            H.box((s * 8.75, y, 0.8), (0.5, 0.4, 0.9), "dark", bevel=0.0)
            H.box((s * 8.85, y, 7.6), (0.5, 0.4, 0.9), "dark", bevel=0.0)
    # airlocks from the rock tunnels onto the catwalks
    for s, y in ((-1, 2.0), (1, -6.0)):
        xw = abs(wall(y, 3.9, s).x)
        H.box((s * (xw - 0.3), y, 3.9), (0.6, 3.2, 2.6), "hull2", bevel=0.05)
        H.box((s * (xw - 0.62), y, 3.8), (0.1, 1.8, 2.2), "dark", bevel=0.0)
        xf = s * (xw - 0.66)
        H.box((xf, y, 5.02), (0.08, 2.3, 0.25), "hazard", bevel=0.0)
        H.box((xf, y, 2.68), (0.08, 2.3, 0.25), "hazard", bevel=0.0)
        for dy in (-1.05, 1.05):
            H.box((xf, y + dy, 3.85), (0.08, 0.25, 2.1), "hazard", bevel=0.0)
        L.box((s * (xw - 0.5), y, 5.5), (0.5, 0.5, 0.3), "green", bevel=0.0)
    # ops-room ports in the cliffs
    for s in (-1, 1):
        for mid in (-14, -6, 2, 10, 18):
            if (s < 0 and mid == 2) or (s > 0 and mid in (-6, -14)):
                continue
            for dy in (-1.5, 1.5):
                y = mid + dy
                hit = wall(y, 4.2, s)
                n = V((-s, 0, 0))
                H.box(hit + n * 0.15, (0.3, 1.2, 0.9), "dark", bevel=0.0)
                lit = "window_pink" if RNG.random() < 0.15 else parts.pick_lit(RNG, "hab")
                parts.window(H, hit + n * 0.32, n, (0, 0, 1), 1.0, 0.6, lit)
    # HV junction on the east wall
    xw = abs(wall(-14, 4.2, 1).x)
    H.box((xw - 0.45, -14, 4.2), (0.9, 2.4, 1.8), "hull2", bevel=0.04)
    H.box((xw - 0.2, -14, 0.8), (0.3, 1.2, 5.0), "dark", bevel=0.0)
    H.beam((xw - 0.3, -14, -1.6), (6.1, -14, -1.2), 0.4, 0.3, "metal")
    return xw


def pipe_run(pts, r, mat, clear=True, tray=False):
    """Pipe through pts with a collar at every bend. With clear, each bend is lifted so
    the runs either side of it stay above the rock, and a support strut drops to the rock
    when the bend stands off it."""
    pts = [V(p) for p in pts]
    if clear:
        for i in range(1, len(pts) - 1):
            a, b = pts[i - 1], pts[i + 1]
            hi = max(surf.top(*(a.lerp(b, t / 8.0)).xy, default=-99.0) for t in range(1, 8))
            hi = max(hi, surf.top(*pts[i].xy, default=-99.0))
            pts[i].z = max(pts[i].z, hi + r + 0.35)
    for a, b in zip(pts, pts[1:]):
        parts.pipe(H, a, b, r, mat, segs=8)
    for i in range(1, len(pts) - 1):
        d = (pts[i + 1] - pts[i - 1]).normalized()
        H.cyl(pts[i], r * 1.35, r * 1.35, r * 2.6, "dark", segs=8, axis_rot=track(d))
        if tray:
            H.box(pts[i] - V((0, 0, r + 0.15)), (0.6, 1.2, 0.3), "dark", bevel=0.0)
        zt = surf.top(pts[i].x, pts[i].y, default=-99.0)
        if clear and pts[i].z - r - zt > 0.5:
            parts.strut(H, pts[i] - V((0, 0, r)), V((pts[i].x, pts[i].y, zt - 0.3)), 0.25, 0.25,
                        "dark")
    return pts


# ---------------------------------------------------------------- hab, bunker, rads, tanks
def build_hab():
    parts.capsule(H, -10.0, 16.0, 3.8, lambda i, j: "hull3", segs=16, x=-25.0, z=10.7,
                  dome0=0.55, dome1=0.7, steps=3)
    H.cyl((-25, 4.0, 10.7), 3.95, 3.95, 1.6, "accent", segs=16, axis_rot=ALONG_Y)
    for y in (-6.0, 12.0):
        H.cyl((-25, y, 10.7), 4.0, 4.0, 0.6, "dark", segs=16, axis_rot=ALONG_Y)
    for sx in (-1, 1):
        wk.win_row(H, RNG, (-25 + sx * 2.28, -6, 13.74), (-25 + sx * 2.28, 12, 13.74),
                   (sx * 0.6, 0, 0.8), 8, 0.6, 0.45, "hab")
        for y in (-6.0, 3.0, 12.0):
            H.box((-25 + sx * 4.3, y, 8.2), (1.2, 2.0, 2.4), "dark", bevel=0.03)
    H.cyl((-25, 16.3, 10.7), 1.6, 1.6, 0.6, "metal", axis_rot=ALONG_Y)
    H.tube((-21.6, 4, 10.0), (-19.4, 4, 10.0), 1.1, 1.1, "hull2", segs=10)
    H.cyl((-19.8, 4, 10.0), 1.4, 1.4, 0.4, "hazard", segs=10, axis_rot=ALONG_X)


def build_bunker(junction_x):
    H.box((22, -3, 6.6), (14, 12, 5.2), "hull2", bevel=0.04)
    H.box((22, -9.15, 6.4), (12, 0.3, 4.2), "hull", bevel=0.0)
    H.cyl((22, -3, 10.6), 3.4, 3.0, 2.8, "metal", segs=14)
    H.cyl((22, -3, 10.0), 3.45, 3.45, 0.5, "accent", segs=14)
    for y in (1.5, -7.5):
        H.cyl((28.3, y, 10.4), 0.5, 0.5, 2.4, "dark", segs=8)
    # thermal tent (black quilted blankets), open at the ends
    S.box((22, -3, 12.3), (9.0, 9.4, 0.3), "shroud", bevel=0.2)
    S.box((17.05, -3, 10.75), (0.3, 9.4, 3.3), "shroud", r=parts.rot(ry=0.28), bevel=0.2)
    S.box((26.95, -3, 10.75), (0.3, 9.4, 3.3), "shroud", r=parts.rot(ry=-0.28), bevel=0.2)
    for y in (-6.5, -3.0, 0.5):
        S.beam((17.5, y, 12.5), (26.5, y, 12.5), 0.12, 0.05, "dark")
        S.beam((17.45, y, 12.4), (16.6, y, 9.2), 0.12, 0.05, "dark")
        S.beam((26.55, y, 12.4), (27.4, y, 9.2), 0.12, 0.05, "dark")
    # power conduits to the HV junction in the slot
    xw = junction_x
    for yy, dy in ((-7.4, 0.6), (-8.6, -0.6)):
        pts = [V((15.0, yy, 7.0)), V((12.0, yy - 4.0, surf.top(12, yy - 4) + 0.6)),
               V((xw + 0.4, -14 + dy, surf.top(xw + 0.4, -14) + 0.5)),
               V((xw - 0.4, -14 + dy, 5.1))]
        pipe_run(pts, 0.45, "hull2", tray=True)
    pipe_run([V((21, 3.2, 6.5)), V((21, 6.5, surf.top(21, 6.5) + 0.5)), V((21, 10.5, 7.2))],
             0.4, "metal")


def build_radiators():
    for x in (16.0, 18.5, 21.0, 23.5, 26.0):
        parts.radiator(H, (x, 17, 4.25), 12.0, 5.5, (1, 0, 0), "radiator", "dark", ribs=8, t=0.12)
        for y in (11.2, 22.8):
            H.box((x, y, 1.8), (0.6, 0.6, 0.6), "dark", bevel=0.0)
    H.cyl((21, 17, 1.8), 0.5, 0.5, 11.0, "metal", segs=8, axis_rot=ALONG_X)
    H.cyl((21, 17, 7.2), 0.35, 0.35, 11.0, "metal", segs=8, axis_rot=ALONG_X)


def build_tanks():
    for x in (-17.0, -23.0):
        wk.tank_v(H, (x, 23.5, 6.0), 2.6, 7.5, "hull", "accent", segs=14)
        H.cyl((x, 23.5, 6.4), 2.75, 2.75, 0.6, "dark", segs=14)
    H.beam((-17, 23.5, 12.0), (-23, 23.5, 12.0), 0.4, 0.4, "dark")
    pts = [V((-14.6, 23.5, 9.0)), V((-10.6, 18.5, surf.top(-10.6, 18.5) + 0.5)),
           V((-8.75, 18.5, 7.6))]
    pipe_run(pts, 0.3, "metal")


# ---------------------------------------------------------------- stern cross-dock
def build_stern():
    for s in (-1, 1):
        H.box((s * 8.2, 34, 5.3), (1.4, 1.4, 15.6), "hull2", bevel=0.04)
        parts.strut(H, (s * 8.2, 34, 14.7), (0, 47, 15.2), 0.3, 0.3, "dark")
        L.box((s * 8.6, 34, 14.95), (0.7, 0.7, 0.42), "magenta", bevel=0.0)
    H.box((0, 34, 13.9), (18.0, 1.6, 1.6), "hull", bevel=0.04)
    H.box((0, 33.18, 13.9), (18.1, 0.06, 0.4), "accent", bevel=0.0)
    H.box((0, 37, 15.2), (1.4, 24, 1.0), "hull2", bevel=0.03)
    H.box((0, 44, 14.1), (2.2, 2.6, 1.2), "dark", bevel=0.04)
    L.box((0, 44, 13.45), (0.5, 0.5, 0.3), "light", bevel=0.0)
    pods = [((0, 29, -1.2), "cargo2", "dark"), ((0, 29, 1.4), "hull3", "cargo"),
            ((0, 31.8, -1.2), "hull3", "cargo2"), ((0, 31.8, 1.4), "accent", "dark"),
            ((0, 38, -1.2), "hull3", "cargo"), ((0, 38, 1.4), "cargo", "dark"),
            ((0, 44, 7.7), "hull3", "cargo2")]
    for c, body, band in pods:
        wk.cargo_pod(S, c, (2.6, 12.0, 2.6), rot_z=math.pi / 2, body=body, band=band, frame="dark")
    S.box((0, 44, 9.3), (12.2, 2.8, 0.3), "dark", bevel=0.0)
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.strut(S, (sx * 1.0, 44 + sy * 1.2, 13.5), (sx * 5.8, 44 + sy * 1.2, 9.45), 0.08,
                        0.08, "dark")
    # fence dock
    H.box((0, 41.5, -2.7), (10, 3, 0.4), "pad", bevel=0.02)
    H.tube((0, 41, -0.3), (0, 45, -0.3), 1.6, 1.6, "hull2", segs=12)
    for y in (42.0, 44.0):
        H.box((0, y, -2.2), (3.4, 0.8, 0.6), "dark", bevel=0.0)
    H.cyl((0, 45.4, -0.3), 2.8, 2.8, 0.9, "hull2", segs=16, axis_rot=ALONG_Y)
    H.cyl((0, 45.9, -0.3), 2.2, 2.2, 0.2, "dark", segs=16, axis_rot=ALONG_Y)
    H.cyl((0, 44.6, -0.3), 2.9, 2.9, 0.4, "accent", segs=16, axis_rot=ALONG_Y)
    for a in (0.0, math.pi / 2, math.pi, 1.5 * math.pi):
        H.box((2.9 * math.cos(a), 45.6, -0.3 + 2.9 * math.sin(a)), (0.8, 0.6, 0.5), "metal",
              r=Matrix.Rotation(-a, 4, "Y"), bevel=0.0)
    for sx in (-1, 1):
        L.box((sx * 2.95, 45.4, -0.3), (0.6, 0.6, 0.6), "magenta", bevel=0.0)
    for z in (2.7, -3.3):
        L.box((0, 45.9, z), (0.5, 0.5, 0.5), "green", bevel=0.0)


# ---------------------------------------------------------------- mouth
def build_mouth():
    for y in (-50.0, -42.0):
        H.beam((-RAIL_X, y, -4.4), (RAIL_X, y, -4.4), 0.6, 0.8, "dark")
    for sx in (-1, 1):
        H.beam((sx * RAIL_X, -50, -4.4), (-sx * RAIL_X, -42, -4.4), 0.35, 0.35, "dark")
    for s in (-1, 1):
        H.box((s * 8.0, COLLAR_Y, 0.0), (1.2, 1.6, 8.0), "hull2", bevel=0.04)
        H.box((s * 8.0, -53.32, 0.0), (1.0, 0.06, 7.6), "hazard", bevel=0.0)
        G.box((s * 7.35, -53.35, 0.0), (0.2, 0.12, 7.6), "den_glow", bevel=0.0)
        for z in (5.2, -4.9):
            L.box((s * 8.6, -53.4, z), (0.8, 0.8, 0.48), "magenta", bevel=0.0)
    H.box((0, COLLAR_Y, 4.6), (17.2, 1.6, 1.2), "hull2", bevel=0.04)
    H.box((0, COLLAR_Y, -4.4), (17.2, 1.6, 1.0), "hull2", bevel=0.04)
    G.box((0, -53.35, 3.85), (14.4, 0.12, 0.2), "den_glow", bevel=0.0)
    for s in (-1, 1):
        H.box((s * 9.75, -33, 0.25), (0.8, 2.0, 5.5), "hull", bevel=0.05)
        H.box((s * 9.33, -33, 0.25), (0.1, 1.6, 5.0), "accent", bevel=0.0)
        parts.strut(H, (s * 8.6, COLLAR_Y, 5.2), (s * 9.75, -33, 3.0), 0.6, 0.6, "dark")
        parts.strut(H, (s * RAIL_X, -53, -5.9), wall(-30, -4.5, s), 0.7, 0.7, "dark")
        for y in (-38, -42, -46, -50):
            L.box((s * 5.65, y, -2.1), (0.6, 0.6, 0.36), "strobe", bevel=0.0)
        for y in (-34, -30, -26, -22, -18):
            x = s * (CLEFT(y) + 0.9)
            z = surf.top(x, y) + 0.3
            H.box((x, y, z - 0.3), (0.6, 0.6, 0.5), "dark", bevel=0.0)
            L.box((x, y, z + 0.15), (0.5, 0.5, 0.4), "magenta", bevel=0.0)
        for y in range(-36, 37, 8):
            L.box((s * 8.7, y, -1.95), (0.5, 0.5, 0.5), "magenta", bevel=0.0)
    L.box((0, CATCH_Y, 5.05), (0.5, 0.5, 0.3), "light", bevel=0.0)
    L.box((0, REARM_Y, 4.95), (0.5, 0.5, 0.3), "light", bevel=0.0)


# ---------------------------------------------------------------- sensors + tethers
def build_sensors():
    x, y = 28.0, -15.0
    z = surf.top(x, y)
    S.box((x, y, z + 0.6), (3.0, 3.0, 1.2), "hull2", bevel=0.05)
    S.cyl((x, y, z + 5.7), 0.45, 0.3, 9.0, "metal", segs=8)
    S.sphere((x, y, z + 10.9), 1.3, "hull2", segs=12, rings=8)
    S.cyl((x, y - 1.25, z + 10.9), 0.7, 0.7, 0.15, "glass", segs=12, axis_rot=ALONG_Y)
    S.beam((x, y, z + 8.4), (x + 1.8, y, z + 8.4), 0.3, 0.3, "dark")
    S.cyl((x + 1.8, y, z + 9.0), 0.5, 0.5, 1.4, "hull", segs=10, axis_rot=ALONG_Y)
    S.box((x + 1.8, y, z + 8.55), (0.3, 0.3, 0.6), "dark", bevel=0.0)
    for wx, wy in ((26.6, -16.2), (29.4, -13.8)):
        S.cyl((wx, wy, z + 3.2), 0.06, 0.06, 4.0, "dark", segs=5)
    L.box((x, y, z + 12.4), (0.8, 0.8, 0.48), "magenta", bevel=0.0)


def build_tethers():
    for c, axes in BOULDERS:
        c = V(c)
        target = V((-24.0 if c.x < 0 else 24.0, 0.0, 0.0))
        d = (target - c)
        d.z = 0.0
        d.normalize()
        # exit point of the boulder toward the rock (ray from inside hits its far side)
        a = None
        for k in range(40):
            hit = surf.toward(c + d * (0.25 * k), d)[0]
            if hit is not None and (hit - c).length < max(axes) * 1.6:
                a = hit
                break
        if a is None:
            a = c + d * max(axes)
        b = surf.toward(a + d * 0.3, d)[0]
        if b is None or (b - a).length > 30:
            print("WARN tether miss", c)
            continue
        parts.strut(S, a - d * 0.3, b + d * 0.3, 0.25, 0.25, "dark")
        for p, sgn in ((a, 1), (b, -1)):
            S.box(p + d * sgn * 0.1, (1.6, 1.6, 0.5), "metal", r=track(d), bevel=0.0)


# ---------------------------------------------------------------- PDC turrets
def pdc_matrix(site):
    x, y, sz, a = site
    return Matrix.Translation((x, y, sz)) @ Matrix.Rotation(math.radians(a) - math.pi / 2, 4, "Z")


def build_plinths():
    for i, (x, y, sz, a) in enumerate(PDCS):
        H.box((x, y, sz - 0.5), (8.4, 8.4, 1.0), "dark", bevel=0.03)
        for dx in (-3.8, 3.8):
            for dy in (-3.8, 3.8):
                cx, cy = x + dx, y + dy
                zt = surf.top(cx, cy, default=sz - 6.0)
                if zt < sz - 1.2:
                    parts.strut(H, (cx, cy, sz - 1.0), (cx, cy, zt - 0.8), 0.8, 0.8, "dark")
                    H.box((cx, cy, zt), (1.8, 1.8, 0.4), "rust", bevel=0.0)
        M = pdc_matrix(PDCS[i])
        L.box(M @ (PDC_S * V((-1.4, -1.8, 4.45))), (0.6, 0.6, 0.36), "magenta", bevel=0.0)


def build_pdc(i):
    """Rotary PDC in its own frame (z 0 = plinth top, barrels along +Y)."""
    p = parts.PanelPart(f"den_pdc_{i + 1}", MATS)
    p.cyl((0, 0, 0.7), 3.0, 2.8, 1.4, "hull2", segs=16)
    p.cyl((0, 0, 0.35), 3.03, 3.03, 0.3, "accent", segs=16)
    p.cyl((0, 0, 1.55), 2.7, 2.7, 0.3, "metal", segs=16)
    side = Matrix.Translation((0, 0, 1.7)) @ parts.SIDE
    prof = [(-2.6, 0.0), (2.2, 0.0), (2.9, 1.1), (1.8, 2.6), (-2.0, 2.6), (-2.8, 1.3)]
    p.slab(prof[::-1], -1.8, 1.8, "hull", matrix=side)
    for sx in (-1, 1):
        p.slab([(-2.0, 0.4), (1.6, 0.4), (2.2, 1.1), (1.3, 2.2), (-1.8, 2.2)][::-1],
               sx * 1.8, sx * 1.95, "accent", matrix=side)
    p.cyl((0, -2.4, 3.0), 1.2, 1.2, 3.2, "hull2", segs=12, axis_rot=ALONG_X)
    p.beam((2.1, -2.2, 3.2), (2.1, 1.6, 3.2), 0.4, 0.4, "dark")
    p.box((1.2, 0.6, 4.65), (0.9, 1.0, 0.7), "dark", bevel=0.03)
    p.box((1.2, 1.12, 4.65), (0.5, 0.06, 0.35), "target", bevel=0.0)
    fwd = V((0, math.cos(PDC_EL), math.sin(PDC_EL)))
    q = track(fwd)
    R = V((0, 2.9, 3.0))
    X = V((1, 0, 0))
    U = fwd.cross(X).normalized()
    p.box((0, 2.6, 3.0), (1.6, 1.0, 1.4), "dark", bevel=0.05)
    p.cyl(R + fwd * 0.8, 0.5, 0.5, 1.2, "metal", segs=10, axis_rot=q)
    p.cyl(R + fwd * 2.45, 0.42, 0.42, 2.9, "dark", segs=10, axis_rot=q)
    p.cyl(R + fwd * 4.4, 0.36, 0.36, 0.2, "dark", segs=10, axis_rot=q)
    for k in range(6):
        t = math.radians(60 * k)
        p.cyl(R + fwd * 5.0 + 0.24 * (math.cos(t) * X + math.sin(t) * U), 0.09, 0.09, 2.6,
              "metal", segs=6, axis_rot=q)
    p.cyl(R + fwd * 6.15, 0.36, 0.36, 0.3, "dark", segs=10, axis_rot=q)
    tip = R + fwd * 6.3
    assert (tip - PDC_TIP).length < 0.01, tip
    return p


# ---------------------------------------------------------------- decals
def build_decals():
    DECALS.clear()
    il, idk = wk.INK_LIGHT, wk.INK_DARK
    label("#CHEV", (0, -33, -2.49), (0, 0, 1), (1, 0, 0), 1.2, il, 0.8)
    label("KEEP CLEAR", (0, -21, -2.49), (0, 0, 1), (0, -1, 0), 0.9, il)
    label("HOT RAIL", (0, 21, -2.49), (0, 0, 1), (0, -1, 0), 0.9, MAG_INK, 0.85)
    label("RAIL A", (-5.31, -40, -1.7), (-1, 0, 0), (0, 0, 1), 0.8, il)
    label("RAIL B", (5.31, -40, -1.7), (1, 0, 0), (0, 0, 1), 0.8, il)
    label("LAUNCH", (0, -53.31, 4.6), (0, -1, 0), (0, 0, 1), 0.8, il)
    label("DANGER", (22, -9.31, 6.6), (0, -1, 0), (0, 0, 1), 0.9, il)
    label("CN-7", (14.99, -3, 7.0), (-1, 0, 0), (0, 0, 1), 1.2, il)
    label("NO STEP", (22, -8.4, 9.21), (0, 0, 1), (0, 1, 0), 0.5, il, 0.6)
    for x in (-17.0, -23.0):
        label("REMASS", (x, 20.89, 8.6), (0, -1, 0), (0, 0, 1), 0.55, il)
    label("ARIADNE", (-28.31, 0.5, 12.6), (-0.87, 0, 0.5), (0, 0, 1), 1.0, idk, 0.35)
    label("SHRIKE", (-28.31, 8.0, 12.6), (-0.87, 0, 0.5), (0, 0, 1), 1.2, MAG_INK, 0.9)
    for x in (-25.6, -24.4):
        label("#BAR", (x, -2.0, 14.52), (0, 0, 1), (0.927, 0.375, 0), 0.6, MAG_INK, 0.95)
    label("SOLACE", (2.5, 27.77, 1.4), (0, -1, 0), (0, 0, 1), 1.0, idk)
    label("SOLACE", (2.5, 36.77, -1.2), (0, -1, 0), (0, 0, 1), 1.0, idk)
    label("#BAR", (3.3, 36.76, -1.2), (0, -1, 0), (0, 0, 1), 1.0, idk, 0.95)
    label("OSTRA 14", (2.5, 42.77, 7.7), (0, -1, 0), (0, 0, 1), 0.9, idk)
    for name, c, n in (("PD 1", (-18, -29.21, 8.0), (0, -1, 0)),
                       ("PD 2", (18, -28.21, 5.5), (0, -1, 0)),
                       ("PD 3", (-19, 35.71, 6.5), (0, 1, 0)),
                       ("PD 4", (19, 34.21, 4.5), (0, 1, 0))):
        label(name, c, n, (0, 0, 1), 0.6, il)


# ---------------------------------------------------------------- assemble
def build_nest():
    global H, S, G, L, surf
    build_materials()
    root = parts.make_root(PRE, size=20)
    rock, bvh = build_rock(root)
    surf = Surface(bvh)
    H = parts.PanelPart("den_hull", MATS)
    S = parts.PanelPart("den_salvage", MATS)
    G = parts.Part("den_hangar_glow", MATS)
    L = parts.Part("den_lights", MATS)
    build_deck()
    build_rails()
    build_sleds()
    build_cranes()
    build_ties()
    jx = build_walls()
    build_hab()
    build_bunker(jx)
    build_radiators()
    build_tanks()
    build_stern()
    build_mouth()
    build_sensors()
    build_tethers()
    build_plinths()
    build_decals()
    hull = H.finish(root)
    sal = S.finish(root)
    glow = G.finish(root)
    lights = L.finish(root)
    pdcs = []
    for i, site in enumerate(PDCS):
        o = build_pdc(i).finish(root)
        o.data.transform(Matrix.Scale(PDC_S, 4))
        o.data.transform(pdc_matrix(site))
        pdcs.append(o)
    return root, rock, hull, sal, glow, lights, pdcs


def bake_rock_ao(rock, distance=7.0, samples=64):
    """Bake ambient occlusion (rock plus every piece of hardware on it) into the rock's
    vertex colour: crevices, the slot walls and the ground under the plinths, tanks and
    hab darken, so the kit sits on the stone instead of floating over flat clay."""
    scene = bpy.context.scene
    engine = scene.render.engine
    st.setup_cycles(samples)
    if scene.world is None:
        scene.world = bpy.data.worlds.new("bake_world")
    scene.world.light_settings.distance = distance
    mesh = rock.data
    ao = mesh.color_attributes.new("AO", "FLOAT_COLOR", "CORNER")
    mesh.color_attributes.active_color = ao
    bpy.ops.object.select_all(action="DESELECT")
    rock.select_set(True)
    bpy.context.view_layer.objects.active = rock
    bpy.ops.object.bake(type="AO", target="VERTEX_COLORS")
    rock.select_set(False)
    col = mesh.color_attributes["Col"]
    ao = mesh.color_attributes["AO"]
    mats = [p.material_index for p in mesh.polygons]
    loop_mat = [0] * len(mesh.loops)
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            loop_mat[li] = mats[poly.index]
    lo = []
    for li, (c, a) in enumerate(zip(col.data, ao.data)):
        occ = max(0.0, min(1.0, a.color[0]))
        # outer stone takes more of it than the laser-cut faces (lit by the slot work lights)
        k = (0.3 + 0.7 * occ ** 1.3) if loop_mat[li] == 0 else (0.45 + 0.55 * occ)
        lo.append(occ)
        c.color = (c.color[0] * k, c.color[1] * k, c.color[2] * k, 1.0)
    mesh.color_attributes.remove(mesh.color_attributes["AO"])
    col = mesh.color_attributes["Col"]
    mesh.color_attributes.active_color = col
    mesh.color_attributes.render_color_index = mesh.color_attributes.active_color_index
    scene.render.engine = engine
    print(f"ROCK AO baked: mean {sum(lo) / max(1, len(lo)):.2f}, min {min(lo):.2f}")


def add_hooks(root):
    parts.add_empty("spawn_point", root, SPAWN_POS, rot_z=math.pi, size=6)
    expect = [(-24.24, -33.91, 13.67), (24.24, -32.91, 11.17), (-25.24, 40.41, 12.17),
              (25.24, 38.91, 10.17)]
    guns = []
    for i, site in enumerate(PDCS):
        pos = pdc_matrix(site) @ (PDC_TIP * PDC_S)
        e = parts.add_empty(f"den_gun_{i + 1}", root, tuple(pos), size=1.5)
        e.rotation_euler = (PDC_EL, 0.0, math.radians(site[3]) - math.pi / 2)
        print(f"HOOK den_gun_{i + 1} pos ({pos.x:.2f}, {pos.y:.2f}, {pos.z:.2f}) "
              f"rot_z {math.degrees(e.rotation_euler.z):.1f} deg")
        assert (pos - V(expect[i])).length < 0.05, (i, pos)
        guns.append(pos)
    return guns


def checks(guns, hull, total):
    ok = True
    for i, g in enumerate(guns):
        above = surf.top(g.x, g.y, default=-99.0)
        loc, _, _, dist = surf.bvh.find_nearest(g)
        print(f"CHECK den_gun_{i + 1} rock top below {above:.2f} < {g.z:.2f}, "
              f"nearest rock {dist:.2f} m")
        ok &= above < g.z and dist > 1.0
    sp = V(SPAWN_POS)
    rock_hit = surf.bvh.ray_cast(sp, V((0, -1, 0)), 3.0)[0]
    dg = bpy.context.evaluated_depsgraph_get()
    hb = BVHTree.FromObject(hull, dg)
    hull_hit = hb.ray_cast(sp, V((0, -1, 0)), 6.0)[0]
    side = [hb.ray_cast(sp, V((s, 0, 0)), 20.0)[0] for s in (-1, 1)]
    print(f"CHECK spawn between rails {abs(sp.x) < RAIL_X}, rock ahead {rock_hit}, "
          f"hull ahead {hull_hit}, collar sides {[round(h.x, 2) if h else None for h in side]}")
    ok &= abs(sp.x) < RAIL_X and rock_hit is None and hull_hit is None
    print(f"CHECK tris {total} in 30k..45k: {30000 <= total <= 45000}")
    ok &= 30000 <= total <= 45000
    assert ok, "nest checks failed"


def game_ambient(strength=0.25):
    """Fill light like the game's sky ambient (system.tscn: colour (0.46, 0.5, 0.6), energy
    1.1), seen by the lighting only; the camera still sees the dark preview background.
    Without it the deep slot renders black, which it never is in game."""
    nt = bpy.context.scene.world.node_tree
    bg = nt.nodes.get("Background")
    out = nt.nodes.get("World Output")
    amb = nt.nodes.new("ShaderNodeBackground")
    amb.inputs["Color"].default_value = (0.46, 0.5, 0.6, 1.0)
    amb.inputs["Strength"].default_value = strength
    lp = nt.nodes.new("ShaderNodeLightPath")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
    nt.links.new(amb.outputs[0], mix.inputs[1])
    nt.links.new(bg.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])


def previews(target, ortho, top_ortho, cam_off):
    """wk.previews with the game ambient fill: 3/4 view and top-down into blender/previews."""
    tx, ty, tz = target
    common.setup_preview(cam_loc=(tx + cam_off[0], ty + cam_off[1], tz + cam_off[2]),
                         cam_target=target, ortho_scale=ortho, res=(1600, 1200),
                         key_dir=(-0.6, -0.35, 0.7), key_energy=3.5)
    game_ambient()
    common.render(os.path.join(common.PREVIEW_DIR, f"{PRE}_preview.png"))
    scene = bpy.context.scene
    cam = scene.camera
    cam.location = (tx, ty, 200)
    cam.rotation_euler = (0, 0, 0)
    cam.data.ortho_scale = top_ortho
    scene.render.resolution_x, scene.render.resolution_y = 1200, 1200
    common.render(os.path.join(common.PREVIEW_DIR, f"{PRE}_top.png"))


def extra_views(out_dir):
    """Close-ups and an RTS camera view (45 deg, 400 m, fov 50) with a 15 m ship."""
    os.makedirs(out_dir, exist_ok=True)
    scene = bpy.context.scene
    cam = scene.camera
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1200
    for name, loc, tgt, ortho in (("mouth", (-30, -85, 25), (0, -48, 0), 40.0),
                                  ("sleds", (-25, -8, 30), (0, 12, 1), 30.0),
                                  ("stern", (35, 60, 35), (0, 38, 4), 40.0),
                                  ("hab", (-60, -20, 40), (-22, 4, 10), 40.0),
                                  ("east", (60, -30, 40), (20, 2, 6), 45.0)):
        cam.location = loc
        cam.rotation_euler = (V(tgt) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        cam.data.ortho_scale = ortho
        common.render(os.path.join(out_dir, f"corsair_nest_{name}.png"))
    # 15 m ship for scale in front of the mouth
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(common.ROOT, "assets", "models", "ships",
                                                    "merc_interceptor.glb"))
    new = [o for o in bpy.data.objects if o not in before]
    tops = [o for o in new if o.parent is None]
    bpy.context.view_layer.update()
    ys = [(o.matrix_world @ V(c)).y for o in new if o.type == "MESH" for c in o.bound_box]
    k = 15.0 / max(1e-3, max(ys) - min(ys))
    for o in tops:
        o.scale = (k, k, k)
        o.location = (14.0, -78.0, 2.0)
        o.rotation_euler = (0, 0, math.pi)
    cam.data.type = "PERSP"
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle = math.radians(50)
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    tgt = V((0, -10, 0))
    for name, dist, yaw in (("rts400", 400.0, 20.0), ("rts300", 300.0, -15.0),
                            ("rts600", 600.0, 0.0)):
        y = math.radians(yaw)
        off = V((math.sin(y), -math.cos(y), 0)) * dist * math.cos(math.radians(45))
        cam.location = tgt + off + V((0, 0, dist * math.sin(math.radians(45))))
        cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
        common.render(os.path.join(out_dir, f"corsair_nest_{name}.png"))


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, rock, hull, sal, glow, lights, pdcs = build_nest()
    bpy.context.view_layer.update()
    if "--no-ao" not in argv:
        bake_rock_ao(rock)
    atlas = [hull, sal] + pdcs
    if "--no-textures" not in argv:
        glow.hide_render = lights.hide_render = True
        wk.texture(atlas, MATS, PRE, [(0.0, CATCH_Y)], scorch=SCORCH, decals=DECALS,
                   labels=LABELS, seed0=71)
        glow.hide_render = lights.hide_render = False
    else:
        for o in atlas:
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    guns = add_hooks(root)
    total = wk.stats([rock, hull, sal, glow, lights] + pdcs)
    checks(guns, hull, total)
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        previews((0.0, -3.0, 0.0), 135, 124, cam_off=(-85, -140, 140))
    extra = [a for a in argv if a.startswith("--extra")]
    if extra:
        out_dir = extra[0].split("=", 1)[1] if "=" in extra[0] else tempfile.gettempdir()
        if "--no-preview" in argv:
            common.setup_preview(cam_loc=(-85, -143, 140), cam_target=(0, -3, 0), ortho_scale=135,
                                 res=(1600, 1200), key_dir=(-0.6, -0.35, 0.7), key_energy=3.5)
            game_ambient()
        extra_views(out_dir)


main()
