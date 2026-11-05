"""Generate the planet-outpost surface models (planet mode) .glb files and previews.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_surface.py
  Options after `--`: --only=<id>[,<id>] (default: all), --no-textures (flat colours, fast),
  --no-preview, --no-sheet.
Output: assets/models/surface/<id>.glb (scripts/surface/surface_models.gd loads them, its
_stand_in(id) is the size contract), blender/surface/<id>.blend, previews
blender/previews/surface_<id>.png and the contact sheet blender/previews/surface_sheet.png
(4 x 3 tiles in IDS order).
Textures: the station's worn-industrial language (worn_kit / station_textures.WORN_KINDS),
one atlas per model (1024 or 2048), saved as blender/textures/surface_<id>_*.jpg. The
organic models (critter, nest) have no bake: vertex-coloured flat materials plus emissive.
Kept procedural in Godot (not built here): floater, storm_cell, deposit_*.

Conventions (Blender Z up, exported +Y up; Blender +Y = Godot -Z = vehicle forward).
Every model's origin is its ground contact, centred. Buildings stay above z = 0 (Godot
scales them on Y while they go up); the game hovers vehicles 3 m itself. The platform is
the exception: its deck top is z = 0 and the hull and lift engines hang below it (it is a
child of the building on gas giants, scaled (radius + 12) / 60).

Sizes (m, the stand-ins): landing pad deck r 55 (footprint 60), harvester bay / garrison
footprint 45, ground turret 18, shield dome 30; vehicles ~9 x 13 x 5; critter ~5 x 7;
nest mound r ~41; platform deck r 60.
Faction read: harvester orange-ochre; hover tank (player soldier) red-brown with a grey
turret and cyan hover glow; raider tank dark grey with a rust-red turret and orange glow.
"""
import math
import os
import random
import sys
import time

import bpy
from mathutils import Matrix, Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
import station_textures as st  # noqa: E402
import worn_kit as wk  # noqa: E402

V = Vector
UP = V((0, 0, 1))
IDS = ["landing_pad", "harvester_bay", "garrison", "ground_turret", "shield_dome",
       "harvester", "hover_tank", "raider_tank", "critter", "nest", "platform"]
OUT_DIR = os.path.join(common.ROOT, "assets", "models", "surface")
BLEND_DIR = os.path.join(common.ROOT, "blender", "surface")
NO_PADS = [(0.0, 900.0), (0.0, 901.0)]
EMIT_K = 0.4            # worn_kit emissives are station strength; surface models are not dimmed
INK_DARK, INK_LIGHT = wk.INK_DARK, wk.INK_LIGHT
polar = wk.polar

MATS = {}
DECALS = []
LABELS = []
RNG = random.Random(7)


# ---------------------------------------------------------------- materials
def _kind(base, **kw):
    d = dict(st.WORN_KINDS[base])
    d.update(kw)
    return d


def tones(c, k=(1.0, 0.93, 1.07, 0.9, 1.03, 0.96)):
    return [tuple(x * f for x in c) for f in k]


VEH = dict(big=(2.0, 1.5), plate=(1.0, 0.75))
CUSTOM = {   # key: (worn kind, flat colour for --no-textures)
    "slate": (_kind("hull3", tones=tones((0.15, 0.18, 0.21)), plate_var=0.06, chip_k=1.3,
                    bleach=0.35), (0.15, 0.18, 0.21)),
    "ochre": (_kind("hull3", tones=tones((0.30, 0.235, 0.12)), plate_var=0.07, chip_k=1.6,
                    bleach=0.45, streak_k=0.55), (0.30, 0.235, 0.12)),
    "mark": (_kind("paint", tones=tones((0.46, 0.33, 0.05), (1, .96, 1.04, .94, 1.02, .98)),
                   rivets=False, seam_big=0.12, seam_small=0.03, chip_k=1.4, bleach=0.2),
             (0.46, 0.33, 0.05)),
    "concrete": (_kind("hull3", big=(6.0, 6.0), plate=(3.0, 3.0),
                       tones=tones((0.25, 0.245, 0.23)), plate_var=0.08, rivets=False,
                       hatches=0.0, seam_big=0.25, seam_small=0.05, chip=(0.2, 0.2, 0.19),
                       chip_metal=0.0, chip_k=0.6, grime_k=1.3, streak_k=0.5, bleach=0.2),
                 (0.25, 0.245, 0.23)),
    "veh_ochre": (_kind("hull3", tones=tones((0.50, 0.26, 0.05)), plate_var=0.06, chip_k=1.3,
                        bleach=0.25, hatches=0.1, **VEH), (0.50, 0.26, 0.05)),
    "veh_red": (_kind("hull3", tones=tones((0.34, 0.075, 0.042)), plate_var=0.06, chip_k=1.2,
                      bleach=0.25, hatches=0.1, **VEH), (0.34, 0.075, 0.042)),
    "veh_grey": (_kind("hull2", tones=tones((0.085, 0.084, 0.082)), plate_var=0.1, chip_k=1.4,
                       hatches=0.08, **VEH), (0.085, 0.084, 0.082)),
    "veh_rust": (_kind("accent", tones=tones((0.27, 0.055, 0.022)), plate_var=0.12, chip_k=1.6,
                       bleach=0.2, **VEH), (0.27, 0.055, 0.022)),
}
for _k, (_cfg, _c) in CUSTOM.items():
    st.WORN_KINDS[_k] = _cfg

GLOWS = {   # key: (emission colour, strength)
    "g_amber": ((1.0, 0.58, 0.2), 2.2),
    "g_white": ((1.0, 0.95, 0.85), 2.0),
    "g_red": ((1.0, 0.12, 0.05), 3.5),
    "g_green": ((0.15, 1.0, 0.3), 2.2),
    "g_cyan": ((0.3, 0.8, 1.0), 2.6),
    "g_core": ((0.35, 0.85, 1.0), 4.0),
    "g_orange": ((1.0, 0.38, 0.08), 2.8),
    "g_yellow": ((1.0, 0.78, 0.12), 3.0),
}


def setup(pre, kinds=(), extra=()):
    m = common.make_material
    wk.build_materials(pre, MATS, extra=extra)
    for k in wk.FLAT:
        b = next((n for n in MATS[k].node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if b:
            b.inputs["Emission Strength"].default_value *= EMIT_K
    for k in kinds:
        MATS[k] = m(f"{pre}_{k}", CUSTOM[k][1], roughness=0.6)
    glow = (0.03, 0.028, 0.025)
    for k, (col, s) in GLOWS.items():
        MATS[k] = m(f"{pre}_{k}", glow, roughness=0.3, emission=col, emission_strength=s)
        MATS[k].use_backface_culling = False


def label(text, centre, normal, up, h, colour, opacity=0.85):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity))


# ---------------------------------------------------------------- shape helpers
def rect_ring(c, w, d, z, ch=0.0, rz=0.0, off=(0.0, 0.0)):
    hw, hd = w / 2, d / 2
    if ch > 0:
        pts = [(hw, -hd + ch), (hw, hd - ch), (hw - ch, hd), (-hw + ch, hd), (-hw, hd - ch),
               (-hw, -hd + ch), (-hw + ch, -hd), (hw - ch, -hd)]
    else:
        pts = [(hw, -hd), (hw, hd), (-hw, hd), (-hw, -hd)]
    r = Matrix.Rotation(rz, 3, "Z")
    c = V(c)
    return [V((c.x, c.y, z)) + r @ V((x + off[0], y + off[1], 0)) for x, y in pts]


def frustum(P, c, w0, d0, w1, d1, h, mat, ch=0.0, rz=0.0, off=(0.0, 0.0)):
    """Tapered block: bottom w0 x d0 at c.z, top w1 x d1 (shifted by off) at c.z + h."""
    c = V(c)
    k = min(w1 / w0, d1 / d0)
    P.loft([rect_ring(c, w0, d0, c.z, ch, rz), rect_ring(c, w1, d1, c.z + h, ch * k, rz, off)],
           mat)


def otube(P, pts, radii, mat, segs=6):
    """Organic tapered tube through `pts` (rings perpendicular to the path), capped."""
    pts = [V(p) for p in pts]
    rings = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        a = V((0, 0, 1)) if abs(t.z) < 0.9 else V((1, 0, 0))
        n = t.cross(a).normalized()
        b = t.cross(n).normalized()
        rings.append([p + (n * math.cos(2 * math.pi * k / segs) +
                           b * math.sin(2 * math.pi * k / segs)) * radii[i]
                      for k in range(segs)])
    P.loft(rings, mat)


def lamp(L, pos, s=0.5, mat="g_amber"):
    L.box(V(pos), (s, s, s * 0.6), mat, bevel=0.0)


def wall_windows(L, c0, c1, normal, n, w=0.9, h=0.8, mode="hab"):
    wk.win_row(L, RNG, c0, c1, normal, n, w, h, mode)


def flood_mast(H, L, base, h, face_to, mat="metal"):
    """Thin mast with a floodlight head facing `face_to` (xy)."""
    b = V(base)
    H.cyl(b + UP * h / 2, 0.32, 0.22, h, mat, segs=6)
    H.box(b + UP * 0.3, (1.0, 1.0, 0.6), "dark", bevel=0.0)
    d = (V(face_to).xy.to_3d() - b.xy.to_3d()).normalized()
    a = math.atan2(d.y, d.x)
    top = b + UP * h
    H.box(top, (0.8, 2.6, 1.1), "dark", rot_z=a, bevel=0.05)
    L.box(top + d * 0.45 - UP * 0.1, (0.12, 2.2, 0.8), "g_white", rot_z=a, bevel=0.0)


def hover_pod(H, L, x, y, r, glow, z=0.85):
    H.cyl(V((x, y, z)), r * 0.9, r, 0.9, "dark", segs=10)
    L.cyl(V((x, y, z - 0.52)), r * 1.12, r * 1.12, 0.16, glow, segs=12)


# ---------------------------------------------------------------- buildings
def b_landing_pad():
    LABELS[:] = ["LZ-01", "CARGO", "KEEP CLEAR", "OPS", "FUEL", "P-1", "#CHEV", "NO STEP"]
    setup("surface_landing_pad", kinds=("slate", "mark", "concrete"), extra=("paint",))
    H = parts.PanelPart("landing_pad_hull", MATS)
    L = parts.PanelPart("landing_pad_lights", MATS)
    DZ = 2.4
    prof = [(0, 0), (55.8, 0), (55.8, 0.4), (55.0, 1.2), (55.0, 2.0), (54.4, DZ), (52.2, DZ),
            (46.0, DZ), (44.6, DZ), (31.0, DZ), (29.8, DZ), (0, DZ)]
    em = ["dark", "concrete", "hull2", "hazard", "dark", "hazard", "pad", "mark", "pad",
          "paint", "pad"]
    H.lathe(prof, 48, lambda i, j: em[j], start=math.pi / 48)
    top = DZ + 0.03
    # centre target: four bars and a square
    for a in range(4):
        d = polar(1.0, a * math.pi / 2)
        H.box(d * 9.5 + V((0, 0, top)), (9.0 if a % 2 == 0 else 1.8, 1.8 if a % 2 == 0 else 9.0,
                                          0.06), "mark", bevel=0.0)
    for a in range(4):
        d = polar(1.0, a * math.pi / 2 + math.pi / 4)
        H.box(d * 3.5 + V((0, 0, top)), (1.0, 5.0, 0.06), "paint", rot_z=a * math.pi / 2 + math.pi / 4,
              bevel=0.0)
    # approach chevrons on the four lanes, pointing in
    for a in range(4):
        ang = a * math.pi / 2
        for r in (35.5, 39.5):
            apex = polar(r, ang, top)
            for s in (-1, 1):
                da = ang + s * math.radians(42)
                ln = 5.0
                H.box(apex + polar(ln / 2, da), (ln, 1.1, 0.06), "mark", rot_z=da, bevel=0.0)
    # ramps on the lanes
    for a in range(4):
        ang = a * math.pi / 2
        d, t = polar(1.0, ang), polar(1.0, ang + math.pi / 2)
        ra = [d * 53.0 + t * 6.5, d * 53.0 + t * 6.5 + UP * DZ, d * 53.0 - t * 6.5 + UP * DZ,
              d * 53.0 - t * 6.5]
        rb = [d * 60.0 + t * 6.5, d * 60.0 + t * 6.5 + UP * 0.15, d * 60.0 - t * 6.5 + UP * 0.15,
              d * 60.0 - t * 6.5]
        H.loft([ra, rb], "concrete")
        for s in (-1, 1):
            H.beam(d * 55.4 + t * s * 6.2 + UP * (DZ * 0.68 + 0.08),
                   d * 60.0 + t * s * 6.2 + UP * 0.22, 0.55, 0.16, "hazard")
        for s in (-1, 1):
            lamp(L, d * 54.2 + t * s * 7.4 + UP * (DZ + 0.2), 0.6, "g_green")
    # rim lights
    for k in range(24):
        a = (k + 0.5) * math.tau / 24
        lamp(L, polar(53.3, a, DZ + 0.18), 0.65, "g_amber")
    # ops tower on the -45 deg rim (Godot +x, +z)
    ta = -math.pi / 4
    tc = polar(46.5, ta, DZ)
    rz = ta + math.pi / 2
    R = Matrix.Rotation(rz, 3, "Z")

    def tp(x, y, z):
        return tc + R @ V((x, y, 0)) + UP * z
    H.box(tp(0, 0, 4.0), (12.0, 9.0, 8.0), "hull3", rot_z=rz)
    H.box(tp(0, 0, 0.9), (12.3, 9.3, 1.8), "slate", rot_z=rz, bevel=0.04)
    H.box(tp(0, 0, 8.25), (12.6, 9.6, 0.5), "dark", rot_z=rz, bevel=0.0)
    n_in = -(R @ V((0, 1, 0)))     # local -y faces the pad centre
    for z in (3.4, 5.9):
        wall_windows(L, tp(-5.0, -4.5, z), tp(5.0, -4.5, z), n_in, 7, 0.8, 0.7, "work")
        wall_windows(L, tp(-5.0, 4.5, z), tp(5.0, 4.5, z), -n_in, 7, 0.8, 0.7, "hab")
    H.box(tp(-1.5, 0.5, 15.0), (4.6, 4.6, 13.5), "hull", rot_z=rz, bevel=0.06)
    for s in (-1, 1):
        H.box(tp(-1.5 + s * 2.35, 0.5, 15.0), (0.3, 4.8, 13.5), "dark", rot_z=rz, bevel=0.0)
    H.box(tp(-1.5, 0.5, 22.6), (7.6, 7.6, 1.6), "slate", rot_z=rz)
    H.box(tp(-1.5, 0.5, 24.6), (7.0, 7.0, 2.4), "dark", rot_z=rz, bevel=0.03)
    for k in range(4):
        nk = R @ polar(1.0, k * math.pi / 2)
        tk = R @ polar(1.0, k * math.pi / 2 + math.pi / 2)
        cc = tp(-1.5, 0.5, 24.6) + nk * 3.52
        wall_windows(L, cc - tk * 2.8, cc + tk * 2.8, nk, 4, 1.1, 1.3, "work")
    H.box(tp(-1.5, 0.5, 26.1), (8.0, 8.0, 0.6), "hull2", rot_z=rz, bevel=0.0)
    H.cyl(tp(-1.5, 0.5, 31.0), 0.35, 0.2, 9.4, "metal", segs=6)
    H.beam(tp(-4.0, 0.5, 32.0), tp(1.0, 0.5, 32.0), 0.2, 0.2, "dark")
    L.cyl(tp(-1.5, 0.5, 36.0), 0.6, 0.45, 0.9, "g_red", segs=8)
    lamp(L, tp(-4.0, 0.5, 32.2), 0.4, "g_white")
    lamp(L, tp(1.0, 0.5, 32.2), 0.4, "g_white")
    label("OPS", tp(2.8, -4.52, 6.9), n_in, UP, 1.2, INK_DARK)
    # cargo stacks by the tower, a fuel farm opposite
    for k, (da, rr) in enumerate(((-0.47, 41.5), (-0.31, 44.5), (0.3, 42.0))):
        wk.cargo_pod(H, polar(rr, ta + da, DZ + 1.3), (2.6, 6.0, 2.6), rot_z=ta + da,
                     body=("hull3", "slate", "hull")[k], band=("accent", "hazard", "accent")[k])
    wk.cargo_pod(H, polar(41.5, ta - 0.47, DZ + 3.9), (2.6, 6.0, 2.6), rot_z=ta - 0.47,
                 body="hull", band="accent")
    fa = math.radians(135)
    for s in (-1, 1):
        c = polar(47.4 + s * 1.9, fa, DZ + 2.0)
        t = polar(1.0, fa + math.pi / 2)
        H.cyl(c, 1.6, 1.6, 9.0, "hull", segs=12,
              axis_rot=V((0, 0, 1)).rotation_difference(t).to_matrix().to_4x4())
        for e in (-3.0, 3.0):
            H.box(c + t * e - UP * 1.3, (1.0, 3.4, 1.2), "dark", rot_z=fa, bevel=0.0)
        H.cyl(c + t * 1.5, 1.68, 1.68, 0.6, "accent", segs=12,
              axis_rot=V((0, 0, 1)).rotation_difference(t).to_matrix().to_4x4())
    label("FUEL", polar(47.0, fa, DZ + 3.62), UP, polar(1.0, fa + math.pi / 2), 1.0, INK_DARK)
    # floodlight masts on the other diagonals
    for a in (math.pi / 4, 3 * math.pi / 4 + 0.35, -3 * math.pi / 4):
        flood_mast(H, L, polar(53.4, a, DZ), 14.0, (0, 0, 0))
    label("LZ-01", V((0, -20.0, DZ)), UP, V((0, 1, 0)), 4.2, INK_LIGHT, 0.8)
    label("CARGO", V((0, 20.5, DZ)), UP, V((0, 1, 0)), 2.8, INK_LIGHT, 0.7)
    label("KEEP CLEAR", V((-20.5, 0, DZ)), UP, V((1, 0, 0)), 2.2, INK_LIGHT, 0.7)
    label("P-1", polar(54.0, -math.pi / 2 - 0.25, 1.6), V((0, -1, 0)), UP, 0.7, INK_DARK)
    root = parts.make_root("landing_pad", 20)
    return root, [H.finish(root)], [L.finish(root)], dict(res=2048, seed0=11)


def b_harvester_bay():
    LABELS[:] = ["HARVEST BAY", "S1", "S2", "S3", "HB-2", "KEEP CLEAR", "ORE", "#CHEV"]
    setup("surface_harvester_bay", kinds=("slate", "ochre", "concrete"))
    H = parts.PanelPart("harvester_bay_hull", MATS)
    L = parts.PanelPart("harvester_bay_lights", MATS)
    Z0 = 0.6
    H.box(V((-1, -2, Z0 / 2)), (52, 44, Z0), "concrete", bevel=0.3)
    cx, cy, W, D, HW = -6.0, -2.0, 30.0, 26.0, 11.0
    H.box(V((cx, cy, Z0 + 1.1)), (W + 0.4, D + 0.4, 2.2), "slate", bevel=0.05)
    H.box(V((cx, cy, Z0 + HW / 2)), (W, D, HW), "hull3", bevel=0.02)
    frustum(H, (cx, cy, Z0 + HW), W + 0.6, D + 0.6, W - 6, D - 6, 3.5, "hull2", ch=0.4)
    H.box(V((cx, cy, Z0 + HW + 4.0)), (W - 8, 5.0, 1.2), "dark", bevel=0.05)
    for k in range(5):
        x = cx - 9.0 + k * 4.5
        L.box(V((x, cy, Z0 + HW + 4.62)), (3.0, 3.6, 0.05), "window_cool", bevel=0.0)
    for k in range(7):   # ribs
        x = cx - W / 2 + 0.2 + k * (W - 0.4) / 6
        for s in (-1, 1):
            H.box(V((x, cy + s * (D / 2 + 0.15), Z0 + HW / 2)), (0.5, 0.35, HW), "dark",
                  bevel=0.0)
    for k in range(6):
        y = cy - D / 2 + 0.2 + k * (D - 0.4) / 5
        for s in (-1, 1):
            H.box(V((cx + s * (W / 2 + 0.15), y, Z0 + HW / 2)), (0.35, 0.5, HW), "dark",
                  bevel=0.0)
    # door (front, -Y = Godot +Z)
    fy = cy - D / 2
    H.box(V((cx, fy - 0.35, Z0 + 4.3)), (19.0, 0.4, 8.6), "metal", bevel=0.0)
    for k in range(7):
        H.box(V((cx, fy - 0.6, Z0 + 0.8 + k * 1.2)), (19.0, 0.12, 0.14), "dark", bevel=0.0)
    H.box(V((cx, fy - 0.45, Z0 + 9.1)), (21.6, 0.9, 1.0), "hazard", bevel=0.0)
    for s in (-1, 1):
        H.box(V((cx + s * 10.3, fy - 0.45, Z0 + 4.3)), (1.0, 0.9, 8.6), "hazard", bevel=0.0)
    for k in range(3):
        lamp(L, V((cx - 7 + k * 7, fy - 1.0, Z0 + 9.9)), 0.6, "g_amber")
    label("HARVEST BAY", V((cx, fy - 0.01, Z0 + 10.4)), V((0, -1, 0)), UP, 1.0, INK_DARK)
    H.box(V((cx, fy - 4.6, Z0 + 0.12)), (22.0, 9.0, 0.24), "pad", bevel=0.0)
    for s in (-1, 1):
        H.box(V((cx + s * 11.2, fy - 4.6, Z0 + 0.14)), (0.6, 9.0, 0.28), "hazard", bevel=0.0)
    label("#CHEV", V((cx, fy - 6.0, Z0 + 0.24)), UP, V((0, 1, 0)), 2.6, INK_LIGHT, 0.6)
    # side office with windows (-X)
    H.box(V((cx - W / 2 - 3.0, cy - 6.0, Z0 + 3.0)), (6.0, 10.0, 6.0), "hull", bevel=0.05)
    H.box(V((cx - W / 2 - 3.0, cy - 6.0, Z0 + 6.2)), (6.4, 10.4, 0.4), "dark", bevel=0.0)
    wall_windows(L, V((cx - W / 2 - 6.02, cy - 10.0, Z0 + 3.8)),
                 V((cx - W / 2 - 6.02, cy - 2.0, Z0 + 3.8)), V((-1, 0, 0)), 5, 0.9, 0.8, "hab")
    wall_windows(L, V((cx - W / 2 - 5.2, cy - 11.02, Z0 + 3.8)),
                 V((cx - W / 2 - 0.8, cy - 11.02, Z0 + 3.8)), V((0, -1, 0)), 3, 0.9, 0.8, "work")
    # silos (+X)
    sx = 17.0
    for k, y in enumerate((-9.0, 2.0, 13.0)):
        H.cyl(V((sx, y, Z0 + 1.25)), 4.9, 4.9, 2.5, "dark", segs=16)
        wk.tank_v(H, (sx, y, Z0 + 1.5), 4.6, 19.5, "hull", band="ochre", segs=16)
        label(f"S{k + 1}", V((sx - 4.6, y, Z0 + 8.0)), V((-1, 0, 0)), UP, 2.2, INK_DARK)
        H.box(V((sx - 5.2, y, Z0 + 2.2)), (2.0, 2.2, 2.0), "ochre", bevel=0.08)
        parts.pipe(H, V((sx - 6.2, y, Z0 + 2.2)), V((cx + W / 2, y if y < 10 else 9.5, Z0 + 2.2)),
                   0.45, "metal", segs=8)
        lamp(L, V((sx, y, Z0 + 21.4)), 0.5, "g_red")
    H.box(V((sx, 2.0, Z0 + 21.0)), (2.6, 25.0, 0.8), "dark", bevel=0.05)
    for s in (-1, 1):
        H.box(V((sx + s * 1.25, 2.0, Z0 + 21.8)), (0.12, 25.0, 0.8), "metal", bevel=0.0)
    p0, p1 = V((cx + W / 2 - 3.0, 2.0, Z0 + HW + 2.5)), V((sx - 0.5, 2.0, Z0 + 21.4))
    H.beam(p0, p1, 2.2, 1.6, "ochre")
    H.beam(p0 - UP * 1.1, p1 - UP * 1.1, 1.6, 0.5, "dark")
    H.box(V((cx + W / 2 - 3.0, 2.0, Z0 + HW + 1.6)), (3.4, 3.4, 3.2), "ochre", bevel=0.06)
    for k in range(3):   # conveyor supports
        q = p0.lerp(p1, (k + 1) / 4)
        if q.x > cx + W / 2 + 1:
            H.box(V((q.x, q.y, (q.z + Z0) / 2)), (0.6, 0.6, q.z - Z0), "dark", bevel=0.0)
    # rear annex, mast
    H.box(V((cx - 4.0, cy + D / 2 + 3.5, Z0 + 3.0)), (14.0, 7.0, 6.0), "hull3", bevel=0.05)
    H.box(V((cx - 4.0, cy + D / 2 + 3.5, Z0 + 6.2)), (14.4, 7.4, 0.4), "dark", bevel=0.0)
    for k in range(4):
        H.box(V((cx - 9.0 + k * 3.2, cy + D / 2 + 3.5, Z0 + 8.0)), (0.25, 5.4, 3.2), "radiator",
              bevel=0.0)
    wall_windows(L, V((cx - 10.0, cy + D / 2 + 7.02, Z0 + 3.6)),
                 V((cx + 2.0, cy + D / 2 + 7.02, Z0 + 3.6)), V((0, 1, 0)), 6, 0.9, 0.8, "hab")
    wk.lattice_mast(H, (-24.0, 14.0, Z0), 25.0, 1.0, 0.35, 5, "dark")
    lamp(L, V((-24.0, 14.0, 25.5)), 0.6, "g_red")
    for p in ((cx - W / 2, fy, Z0 + HW + 0.3), (cx + W / 2, fy, Z0 + HW + 0.3)):
        lamp(L, V(p), 0.6, "g_amber")
    flood_mast(H, L, V((cx + 14.0, fy - 8.0, Z0)), 10.0, (cx, fy - 4.0, 0))
    label("HB-2", V((cx + W / 2 + 0.01, cy - 6.0, Z0 + 7.0)), V((1, 0, 0)), UP, 1.6, INK_DARK)
    root = parts.make_root("harvester_bay", 20)
    return root, [H.finish(root)], [L.finish(root)], dict(res=2048, seed0=21)


def b_garrison():
    LABELS[:] = ["GARRISON", "G-1", "G-2", "#CHEV", "KEEP CLEAR", "ARMORY", "#BAR"]
    setup("surface_garrison", kinds=("slate", "concrete"))
    H = parts.PanelPart("garrison_hull", MATS)
    L = parts.PanelPart("garrison_lights", MATS)
    Z0 = 0.6
    H.box(V((0, -1.5, Z0 / 2)), (52, 50, Z0), "concrete", bevel=0.3)
    frustum(H, (0, 0, Z0), 47.0, 43.0, 45.0, 41.0, 2.4, "hull2", ch=2.4)
    frustum(H, (0, 0, Z0 + 2.4), 45.0, 41.0, 41.0, 37.0, 8.0, "slate", ch=2.3)

    def wd(z, base):
        return base - 0.5 * (z - Z0 - 2.4) + 0.35
    z_a, z_b = Z0 + 7.0, Z0 + 8.2
    frustum(H, (0, 0, z_a), wd(z_a, 45.0), wd(z_a, 41.0), wd(z_b, 45.0), wd(z_b, 41.0),
            z_b - z_a, "accent", ch=2.2)
    TOP = Z0 + 10.4
    H.box(V((0, 0, TOP + 0.15)), (41.6, 37.6, 0.3), "dark", bevel=0.0)
    # vehicle doors in armoured housings on the front (-Y)
    for k, x in enumerate((-9.5, 9.5)):
        H.box(V((x, -20.6, Z0 + 4.6)), (14.0, 5.0, 9.2), "hull2", bevel=0.04)
        H.box(V((x, -20.6, Z0 + 9.45)), (14.4, 5.4, 0.5), "dark", bevel=0.0)
        H.box(V((x, -23.15, Z0 + 3.7)), (10.6, 0.3, 7.2), "metal", bevel=0.0)
        for j in range(6):
            H.box(V((x, -23.35, Z0 + 0.7 + j * 1.2)), (10.6, 0.12, 0.14), "dark", bevel=0.0)
        for s in (-1, 1):
            H.box(V((x + s * 5.8, -23.25, Z0 + 3.7)), (0.9, 0.6, 7.4), "hazard", bevel=0.0)
        H.box(V((x, -23.25, Z0 + 7.75)), (12.5, 0.6, 0.8), "hazard", bevel=0.0)
        lamp(L, V((x - 4.5, -23.6, Z0 + 8.6)), 0.55, "g_amber")
        lamp(L, V((x + 4.5, -23.6, Z0 + 8.6)), 0.55, "g_amber")
        label(f"G-{k + 1}", V((x, -23.11, Z0 + 8.65)), V((0, -1, 0)), UP, 0.65, INK_DARK)
    H.box(V((0, -27.4, Z0 + 0.12)), (36.0, 8.0, 0.24), "pad", bevel=0.0)
    H.box(V((0, -31.2, Z0 + 0.14)), (36.0, 0.6, 0.28), "hazard", bevel=0.0)
    for x in (-9.5, 9.5):
        label("#CHEV", V((x, -27.5, Z0 + 0.24)), UP, V((0, 1, 0)), 2.4, INK_LIGHT, 0.6)
    # barracks block, command tower
    H.box(V((0, 3.0, TOP + 3.6)), (28.0, 22.0, 7.2), "hull3", bevel=0.03)
    H.box(V((0, 3.0, TOP + 0.6)), (28.4, 22.4, 1.2), "slate", bevel=0.03)
    H.box(V((0, 3.0, TOP + 7.45)), (28.8, 22.8, 0.5), "dark", bevel=0.0)
    for z in (TOP + 3.0, TOP + 5.3):
        wall_windows(L, V((-12.5, -8.02, z)), V((12.5, -8.02, z)), V((0, -1, 0)), 10, 1.0, 0.7)
        wall_windows(L, V((-12.5, 14.02, z)), V((12.5, 14.02, z)), V((0, 1, 0)), 10, 1.0, 0.7)
        wall_windows(L, V((-14.02, -6.0, z)), V((-14.02, 12.0, z)), V((-1, 0, 0)), 7, 1.0, 0.7)
        wall_windows(L, V((14.02, -6.0, z)), V((14.02, 12.0, z)), V((1, 0, 0)), 7, 1.0, 0.7)
    label("GARRISON", V((0, -8.01, TOP + 1.7)), V((0, -1, 0)), UP, 1.1, INK_LIGHT)
    T = TOP + 7.7
    H.box(V((8.5, 7.5, T + 3.4)), (8.0, 8.0, 6.8), "hull", bevel=0.05)
    H.box(V((8.5, 7.5, T + 6.95)), (8.6, 8.6, 0.4), "dark", bevel=0.0)
    for nrm in (V((0, -1, 0)), V((1, 0, 0)), V((-1, 0, 0)), V((0, 1, 0))):
        c = V((8.5, 7.5, T + 4.6)) + nrm * 4.02
        t = nrm.cross(UP)
        wall_windows(L, c - t * 3.0, c + t * 3.0, nrm, 4, 1.0, 1.0, "work")
    H.cyl(V((8.5, 7.5, T + 9.2)), 0.3, 0.18, 4.4, "metal", segs=6)
    L.cyl(V((8.5, 7.5, T + 11.75)), 0.75, 0.6, 1.1, "g_red", segs=8)
    for p in ((-13.5, -7.0, T + 0.5), (13.5, -7.0, T + 0.5), (-13.5, 13.0, T + 0.5)):
        H.cyl(V(p) - UP * 0.2, 0.3, 0.3, 0.4, "dark", segs=6)
        L.cyl(V(p) + UP * 0.2, 0.4, 0.32, 0.5, "g_red", segs=8)
    parts.dish(H, V((-8.0, 9.0, T + 0.4)), 2.8, V((0.35, -0.5, 1.0)), "hull", "dark")
    H.cyl(V((-8.0, 9.0, T + 0.2)), 0.8, 0.8, 0.4, "dark", segs=8)
    wk.lattice_mast(H, (-11.5, 12.0, T), T + 9.0, 0.7, 0.25, 4, "dark")
    lamp(L, V((-11.5, 12.0, T + 9.4)), 0.5, "g_red")
    for k in range(5):   # vents
        H.box(V((-3.0 + k * 2.4, 11.5, T + 0.5)), (1.6, 2.4, 1.0), "hull2", bevel=0.08)
    # armour barriers along the lower roof edge
    for k in range(8):
        x = -17.5 + k * 5.0
        H.box(V((x, -17.2, TOP + 0.6)), (3.4, 1.4, 1.2), "hull2", bevel=0.12)
    for s in (-1, 1):
        for k in range(6):
            H.box(V((s * 19.0, -13.0 + k * 5.0, TOP + 0.6)), (1.4, 3.4, 1.2), "hull2", bevel=0.12)
    for p in ((-24.0, -24.0), (24.0, -24.0), (-24.0, 21.0), (24.0, 21.0)):
        flood_mast(H, L, V((p[0], p[1], Z0)), 9.0, (0, 0, 0))
    label("ARMORY", V((21.8, 0.0, Z0 + 5.0)), V((1, 0, 0)), UP, 1.2, INK_LIGHT, 0.7)
    root = parts.make_root("garrison", 20)
    return root, [H.finish(root)], [L.finish(root)], dict(res=2048, seed0=31)


def b_ground_turret():
    LABELS[:] = ["T-01", "#BAR", "HV"]
    setup("surface_ground_turret", kinds=("slate", "concrete"))
    H = parts.PanelPart("ground_turret_hull", MATS)
    L = parts.PanelPart("ground_turret_lights", MATS)
    prof = [(0, 0), (10.0, 0), (10.0, 0.8), (9.6, 1.2), (8.8, 3.8), (8.6, 4.4), (7.2, 5.0),
            (0, 5.0)]
    em = ["dark", "concrete", "hazard", "slate", "dark", "hull2", "dark"]
    H.lathe(prof, 8, lambda i, j: em[j], start=math.pi / 8)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 8 * 0
        c = polar(8.6, a, 1.6)
        H.box(c, (2.4, 1.8, 3.2), "hull2", rot_z=a, bevel=0.1)
        lamp(L, polar(9.85, a + math.pi / 4, 1.0), 0.45, "g_amber")
    H.cyl(V((0, 0, 5.45)), 6.2, 6.2, 0.9, "dark", segs=16)
    zc = 8.2
    parts.prism(H, -4.5, 4.0, (9.0, 4.6, 1.4), (9.0, 4.6, 1.4), "hull", z0=zc)
    parts.prism(H, 4.0, 6.0, (9.0, 4.6, 1.4), (6.6, 2.8, 0.8), "hull", z0=zc)
    parts.prism(H, -6.6, -4.5, (7.0, 3.4, 1.0), (7.0, 3.4, 1.0), "hull2", z0=zc + 0.3)
    for s in (-1, 1):
        H.box(V((s * 4.72, -0.3, zc - 0.1)), (0.45, 7.4, 3.4), "slate", bevel=0.1)
        H.box(V((s * 4.98, -0.3, zc + 0.6)), (0.1, 6.8, 0.5), "accent", bevel=0.0)
    H.box(V((0, 6.3, zc + 0.1)), (5.0, 1.4, 2.6), "dark", bevel=0.1)
    for s in (-1, 1):
        x = s * 1.3
        H.cyl(V((x, 8.2, zc + 0.1)), 0.75, 0.68, 3.4, "dark", segs=10, axis_rot=parts.ALONG_Y)
        H.tube(V((x, 6.8, zc + 0.1)), V((x, 16.0, zc + 0.1)), 0.52, 0.44, "metal", segs=10)
        H.cyl(V((x, 16.4, zc + 0.1)), 0.72, 0.72, 1.2, "dark", segs=8, axis_rot=parts.ALONG_Y)
    H.box(V((2.4, -1.0, zc + 2.9)), (1.8, 1.8, 1.2), "dark", bevel=0.1)
    L.box(V((2.4, -0.06, zc + 2.95)), (1.0, 0.1, 0.5), "g_amber", bevel=0.0)
    H.cyl(V((-1.8, -2.0, zc + 2.45)), 1.0, 0.9, 0.4, "hull2", segs=10)
    H.cyl(V((-2.6, -5.2, zc + 3.3)), 0.12, 0.06, 4.0, "metal", segs=5)
    lamp(L, V((-2.6, -5.2, zc + 5.35)), 0.3, "g_red")
    label("T-01", V((4.95, -2.2, zc - 0.6)), V((1, 0, 0)), UP, 0.9, INK_DARK)
    label("T-01", V((-4.95, -2.2, zc - 0.6)), V((-1, 0, 0)), UP, 0.9, INK_DARK)
    root = parts.make_root("ground_turret", 8)
    return root, [H.finish(root)], [L.finish(root)], dict(res=1024, seed0=41, ao_far=2.5,
                                                          edge_r=0.12)


def b_shield_dome():
    LABELS[:] = ["SHIELD", "HV", "DANGER", "#BAR"]
    setup("surface_shield_dome", kinds=("slate", "concrete"))
    H = parts.PanelPart("shield_dome_hull", MATS)
    L = parts.PanelPart("shield_dome_lights", MATS)
    prof = [(0, 0), (16.0, 0), (16.0, 0.8), (15.2, 1.4), (13.8, 1.6), (13.8, 5.0), (13.2, 5.6),
            (11.0, 8.6), (9.6, 9.6), (4.4, 9.8), (0, 9.8)]
    em = ["dark", "concrete", "concrete", "concrete", "slate", "dark", "hull", "hazard",
          "dark", "dark"]
    H.lathe(prof, 24, lambda i, j: em[j], start=math.pi / 24)
    for k in range(6):
        a = k * math.pi / 3 + math.pi / 6
        c = polar(12.4, a, 1.6)
        frustum(H, c, 3.4, 3.4, 1.9, 1.9, 12.0, "hull2", ch=0.5, rz=a)
        n = polar(1.0, a)
        L.beam(c + n * 1.72 + UP * 1.6, c + n * 1.0 + UP * 11.2, 0.55, 0.14, "g_cyan", up=n)
        H.box(c + UP * 12.4, (2.4, 2.4, 0.8), "dark", rot_z=a, bevel=0.1)
        L.sphere(c + UP * 13.3, 0.6, "g_cyan", segs=8, rings=5)
        H.beam(c + UP * 12.6 - n * 0.8, polar(4.4, a, 17.0), 0.5, 0.5, "dark")
        lamp(L, polar(15.4, a + math.pi / 6, 1.55), 0.45, "g_amber")
    H.cyl(V((0, 0, 11.8)), 4.4, 4.0, 4.0, "hull2", segs=16)
    H.cyl(V((0, 0, 17.0)), 4.8, 4.8, 1.0, "dark", segs=16)
    L.cyl(V((0, 0, 18.2)), 2.0, 2.0, 10.0, "g_core", segs=12)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        H.beam(polar(2.9, a, 13.8), polar(2.9, a, 22.8), 0.45, 0.45, "metal")
    for z in (15.2, 19.6, 22.6):
        H.torus(V((0, 0, z)), 3.0, 0.32, "dark", segs=16, minor_segs=6)
    H.cyl(V((0, 0, 23.9)), 3.2, 1.4, 2.6, "hull", segs=12)
    for k in range(4):
        a = k * math.pi / 2
        H.beam(polar(1.2, a, 25.0), polar(2.6, a, 28.6), 0.35, 0.35, "metal")
    L.sphere(V((0, 0, 27.0)), 1.3, "g_cyan", segs=12, rings=7)
    label("SHIELD", polar(13.81, -math.pi / 2, 3.3), V((0, -1, 0)), UP, 1.0, INK_LIGHT, 0.7)
    label("HV", polar(13.81, math.pi / 2 + 0.6, 3.3), polar(1, math.pi / 2 + 0.6), UP, 1.2,
          INK_LIGHT, 0.7)
    root = parts.make_root("shield_dome", 10)
    return root, [H.finish(root)], [L.finish(root)], dict(res=2048, seed0=51, ao_far=3.0)


def b_platform():
    LABELS[:] = ["PLATFORM", "#CHEV"]
    setup("surface_platform", kinds=("slate",))
    H = parts.PanelPart("platform_hull", MATS)
    L = parts.PanelPart("platform_lights", MATS)
    prof = [(0, 0), (55.0, 0), (57.0, 0), (57.0, 0.6), (60.0, 0.6), (60.0, -2.5), (54.0, -5.0),
            (30.0, -7.0), (0, -8.0)]
    em = ["pad", "hazard", "dark", "hull2", "slate", "dark", "hull2", "dark"]
    H.lathe(list(reversed(prof)), 32, lambda i, j: list(reversed(em))[j], start=math.pi / 32)
    H.cyl(V((0, 0, -9.5)), 9.0, 6.0, 3.0, "dark", segs=16)
    H.cyl(V((0, 0, -12.0)), 6.0, 3.0, 2.0, "hull2", segs=16)
    L.cyl(V((0, 0, -11.0)), 6.4, 6.4, 0.4, "g_cyan", segs=16)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        c = polar(42.0, a, 0.0)
        H.cyl(c + V((0, 0, -8.5)), 6.2, 5.6, 5.0, "hull2", segs=12)
        H.cyl(c + V((0, 0, -11.6)), 5.6, 4.6, 1.2, "dark", segs=12)
        H.lathe([(0, -12.2), (4.6, -12.2), (4.8, -14.0), (4.2, -14.0), (3.6, -12.6), (0, -12.6)],
                12, lambda i, j: "metal" if j < 3 else "dark",
                matrix=Matrix.Translation((c.x, c.y, 0)))
        L.cyl(c + V((0, 0, -13.7)), 3.7, 3.7, 0.25, "g_cyan", segs=12)
        H.cyl(c + V((0, 0, -6.1)), 6.6, 6.6, 0.6, "accent", segs=12)
        H.beam(polar(8.0, a, -10.0), c + V((0, 0, -9.0)) - polar(5.5, a), 1.2, 1.2, "dark")
        for s in (-1, 1):
            H.beam(polar(20.0, a + s * 0.35, -6.4), c + V((0, 0, -7.0)), 0.8, 0.8, "dark")
    for k in range(16):
        a = (k + 0.5) * math.tau / 16
        lamp(L, polar(58.5, a, 0.85), 0.6, "g_amber")
    label("PLATFORM", polar(60.0, -math.pi / 2, -1.0), V((0, -1, 0)), UP, 1.4, INK_LIGHT, 0.7)
    root = parts.make_root("platform", 20)
    return root, [H.finish(root)], [L.finish(root)], dict(res=2048, seed0=61, ao_far=4.0)


# ---------------------------------------------------------------- vehicles (nose +Y)
def b_harvester():
    LABELS[:] = ["H-07", "#BAR", "ORE"]
    setup("surface_harvester", kinds=("veh_ochre",), extra=("ore",))
    H = parts.PanelPart("harvester_hull", MATS)
    L = parts.PanelPart("harvester_lights", MATS)
    parts.prism(H, -5.8, 4.8, (8.0, 0.8, 0.25), (8.0, 0.8, 0.25), "dark", z0=0.95)
    parts.prism(H, -5.6, 4.4, (7.6, 1.6, 0.5), (7.6, 1.6, 0.5), "veh_ochre", z0=2.1)
    parts.prism(H, 4.4, 5.6, (7.6, 1.6, 0.5), (6.6, 1.0, 0.3), "veh_ochre", z0=2.0)
    H.box(V((0, 5.7, 1.2)), (7.0, 0.8, 0.9), "hazard", bevel=0.1)
    H.cyl(V((0, 5.9, 2.0)), 1.25, 1.25, 0.8, "dark", segs=10, axis_rot=parts.ALONG_Y)
    H.tube(V((0, 6.2, 2.0)), V((0, 7.2, 2.0)), 1.1, 0.25, "metal", segs=8)
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        H.box(V((math.cos(a) * 0.8, 6.55, 2.0 + math.sin(a) * 0.8)), (0.35, 0.6, 0.35), "dark",
              bevel=0.0)
    # cab front left
    parts.prism(H, 1.9, 4.3, (2.8, 2.0, 0.5), (2.6, 1.8, 0.6), "veh_ochre", x0=-2.2, z0=3.9)
    H.box(V((-2.2, 3.1, 4.95)), (2.4, 2.0, 0.12), "hull2", bevel=0.0)
    L.box(V((-2.2, 4.32, 4.15)), (2.1, 0.05, 0.75), "window_cool", bevel=0.0)
    L.box(V((-3.6, 3.2, 4.15)), (0.05, 1.5, 0.7), "window_cool", bevel=0.0)
    lamp(L, V((-2.2, 3.7, 5.1)), 0.35, "g_amber")
    # ore hopper
    frustum(H, (1.0, -1.6, 2.9), 5.0, 5.6, 5.8, 6.2, 2.2, "veh_ochre", ch=0.4)
    H.box(V((1.0, -1.6, 4.85)), (5.4, 5.8, 0.3), "ore", bevel=0.0)
    for k in range(5):
        H.rock(V((1.0 + RNG.uniform(-1.8, 1.8), -1.6 + RNG.uniform(-2.0, 2.0), 5.05)),
               RNG.uniform(0.5, 0.9), "ore", RNG)
    for s in (-1, 1):
        H.beam(V((1.0 + s * 2.9, -4.7, 5.15)), V((1.0 + s * 2.9, 1.5, 5.15)), 0.25, 0.25, "dark")
        H.beam(V((-1.9, -1.6 + s * 3.1, 5.15)), V((3.9, -1.6 + s * 3.1, 5.15)), 0.25, 0.25, "dark")
        H.box(V((1.0 + s * 2.75, -1.6, 4.0)), (0.3, 4.8, 0.2), "hull2", bevel=0.0)
    # engine block, stacks
    H.box(V((0, -5.2, 3.45)), (7.0, 1.2, 1.4), "hull2", bevel=0.1)
    for s in (-1, 1):
        H.tube(V((s * 2.6, -5.2, 4.0)), V((s * 2.6, -5.3, 5.6)), 0.3, 0.26, "dark", segs=6)
        lamp(L, V((s * 3.2, -5.85, 3.4)), 0.35, "g_red")
        lamp(L, V((s * 2.7, 5.25, 2.5)), 0.4, "g_white")
    for x in (-3.3, 3.3):
        for y in (3.3, -4.2):
            hover_pod(H, L, x, y, 1.15, "g_amber")
    L.box(V((0, 5.3, 0.55)), (6.8, 0.5, 0.3), "g_amber", bevel=0.0)
    label("H-07", V((-3.52, 2.4, 4.6)), V((-1, 0, 0)), UP, 0.35, INK_DARK)
    label("#BAR", V((3.81, 0.0, 2.3)), V((1, 0, 0)), UP, 0.3, INK_DARK, 0.6)
    root = parts.make_root("harvester", 3)
    return root, [H.finish(root)], [L.finish(root)], dict(res=1024, seed0=71, ao_far=1.5,
                                                          edge_r=0.06)


def b_hover_tank():
    LABELS[:] = ["S-12", "#BAR"]
    setup("surface_hover_tank", kinds=("veh_red", "slate"))
    H = parts.PanelPart("hover_tank_hull", MATS)
    L = parts.PanelPart("hover_tank_lights", MATS)
    parts.prism(H, -6.2, 5.2, (8.2, 1.0, 0.3), (8.2, 1.0, 0.3), "dark", z0=1.1)
    parts.prism(H, -6.4, 4.4, (9.0, 1.6, 0.7), (9.0, 1.6, 0.7), "veh_red", z0=2.4)
    parts.prism(H, 4.4, 6.4, (9.0, 1.6, 0.7), (6.6, 0.7, 0.25), "veh_red", z0=2.3)
    for s in (-1, 1):
        H.box(V((s * 4.62, -0.6, 1.9)), (0.4, 8.6, 1.3), "slate", bevel=0.1)
        H.box(V((s * 3.0, -1.0, 3.25)), (1.6, 7.0, 0.12), "hull2", bevel=0.0)
        H.cyl(V((s * 2.2, -6.9, 2.4)), 0.8, 0.8, 1.4, "dark", segs=10, axis_rot=parts.ALONG_Y)
        L.cyl(V((s * 2.2, -7.62, 2.4)), 0.6, 0.6, 0.1, "g_cyan", segs=10, axis_rot=parts.ALONG_Y)
        lamp(L, V((s * 3.9, 5.0, 2.7)), 0.35, "g_white")
    for x in (-3.2, 3.2):
        for y in (3.3, -4.5):
            hover_pod(H, L, x, y, 1.2, "g_cyan", z=0.8)
    L.box(V((0, -4.0, 0.42)), (8.4, 1.2, 0.2), "g_cyan", bevel=0.0)
    # turret
    zt = 4.2
    parts.prism(H, -3.0, 2.2, (5.8, 2.0, 0.7), (5.8, 2.0, 0.7), "hull", z0=zt)
    parts.prism(H, 2.2, 3.4, (5.8, 2.0, 0.7), (4.0, 1.3, 0.45), "hull", z0=zt - 0.05)
    parts.prism(H, -4.3, -3.0, (5.0, 1.6, 0.5), (4.2, 1.3, 0.4), "hull2", z0=zt + 0.1)
    H.box(V((0, 3.55, zt)), (2.0, 0.8, 1.2), "dark", bevel=0.1)
    H.cyl(V((0, 5.0, zt + 0.05)), 0.56, 0.5, 2.2, "dark", segs=10, axis_rot=parts.ALONG_Y)
    H.tube(V((0, 3.8, zt + 0.05)), V((0, 10.0, zt + 0.05)), 0.42, 0.36, "metal", segs=8)
    H.box(V((0, 10.0, zt + 0.05)), (1.0, 0.9, 0.75), "dark", bevel=0.1)
    H.cyl(V((-1.4, -1.2, zt + 1.15)), 0.7, 0.6, 0.3, "hull2", segs=8)
    H.box(V((1.6, -2.0, zt + 1.35)), (0.7, 0.7, 0.7), "dark", bevel=0.1)
    L.box(V((1.6, -1.63, zt + 1.4)), (0.4, 0.05, 0.25), "g_cyan", bevel=0.0)
    for s in (-1, 1):
        H.box(V((s * 2.95, 1.0, zt + 0.3)), (0.3, 1.4, 0.6), "dark", bevel=0.0)
    label("S-12", V((2.91, -1.0, zt + 0.1)), V((1, 0, 0)), UP, 0.45, INK_LIGHT)
    root = parts.make_root("hover_tank", 3)
    return root, [H.finish(root)], [L.finish(root)], dict(res=1024, seed0=81, ao_far=1.5,
                                                          edge_r=0.06)


def b_raider_tank():
    LABELS[:] = ["#BAR"]
    setup("surface_raider_tank", kinds=("veh_grey", "veh_rust"), extra=("rust", "scrap"))
    H = parts.PanelPart("raider_tank_hull", MATS)
    L = parts.PanelPart("raider_tank_lights", MATS)
    rng = random.Random(13)
    parts.prism(H, -6.0, 5.0, (7.8, 1.0, 0.3), (7.8, 1.0, 0.3), "dark", z0=1.0)
    parts.prism(H, -6.0, 3.6, (8.0, 1.6, 1.0), (7.6, 1.6, 1.0), "veh_grey", z0=2.2)
    parts.prism(H, 3.6, 6.0, (7.6, 1.6, 1.0), (4.0, 0.6, 0.2), "veh_grey", z0=2.0)
    H.box(V((0, 5.6, 1.5)), (8.4, 0.5, 1.6), "rust", r=parts.rot(rx=-0.45), bevel=0.05)
    for x in (-3.2, -1.6, 0.0, 1.6, 3.2):
        H.tube(V((x, 5.85, 1.6)), V((x, 7.1, 1.45)), 0.24, 0.03, "metal", segs=5)
    for k in range(6):
        c = V((rng.uniform(-2.8, 2.8), rng.uniform(-5.0, 2.6), 3.05))
        H.box(c, (rng.uniform(1.2, 2.4), rng.uniform(1.4, 2.8), 0.15),
              rng.choice(("scrap", "rust", "veh_grey")),
              r=parts.rot(rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12), rng.uniform(-0.4, 0.4)),
              bevel=0.0)
    for s in (-1, 1):
        H.box(V((s * 4.15, -0.8, 1.8)), (0.35, 7.0, 1.1), "rust", r=parts.rot(0, s * 0.12, 0),
              bevel=0.05)
        H.tube(V((s * 2.5, -5.8, 2.6)), V((s * 2.8, -6.6, 4.4)), 0.35, 0.3, "dark", segs=6)
        L.cyl(V((s * 2.8, -6.62, 4.45)), 0.3, 0.3, 0.1, "g_orange", segs=6)
    for x in (-3.0, 3.0):
        for y in (3.0, -4.2):
            hover_pod(H, L, x, y, 1.1, "g_orange", z=0.8)
    L.box(V((0, -6.1, 1.4)), (6.0, 0.3, 0.5), "g_orange", bevel=0.0)
    # turret, rust red, set back
    zt = 4.2
    parts.prism(H, -3.6, 1.6, (5.0, 2.0, 0.9), (4.6, 1.8, 0.8), "veh_rust", z0=zt)
    parts.prism(H, 1.6, 2.6, (4.6, 1.8, 0.8), (3.4, 1.1, 0.4), "veh_rust", z0=zt - 0.05)
    H.box(V((0.5, 2.7, zt)), (1.5, 0.7, 1.0), "dark", bevel=0.1)
    H.tube(V((0.5, 2.8, zt)), V((0.5, 9.0, zt)), 0.4, 0.34, "metal", segs=8)
    H.cyl(V((0.5, 8.8, zt)), 0.55, 0.55, 0.9, "dark", segs=8, axis_rot=parts.ALONG_Y)
    H.box(V((-3.1, -0.8, zt + 0.4)), (1.4, 2.6, 1.2), "veh_grey", bevel=0.1)
    for dx in (-0.35, 0.35):
        for dz in (-0.3, 0.3):
            H.cyl(V((-3.1 + dx, 0.52, zt + 0.4 + dz)), 0.22, 0.22, 0.1, "dark", segs=6,
                  axis_rot=parts.ALONG_Y)
    H.tube(V((1.8, -3.0, zt + 1.0)), V((1.95, -3.5, zt + 4.0)), 0.06, 0.04, "metal", segs=4)
    L.box(V((-1.2, 2.32, zt + 0.35)), (0.7, 0.06, 0.25), "g_orange", bevel=0.0)
    root = parts.make_root("raider_tank", 3)
    return root, [H.finish(root)], [L.finish(root)], dict(res=1024, seed0=91, ao_far=1.5,
                                                          edge_r=0.06)


# ---------------------------------------------------------------- organic
def organic_mats(pre, flesh, chitin):
    m = common.make_material
    MATS.clear()
    MATS["flesh"] = m(f"{pre}_flesh", flesh, roughness=0.7, use_vertex_color=True)
    MATS["chitin"] = m(f"{pre}_chitin", chitin, roughness=0.38, use_vertex_color=True)
    glow = (0.03, 0.028, 0.025)
    MATS["g_yellow"] = m(f"{pre}_glow", glow, roughness=0.3, emission=(1.0, 0.78, 0.12),
                         emission_strength=3.0)
    MATS["pod"] = m(f"{pre}_pod", (0.22, 0.27, 0.05), roughness=0.3,
                    emission=(0.75, 0.85, 0.12), emission_strength=0.7)
    MATS["g_yellow"].use_backface_culling = False


def paint_vcol(obj, fn):
    me = obj.data
    col = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    names = [m.name for m in me.materials]
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            c = fn(co, poly.normal, names[poly.material_index])
            col.data[li].color = (*(max(0.0, min(1.0, x)) for x in c), 1.0)
    me.color_attributes.active_color = col
    me.color_attributes.render_color_index = me.color_attributes.active_color_index


def b_critter():
    organic_mats("surface_critter", (0.13, 0.19, 0.045), (0.05, 0.062, 0.024))
    P = parts.Part("critter_body", MATS)
    G = parts.Part("critter_glow", MATS)
    P.sphere(V((0, 0.2, 1.9)), 1.0, "flesh", segs=14, rings=9, scale=(1.9, 2.1, 1.2))
    P.sphere(V((0, -2.3, 1.7)), 1.0, "flesh", segs=12, rings=8, scale=(1.6, 1.8, 1.1))
    P.sphere(V((0, 2.6, 1.85)), 1.0, "flesh", segs=12, rings=8, scale=(1.25, 1.15, 0.9))
    for y, w in ((1.0, 1.5), (-0.1, 1.6), (-1.4, 1.5), (-2.6, 1.3)):
        P.sphere(V((0, y, 2.85 - 0.15 * abs(y + 0.5))), 1.0, "chitin", segs=10, rings=5,
                 scale=(w, 0.75, 0.38))
    for y in (0.6, -0.8, -2.1):
        otube(P, [(0, y, 3.05), (0, y - 0.35, 3.6), (0, y - 0.8, 3.95)], [0.24, 0.13, 0.02],
              "chitin", segs=5)
    for s in (-1, 1):
        otube(P, [(s * 0.55, 3.35, 1.55), (s * 0.8, 4.1, 1.35), (s * 0.35, 4.65, 1.05)],
              [0.28, 0.2, 0.04], "chitin", segs=6)
        for k, y in enumerate((1.3, 0.1, -1.2)):
            sw = (1 - k) * 0.45
            otube(P, [(s * 1.5, y, 1.65), (s * 2.35, y + sw * 0.6, 2.75),
                      (s * 2.75, y + sw * 1.2, 1.2), (s * 2.6, y + sw * 1.4, 0.0)],
                  [0.34, 0.26, 0.17, 0.06], "chitin", segs=6)
        G.sphere(V((s * 0.45, 3.45, 2.2)), 0.23, "g_yellow", segs=8, rings=5)
        G.sphere(V((s * 0.85, 3.15, 2.1)), 0.17, "g_yellow", segs=6, rings=4)
        for y in (-1.9, -2.8):
            G.sphere(V((s * 1.45, y, 1.95)), 0.13, "g_yellow", segs=6, rings=4)
    root = parts.make_root("critter", 2)
    body = P.finish(root, sharp_deg=80)
    glow = G.finish(root, sharp_deg=80)

    def vc(co, n, mat):
        mot = noise.noise(co * 0.9 + V((3, 1, 7)))
        stripe = 0.5 + 0.5 * math.sin(co.y * 4.2 + 0.7 * noise.noise(co * 0.6))
        if mat.endswith("chitin"):
            k = 0.85 + 0.25 * mot
            return (k, k, k * 0.9)
        under = 0.55 + 0.45 * max(0.0, min(1.0, (n.z + 0.4) / 1.0))
        k = (0.78 + 0.18 * mot + 0.12 * stripe) * under
        return (k * 1.05, k, k * 0.8)
    paint_vcol(body, vc)
    return root, [], [body, glow], dict()


def b_nest():
    organic_mats("surface_nest", (0.085, 0.10, 0.032), (0.045, 0.05, 0.022))
    P = parts.Part("nest_mound", MATS)
    G = parts.Part("nest_pods", MATS)
    R_OUT, H_TOP, SEG = 41.0, 19.0, 36

    def mound_h(r):
        if r >= 7.0:
            return H_TOP * max(0.0, 1.0 - (r / R_OUT) ** 2) ** 0.7
        return None

    def disp(x, y, r):
        k = min(1.0, (R_OUT - r) / 6.0) if r < R_OUT else 0.0
        return 2.4 * noise.noise(V((x * 0.055, y * 0.055, 1.3))) * k + \
            0.8 * noise.noise(V((x * 0.17, y * 0.17, 4.1))) * k

    radial = [(41.0, -0.6), (40.0, None), (37.0, None), (33.0, None), (28.5, None),
              (24.0, None), (19.5, None), (15.0, None), (11.0, None), (8.0, None),
              (6.6, H_TOP + 1.2), (5.4, H_TOP + 0.6), (4.2, H_TOP - 2.6), (2.6, H_TOP - 5.4),
              (0.8, H_TOP - 6.2)]
    rings = []
    for r, z in radial:
        ring = []
        for j in range(SEG):
            a = j * math.tau / SEG + (0.0 if r > 8 else 0.05)
            rr = r * (1.0 + 0.07 * noise.noise(V((math.cos(a) * 2.0, math.sin(a) * 2.0, r * 0.05))))
            x, y = rr * math.cos(a), rr * math.sin(a)
            zz = z if z is not None else mound_h(r)
            if r < 41.0:
                zz += disp(x, y, r)
            ring.append(V((x, y, zz)))
        rings.append(ring)
    P.loft(rings, "flesh")

    def surf(r, a):
        x, y = r * math.cos(a), r * math.sin(a)
        return V((x, y, mound_h(r) + disp(x, y, r)))
    G.cyl(V((0, 0, H_TOP - 5.8)), 3.4, 3.4, 0.5, "g_yellow", segs=12)
    for k in range(6):
        a = k * math.tau / 6 + 0.26
        r = 28.5 + 2.5 * math.sin(k * 1.7)
        c = surf(r, a)
        G.sphere(c + V((0, 0, 1.6)), 5.0, "pod", segs=12, rings=8, scale=(1.0, 1.0, 1.3))
        for s in (-0.5, 0.5):
            otube(P, [surf(r - 4, a + s * 0.12) + UP * 0.6, surf(r - 10, a + s * 0.2) + UP * 0.4,
                      surf(r - 16, a + s * 0.25) + UP * 0.2], [0.9, 0.6, 0.3], "chitin", segs=6)
    rng = random.Random(5)
    for k in range(13):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(10.0, 37.0)
        G.sphere(surf(r, a) + UP * 0.4, rng.uniform(1.3, 2.6), "pod", segs=8, rings=6,
                 scale=(1.0, 1.0, 1.25))
    for k in range(5):
        a = k * math.tau / 5 + 0.6
        r0 = 15.0 + 4.0 * math.sin(k * 2.3)
        b = surf(r0, a)
        out = polar(1.0, a)
        pts = [b - UP * 0.5, b + UP * 3.5 + out * 0.8, b + UP * 7.0 + out * 2.6,
               b + UP * 9.5 + out * 5.2]
        otube(P, pts, [1.5, 1.05, 0.6, 0.06], "chitin", segs=7)
    for k in range(8):
        a = k * math.tau / 8 + 0.1
        pts = [surf(r, a + 0.03 * math.sin(r)) + UP * 0.35 for r in (8.5, 14, 20, 27, 34, 39.5)]
        otube(P, pts, [0.9, 0.85, 0.75, 0.6, 0.45, 0.2], "chitin", segs=6)
    root = parts.make_root("nest", 10)
    mound = P.finish(root, sharp_deg=70)
    pods = G.finish(root, sharp_deg=80)

    def vc(co, n, mat):
        r = co.xy.length
        mot = noise.noise(co * 0.12 + V((7, 2, 5)))
        moss = noise.noise(co * 0.04 + V((1, 9, 3)))
        if mat.endswith("chitin"):
            k = 0.8 + 0.3 * mot
            return (k, k * 0.95, k * 0.8)
        hgt = max(0.0, min(1.0, co.z / H_TOP))
        k = (0.55 + 0.35 * hgt + 0.15 * mot) * (0.75 + 0.25 * max(0.0, n.z))
        if r < 7.0:
            k *= 0.6
        w = 0.12 * moss
        return (k * (1.0 + w), k, k * (0.85 - w))
    paint_vcol(mound, vc)
    return root, [], [mound, pods], dict()


BUILDERS = dict(landing_pad=b_landing_pad, harvester_bay=b_harvester_bay, garrison=b_garrison,
                ground_turret=b_ground_turret, shield_dome=b_shield_dome, harvester=b_harvester,
                hover_tank=b_hover_tank, raider_tank=b_raider_tank, critter=b_critter,
                nest=b_nest, platform=b_platform)
VIEW = {   # preview target (x, y, z) and span (m)
    "landing_pad": ((0, 0, 4), 122), "harvester_bay": ((-1, -2, 8), 72),
    "garrison": ((0, -2, 9), 72), "ground_turret": ((0, 3, 6), 30),
    "shield_dome": ((0, 0, 12), 40), "harvester": ((0, 0.5, 2.5), 17),
    "hover_tank": ((0, 1.5, 2.5), 19), "raider_tank": ((0, 1.0, 2.5), 17),
    "critter": ((0, 0.6, 1.6), 10), "nest": ((0, 0, 7), 96), "platform": ((0, 0, -6), 132),
}


# ---------------------------------------------------------------- previews
def preview(mid):
    (tx, ty, tz), span = VIEW[mid]
    d = span * 2.0
    common.setup_preview(cam_loc=(tx - d * 0.42, ty - d * 0.78, tz + d * 0.95),
                         cam_target=(tx, ty, tz), ortho_scale=span * 1.25, res=(1200, 900),
                         key_dir=(-0.5, -0.35, 0.75), key_energy=3.5)
    bpy.context.scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 6.0
    gz = -40.0 if mid == "platform" else (-0.02 if mid in ("critter", "nest") else -0.01)
    me = bpy.data.meshes.new("ground")
    s = span * 4
    me.from_pydata([(-s, -s, gz), (s, -s, gz), (s, s, gz), (-s, s, gz)], [], [(0, 1, 2, 3)])
    g = bpy.data.objects.new("ground", me)
    bpy.context.scene.collection.objects.link(g)
    me.materials.append(common.make_material("preview_ground", (0.07, 0.068, 0.065), 0.9))
    path = os.path.join(common.PREVIEW_DIR, f"surface_{mid}.png")
    common.render(path)
    return path


def contact_sheet():
    import numpy as np
    tw, th, cols, rows = 480, 360, 4, 3
    sheet = np.zeros((rows * th, cols * tw, 4), np.float32)
    sheet[..., 3] = 1.0
    for k, mid in enumerate(IDS):
        p = os.path.join(common.PREVIEW_DIR, f"surface_{mid}.png")
        if not os.path.exists(p):
            continue
        img = bpy.data.images.load(p, check_existing=False)
        img.scale(tw, th)
        px = np.empty(tw * th * 4, np.float32)
        img.pixels.foreach_get(px)
        r, c = divmod(k, cols)
        y0 = (rows - 1 - r) * th
        sheet[y0:y0 + th, c * tw:(c + 1) * tw] = px.reshape(th, tw, 4)
        bpy.data.images.remove(img)
    out = bpy.data.images.new("surface_sheet", cols * tw, rows * th, alpha=False)
    out.pixels.foreach_set(sheet.ravel())
    path = os.path.join(common.PREVIEW_DIR, "surface_sheet.png")
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    print("SHEET", path)


# ---------------------------------------------------------------- main
def build_one(mid, textures, do_preview):
    t0 = time.time()
    common.reset_scene()
    MATS.clear()
    DECALS.clear()
    LABELS.clear()
    RNG.seed(7)
    root, baked, flat, tex = BUILDERS[mid]()
    if baked and textures:
        wk.texture(baked, MATS, f"surface_{mid}", NO_PADS, decals=list(DECALS),
                   labels=list(LABELS), seed0=tex.get("seed0", 1), res=tex.get("res", 1024),
                   ao_far=tex.get("ao_far", 4.0), edge_r=tex.get("edge_r", 0.2))
    else:
        for o in baked:
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    for o in flat:
        if "panel" in o.data.uv_layers:
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    tris = wk.stats(baked + flat)
    os.makedirs(BLEND_DIR, exist_ok=True)
    wk.save_and_export(root, os.path.join(BLEND_DIR, f"{mid}.blend"),
                       os.path.join(OUT_DIR, f"{mid}.glb"))
    if do_preview:
        preview(mid)
    print(f"DONE {mid} tris={tris} in {time.time() - t0:.0f}s")
    return tris


def main():
    argv = parts.script_args(sys.argv)
    ids = list(IDS)
    for a in argv:
        if a.startswith("--only="):
            ids = [s.strip() for s in a.split("=", 1)[1].split(",") if s.strip()]
    bad = [i for i in ids if i not in BUILDERS]
    if bad:
        raise SystemExit(f"unknown ids {bad}, known {IDS}")
    summary = []
    for mid in ids:
        summary.append((mid, build_one(mid, "--no-textures" not in argv,
                                       "--no-preview" not in argv)))
    if "--no-sheet" not in argv and "--no-preview" not in argv:
        common.reset_scene()
        contact_sheet()
    for mid, t in summary:
        print(f"SUMMARY {mid} tris={t}")


main()
