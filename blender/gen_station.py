"""Generate the home station .glb and previews. Worn industrial working station: painted
hull plates, exposed trusses, conduits, radiators, MLI foil, small window rows and nav lights.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_station.py
  Add `-- --no-preview` to skip the PNG renders, `-- --no-textures` for flat materials.
Textures are baked by station_textures.texture_station (Cycles, a few minutes) into
blender/textures/station_hull_* (4096 atlas, JPEG) and embedded in the glb.

Layout (Blender Z up, exported +Y up). Hub centre at origin, play plane z=0.
  core drum r 13.5 (static) with a spoke bearing band at z +-1.4, docking collars on the
  upper tier, comm dish on the tower.
  habitation ring r 32..40 (swept r <= 40.4): 16 pressurised modules between bulkhead ribs,
  4 spoke junction drums, 4 MLI-wrapped tank modules, window rows. The 4 spokes belong to
  station_ring and spin with it.
  Static outer frame ring r 43..45.6 (z +-1), carried by 6 truss struts under the habitat ring
  from a lower spine collar on the underside cone (z ~-13).
  6 addon bays on the frame at BAY_DEG (165 + k*60 deg), collar outer face at r BAY_R, z 0.
  Each bay fits a module 30 wide x 25 tall x 45 long pointing radially out.
  2 docking arms with pads (15 and 195 deg, pad centre r 57.5) and 2 solar wings (135 and 315
  deg, panels r 53.7..82.8, half width 11.3) sit in the 30 deg gaps between the bays.
Hierarchy: station_home (empty root) -> station_core, station_ring, station_docks, station_solar,
  station_bays, addon_bay_1..addon_bay_6, dock_pad_1, dock_pad_2 (empties).
station_ring has its origin at the hub centre so Godot can spin it.
addon_bay_N: Blender rot_z = angle + 90 deg, so its local -Y points radially out; after the
glTF Y-up conversion that is the node's local +Z (Godot basis.z = outward, basis.y = up).
dock_pad_N: pad centre at z 0 (HomeStation.dock_pad; same point as its fallback).
Emission: Godot scales it by ModelLoader.BUILDING_LIGHT_DIM (0.35), so the Blender strengths
here are ~3x what shows in game.
"""
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
import station_textures as st  # noqa: E402

V = Vector
OUT = os.path.join(common.ROOT, "assets", "models", "station", "station_home.glb")
BAY_R = 47.0                                   # collar outer face radius (attach point)
BAY_DEG = [165.0 + 60.0 * k for k in range(6)]  # addon_bay_1 .. addon_bay_6
DOCK_DEG = (15, 195)                           # docking arms, in the gaps between bays
PAD_R = 57.5
SOLAR_DEG = (135, 315)
RING_MODULES = 16
UP = V((0, 0, 1))

MATS = {}
FLAT = ("window", "window_dim", "window_cool", "glass", "nav_red", "nav_green", "nav_white",
        "flood")

# decal sheet cells (station_textures.make_decal_sheet)
LABELS = (["DOCK 1", "DOCK 2"] + [f"BAY {k + 1}" for k in range(6)]
          + [f"C-0{k + 1}" for k in range(4)] + [f"R-{k + 1:02d}" for k in range(RING_MODULES)]
          + ["#BAR", "#CHEV", "NO STEP", "LOX", "N2", "PWR"])
CELL = {t: i for i, t in enumerate(LABELS)}
INK_DARK = (0.035, 0.035, 0.038)        # stencil paint on light hull
INK_LIGHT = (0.42, 0.42, 0.39)          # faded off-white on dark surfaces
ID_COLS = [(0.045, 0.085, 0.17), (0.20, 0.045, 0.035), (0.06, 0.13, 0.06),
           (0.36, 0.26, 0.04), (0.13, 0.13, 0.14), (0.05, 0.11, 0.13)]
DECALS = []
SCORCH = []


def build_materials():
    m = common.make_material
    MATS["hull"] = m("station_hull_white", (0.5, 0.5, 0.48), roughness=0.5)
    MATS["hull2"] = m("station_hull_grey", (0.2, 0.21, 0.22), roughness=0.55)
    MATS["hull3"] = m("station_hull_warm", (0.33, 0.32, 0.29), roughness=0.58)
    MATS["dark"] = m("station_structure_dark", (0.055, 0.058, 0.062), roughness=0.5, metallic=0.55)
    MATS["metal"] = m("station_bare_metal", (0.3, 0.3, 0.31), roughness=0.36, metallic=0.9)
    MATS["accent"] = m("station_accent_paint", (0.28, 0.12, 0.045), roughness=0.6)
    MATS["hazard"] = m("station_hazard", (0.4, 0.29, 0.05), roughness=0.62)
    MATS["pad"] = m("station_pad_deck", (0.095, 0.095, 0.1), roughness=0.72, metallic=0.2)
    MATS["mli"] = m("station_mli_white", (0.5, 0.49, 0.455), roughness=0.86)
    MATS["mli_gold"] = m("station_mli_gold", (0.6, 0.39, 0.12), roughness=0.3, metallic=1.0)
    MATS["mli_silver"] = m("station_mli_silver", (0.6, 0.6, 0.61), roughness=0.26, metallic=1.0)
    MATS["radiator"] = m("station_radiator", (0.47, 0.475, 0.48), roughness=0.45, metallic=0.15)
    MATS["solar"] = m("station_solar_panel", (0.01, 0.018, 0.045), roughness=0.2, metallic=0.5)
    # flat (untextured) emissive / glass, double sided
    # Emissive parts get a near-black base colour so the sun does not light them up white;
    # the glow comes from emission only (Godot multiplies it by BUILDING_LIGHT_DIM 0.35).
    glow = (0.03, 0.028, 0.025)
    MATS["window"] = m("station_window_warm", glow, roughness=0.25,
                       emission=(1.0, 0.6, 0.28), emission_strength=2.0)
    MATS["window_dim"] = m("station_window_amber", glow, roughness=0.25,
                           emission=(1.0, 0.5, 0.18), emission_strength=1.1)
    MATS["window_cool"] = m("station_window_cool", glow, roughness=0.25,
                            emission=(0.7, 0.82, 1.0), emission_strength=1.5)
    MATS["glass"] = m("station_glass_dark", (0.012, 0.016, 0.02), roughness=0.1, metallic=0.0)
    MATS["nav_red"] = m("station_nav_red", glow, roughness=0.3,
                        emission=(1.0, 0.08, 0.03), emission_strength=6.0)
    MATS["nav_green"] = m("station_nav_green", glow, roughness=0.3,
                          emission=(0.08, 1.0, 0.22), emission_strength=6.0)
    MATS["nav_white"] = m("station_nav_white", glow, roughness=0.3,
                          emission=(1.0, 0.97, 0.92), emission_strength=4.0)
    MATS["flood"] = m("station_floodlight", glow, roughness=0.3,
                      emission=(1.0, 0.95, 0.85), emission_strength=4.5)
    for k in FLAT:
        MATS[k].use_backface_culling = False


def polar(r, a, z=0.0):
    return V((r * math.cos(a), r * math.sin(a), z))


def radial(a):
    return V((math.cos(a), math.sin(a), 0.0))


def tangent(a):
    return V((-math.sin(a), math.cos(a), 0.0))


def frame_r(a):
    """Rotation: local X radial out, Y tangential, Z up."""
    return Matrix.Rotation(a, 4, "Z")


def axis_radial(a):
    """Cylinder axis (local Z) pointing radially out at bearing a."""
    return Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "Y")


def axis_tangent(a):
    return Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(-math.pi / 2, 4, "X")


def up_for(n_up):
    """Label up direction that never reads upside down from the south (-Y) camera."""
    return n_up if n_up.y >= -1e-3 else -n_up


def label(text, centre, normal, up, h, colour, opacity=0.85):
    DECALS.append(st.decal(CELL[text], centre, normal, up, h, colour, opacity))


# ---------------------------------------------------------------- generic pieces
def arc_lathe(p, profile, a0, a1, steps, mat_fn, centre=V((0, 0, 0))):
    """Open lathe arc a0..a1 (no end caps) with panel UVs like PanelPart.lathe.
    mat_fn(step_i, edge_j) -> material key."""
    rings = []
    for i in range(steps + 1):
        a = a0 + (a1 - a0) * i / steps
        ca, sa = math.cos(a), math.sin(a)
        rings.append([p.bm.verts.new(centre + V((r * ca, r * sa, z))) for r, z in profile])
    off = p._offset()
    s_len = [0.0]
    for j in range(len(profile) - 1):
        s_len.append(s_len[-1] + math.hypot(profile[j + 1][0] - profile[j][0],
                                            profile[j + 1][1] - profile[j][1]))
    for i in range(steps):
        a, b = rings[i], rings[i + 1]
        for j in range(len(profile) - 1):
            rm = (profile[j][0] + profile[j + 1][0]) / 2
            u0 = rm * (a0 + (a1 - a0) * i / steps) + off.x
            u1 = rm * (a0 + (a1 - a0) * (i + 1) / steps) + off.x
            v0, v1 = s_len[j] + off.y, s_len[j + 1] + off.y
            f = p.bm.faces.new((a[j], b[j], b[j + 1], a[j + 1]))
            f.material_index = p.mi(mat_fn(i, j))
            for lp, uv in zip(f.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
                lp[p.uv].uv = uv


quad = parts.quad
window = parts.window
pick_lit = parts.pick_lit
strut = parts.strut
pipe = parts.pipe


def nav(p, c, mat, s=0.5):
    p.box(c - V((0, 0, s * 0.45)), (s * 0.7, s * 0.7, s * 0.4), "dark", bevel=0.0)
    p.box(c, (s, s, s * 0.6), mat, bevel=0.0)


def truss(p, p0, p1, w, h, n, mat, chord=0.22, brace=0.13, up=UP, diag=True):
    """Open square truss from p0 to p1: 4 longerons, n bays, frames and side diagonals."""
    p0, p1 = V(p0), V(p1)
    x = (p1 - p0).normalized()
    z = (up - x * up.dot(x)).normalized()
    y = z.cross(x)
    corners = [(sy * w / 2, sz * h / 2) for sy in (-1, 1) for sz in (-1, 1)]
    for cy, cz in corners:
        strut(p, p0 + y * cy + z * cz, p1 + y * cy + z * cz, chord, chord, mat, up=z)
    pts = [p0.lerp(p1, i / n) for i in range(n + 1)]
    for i, q in enumerate(pts):
        for sz in (-1, 1):
            strut(p, q + z * sz * h / 2 - y * w / 2, q + z * sz * h / 2 + y * w / 2, brace,
                  brace, mat, up=z)
        if not diag or i == n:
            continue
        qa, qb = (q, pts[i + 1]) if i % 2 == 0 else (pts[i + 1], q)
        for sy in (-1, 1):
            strut(p, qa + y * sy * w / 2 - z * h / 2, qb + y * sy * w / 2 + z * h / 2, brace,
                  brace, mat, up=y)


def pipe_arc(p, r, z, a0, a1, n, rad, mat, segs=6):
    for i in range(n):
        b0 = a0 + (a1 - a0) * i / n
        b1 = a0 + (a1 - a0) * (i + 1) / n
        pipe(p, polar(r, b0, z), polar(r, b1, z), rad, mat, segs=segs)


def handrail(p, pts, mat="metal", hgt=0.9, t=0.07):
    """Rail through `pts` (on the deck) at height hgt, with posts at every point."""
    up = UP * hgt
    for a, b in zip(pts, pts[1:]):
        strut(p, a + up, b + up, t, t, mat)
    for a in pts:
        strut(p, a, a + up, t, t, mat)


def radiator_fin(p, c, along, length, height, t=0.12):
    """Upright thin radiator panel with a manifold pipe on top."""
    along = V(along).normalized()
    rm = Matrix((along, UP.cross(along), UP)).transposed().to_4x4()
    p.box(c, (length, t, height), "radiator", r=rm, bevel=0.0)
    p.tube(c + UP * height / 2 - along * length / 2, c + UP * height / 2 + along * length / 2,
           0.09, 0.09, "metal", segs=5)


# ---------------------------------------------------------------- core (static)
def build_core(rng):
    p = parts.PanelPart("station_core", MATS)
    prof = [(0, -17), (2.5, -17), (3.2, -15.5), (6, -12.5), (10, -9), (12.5, -7.2),
            (13.5, -5.8), (13.5, -1.0), (13.5, 1.0), (13.5, 4.6), (12.6, 6.0),
            (11.2, 6.4), (9.6, 6.4), (9.2, 7.0), (9.2, 8.6), (9.2, 9.8), (8.8, 11.0),
            (6.0, 12.4), (4.6, 12.6), (4.6, 16.8), (3.8, 17.8), (0, 17.8)]
    edge_mat = {0: "dark", 1: "dark", 2: "metal", 3: "hull2", 4: "hull2", 5: "dark",
                6: "hull", 7: "dark", 8: "hull", 9: "hull2", 10: "hull2", 11: "pad", 12: "dark",
                13: "hull3", 14: "hull3", 15: "hull2", 16: "hull", 17: "dark", 18: "hull2",
                19: "hull", 20: "dark"}
    segs = 48
    panel = [rng.random() < 0.3 for _ in range(segs // 6)]

    def core_mat(i, j):
        k = edge_mat[j]
        if k == "hull" and panel[i // 6]:
            return "hull3"
        return k
    p.lathe(prof, segs, core_mat)

    # spoke bearing band: the spokes (station_ring) turn on it
    brg = [(13.4, -1.5), (14.3, -1.4), (14.3, -0.5), (14.15, 0.0), (14.3, 0.5), (14.3, 1.4),
           (13.4, 1.5)]
    p.lathe(brg, segs, lambda i, j: "metal" if j in (2, 3) else "dark")
    for i in range(12):
        a = 2 * math.pi * (i + 0.5) / 12
        p.box(polar(14.0, a, 1.62), (0.9, 0.35, 0.25), "dark", rot_z=a, bevel=0.0)

    # window rows (two decks), skipping pipe and RCS bearings
    for z, mode_k in ((3.2, 0), (-3.6, 1)):
        for i in range(60):
            a = 2 * math.pi * (i + 0.5) / 60
            deg = math.degrees(a) % 45.0
            if abs(deg - 22.5) < 3.2 or (z > 0 and (deg < 4.0 or deg > 41.0)):
                continue
            mode = ("hab", "work", "store")[(i // 10 + mode_k) % 3]
            window(p, polar(13.5, a, z), radial(a), UP, 0.55, 0.8, pick_lit(rng, mode))
    # conduits up the drum (two runs, broken by the bearing band) with brackets
    for k in range(8):
        a = math.radians(22.5 + 45 * k)
        for z0, z1 in ((-5.6, -1.6), (1.6, 4.4)):
            p.tube(polar(13.72, a, z0), polar(13.72, a, z1), 0.16, 0.16, "metal", segs=6)
            p.box(polar(13.6, a, (z0 + z1) / 2), (0.3, 0.5, 0.25), "dark", rot_z=a, bevel=0.0)
        p.tube(polar(13.95, a + 0.03, -5.0), polar(13.95, a + 0.03, -1.6), 0.09, 0.09, "accent",
               segs=5)
    # RCS quads on the upper drum, scorch around them
    for k in range(4):
        a = math.radians(45 + 90 * k)
        c = polar(13.75, a, 4.0)
        parts.rcs_quad(p, c, radial(a), "hull2", "dark", s=0.6, fwd=UP)
        SCORCH.append((*(polar(13.5, a, 4.0)), 1.6))
    # stencil labels and ID bars on the drum
    for k in range(4):
        a = math.radians(45 + 90 * k)
        c = polar(13.52, a, 2.05)
        label(f"C-0{k + 1}", c, radial(a), UP, 0.62, INK_DARK)
        label("#BAR", polar(13.52, a, 2.05) + tangent(a) * 2.2, radial(a), UP, 0.3, ID_COLS[k])

    # ledge (z 6.4): equipment, radiators, handrail along the rim
    for i in range(8):
        a = 2 * math.pi * (i + 0.3) / 8
        w, d, h = rng.uniform(1.0, 1.6), rng.uniform(0.8, 1.2), rng.uniform(0.6, 1.1)
        p.box(polar(10.3, a, 6.4 + h / 2), (d, w, h), rng.choice(["hull2", "hull3", "dark"]),
              rot_z=a, bevel=0.06)
        p.box(polar(10.3, a, 6.4 + h + 0.08), (d * 0.6, w * 0.5, 0.16), "dark", rot_z=a, bevel=0.0)
    for k in range(4):
        a = math.radians(45 + 90 * k)
        radiator_fin(p, polar(10.9, a, 7.75), radial(a), 2.6, 2.4)
        p.box(polar(10.9, a, 6.5), (2.6, 0.4, 0.2), "dark", rot_z=a, bevel=0.0)
    rail = [polar(12.25, 2 * math.pi * i / 24, 6.15) for i in range(25)]
    handrail(p, rail, hgt=0.85, t=0.07)
    # docking collars on the upper tier (between the radiators)
    for k in range(4):
        a = math.radians(90 * k)
        p.cyl(polar(10.6, a, 8.1), 1.35, 1.35, 3.0, "hull2", segs=12, axis_rot=axis_radial(a))
        p.cyl(polar(12.2, a, 8.1), 1.65, 1.65, 0.35, "dark", segs=12, axis_rot=axis_radial(a))
        p.cyl(polar(12.42, a, 8.1), 1.0, 1.0, 0.1, "metal", segs=12, axis_rot=axis_radial(a))
        p.cyl(polar(11.4, a, 8.1), 1.42, 1.42, 0.3, "accent", segs=12, axis_rot=axis_radial(a))
        nav(p, polar(12.2, a, 9.85), "nav_white", 0.35)
        SCORCH.append((*(polar(12.4, a, 8.1)), 1.4))
    # tier windows (ops deck)
    for i in range(36):
        a = 2 * math.pi * (i + 0.5) / 36
        if min(abs(math.degrees(a) % 90.0 - x) for x in (0, 90)) < 9:
            continue
        window(p, polar(9.2, a, 9.2), radial(a), UP, 0.45, 0.55, pick_lit(rng, "work"))

    # tanks on the underside cone: foil wrapped, banded, piped in
    for i in range(6):
        a = 2 * math.pi * i / 6 + 0.5
        foil = "mli_gold" if i % 2 == 0 else "mli_silver"
        p.cyl(polar(8.2, a, -10.0), 1.6, 1.6, 4.0, foil, segs=12)
        p.cyl(polar(8.2, a, -7.7), 1.6, 1.1, 0.6, "hull2", segs=12)
        p.cyl(polar(8.2, a, -12.2), 1.1, 1.6, 0.4, "hull2", segs=12)
        for z in (-10.0,):
            p.cyl(polar(8.2, a, z), 1.66, 1.66, 0.18, "dark", segs=12)
        p.tube(polar(8.2, a, -7.4), polar(10.6, a, -7.4), 0.14, 0.14, "metal", segs=5)

    # tower: control deck windows, dish, antennas
    for i in range(20):
        a = 2 * math.pi * (i + 0.5) / 20
        window(p, polar(4.6, a, 15.4), radial(a), UP, 0.5, 0.6,
               "window_cool" if rng.random() < 0.6 else None)
    p.cyl(V((0, 0, 19.5)), 0.7, 0.5, 3.4, "metal", segs=10)
    p.box(V((0, 0, 18.3)), (3.2, 3.2, 1.0), "hull2", bevel=0.08)
    dish_m = Matrix.Translation((0, 0, 21.5)) @ Matrix.Rotation(math.radians(-38), 4, "X")
    dish_prof = [(0, 0.0), (2.0, 0.2), (4.0, 0.85), (5.9, 2.0), (6.2, 2.0), (6.0, 1.7),
                 (4.0, 0.55), (1.6, -0.2), (0, -0.35)]
    dish_mats = {0: "hull", 1: "hull", 2: "hull", 3: "hull2", 4: "dark", 5: "dark",
                 6: "dark", 7: "dark"}
    p.lathe(dish_prof, 24, lambda i, j: dish_mats[j], matrix=dish_m)
    dish_axis = dish_m.to_3x3().to_4x4()
    for k in range(3):
        aa = k * 2 * math.pi / 3
        p.beam(dish_m @ V((5.4 * math.cos(aa), 5.4 * math.sin(aa), 1.7)), dish_m @ V((0, 0, 4.4)),
               0.1, 0.1, "metal")
    p.cyl(dish_m @ V((0, 0, 4.5)), 0.35, 0.35, 0.6, "hull2", segs=8, axis_rot=dish_axis)
    p.cyl(V((3.8, 0, 20.5)), 0.2, 0.07, 9.0, "metal", segs=6)
    nav(p, V((3.8, 0, 25.2)), "nav_red", 0.45)
    p.cyl(V((-3.4, 1.6, 19.5)), 0.12, 0.05, 5.0, "metal", segs=6)
    p.cyl(V((-1.4, -3.4, 19.0)), 0.1, 0.04, 3.6, "metal", segs=5)
    parts.dish(p, V((2.9, -2.9, 18.9)), 1.0, V((0.5, -0.6, 0.6)), "hull", "metal", depth=0.3)
    nav(p, V((-1.6, -1.6, 18.95)), "nav_white", 0.35)
    # underside: dark thrust cone and beacon instead of a glowing disc
    p.cyl(V((0, 0, -17.6)), 2.2, 1.7, 1.2, "metal", segs=16)
    p.cyl(V((0, 0, -18.3)), 1.7, 1.2, 0.3, "dark", segs=16)
    nav(p, V((0, 0, -18.7)), "nav_white", 0.45)
    SCORCH.append((0.0, 0.0, -17.4, 3.5))
    return p


# ---------------------------------------------------------------- ring (spins)
RING_BODY = [(32.0, -1.4), (32.5, -2.5), (33.6, -3.0), (38.4, -3.0), (39.5, -2.5), (40.0, -1.4),
             (40.0, 1.4), (39.5, 2.5), (38.4, 3.0), (36.8, 3.0), (35.2, 3.0), (33.6, 3.0),
             (32.5, 2.5), (32.0, 1.4), (32.0, -1.4)]


def offset_profile(prof, d):
    out = []
    for r, z in prof:
        v = V((r - 36.0, z))
        n = V((math.copysign(1, v.x) if abs(v.x) > 3.9 else v.x / 4.0,
               math.copysign(1, v.y) if abs(v.y) > 2.9 else v.y / 3.0))
        out.append((r + n.x * d, z + n.y * d))
    return out


def build_ring(rng):
    p = parts.PanelPart("station_ring", MATS)
    step = 2 * math.pi / RING_MODULES
    rib = offset_profile(RING_BODY, 0.35)
    rib_s = offset_profile(RING_BODY, 0.12)
    body = {0: "hull2", 1: "hull2", 2: "hull2", 3: "hull2", 4: "hull", 5: "hull", 6: "hull",
            7: "hull", 8: "hull", 9: "hull2", 10: "hull", 11: "hull", 12: "hull", 13: "hull"}
    modes = []
    for m in range(RING_MODULES):
        a0 = m * step
        paint = "hull3" if rng.random() < 0.3 else "hull"
        mode = rng.choice(["hab", "hab", "hab", "work", "store"])
        if m % 4 == 2:
            mode = "store"           # the MLI tank modules
        modes.append(mode)

        def mf(i, j, paint=paint):
            k = body[j]
            return paint if k == "hull" else k
        arc_lathe(p, RING_BODY, a0, a0 + step, 5, mf)
        # bulkhead rib at the module joint, a light rib mid module
        arc_lathe(p, rib, a0 - 0.014, a0 + 0.014, 1, lambda i, j: "dark")
        arc_lathe(p, rib_s, a0 + step / 2 - 0.005, a0 + step / 2 + 0.005, 1,
                  lambda i, j: "hull2")
        # windows: outer and inner wall, one row each
        # inner wall is concave between lathe vertices: sit the panes 3 cm in
        for side, r in ((1, 40.0), (-1, 31.97)):
            nw = 9 if side > 0 else 7
            for w in range(nw):
                a = a0 + step * (0.1 + 0.8 * (w + 0.5) / nw)
                if min(abs(math.degrees(a) % 90.0 - x) for x in (0.0, 90.0)) < 7.0:
                    continue          # inside a spoke junction drum
                window(p, polar(r, a, 0.45), radial(a) * side, UP, 0.5, 0.65,
                       pick_lit(rng, mode))
        # top: EVA hatch with a short handrail, conduits, label
        am = a0 + step * 0.62
        hc = polar(36.0, am, 3.0)
        p.box(hc + UP * 0.08, (1.3, 1.3, 0.16), "hull2", rot_z=am, bevel=0.1)
        p.box(hc + UP * 0.2, (0.9, 0.9, 0.08), "dark", rot_z=am, bevel=0.0)
        if m % 2 == 0:
            rr = [polar(36.9, am - 1.2 / 36.0, 3.0), polar(36.9, am + 1.2 / 36.0, 3.0)]
            handrail(p, rr, hgt=0.7, t=0.06)
        label("NO STEP", polar(36.0, am - 2.3 / 36.0, 3.0), UP, up_for(radial(am)), 0.32,
              INK_DARK, 0.7)
        lab_a = a0 + step * 0.42
        label(f"R-{m + 1:02d}", polar(37.75, lab_a, 3.0), UP, up_for(tangent(lab_a)), 0.8,
              INK_DARK)
        if m % 3 == 1:
            label("#BAR", polar(37.75, lab_a + 2.6 / 37.75, 3.0), UP, up_for(tangent(lab_a)),
                  0.35, ID_COLS[m % len(ID_COLS)])
        # equipment on store / work modules: upright radiator fins, small boxes
        if mode in ("work", "store") and m % 4 != 2:
            for f in range(2):
                a = a0 + step * (0.5 + 0.28 * f)
                radiator_fin(p, polar(38.0, a, 3.0 + 0.8), tangent(a), 2.2, 1.6)
        if m % 5 == 3:
            p.cyl(polar(34.4, a0 + step * 0.4, 3.9), 0.12, 0.05, 1.8, "metal", segs=5)
            parts.dish(p, polar(34.4, a0 + step * 0.4, 4.8), 0.6, V((0.3, 0.2, 1.0)), "hull",
                       "metal", depth=0.2)
    # conduits along the top (inner half) and underside fins
    pipe_arc(p, 34.35, 3.17, 0.0, 2 * math.pi, 48, 0.17, "metal", segs=6)
    for i in range(16):
        a = 2 * math.pi * (i + 0.25) / 16
        p.box(polar(36.0, a, -3.4), (4.4, 0.3, 0.8), "dark", rot_z=a, bevel=0.0)

    # spoke junction drums (0/90/180/270)
    for s in range(4):
        a = s * math.pi / 2
        c = polar(36.0, a)
        prof = [(0.0, -3.9), (3.6, -3.9), (4.2, -3.3), (4.2, -1.0), (4.2, 1.0), (4.2, 3.3),
                (3.6, 3.9), (1.2, 3.9), (1.2, 4.3), (0.0, 4.3)]
        jm = {0: "dark", 1: "hull2", 2: "hull2", 3: "dark", 4: "hull2", 5: "hull2", 6: "hull2",
              7: "dark", 8: "dark"}
        p.lathe(prof, 20, lambda i, j: jm[j], matrix=Matrix.Translation(c))
        for i in range(16):
            aa = 2 * math.pi * (i + 0.5) / 16
            window(p, c + V((math.cos(aa), math.sin(aa), 0)) * 4.2 + UP * 1.9,
                   V((math.cos(aa), math.sin(aa), 0)), UP, 0.5, 0.5, pick_lit(rng, "work"))
        nav(p, c + UP * 4.45, "nav_white", 0.3)
        label("#BAR", c + UP * 3.9 + tangent(a) * 2.1, UP, up_for(radial(a)), 0.4, ID_COLS[s])
        rc = polar(40.25, a, 2.4)
        parts.rcs_quad(p, rc, radial(a), "hull2", "dark", s=0.5, fwd=UP)
        SCORCH.append((*rc, 1.4))

    # MLI-wrapped tank modules on top (45/135/225/315), foil end caps, saddles
    for s in range(4):
        a = s * math.pi / 2 + math.pi / 4
        c = polar(36.0, a, 5.6)
        ax = axis_tangent(a)
        body_prof = [(0.0, -4.8), (1.6, -4.7), (2.3, -4.1), (2.4, -3.5), (2.4, 3.5),
                     (2.3, 4.1), (1.6, 4.7), (0.0, 4.8)]
        tm = {0: "mli_gold", 1: "mli_gold", 2: "dark", 3: "mli", 4: "dark", 5: "mli_gold",
              6: "mli_gold"}
        p.lathe(body_prof, 14, lambda i, j: tm[j], matrix=Matrix.Translation(c) @ ax)
        for t in (-2.2, 0.0, 2.2):
            p.cyl(c + tangent(a) * t, 2.47, 2.47, 0.22, "dark", segs=14, axis_rot=ax)
        for t in (-2.6, 2.6):
            p.box(polar(36.0, a, 3.0) + tangent(a) * t + UP * 0.6, (3.2, 0.5, 1.2), "dark",
                  rot_z=a, bevel=0.0)
        p.tube(polar(34.0, a, 3.2), c + V((0, 0, -1.5)) - radial(a) * 1.2, 0.15, 0.15,
               "metal", segs=5)
        label(("LOX", "N2", "LOX", "N2")[s], c + UP * 2.4 + tangent(a) * 1.0, UP,
              up_for(tangent(a)), 0.55, INK_DARK, 0.75)

    # spokes: pressurised tube with collars, open truss alongside, conduit on top
    for s in range(4):
        a = s * math.pi / 2
        p.cyl(polar(23.2, a), 1.1, 1.1, 17.8, "hull", segs=10, axis_rot=axis_radial(a))
        for k in range(5):
            p.cyl(polar(16.0 + k * 3.6, a), 1.32, 1.32, 0.45, "dark", segs=10,
                  axis_rot=axis_radial(a))
        p.cyl(polar(14.7, a), 1.6, 1.6, 0.8, "metal", segs=12, axis_rot=axis_radial(a))
        off = tangent(a) * 2.0
        truss(p, polar(15.2, a) + off, polar(31.6, a) + off, 0.9, 0.9, 8, "metal",
              chord=0.18, brace=0.1)
        p.tube(polar(14.4, a, 1.25), polar(32.2, a, 1.25), 0.14, 0.14, "metal", segs=5)
        for k in range(3):
            p.box(polar(18.0 + k * 5.5, a, 1.15), (0.3, 0.4, 0.3), "dark", rot_z=a, bevel=0.0)
        for k in range(4):
            window(p, polar(19.0 + k * 3.6, a) - tangent(a) * 1.1, -tangent(a), UP, 0.45, 0.45,
                   pick_lit(rng, "work"))
    ring_modes = modes
    return p, ring_modes


# ---------------------------------------------------------------- docks
def build_docks(rng):
    p = parts.PanelPart("station_docks", MATS)
    for n_pad, a_deg in enumerate(DOCK_DEG):
        a = math.radians(a_deg)
        t = tangent(a)
        # open truss arm from the frame ring out to the collar, walkway tube on top
        truss(p, polar(41.8, a, -0.9), polar(50.0, a, -0.9), 2.6, 1.6, 4, "metal",
              chord=0.26, brace=0.15)
        p.cyl(polar(46.4, a, 0.9), 1.0, 1.0, 7.4, "hull", segs=10, axis_rot=axis_radial(a))
        for k in range(3):
            p.cyl(polar(43.6 + k * 2.8, a, 0.9), 1.18, 1.18, 0.3, "dark", segs=10,
                  axis_rot=axis_radial(a))
        for k in range(5):
            for sd in (-1, 1):
                window(p, polar(44.3 + k * 1.2, a, 0.95) + t * sd * 1.0, t * sd, UP, 0.38, 0.45,
                       pick_lit(rng, "hab"))
        p.tube(polar(42.5, a, -0.9) + t * 1.6, polar(50.0, a, -0.9) + t * 1.6, 0.16, 0.16,
               "accent", segs=5)
        handrail(p, [polar(42.6, a, 1.9) + t * 0.5, polar(49.8, a, 1.9) + t * 0.5], hgt=0.6,
                 t=0.06)
        # docking collar node
        prof = [(0.0, -1.8), (2.2, -1.8), (2.5, -1.4), (2.5, 1.4), (2.2, 1.8), (0.0, 1.8)]
        cm = {0: "dark", 1: "hull2", 2: "hull2", 3: "hull2", 4: "dark"}
        c51 = polar(51.0, a)
        p.lathe(prof, 14, lambda i, j: cm[j], matrix=Matrix.Translation(c51))
        p.cyl(c51 + UP * 1.95, 1.4, 1.4, 0.3, "metal", segs=12)
        for i in range(8):
            aa = a + math.pi / 2 + (i - 3.5) * 0.3
            window(p, c51 + V((math.cos(aa), math.sin(aa), 0)) * 2.5 + UP * 0.3,
                   V((math.cos(aa), math.sin(aa), 0)), UP, 0.4, 0.5, pick_lit(rng, "work"))
        SCORCH.append((*(polar(53.0, a, 0.5)), 2.5))
        # pad: octagonal platform centred at r PAD_R
        c = polar(PAD_R, a, 0.2)
        mtx = Matrix.Translation(c) @ Matrix.Rotation(a + math.pi / 8, 4, "Z")
        prof = [(0, 0.7), (4.6, 0.7), (5.4, 0.7), (6.6, 0.7), (7.2, 0.4), (7.2, -0.4),
                (6.4, -0.9), (3.0, -1.4), (0, -1.6)]
        pad_mats = {0: "pad", 1: "hazard", 2: "pad", 3: "hull2", 4: "dark", 5: "dark",
                    6: "dark", 7: "dark"}
        p.lathe(prof, 8, lambda i, j: pad_mats[j], matrix=mtx)
        deck = c + UP * 0.7
        label(f"DOCK {n_pad + 1}", deck + V((0, 0, 0.0)), UP, V((0, 1, 0)), 0.95, INK_LIGHT, 0.8)
        label("#CHEV", deck - radial(a) * 3.2, UP, up_for(t), 0.55, (0.36, 0.26, 0.04), 0.75)
        # rim edge lights (small, amber) and four floodlight masts aimed at the deck
        for k in range(8):
            ang = a + math.pi / 8 + k * math.pi / 4
            lp = c + V((math.cos(ang), math.sin(ang), 0)) * 6.9 + UP * 0.55
            p.box(lp, (0.3, 0.3, 0.16), "window_dim", rot_z=ang, bevel=0.0)
        for k in range(4):
            ang = a + math.pi / 4 + k * math.pi / 2
            d = V((math.cos(ang), math.sin(ang), 0))
            base = c + d * 6.2 + UP * 0.5
            p.beam(base, base + UP * 2.6, 0.16, 0.16, "metal")
            p.box(base + UP * 2.7 - d * 0.15, (0.55, 0.55, 0.32), "dark", rot_z=ang, bevel=0.0)
            p.box(base + UP * 2.62 - d * 0.32, (0.08, 0.42, 0.22), "flood", rot_z=ang, bevel=0.0)
        nav(p, c + (radial(a) * 7.0) + UP * 0.6, "nav_red" if n_pad == 0 else "nav_green", 0.45)
        p.cyl(c + UP * -2.6, 1.6, 0.8, 2.4, "metal", segs=8)
        truss(p, polar(51.5, a, -1.2), polar(55.5, a, -1.2), 1.4, 0.8, 2, "metal",
              chord=0.22, brace=0.13)
        # control cab beside the collar
        tc = polar(51.0, a) + t * 3.6
        p.box(tc + UP * 1.2, (2.0, 2.0, 2.6), "hull3", rot_z=a, bevel=0.1)
        for sd, nn in ((1, radial(a)), (-1, -radial(a)), (1, t), (-1, -t)):
            for wk in (-0.45, 0.45):
                side = nn.cross(UP).normalized()
                window(p, tc + UP * 2.05 + nn * 1.0 + side * wk, nn, UP, 0.62, 0.42,
                       "window_cool" if rng.random() < 0.6 else None)
        p.box(tc + UP * 2.72, (2.3, 2.3, 0.3), "dark", rot_z=a, bevel=0.0)
        p.cyl(tc + UP * 3.9, 0.08, 0.04, 2.2, "metal", segs=5)
        nav(p, tc + UP * 5.05, "nav_red", 0.3)
    return p


# ---------------------------------------------------------------- solar
def build_solar(rng):
    p = parts.PanelPart("station_solar", MATS)
    for wing, a_deg in enumerate(SOLAR_DEG):
        a = math.radians(a_deg)
        t, rd = tangent(a), radial(a)
        # root gimbal between the bays
        p.cyl(polar(47.5, a), 1.9, 1.9, 4.0, "hull2", segs=12, axis_rot=axis_radial(a))
        p.cyl(polar(46.0, a), 2.2, 2.2, 0.5, "dark", segs=12, axis_rot=axis_radial(a))
        p.cyl(polar(49.2, a), 1.3, 1.3, 0.8, "metal", segs=12, axis_rot=axis_radial(a))
        label("PWR", polar(47.5, a, 1.92), UP, up_for(t), 0.6, INK_LIGHT, 0.7)
        # mast: open truss out to the tip
        truss(p, polar(49.5, a), polar(86.0, a), 1.2, 1.2, 9, "metal", chord=0.2, brace=0.12)
        p.tube(polar(49.6, a, 0.75), polar(85.5, a, 0.75), 0.12, 0.12, "dark", segs=5)
        p.cyl(polar(86.4, a), 1.0, 1.0, 1.6, "hull2", segs=10)
        nav(p, polar(86.4, a, 1.05), "nav_red" if wing == 0 else "nav_green", 0.6)
        # blankets: 4 segments per side, 6 x 9 m cell area in a thin frame
        for k in range(4):
            r = 57.0 + k * 7.5   # inner panel edge r 53.7 clears the bay modules
            for sgn in (-1, 1):
                pc = polar(r, a, 0.15) + t * sgn * 6.4
                p.box(polar(r, a, 0.0) + t * sgn * 1.2, (0.3, 1.3, 0.25), "metal", rot_z=a,
                      bevel=0.0)
                p.box(pc, (6.6, 9.8, 0.08), "dark", rot_z=a, bevel=0.0)
                p.box(pc + UP * 0.07, (6.0, 9.0, 0.04), "solar", rot_z=a, bevel=0.0)
                for sx in (-1, 1):
                    p.box(pc + rd * sx * 3.18 + UP * 0.08, (0.24, 9.8, 0.1), "metal", rot_z=a,
                          bevel=0.0)
                    p.box(pc + t * sx * 4.7 + UP * 0.08, (6.6, 0.24, 0.1), "metal", rot_z=a,
                          bevel=0.0)
                p.box(pc + UP * 0.1, (0.1, 9.0, 0.06), "metal", rot_z=a, bevel=0.0)
    return p


# ---------------------------------------------------------------- addon bays
def bay_frame(a, r=BAY_R, z=0.0):
    """Frame at radius r on bearing a: local +Z radially out, local +X tangential, +Y up."""
    return (Matrix.Translation(polar(r, a, z)) @ Matrix.Rotation(a, 4, "Z")
            @ Matrix.Rotation(math.pi / 2, 4, "Y") @ Matrix.Rotation(math.pi / 2, 4, "Z"))


def bay_collar(p, a, k):
    """Station half of the docking collar; its outer face lies at r = BAY_R.
    Same flange as gen_station_addons.mating_collar (r 5.4, hazard ring r 3.6..4.6)."""
    t = tangent(a)
    # adapter block between the frame ring and the flange
    p.box(polar(44.6, a, 0.0), (3.2, 13.0, 11.0), "hull3" if k % 2 else "hull", rot_z=a,
          bevel=0.03)
    p.box(polar(44.6, a, 5.62), (3.0, 12.4, 0.25), "hull2", rot_z=a, bevel=0.0)
    p.box(polar(44.6, a, -5.6), (3.4, 13.2, 0.3), "dark", rot_z=a, bevel=0.0)
    for sgn in (-1, 1):
        for zz in (-3.0, 0.0, 3.0):
            p.box(polar(44.6, a, zz) + t * sgn * 6.55, (2.8, 0.18, 0.5), "dark", rot_z=a,
                  bevel=0.0)
        p.tube(polar(43.1, a, -5.0) + t * sgn * 5.8, polar(43.1, a, 5.0) + t * sgn * 5.8,
               0.15, 0.15, "metal", segs=5)
    for sgn in (-1, 1):   # top stiffener ribs, vent box, conduit
        p.box(polar(44.6, a, 5.9) + t * sgn * 3.4, (3.3, 0.3, 0.3), "dark", rot_z=a, bevel=0.0)
        p.box(polar(43.7, a, 5.75) + t * sgn * 5.2, (1.0, 1.4, 0.5), "hull2", rot_z=a, bevel=0.08)
        p.box(polar(46.15, a, 0.0) + t * sgn * 6.25, (0.3, 0.5, 11.0), "dark", rot_z=a, bevel=0.0)
        p.box(polar(46.15, a, sgn * 5.25), (0.3, 13.0, 0.5), "dark", rot_z=a, bevel=0.0)
    pipe(p, polar(43.25, a, 5.95) - t * 6.0, polar(43.25, a, 5.95) + t * 6.0, 0.14, "metal")
    label(f"BAY {k + 1}", polar(44.9, a, 5.75), UP, up_for(t), 0.95, INK_DARK)
    label("#BAR", polar(44.6, a, 5.75) + t * 5.0, UP, up_for(t), 0.4, ID_COLS[k], 0.8)
    # flange, closed hatch in the middle; outer face exactly at BAY_R
    prof = [(0.0, -0.15), (3.4, -0.15), (3.6, 0.0), (4.6, 0.0), (5.4, 0.0), (5.4, -1.0),
            (0.0, -1.0)]
    fm = {0: "dark", 1: "dark", 2: "hazard", 3: "hull2", 4: "hull2", 5: "dark"}
    p.lathe(prof, 24, lambda i, j: fm[j], matrix=bay_frame(a), start=math.pi / 24)
    # hatch cross bars and latches
    p.box(polar(BAY_R - 0.12, a, 0.0), (0.12, 6.4, 0.5), "metal", rot_z=a, bevel=0.0)
    p.box(polar(BAY_R - 0.12, a, 0.0), (0.12, 0.5, 6.4), "metal", rot_z=a, bevel=0.0)
    for q in range(4):
        ang = math.pi / 4 + q * math.pi / 2
        off = t * math.cos(ang) * 5.9 + V((0, 0, math.sin(ang) * 5.9))
        p.box(polar(BAY_R - 0.6, a, 0.0) + off, (1.2, 0.9, 0.9), "dark", rot_z=a, bevel=0.0)
    # small docking guide lights on the adapter face corners
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.box(polar(46.22, a, sz * 4.8) + t * sx * 5.8, (0.1, 0.3, 0.3),
                  "window_dim" if sz < 0 else "nav_white", rot_z=a, bevel=0.0)
    # strut: post down from the adapter, truss in under the habitat ring to the spine collar
    p.box(polar(44.6, a, -9.9), (2.2, 2.2, 8.8), "dark", rot_z=a, bevel=0.06)
    for zz in (-8.0, -11.0):
        p.box(polar(44.6, a, zz), (2.4, 2.4, 0.3), "hull2", rot_z=a, bevel=0.0)
    truss(p, polar(9.8, a, -13.4), polar(43.6, a, -13.4), 1.8, 1.6, 6, "metal",
          chord=0.3, brace=0.16)
    p.tube(polar(10.0, a, -12.35), polar(43.5, a, -12.35), 0.14, 0.14, "accent", segs=5)
    p.box(polar(44.6, a, -14.2), (3.4, 3.2, 1.6), "hull2", rot_z=a, bevel=0.06)


def build_bays(rng):
    p = parts.PanelPart("station_bays", MATS)
    # static frame ring just outside the habitat ring (swept r <= 40.4)
    prof = [(43.0, -1.0), (45.6, -1.0), (45.6, 1.0), (43.0, 1.0), (43.0, -1.0)]
    fmat = {0: "dark", 1: "hull2", 2: "hull2", 3: "dark"}
    p.lathe(prof, 96, lambda i, j: fmat[j])
    for i in range(24):
        a = 2 * math.pi * (i + 0.5) / 24
        p.box(polar(44.3, a, 0.0), (2.9, 0.35, 2.3), "dark", rot_z=a, bevel=0.0)
    pipe_arc(p, 44.9, 1.2, 0.0, 2 * math.pi, 48, 0.16, "metal", segs=6)
    # lower spine collar on the underside cone, below the tanks
    prof = [(5.0, -14.4), (9.6, -14.4), (10.2, -13.8), (10.2, -12.9), (9.6, -12.3), (5.6, -12.3)]
    cmat = {0: "dark", 1: "dark", 2: "hull2", 3: "metal", 4: "hull2"}
    p.lathe(prof, 36, lambda i, j: cmat[j])
    for k, a_deg in enumerate(BAY_DEG):
        bay_collar(p, math.radians(a_deg), k)
    return p


def add_empties(root):
    """addon_bay_N at each collar face. rot_z = a + 90 deg: local -Y radially out, which the
    glTF Y-up conversion turns into the node's local +Z. dock_pad_N at each pad centre."""
    for k, a_deg in enumerate(BAY_DEG):
        a = math.radians(a_deg)
        e = parts.add_empty(f"addon_bay_{k + 1}", root, polar(BAY_R, a), a + math.pi / 2, 6.0)
    for k, a_deg in enumerate(DOCK_DEG):
        parts.add_empty(f"dock_pad_{k + 1}", root, polar(PAD_R, math.radians(a_deg)), 0.0, 4.0)


def build_station():
    rng = random.Random(4242)
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    root = parts.make_root("station_home", size=8)
    core = build_core(rng)
    ring, _ = build_ring(rng)
    builders = [core, ring, build_docks(rng), build_solar(rng), build_bays(rng)]
    objs = [b.finish(root) for b in builders]
    add_empties(root)
    return root, objs


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    common.reset_scene()
    root, objs = build_station()
    ring = next(o for o in objs if o.name == "station_ring")
    rmax = max(math.hypot(v.co.x, v.co.y) for v in ring.data.vertices)
    print(f"STAT station_ring max radius {rmax:.2f} (limit 41.07)")
    assert rmax < 41.07, rmax
    if "--no-textures" not in argv:
        pads = [tuple(polar(PAD_R, math.radians(d))[:2]) for d in DOCK_DEG]
        st.texture_station(objs, MATS, pads, scorch=SCORCH, decals=DECALS, labels=LABELS)
    parts.print_stats(objs)
    blend = os.path.join(common.ROOT, "blender", "station_home.blend")
    parts.save_blend(blend)
    bpy.ops.file.make_paths_relative()      # textures as //textures/...
    bpy.ops.wm.save_mainfile(filepath=blend)
    common.export_glb(root, OUT, export_image_format="AUTO")
    if "--no-preview" not in argv:
        common.setup_preview(cam_loc=(0, -120, 120), cam_target=(0, 0, 0), ortho_scale=175,
                             res=(1600, 1200), key_dir=(-0.6, -0.35, 0.7), key_energy=3.5)
        for m in bpy.data.materials:   # show the in-game emission (BUILDING_LIGHT_DIM)
            b = m.node_tree.nodes.get("Principled BSDF") if m.node_tree else None
            if b:
                b.inputs["Emission Strength"].default_value *= 0.35
        common.render(os.path.join(common.PREVIEW_DIR, "station_home_preview.png"))
        scene = bpy.context.scene
        cam = scene.camera
        cam.data.type = "PERSP"
        cam.data.lens = 35
        cam.location = (66.0, 18.0, 30.0)
        target = V((30.0, 32.0, 0.0))
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        common.render(os.path.join(common.PREVIEW_DIR, "station_home_closeup.png"))


main()
