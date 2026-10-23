"""Generate the Shield Generator (station bubble projector) .glb and previews.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python /Users/hannesalm/code/games/space-majesty/blender/gen_shield_generator.py
  Add `-- --no-preview` to skip the PNG renders, `-- --no-textures` for flat materials.
Textures: one 2048 atlas baked with the station_textures surface kinds (plus "radiator"),
saved as blender/textures/shield_*.{jpg,png} and embedded as JPEG.

Layout (Blender Z up, exported +Y up; Blender +Y = Godot -Z). Centre at origin, plane z=0.
  deck            octagon, flats at r 16.6, z -3.2..0.3
  reactor drum    r 8.5, z 0.3..10.6, centre
  capacitors      4 octagonal banks on the diagonals at r 13.4, z 0.3..12, HV bushings and
                  heavy cables to the drum shoulder; cyan charge strips on the outer flats
  radiators       two edge-on radial fin banks on +-X, x 12.5..19.5, z 1.3..12
  control block   -Y side (Godot +Z), y -17..-12
  link port       +Y side (Godot -Z), airlock on a pylon, flange at y = 20.5, z = 12
  mast            truss + tapered column from the drum roof to z 33
  projector       hub + ring of 12 outward-leaning emitter fins + crown ring, z 32.5..40.5
Hierarchy: shield_generator (empty root) -> shield_base, shield_emitter_glow,
  shield_capacitors, shield_emitter_point, link_point.
shield_capacitors has its origin at the strip bottoms (z = 2), so scaling Godot Y on it
fills the strips from the bottom. shield_emitter_glow has its origin at the projector centre.
link_point is unrotated: its Godot -Z points out of the +Y (Godot -Z) side.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
import station_textures as st  # noqa: E402

V = Vector
OUT = os.path.join(common.ROOT, "assets", "models", "buildings", "shield_generator.glb")
BLEND = os.path.join(common.ROOT, "blender", "shield_generator.blend")
LINK_POS = (0.0, 20.5, 12.0)
EMITTER_POS = (0.0, 0.0, 41.5)
GLOW_ORIGIN = (0.0, 0.0, 37.0)
CAP_ORIGIN = (0.0, 0.0, 2.0)
ATLAS_RES = 2048
ALONG_Y = parts.ALONG_Y

MATS = {}


def build_materials():
    m = common.make_material
    MATS["hull"] = m("shield_hull_white", (0.78, 0.78, 0.76), roughness=0.45, metallic=0.1)
    MATS["hull2"] = m("shield_hull_grey", (0.50, 0.52, 0.55), roughness=0.5, metallic=0.15)
    MATS["dark"] = m("shield_structure_dark", (0.06, 0.065, 0.07), roughness=0.55, metallic=0.5)
    MATS["orange"] = m("shield_accent_orange", (0.85, 0.28, 0.03), roughness=0.45)
    MATS["hazard"] = m("shield_hazard", (0.8, 0.55, 0.02), roughness=0.5)
    MATS["mli"] = m("shield_mli_white", (0.8, 0.8, 0.78), roughness=0.85)
    MATS["mli_gold"] = m("shield_mli_gold", (0.8, 0.52, 0.15), roughness=0.4, metallic=0.9)
    MATS["pad"] = m("shield_deck", (0.15, 0.15, 0.16), roughness=0.7, metallic=0.2)
    MATS["radiator"] = m("shield_radiator", (0.12, 0.13, 0.14), roughness=0.4, metallic=0.7)
    MATS["window"] = m("shield_window_warm", (1.0, 0.85, 0.6), roughness=0.3,
                       emission=(1.0, 0.78, 0.5), emission_strength=3.5)
    MATS["light"] = m("shield_light_orange", (1.0, 0.45, 0.1), roughness=0.3,
                      emission=(1.0, 0.42, 0.08), emission_strength=5.0)
    MATS["red"] = m("shield_light_red", (1.0, 0.12, 0.05), roughness=0.3,
                    emission=(1.0, 0.1, 0.04), emission_strength=5.0)
    MATS["glow"] = m("shield_emitter_cyan", (0.3, 0.85, 1.0), roughness=0.3,
                     emission=(0.25, 0.85, 1.0), emission_strength=8.0)
    MATS["charge"] = m("shield_charge_cyan", (0.3, 0.85, 1.0), roughness=0.3,
                       emission=(0.2, 0.8, 1.0), emission_strength=5.0)


EXTRA_KINDS = {
    "radiator": dict(panel=(0.6, 3.0), tones=[(0.13, 0.14, 0.15), (0.11, 0.12, 0.13),
                                              (0.15, 0.155, 0.16), (0.12, 0.125, 0.13)],
                     rough=(0.38, 0.12), metal=0.7, seam_dark=0.5, rivets=False,
                     chip=(0.45, 0.45, 0.46), chip_metal=1.0, chip_k=0.6, grime_k=0.6,
                     bleach=0.25),
}

H = G = C = L = None   # parts: hull, emitter glow, capacitor strips, lights


def lamp(pos, s=0.8, mat="light"):
    L.box(V(pos), (s, s, s * 0.6), mat, bevel=0.0)


def beacon(pos, r=0.7, mat="light"):
    p = V(pos)
    H.cyl(p - V((0, 0, 0.5)), 0.25, 0.25, 1.0, "dark", segs=6)
    L.cyl(p + V((0, 0, 0.25)), r, r * 0.8, r * 0.9, mat, segs=8)


def polar(r, a, z):
    return V((r * math.cos(a), r * math.sin(a), z))


def cable(pts, r, mat, segs=8):
    """Heavy cable as a chain of tubes through `pts`, with a dark clamp at each joint."""
    pts = [V(p) for p in pts]
    for a, b in zip(pts, pts[1:]):
        H.tube(a, b, r, r, mat, segs=segs)
    for p in pts[1:-1]:
        H.sphere(p, r * 1.08, mat, segs=segs, rings=4)


# ---------------------------------------------------------------- deck
def build_deck():
    prof = [(0.0, -3.2), (12.0, -3.2), (18.0, -1.4), (18.0, -0.2), (18.0, 0.3),
            (17.2, 0.3), (0.0, 0.3)]
    dm = {0: "dark", 1: "dark", 2: "hull2", 3: "hazard", 4: "hazard", 5: "pad"}
    H.lathe(prof, 8, lambda i, j: dm[j], start=math.pi / 8)
    # keel: underside girders on the axes and the diagonals
    for k in range(4):
        a = k * math.pi / 4
        d = V((math.cos(a), math.sin(a), 0))
        H.beam(-d * 15.0 + V((0, 0, -3.6)), d * 15.0 + V((0, 0, -3.6)), 1.4, 0.9, "dark")
    # deck rim edge lamps on the octagon corners
    for k in range(8):
        a = math.pi / 8 + k * math.pi / 4
        lamp(polar(17.6, a, 0.6), 0.8)
    # deck plating stripes between the banks
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        H.box(polar(13.5, a, 0.36), (4.0, 0.3, 0.08), "hazard", rot_z=a, bevel=0.0)


# ---------------------------------------------------------------- reactor drum
def build_drum():
    prof = [(0.0, 0.3), (9.4, 0.3), (9.4, 1.6), (8.5, 1.8), (8.5, 6.0), (8.5, 6.8),
            (8.5, 9.0), (7.2, 10.2), (4.6, 10.6), (0.0, 10.6)]
    dm = {0: "dark", 1: "dark", 2: "dark", 3: "hull", 4: "orange", 5: "hull", 6: "dark",
          7: "hull2", 8: "hull2"}
    H.lathe(prof, 16, lambda i, j: dm[j], start=math.pi / 16)
    for k in range(8):
        a = k * math.pi / 4
        H.box(polar(8.75, a, 5.2), (0.7, 1.1, 7.6), "dark", rot_z=a, bevel=0.0)
        # window strip in each bay between the ribs
        b = a + math.pi / 8
        L.box(polar(8.45, b, 4.0), (0.12, 2.0, 0.45), "window", rot_z=b, bevel=0.0)
        # MLI service panels low on the drum
        H.box(polar(8.6, b, 2.9), (0.3, 2.4, 1.4), "mli", rot_z=b, bevel=0.1)
    # roof: equipment boxes around the mast collar
    for k, (mat, w) in enumerate((("hull", 2.4), ("mli", 2.0), ("hull2", 2.6), ("mli", 2.2))):
        a = math.pi / 4 + k * math.pi / 2 + 0.35
        H.box(polar(6.2, a, 10.7), (w, 1.8, 1.2), mat, rot_z=a, bevel=0.08)


# ---------------------------------------------------------------- capacitor banks
CAP_ANGLES = [math.pi / 4 + k * math.pi / 2 for k in range(4)]
CAP_R = 13.4


def build_capacitors():
    for a in CAP_ANGLES:
        c = polar(CAP_R, a, 0.0)
        rz = Matrix.Rotation(a, 4, "Z")
        H.box(c + V((0, 0, 0.8)), (6.6, 6.6, 1.0), "dark", rot_z=a, bevel=0.05)
        # octagonal body, flats facing radially (start so a flat faces angle a)
        body = [(0.0, 1.3), (2.9, 1.3), (2.9, 1.9), (2.6, 2.0), (2.6, 10.4), (2.9, 10.5),
                (2.9, 11.1), (2.2, 11.6), (0.0, 11.6)]
        bm = {0: "dark", 1: "dark", 2: "dark", 3: "hull", 4: "dark", 5: "dark", 6: "hull2",
              7: "hull2"}
        H.lathe(body, 8, lambda i, j: bm[j], matrix=Matrix.Translation(c) @ rz,
                start=math.pi / 8)
        # orange band ring
        H.lathe([(2.66, 6.9), (2.66, 7.5)], 8, lambda i, j: "orange",
                matrix=Matrix.Translation(c) @ rz, start=math.pi / 8)
        # charge strips on the three outward flats
        flat = 2.6 * math.cos(math.pi / 8)
        for off in (-math.pi / 4, 0.0, math.pi / 4):
            b = a + off
            p = c + polar(flat + 0.06, b, 0.0)
            C.box(p + V((0, 0, 4.3)), (0.12, 0.6, 4.4), "charge", rot_z=b, bevel=0.0)
            C.box(p + V((0, 0, 9.1)), (0.12, 0.6, 1.8), "charge", rot_z=b, bevel=0.0)
        # HV bushings: stack of insulator discs
        top = c + V((0, 0, 11.6))
        H.cyl(top + V((0, 0, 0.5)), 0.7, 0.7, 1.0, "hull2", segs=8)
        for k in range(4):
            H.cyl(top + V((0, 0, 1.15 + k * 0.45)), 1.05, 1.05, 0.22, "dark", segs=10)
        H.cyl(top + V((0, 0, 3.0)), 0.8, 0.8, 0.5, "hull", segs=8)
        lamp(top + V((0, 0, 3.5)), 0.6, "red")
        # heavy cable: bushing top over to the drum shoulder
        inward = polar(1.0, a + math.pi, 0.0)
        p0 = top + V((0, 0, 2.6)) + inward * 0.6
        p3 = polar(7.0, a, 10.4)
        p1 = p0 + inward * 1.8 + V((0, 0, 0.6))
        p2 = p3 + polar(1.6, a, 1.2)
        cable([p0, p1, p2, p3], 0.42, "dark")
        # twin feeder conduits along the deck into the drum skirt
        tang = polar(1.0, a + math.pi / 2, 0.0)
        for s in (-1, 1):
            q0 = c + inward * 2.8 + tang * s * 1.2 + V((0, 0, 0.9))
            q1 = polar(9.5, a, 0.9) + tang * s * 1.2
            H.tube(q0, q1, 0.38, 0.38, "orange" if s < 0 else "hull2", segs=8)
        for t in (0.35, 0.7):
            q = c.lerp(polar(9.5, a, 0.0), t) + inward * 1.0
            H.box(q + V((0, 0, 0.9)), (0.5, 3.4, 1.1), "dark", rot_z=a, bevel=0.0)


# ---------------------------------------------------------------- radiators (edge-on fins)
def build_radiators():
    for sx in (-1, 1):
        x0, x1 = 12.5, 19.5
        xc, ln = sx * (x0 + x1) / 2, x1 - x0
        zb, zt = 1.3, 12.0
        H.box(V((xc, 0, 0.8)), (ln + 0.4, 8.6, 1.0), "dark", bevel=0.05)
        fins = [-3.2, -1.6, 0.0, 1.6, 3.2]
        for y in fins:
            H.box(V((xc, y, (zb + zt) / 2)), (ln, 0.22, zt - zb), "radiator", bevel=0.0)
            for k in range(6):
                z = zb + 1.0 + k * (zt - zb - 2.0) / 5
                H.box(V((xc, y, z)), (ln + 0.1, 0.38, 0.16), "hull2", bevel=0.0)
            H.box(V((xc, y, zt + 0.15)), (ln + 0.3, 0.42, 0.3), "dark", bevel=0.0)
            for x in (sx * x0 - sx * 0.2, sx * x1 + sx * 0.2):
                H.box(V((x, y, (zb + zt) / 2)), (0.3, 0.42, zt - zb), "orange", bevel=0.0)
        # coolant headers across the fins, inner end, top and bottom
        xi = sx * (x0 - 0.9)
        for z, r in ((zb + 0.4, 0.45), (zt - 0.6, 0.35)):
            H.tube(V((xi, fins[0] - 1.0, z)), V((xi, fins[-1] + 1.0, z)), r, r, "hull", segs=8)
            for y in fins:
                H.box(V((sx * (x0 - 0.45), y, z)), (0.9, 0.3, 0.3), "dark", bevel=0.0)
        for y in (fins[0] - 1.0, fins[-1] + 1.0):
            H.tube(V((xi, y, zb + 0.4)), V((xi, y, zt - 0.6)), 0.3, 0.3, "hull", segs=8)
        # coolant loop back into the drum
        for y, z in ((-1.0, 3.0), (1.0, 7.5)):
            H.tube(V((xi, y, z)), V((sx * 8.4, y, z)), 0.45, 0.45, "hull2", segs=8)
        for y in (fins[0], fins[-1]):
            lamp((sx * x1, y, zt + 0.55), 0.6)


# ---------------------------------------------------------------- control block (-Y)
def build_control():
    yc = -14.2
    H.box(V((0, yc, 3.3)), (8.0, 5.6, 6.0), "hull", bevel=0.06)
    H.box(V((0, yc, 6.6)), (8.6, 6.2, 0.6), "dark", bevel=0.05)
    H.box(V((0, yc + 3.6, 2.6)), (5.0, 2.0, 3.6), "hull2", bevel=0.06)   # tunnel to drum
    L.box(V((0, yc - 2.83, 4.6)), (6.4, 0.08, 0.6), "window", bevel=0.0)
    for sx in (-1, 1):
        L.box(V((sx * 4.03, yc, 4.6)), (0.08, 4.4, 0.6), "window", bevel=0.0)
    H.box(V((0, yc - 2.9, 1.6)), (8.2, 0.2, 0.5), "orange", bevel=0.0)
    H.box(V((2.0, yc + 0.5, 7.4)), (2.6, 2.4, 1.0), "mli", bevel=0.08)
    parts.dish(H, V((-1.8, yc - 0.6, 7.6)), 1.5, V((-0.3, -0.6, 1.0)), "hull", "dark",
               depth=0.4, segs=12)
    H.cyl(V((2.6, yc - 2.0, 9.0)), 0.16, 0.08, 4.0, "dark", segs=6)
    lamp((2.6, yc - 2.0, 11.1), 0.5, "red")
    for sx in (-1, 1):
        lamp((sx * 4.2, yc - 2.9, 7.0), 0.7)


# ---------------------------------------------------------------- link port (+Y)
def build_link():
    lx, ly, lz = LINK_POS
    H.box(V((lx, 16.5, lz)), (7.0, 8.0, 7.0), "hull2", bevel=0.06)
    H.box(V((lx, 16.5, lz + 3.7)), (7.4, 8.2, 0.4), "hull", bevel=0.05)
    for sx in (-1, 1):
        H.box(V((sx * 3.45, 16.5, lz + 3.95)), (0.5, 8.2, 0.12), "orange", bevel=0.0)
    H.box(V((1.2, 15.6, lz + 4.4)), (2.6, 3.0, 1.0), "mli", bevel=0.08)
    H.box(V((lx, 16.5, lz - 3.7)), (7.4, 8.2, 0.4), "dark", bevel=0.0)
    H.box(V((lx, 10.0, 11.2)), (4.4, 5.6, 3.6), "hull", bevel=0.06)     # gallery to drum
    H.box(V((lx, 10.0, 13.1)), (4.6, 5.8, 0.3), "dark", bevel=0.0)
    H.box(V((lx, 16.5, 4.4)), (3.6, 3.6, 8.2), "dark", bevel=0.05)        # pylon
    for sx in (-1, 1):
        H.beam(V((sx * 3.0, 14.0, 0.4)), V((sx * 1.6, 15.8, 8.2)), 0.5, 0.5, "orange")
        L.box(V((sx * 3.53, 16.5, lz + 1.6)), (0.08, 6.0, 0.5), "window", bevel=0.0)
    H.cyl(V((lx, ly - 0.4, lz)), 3.8, 3.8, 0.8, "dark", segs=12, axis_rot=ALONG_Y)
    H.cyl(V((lx, ly - 0.05, lz)), 3.2, 3.2, 0.1, "hazard", segs=12, axis_rot=ALONG_Y)
    for sx in (-1, 1):
        for sz in (-1, 1):
            lamp((lx + sx * 3.9, 20.0, lz + sz * 3.9), 0.7)


# ---------------------------------------------------------------- mast
def build_mast():
    prof = [(0.0, 10.6), (4.4, 10.6), (4.4, 11.6), (3.4, 12.6), (2.3, 12.8), (2.3, 18.0),
            (2.3, 18.8), (1.9, 26.0), (1.9, 26.8), (1.5, 33.0), (0.0, 33.0)]
    pm = {0: "dark", 1: "dark", 2: "hull2", 3: "dark", 4: "hull", 5: "orange", 6: "hull",
          7: "orange", 8: "hull2", 9: "hull2"}
    H.lathe(prof, 12, lambda i, j: pm[j], start=math.pi / 12)
    # three truss legs from the drum roof up the column
    legs = [math.pi / 2 + k * 2 * math.pi / 3 + math.pi / 3 for k in range(3)]

    def leg_at(a, z):
        t = (z - 10.6) / (30.0 - 10.6)
        return polar(6.6 + (2.0 - 6.6) * t, a, z)
    for a in legs:
        H.box(polar(6.6, a, 11.0), (1.6, 1.6, 0.8), "dark", rot_z=a, bevel=0.05)
        H.beam(leg_at(a, 10.6), leg_at(a, 30.0), 0.6, 0.6, "dark")
    for z in (16.0, 22.0, 27.0):
        for k in range(3):
            H.beam(leg_at(legs[k], z), leg_at(legs[(k + 1) % 3], z), 0.3, 0.3, "dark")
            r = (leg_at(legs[k], z) - V((0, 0, z))).length
            H.beam(leg_at(legs[k], z), polar(2.0, legs[k], z), 0.25, 0.25, "dark")
    for k in range(3):   # diagonal braces
        for z0, z1 in ((10.6, 16.0), (16.0, 22.0), (22.0, 27.0)):
            H.beam(leg_at(legs[k], z0), leg_at(legs[(k + 1) % 3], z1), 0.2, 0.2, "dark")
    # cable runs up the column (power to the projector)
    for a in (0.0, math.pi):
        H.tube(polar(2.6, a, 11.2), polar(2.6, a, 18.0), 0.35, 0.35, "dark", segs=8)
        H.tube(polar(2.6, a, 18.0), polar(1.95, a, 32.6), 0.35, 0.35, "dark", segs=8)
    # service platform with railing lamps
    H.lathe([(2.0, 21.6), (4.0, 21.6), (4.0, 22.0), (2.0, 22.0)], 12,
            lambda i, j: "dark" if j != 0 else "hull2", start=math.pi / 12)
    for k in range(4):
        lamp(polar(3.8, k * math.pi / 2 + math.pi / 4, 22.3), 0.5)
    for k in range(3):
        lamp(polar(1.7, legs[k], 32.2), 0.55, "red")


# ---------------------------------------------------------------- projector array
def build_projector():
    hub = [(0.0, 32.5), (2.6, 32.5), (2.9, 33.4), (2.0, 34.0), (2.0, 37.6), (1.4, 38.2),
           (0.0, 38.2)]
    hm = {0: "dark", 1: "hull2", 2: "dark", 3: "hull", 4: "dark", 5: "dark"}
    H.lathe(hub, 12, lambda i, j: hm[j], start=math.pi / 12)
    G.lathe([(2.05, 34.6), (2.05, 35.1)], 12, lambda i, j: "glow", start=math.pi / 12)
    n = 12
    tilt = 0.32
    for k in range(n):
        a = k * 2 * math.pi / n
        rm = Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(tilt, 4, "Y")
        base = polar(2.0, a, 34.0)

        def at(lx, lz):
            return base + (rm @ V((lx, 0.0, lz, 0.0))).to_3d()
        # blade: radial length 3.4, height 6.4, leaning outward
        H.box(at(1.7, 3.2), (3.4, 0.32, 6.4), "hull2", r=rm, bevel=0.0)
        H.box(at(0.25, 3.2), (0.5, 0.5, 6.6), "dark", r=rm, bevel=0.0)
        H.box(at(1.7, 6.5), (3.6, 0.45, 0.35), "dark", r=rm, bevel=0.0)
        # emitter edge strip on the outer edge of each blade
        G.box(at(3.48, 3.4), (0.22, 0.42, 5.6), "glow", r=rm, bevel=0.0)
    # crown ring tying the fin tips, glow ring inside it, emitter core on top
    H.torus(V((0, 0, 39.7)), 5.6, 0.32, "dark", segs=24, minor_segs=6)
    G.torus(V((0, 0, 38.8)), 3.7, 0.2, "glow", segs=24, minor_segs=6)
    H.cyl(V((0, 0, 38.8)), 0.9, 0.6, 1.2, "hull", segs=10)
    G.sphere(V((0, 0, 40.2)), 1.0, "glow", segs=12, rings=6)
    H.cyl(V((0, 0, 41.3)), 0.12, 0.12, 0.6, "dark", segs=6)


def recentre(obj, origin):
    o = V(origin)
    obj.data.transform(Matrix.Translation(-o))
    obj.location = o


def build_shield():
    global H, G, C, L
    build_materials()
    H = parts.PanelPart("shield_base", MATS)
    G = parts.PanelPart("shield_emitter_glow", MATS)
    C = parts.PanelPart("shield_capacitors", MATS)
    L = parts.PanelPart("shield_lights", MATS)
    for b in (build_deck, build_drum, build_capacitors, build_radiators, build_control,
              build_link, build_mast, build_projector):
        b()
    root = parts.make_root("shield_generator", size=10)
    objs = [p.finish(root) for p in (H, G, C, L)]
    for o in objs[1:]:   # flat emissive meshes: no atlas, no panel layer
        o.data.uv_layers.remove(o.data.uv_layers["panel"])
    parts.add_empty("shield_emitter_point", root, EMITTER_POS, size=3)
    parts.add_empty("link_point", root, LINK_POS, rot_z=0.0, size=4)
    return root, objs


# ---------------------------------------------------------------- textures
def texture_shield(objs):
    """Bake one 2048 atlas for the base (station surface kinds), as gen_factory does."""
    st.ATLAS_RES = ATLAS_RES
    st.KINDS.update(EXTRA_KINDS)
    atlas_keys = [k for k in st.KINDS if k in MATS]
    atlas_mats = {MATS[k] for k in atlas_keys}
    st.unwrap_atlas(objs, atlas_mats)
    st.setup_cycles(8)
    masks = st.new_image("shield_masks", ATLAS_RES, True)
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

    albedo = st.new_image("shield_albedo", ATLAS_RES, False)
    mr = st.new_image("shield_mr", ATLAS_RES, True)
    normal = st.new_image("shield_normal", ATLAS_RES, True)
    for i, k in enumerate(atlas_keys):
        nb = st.NB(MATS[k])
        outs = st.build_surface(nb, k, st.KINDS[k], masks, i + 1, [(0.0, 0.0)])
        bms[k] = st.BakeMat(MATS[k], outs, nb)
    for name, img, kind in (("albedo", albedo, "EMIT"), ("mr", mr, "EMIT"),
                            ("normal", normal, "NORMAL")):
        for bm in bms.values():
            bm.set_pass(name, img)
        st.bake(objs, kind, 8, img)
    p_alb = st.save_image(albedo, "shield_albedo.jpg", "JPEG", 92)
    p_mr = st.save_image(mr, "shield_mr.png", "PNG")
    p_nrm = st.save_image(normal, "shield_normal.png", "PNG")

    hull = st.pbr_material("shield_hull", st.load_saved(p_alb, False),
                           st.load_saved(p_mr, True), st.load_saved(p_nrm, True))
    mapping = {m: hull for m in atlas_mats}
    for o in objs:
        st.remap_materials(o, mapping)
        o.data.uv_layers.remove(o.data.uv_layers["panel"])
    for img in (masks, albedo, mr, normal):
        bpy.data.images.remove(img)
    for m in atlas_mats:
        if m.users == 0:
            bpy.data.materials.remove(m)


def join_lights(base, lights):
    """Warm lamps/windows ride on shield_base (flat emissive materials, no atlas)."""
    bpy.ops.object.select_all(action="DESELECT")
    lights.select_set(True)
    base.select_set(True)
    bpy.context.view_layer.objects.active = base
    bpy.ops.object.join()
    base.name = base.data.name = "shield_base"


# ---------------------------------------------------------------- previews
def previews():
    target = (0.0, 0.0, 16.0)
    common.setup_preview(cam_loc=(-55, -82, 95), cam_target=target, ortho_scale=66,
                         res=(1200, 1200), key_dir=(-0.6, -0.35, 0.7), key_energy=3.5)
    common.render(os.path.join(common.PREVIEW_DIR, "shield_generator_preview.png"))
    scene = bpy.context.scene
    cam = scene.camera
    cam.location = (0, 0, 150)
    cam.rotation_euler = (0, 0, 0)
    cam.data.ortho_scale = 48
    scene.render.resolution_x, scene.render.resolution_y = 1200, 1200
    common.render(os.path.join(common.PREVIEW_DIR, "shield_generator_top.png"))


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_shield()
    base, glow, caps, lights = objs
    if "--no-textures" not in argv:
        texture_shield([base])
    join_lights(base, lights)
    recentre(glow, GLOW_ORIGIN)
    recentre(caps, CAP_ORIGIN)
    total = 0
    for o in (base, glow, caps):
        tris = sum(len(pl.vertices) - 2 for pl in o.data.polygons)
        total += tris
        bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
        lo = [min(v[i] for v in bb) for i in range(3)]
        hi = [max(v[i] for v in bb) for i in range(3)]
        rad = max(math.hypot(*(o.matrix_world @ v.co).xy) for v in o.data.vertices)
        print(f"STAT {o.name} tris={tris} mats={[m.name for m in o.data.materials]} "
              f"bbox={[round(c, 2) for c in lo]}..{[round(c, 2) for c in hi]} rxy={rad:.1f}")
    print(f"STAT total tris={total}")
    parts.save_blend(BLEND)
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_mainfile(filepath=BLEND)
    common.export_glb(root, OUT, export_image_format="JPEG", export_image_quality=90)
    if "--no-preview" not in argv:
        previews()


main()
