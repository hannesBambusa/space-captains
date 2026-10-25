"""Generate the faction Claim Garrison (orbital platform that claims a planet) .glb + previews.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_claim_garrison.py
  Options after `--`: --no-preview, --no-textures.
Textures: one 2048 worn-industrial atlas (worn_kit), saved as blender/textures/
claim_garrison_*.jpg. Faction colour: every face meant to carry the owner's colour uses the
separate material "faction_paint" (same atlas, light neutral worn paint there, default
baseColorFactor hostile red). Godot tints it by setting albedo_color on that material
(a per-instance copy / surface override), the wear in the texture stays.

Design: armed ring platform, hostile and generic. Segmented armoured ring with ram plates
on the outer face, four flak turrets on the ring diagonals, a central command hub with a
reactor bulb and radiators underneath, four girder spokes and four pressurised tubes, a
beacon mast rising from the hub with a yard arm carrying two faction banners and a big
pulsing beacon at the top, two docking arms (Blender +-X), a launch bay facing Godot +Z
and a sensor array facing Godot -Z.

Layout (Blender Z up, exported +Y up; Blender -Y = Godot +Z). Centre at origin, ring plane
z = 0.
  ring      r 29.5..34.5 (ram plates to r 37), z -1.6..2.1
  hub       r 10.5, z -8..8, reactor bulb to z -17
  mast      z 8..50, banners z 24..39 on the yard arm, beacon at z 48.5
  arms      +-X, ring -> r 43, docking collars at r 43
  turrets   r 32 on the 45 deg diagonals, ring top z 2.1
  overall   ~89 x 84 m, 67 m tall (reactor bottom z -17 .. beacon z 50)
Hierarchy: claim_garrison (empty root) -> garrison_hull, garrison_lights, beacon_light
  (emissive, origin at the lens), garrison_hangar_glow (launch bay glow),
  flak_turret_1..4 (yaw nodes, origin on the slewing ring; local Godot -Z = barrels,
  rotated to face radially out) each with children flak_N_muzzle_l / flak_N_muzzle_r,
  dock_point_1 (+X arm), dock_point_2 (-X arm), spawn_point (launch bay), beacon_point,
  banner_point (empties). Dock / spawn empties: Godot -Z points away from the platform.
"""
import math
import os
import random
import sys

from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
import station_textures as st  # noqa: E402
import worn_kit as wk  # noqa: E402

V = Vector
PRE = "claim_garrison"
OUT = os.path.join(common.ROOT, "assets", "models", "buildings", "claim_garrison.glb")
BLEND = os.path.join(common.ROOT, "blender", "claim_garrison.blend")
R0, R1 = 28.5, 35.0
RING_Z0, RING_Z1 = -2.6, 1.6
RING_TOP = 2.2
HUB_R = 10.5
MAST_TOP = 46.0
BEACON = V((0.0, 0.0, 48.5))
ARM_R = 43.0
TURRET_R = 31.8
TURRET_S = 1.35
TURRET_ANGLES = [math.radians(a) for a in (45, 135, 225, 315)]
BAY_A = -math.pi / 2          # launch bay at Blender -Y (Godot +Z)
SPAWN_POS = (0.0, -46.0, 0.0)
LABELS = ["CG-04", "#BAR", "#CHEV", "DOCK 1", "DOCK 2", "NO STEP", "KEEP OUT", "LAUNCH"]

MATS = {}
DECALS = []
SCORCH = []
H = L = B = G = None
RNG = random.Random(23)


def label(text, centre, normal, up, h, colour, opacity=0.85):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity))


def lamp(pos, s=0.5, mat="red"):
    wk.lamp(L, pos, s, mat)


polar = wk.polar


def radial(a):
    return V((math.cos(a), math.sin(a), 0))


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


# ---------------------------------------------------------------- ring
def build_ring():
    n = 16
    step = 2 * math.pi / n
    gap = math.radians(0.9)
    for k in range(n):
        a0 = k * step + gap + step / 2
        a1 = (k + 1) * step - gap + step / 2
        H.ring_segment(V((0, 0, 0)), R0, R1, a0, a1, RING_Z0, RING_Z1, "hull2", steps=2)
        # top armour: inner + outer plates, faction stripe on every other segment
        H.ring_segment(V((0, 0, 0)), R0 + 0.3, R0 + 2.3, a0 + 0.01, a1 - 0.01, RING_Z1,
                       RING_TOP, "dark", steps=2)
        H.ring_segment(V((0, 0, 0)), R1 - 2.3, R1 - 0.3, a0 + 0.01, a1 - 0.01, RING_Z1,
                       RING_TOP, "paint" if k % 2 == 0 else "hull3", steps=2)
        H.ring_segment(V((0, 0, 0)), R0 + 2.5, R1 - 2.5, a0 + 0.01, a1 - 0.01, RING_Z1,
                       RING_Z1 + 0.25, "pad", steps=2)
        # underside keel plate
        H.ring_segment(V((0, 0, 0)), R0 + 1.0, R1 - 1.0, a0 + 0.02, a1 - 0.02, RING_Z0 - 0.8,
                       RING_Z0, "dark", steps=2)
        # ram plate wedge on the outer face (blunt, angled), not under turrets/arms
        am = (a0 + a1) / 2
        r = radial(am)
        t = V((-r.y, r.x, 0))
        pts = []
        for sz in (RING_Z0 + 0.2, RING_Z1 - 0.1):
            for st_ in (-1, 1):
                pts.append(r * (R1 - 0.2) + t * st_ * 2.6 + V((0, 0, sz)))
        pts += [r * 38.4 + t * 0.9 + V((0, 0, -0.4)), r * 38.4 - t * 0.9 + V((0, 0, -0.4)),
                r * 37.6 + V((0, 0, 1.0)), r * 37.6 + V((0, 0, -1.8))]
        parts.part_hull(H, pts, "metal" if k % 2 else "dark")
        # joint collar between segments
        aj = (k + 1) * step + step / 2
        rj = radial(aj)
        H.box(rj * (R0 + R1) / 2 + V((0, 0, (RING_Z0 + RING_TOP) / 2 + 0.1)),
              (R1 - R0 + 0.6, 1.0, RING_TOP - RING_Z0 + 0.6), "dark", rot_z=aj, bevel=0.0)
        lamp(rj * (R1 + 0.35) + V((0, 0, RING_Z1)), 0.4, "red")
        lamp(rj * (R0 - 0.35) + V((0, 0, RING_Z1)), 0.3, "light")
        # inner face window strip
        wk.win_row(L, RNG, polar(R0 - 0.02, a0 + 0.05, 0.0), polar(R0 - 0.02, a1 - 0.05, 0.0),
                   -radial(am), 4, 0.5, 0.4, "work")
        if k % 4 == 1:
            label("KEEP OUT", r * (R1 + 0.02) + V((0, 0, 0.0)), r, (0, 0, 1), 0.7,
                  wk.INK_LIGHT, 0.7)


def build_ring_top():
    """Bunkers and missile racks on the free ring stations, inner structural collar."""
    for k in range(8):
        a = math.radians(22.5 + 45 * k)
        r = radial(a)
        t = V((-r.y, r.x, 0))
        c = r * ((R0 + R1) / 2) + V((0, 0, RING_TOP))
        if k % 2 == 0:   # armoured bunker with a window slit and a faction band
            H.box(c + V((0, 0, 1.6)), (5.2, 8.0, 3.2), "hull2", rot_z=a, bevel=0.06)
            H.box(c + V((0, 0, 3.35)), (4.2, 7.0, 0.3), "dark", rot_z=a, bevel=0.0)
            H.box(c + r * 2.62 + V((0, 0, 2.6)), (0.08, 7.6, 0.5), "paint", rot_z=a, bevel=0.0)
            L.box(c + r * 2.63 + V((0, 0, 1.6)), (0.06, 5.0, 0.35), "window", rot_z=a, bevel=0.0)
            lamp(c + t * 3.8 + V((0, 0, 3.4)), 0.35, "red")
        else:            # missile rack: tilted launcher box, tube ends, blast deflector
            H.box(c + V((0, 0, 0.4)), (5.0, 6.0, 0.8), "dark", rot_z=a, bevel=0.0)
            rr = (Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(math.radians(-35), 4, "Y"))
            H.box(c + r * 0.4 + V((0, 0, 2.2)), (3.2, 5.0, 2.4), "metal", r=rr, bevel=0.06)
            for i in range(3):
                for j in range(2):
                    off = t * (-1.5 + i * 1.5) + V((0, 0, 2.7 + j * 0.9)) + r * 1.55
                    H.cyl(c + off, 0.35, 0.35, 0.12, "dark", segs=6,
                          axis_rot=(r + V((0, 0, 0.7))).normalized().to_track_quat(
                              "Z", "Y").to_matrix().to_4x4())
            H.box(c - r * 1.9 + V((0, 0, 1.4)), (0.4, 5.0, 2.0), "hazard", rot_z=a, bevel=0.0)
    # inner collar linking the spokes and tubes
    H.ring_segment(V((0, 0, 0)), 18.0, 20.0, 0.0, 2 * math.pi, -1.2, 1.2, "hull2", steps=16)
    H.ring_segment(V((0, 0, 0)), 18.3, 19.7, 0.0, 2 * math.pi, 1.2, 1.5, "paint", steps=16)
    for k in range(8):
        lamp(polar(20.1, k * math.pi / 4 + math.pi / 8, 0.8), 0.35, "red")


def build_spokes():
    for k in range(4):
        a = k * math.pi / 2
        d = radial(a)
        girder(H, d * (HUB_R - 0.5), d * (R0 + 0.2), 2.6, 2.2, 6, "dark")
        # walkway tube along the girder
        H.tube(d * HUB_R + V((0, 0, -0.2)), d * R0 + V((0, 0, -0.2)), 0.6, 0.6, "hull3", segs=8)
    for a in TURRET_ANGLES:
        d = radial(a)
        H.tube(d * (HUB_R - 0.5), d * (R0 + 0.3), 1.3, 1.3, "hull2", segs=10)
        for k in range(3):
            H.cyl(d * (HUB_R + 4.0 + k * 6.0), 1.5, 1.5, 0.6, "dark", segs=10,
                  axis_rot=d.to_track_quat("Z", "Y").to_matrix().to_4x4())


# ---------------------------------------------------------------- hub + reactor
def build_hub():
    prof = [(0.0, -8.0), (6.5, -8.0), (9.0, -6.2), (HUB_R, -3.5), (HUB_R, 3.0), (HUB_R, 4.2),
            (8.4, 7.0), (4.5, 8.0), (0.0, 8.0)]
    hm = {0: "dark", 1: "hull2", 2: "hull2", 3: "hull2", 4: "paint", 5: "hull3", 6: "dark",
          7: "dark"}
    H.lathe(prof, 16, lambda i, j: hm[j], start=math.pi / 16)
    # armour skirt panels around the hub wall
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        r = radial(a)
        H.box(r * (HUB_R + 0.35) + V((0, 0, -0.4)), (0.6, 4.2, 4.6), "metal", rot_z=a, bevel=0.06)
        wk.win_row(L, RNG, r * (HUB_R + 0.02) + radial(a + 0.45) * 0 + V((0, 0, 1.5))
                   + V((-r.y, r.x, 0)) * -2.4,
                   r * (HUB_R + 0.02) + V((0, 0, 1.5)) + V((-r.y, r.x, 0)) * 2.4, r, 3, 0.5, 0.5,
                   "hab")
    # faction emblem on the hub roof: paint disc with a dark chevron-diamond
    H.cyl(V((0, 0, 8.1)), 4.4, 4.4, 0.25, "paint", segs=16)
    H.slab([(0, 3.4), (2.2, 0), (0, -3.4), (-2.2, 0)], 8.2, 8.3, "dark")
    H.slab([(0, 1.6), (1.0, 0), (0, -1.6), (-1.0, 0)], 8.3, 8.36, "paint")
    label("CG-04", polar(HUB_R + 0.66, math.radians(-112), -1.0), radial(math.radians(-112)),
          (0, 0, 1), 0.9, wk.INK_LIGHT)
    # roof equipment
    for a in (0.6, 2.2, 3.8, 5.4):
        H.box(polar(6.6, a, 7.6), (2.0, 1.4, 1.2), "hull2", rot_z=a, bevel=0.06)
        lamp(polar(6.6, a, 8.3), 0.35, "red")
    # reactor bulb + radiator fins underneath
    prof = [(0.0, -8.0), (5.5, -8.0), (5.0, -10.5), (6.2, -12.0), (6.2, -13.5), (4.4, -15.5),
            (2.0, -16.6), (0.0, -16.8)]
    rm = {0: "dark", 1: "hull3", 2: "dark", 3: "paint", 4: "hull3", 5: "dark", 6: "dark"}
    H.lathe(prof, 12, lambda i, j: rm[j])
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        r = radial(a)
        for j in range(4):
            H.box(r * (8.5 + j * 1.7) + V((0, 0, -11.5)), (1.4, 0.12, 5.0), "radiator", rot_z=a,
                  bevel=0.0)
        H.box(r * 10.4 + V((0, 0, -9.2)), (7.4, 0.6, 0.4), "dark", rot_z=a, bevel=0.0)
    L.cyl(V((0, 0, -16.9)), 1.2, 1.2, 0.2, "red", segs=10)


# ---------------------------------------------------------------- mast, banners, beacon
def build_mast():
    prof = [(2.6, 8.0), (2.4, 12.0), (1.8, 22.0), (0.0, 22.0)]
    H.lathe([(0.0, 8.0)] + prof, 8, lambda i, j: ("dark", "hull2", "hull2", "dark")[j],
            start=math.pi / 8)
    H.cyl(V((0, 0, 12.5)), 2.7, 2.7, 0.8, "paint", segs=8)
    wk.lattice_mast(H, (0, 0, 22.0), MAST_TOP, 1.4, 0.7, 6, "dark", chord=0.4, brace=0.18)
    # yard arm across the mast, banners hanging from it on both sides (face +-Y)
    ya = 40.0
    H.box(V((0, 0, ya)), (17.0, 0.8, 0.8), "dark", bevel=0.0)
    H.box(V((0, 0, ya + 0.9)), (2.4, 2.4, 1.6), "hull2", bevel=0.06)
    for sx in (-1, 1):
        parts.strut(H, V((sx * 8.2, 0, ya)), V((0, 0, ya + 4.5)), 0.12, 0.12, "dark")
        cx = sx * 4.8
        H.box(V((cx, 0, ya - 0.9)), (5.6, 0.5, 0.5), "metal", bevel=0.0)       # top batten
        H.box(V((cx, 0, 24.3)), (5.6, 0.6, 0.6), "metal", bevel=0.0)           # bottom weight
        H.slab([(cx - 2.6, ya - 1.1), (cx + 2.6, ya - 1.1), (cx + 2.6, 25.5), (cx, 24.6),
                (cx - 2.6, 25.5)][::-1], -0.12, 0.12, "paint",
               matrix=Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1))))
        for side in (-1, 1):   # emblem diamond on both faces
            H.slab([(cx, 36.5), (cx + 1.6, 33.0), (cx, 29.5), (cx - 1.6, 33.0)][::-side],
                   side * 0.12, side * 0.17, "dark",
                   matrix=Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1))))
        lamp(V((sx * 8.4, 0, ya + 0.5)), 0.45, "red")
    # beacon housing at the top: cage + lens (beacon_light, separate so Godot can pulse it)
    H.cyl(V((0, 0, MAST_TOP + 0.5)), 1.4, 1.6, 1.0, "hull2", segs=8)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        parts.strut(H, polar(1.3, a, MAST_TOP + 1.0), polar(1.3, a, BEACON.z + 1.4), 0.15, 0.15,
                    "dark")
    H.cyl(V((0, 0, BEACON.z + 1.6)), 1.5, 1.0, 0.4, "dark", segs=8)
    B.sphere(V((0, 0, 0)), 1.05, "red", segs=10, rings=6, scale=(1, 1, 1.15))
    for k in range(3):   # aviation lamps down the mast
        z = 26.0 + k * 7.0
        for sx in (-1, 1):
            lamp(V((sx * (1.4 - 0.12 * k), 0, z)), 0.35, "red")


# ---------------------------------------------------------------- docking arms
def build_arms():
    for i, a in enumerate((0.0, math.pi)):
        d = radial(a)
        t = V((-d.y, d.x, 0))
        r_in, r_out = R1 - 0.5, ARM_R - 1.6
        girder(H, d * r_in + V((0, 0, -0.2)), d * r_out + V((0, 0, -0.2)), 3.0, 2.6, 4, "dark")
        H.box(d * ((r_in + r_out) / 2) + V((0, 0, 1.4)), (r_out - r_in, 2.0, 0.4), "pad",
              rot_z=a, bevel=0.0)
        H.tube(d * r_in + V((0, 0, -0.2)), d * r_out + V((0, 0, -0.2)), 0.9, 0.9, "hull3", segs=8)
        # docking collar facing outward, clamp jaws, faction band
        q = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        H.cyl(d * (ARM_R - 1.0), 2.6, 2.6, 1.6, "hull2", segs=12, axis_rot=q)
        H.cyl(d * (ARM_R - 0.05), 2.0, 2.0, 0.3, "dark", segs=12, axis_rot=q)
        H.cyl(d * (ARM_R - 1.9), 2.7, 2.7, 0.4, "paint", segs=12, axis_rot=q)
        for sz in (-1, 1):
            H.box(d * (ARM_R + 0.6) + V((0, 0, sz * 2.4)), (2.2, 1.0, 0.6), "metal", rot_z=a,
                  bevel=0.05)
            lamp(d * (ARM_R + 0.2) + t * 2.8 * sz + V((0, 0, 0.0)), 0.45,
                 "green" if i == 0 else "red")
        label("DOCK 1" if i == 0 else "DOCK 2", d * ((r_in + r_out) / 2) + V((0, 0, 1.61)),
              (0, 0, 1), t, 0.8, wk.INK_LIGHT, 0.7)
        for k in range(4):
            lamp(d * (r_in + 1.5 + k * 2.6) + t * 1.1 + V((0, 0, 1.65)), 0.3, "light")


# ---------------------------------------------------------------- launch bay + sensors
def build_bay():
    a = BAY_A
    d = radial(a)
    t = V((-d.y, d.x, 0))
    c = d * 33.5
    # armoured hangar block on the ring, mouth facing outward
    H.box(c + V((0, 0, 2.0)), (14.0, 9.0, 7.4), "hull2", rot_z=a + math.pi / 2, bevel=0.05)
    H.box(c + V((0, 0, 6.0)), (14.6, 9.4, 0.6), "paint", rot_z=a + math.pi / 2, bevel=0.0)
    H.box(c + d * 4.6 + V((0, 0, 1.9)), (10.8, 0.4, 5.4), "dark", rot_z=a + math.pi / 2,
          bevel=0.0)
    G.box(c + d * 4.75 + V((0, 0, 1.9)), (9.6, 0.1, 4.4), "red", rot_z=a + math.pi / 2,
          bevel=0.0)
    for sx in (-1, 1):
        H.box(c + d * 4.9 + t * sx * 5.9 + V((0, 0, 2.0)), (1.6, 1.2, 7.6), "metal",
              rot_z=a + math.pi / 2, bevel=0.05)
        lamp(c + d * 5.6 + t * sx * 5.9 + V((0, 0, 5.4)), 0.5, "red")
    label("LAUNCH", c + d * 4.81 + V((0, 0, 5.3)), d, (0, 0, 1), 0.6, wk.INK_LIGHT)
    # launch deck tongue
    H.box(c + d * 8.0 + V((0, 0, -1.4)), (10.0, 7.0, 0.8), "pad", rot_z=a + math.pi / 2,
          bevel=0.0)
    H.box(c + d * 11.4 + V((0, 0, -0.98)), (10.0, 0.4, 0.06), "hazard", rot_z=a + math.pi / 2,
          bevel=0.0)
    SCORCH.append((*(c + d * 7.0), 4.0))
    # sensor array opposite (Blender +Y): dish + antenna rack
    s = radial(math.pi / 2) * 32.0
    H.box(s + V((0, 0, 3.0)), (8.0, 6.0, 1.8), "hull2", bevel=0.05)
    H.cyl(s + V((0, 0, 4.6)), 0.9, 0.9, 1.6, "dark", segs=8)
    parts.dish(H, s + V((0, 0, 5.4)), 4.2, (0.0, 0.5, 0.85), "hull3", "dark", depth=1.0, segs=14)
    for k in range(3):
        H.cyl(s + V((-3.0 + k * 3.0, -2.2, 6.5)), 0.12, 0.06, 5.0, "dark", segs=5)
        lamp(s + V((-3.0 + k * 3.0, -2.2, 9.1)), 0.35, "red")


# ---------------------------------------------------------------- flak turrets
def build_turret(i):
    """Flak turret in its own frame: slewing ring at z 0, barrels toward local +Y
    (Godot -Z). Quad autocannon on an armoured wedge house."""
    p = parts.PanelPart(f"flak_turret_{i + 1}", MATS)
    p.cyl(V((0, 0, 0.35)), 2.5, 2.5, 0.7, "dark", segs=12)
    p.cyl(V((0, 0, 0.8)), 2.2, 2.2, 0.2, "paint", segs=12)
    side = Matrix.Translation((0, 0, 0.9)) @ parts.SIDE
    prof = [(-2.6, 0.0), (2.0, 0.0), (2.8, 1.0), (1.6, 2.6), (-2.2, 2.6), (-2.8, 1.4)]
    p.slab(prof[::-1], -1.9, 1.9, "hull2", matrix=side)
    for sx in (-1, 1):   # paint cheek plates
        p.slab([(-2.0, 0.4), (1.6, 0.4), (2.2, 1.1), (1.3, 2.2), (-1.8, 2.2)][::-1],
               sx * 1.9, sx * 2.05, "paint", matrix=side)
    p.box(V((0, -2.6, 2.4)), (2.6, 1.2, 1.4), "metal", bevel=0.06)     # ammo drum housing
    p.box(V((0, 0.4, 3.8)), (0.8, 0.8, 0.6), "dark", bevel=0.0)         # sensor
    L_box = p.box
    L_box(V((0, 0.82, 3.8)), (0.5, 0.06, 0.25), "red", bevel=0.0)
    # quad barrels, elevated 18 deg, with recoil sleeves and flash hiders
    el = math.radians(18)
    fwd = V((0, math.cos(el), math.sin(el)))
    q = fwd.to_track_quat("Z", "Y").to_matrix().to_4x4()
    root = V((0, 2.4, 2.0))
    p.box(root + V((0, -0.1, 0.0)), (2.4, 1.0, 1.4), "dark", bevel=0.06)
    muzzles = []
    for sx in (-0.48, 0.48):
        for sz in (-0.34, 0.34):
            b0 = root + V((sx, 0, sz))
            p.cyl(b0 + fwd * 0.9, 0.2, 0.2, 1.4, "metal", segs=6, axis_rot=q)
            p.cyl(b0 + fwd * 3.0, 0.1, 0.1, 3.2, "dark", segs=6, axis_rot=q)
            p.cyl(b0 + fwd * 4.7, 0.16, 0.16, 0.4, "dark", segs=6, axis_rot=q)
            muzzles.append(b0 + fwd * 4.95)
    return p, muzzles


# ---------------------------------------------------------------- assemble
def build_garrison():
    global H, L, B, G
    wk.build_materials(PRE, MATS, extra=("paint",))
    DECALS.clear()
    SCORCH.clear()
    H = parts.PanelPart("garrison_hull", MATS)
    L = parts.PanelPart("garrison_lights", MATS)
    B = parts.PanelPart("beacon_light", MATS)
    G = parts.PanelPart("garrison_hangar_glow", MATS)
    for b in (build_ring, build_ring_top, build_spokes, build_hub, build_mast, build_arms, build_bay):
        b()
    root = parts.make_root(PRE, size=20)
    hull = H.finish(root)
    flat = [p.finish(root) for p in (L, B, G)]
    for o in flat:
        o.data.uv_layers.remove(o.data.uv_layers["panel"])
    flat[1].location = BEACON
    turrets = []
    for i, a in enumerate(TURRET_ANGLES):
        p, muzzles = build_turret(i)
        o = p.finish(root)
        o.data.transform(Matrix.Scale(TURRET_S, 4))
        muzzles = [mz * TURRET_S for mz in muzzles]
        m = Matrix.Translation(polar(TURRET_R, a, RING_TOP)) @ Matrix.Rotation(a - math.pi / 2,
                                                                              4, "Z")
        o.data.transform(m)          # world-space pose while the atlas is baked
        turrets.append((o, m, muzzles))
    return root, hull, flat, turrets


def place_turrets(root, turrets):
    """After the bake: turret origin onto its slewing ring, rotated to face out, muzzles."""
    out = []
    for i, (o, m, muzzles) in enumerate(turrets):
        o.data.transform(m.inverted())
        o.matrix_world = m
        for name, mz in zip(("l", "r"), (muzzles[1], muzzles[3])):
            e = parts.add_empty(f"flak_{i + 1}_muzzle_{name}", o, mz, size=1.0)
            e.rotation_euler = (math.radians(18), 0, 0)
        out.append(o)
    return out


def add_points(root):
    for name, pos, rz in (("dock_point_1", (ARM_R + 1.0, 0, 0), -math.pi / 2),
                          ("dock_point_2", (-ARM_R - 1.0, 0, 0), math.pi / 2),
                          ("spawn_point", SPAWN_POS, math.pi)):
        parts.add_empty(name, root, pos, rot_z=rz, size=4)
    for name, pos in (("beacon_point", BEACON + V((0, 0, 1.5))), ("banner_point", (0, 0, 32.0))):
        e = parts.add_empty(name, root, pos, size=3)
        e.empty_display_type = "PLAIN_AXES"


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, hull, flat, tur = build_garrison()
    turrets = [t[0] for t in tur]
    if "--no-textures" not in argv:
        wk.texture([hull] + turrets, MATS, PRE, [(0.0, -41.5)], scorch=SCORCH, decals=DECALS, labels=LABELS,
                   seed0=51, paint_key="paint")
    else:
        for o in [hull] + turrets:
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    place_turrets(root, tur)
    add_points(root)
    wk.stats([hull] + flat + turrets)
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        wk.previews(PRE, (0.0, -2.0, 8.0), 118, 104, cam_off=(-70, -115, 125))


main()
