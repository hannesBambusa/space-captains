"""Generate the Forward Station .glb and previews: the frontier station a colony founds in
another solar system. Smaller, rougher sibling of the home station (gen_station.py): the
same material language and worn atlas bake, the same node names, but prefab can modules
bolted to a faceted core, a prefab habitat ring that is still partly open truss, a big comms
dish pointed back toward home, a docking spine under the hub, cargo pod racks, beacons and
hazard paint.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_forward_station.py
  Options after `--`: --no-preview, --no-textures (flat materials, no Cycles bake),
  --no-compare (skip the side-by-side render with station_home.glb).
Textures: one 4096 worn atlas (station_textures.WORN_KINDS + worn_kit "rust"), saved as
blender/textures/station_forward_{albedo,mr,normal}.jpg + station_forward_decals.png; the
solar panels reuse the home station's tiling cell texture (blender/textures/station_solar_*,
baked once if missing). Images are embedded in the glb as JPEG.

Layout (Blender Z up, exported +Y up; Blender -Y = Godot +Z). Hub centre at origin, plane z=0.
  core     faceted 16-sided drum r 8.5 (z -13..10), spoke bearing band r 8.4..9.3 at z +-1.5,
           three prefab can modules bolted radially to the tower (z 6.9, r 5.6..13.6),
           comms dish r 6.2 on a mast (centre z 16.8) aimed at DISH_BEARING / DISH_ELEV.
  ring     prefab habitat ring, 9 junction nodes on r 21.5 (every 40 deg), 7 can modules
           and 2 open-truss segments still under construction, 3 spokes (0/120/240).
           Swept r <= 24.8 (asserted < 25.4). station_ring has its origin at the hub
           centre so Godot can spin it.
  frame    static frame ring r 26..27.6 (z +-0.9), posts + trusses down to a lower collar
           (z ~-9) on the underside cone.
  bays     2 addon bays: addon_bay_1 at 285 deg (front, toward the RTS camera), addon_bay_2
           at 105 deg. Collar outer face at r BAY_R 30, z 0, same flange as the home bays
           (r 5.4, gen_station_addons.mating_collar), fits the same 30 x 25 x 45 m modules.
  docks    docking spine along the 15/195 deg axis under the hub (z -6.5), docking collar
           at r 33.5, octagonal pads (r 7.2, deck top z 0.9) centred r PAD_R 40 at 15 and
           195 deg, the same bearings and pad as the home station.
  solar    2 wings at 60 and 240 deg, panels r ~34..54, mast tip r 59.7; one blanket left unfitted.
  cargo    pod racks at 150 and 330 deg, r 28..37.
Hierarchy: station_forward (empty root) -> station_core, station_ring, station_docks,
  station_solar, station_bays, addon_bay_1, addon_bay_2, dock_pad_1, dock_pad_2 (empties).
addon_bay_N: Blender rot_z = angle + 90 deg (as gen_station.py), so its local -Y points
radially out; after the glTF Y-up conversion that is the node's local +Z (Godot basis.z =
outward, basis.y = up). dock_pad_N: pad centre at z 0, rot 0 (as gen_station.py).
Emission: Godot scales it by ModelLoader.BUILDING_LIGHT_DIM (0.35).
"""
import math
import os
import random
import shutil
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
import station_textures as st  # noqa: E402
import worn_kit as wk  # noqa: E402  (registers the "rust" worn kind)

V = Vector
PRE = "station_forward"
OUT = os.path.join(common.ROOT, "assets", "models", "station", "station_forward.glb")
BLEND = os.path.join(common.ROOT, "blender", "station_forward.blend")
HOME_GLB = os.path.join(common.ROOT, "assets", "models", "station", "station_home.glb")
PREVIEW_COPY = os.path.join(wk.SCRATCH, "forward")

BAY_R = 30.0                         # collar outer face radius (attach point)
BAY_DEG = [285.0, 105.0]             # addon_bay_1, addon_bay_2
DOCK_DEG = (15, 195)                 # same bearings as the home station's pads
PAD_R = 40.0
SOLAR_DEG = (60, 240)
CARGO_DEG = (150, 330)
RING_R = 21.5                        # junction node centres
RING_NODES = 9
SPOKES = (0, 3, 6)                   # node indices with a spoke
OPEN_SEGS = (2, 7)                   # ring segments still open truss
FRAME_R0, FRAME_R1 = 26.0, 27.6
SPINE_Z = -6.5
LOW_Z = -9.0                         # lower collar / strut trusses
DISH_BEARING = 115.0                 # comms dish azimuth (deg), "back toward home"
DISH_ELEV = 52.0
RING_LIMIT = 25.4
UP = V((0, 0, 1))

MATS = {}
FLAT = ("window", "window_dim", "window_cool", "glass", "nav_red", "nav_green", "nav_white",
        "flood")

LABELS = (["DOCK 1", "DOCK 2", "BAY 1", "BAY 2", "FS-1", "FWD"]
          + [f"M-{k + 1:02d}" for k in range(10)]
          + ["#BAR", "#CHEV", "NO STEP", "LOX", "N2", "PWR", "CARGO", "KEEP CLEAR", "COMMS",
             "H2O"])
CELL = {t: i for i, t in enumerate(LABELS)}
INK_DARK = (0.035, 0.035, 0.038)
INK_LIGHT = (0.42, 0.42, 0.39)
HAZ_INK = (0.36, 0.26, 0.04)
ID_COLS = [(0.045, 0.085, 0.17), (0.20, 0.045, 0.035), (0.06, 0.13, 0.06),
           (0.36, 0.26, 0.04), (0.13, 0.13, 0.14), (0.05, 0.11, 0.13)]
DECALS = []
SCORCH = []


def build_materials():
    m = common.make_material
    MATS.clear()
    MATS["hull"] = m(f"{PRE}_hull_white", (0.5, 0.5, 0.48), roughness=0.5)
    MATS["hull2"] = m(f"{PRE}_hull_grey", (0.2, 0.21, 0.22), roughness=0.55)
    MATS["hull3"] = m(f"{PRE}_hull_warm", (0.33, 0.32, 0.29), roughness=0.58)
    MATS["dark"] = m(f"{PRE}_structure_dark", (0.055, 0.058, 0.062), roughness=0.5,
                     metallic=0.55)
    MATS["metal"] = m(f"{PRE}_bare_metal", (0.3, 0.3, 0.31), roughness=0.36, metallic=0.9)
    MATS["accent"] = m(f"{PRE}_accent_paint", (0.28, 0.12, 0.045), roughness=0.6)
    MATS["hazard"] = m(f"{PRE}_hazard", (0.4, 0.29, 0.05), roughness=0.62)
    MATS["pad"] = m(f"{PRE}_pad_deck", (0.095, 0.095, 0.1), roughness=0.72, metallic=0.2)
    MATS["mli"] = m(f"{PRE}_mli_white", (0.5, 0.49, 0.455), roughness=0.86)
    MATS["mli_gold"] = m(f"{PRE}_mli_gold", (0.6, 0.39, 0.12), roughness=0.3, metallic=1.0)
    MATS["mli_silver"] = m(f"{PRE}_mli_silver", (0.6, 0.6, 0.61), roughness=0.26, metallic=1.0)
    MATS["radiator"] = m(f"{PRE}_radiator", (0.47, 0.475, 0.48), roughness=0.45, metallic=0.15)
    MATS["rust"] = m(f"{PRE}_rust", (0.15, 0.07, 0.03), roughness=0.7)
    MATS["solar"] = m(f"{PRE}_solar_panel", (0.01, 0.018, 0.045), roughness=0.2, metallic=0.5)
    glow = (0.03, 0.028, 0.025)
    MATS["window"] = m(f"{PRE}_window_warm", glow, roughness=0.25,
                       emission=(1.0, 0.6, 0.28), emission_strength=2.0)
    MATS["window_dim"] = m(f"{PRE}_window_amber", glow, roughness=0.25,
                           emission=(1.0, 0.5, 0.18), emission_strength=1.1)
    MATS["window_cool"] = m(f"{PRE}_window_cool", glow, roughness=0.25,
                            emission=(0.7, 0.82, 1.0), emission_strength=1.5)
    MATS["glass"] = m(f"{PRE}_glass_dark", (0.012, 0.016, 0.02), roughness=0.1)
    MATS["nav_red"] = m(f"{PRE}_nav_red", glow, roughness=0.3,
                        emission=(1.0, 0.08, 0.03), emission_strength=6.0)
    MATS["nav_green"] = m(f"{PRE}_nav_green", glow, roughness=0.3,
                          emission=(0.08, 1.0, 0.22), emission_strength=6.0)
    MATS["nav_white"] = m(f"{PRE}_nav_white", glow, roughness=0.3,
                          emission=(1.0, 0.97, 0.92), emission_strength=4.0)
    MATS["flood"] = m(f"{PRE}_floodlight", glow, roughness=0.3,
                      emission=(1.0, 0.95, 0.85), emission_strength=4.5)
    for k in FLAT:
        MATS[k].use_backface_culling = False


# ---------------------------------------------------------------- helpers (as gen_station)
def polar(r, a, z=0.0):
    return V((r * math.cos(a), r * math.sin(a), z))


def radial(a):
    return V((math.cos(a), math.sin(a), 0.0))


def tangent(a):
    return V((-math.sin(a), math.cos(a), 0.0))


def axis_radial(a):
    """Cylinder axis (local Z) pointing radially out at bearing a."""
    return Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "Y")


def axis_tangent(a):
    """Cylinder axis (local Z) along the tangent at bearing a; local X radially out."""
    return Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(-math.pi / 2, 4, "X")


def up_for(n_up):
    """Label up direction that never reads upside down from the south (-Y) camera."""
    return n_up if n_up.y >= -1e-3 else -n_up


def label(text, centre, normal, up, h, colour, opacity=0.85):
    DECALS.append(st.decal(CELL[text], centre, normal, up, h, colour, opacity))


strut = parts.strut
pipe = parts.pipe
window = parts.window
pick_lit = parts.pick_lit


def nav(p, c, mat, s=0.5):
    p.box(c - V((0, 0, s * 0.45)), (s * 0.7, s * 0.7, s * 0.4), "dark", bevel=0.0)
    p.box(c, (s, s, s * 0.6), mat, bevel=0.0)


def beacon_mast(p, base, h, mat, s=0.5):
    """Thin mast with a guard cage and a beacon on top."""
    base = V(base)
    p.cyl(base + UP * h / 2, 0.14, 0.07, h, "metal", segs=6)
    p.box(base + UP * 0.15, (0.6, 0.6, 0.3), "dark", bevel=0.0)
    nav(p, base + UP * (h + s * 0.3), mat, s)


def truss(p, p0, p1, w, h, n, mat, chord=0.22, brace=0.13, up=UP, diag=True):
    """Open square truss from p0 to p1: 4 longerons, n bays, frames and side diagonals."""
    p0, p1 = V(p0), V(p1)
    x = (p1 - p0).normalized()
    z = (up - x * up.dot(x)).normalized()
    y = z.cross(x)
    for cy, cz in [(sy * w / 2, sz * h / 2) for sy in (-1, 1) for sz in (-1, 1)]:
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
    up = UP * hgt
    for a, b in zip(pts, pts[1:]):
        strut(p, a + up, b + up, t, t, mat)
    for a in pts:
        strut(p, a, a + up, t, t, mat)


def radiator_fin(p, c, along, length, height, t=0.12):
    along = V(along).normalized()
    rm = Matrix((along, UP.cross(along), UP)).transposed().to_4x4()
    p.box(c, (length, t, height), "radiator", r=rm, bevel=0.0)
    p.tube(c + UP * height / 2 - along * length / 2, c + UP * height / 2 + along * length / 2,
           0.09, 0.09, "metal", segs=5)


def hazard_band(p, c0, c1, w, h, up=UP, pitch=0.9):
    """Alternating hazard / dark blocks from c0 to c1 (painted kerb, w x h section)."""
    c0, c1 = V(c0), V(c1)
    d = c1 - c0
    n = max(2, int(d.length / pitch))
    for i in range(n):
        a, b = c0.lerp(c1, i / n), c0.lerp(c1, (i + 1) / n)
        p.beam(a, b, w, h, "hazard" if i % 2 == 0 else "dark", up=up)


def can_module(p, rng, c, axis_m, length, r, mode, paint="hull", segs=16, win_sides=(1, -1),
               win_n=None, bands=2):
    """Prefab pressurised can: lathe along local Z (axis_m: local X = window side 'out'),
    end domes, collar bands, stringer straps, window rows on the local +-X sides."""
    L = length / 2
    prof = [(0.0, -L), (r * 0.55, -L), (r * 0.85, -L + 0.25), (r, -L + 0.7),
            (r, L - 0.7), (r * 0.85, L - 0.25), (r * 0.55, L), (0.0, L)]
    mt = {0: "dark", 1: "hull2", 2: "hull2", 3: paint, 4: "hull2", 5: "hull2", 6: "dark"}
    m = Matrix.Translation(c) @ axis_m
    p.lathe(prof, segs, lambda i, j: mt[j], matrix=m, start=math.pi / segs)
    r3 = axis_m.to_3x3()
    ax, out, side = r3 @ V((0, 0, 1)), r3 @ V((1, 0, 0)), r3 @ V((0, 1, 0))
    for k in range(bands):
        t = -L + 0.7 + (length - 1.4) * (k + 1) / (bands + 1)
        p.cyl(c + ax * t, r + 0.07, r + 0.07, 0.3, "dark", segs=segs, axis_rot=axis_m)
    for ang in (math.pi / 2, -math.pi / 2):       # stringer straps top/bottom-ish
        d = (out * math.cos(ang) + side * math.sin(ang))
        p.beam(c + d * (r + 0.03) - ax * (L - 0.8), c + d * (r + 0.03) + ax * (L - 0.8), 0.22,
               0.08, "dark", up=d)
    rf = r * math.cos(math.pi / segs)
    n = win_n or max(2, int((length - 2.0) / 1.1))
    for sd in win_sides:
        for w in range(n):
            t = -L + 1.0 + (length - 2.0) * (w + 0.5) / n
            window(p, c + ax * t + out * sd * rf, out * sd, side if abs(side.z) > 0.5 else UP,
                   0.5, 0.55, pick_lit(rng, mode))
    return ax, out, side


# ---------------------------------------------------------------- core (static)
def build_core(rng):
    p = parts.PanelPart("station_core", MATS)
    segs = 16
    prof = [(0, -13.0), (2.0, -13.0), (2.6, -12.0), (5.0, -9.5), (7.5, -7.0), (8.5, -5.5),
            (8.5, -1.6), (8.5, 1.6), (8.5, 4.0), (7.8, 5.0), (6.0, 5.2), (5.6, 5.8),
            (5.6, 8.6), (5.0, 9.4), (3.0, 10.0), (0, 10.0)]
    edge = {0: "dark", 1: "metal", 2: "hull2", 3: "hull2", 4: "dark", 5: "hull", 6: "dark",
            7: "hull", 8: "hull2", 9: "pad", 10: "dark", 11: "hull3", 12: "hull2", 13: "hull",
            14: "dark"}
    panel = [rng.random() < 0.35 for _ in range(segs)]

    def core_mat(i, j):
        k = edge[j]
        if k == "hull" and panel[i]:
            return "hull3" if i % 3 else "accent"
        return k
    p.lathe(prof, segs, core_mat, start=math.pi / segs)
    rf = 8.5 * math.cos(math.pi / segs)
    # bolted rib plates on every facet edge (prefab look)
    for i in range(segs):
        a = 2 * math.pi * i / segs + math.pi / segs
        p.box(polar(8.48, a, 0.0), (0.4, 0.5, 11.0), "dark", rot_z=a, bevel=0.0)
    # spoke bearing band
    brg = [(8.4, -1.5), (9.3, -1.4), (9.3, -0.5), (9.15, 0.0), (9.3, 0.5), (9.3, 1.4),
           (8.4, 1.5)]
    p.lathe(brg, 24, lambda i, j: "metal" if j in (2, 3) else "dark")
    for i in range(8):
        a = 2 * math.pi * (i + 0.5) / 8
        p.box(polar(9.0, a, 1.6), (0.8, 0.3, 0.22), "dark", rot_z=a, bevel=0.0)
    # window rows on the drum facets
    for z, mode in ((3.0, "hab"), (-3.4, "work")):
        for i in range(segs):
            a = 2 * math.pi * i / segs                    # facet centre (lathe start pi/16)
            if i % 4 == 1 and z > 0:
                continue                                  # RCS / conduit facets
            for off in (-0.9, 0.9):
                window(p, polar(rf, a, z) + tangent(a) * off, radial(a), UP, 0.55, 0.75,
                       pick_lit(rng, mode))
    # conduits and RCS on the drum
    for k in range(4):
        a = 2 * math.pi * (4 * k + 1) / segs
        for z0, z1 in ((-5.4, -1.7), (1.7, 3.9)):
            p.tube(polar(rf + 0.22, a, z0), polar(rf + 0.22, a, z1), 0.15, 0.15, "metal", segs=6)
        parts.rcs_quad(p, polar(rf + 0.2, a, 3.6), radial(a), "hull2", "dark", s=0.55, fwd=UP)
        SCORCH.append((*polar(rf, a, 3.6), 1.4))
    for k in range(3):
        a = 2 * math.pi * (4 * k + 2) / segs
        label("FS-1" if k == 0 else "FWD", polar(rf + 0.01, a, 1.0 + 0.0), radial(a), UP, 0.55,
              INK_DARK)
        label("#BAR", polar(rf + 0.01, a, 0.3), radial(a), UP, 0.22, ID_COLS[k])
    # ledge (z 5.2): equipment boxes, radiator fins, rail
    for i in range(6):
        a = 2 * math.pi * (i + 0.15) / 6
        w, d, h = rng.uniform(0.9, 1.4), rng.uniform(0.7, 1.0), rng.uniform(0.5, 0.9)
        p.box(polar(7.0, a, 5.2 + h / 2), (d, w, h), rng.choice(["hull2", "hull3", "dark"]),
              rot_z=a, bevel=0.06)
    for k in range(2):
        a = math.radians(160 + 180 * k)
        radiator_fin(p, polar(7.0, a, 6.4), tangent(a), 2.4, 2.2)
    rail = [polar(7.6, 2 * math.pi * i / 16 + math.pi / 16, 4.98) for i in range(17)]
    handrail(p, rail, hgt=0.75, t=0.06)

    # prefab hab cans bolted radially to the tower (cantilevered over the drum)
    for k, b in enumerate((100.0, 220.0, 340.0)):
        a = math.radians(b)
        c = polar(9.6, a, 6.9)
        # local Z radially out, local X tangent (window sides), local Y up
        prof_m = (Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "Y")
                  @ Matrix.Rotation(math.pi / 2, 4, "Z"))
        can_module(p, rng, c, prof_m, 8.0, 1.6, "hab", paint="hull3" if k == 1 else "hull",
                   segs=12, win_n=5)
        # end hatch + docking ring on the outer end
        p.cyl(polar(13.65, a, 6.9), 1.0, 1.0, 0.3, "metal", segs=12, axis_rot=axis_radial(a))
        p.cyl(polar(13.45, a, 6.9), 1.25, 1.25, 0.3, "hazard", segs=12, axis_rot=axis_radial(a))
        # bolted saddle + diagonal brace down to the drum shoulder
        p.box(polar(8.0, a, 5.6), (1.2, 2.4, 0.6), "dark", rot_z=a, bevel=0.0)
        for sd in (-1, 1):
            p.beam(polar(8.4, a, 4.4) + tangent(a) * sd * 0.9,
                   polar(12.4, a, 5.6) + tangent(a) * sd * 0.9, 0.22, 0.22, "rust")
        p.box(polar(11.0, a, 8.55), (2.4, 1.2, 0.18), "dark", rot_z=a, bevel=0.0)
        label(f"M-0{k + 1}", polar(11.0, a, 8.53) + UP * 0.01, UP, up_for(tangent(a)), 0.5,
              INK_DARK)
        label("#BAR", polar(9.0, a, 8.53), UP, up_for(tangent(a)), 0.25, ID_COLS[k + 2])
        nav(p, polar(13.3, a, 8.6), "nav_white", 0.28)

    # tower top: mast, gimbal, big comms dish aimed back toward home
    p.cyl(V((0, 0, 10.1)), 2.6, 2.6, 0.4, "dark", segs=16)
    p.box(V((0, 0, 10.9)), (3.0, 3.0, 1.2), "hull2", bevel=0.08)
    for i in range(12):
        a = 2 * math.pi * (i + 0.5) / 12
        window(p, polar(5.6 * math.cos(math.pi / 16), a, 7.4), radial(a), UP, 0.45, 0.55,
               "window_cool" if rng.random() < 0.6 else None)
    lattice = V((0, 0, 11.5))
    wk.lattice_mast(p, lattice, 15.0, 1.1, 0.6, 3, "dark", chord=0.26, brace=0.13)
    p.cyl(V((0, 0, 15.3)), 0.9, 0.9, 0.8, "metal", segs=12)
    bear, elev = math.radians(DISH_BEARING), math.radians(DISH_ELEV)
    n = V((math.cos(elev) * math.cos(bear), math.cos(elev) * math.sin(bear), math.sin(elev)))
    q = n.to_track_quat("Z", "Y").to_matrix().to_4x4()
    centre = V((0, 0, 16.8)) - n * 1.2
    dish_m = Matrix.Translation(centre) @ q
    R = 6.2
    dish_prof = [(0, 0.0), (R * 0.32, 0.22), (R * 0.65, 0.95), (R * 0.95, 2.2), (R, 2.25),
                 (R * 0.97, 1.9), (R * 0.65, 0.6), (R * 0.26, -0.25), (0, -0.4)]
    dm = {0: "hull", 1: "hull", 2: "hull", 3: "hazard", 4: "dark", 5: "dark", 6: "dark",
          7: "dark"}
    p.lathe(dish_prof, 28, lambda i, j: dm[j], matrix=dish_m)
    # back ribs and yoke
    for k in range(6):
        aa = k * math.pi / 3
        p.beam(dish_m @ V((R * 0.3 * math.cos(aa), R * 0.3 * math.sin(aa), -0.2)),
               dish_m @ V((R * 0.9 * math.cos(aa), R * 0.9 * math.sin(aa), 1.75)), 0.18, 0.18,
               "dark")
    p.cyl(dish_m @ V((0, 0, -0.9)), 1.0, 1.2, 1.2, "hull2", segs=12, axis_rot=q)
    p.beam(V((0, 0, 15.3)), dish_m @ V((0, 0, -1.4)), 0.7, 0.7, "dark")
    feed = dish_m @ V((0, 0, 5.4))
    for k in range(4):
        aa = k * math.pi / 2 + math.pi / 4
        p.beam(dish_m @ V((R * 0.9 * math.cos(aa), R * 0.9 * math.sin(aa), 2.0)), feed,
               0.12, 0.12, "metal")
    p.cyl(feed, 0.45, 0.3, 0.9, "hull2", segs=8, axis_rot=q)
    nav(p, feed + n * 0.6, "nav_red", 0.35)
    for k in range(4):
        aa = k * math.pi / 2
        p.box(dish_m @ V((R * 1.0 * math.cos(aa), R * 1.0 * math.sin(aa), 2.3)),
              (0.32, 0.32, 0.22), "nav_white", r=q, bevel=0.0)
    label("COMMS", dish_m @ V((0, 0, -0.42)), -n, up_for(V((0, 1, 0))), 0.9, INK_LIGHT, 0.5)
    # secondary antennas, beacon
    p.cyl(V((1.6, 1.2, 13.0)), 0.12, 0.05, 5.0, "metal", segs=6)
    nav(p, V((1.6, 1.2, 15.65)), "nav_red", 0.35)
    parts.dish(p, V((-1.8, 1.6, 12.0)), 0.9, V((-0.3, 0.7, 0.6)), "hull", "metal", depth=0.28)
    parts.dish(p, V((1.7, -1.7, 11.9)), 0.7, V((0.6, -0.5, 0.7)), "hull", "metal", depth=0.22)

    # underside: hanging tanks (avoid spine 15/195 and bay trusses 105/285), thrust cone
    for i, b in enumerate((60, 150, 240, 330)):
        a = math.radians(b)
        foil = "mli_gold" if i % 2 == 0 else "mli_silver"
        p.cyl(polar(6.1, a, -10.6), 1.35, 1.35, 3.4, foil, segs=12)
        p.cyl(polar(6.1, a, -8.65), 1.35, 0.9, 0.5, "hull2", segs=12)
        p.cyl(polar(6.1, a, -12.55), 0.9, 1.35, 0.5, "hull2", segs=12)
        p.cyl(polar(6.1, a, -10.6), 1.41, 1.41, 0.18, "dark", segs=12)
        label(("LOX", "N2", "H2O", "LOX")[i], polar(6.1 + 1.36, a, -10.0), radial(a), UP, 0.4,
              INK_DARK, 0.7)
    p.cyl(V((0, 0, -13.5)), 1.9, 1.4, 1.0, "metal", segs=16)
    p.cyl(V((0, 0, -14.1)), 1.4, 1.0, 0.3, "dark", segs=16)
    nav(p, V((0, 0, -14.5)), "nav_white", 0.4)
    SCORCH.append((0.0, 0.0, -13.2, 3.0))
    return p


# ---------------------------------------------------------------- ring (spins)
def build_ring(rng):
    p = parts.PanelPart("station_ring", MATS)
    step = 2 * math.pi / RING_NODES
    chord = 2 * RING_R * math.sin(step / 2)
    node_r = 2.8
    can_r = 2.1
    m_id = 0
    for s in range(RING_NODES):
        a0 = s * step
        am = a0 + step / 2
        c = polar(RING_R * math.cos(step / 2), am)
        if s in OPEN_SEGS:
            # under construction: open truss, crawl tunnel, scaffolding, work lights
            pa, pb = polar(RING_R, a0), polar(RING_R, a0 + step)
            d = (pb - pa).normalized()
            pa, pb = pa + d * (node_r - 0.3), pb - d * (node_r - 0.3)
            truss(p, pa, pb, 3.4, 3.4, 5, "rust" if s == OPEN_SEGS[0] else "metal",
                  chord=0.24, brace=0.14)
            p.tube(pa, pb, 0.85, 0.85, "hull2", segs=10)
            for k in range(4):
                q = pa.lerp(pb, (k + 0.5) / 4)
                p.cyl(q, 1.0, 1.0, 0.3, "dark", segs=10,
                      axis_rot=d.to_track_quat("Z", "Y").to_matrix().to_4x4())
            # one prefab can half fitted on the truss, the rest of the slot open
            half = pa.lerp(pb, 0.3)
            n_out = radial(am)
            p.box(half + UP * 2.1, (2.4, 4.4, 0.8), "hull", rot_z=am, bevel=0.05)
            for sd in (-1, 1):
                hazard_band(p, pa + UP * 1.85 + n_out * sd * 1.75,
                            pb + UP * 1.85 + n_out * sd * 1.75, 0.18, 0.18)
            for k in (0.25, 0.75):
                q = pa.lerp(pb, k)
                p.box(q + UP * 2.3, (0.5, 0.5, 0.4), "dark", rot_z=am, bevel=0.0)
                p.box(q + UP * 2.6, (0.36, 0.36, 0.2), "flood", rot_z=am, bevel=0.0)
            continue
        m_id += 1
        mode = rng.choice(["hab", "hab", "hab", "work", "store"])
        paint = "hull3" if rng.random() < 0.35 else ("accent" if rng.random() < 0.12 else "hull")
        length = chord - 2 * node_r + 1.2
        can_module(p, rng, c, axis_tangent(am), length, can_r, mode, paint=paint, segs=16,
                   bands=2)
        # top: hatch, label, equipment
        top = c + UP * can_r * math.cos(math.pi / 16)
        tn = tangent(am)
        p.box(top + tn * 1.4 + UP * 0.08, (1.1, 1.1, 0.16), "hull2", rot_z=am, bevel=0.1)
        label(f"M-{m_id + 3:02d}", top - tn * 0.6 + UP * 0.02, UP, up_for(tn), 0.55, INK_DARK)
        if m_id % 3 == 1:
            label("NO STEP", top + tn * 2.6, UP, up_for(tn), 0.28, INK_DARK, 0.7)
        if m_id % 2 == 0:
            label("#BAR", top - tn * 2.6, UP, up_for(tn), 0.28, ID_COLS[m_id % len(ID_COLS)])
        if mode in ("work", "store") or m_id == 5:
            # strapped MLI tank on top
            tc = top + UP * 1.15
            prof = [(0.0, -2.0), (0.7, -1.95), (1.0, -1.6), (1.0, 1.6), (0.7, 1.95), (0.0, 2.0)]
            tm = {0: "mli_gold", 1: "dark", 2: "mli", 3: "dark", 4: "mli_gold"}
            p.lathe(prof, 12, lambda i, j: tm[j], matrix=Matrix.Translation(tc) @ axis_tangent(am))
            for t in (-1.0, 1.0):
                p.box(tc + tn * t - UP * 0.5, (2.2, 0.3, 1.2), "dark", rot_z=am, bevel=0.0)
        else:
            radiator_fin(p, top + UP * 0.75 - tn * 1.0, tn, 2.0, 1.3)
        p.box(c - UP * (can_r + 0.25), (1.2, 3.6, 0.5), "dark", rot_z=am, bevel=0.0)
        p.tube(c + radial(am) * 0.9 + UP * (can_r + 0.05) - tn * (length / 2 - 0.6),
               c + radial(am) * 0.9 + UP * (can_r + 0.05) + tn * (length / 2 - 0.6), 0.12, 0.12,
               "metal", segs=5)

    # junction nodes
    for k in range(RING_NODES):
        a = k * step
        c = polar(RING_R, a)
        big = k in SPOKES
        rr = node_r + (0.2 if big else 0.0)
        prof = [(0.0, -2.9), (rr - 0.4, -2.9), (rr, -2.4), (rr, -0.6), (rr, 0.6), (rr, 2.4),
                (rr - 0.4, 2.9), (0.9, 2.9), (0.9, 3.3), (0.0, 3.3)]
        jm = {0: "dark", 1: "hull2", 2: "hull2", 3: "dark" if big else "hull3", 4: "hull2",
              5: "hull2", 6: "hull2", 7: "dark", 8: "dark"}
        p.lathe(prof, 14, lambda i, j: jm[j], matrix=Matrix.Translation(c), start=math.pi / 14)
        for i in range(10):
            aa = 2 * math.pi * (i + 0.5) / 10
            dv = V((math.cos(aa), math.sin(aa), 0))
            window(p, c + dv * rr * math.cos(math.pi / 14) + UP * 1.45, dv, UP, 0.42, 0.42,
                   pick_lit(rng, "work"))
        nav(p, c + UP * 3.45, "nav_white" if not big else "nav_red", 0.3)
        label("#BAR", c + UP * 2.92 + tangent(a) * 1.4, UP, up_for(radial(a)), 0.3,
              ID_COLS[k % len(ID_COLS)])
        if big:
            rc = polar(RING_R + rr + 0.1, a, 1.6)
            parts.rcs_quad(p, rc, radial(a), "hull2", "dark", s=0.45, fwd=UP)
            SCORCH.append((*rc, 1.2))

    # spokes: pressurised tube + side truss + conduit
    for k in SPOKES:
        a = k * step
        r0, r1 = 9.3, RING_R - node_r - 0.1
        mid = (r0 + r1) / 2
        p.cyl(polar(mid, a), 0.9, 0.9, r1 - r0 + 0.4, "hull", segs=10, axis_rot=axis_radial(a))
        for j in range(3):
            p.cyl(polar(r0 + 1.5 + j * 3.0, a), 1.1, 1.1, 0.4, "dark", segs=10,
                  axis_rot=axis_radial(a))
        p.cyl(polar(9.7, a), 1.35, 1.35, 0.7, "metal", segs=12, axis_rot=axis_radial(a))
        off = tangent(a) * 1.7
        truss(p, polar(9.8, a) + off, polar(r1 + 0.5, a) + off, 0.8, 0.8, 5, "metal",
              chord=0.16, brace=0.09)
        p.tube(polar(9.3, a, 1.05), polar(r1 + 0.4, a, 1.05), 0.12, 0.12, "accent", segs=5)
        for j in range(2):
            window(p, polar(11.8 + j * 3.0, a) - tangent(a) * 0.9, -tangent(a), UP, 0.4, 0.4,
                   pick_lit(rng, "work"))
    return p


# ---------------------------------------------------------------- docks + spine
def build_docks(rng):
    p = parts.PanelPart("station_docks", MATS)
    for n_pad, a_deg in enumerate(DOCK_DEG):
        a = math.radians(a_deg)
        t = tangent(a)
        rd = radial(a)
        collar_r = PAD_R - 6.5
        # docking spine under the hub: heavy truss + pressurised tube, approach lights
        truss(p, polar(7.4, a, SPINE_Z), polar(PAD_R - 1.0, a, SPINE_Z), 3.0, 2.2, 10,
              "metal" if n_pad == 0 else "rust", chord=0.3, brace=0.17)
        p.cyl(polar((8.0 + collar_r) / 2, a, SPINE_Z + 1.45), 1.05, 1.05, collar_r - 8.0,
              "hull", segs=10, axis_rot=axis_radial(a))
        for k in range(7):
            rr = 9.5 + k * (collar_r - 11.0) / 6
            p.cyl(polar(rr, a, SPINE_Z + 1.45), 1.22, 1.22, 0.35,
                  "hazard" if k in (0, 6) else "dark", segs=10, axis_rot=axis_radial(a))
        for k in range(8):
            rr = 10.0 + k * 3.6
            for sd in (-1, 1):
                p.box(polar(rr, a, SPINE_Z - 1.2) + t * sd * 1.5, (0.3, 0.3, 0.16),
                      "window_dim" if k % 2 else "nav_white", rot_z=a, bevel=0.0)
        for k in range(5):
            window(p, polar(12.0 + k * 3.6, a, SPINE_Z + 1.45) + t * 1.03, t, UP, 0.35, 0.4,
                   pick_lit(rng, "work"))
            window(p, polar(12.0 + k * 3.6, a, SPINE_Z + 1.45) - t * 1.03, -t, UP, 0.35, 0.4,
                   pick_lit(rng, "hab"))
        p.tube(polar(8.0, a, SPINE_Z - 0.6) + t * 1.2, polar(collar_r, a, SPINE_Z - 0.6) + t * 1.2,
               0.14, 0.14, "accent", segs=5)
        p.tube(polar(8.0, a, SPINE_Z - 0.6) - t * 1.2, polar(collar_r, a, SPINE_Z - 0.6) - t * 1.2,
               0.12, 0.12, "metal", segs=5)
        p.box(polar(7.8, a, SPINE_Z), (1.6, 4.0, 3.2), "dark", rot_z=a, bevel=0.06)
        # riser from the spine up into the collar node
        z0, z1 = SPINE_Z + 1.45, -1.8
        p.cyl(polar(collar_r, a, (z0 + z1) / 2), 1.2, 1.2, z1 - z0 + 0.6, "hull2", segs=10)
        p.cyl(polar(collar_r, a, SPINE_Z + 1.45), 1.5, 1.5, 2.8, "dark", segs=12)
        # walkway arm from the frame ring to the collar
        truss(p, polar(FRAME_R0 + 0.6, a, -0.9), polar(collar_r - 2.0, a, -0.9), 2.4, 1.5, 2,
              "metal", chord=0.24, brace=0.14)
        p.cyl(polar((FRAME_R1 + collar_r - 2.0) / 2, a, 0.9), 0.95, 0.95,
              collar_r - 2.0 - FRAME_R1 + 0.6, "hull", segs=10, axis_rot=axis_radial(a))
        for k in range(3):
            window(p, polar(FRAME_R1 + 0.9 + k * 1.1, a, 0.95) + t * 0.95, t, UP, 0.35, 0.42,
                   pick_lit(rng, "hab"))
        # docking collar node
        prof = [(0.0, -1.8), (2.2, -1.8), (2.5, -1.4), (2.5, 1.4), (2.2, 1.8), (0.0, 1.8)]
        cm = {0: "dark", 1: "hull2", 2: "hull3", 3: "hull2", 4: "dark"}
        cc = polar(collar_r, a)
        p.lathe(prof, 14, lambda i, j: cm[j], matrix=Matrix.Translation(cc))
        p.cyl(cc + UP * 1.95, 1.4, 1.4, 0.3, "metal", segs=12)
        p.cyl(cc + UP * 0.0, 2.56, 2.56, 0.35, "hazard", segs=14)
        for i in range(8):
            aa = a + math.pi / 2 + (i - 3.5) * 0.3
            dv = V((math.cos(aa), math.sin(aa), 0))
            window(p, cc + dv * 2.5 + UP * 0.8, dv, UP, 0.38, 0.45, pick_lit(rng, "work"))
        SCORCH.append((*polar(collar_r + 2.0, a, 0.5), 2.2))
        # pad: octagonal platform centred at PAD_R (same profile as the home pads)
        c = polar(PAD_R, a, 0.2)
        mtx = Matrix.Translation(c) @ Matrix.Rotation(a + math.pi / 8, 4, "Z")
        prof = [(0, 0.7), (4.6, 0.7), (5.4, 0.7), (6.6, 0.7), (7.2, 0.4), (7.2, -0.4),
                (6.4, -0.9), (3.0, -1.4), (0, -1.6)]
        pad_mats = {0: "pad", 1: "hazard", 2: "pad", 3: "hazard", 4: "dark", 5: "dark",
                    6: "dark", 7: "dark"}
        p.lathe(prof, 8, lambda i, j: pad_mats[j], matrix=mtx)
        deck = c + UP * 0.7
        label(f"DOCK {n_pad + 1}", deck, UP, V((0, 1, 0)), 0.95, INK_LIGHT, 0.8)
        label("#CHEV", deck - rd * 3.2, UP, up_for(t), 0.55, HAZ_INK, 0.75)
        label("KEEP CLEAR", deck + rd * 3.4, UP, up_for(t), 0.42, HAZ_INK, 0.7)
        for k in range(8):
            ang = a + math.pi / 8 + k * math.pi / 4
            lp = c + V((math.cos(ang), math.sin(ang), 0)) * 6.9 + UP * 0.55
            p.box(lp, (0.3, 0.3, 0.16), "window_dim", rot_z=ang, bevel=0.0)
        for k in range(4):
            ang = a + math.pi / 4 + k * math.pi / 2
            d = V((math.cos(ang), math.sin(ang), 0))
            base = c + d * 6.2 + UP * 0.5
            p.beam(base, base + UP * 2.4, 0.16, 0.16, "metal")
            p.box(base + UP * 2.5 - d * 0.15, (0.55, 0.55, 0.32), "dark", rot_z=ang, bevel=0.0)
            p.box(base + UP * 2.42 - d * 0.32, (0.08, 0.42, 0.22), "flood", rot_z=ang, bevel=0.0)
        nav(p, c + rd * 7.0 + UP * 0.6, "nav_red" if n_pad == 0 else "nav_green", 0.45)
        # pad support from the spine end
        p.cyl(c + UP * -2.4, 1.6, 0.9, 2.0, "metal", segs=8)
        p.cyl(polar(PAD_R - 1.0, a, SPINE_Z + 1.6), 1.1, 1.1, 5.0, "dark", segs=8)
        # control cab beside the collar (prefab box with a sloped visor)
        tc = cc + t * 3.7
        p.box(tc + UP * 1.1, (2.2, 2.0, 2.4), "hull3", rot_z=a, bevel=0.08)
        for nn in (rd, -rd, t, -t):
            side = nn.cross(UP).normalized()
            for wk_ in (-0.45, 0.45):
                window(p, tc + UP * 1.85 + nn * 1.02 + side * wk_, nn, UP, 0.6, 0.4,
                       "window_cool" if rng.random() < 0.6 else None)
        p.box(tc + UP * 2.45, (2.5, 2.3, 0.3), "dark", rot_z=a, bevel=0.0)
        beacon_mast(p, tc + UP * 2.6, 2.2, "nav_red", 0.3)
    return p


# ---------------------------------------------------------------- solar
def build_solar(rng):
    p = parts.PanelPart("station_solar", MATS)
    for wing, a_deg in enumerate(SOLAR_DEG):
        a = math.radians(a_deg)
        t, rd = tangent(a), radial(a)
        p.cyl(polar(29.0, a), 1.6, 1.6, 3.0, "hull2", segs=12, axis_rot=axis_radial(a))
        p.cyl(polar(27.9, a), 1.9, 1.9, 0.5, "dark", segs=12, axis_rot=axis_radial(a))
        p.cyl(polar(30.7, a), 1.1, 1.1, 0.6, "metal", segs=12, axis_rot=axis_radial(a))
        label("PWR", polar(29.0, a, 1.62), UP, up_for(t), 0.5, INK_LIGHT, 0.7)
        # support post down to the lower strut level (keeps the frame braced)
        p.box(polar(27.0, a, -4.6), (1.4, 1.4, 7.4), "dark", rot_z=a, bevel=0.05)
        truss(p, polar(31.0, a), polar(58.5, a), 1.0, 1.0, 8, "metal", chord=0.18, brace=0.1)
        p.tube(polar(31.0, a, 0.62), polar(58.0, a, 0.62), 0.1, 0.1, "dark", segs=5)
        p.cyl(polar(58.9, a), 0.85, 0.85, 1.4, "hull2", segs=10)
        nav(p, polar(58.9, a, 0.95), "nav_red" if wing == 0 else "nav_green", 0.5)
        for k in range(3):
            r = 37.0 + k * 7.0
            for sgn in (-1, 1):
                if wing == 1 and k == 2 and sgn == 1:
                    # a blanket never fitted: bare frame only (frontier station)
                    pc = polar(r, a, 0.15) + t * sgn * 5.4
                    p.box(polar(r, a, 0.0) + t * sgn * 1.0, (0.3, 1.1, 0.25), "metal", rot_z=a,
                          bevel=0.0)
                    for sx in (-1, 1):
                        p.box(pc + rd * sx * 2.95 + UP * 0.05, (0.22, 8.2, 0.1), "metal",
                              rot_z=a, bevel=0.0)
                        p.box(pc + t * sx * 3.95 + UP * 0.05, (6.1, 0.22, 0.1), "metal",
                              rot_z=a, bevel=0.0)
                    continue
                pc = polar(r, a, 0.15) + t * sgn * 5.4
                p.box(polar(r, a, 0.0) + t * sgn * 1.0, (0.3, 1.1, 0.25), "metal", rot_z=a,
                      bevel=0.0)
                p.box(pc, (6.1, 8.2, 0.08), "dark", rot_z=a, bevel=0.0)
                p.box(pc + UP * 0.07, (5.5, 7.5, 0.04), "solar", rot_z=a, bevel=0.0)
                for sx in (-1, 1):
                    p.box(pc + rd * sx * 2.95 + UP * 0.08, (0.22, 8.2, 0.1), "metal", rot_z=a,
                          bevel=0.0)
                    p.box(pc + t * sx * 3.95 + UP * 0.08, (6.1, 0.22, 0.1), "metal", rot_z=a,
                          bevel=0.0)
                p.box(pc + UP * 0.1, (0.1, 7.5, 0.06), "metal", rot_z=a, bevel=0.0)
    return p


# ---------------------------------------------------------------- frame, bays, cargo
def bay_collar(p, a, k):
    """Station half of the docking collar (as gen_station.bay_collar, radii relative to
    BAY_R); its outer face lies at r = BAY_R."""
    t = tangent(a)
    ac = BAY_R - 2.4
    p.box(polar(ac, a, 0.0), (3.2, 13.0, 11.0), "hull3" if k % 2 else "hull", rot_z=a,
          bevel=0.03)
    p.box(polar(ac, a, 5.62), (3.0, 12.4, 0.25), "hull2", rot_z=a, bevel=0.0)
    p.box(polar(ac, a, -5.6), (3.4, 13.2, 0.3), "dark", rot_z=a, bevel=0.0)
    for sgn in (-1, 1):
        for zz in (-3.0, 0.0, 3.0):
            p.box(polar(ac, a, zz) + t * sgn * 6.55, (2.8, 0.18, 0.5), "dark", rot_z=a,
                  bevel=0.0)
        p.tube(polar(ac - 1.5, a, -5.0) + t * sgn * 5.8, polar(ac - 1.5, a, 5.0) + t * sgn * 5.8,
               0.15, 0.15, "metal", segs=5)
        p.box(polar(ac, a, 5.9) + t * sgn * 3.4, (3.3, 0.3, 0.3), "dark", rot_z=a, bevel=0.0)
        p.box(polar(ac - 0.9, a, 5.75) + t * sgn * 5.2, (1.0, 1.4, 0.5), "hull2", rot_z=a,
              bevel=0.08)
        p.box(polar(BAY_R - 0.85, a, 0.0) + t * sgn * 6.25, (0.3, 0.5, 11.0), "dark", rot_z=a,
              bevel=0.0)
        p.box(polar(BAY_R - 0.85, a, sgn * 5.25), (0.3, 13.0, 0.5), "dark", rot_z=a, bevel=0.0)
        # hazard kerbs down the face edges (frontier paint job)
        hazard_band(p, polar(BAY_R - 0.7, a, -4.7) + t * sgn * 6.55,
                    polar(BAY_R - 0.7, a, 4.7) + t * sgn * 6.55, 0.2, 0.2, up=t, pitch=0.8)
    pipe(p, polar(ac - 1.35, a, 5.95) - t * 6.0, polar(ac - 1.35, a, 5.95) + t * 6.0, 0.14, "metal")
    label(f"BAY {k + 1}", polar(ac + 0.3, a, 5.75), UP, up_for(t), 0.95, INK_DARK)
    label("#BAR", polar(ac, a, 5.75) + t * 5.0, UP, up_for(t), 0.4, ID_COLS[k + 3], 0.8)
    prof = [(0.0, -0.15), (3.4, -0.15), (3.6, 0.0), (4.6, 0.0), (5.4, 0.0), (5.4, -1.0),
            (0.0, -1.0)]
    fm = {0: "dark", 1: "dark", 2: "hazard", 3: "hull2", 4: "hull2", 5: "dark"}
    frame = (Matrix.Translation(polar(BAY_R, a)) @ Matrix.Rotation(a, 4, "Z")
             @ Matrix.Rotation(math.pi / 2, 4, "Y") @ Matrix.Rotation(math.pi / 2, 4, "Z"))
    p.lathe(prof, 24, lambda i, j: fm[j], matrix=frame, start=math.pi / 24)
    p.box(polar(BAY_R - 0.12, a, 0.0), (0.12, 6.4, 0.5), "metal", rot_z=a, bevel=0.0)
    p.box(polar(BAY_R - 0.12, a, 0.0), (0.12, 0.5, 6.4), "metal", rot_z=a, bevel=0.0)
    for q in range(4):
        ang = math.pi / 4 + q * math.pi / 2
        off = t * math.cos(ang) * 5.9 + V((0, 0, math.sin(ang) * 5.9))
        p.box(polar(BAY_R - 0.6, a, 0.0) + off, (1.2, 0.9, 0.9), "dark", rot_z=a, bevel=0.0)
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.box(polar(BAY_R - 0.78, a, sz * 4.8) + t * sx * 5.8, (0.1, 0.3, 0.3),
                  "window_dim" if sz < 0 else "nav_white", rot_z=a, bevel=0.0)
    strut_down(p, a, ac, 2.2)


def strut_down(p, a, r_post, w):
    """Post from the frame level down to LOW_Z, truss in under the ring to the lower collar."""
    z0, z1 = -0.9, LOW_Z - 0.6
    p.box(polar(r_post, a, (z0 + z1) / 2), (w, w, z0 - z1), "dark", rot_z=a, bevel=0.06)
    for zz in (-5.0, -7.2):
        p.box(polar(r_post, a, zz), (w + 0.2, w + 0.2, 0.3), "hull2", rot_z=a, bevel=0.0)
    truss(p, polar(6.2, a, LOW_Z), polar(r_post - 1.0, a, LOW_Z), 1.6, 1.4, 6, "metal",
          chord=0.26, brace=0.14)
    p.tube(polar(6.4, a, LOW_Z + 0.95), polar(r_post - 1.0, a, LOW_Z + 0.95), 0.13, 0.13,
           "accent", segs=5)
    p.box(polar(r_post, a, LOW_Z - 0.6), (3.0, 2.8, 1.4), "hull2", rot_z=a, bevel=0.06)


def cargo_rack(p, rng, a, k):
    """Pod rack: truss cradle out from the frame ring, prefab cargo pods both sides and on
    top, some slots empty, hazard end frames and loading lights."""
    t, rd = tangent(a), radial(a)
    r0, r1 = FRAME_R1 - 0.2, 37.5
    truss(p, polar(r0, a, -0.4), polar(r1, a, -0.4), 2.2, 2.2, 5, "metal", chord=0.26,
          brace=0.14)
    p.box(polar(r1 + 0.3, a, -0.4), (0.6, 7.6, 2.6), "hazard", rot_z=a, bevel=0.0)
    p.box(polar(r1 + 0.65, a, -0.4), (0.2, 7.0, 2.0), "dark", rot_z=a, bevel=0.0)
    cols = ["hull3", "accent", "hull2", "hull", "rust", "hull3"]
    slots = [(sd, lvl, j) for sd in (-1, 1) for lvl in (0, 1) for j in range(3)]
    for n, (sd, lvl, j) in enumerate(slots):
        if rng.random() < 0.22:
            continue
        r = r0 + 2.0 + j * 3.15
        c = polar(r, a, -0.4 + lvl * 2.5) + t * sd * 2.4
        wk.cargo_pod(p, c, (2.3, 3.0, 2.3), rot_z=a, body=rng.choice(cols),
                     band="hazard" if (n + k) % 4 == 0 else "dark", frame="dark")
    for j in range(3):
        c = polar(r0 + 2.0 + j * 3.15, a, 2.1 + 0.4)
        if rng.random() < 0.6:
            wk.cargo_pod(p, c, (2.3, 3.0, 2.3), rot_z=a, body=rng.choice(cols),
                         band="accent", frame="dark")
    label("CARGO", polar(r0 + 4.5, a, 3.75) + UP * 0.0, UP, up_for(t), 0.6, INK_DARK, 0.75)
    for sd in (-1, 1):
        p.box(polar(r1 + 0.3, a, 1.1) + t * sd * 3.4, (0.3, 0.3, 0.2), "window_dim", rot_z=a,
              bevel=0.0)
    beacon_mast(p, polar(r1 + 0.3, a, 0.9), 2.6, "nav_white" if k else "nav_red", 0.35)
    # handling arm (small crane) on the frame side
    base = polar(r0 + 0.8, a, 1.0) - t * 3.9
    p.cyl(base + UP * 1.0, 0.45, 0.45, 2.0, "hull2", segs=8)
    p.beam(base + UP * 2.0, base + UP * 3.6 + rd * 6.0, 0.35, 0.35, "hazard")
    p.box(base + UP * 3.6 + rd * 6.0, (0.6, 0.6, 0.6), "dark", bevel=0.0)


def build_bays(rng):
    p = parts.PanelPart("station_bays", MATS)
    # static frame ring outside the habitat ring (swept r <= 24.8), faceted
    prof = [(FRAME_R0, -0.9), (FRAME_R1, -0.9), (FRAME_R1, 0.9), (FRAME_R0, 0.9),
            (FRAME_R0, -0.9)]
    fmat = {0: "dark", 1: "hull2", 2: "hull2", 3: "dark"}
    p.lathe(prof, 36, lambda i, j: fmat[j], start=math.pi / 36)
    for i in range(18):
        a = 2 * math.pi * (i + 0.5) / 18
        p.box(polar((FRAME_R0 + FRAME_R1) / 2, a, 0.0), (1.9, 0.35, 2.1),
              "hazard" if i % 3 == 0 else "dark", rot_z=a, bevel=0.0)
    pipe_arc(p, (FRAME_R0 + FRAME_R1) / 2 + 0.2, 1.08, 0.0, 2 * math.pi, 36, 0.15, "metal")
    # lower collar on the underside cone
    prof = [(3.6, LOW_Z - 1.0), (6.4, LOW_Z - 1.0), (6.9, LOW_Z - 0.5), (6.9, LOW_Z + 0.4),
            (6.4, LOW_Z + 0.9), (4.4, LOW_Z + 0.9)]
    cmat = {0: "dark", 1: "dark", 2: "hull2", 3: "metal", 4: "hull2"}
    p.lathe(prof, 24, lambda i, j: cmat[j])
    for k, a_deg in enumerate(BAY_DEG):
        bay_collar(p, math.radians(a_deg), k)
    for k, a_deg in enumerate(CARGO_DEG):
        a = math.radians(a_deg)
        strut_down(p, a, (FRAME_R0 + FRAME_R1) / 2, 1.6)
        cargo_rack(p, rng, a, k)
    # beacon masts on the frame ring between everything
    for i, b in enumerate((37.5, 82.5, 127.5, 172.5, 217.5, 262.5, 307.5, 352.5)):
        a = math.radians(b)
        beacon_mast(p, polar((FRAME_R0 + FRAME_R1) / 2, a, 0.9), 2.4 + (i % 2) * 1.2,
                    ("nav_red", "nav_green", "nav_white")[i % 3], 0.32)
    return p


def add_empties(root):
    """addon_bay_N at each collar face (rot_z = a + 90 deg, as gen_station.add_empties),
    dock_pad_N at each pad centre (rot 0)."""
    for k, a_deg in enumerate(BAY_DEG):
        a = math.radians(a_deg)
        parts.add_empty(f"addon_bay_{k + 1}", root, polar(BAY_R, a), a + math.pi / 2, 6.0)
    for k, a_deg in enumerate(DOCK_DEG):
        parts.add_empty(f"dock_pad_{k + 1}", root, polar(PAD_R, math.radians(a_deg)), 0.0, 4.0)


def build_station():
    rng = random.Random(7171)
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    root = parts.make_root(PRE, size=6)
    builders = [build_core(rng), build_ring(rng), build_docks(rng), build_solar(rng),
                build_bays(rng)]
    objs = [b.finish(root) for b in builders]
    add_empties(root)
    return root, objs


# ---------------------------------------------------------------- texture
def texture(objs):
    pads = [tuple(polar(PAD_R, math.radians(d))[:2]) for d in DOCK_DEG]
    solar_obj = next(o for o in objs if o.name == "station_solar")
    p_alb, p_mr, p_nrm, atlas_mats = st.bake_worn_atlas(
        objs, MATS, PRE, 4096, pads, SCORCH, DECALS, LABELS, seed0=31)
    st.set_solar_uvs(solar_obj, MATS["solar"])
    ps = [os.path.join(st.TEX_DIR, f"station_solar_{n}.jpg") for n in ("albedo", "mr", "normal")]
    if not all(os.path.exists(x) for x in ps):
        ps = st.bake_solar_tile()
    hull = st.pbr_material(f"{PRE}_hull", st.load_saved(p_alb, False), st.load_saved(p_mr, True),
                           st.load_saved(p_nrm, True))
    solar = st.pbr_material("station_solar_panel_cells", st.load_saved(ps[0], False),
                            st.load_saved(ps[1], True), st.load_saved(ps[2], True))
    mapping = {m: hull for m in atlas_mats}
    mapping[MATS["solar"]] = solar
    for o in objs:
        st.remap_materials(o, mapping)
        o.data.uv_layers.remove(o.data.uv_layers["panel"])
    for m in list(atlas_mats) + [MATS["solar"]]:
        if m.users == 0:
            bpy.data.materials.remove(m)


# ---------------------------------------------------------------- previews
def dim_emission():
    for m in bpy.data.materials:
        b = m.node_tree.nodes.get("Principled BSDF") if m.node_tree else None
        if b is None and m.node_tree:
            b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if b:
            b.inputs["Emission Strength"].default_value *= 0.35


def previews(compare):
    os.makedirs(PREVIEW_COPY, exist_ok=True)
    out = []
    common.setup_preview(cam_loc=(0, -120, 120), cam_target=(0, 0, 0), ortho_scale=120,
                         res=(1600, 1200), key_dir=(-0.6, -0.35, 0.7), key_energy=3.5)
    dim_emission()
    scene = bpy.context.scene
    cam = scene.camera
    a = os.path.join(common.PREVIEW_DIR, "station_forward_preview.png")
    common.render(a)
    out.append(a)
    cam.location = (0, 0, 200)
    cam.rotation_euler = (0, 0, 0)
    cam.data.ortho_scale = 128
    scene.render.resolution_x, scene.render.resolution_y = 1400, 1400
    b = os.path.join(common.PREVIEW_DIR, "station_forward_top.png")
    common.render(b)
    out.append(b)
    cam.data.type = "PERSP"
    cam.data.lens = 35
    cam.location = (30.0, -46.0, 22.0)
    tgt = V((2.0, -6.0, 2.0))
    cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1000
    c = os.path.join(common.PREVIEW_DIR, "station_forward_closeup.png")
    common.render(c)
    out.append(c)
    if compare and os.path.exists(HOME_GLB):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=HOME_GLB)
        new = [o for o in bpy.data.objects if o not in before]
        hroot = next(o for o in new if o.parent is None)
        hroot.location = (-84.0, 0.0, 0.0)
        for m in {s.material for o in new if o.type == "MESH" for s in o.material_slots}:
            if m and m.node_tree:
                bb = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
                if bb:
                    bb.inputs["Emission Strength"].default_value *= 0.35
        froot = bpy.data.objects[PRE]
        froot.location = (56.0, 0.0, 0.0)
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = 280
        cam.location = (-14.0, -150.0, 150.0)
        cam.rotation_euler = (V((-14.0, 0, 0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.resolution_x, scene.render.resolution_y = 2400, 1200
        d = os.path.join(common.PREVIEW_DIR, "station_forward_compare.png")
        common.render(d)
        out.append(d)
        cam.location = (-14.0, 0.0, 250.0)
        cam.rotation_euler = (0, 0, 0)
        e = os.path.join(common.PREVIEW_DIR, "station_forward_compare_top.png")
        common.render(e)
        out.append(e)
    for x in out:
        shutil.copy(x, PREVIEW_COPY)


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_station()
    ring = next(o for o in objs if o.name == "station_ring")
    rmax = max(math.hypot(v.co.x, v.co.y) for v in ring.data.vertices)
    print(f"STAT station_ring max radius {rmax:.2f} (limit {RING_LIMIT})")
    assert rmax < RING_LIMIT, rmax
    if "--no-textures" not in argv:
        texture(objs)
    wk.stats(objs)
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        previews("--no-compare" not in argv)


main()
