"""Generate the cargo shuttle .glb and previews (3/4, top-down, and a scale shot next to the miner).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_cargo_shuttle.py
  Add `-- --no-preview` to skip the PNG renders.
  Add `-- --no-textures` to skip the atlas bake (flat colours, fast iteration).
  Add `-- --scale-png /abs/out.png` to also render a tilted top-down shot beside the miner.

Design: short-haul civilian freight shuttle, functional hard sci-fi, ~8.9 m long, ~5 m wide.
Three readable blocks from the RTS camera: a lofted, chamfered crew cab at the nose
(raked windscreen, side portholes, teal accent band and chamfer stripes, sensor sponsons
with RCS and nav lights, comms dish, antenna, docking collar on the nose), an open cargo
cradle in the middle (a chamfered keel spine with pipe runs, three U-shaped saddle frames,
outer keel rails, landing legs, yellow clamp jaws on posts and on the spine) and a chunky
engine block at the stern (two strapped propellant tanks, vent housing, flat radiator
winglets, hazard band, two gimballed main bells with actuators and cooling rings).
Empty, the cradle reads as a ladder frame between cab and engines. The cargo is four
colour-coded units clamped two a side: three corrugated containers (blue, rust, green)
with corner castings, rails and door gear, and one white tank container in a frame.

Surfaces: worn atlas (station_textures / worn_kit bake, one 2048 atlas named
cargo_shuttle_*) for everything opaque, so hulls get plates, seams, rivets, hatches, grime
and chipping. The ship-scale panel sizes and the shuttle colours (teal, yellow, the
container paints) are process-local entries in station_textures.WORN_KINDS (the shared
file is untouched). Windows, lights and the engine glow stay flat emissive.

Layout (Blender Z up, exported +Y up). Ship centre near the origin on the play plane z=0.
The nose points along Blender +Y, which the exporter turns into Godot -Z (forward), same as
miner/salvager. Cab y 2.0..4.5, cradle y -2.3..1.95 (containers z -0.8..0.8), engine block
y -2.4..-3.7, bell exits at NOZZLE_Y.
Hierarchy: cargo_shuttle (empty root) -> cargo_shuttle_hull, cargo_containers, engine_glow.
cargo_containers is its own node so Godot can hide it when the shuttle flies empty; its
origin sits at the middle of the container bed, on the bed (z -0.8), so the supply-run
scale squashes the load down onto the cradle. engine_glow holds both glows; its origin is
on the bell exit plane (Blender y = NOZZLE_Y) and plumes extend along Godot local +Z, so
scaling it on Z lengthens both glows backwards.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
import station_textures as st  # noqa: E402
import worn_kit as wk  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402
from parts import ALONG_X, ALONG_Y  # noqa: E402

V = Vector
PRE = "cargo_shuttle"
OUT = os.path.join(common.ROOT, "assets", "models", "ships", "cargo_shuttle.glb")
BLEND = os.path.join(common.ROOT, "blender", "cargo_shuttle.blend")

NOZZLE_Y = -4.45
BELL_R = 0.55
BELL_LEN = 0.72
BELL_X = 0.8
SPINE_Y0, SPINE_Y1 = -2.6, 2.05
SPINE_W, SPINE_H, SPINE_Z = 1.0, 0.85, -0.15
CONT = (1.75, 1.95, 1.6)          # w (x), len (y), h (z)
CONT_X = 1.5
CONT_Y = (0.85, -1.25)            # front, rear container centres
CONT_Z = 0.0
FRAME_Y = (1.8, -0.2, -2.2)       # saddle frames: under the front end, joint, rear end
RAIL_X = 2.5
BED_Z = -0.8                      # container floor
CARGO_ORIGIN = V((0.0, (CONT_Y[0] + CONT_Y[1]) / 2, BED_Z))

MATS = {}
DECALS = []
SCORCH = []
LABELS = ["CS-07", "#CHEV", "NO STEP", "#BAR", "CARGO", "HAUL 4"]
INK = (0.04, 0.04, 0.045)


# ---------------------------------------------------------------- materials
def _tones(c):
    k = ((1.0, 1.0, 1.0), (0.95, 0.955, 0.96), (1.04, 1.035, 1.03), (0.92, 0.925, 0.93),
         (0.99, 0.975, 0.955), (0.94, 0.95, 0.965))
    return [tuple(min(1.0, a * b) for a, b in zip(c, m)) for m in k]


def _kind(base, colour=None, **over):
    d = dict(st.WORN_KINDS[base])
    if colour is not None:
        d["tones"] = _tones(colour)
    d.update(over)
    return d


def register_kinds():
    """Ship-scale worn kinds for this process only (station_textures.py is not edited)."""
    W = st.WORN_KINDS
    hull0, hull2_0, dark0, metal0, haz0, rad0 = (dict(W[k]) for k in
                                                 ("hull", "hull2", "dark", "metal", "hazard",
                                                  "radiator"))
    W["hull"] = dict(hull0, tones=_tones((0.60, 0.61, 0.60)), big=(1.8, 1.3), plate=(0.9, 0.65),
                     hatches=0.12, seam_big=0.42, seam_small=0.14, streak_k=0.32)
    W["hull2"] = dict(hull2_0, tones=_tones((0.30, 0.31, 0.32)), big=(1.2, 1.0),
                      plate=(0.6, 0.5), hatches=0.1)
    W["dark"] = dict(dark0, big=(1.0, 1.0), plate=(0.5, 0.5))
    W["metal"] = dict(metal0, big=(1.6, 0.6), plate=(0.8, 0.3))
    W["hazard"] = dict(haz0, tones=_tones((0.66, 0.47, 0.05)), big=(1.2, 1.2), plate=(0.6, 0.6),
                       stripes=0.3, bleach=0.2)
    W["radiator"] = dict(rad0, big=(1.0, 0.3), plate=(1.0, 0.1))
    W["teal"] = _kind("accent", (0.04, 0.33, 0.34), big=(1.6, 1.0), plate=(0.8, 0.5),
                      chip_k=1.1, bleach=0.2)
    W["yellow"] = _kind("accent", (0.70, 0.50, 0.05), big=(1.0, 1.0), plate=(0.5, 0.5),
                        chip_k=1.4, bleach=0.2)
    for key, col in (("c_blue", (0.09, 0.19, 0.42)), ("c_rust", (0.50, 0.18, 0.06)),
                     ("c_green", (0.11, 0.30, 0.15))):
        # fins: the radiator rib pattern doubles as corrugation on walls and roofs
        W[key] = _kind("accent", col, big=(2.0, 1.0), plate=(2.0, 0.11), fins=True,
                       seam_small=0.05, chip_k=1.3, streak_k=0.55, grime_k=1.2, bleach=0.3)


def build_materials():
    m = common.make_material
    MATS.clear()
    base = dict(hull=(0.6, 0.61, 0.6), hull2=(0.3, 0.31, 0.32), dark=(0.055, 0.058, 0.062),
                metal=(0.3, 0.3, 0.31), hazard=(0.66, 0.47, 0.05), radiator=(0.47, 0.475, 0.48),
                teal=(0.04, 0.33, 0.34), yellow=(0.7, 0.5, 0.05), c_blue=(0.09, 0.19, 0.42),
                c_rust=(0.5, 0.18, 0.06), c_green=(0.11, 0.3, 0.15))
    for k, c in base.items():
        MATS[k] = m(f"{PRE}_{k}", c, roughness=0.55, metallic=0.5 if k in ("dark", "metal")
                    else 0.0)
    glow = (0.03, 0.028, 0.025)
    MATS["glass"] = m(f"{PRE}_glass_dark", (0.012, 0.016, 0.02), roughness=0.1)
    MATS["window"] = m(f"{PRE}_window_warm", glow, roughness=0.25,
                       emission=(1.0, 0.46, 0.14), emission_strength=1.3)
    MATS["window_dim"] = m(f"{PRE}_window_amber", glow, roughness=0.25,
                           emission=(1.0, 0.5, 0.18), emission_strength=1.2)
    MATS["light"] = m(f"{PRE}_light_amber", glow, roughness=0.3,
                      emission=(1.0, 0.55, 0.15), emission_strength=4.0)
    MATS["red"] = m(f"{PRE}_light_red", glow, roughness=0.3,
                    emission=(1.0, 0.08, 0.03), emission_strength=6.0)
    MATS["green"] = m(f"{PRE}_light_green", glow, roughness=0.3,
                      emission=(0.15, 1.0, 0.3), emission_strength=5.0)
    MATS["white"] = m(f"{PRE}_light_white", glow, roughness=0.3,
                      emission=(0.85, 0.92, 1.0), emission_strength=5.0)
    MATS["glow"] = m(f"{PRE}_engine_glow", (0.75, 0.92, 1.0), roughness=0.2,
                     emission=(0.6, 0.86, 1.0), emission_strength=5.0)
    for k in ("glass", "window", "window_dim", "light", "red", "green", "white", "glow"):
        MATS[k].use_backface_culling = False


# ---------------------------------------------------------------- shape helpers
def loft_secs(P, secs, mat_fn, cap_mat, x0=0.0):
    """Loft chamfered sections (y, w, h, chamfer, z) along Y. Returns the point rings."""
    rings = [parts.oct_ring(y, w, h, c, x0=x0, z0=z) for y, w, h, c, z in secs]
    P.loft(rings, cap_mat, mat_fn=mat_fn)
    return rings


def oct_x(x, wy, h, c, y, z):
    """oct_ring turned to sit across X (w along Y, h along Z) at x."""
    hw, hh = wy / 2, h / 2
    pts = [(hw, -hh + c), (hw, hh - c), (hw - c, hh), (-hw + c, hh),
           (-hw, hh - c), (-hw, -hh + c), (-hw + c, -hh), (hw - c, -hh)]
    return [V((x, y + a, z + b)) for a, b in pts]


def xbeam(P, x0, x1, y, wy, h, c, z, mat):
    P.loft([oct_x(x0, wy, h, c, y, z), oct_x(x1, wy, h, c, y, z)], mat)


def face_pt(ra, rb, j, u, v):
    n = len(ra)
    a, b = ra[j], ra[(j + 1) % n]
    d, c = rb[j], rb[(j + 1) % n]
    return a.lerp(b, u).lerp(d.lerp(c, u), v)


def face_normal(ra, rb, j, centre):
    n = len(ra)
    a, b, d = ra[j], ra[(j + 1) % n], rb[j]
    nrm = (b - a).cross(d - a).normalized()
    mid = face_pt(ra, rb, j, 0.5, 0.5)
    if nrm.dot(mid - centre) < 0:
        nrm = -nrm
    return nrm


def plate(P, q, n, t, mat, lift=0.0):
    """Raised closed plate on a face: quad q (4 points), outward n, thickness t."""
    n = V(n).normalized()
    b = [P.bm.verts.new(V(p) + n * lift) for p in q]
    tp = [P.bm.verts.new(V(p) + n * (lift + t)) for p in q]
    idx = P.mi(mat)
    fs = [P.bm.faces.new(b), P.bm.faces.new(tp)]
    for i in range(4):
        k = (i + 1) % 4
        fs.append(P.bm.faces.new((b[i], b[k], tp[k], tp[i])))
    for f in fs:
        f.material_index = idx


def face_plate(P, rings, i, j, u0, u1, v0, v1, t, mat, centre, lift=0.0):
    ra, rb = rings[i], rings[i + 1]
    q = [face_pt(ra, rb, j, u, v) for u, v in ((u0, v0), (u1, v0), (u1, v1), (u0, v1))]
    plate(P, q, face_normal(ra, rb, j, centre), t, mat, lift)


def face_quad(P, rings, i, j, u0, u1, v0, v1, mat, centre, lift=0.03):
    ra, rb = rings[i], rings[i + 1]
    n = face_normal(ra, rb, j, centre)
    vs = [P.bm.verts.new(face_pt(ra, rb, j, u, v) + n * lift)
          for u, v in ((u0, v0), (u1, v0), (u1, v1), (u0, v1))]
    P.bm.faces.new(vs).material_index = P.mi(mat)


def vents(P, c, n, along, length, width, slats, mat_frame="dark", mat_slat="metal"):
    """Recessed louvre: dark frame plate with raised slats across it."""
    n, along = V(n).normalized(), V(along).normalized()
    side = n.cross(along).normalized()
    c = V(c)
    q = [c + along * a * length / 2 + side * s * width / 2
         for a, s in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    plate(P, q, n, 0.02, mat_frame)
    for k in range(slats):
        t = -0.5 + (k + 0.5) / slats
        p = c + along * t * length * 0.9 + n * 0.03
        r = Matrix((along, side, n)).transposed().to_4x4()
        P.box(p, (length / slats * 0.45, width * 0.86, 0.035), mat_slat, r=r, bevel=0.0)


def lamp(P, pos, s, mat):
    P.box(V(pos), (s, s, s * 0.6), mat, bevel=0.0)


def label(text, centre, normal, up, h, colour=INK, opacity=0.85):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity))


def greebles(P, rng, c, size, n_items, up=V((0, 0, 1)), mats=("hull2", "dark", "metal")):
    """Scatter small boxes on a flat top area centred at c (size x, y)."""
    for _ in range(n_items):
        w = rng.uniform(0.08, 0.26)
        ln = rng.uniform(0.08, 0.32)
        h = rng.uniform(0.03, 0.1)
        p = V(c) + V((rng.uniform(-0.5, 0.5) * (size[0] - w), rng.uniform(-0.5, 0.5) *
                      (size[1] - ln), h / 2))
        P.box(p, (w, ln, h), rng.choice(mats), bevel=0.15)


# ---------------------------------------------------------------- hull: cab
CAB = [(2.0, 2.15, 1.6, 0.45, 0.0), (2.15, 2.4, 1.8, 0.5, 0.0), (3.25, 2.4, 1.8, 0.5, 0.0),
       (3.95, 1.95, 1.3, 0.45, -0.1), (4.35, 1.15, 0.75, 0.3, -0.15),
       (4.5, 0.62, 0.42, 0.16, -0.15)]


def build_cab(P, rng):
    def mf(i, j):
        if i == 0:
            return "dark"
        if i in (1, 2) and j in (1, 3):
            return "teal" if i == 1 else "hull"
        if i >= 4:
            return "hull2"
        if i == 3 and j in (5, 6, 7):
            return "hull2"
        return "hull"
    rings = loft_secs(P, CAB, mf, "hull2")
    ctr = V((0, 3.0, 0.0))
    # accent band behind the windscreen
    loft_secs(P, [(2.62, 2.46, 1.86, 0.52, 0.0), (2.82, 2.46, 1.86, 0.52, 0.0)],
              lambda i, j: "teal" if j not in (5, 6, 7) else "hull2", "teal")
    # windscreen: three raked panes on the top slope, two on the top chamfers
    for j in (2,):
        face_plate(P, rings, 2, j, 0.02, 0.98, 0.06, 0.94, 0.015, "glass", ctr)
        for u0, u1 in ((0.05, 0.32), (0.37, 0.63), (0.68, 0.95)):
            face_quad(P, rings, 2, j, u0, u1, 0.14, 0.86, "window", ctr, lift=0.03)
    for j in (1, 3):
        face_plate(P, rings, 2, j, 0.06, 0.94, 0.1, 0.9, 0.015, "glass", ctr)
        face_quad(P, rings, 2, j, 0.14, 0.86, 0.2, 0.82, "window", ctr, lift=0.03)
    # side windows (upper flank under the windscreen), mullion frame in dark
    for j in (0, 4):
        face_plate(P, rings, 2, j, 0.62, 0.95, 0.08, 0.6, 0.015, "glass", ctr)
        face_quad(P, rings, 2, j, 0.67, 0.9, 0.14, 0.54, "window", ctr, lift=0.03)
    # portholes along the cabin flank
    for sx in (-1, 1):
        for y in (2.35, 3.0):
            lit = parts.pick_lit(rng, "hab") or "window_dim"
            parts.window(P, V((sx * 1.2, y, 0.38)), (sx, 0, 0), (0, 0, 1), 0.2, 0.2, lit)
    # roof: hatch, inset plates, comms gear
    face_plate(P, rings, 1, 2, 0.18, 0.82, 0.08, 0.42, 0.03, "hull2", ctr)
    face_plate(P, rings, 1, 2, 0.28, 0.72, 0.13, 0.37, 0.02, "hazard", ctr, lift=0.03)
    face_plate(P, rings, 1, 2, 0.1, 0.45, 0.62, 0.95, 0.02, "hull", ctr)
    for j in (0, 4):   # flank plates
        face_plate(P, rings, 1, j, 0.08, 0.5, 0.06, 0.94, 0.025, "hull", ctr)
        face_plate(P, rings, 3, j, 0.1, 0.9, 0.1, 0.8, 0.02, "hull2", ctr)
    for j in (5, 6, 7):   # belly plates
        face_plate(P, rings, 1, j, 0.1, 0.9, 0.08, 0.92, 0.03, "hull2", ctr)
    # brow over the windscreen, roof handrails, cheek vents
    P.box(V((0, 3.22, 0.93)), (1.5, 0.14, 0.07), "hull2", bevel=0.2)
    for sx in (-1, 1):
        P.box(V((sx * 0.86, 3.2, 0.82)), (0.32, 0.16, 0.08), "hull2", bevel=0.2,
              r=Matrix.Rotation(sx * -0.75, 4, "Y"))
        for y in (2.25, 3.05):
            parts.pipe(P, V((sx * 0.6, y, 0.9)), V((sx * 0.6, y, 0.98)), 0.02, "yellow", segs=4)
        parts.pipe(P, V((sx * 0.6, 2.25, 0.98)), V((sx * 0.6, 3.05, 0.98)), 0.02, "yellow", segs=4)
        vents(P, V((sx * 0.99, 3.85, -0.12)), (sx, 0.45, 0), (0, 0, 1), 0.36, 0.3, 4)
    label("CS-07", V((0, 2.75, 0.92)), (0, 0, 1), (1, 0, 0), 0.22)
    for sx in (-1, 1):
        label("CS-07", V((sx * 1.21, 2.65, -0.25)), (sx, 0, 0), (0, 0, 1), 0.2)
    # antenna mast and beacon, comms dish, sensor pod
    P.cyl(V((0.45, 2.45, 1.0)), 0.07, 0.07, 0.2, "dark", segs=8)
    P.tube(V((0.45, 2.45, 1.05)), V((0.45, 2.45, 1.85)), 0.025, 0.012, "metal", segs=5)
    P.tube(V((0.45, 2.45, 1.4)), V((0.65, 2.3, 1.55)), 0.012, 0.008, "metal", segs=4)
    lamp(P, (0.45, 2.45, 1.88), 0.07, "red")
    P.cyl(V((-0.5, 2.35, 0.98)), 0.1, 0.1, 0.22, "hull2", segs=8)
    parts.dish(P, V((-0.5, 2.35, 1.12)), 0.32, (0.2, -0.3, 1.0), "hull", "dark", depth=0.12,
               segs=12)
    P.box(V((0.0, 2.25, 0.96)), (0.36, 0.22, 0.14), "hull2", bevel=0.2)
    lamp(P, (0.0, 2.25, 1.05), 0.09, "white")
    # nose: docking collar, floodlight, chin sensor
    P.cyl(V((0, 4.55, -0.15)), 0.24, 0.24, 0.12, "dark", segs=12, axis_rot=ALONG_Y)
    P.torus(V((0, 4.62, -0.15)), 0.22, 0.035, "metal", segs=14, minor_segs=5, matrix=ALONG_Y)
    P.cyl(V((0, 4.63, -0.15)), 0.12, 0.12, 0.04, "white", segs=10, axis_rot=ALONG_Y)
    P.sphere(V((0, 3.75, -0.72)), 0.2, "dark", segs=10, rings=5, scale=(1.0, 1.4, 0.6))
    lamp(P, (0, 3.98, -0.72), 0.06, "white")
    # belly: docking hatch ring and nose skid
    P.cyl(V((0, 2.75, -0.9)), 0.38, 0.38, 0.06, "hull2", segs=14)
    P.torus(V((0, 2.75, -0.94)), 0.33, 0.035, "hazard", segs=14, minor_segs=4)
    P.tube(V((0, 3.3, -0.8)), V((0, 3.45, -1.3)), 0.06, 0.05, "metal", segs=6)
    P.box(V((0, 3.48, -1.34)), (0.42, 0.26, 0.06), "dark", bevel=0.2)
    lamp(P, (0, 3.6, -0.86), 0.08, "white")
    # sensor sponsons: RCS quad on the outside, nav light on the front
    for sx in (-1, 1):
        x = sx * 1.36
        loft_secs(P, [(2.3, 0.18, 0.4, 0.06, -0.2), (2.45, 0.34, 0.5, 0.1, -0.2),
                      (3.05, 0.34, 0.5, 0.1, -0.2), (3.3, 0.22, 0.36, 0.07, -0.22)],
                  lambda i, j: "hull2" if j != 2 else "teal", "hull2", x0=x)
        parts.rcs_quad(P, V((sx * 1.56, 2.75, -0.2)), (sx, 0, 0), "hull2", "dark", s=0.2)
        lamp(P, (x, 3.33, -0.2), 0.09, "red" if sx < 0 else "green")
        vents(P, V((x, 2.75, 0.06)), (0, 0, 1), (0, 1, 0), 0.5, 0.22, 4)
    for sz in (-1, 1):   # RCS on the cab roof/belly corners at the front
        for sx in (-1, 1):
            n = V((sx, 0, sz * 0.8)).normalized()
            parts.rcs_quad(P, V((sx * 0.85, 3.55, sz * 0.55 - 0.05)), n, "hull2", "dark", s=0.18)
    return rings


# ---------------------------------------------------------------- hull: spine + cradle
def build_spine(P, rng):
    secs = [(SPINE_Y0, SPINE_W, SPINE_H, 0.22, SPINE_Z), (SPINE_Y1, SPINE_W, SPINE_H, 0.22,
                                                           SPINE_Z)]
    rings = loft_secs(P, secs, lambda i, j: "dark" if j in (1, 3, 5, 7) else "hull2", "hull2")
    top = SPINE_Z + SPINE_H / 2
    ctr = V((0, 0, SPINE_Z))
    # top: conduit tray, pipe runs, junction boxes, greebles between the frames
    P.box(V((0, -0.3, top + 0.04)), (0.3, SPINE_Y1 - SPINE_Y0 - 0.5, 0.08), "metal", bevel=0.2)
    for sx in (-1, 1):
        parts.pipe(P, V((sx * 0.3, SPINE_Y0 + 0.1, top + 0.06)), V((sx * 0.3, SPINE_Y1 - 0.1,
                                                                    top + 0.06)),
                   0.05, "teal" if sx > 0 else "yellow", segs=6)
        parts.pipe(P, V((sx * 0.53, SPINE_Y0 + 0.2, SPINE_Z + 0.05)),
                   V((sx * 0.53, SPINE_Y1 - 0.2, SPINE_Z + 0.05)), 0.045, "metal", segs=6)
        parts.pipe(P, V((sx * 0.52, SPINE_Y0 + 0.2, SPINE_Z - 0.2)),
                   V((sx * 0.52, SPINE_Y1 - 0.2, SPINE_Z - 0.2)), 0.035, "dark", segs=6)
        for y in (1.2, 0.2, -0.8, -1.6):   # pipe brackets
            P.box(V((sx * 0.53, y, SPINE_Z - 0.07)), (0.08, 0.06, 0.38), "dark", bevel=0.0)
    for y0, y1 in ((FRAME_Y[1] + 0.25, FRAME_Y[0] - 0.25), (FRAME_Y[2] + 0.25, FRAME_Y[1] - 0.25)):
        greebles(P, rng, V((0, (y0 + y1) / 2, top)), (0.9, y1 - y0), 7)
        P.box(V((0, (y0 + y1) / 2, top + 0.08)), (0.5, 0.4, 0.14), "hull2", bevel=0.2)
        vents(P, V((0, (y0 + y1) / 2, top + 0.16)), (0, 0, 1), (0, 1, 0), 0.36, 0.4, 4)
    for j in (6,):   # belly plates
        for v0 in (0.08, 0.38, 0.68):
            face_plate(P, rings, 0, j, 0.1, 0.9, v0, v0 + 0.26, 0.03, "hull2", ctr)
    # flank access plates
    for j in (0, 4):
        for v0 in (0.1, 0.55):
            face_plate(P, rings, 0, j, 0.2, 0.8, v0, v0 + 0.3, 0.02, "hull", ctr)
    lamp(P, (0, SPINE_Y0 + 0.6, SPINE_Z - SPINE_H / 2 - 0.03), 0.1, "white")


def build_cradle(P, rng):
    fz = BED_Z - 0.17        # saddle beam centre (top at the container floor)
    for k, y in enumerate(FRAME_Y):
        xbeam(P, -RAIL_X - 0.1, RAIL_X + 0.1, y, 0.3, 0.32, 0.08, fz, "hull2")
        # gusset plates where the saddle meets the spine
        for sx in (-1, 1):
            P.box(V((sx * 0.62, y, fz + 0.2)), (0.3, 0.32, 0.36), "dark", bevel=0.1)
        # outer posts with clamp jaws
        for sx in (-1, 1):
            x = sx * RAIL_X
            P.box(V((x, y, -0.25)), (0.22, 0.3, 1.5), "hull2", bevel=0.15)
            P.box(V((x - sx * 0.02, y, -0.85)), (0.3, 0.38, 0.3), "dark", bevel=0.1)
            P.box(V((x - sx * 0.12, y, 0.9)), (0.48, 0.34, 0.2), "yellow", bevel=0.2)
            P.box(V((x - sx * 0.3, y, 0.84)), (0.12, 0.3, 0.12), "dark", bevel=0.1)
            P.box(V((x + sx * 0.05, y, 0.62)), (0.2, 0.36, 0.3), "dark", bevel=0.15)
            parts.pipe(P, V((x + sx * 0.14, y + 0.08, -0.6)), V((x + sx * 0.14, y + 0.08, 0.5)),
                       0.04, "metal", segs=6)
            lamp(P, (x + sx * 0.02, y, 1.02), 0.08, "light")
        # spine clamp: post and crossbar jaw over both containers
        top = SPINE_Z + SPINE_H / 2
        P.box(V((0, y, top + 0.3)), (0.22, 0.26, 0.6), "hull2", bevel=0.15)
        xbeam(P, -0.62, 0.62, y, 0.26, 0.16, 0.05, 0.9, "hull2")
        for sx in (-1, 1):
            P.box(V((sx * 0.75, y, 0.9)), (0.3, 0.32, 0.2), "yellow", bevel=0.2)
            P.box(V((sx * 0.82, y, 0.82)), (0.12, 0.28, 0.1), "dark", bevel=0.1)
        lamp(P, (0, y, 1.01), 0.08, "light")
    # outer keel rails with a hazard tread on top, landing legs, floodlights
    for sx in (-1, 1):
        x = sx * RAIL_X
        P.loft([parts.oct_ring(FRAME_Y[2] - 0.15, 0.2, 0.24, 0.05, x0=x, z0=fz),
                parts.oct_ring(FRAME_Y[0] + 0.15, 0.2, 0.24, 0.05, x0=x, z0=fz)], "hull2")
        P.box(V((x, (FRAME_Y[0] + FRAME_Y[2]) / 2, fz + 0.13)),
              (0.18, FRAME_Y[0] - FRAME_Y[2] - 0.3, 0.025), "hazard", bevel=0.0)
        for y in (FRAME_Y[0] - 0.35, FRAME_Y[2] + 0.35):
            a = V((x, y, fz - 0.1))
            b = V((x + sx * 0.12, y, fz - 0.55))
            P.tube(a, b, 0.07, 0.06, "metal", segs=6)
            P.tube(V((x - sx * 0.25, y, fz - 0.05)), b + V((0, 0, 0.1)), 0.035, 0.035, "dark",
                   segs=5)
            P.cyl(b - V((0, 0, 0.04)), 0.2, 0.22, 0.07, "dark", segs=10)
        for y in (FRAME_Y[1] + 0.6, FRAME_Y[1] - 0.6):
            P.box(V((x, y, fz - 0.16)), (0.16, 0.2, 0.1), "dark", bevel=0.1)
            lamp(P, (x, y, fz - 0.22), 0.11, "white")


# ---------------------------------------------------------------- hull: engine block
ENG = [(-2.4, 1.3, 1.0, 0.25, -0.1), (-2.55, 3.1, 1.55, 0.4, 0.0), (-3.4, 3.3, 1.7, 0.45, 0.0),
       (-3.7, 2.9, 1.45, 0.4, 0.0)]


def build_engine(P, rng):
    def mf(i, j):
        if i == 0:
            return "dark"
        if i == 2:
            return "hull2"
        return "teal" if j in (1, 3) else "hull"
    rings = loft_secs(P, ENG, mf, "hull2")
    ctr = V((0, -3.0, 0.0))
    loft_secs(P, [(-3.22, 3.36, 1.76, 0.47, 0.0), (-3.38, 3.36, 1.76, 0.47, 0.0)],
              lambda i, j: "hazard", "hazard")
    # top deck: tanks on saddles with straps, vent housing and strobe between
    top = 0.85
    for sx in (-1, 1):
        x = sx * 0.78
        parts.capsule(P, -3.35, -2.5, 0.34, lambda i, j: "teal" if j in (0, 7) else "hull",
                      segs=12, x=x, z=top + 0.3, dome0=0.6, dome1=0.6)
        for y in (-2.75, -3.1):
            P.torus(V((x, y, top + 0.3)), 0.35, 0.03, "dark", segs=12, minor_segs=4,
                    matrix=ALONG_Y)
            P.box(V((x, y, top + 0.04)), (0.5, 0.1, 0.1), "dark", bevel=0.1)
        parts.pipe(P, V((x, -3.4, top + 0.25)), V((x * 0.5, -3.55, top + 0.05)), 0.04, "metal")
        # flank plates and RCS
        for j in ((0,) if sx > 0 else (4,)):
            face_plate(P, rings, 1, j, 0.12, 0.88, 0.1, 0.9, 0.025, "hull2", ctr)
            face_plate(P, rings, 1, j, 0.2, 0.45, 0.2, 0.8, 0.02, "teal", ctr, lift=0.025)
        parts.rcs_quad(P, V((sx * 1.62, -2.75, 0.62)), (sx, 0, 0.6), "hull2", "dark", s=0.2)
        parts.rcs_quad(P, V((sx * 1.62, -2.75, -0.62)), (sx, 0, -0.6), "hull2", "dark", s=0.2)
        # radiator winglets
        rx = sx * 2.05
        P.box(V((rx, -3.0, 0.05)), (0.9, 0.7, 0.05), "radiator", bevel=0.0)
        for k in range(5):
            P.box(V((rx, -2.72 + k * -0.14, 0.09)), (0.86, 0.025, 0.03), "dark", bevel=0.0)
        P.box(V((sx * 2.52, -3.0, 0.05)), (0.06, 0.74, 0.09), "dark", bevel=0.0)
        P.box(V((sx * 1.67, -3.0, 0.05)), (0.14, 0.8, 0.16), "hull2", bevel=0.2)
        lamp(P, (sx * 2.55, -3.0, 0.1), 0.09, "red" if sx < 0 else "green")
    P.box(V((0, -2.95, top + 0.12)), (0.5, 0.9, 0.26), "hull2", bevel=0.2)
    vents(P, V((0, -2.95, top + 0.26)), (0, 0, 1), (0, 1, 0), 0.7, 0.36, 6)
    P.cyl(V((0, -3.45, top + 0.2)), 0.07, 0.07, 0.4, "dark", segs=6)
    lamp(P, (0, -3.45, top + 0.42), 0.09, "white")
    P.tube(V((0.12, -2.6, top + 0.25)), V((0.12, -2.6, top + 1.0)), 0.02, 0.01, "metal", segs=4)
    label("HAUL 4", V((0, -3.2, -0.86)), (0, 0, -1), (1, 0, 0), 0.18)
    for sx in (-1, 1):
        label("NO STEP", V((sx * 1.66, -3.0, 0.25)), (sx, 0, 0), (0, 0, 1), 0.12)
    # belly plates
    for j in (5, 6, 7):
        face_plate(P, rings, 1, j, 0.1, 0.9, 0.12, 0.88, 0.03, "hull2", ctr)
    # rear plate: bell mounts, gimbals, actuators
    ry = ENG[-1][0]
    P.box(V((0, ry - 0.02, 0)), (0.5, 0.06, 0.8), "dark", bevel=0.1)
    vents(P, V((0, ry - 0.06, 0.45)), (0, -1, 0), (1, 0, 0), 0.5, 0.16, 5)
    for sx in (-1, 1):
        x = sx * BELL_X
        P.cyl(V((x, ry - 0.06, 0)), 0.5, 0.5, 0.12, "dark", segs=16, axis_rot=ALONG_Y)
        P.cyl(V((x, ry - 0.16, 0)), 0.36, 0.3, 0.14, "metal", segs=14, axis_rot=ALONG_Y)
        P.torus(V((x, ry - 0.22, 0)), 0.32, 0.045, "dark", segs=14, minor_segs=5, matrix=ALONG_Y)
        parts.bell(P, NOZZLE_Y, BELL_R, BELL_LEN, "metal", "dark", x=x, segs=16)
        for t, r in ((0.35, 0.44), (0.7, 0.51)):
            y = NOZZLE_Y + BELL_LEN * (1 - t)
            P.torus(V((x, y, 0)), r + 0.01, 0.022, "dark", segs=16, minor_segs=4,
                    matrix=ALONG_Y)
        P.torus(V((x, NOZZLE_Y + 0.02, 0)), BELL_R - 0.01, 0.03, "hull2", segs=16, minor_segs=4,
                matrix=ALONG_Y)
        for a in (math.pi / 4, 3 * math.pi / 4):
            d = V((math.cos(a) * sx, 0, math.sin(a)))
            p0 = V((x, ry - 0.05, 0)) + d * 0.62
            p1 = V((x, NOZZLE_Y + BELL_LEN * 0.55, 0)) + d * 0.38
            P.tube(p0, p1, 0.045, 0.035, "metal", segs=6)
            P.box(p0, (0.12, 0.08, 0.12), "dark", bevel=0.1)
        SCORCH.append((x, ry - 0.1, 0.0, 0.9))


# ---------------------------------------------------------------- containers
def corr_container(P, c, mat, rng, door_rear=True):
    w, ln, h = CONT
    c = V(c)
    P.box(c, (w - 0.06, ln - 0.06, h - 0.06), mat, bevel=0.03)
    # corrugated long sides and roof: thin raised ribs (even counts: none over a face
    # centre, or the atlas bake counts the whole wall as buried under its rib)
    n = 8
    for sx in (-1, 1):
        for k in range(n):
            y = -ln / 2 + 0.17 + (ln - 0.34) * k / (n - 1)
            P.box(c + V((sx * (w / 2 - 0.02), y, 0)), (0.04, 0.09, h - 0.3), mat, bevel=0.3)
    for k in range(4):
        y = -ln / 2 + 0.3 + (ln - 0.6) * k / 3
        P.box(c + V((0, y, h / 2 - 0.02)), (w - 0.3, 0.12, 0.04), mat, bevel=0.3)
    # frame: top/bottom side rails, end frames, corner castings
    for sz in (-1, 1):
        for sx in (-1, 1):
            P.box(c + V((sx * (w / 2 - 0.05), 0, sz * (h / 2 - 0.05))), (0.1, ln - 0.1, 0.1),
                  "dark", bevel=0.0)
    for sy in (-1, 1):
        y = sy * (ln / 2 - 0.05)
        for sx in (-1, 1):
            P.box(c + V((sx * (w / 2 - 0.05), y, 0)), (0.1, 0.1, h - 0.1), "dark", bevel=0.0)
        for sz in (-1, 1):
            P.box(c + V((0, y, sz * (h / 2 - 0.05))), (w - 0.1, 0.1, 0.1), "dark", bevel=0.0)
        for sx in (-1, 1):
            for sz in (-1, 1):
                P.box(c + V((sx * (w / 2 - 0.06), y, sz * (h / 2 - 0.06))), (0.15, 0.15, 0.15),
                      "metal", bevel=0.1)
    # doors on the rear end: two leaves, four lock bars with cams
    ye = c.y - ln / 2 - 0.01 if door_rear else c.y + ln / 2 + 0.01
    s = -1 if door_rear else 1
    for sx in (-1, 1):
        P.box(V((c.x + sx * w / 4, ye, c.z)), (w / 2 - 0.16, 0.03, h - 0.24), mat, bevel=0.2)
        for k in (0.3, 0.7):
            x = c.x + sx * w * k / 2 + sx * 0.06
            P.tube(V((x, ye + s * 0.03, c.z - h / 2 + 0.14)), V((x, ye + s * 0.03, c.z + h / 2 - 0.14)),
                   0.018, 0.018, "metal", segs=5)
            P.box(V((x, ye + s * 0.05, c.z - 0.1)), (0.06, 0.04, 0.16), "dark", bevel=0.0)
    # ID placard and a pale band on each long side
    for sx in (-1, 1):
        P.box(c + V((sx * (w / 2 + 0.005), 0.0, h * 0.28)), (0.02, ln * 0.92, 0.12), "hull",
              bevel=0.0)
        P.box(c + V((sx * (w / 2 + 0.015), -ln * 0.28, -h * 0.12)), (0.02, 0.36, 0.24), "hull",
              bevel=0.0)


def tank_container(P, c, rng):
    w, ln, h = CONT
    c = V(c)
    for sy in (-1, 1):   # end frames with diagonals
        y = sy * (ln / 2 - 0.06)
        for sx in (-1, 1):
            P.box(c + V((sx * (w / 2 - 0.06), y, 0)), (0.12, 0.12, h - 0.1), "dark", bevel=0.0)
        for sz in (-1, 1):
            P.box(c + V((0, y, sz * (h / 2 - 0.06))), (w - 0.1, 0.12, 0.12), "dark", bevel=0.0)
        P.beam(c + V((-w / 2 + 0.1, y, -h / 2 + 0.1)), c + V((w / 2 - 0.1, y, h / 2 - 0.1)), 0.07,
               0.07, "dark", up=V((0, 1, 0)))
        for sx in (-1, 1):
            for sz in (-1, 1):
                P.box(c + V((sx * (w / 2 - 0.06), y, sz * (h / 2 - 0.06))), (0.16, 0.16, 0.16),
                      "metal", bevel=0.1)
    for sz in (-1, 1):
        for sx in (-1, 1):
            P.box(c + V((sx * (w / 2 - 0.06), 0, sz * (h / 2 - 0.06))), (0.1, ln - 0.2, 0.1),
                  "dark", bevel=0.0)
    r = h / 2 - 0.12
    parts.capsule(P, c.y - ln / 2 + 0.1, c.y + ln / 2 - 0.1, r,
                  lambda i, j: "yellow" if i % 2 == 0 and j in (3, 4) else "hull",
                  segs=16, x=c.x, z=c.z, dome0=0.35, dome1=0.35)
    for y in (-0.55, 0.55):   # saddle bands
        P.torus(c + V((0, y, 0)), r + 0.01, 0.03, "dark", segs=16, minor_segs=4, matrix=ALONG_Y)
    P.box(c + V((0, 0, r + 0.02)), (0.36, ln - 0.4, 0.03), "metal", bevel=0.0)   # walkway
    P.cyl(c + V((0, 0.3, r + 0.08)), 0.14, 0.14, 0.12, "hull2", segs=10)
    P.cyl(c + V((0, -0.35, r + 0.06)), 0.06, 0.06, 0.1, "dark", segs=6)
    P.cyl(c + V((0.3, -ln / 2 + 0.04, -h * 0.25)), 0.06, 0.06, 0.12, "teal", segs=8,
          axis_rot=ALONG_Y)


def build_containers(rng):
    P = parts.PanelPart("cargo_containers", MATS)
    slots = [(-1, 0, "c_blue"), (1, 0, "c_rust"), (-1, 1, "c_green"), (1, 1, "tank")]
    for sx, k, mat in slots:
        c = V((sx * CONT_X, CONT_Y[k], CONT_Z))
        if mat == "tank":
            tank_container(P, c, rng)
        else:
            corr_container(P, c, mat, rng, door_rear=(k == 1))
    return P


# ---------------------------------------------------------------- assemble
def build_hull(rng):
    P = parts.PanelPart("cargo_shuttle_hull", MATS)
    build_cab(P, rng)
    build_spine(P, rng)
    build_cradle(P, rng)
    build_engine(P, rng)
    return P


def build_glow():
    p = parts.Part("engine_glow", MATS)
    for sx in (-1, 1):
        parts.exhaust_glow(p, BELL_R * 0.85, 0.9, "glow", x=sx * BELL_X, segs=16)
    return p


def build_ship(textures=True):
    rng = random.Random(7731)
    register_kinds()
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    root = parts.make_root(PRE)
    hull = build_hull(rng).finish(root)
    cont = build_containers(rng).finish(root)
    glow = build_glow().finish(root)
    glow.location = (0, NOZZLE_Y, 0)
    if textures:
        wk.texture([hull, cont], MATS, PRE, [(0.0, 0.0)], scorch=SCORCH,
                   decals=DECALS, labels=LABELS, seed0=73,
                   res=2048)
    else:
        for o in (hull, cont):
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    # containers: origin on the middle of the bed so the supply-run scale squashes them down
    cont.data.transform(Matrix.Translation(-CARGO_ORIGIN))
    cont.location = CARGO_ORIGIN
    return root, [hull, cont, glow]


def scale_preview(path):
    import bpy
    ship = "miner_hauler.glb" if os.path.exists(os.path.join(
        common.ROOT, "assets", "models", "ships", "miner_hauler.glb")) else "miner.glb"
    miner = os.path.join(common.ROOT, "assets", "models", "ships", ship)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=miner)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.parent is None:
            o.location.x += 12.0
    common.setup_preview(cam_loc=(-4, -16, 24), cam_target=(6.0, 0, 0), res=(1600, 1000),
                         key_dir=(-0.5, 0.4, 0.75), key_energy=3.5)
    common.render(path)


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_ship(textures="--no-textures" not in argv)
    wk.stats(objs)
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews(PRE, 10.0, target=(0, 0, 0))
    if "--scale-png" in argv:
        scale_preview(argv[argv.index("--scale-png") + 1])


main()
