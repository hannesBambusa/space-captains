"""Generate the Syndicate Keep (armoured launch bastion S-07) .glb and previews.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_syndicate_fortress.py
  Options after `--`: --no-preview, --no-textures (flat colours, fast shape iteration),
  --rts=<png> (an extra RTS-camera render, 45 deg from ~400 m, with a gunship for scale).
Textures: one 2048 worn-industrial atlas (worn_kit / station_textures bake), saved as
blender/textures/syndicate_fortress_{albedo,mr,normal}.jpg plus the stencil sheet
syndicate_fortress_decals.png. Lamps, windows and glows stay flat emissive materials.
The model carries the Syndicate violet itself; Godot does not tint it.

Design: the Syndicate pays for its fortress, so it has no rock to hide in. A free-standing
military bastion built to a shipyard drawing, laid out to launch and protect the slow,
heavy gunships. Mirror-symmetric arrowhead pointing out of the hangar mouth (Blender -Y):
  gatehouse   armoured tip with the 24 x 12 m launch tube (mag rails, ribs, blast-door
              slots, violet-lit throat), a sloped glacis on the roof, a hazard-edged apron
              and the hull number S-07 on the front face and the roof.
  spine       the hangar keep behind it (gunship racks), stand-off side armour, violet roof
              bars and a violet double chevron aimed at the mouth, a squat CIC tower with an
              armoured visor and a lattice sensor mast with a violet strobe.
  wings       two casemate wings swept back at 45 deg (magazines, torpedo VLS cells,
              barracks) with spaced plates on sloped glacis faces, ending in octagonal gun
              bastions with heavy twin turrets.
  reactor     an octagonal shielded fusion drum behind the spine with a violet band and the
              cartel emblem, two radiator wings in the play plane (edge-on to fire: coolant
              manifolds down a truss with 18 separate blades each), two
              aft gun sponsons and a dorsal turret on its crown.
  support     propellant tanks between wing and spine piped into the hangar, four shield
              emitter pylons (capacitors, insulator stack, emitter head), a supply dock with
              cargo pods on +X and a long-range comms dish on -X, Expanse-style PDC ball
              mounts and RCS quads.
Gunmetal roofs, charcoal walls, blued armour plate, crisp violet bands, hazard yellow and
amber windows (the gunships' colours).

Layout (Blender Z up, exported +Y up; Blender -Y = Godot +Z). Spine centre near the origin,
play plane z = 0.
  gatehouse   x -22..22, y -54..-16, z -14..14, glacis to z 16.5; collar y -57..-54;
              apron y -66..-57, top z -5.7; tube x -12..12, z -6..6
  spine       x -18..18, y -16..30, z -11..11; CIC tower y 0.5..17 to z 23.5, mast to z 43
  wings       from (+-20, -42) to the bastions at (+-62, 0); wing top z 7, bastion deck z 9
  reactor     centre (0, 44), apothem 14.3, z -12..10.5; radiator blades x 21.7..71.1 each
              side, y 34.2..53.8; aft sponsons at (+-22, 62)
  overall     about 151 x 142 x 63 m (x -75.5..75.5, y -66..76, z -19.7..43.3)
Hierarchy: syndicate_fortress (empty root)
  -> den_rock (the armoured structure; stays as the burnt ruin), den_salvage (turrets,
     radiator panels, tanks, pylons, mast, dock, comms, PDCs, RCS, tube fittings; hidden
     when destroyed), den_windows (steady windows), den_lights (small nav and warning
     blobs only, flickered), den_hangar_glow (tube glow "syndicate_fortress_hangar_glow"
     plus the shield emitter rings and lenses, pulsed), spawn_point and den_gun_1..6
     (empties).
  spawn_point (0, -61, 0), rotated 180 deg about up: its Godot -Z points out of the mouth.
  den_gun_N   at the muzzle-brake tips of the six heavy twin turrets (yaw = barrel heading):
              1 / 2 right / left bastion, 3 / 4 right / left aft sponson, 5 dorsal over the
              gatehouse (forward), 6 on the reactor crown (aft).
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
import parts  # noqa: E402
import station_textures as st  # noqa: E402
import worn_kit as wk  # noqa: E402

V = Vector
PRE = "syndicate_fortress"
OUT = os.path.join(common.ROOT, "assets", "models", "buildings", "syndicate_fortress.glb")
BLEND = os.path.join(common.ROOT, "blender", "syndicate_fortress.blend")
GUNSHIP_GLB = os.path.join(common.ROOT, "assets", "models", "ships", "syndicate_gunship.glb")
RNG = random.Random(7719)
SPAWN_POS = (0.0, -61.0, 0.0)
RC = V((0.0, 44.0, 0.0))                 # reactor drum centre
TUBE_RIBS = (-50, -44, -38, -32, -26, -20)
VIOLET_INK = (0.25, 0.1, 0.45)
LABELS = ["S-07", "#BAR", "#CHEV", "LAUNCH", "KEEP CLEAR", "AMMO", "B1", "B2", "REACTOR",
          "RAD A", "RAD B", "DOCK A", "PROPELLANT", "NO STEP", "CIC", "DANGER"]

# Worn kinds at station plate scale for the fortress (process-local overrides).
FORT_WORN = {
    # gunmetal blue-grey: every roof and deck, so the plan reads from above
    "hull": dict(big=(4.0, 3.0), plate=(2.0, 1.5),
                 tones=[(0.20, 0.212, 0.23), (0.19, 0.202, 0.22), (0.21, 0.222, 0.24),
                        (0.186, 0.198, 0.216), (0.205, 0.21, 0.222), (0.195, 0.208, 0.228)],
                 plate_var=0.07, rough=(0.5, 0.12), metal=0.2, seam_big=0.45,
                 seam_small=0.18, rivets=True, hatches=0.12, chip=(0.1, 0.1, 0.105),
                 chip_metal=0.85, chip_k=1.1, grime_k=0.9, streak_k=0.35, bleach=0.05),
    # charcoal: walls, spine sides, barbettes, towers
    "hull2": dict(big=(4.0, 2.5), plate=(1.0, 1.25),
                  tones=[(0.09, 0.095, 0.105), (0.08, 0.085, 0.095), (0.1, 0.105, 0.112),
                         (0.085, 0.088, 0.096), (0.095, 0.092, 0.09), (0.085, 0.09, 0.1)],
                  plate_var=0.08, rough=(0.55, 0.12), metal=0.1, seam_big=0.45,
                  seam_small=0.18, rivets=True, hatches=0.12, chip=(0.30, 0.30, 0.31),
                  chip_metal=0.9, chip_k=0.9, grime_k=0.9, streak_k=0.25, bleach=0.1),
    # work grey: tanks, cargo pods, dishes, insulators (kept below the deck brightness so
    # the kit does not outshine the armoured core from the RTS camera)
    "hull3": dict(big=(3.0, 3.0), plate=(1.5, 1.5),
                  tones=[(0.29, 0.29, 0.285), (0.275, 0.277, 0.272), (0.305, 0.303, 0.295),
                         (0.268, 0.27, 0.267), (0.297, 0.293, 0.283), (0.283, 0.285, 0.28)],
                  plate_var=0.035, rough=(0.58, 0.12), metal=0.0, seam_big=0.36,
                  seam_small=0.1, rivets=True, hatches=0.12, chip=(0.16, 0.165, 0.17),
                  chip_metal=0.75, chip_k=1.1, grime_k=1.1, streak_k=0.45, bleach=0.2),
    # gouged blued armour plate
    "armor": dict(big=(3.0, 2.0), plate=(1.5, 1.0),
                  tones=[(0.11, 0.115, 0.12), (0.1, 0.104, 0.11), (0.125, 0.128, 0.132),
                         (0.095, 0.098, 0.103), (0.118, 0.115, 0.112), (0.105, 0.11, 0.118)],
                  plate_var=0.1, rough=(0.45, 0.14), metal=0.7, seam_big=0.5,
                  seam_small=0.25, rivets=True, hatches=0.0, chip=(0.38, 0.38, 0.39),
                  chip_metal=1.0, chip_k=1.6, grime_k=0.8, streak_k=0.35, bleach=0.0),
    # Syndicate violet
    "accent": dict(big=(3.0, 2.0), plate=(1.5, 1.0),
                   tones=[(0.25, 0.10, 0.45), (0.23, 0.09, 0.42), (0.27, 0.11, 0.48),
                          (0.21, 0.085, 0.39), (0.26, 0.105, 0.46), (0.24, 0.095, 0.43)],
                   plate_var=0.06, rough=(0.5, 0.1), metal=0.05, seam_big=0.4,
                   seam_small=0.15, rivets=False, hatches=0.0, chip=(0.1, 0.1, 0.105),
                   chip_metal=0.8, chip_k=1.2, grime_k=1.0, streak_k=0.35, bleach=0.15),
    # radiator blades: darker than the station's white panels, ribbed along the flow
    "radiator": dict(big=(6.0, 0.6), plate=(6.0, 0.3),
                     tones=[(0.27, 0.272, 0.275), (0.25, 0.252, 0.256), (0.29, 0.29, 0.292),
                            (0.245, 0.247, 0.25), (0.265, 0.265, 0.268), (0.258, 0.26, 0.263)],
                     plate_var=0.03, rough=(0.5, 0.08), metal=0.25, seam_big=0.35,
                     seam_small=0.25, rivets=False, hatches=0.0, chip=(0.16, 0.16, 0.17),
                     chip_metal=0.9, chip_k=0.4, grime_k=0.8, streak_k=0.35, bleach=0.1,
                     fins=True),
}
st.WORN_KINDS.update(FORT_WORN)

MATS = {}
DECALS = []
SCORCH = []
R = S = W = L = G = None
I4 = Matrix.Identity(4)
Z = V((0, 0, 1))


class FortPart(parts.PanelPart):
    """PanelPart with hard armour shading. Slabs, lofts and hulls are flat shaded (no
    smoothing across shallow armour facets, which also kept the bake's edge mask from
    speckling whole faces), and any face no helper projected gets a face-local planar
    projection in metres (no stretch on faces sloped in plan, like the wing glacis)."""

    def __init__(self, name, mats):
        super().__init__(name, mats)
        self.hard = []

    def _mark(self, before):
        self.hard += [f for f in self.bm.faces if f not in before]

    def slab(self, pts, z0, z1, mat, matrix=None):
        before = set(self.bm.faces)
        super().slab(pts, z0, z1, mat, matrix)
        self._mark(before)

    def loft(self, rings, mat, cap=True, mat_fn=None):
        before = set(self.bm.faces)
        super().loft(rings, mat, cap, mat_fn)
        self._mark(before)

    def hull(self, points, mat):
        before = set(self.bm.faces)
        parts.part_hull(self, points, mat)
        self._mark(before)

    def finish(self, parent, sharp_deg=32):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        off = V((17 * 64.0, 23 * 64.0))
        for f in bm.faces:
            if all(lp[self.uv].uv.length < 1e-6 for lp in f.loops):
                f.normal_update()
                n = f.normal
                u = Z.cross(n)
                u = u.normalized() if u.length > 1e-3 else V((1, 0, 0))
                v = n.cross(u).normalized()
                for lp in f.loops:
                    q = lp.vert.co
                    lp[self.uv].uv = (q.dot(u) + off.x, q.dot(v) + off.y)
        hard = {f for f in self.hard if f.is_valid}
        for f in bm.faces:
            f.smooth = f not in hard
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        for m in self.slots:
            mesh.materials.append(m)
        mesh.set_sharp_from_angle(angle=math.radians(sharp_deg))
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj.parent = parent
        return obj


# ---------------------------------------------------------------- materials
def build_materials():
    m = common.make_material
    wk.build_materials(PRE, MATS)
    base = {"hull": ((0.2, 0.212, 0.23), 0.2), "hull2": ((0.085, 0.09, 0.1), 0.0),
            "hull3": ((0.29, 0.29, 0.285), 0.0), "accent": ((0.25, 0.1, 0.45), 0.0)}
    for k, (col, met) in base.items():
        bsdf = MATS[k].node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*col, 1.0)
        bsdf.inputs["Metallic"].default_value = met
    MATS["armor"] = m(f"{PRE}_armor", (0.11, 0.115, 0.12), roughness=0.45, metallic=0.7)
    glow = (0.03, 0.028, 0.025)
    flat = {
        "light": (f"{PRE}_light_amber", (1.0, 0.55, 0.18), 9.0),
        "red": (f"{PRE}_light_red", (1.0, 0.08, 0.03), 10.0),
        "green": (f"{PRE}_light_green", (0.15, 1.0, 0.3), 9.0),
        "violet": (f"{PRE}_light_violet", (0.62, 0.4, 1.0), 11.0),
        "white": (f"{PRE}_light_white", (0.85, 0.9, 1.0), 9.0),
        "window": (f"{PRE}_window_warm", (1.0, 0.6, 0.28), 3.5),
        "window_cool": (f"{PRE}_window_cool", (0.7, 0.82, 1.0), 2.5),
        "window_dim": (f"{PRE}_window_amber", (1.0, 0.5, 0.18), 2.0),
        "shield": (f"{PRE}_shield_violet", (0.7, 0.5, 1.0), 10.0),
    }
    for k, (name, col, s) in flat.items():
        MATS[k] = m(name, glow, roughness=0.3, emission=col, emission_strength=s)
    MATS["glow"] = m(f"{PRE}_hangar_glow", (0.05, 0.03, 0.08), roughness=0.3,
                     emission=(0.65, 0.45, 1.0), emission_strength=12.0)
    for k in list(flat) + ["glow", "glass"]:
        MATS[k].use_backface_culling = False


# ---------------------------------------------------------------- helpers
def octagon(r, x=0.0, y=0.0):
    """Octagon with vertices at 22.5 + 45k deg (face normals at 0, 45, 90.. deg)."""
    return [(x + r * math.cos(math.radians(22.5 + 45 * k)),
             y + r * math.sin(math.radians(22.5 + 45 * k))) for k in range(8)]


def polar(r, a, z=0.0):
    return V((r * math.cos(a), r * math.sin(a), z))


def radial(a):
    return V((math.cos(a), math.sin(a), 0))


def lamp(pos, s=0.8, mat="violet"):
    L.box(V(pos), (s, s, s * 0.6), mat, bevel=0.0)


def label(text, centre, normal, up, h, colour=wk.INK_LIGHT, opacity=0.85):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity))


def girder(p, a, b, w, h, n, mat="dark", chord=0.45, brace=0.25):
    """Open box girder from a to b (w across, h up), n bays of X-braced frames."""
    a, b = V(a), V(b)
    x = (b - a).normalized()
    side = x.cross(Z).normalized()
    up = side.cross(x).normalized()
    cs = [side * sx * w / 2 + up * sz * h / 2 for sx in (-1, 1) for sz in (-1, 1)]
    for c in cs:
        parts.strut(p, a + c, b + c, chord, chord, mat)
    for k in range(n):
        p0 = a.lerp(b, k / n)
        p1 = a.lerp(b, (k + 1) / n)
        for sz in (-1, 1):
            parts.strut(p, p0 + side * w / 2 + up * sz * h / 2, p1 - side * w / 2 + up * sz * h / 2,
                        brace, brace, mat)
        for sx in (-1, 1):
            parts.strut(p, p0 + side * sx * w / 2 - up * h / 2, p1 + side * sx * w / 2 + up * h / 2,
                        brace, brace, mat)
        parts.strut(p, p1 + side * w / 2 + up * h / 2, p1 - side * w / 2 + up * h / 2, brace,
                    brace, mat)


def chevron(apex_y, end_x, end_y, hw, z0, z1, mat="accent"):
    """Mitred chevron slab on a deck: apex (0, apex_y), arm ends (+-end_x, end_y), arm
    half width hw. Each arm is one convex quad that meets the other on the centreline."""
    d = V((end_x, end_y - apex_y)).normalized()
    p = V((-d.y, d.x)) * hw
    for sx in (-1, 1):
        e = V((sx * end_x, end_y))
        a, b = e + p * sx, e - p * sx            # outer end corners
        ka = -a.x / (sx * -d.x)                  # run each edge back to x = 0
        kb = -b.x / (sx * -d.x)
        ta = a + V((sx * -d.x, -d.y)) * ka
        tb = b + V((sx * -d.x, -d.y)) * kb
        R.slab([tuple(a), tuple(ta), tuple(tb), tuple(b)], z0, z1, mat)


def wing_frame(sx):
    d = V((sx * 0.7071, 0.7071, 0))
    n = V((sx * 0.7071, -0.7071, 0))
    c0 = V((sx * 20, -42, 0))

    def at(s, a, z):
        return c0 + d * s + n * a + Z * z
    return d, n, c0, at


# ---------------------------------------------------------------- spine
def build_spine():
    mf = {0: "hull2", 1: "armor", 2: "hull", 3: "armor", 4: "hull2", 5: "dark", 6: "hull2",
          7: "dark"}
    parts.prism(R, -16, 30, (36, 22, 6), (36, 22, 6), "hull2", mat_fn=lambda i, j: mf[j])
    R.box((0, 7, -12.2), (14, 46, 2.4), "dark")
    for sx in (-1, 1):
        for y in (-10, -2, 6, 14):
            R.box((sx * 18.7, y, 0), (0.6, 7, 9), "armor", bevel=0.04)
        R.box((sx * 11.2, 7, 11.05), (1.4, 40, 0.1), "accent", bevel=0)
        S.box((sx * 6, -14, 11.2), (3, 3, 0.4), "metal")
        S.box((sx * 6, 24, 11.2), (3, 3, 0.4), "metal")
    chevron(-11, 8, -3, 1.0, 11.0, 11.12)      # double chevron aimed at the mouth
    chevron(-6, 7, 1, 1.0, 11.0, 11.12)
    label("NO STEP", (0, 27.5, 11.02), (0, 0, 1), (0, 1, 0), 1.0)


# ---------------------------------------------------------------- gatehouse + tube
def build_gatehouse():
    R.box((0, -35, 10), (44, 38, 8), "hull", bevel=0.03)
    R.box((0, -35, -10), (44, 38, 8), "hull2", bevel=0.03)
    for sx in (-1, 1):
        R.box((sx * 17, -35, 0), (10, 38, 12), "hull2", bevel=0.03)
    R.hull([(-22, -54, 14), (22, -54, 14), (-22, -44, 16.5), (22, -44, 16.5),
                        (-22, -44, 14), (22, -44, 14)], "armor")
    # mouth collar
    R.box((0, -55.5, 8.5), (32, 3, 5), "armor")
    R.box((0, -55.5, -8.5), (32, 3, 5), "armor")
    for sx in (-1, 1):
        R.box((sx * 14.5, -55.5, 0), (5, 3, 12), "armor")
    for zc in (9, -9):
        R.hazard(-16, 16, 2.0, 0, 0.08, matrix=Matrix.Translation((0, -57, zc)) @ parts.FRONT,
                 cols=("hazard", "dark"), pitch=2.0)
    # apron
    R.box((0, -61.5, -6.3), (32, 9, 1.2), "pad", bevel=0)
    R.hazard(-16, 16, 0.9, 0, 0.06, matrix=Matrix.Translation((0, -65.4, -5.7)),
             cols=("hazard", "dark"), pitch=1.6)
    for sx in (-1, 1):
        R.box((sx * 20.6, -30, 14.05), (1.6, 26, 0.1), "accent", bevel=0)
    R.box((-15, -40, 16), (8, 6, 4), "hull2")       # flight-control booth (port)
    # tube fittings (salvage)
    S.box((0, -36.5, -5.85), (24, 41, 0.3), "pad", bevel=0)
    for sx in (-1, 1):
        S.box((sx * 11.8, -35, 0), (0.4, 36, 12), "dark", bevel=0)
        S.box((sx * 4, -41, -5.45), (0.8, 50, 0.5), "metal", bevel=0)
        S.box((sx * 12.5, -52.5, 0), (1.2, 1.6, 12.4), "hazard", bevel=0)
        S.box((sx * 3.5, -30, -4.2), (0.8, 3, 3), "dark")
        label("DANGER", (sx * 11.58, -47, 2), (-sx, 0, 0), (0, 0, 1), 1.2)
    S.box((0, -35, 5.8), (24, 36, 0.4), "dark", bevel=0)
    for y in TUBE_RIBS:
        for sx in (-1, 1):
            S.box((sx * 11.4, y, 0), (0.6, 0.8, 12), "metal", bevel=0)
        S.box((0, y, 5.6), (23, 0.8, 0.6), "metal", bevel=0)
    S.box((0, -16.3, 0), (20, 0.6, 10), "dark", bevel=0)
    S.box((0, -30, -2.9), (8, 1.2, 0.5), "dark")
    # stencils
    label("S-07", (0, -54.02, 12.6), (0, -1, 0), (0, 0, 1), 2.2)
    label("S-07", (0, -22.0, 14.01), (0, 0, 1), (0, 1, 0), 4.4)
    label("LAUNCH", (0, -60.2, -5.68), (0, 0, 1), (0, 1, 0), 1.6)
    label("KEEP CLEAR", (0, -63.3, -5.68), (0, 0, 1), (0, 1, 0), 1.0)


def build_glow():
    for y in TUBE_RIBS:
        G.box((0, y, 5.25), (16, 0.3, 0.12), "glow", bevel=0)
    for sx in (-1, 1):
        G.box((sx * 7, -36, -5.66), (0.25, 36, 0.08), "glow", bevel=0)
        G.box((sx * 8, -16.7, 0), (0.35, 0.12, 8), "glow", bevel=0)
        G.box((sx * 11.75, -56.9, 0), (0.3, 0.12, 11.5), "glow", bevel=0)
    for zz in (4, -4):
        G.box((0, -16.7, zz), (16, 0.12, 0.35), "glow", bevel=0)
    G.box((0, -16.7, 0), (0.25, 0.12, 8), "glow", bevel=0)
    G.box((0, -56.9, 5.75), (23.5, 0.12, 0.3), "glow", bevel=0)


# ---------------------------------------------------------------- wings
SEC_W = [(-8, -6), (8, -6), (8, 1), (3.5, 7), (-5, 7), (-8, 3)]


def build_wings():
    for sx in (-1, 1):
        d, n, c0, at = wing_frame(sx)
        c1 = c0 + d * 53.74
        R.loft([[c + n * a + Z * z for a, z in SEC_W] for c in (c0, c1)], "hull2",
               mat_fn=lambda i, j: ("dark", "hull2", "armor", "hull", "hull2", "hull2")[j])
        R.hull([(sx * 22, -44, -6), (sx * 22, -51.32, -6), (sx * 25.66, -47.66, -6),
                            (sx * 22, -44, 7), (sx * 25.66, -47.66, 1), (sx * 22, -51.32, 1)],
                        "hull2")
        t = n * (-0.6) + Z * 0.8
        g = n * 0.8 + Z * 0.6
        rg = Matrix((sx * d, t, g)).transposed().to_4x4()
        for s in (12, 19, 26, 33, 40):
            R.box(at(s, 6.39, 4.48), (6.2, 6.6, 0.6), "armor", r=rg, bevel=0.04)
            for k in (-2, 2):
                R.box(at(s + k, 5.75, 4.0) + g * 0.35, (1, 1, 0.8), "dark", r=rg, bevel=0)
        rz = math.atan2(d.y, d.x)
        R.box(at(28, -0.6, 7.05), (40, 1.6, 0.1), "accent", rot_z=rz, bevel=0)
        for k in (-4, 4):
            R.box(at(28, k, -6.6), (40, 1.2, 1.2), "dark", rot_z=rz, bevel=0)
        S.box(at(28, 2, 7.9), (40, 1.6, 1.8), "hull2", rot_z=rz)
        S.box(at(21, -3.4, 7.6), (8, 2.6, 1.2), "dark", rot_z=rz)
        for i in range(4):
            for k in (-0.65, 0.65):
                S.box(at(17.9 + 2.05 * i, -3.4 + k, 8.27), (1.5, 1.1, 0.14), "metal", rot_z=rz,
                      bevel=0)
        for s in (12, 16.5, 21, 25.5, 30, 34.5, 39, 43.5):
            parts.window(W, at(s, 8.02, -0.5), n, Z, 1.8, 0.4, parts.pick_lit(RNG, "hab"))
        for s in (14, 30, 44):
            lamp(at(s, -4.4, 7.25), 0.7, "light")
        label("#CHEV", at(38, -3.0, 7.02), (0, 0, 1), n, 2.2)
        label("AMMO", at(13, -3.0, 7.02), (0, 0, 1), n, 1.0)
        label("B1" if sx > 0 else "B2", at(29, 8.02, -3.5), n, (0, 0, 1), 3.0)
        pdc(at(18, 8, -4.5), n)
        pdc(at(40, 8, -4.5), n)
        R.box(at(27, 8.15, -1.7), (46, 0.3, 0.4), "dark", rot_z=rz, bevel=0)   # rub rail


# ---------------------------------------------------------------- turrets
def heavy_turret(pos, yaw, s, name):
    """Heavy twin turret in den_salvage. Local frame: slewing ring at z 0, barrels +Y.
    Adds the den_gun empty later; returns (name, muzzle world pos, yaw)."""
    M = Matrix.Translation(V(pos)) @ Matrix.Rotation(yaw, 4, "Z")
    Rm = Matrix.Rotation(yaw, 4, "Z")

    def tbox(c, size, mat, r_local=None, bevel=0.06):
        S.box(M @ (V(c) * s), V(size) * s, mat, r=Rm @ (r_local or I4), bevel=bevel)

    def tcyl(c, r1, r2, dd, mat, segs, q=None):
        S.cyl(M @ (V(c) * s), r1 * s, r2 * s, dd * s, mat, segs=segs,
              axis_rot=Rm @ q if q is not None else Rm)

    def tslab(pts, z0, z1, mat, m_local):
        S.slab(pts, z0, z1, mat, matrix=M @ Matrix.Scale(s, 4) @ m_local)

    tcyl((0, 0, 0.5), 5.6, 5.6, 1.0, "dark", 20)
    tcyl((0, 0, 1.1), 5.0, 5.0, 0.2, "accent", 20)
    tslab([(-5, 1), (3.6, 1), (5, 2.6), (3.8, 5.4), (-3.6, 5.4), (-5, 3.6)][::-1], -3.8, 3.8,
          "hull", parts.SIDE)
    cheek = [(-4.2, 1.6), (3.2, 1.6), (4.2, 2.7), (3.2, 4.8), (-3.4, 4.8)][::-1]
    tslab(cheek, 3.8, 4.05, "accent", parts.SIDE)
    tslab(cheek, -4.05, -3.8, "accent", parts.SIDE)
    tbox((0, -0.4, 5.55), (6.4, 6, 0.3), "armor")
    tbox((0, 4.6, 3.0), (5.2, 1.6, 3.0), "armor", bevel=0.08)
    tbox((0, -5.6, 2.4), (3.2, 1.6, 2.4), "hull2")
    tbox((0, 1, 6.3), (1.6, 1.2, 1.4), "hull2")
    for k in (-3.95, 3.95):
        tbox((k, -2, 3.6), (0.3, 2.4, 1.0), "dark")
    el = math.radians(6)
    f = V((0, math.cos(el), math.sin(el)))
    q = f.to_track_quat("Z", "Y").to_matrix().to_4x4()
    for x in (-1.25, 1.25):
        root = V((x, 5.2, 3.0))
        tcyl(root + f * 1.6, 0.85, 0.85, 3.2, "metal", 16, q)
        tcyl(root + f * 8, 0.5, 0.42, 11, "dark", 16, q)
        tcyl(root + f * 5, 0.6, 0.6, 0.5, "hazard", 16, q)
        tcyl(root + f * 9, 0.68, 0.68, 1.4, "metal", 16, q)
        tbox(root + f * 13.9, (1.3, 1.3, 1.0), "dark", r_local=q)
    L.box(M @ (V((0, 1.62, 6.3)) * s), V((0.9, 0.06, 0.5)) * s, "red", r=Rm, bevel=0)
    muzzle = V((0, 5.2, 3.0)) + f * 14.4
    return name, M @ (muzzle * s), yaw


def build_bastions():
    guns = []
    for sx in (1, -1):
        b = V((sx * 62, 0, 0))
        R.slab(octagon(13, b.x, b.y), -8, 8, "hull2")
        R.slab(octagon(12.2, b.x, b.y), 8, 9, "hull")
        R.slab(octagon(10, b.x, b.y), -10, -8, "dark")
        angs = (-90, -45, 0, 45) if sx > 0 else (-90, -135, 180, 135)
        for ad in angs:
            a = math.radians(ad)
            tang = V((-math.sin(a), math.cos(a), 0))
            R.box(b + radial(a) * 12.71, (0.6, 8.0, 12), "armor", rot_z=a, bevel=0.04)
            for k in (-2.5, 2.5):
                R.box(b + radial(a) * 12.2 + tang * k, (0.8, 1, 1), "dark", rot_z=a, bevel=0)
        R.cyl(b + V((0, 0, 9.06)), 8.0, 8.0, 0.12, "accent", segs=32)
        R.cyl(b + V((0, 0, 10)), 6.6, 6.2, 2.0, "hull2", segs=32)
        R.cyl(b + V((0, 0, 11.1)), 6.25, 6.25, 0.2, "hazard", segs=32)
        yaw = math.radians(-143.13 if sx > 0 else 143.13)
        guns.append(heavy_turret((sx * 62, 0, 11.2), yaw, 1.0,
                                 "den_gun_1" if sx > 0 else "den_gun_2"))
        for ad in (22.5, 112.5, 202.5, 292.5):
            lamp(b + polar(11.6, math.radians(ad), 9.3), 0.9, "violet")
        for ad in ((90, 135, 180) if sx > 0 else (90, 45, 0)):   # gun crew deck slits
            a = math.radians(ad)
            tang = V((-math.sin(a), math.cos(a), 0))
            for k in (-2.4, 0, 2.4):
                parts.window(W, b + radial(a) * 12.02 + tang * k + V((0, 0, 4.0)), radial(a), Z,
                             1.4, 0.5, parts.pick_lit(RNG, "hab"))
        parts.rcs_quad(S, (sx * 62, 0, -10.3), (0, 0, -1), "hull2", "dark", s=1.4)
    return guns


# ---------------------------------------------------------------- reactor + aft
def build_reactor():
    guns = []
    tr = Matrix.Translation(RC)
    R.lathe([(0, -12), (12, -12), (15.5, -8.5), (15.5, 6.5), (12.5, 9.5), (6.5, 10.5), (0, 10.5)],
            8, lambda i, j: ("dark", "armor", "hull2", "armor", "hull", "hull")[j], matrix=tr,
            start=math.pi / 8)
    R.lathe([(15.55, -1.5), (15.75, -1.5), (15.75, 1.5), (15.55, 1.5)], 8,
            lambda i, j: "accent", matrix=tr, start=math.pi / 8)
    for k in range(8):
        ad = 22.5 + 45 * k
        if ad in (247.5, 292.5):
            continue
        a = math.radians(ad)
        R.box(RC + polar(16.1, a, -1), (1.4, 1.4, 14.5), "metal", rot_z=a)
        lamp(RC + polar(12.4, a, 9.75), 0.8, "light")
    hexa = [(4.5 * math.cos(math.radians(60 * k)), 40 + 4.5 * math.sin(math.radians(60 * k)))
            for k in range(6)]
    R.slab(hexa, 10.1, 10.6, "accent")
    chev = [(-2.6, 38.4), (-1.6, 38.4), (0, 41), (0, 42.4)]
    R.slab(chev, 10.6, 10.66, "dark")
    R.slab([(-x, y) for x, y in chev][::-1], 10.6, 10.66, "dark")
    for sx in (-1, 1):
        for dy in (-5, 0, 5):
            parts.pipe(R, (sx * 14, 44 + dy, -3), (sx * 19, 44 + dy, -3), 0.7, "metal", segs=8)
        label("REACTOR", (sx * 14.34, 44, 4.6), (sx, 0, 0), (0, 0, 1), 1.6)
        # aft sponson + barbette
        R.beam((sx * 8, 56, -1), (sx * 19, 61, -1), 5, 7, "hull2")
        R.slab(octagon(7, sx * 22, 62), -5, 5, "hull2")
        R.slab(octagon(6.4, sx * 22, 62), 5, 5.6, "hull")
        R.slab(octagon(5, sx * 22, 62), -7, -5, "dark")
        R.cyl(V((sx * 22, 62, 6.4)), 5.4, 5.1, 1.6, "hull2", segs=28)
        R.cyl(V((sx * 22, 62, 7.3)), 5.15, 5.15, 0.2, "hazard", segs=28)
        yaw = math.radians(-36.87 if sx > 0 else 36.87)
        guns.append(heavy_turret((sx * 22, 62, 7.4), yaw, 0.85,
                                 "den_gun_3" if sx > 0 else "den_gun_4"))
        for ad in (-22.5, 22.5):
            a = math.radians(ad if sx > 0 else 180 - ad)
            lamp(V((sx * 22, 62, 5.85)) + polar(5.9, a), 0.8, "red")
        parts.rcs_quad(S, (sx * 22, 68.9, -2), (0, 1, 0), "hull2", "dark", s=1.4)
    # crown turret, aft
    R.cyl(V((0, 51, 10.8)), 4.6, 4.3, 2.4, "hull2", segs=28)
    R.cyl(V((0, 51, 12.1)), 4.35, 4.35, 0.2, "hazard", segs=28)
    guns.append(heavy_turret((0, 51, 12.2), 0.0, 0.75, "den_gun_6"))
    parts.rcs_quad(S, (0, 44, -12.5), (0, 0, -1), "hull2", "dark", s=1.4)
    return guns


def build_radiators():
    for sx in (-1, 1):
        girder(R, (sx * 14, 44, 0), (sx * 73, 44, 0), 3.0, 2.4, 9, "dark")
        R.box((sx * 20, 44, 0), (3, 14, 2.6), "hull2")
        R.box((sx * 74.25, 44, 0), (2.5, 3.5, 3), "hull2")
        # coolant loop: supply and return manifolds down both sides of the truss, with
        # separate radiator blades hung off them (gaps between blades, so the wing reads
        # as a heat-rejection comb, not a solar array)
        for sy in (-1, 1):
            parts.pipe(S, (sx * 21.5, 44 + sy * 2.1, 0), (sx * 72.5, 44 + sy * 2.1, 0), 0.55,
                       "metal", segs=8)
            for i in range(9):
                x = sx * (24.0 + 5.6 * i)
                yc = 44 + sy * 6.1
                S.box((x, yc, 0), (4.6, 7.0, 0.22), "radiator", bevel=0)
                for k in (-2.3, 2.3):
                    S.box((x + k, yc, 0), (0.28, 7.0, 0.5), "dark", bevel=0)
                S.box((x, 44 + sy * 9.75, 0), (4.9, 0.3, 0.5), "dark", bevel=0)
                S.box((x, 44 + sy * 2.6, 0), (1.6, 1.0, 0.8), "hull2", bevel=0)
        for y in (41.9, 46.1):
            S.box((sx * 72.8, y, 0), (0.9, 0.9, 1.6), "dark", bevel=0)
        lamp((sx * 74.25, 44, 1.9), 1.0, "red" if sx > 0 else "green")
        label("RAD A" if sx > 0 else "RAD B", (sx * 20, 46, 1.32), (0, 0, 1), (-sx, 0, 0), 1.2)


# ---------------------------------------------------------------- tower + mast
def build_tower():
    R.box((0, 9, 14), (16, 14, 6), "hull2", bevel=0.04)
    R.box((0, 10, 20), (20, 14, 6), "hull", bevel=0.04)
    R.hull([(-10, 3, 17), (10, 3, 17), (-10, 3, 23), (10, 3, 23), (-9, 0.5, 18),
                        (9, 0.5, 18), (-9, 0.5, 21.5), (9, 0.5, 21.5)], "armor")
    R.box((0, 11, 23.5), (16, 11, 1), "dark")
    for x in (-6, 0, 6):
        parts.window(W, (x, 0.47, 19.75), (0, -1, 0), Z, 5.0, 0.5, "window_cool")
    for sx in (-1, 1):
        for y in (5, 7.5, 10, 12.5, 15):
            parts.window(W, (sx * 10.02, y, 21), (sx, 0, 0), Z, 1.2, 0.5,
                         parts.pick_lit(RNG, "hab"))
        S.box((sx * 8.25, 9, 14), (0.4, 8, 4.5), "dark", r=Matrix.Rotation(sx * 0.25, 4, "Y"))
        S.cyl((sx * 4.8, 13, 37), 0.12, 0.05, 6, "metal", segs=5)
        lamp((sx * 5.2, 13, 34.3), 0.9, "red")
        for y in (5.8, 16.2):
            lamp((sx * 7.6, y, 24.2), 0.8, "red")
    wk.lattice_mast(S, (0, 13, 24), 42.0, 1.4, 0.6, 6, "dark", chord=0.4, brace=0.18)
    S.box((0, 13, 34), (10, 0.6, 0.6), "metal", bevel=0)
    parts.dish(S, V((-4.5, 13, 34)), 2.6, (-0.4, -0.4, 0.8), "hull3", "dark", depth=0.8, segs=14)
    lamp((0, 13, 42.9), 1.4, "violet")
    label("CIC", (0, 17.02, 20), (0, 1, 0), (0, 0, 1), 1.6)


# ---------------------------------------------------------------- tanks, pylons, dock
def build_tanks():
    for sx in (-1, 1):
        for x, y0, y1, r, z, cr_ys in ((sx * 25, -14, 18, 4.0, -1, (-8, 2, 12)),
                                       (sx * 34, -6, 18, 3.6, -2, (0, 6, 12))):
            parts.capsule(S, y0, y1, r, lambda i, j: "hull3", segs=24, x=x, z=z)
            for y in (y0 + 3, y1 - 3):
                S.cyl((x, y, z), r + 0.08, r + 0.08, 1.2, "accent", segs=24, axis_rot=parts.ALONG_Y)
            for y in cr_ys:
                S.box((x, y, z - r * 0.6), (2 * r + 1.2, 1.4, r + 1.0), "dark")
                S.beam((sx * 18, y, -4), (x, y, -4), 1.2, 1.2, "dark")
            label("PROPELLANT", (x, (y0 + y1) / 2, z + r + 0.01), (0, 0, 1), (-sx, 0, 0), 1.4,
                  wk.INK_DARK)
            label("#BAR", (x, y0 + 5, z + r + 0.01), (0, 0, 1), (0, 1, 0), 0.9, VIOLET_INK)
        # feed lines leave the aft dome tips (no gap) and run into the hangar side wall
        for x, y0, z, y1 in ((sx * 25, -14, -1, -26), (sx * 34, -6, -2, -28)):
            S.cyl((x, y0 - 0.3, z), 0.9, 0.9, 0.6, "dark", segs=10, axis_rot=parts.ALONG_Y)
            parts.pipe(S, (x, y0 - 0.2, z), (sx * 22, y1, z), 0.5, "metal")
            S.box((sx * 22.4, y1, z), (0.8, 1.6, 1.6), "dark")


def build_pylons():
    for sx in (-1, 1):
        for b in (V((sx * 16, -22, 14)), V((sx * 20, 39.6, 1.3))):
            S.box(b + V((0, 0, 0.8)), (5, 5, 1.6), "hull2")
            for ad in (90, 210, 330):
                a = math.radians(ad)
                S.cyl(b + polar(1.7, a, 3.35), 0.75, 0.75, 3.5, "metal", segs=10)
                S.cyl(b + polar(1.7, a, 5.25), 0.8, 0.8, 0.3, "accent", segs=10)
            S.cyl(b + V((0, 0, 4.6)), 0.5, 0.5, 6, "metal", segs=8)
            for k in range(6):
                S.cyl(b + V((0, 0, 1.8 + 0.6 * k)), 1.3, 1.3, 0.35, "dark" if k % 2 else "hull3",
                      segs=12)
            S.sphere(b + V((0, 0, 8.6)), 1.6, "metal", segs=12, rings=6)
            G.torus(b + V((0, 0, 8.6)), 1.65, 0.22, "shield", segs=16, minor_segs=4)
            G.cyl(b + V((0, 0, 10.25)), 0.6, 0.6, 0.25, "shield", segs=10)
            lamp(b + V((2.2, 2.2, 1.75)), 0.6, "red")


def build_dock_comms():
    girder(S, (18, 24, -1), (46, 24, -1), 3.0, 2.6, 5, "dark")
    S.tube((18, 24, -1), (46, 24, -1), 1.4, 1.4, "hull2", segs=10)
    S.box((32, 24, 0.55), (26, 2.4, 0.3), "pad", bevel=0)
    S.cyl((47, 24, -1), 3, 3, 2, "hull2", segs=14, axis_rot=parts.ALONG_X)
    S.cyl((48.1, 24, -1), 2.4, 2.4, 0.3, "dark", segs=14, axis_rot=parts.ALONG_X)
    S.cyl((45.8, 24, -1), 3.1, 3.1, 0.5, "accent", segs=14, axis_rot=parts.ALONG_X)
    for x in (26, 31, 36, 41):
        wk.cargo_pod(S, (x, 29.5, -1), (4.2, 8, 4), 0, body="hull3", band="accent")
    for dz in (3.2, -3.2):
        lamp((48.4, 24, -1 + dz), 0.9, "green")
    for x in (22, 28, 36, 42):
        lamp((x, 25, 0.85), 0.6, "light")
    label("DOCK A", (32, 24, 0.72), (0, 0, 1), (0, 1, 0), 1.2)
    # comms array, port side
    S.beam((-18, 24, 0), (-36, 24, 0), 3, 3, "hull2")
    S.cyl((-38, 24, 2), 1.5, 1.5, 8, "hull2", segs=10)
    S.box((-38, 24, -3), (6, 5, 3), "hull2")
    parts.dish(S, V((-38, 24, 8)), 6.0, (-0.5, 0.2, 0.85), "hull3", "dark", depth=1.8, segs=18)


# ---------------------------------------------------------------- PDC, RCS
def pdc(base, out):
    base, out = V(base), V(out).normalized()
    q = out.to_track_quat("Z", "Y").to_matrix().to_4x4()
    side = out.cross(Z)
    side = side.normalized() if side.length > 1e-3 else V((1, 0, 0))
    S.cyl(base + out * 0.4, 1.5, 1.5, 0.8, "hull2", segs=10, axis_rot=q)
    S.sphere(base + out * 1.3, 1.15, "hull", segs=10, rings=6)
    S.cyl(base + out * 2.9, 0.42, 0.42, 1.2, "dark", segs=8, axis_rot=q)
    S.cyl(base + out * 4.6, 0.28, 0.28, 3.0, "metal", segs=6, axis_rot=q)
    S.cyl(base + out * 6.1, 0.34, 0.34, 0.3, "dark", segs=8, axis_rot=q)
    S.box(base + side * 1.8 + out * 0.5, (1.4, 1, 1), "hull2")


def build_pdc_rcs():
    for sx in (-1, 1):
        pdc((sx * 20, -54, -11.5), (sx * 0.45, -0.75, -0.48))
        parts.rcs_quad(S, (sx * 22.3, -52, 9), (sx, 0, 0), "hull2", "dark", s=1.4)
    pdc((0, 12, -13.4), (0, 0, -1))


# ---------------------------------------------------------------- lights + windows
def build_lights_windows():
    for sx in (-1, 1):
        for sz in (-1, 1):
            lamp((sx * 15.5, -57.35, sz * 10.4), 1.0, "light")
        for y in (-58, -60.5, -63, -65.5):
            lamp((sx * 14.5, y, -5.4), 0.8, "violet")
        for y in (-58.5, -61, -63.5):
            lamp((sx * 6, y, -5.45), 0.6, "white")
        for y in (-53.5, -17):
            lamp((sx * 21.5, y, 14.4), 0.8, "violet")
        for z in (-8, -4, 0, 4, 8):
            parts.window(W, (sx * 19.5, -54.04, z), (0, -1, 0), Z, 0.6, 1.6, "window_cool")
    for x in (-17, -15, -13):
        parts.window(W, (x, -43.04, 16.5), (0, -1, 0), Z, 1.6, 0.6, "window_cool")


# ---------------------------------------------------------------- assemble
def build_fortress():
    global R, S, W, L, G
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    R = FortPart("den_rock", MATS)
    S = FortPart("den_salvage", MATS)
    W = parts.PanelPart("den_windows", MATS)
    L = parts.PanelPart("den_lights", MATS)
    G = parts.PanelPart("den_hangar_glow", MATS)
    build_spine()
    build_gatehouse()
    build_wings()
    guns = build_bastions()
    guns += build_reactor()
    build_radiators()
    build_tower()
    build_tanks()
    build_pylons()
    build_dock_comms()
    R.cyl(V((0, -34, 15.5)), 5.2, 4.8, 3.0, "hull2", segs=28)
    R.cyl(V((0, -34, 17.1)), 4.85, 4.85, 0.2, "hazard", segs=28)
    guns.append(heavy_turret((0, -34, 17.2), math.pi, 0.75, "den_gun_5"))
    build_pdc_rcs()
    build_lights_windows()
    build_glow()
    SCORCH.extend([(0, -61.5, -5.7, 6.5), (0, -48, -5.7, 5.0)])
    for sx in (-1, 1):
        SCORCH.extend([(sx * 69.5, -9, 9.0, 3.5), (sx * 14, -57, 0, 2.0),
                       (sx * 18, -50, 15.5, 2.5), (sx * 27, 70, 5.6, 2.5)])
    root = parts.make_root(PRE, size=20)
    rock = R.finish(root)
    sal = S.finish(root)
    flat = [p.finish(root) for p in (W, L, G)]
    for o in flat:
        o.data.uv_layers.remove(o.data.uv_layers["panel"])
    guns.sort(key=lambda g: g[0])
    return root, rock, sal, flat, guns


def add_points(root, guns):
    parts.add_empty("spawn_point", root, SPAWN_POS, rot_z=math.pi, size=6)
    for name, pos, yaw in guns:
        parts.add_empty(name, root, pos, rot_z=yaw, size=2)
        print(f"HOOK {name} ({pos.x:.2f}, {pos.y:.2f}, {pos.z:.2f}) yaw "
              f"{math.degrees(yaw):.2f}")


def rts_view(path):
    """Scratch render: perspective RTS camera ~45 deg from ~400 m, a gunship for scale."""
    scene = bpy.context.scene
    if os.path.exists(GUNSHIP_GLB):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=GUNSHIP_GLB)
        for o in set(bpy.data.objects) - before:
            if o.parent is None:
                # imported +Y up -> Blender Z up; nose (Godot -Z) = Blender +Y; fly out of
                # the mouth toward -Y
                o.location = (8.0, -92.0, 0.0)
                o.rotation_mode = "XYZ"
                o.rotation_euler = (0, 0, math.pi)
    cam = scene.camera
    cam.data.type = "PERSP"
    cam.data.lens = 50
    tgt = V((0, -5, 0))
    loc = tgt + V((-150, -230, 290)).normalized() * 400
    cam.location = loc
    cam.rotation_euler = (tgt - loc).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1000
    common.render(path)


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, rock, sal, flat, guns = build_fortress()
    bpy.context.view_layer.update()
    if "--no-textures" not in argv:
        for o in flat:
            o.hide_render = True
        wk.texture([rock, sal], MATS, PRE, [(0.0, -61.5)], scorch=SCORCH, decals=DECALS,
                   labels=LABELS, seed0=77, res=2048, ao_far=6.0, edge_r=0.25)
        for o in flat:
            o.hide_render = False
    else:
        for o in (rock, sal):
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    add_points(root, guns)
    wk.stats([rock, sal] + flat)
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        wk.previews(PRE, (0, 4, 4), 205, 170, cam_off=(-130, -215, 225))
    rts = [a.split("=", 1)[1] for a in argv if a.startswith("--rts=")]
    if rts:
        rts_view(rts[0])


main()
