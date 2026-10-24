"""Generate the station defense turret (point-defense / flak platform) .glb and previews.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_defense_turret.py
  Add `-- --no-preview` to skip the PNG renders, `-- --no-textures` for flat materials.
Textures: one 1024 atlas baked with the station_textures surface kinds (plus "gun" and
"radiator"), saved as blender/textures/defense_turret_*.{jpg,png}, embedded as JPEG.

Layout (Blender Z up, exported +Y up; Blender +Y = Godot -Z = the barrels' rest heading).
Centre on the yaw axis, origin on the play plane z = 0.
  lower hub       ammo magazine node z 3.6..5.9, support truss up to the platform
  base platform   armoured octagon, 17 m flat to flat, z 7.6..15.6, deck at z 15.6
  link port       on the +Y face (Godot -Z), flange face at y = 10, centre z = 12
  radiators       two horizontal finned panels per side on the +-X faces, out to x = +-11
  turret          bearing on the deck, armoured housing, rear magazine, feed chutes,
                  sensor dish, rear radiator fins, status beacon
  guns            twin cannons in a mantlet, muzzles at y = 11.05, z = 17.6
Hierarchy: defense_turret (empty root)
  -> turret_base (mesh, origin 0) -> link_point (empty)
  -> turret_yaw (mesh, origin on the yaw axis at the deck, z = 15.6)
       -> turret_pitch (mesh, origin on the pitch axis) -> muzzle_l, muzzle_r (empties)
       -> turret_status_light (emissive mesh, own material "turret_status_light")
All empties are unrotated: Godot -Z = Blender +Y (out of the barrels / out of the port).
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
ALONG_Y = parts.ALONG_Y
ALONG_X = parts.ALONG_X
OUT = os.path.join(common.ROOT, "assets", "models", "buildings", "defense_turret.glb")
BLEND = os.path.join(common.ROOT, "blender", "defense_turret.blend")
ATLAS_RES = 1024

APO = 8.5                 # platform side apothem (flat to flat 17 m)
DECK_APO = 7.4            # deck apothem after the top chamfer
Z_BOT, Z_SIDE0, Z_SIDE1, DECK_Z = 7.6, 8.4, 14.6, 15.6
LINK_Y, LINK_Z = 10.0, 12.0
YAW_Z = DECK_Z
PITCH_Y, PITCH_Z = 1.8, 17.6
GUN_X = 1.2
MUZZLE_Y = 11.05
OCT0 = math.radians(22.5)  # lathe start so the octagon has flats facing +-X / +-Y

MATS = {}


def circ(apothem):
    return apothem / math.cos(math.pi / 8)


def build_materials():
    m = common.make_material
    MATS["hull"] = m("turret_hull_white", (0.78, 0.78, 0.76), roughness=0.45, metallic=0.1)
    MATS["hull2"] = m("turret_hull_grey", (0.50, 0.52, 0.55), roughness=0.5, metallic=0.15)
    MATS["dark"] = m("turret_structure_dark", (0.06, 0.065, 0.07), roughness=0.55, metallic=0.5)
    MATS["orange"] = m("turret_accent_orange", (0.85, 0.28, 0.03), roughness=0.45)
    MATS["hazard"] = m("turret_hazard", (0.8, 0.55, 0.02), roughness=0.5)
    MATS["pad"] = m("turret_deck", (0.15, 0.15, 0.16), roughness=0.7, metallic=0.2)
    MATS["gun"] = m("turret_gunmetal", (0.13, 0.14, 0.16), roughness=0.38, metallic=0.7)
    MATS["radiator"] = m("turret_radiator", (0.12, 0.13, 0.14), roughness=0.4, metallic=0.7)
    MATS["light"] = m("turret_light_orange", (1.0, 0.45, 0.1), roughness=0.3,
                      emission=(1.0, 0.42, 0.08), emission_strength=5.0)
    MATS["red"] = m("turret_light_red", (1.0, 0.12, 0.05), roughness=0.3,
                    emission=(1.0, 0.1, 0.04), emission_strength=5.0)
    MATS["status"] = m("turret_status_light", (1.0, 0.16, 0.04), roughness=0.3,
                       emission=(1.0, 0.14, 0.03), emission_strength=6.0)


EXTRA_KINDS = {
    "gun": dict(panel=(1.2, 1.2), tones=[(0.13, 0.14, 0.16), (0.11, 0.12, 0.14),
                                         (0.15, 0.16, 0.18), (0.12, 0.13, 0.15)],
                rough=(0.38, 0.10), metal=0.7, seam_dark=0.45, rivets=False,
                chip=(0.50, 0.51, 0.53), chip_metal=1.0, chip_k=0.9, grime_k=0.7,
                bleach=0.15),
    "radiator": dict(panel=(0.6, 3.0), tones=[(0.13, 0.14, 0.15), (0.11, 0.12, 0.13),
                                              (0.15, 0.155, 0.16), (0.12, 0.125, 0.13)],
                     rough=(0.38, 0.12), metal=0.7, seam_dark=0.5, rivets=False,
                     chip=(0.45, 0.45, 0.46), chip_metal=1.0, chip_k=0.6, grime_k=0.6,
                     bleach=0.25),
}
EMISSIVE = ("light", "red")

B = Y = P = S = None   # parts: base, yaw, pitch, status light


def face_frame(theta, apothem, z):
    """Frame on the octagon face whose outward normal is at angle theta (local X = out)."""
    return (Matrix.Translation((apothem * math.cos(theta), apothem * math.sin(theta), z))
            @ Matrix.Rotation(theta, 4, "Z"))


def oct_band(p, a0, a1, z0, z1, mat):
    """Flat octagonal ring (apothem a0..a1) as 8 trapezoid slabs."""
    for k in range(8):
        t0, t1 = OCT0 + k * math.pi / 4, OCT0 + (k + 1) * math.pi / 4
        r0, r1 = circ(a0), circ(a1)
        pts = [(r0 * math.cos(t0), r0 * math.sin(t0)), (r1 * math.cos(t0), r1 * math.sin(t0)),
               (r1 * math.cos(t1), r1 * math.sin(t1)), (r0 * math.cos(t1), r0 * math.sin(t1))]
        p.slab(pts, z0, z1, mat)


# ---------------------------------------------------------------- base
def build_platform():
    # armoured octagon: bottom chamfer, vertical armoured sides, top chamfer, deck
    prof = [(0.0, Z_BOT), (circ(7.0), Z_BOT), (circ(APO), Z_SIDE0), (circ(APO), Z_SIDE1),
            (circ(DECK_APO), DECK_Z), (0.0, DECK_Z)]
    pm = {0: "dark", 1: "hull2", 2: "hull2", 3: "hull", 4: "pad"}
    B.lathe(prof, 8, lambda i, j: pm[j], start=OCT0)
    # armour plates on the five plain faces, the rear one with a maintenance hatch
    for k in range(8):
        th = k * math.pi / 4
        if k in (0, 2, 4):        # +X radiators, +Y port, -X radiators
            continue
        for ly in (-1.75, 1.75):
            fr = face_frame(th, APO + 0.14, 11.5) @ Matrix.Translation((0, ly, 0))
            B.box(V((0, 0, 0)), (0.28, 3.15, 5.4), "hull", r=fr, bevel=0.06)
            B.box(V((0, 0, 0)), (0.06, 2.9, 0.35),
                  "orange" if k in (1, 3) else "dark",
                  r=fr @ Matrix.Translation((0.16, 0, 2.15)), bevel=0.0)
        if k == 6:   # rear: hatch with a hazard frame between the plates
            fr = face_frame(th, APO + 0.05, 10.6)
            B.box(V((0, 0, 0)), (0.1, 0.36, 3.6), "hazard", r=fr, bevel=0.0)
            B.box(V((0, 0, 0)), (0.16, 0.24, 3.0), "dark", r=fr, bevel=0.0)
    # radiator mounting faces get a dark service panel
    for th in (0.0, math.pi):
        B.box(V((0, 0, 0)), (0.2, 6.2, 5.6), "dark", r=face_frame(th, APO + 0.05, 11.5),
              bevel=0.02)
    # deck: bearing race, hazard sweep ring, rim lip, hatches, corner beacons
    B.cyl(V((0, 0, DECK_Z + 0.12)), 4.35, 4.35, 0.24, "dark", segs=32)
    oct_band(B, 4.75, 5.35, DECK_Z, DECK_Z + 0.05, "hazard")
    oct_band(B, DECK_APO - 0.35, DECK_APO - 0.05, DECK_Z, DECK_Z + 0.22, "dark")
    for x, y in ((-5.2, -2.6), (5.2, -2.6)):
        B.box(V((x, y, DECK_Z + 0.06)), (1.3, 1.6, 0.14), "hull2", bevel=0.05)
    for k in range(4):
        th = math.pi / 4 + k * math.pi / 2
        r = circ(DECK_APO) - 0.9
        c = V((r * math.cos(th), r * math.sin(th), DECK_Z))
        B.cyl(c + V((0, 0, 0.3)), 0.22, 0.22, 0.6, "dark", segs=6)
        B.cyl(c + V((0, 0, 0.75)), 0.38, 0.3, 0.32, "light", segs=8)


def build_port():
    """Corridor port on the +Y face (Godot -Z), flange face at y = LINK_Y, centre z 12."""
    B.box(V((0, 8.5, LINK_Z)), (7.4, 2.2, 7.0), "hull", bevel=0.04)
    B.cyl(V((0, 9.8, LINK_Z)), 3.25, 3.25, 0.4, "dark", segs=16, axis_rot=ALONG_Y)
    B.cyl(V((0, 10.0, LINK_Z)), 2.35, 2.35, 0.04, "orange", segs=16, axis_rot=ALONG_Y)
    B.cyl(V((0, 10.0, LINK_Z)), 1.2, 1.2, 0.07, "hull2", segs=12, axis_rot=ALONG_Y)
    for z in (LINK_Z + 3.25, LINK_Z - 3.25):
        B.box(V((0, 9.63, z)), (7.4, 0.08, 0.45), "hazard", bevel=0.0)
    for sx in (-1, 1):
        B.box(V((sx * 3.85, 9.2, LINK_Z)), (0.4, 0.4, 0.4), "light", bevel=0.0)


def build_radiators():
    for sx in (-1, 1):
        B.box(V((sx * 9.05, 0, 11.5)), (1.1, 1.8, 5.0), "dark", bevel=0.05)
        for z in (9.9, 13.1):
            x0, x1 = sx * 9.4, sx * 11.2
            xc = (x0 + x1) / 2
            B.box(V((xc, 0, z)), (abs(x1 - x0), 5.8, 0.12), "radiator", bevel=0.0)
            for k in range(7):
                y = -2.5 + k * 5.0 / 6
                B.box(V((xc, y, z + 0.09)), (abs(x1 - x0) - 0.1, 0.07, 0.07), "hull2", bevel=0.0)
            for y in (-2.95, 2.95):
                B.box(V((xc, y, z)), (abs(x1 - x0) + 0.1, 0.16, 0.22), "dark", bevel=0.0)
            B.box(V((sx * 11.3, 0, z)), (0.2, 6.0, 0.24), "dark", bevel=0.0)
            B.beam(V((sx * 8.9, 0, z)), V((x0, 0, z)), 0.5, 0.35, "hull2")
        B.box(V((sx * 11.3, 2.9, 13.1 + 0.2)), (0.3, 0.3, 0.2), "light", bevel=0.0)


def build_truss():
    hub_top = 5.9
    prof = [(0.0, 3.6), (circ(2.2), 3.6), (circ(2.8), 4.2), (circ(2.8), 5.4),
            (circ(2.2), hub_top), (0.0, hub_top)]
    hm = {0: "dark", 1: "hull2", 2: "hull", 3: "hull2", 4: "dark"}
    B.lathe(prof, 8, lambda i, j: hm[j], start=OCT0)
    B.cyl(V((0, 0, 4.8)), circ(2.85), circ(2.85), 0.3, "orange", segs=8,
          axis_rot=Matrix.Rotation(OCT0, 4, "Z"))
    B.cyl(V((0, 0, 3.45)), 0.35, 0.3, 0.3, "red", segs=8)
    # central power / ammo shaft, two hoist conduits
    B.cyl(V((0, 0, (hub_top + Z_BOT) / 2)), 1.0, 1.0, Z_BOT - hub_top + 0.2, "dark", segs=10)
    for sx in (-1, 1):
        B.cyl(V((sx * 1.55, 0.4, (hub_top + Z_BOT) / 2)), 0.32, 0.32, Z_BOT - hub_top + 0.2,
              "hull2", segs=8)
    # eight legs, zigzag braces, mid ring
    tops, bots = [], []
    for k in range(8):
        a = OCT0 + k * math.pi / 4
        tops.append(V((6.0 * math.cos(a), 6.0 * math.sin(a), Z_BOT + 0.05)))
        bots.append(V((2.6 * math.cos(a), 2.6 * math.sin(a), 5.0)))
    for k in range(8):
        B.beam(bots[k], tops[k], 0.45, 0.45, "dark")
        n = (k + 1) % 8
        B.beam(bots[k], tops[n], 0.22, 0.22, "dark")
        mk, mn = bots[k].lerp(tops[k], 0.55), bots[n].lerp(tops[n], 0.55)
        B.beam(mk, mn, 0.26, 0.26, "hull2")


# ---------------------------------------------------------------- turret (yaw)
def build_housing():
    Y.cyl(V((0, 0, YAW_Z + 0.42)), 4.0, 4.0, 0.36, "hull2", segs=32)
    Y.cyl(V((0, 0, YAW_Z + 0.68)), 3.7, 3.6, 0.2, "dark", segs=32)
    rings = [parts.oct_ring(-3.8, 5.8, 2.2, 0.7, z0=17.45),
             parts.oct_ring(-3.2, 6.6, 2.6, 0.8, z0=17.55),
             parts.oct_ring(1.4, 7.0, 2.8, 0.9, z0=17.6),
             parts.oct_ring(2.6, 5.8, 2.2, 0.9, z0=17.6)]
    edge = {0: "hull", 1: "hull2", 2: "hull", 3: "hull2", 4: "hull", 5: "dark", 6: "dark",
            7: "dark"}

    def hm(i, j):
        if i == 2:
            return "hull2" if j in (1, 2, 3) else "dark"
        return edge[j]
    Y.loft(rings, "dark", mat_fn=hm)
    # cheek armour, orange id stripes, hazard strip at the glacis edge
    for sx in (-1, 1):
        Y.box(V((sx * 3.58, -0.9, 17.4)), (0.26, 3.8, 1.5), "hull2", bevel=0.08)
        Y.box(V((sx * 3.72, -0.9, 17.4)), (0.04, 3.4, 0.25), "orange", bevel=0.0)
        Y.box(V((sx * 2.2, -1.0, 19.0)), (0.5, 4.2, 0.08), "orange", bevel=0.0)
        # trunnion bearings on the pitch axis
        Y.cyl(V((sx * 3.62, PITCH_Y, PITCH_Z)), 0.62, 0.62, 0.5, "gun", segs=12, axis_rot=ALONG_X)
        Y.cyl(V((sx * 3.9, PITCH_Y, PITCH_Z)), 0.35, 0.35, 0.2, "dark", segs=10, axis_rot=ALONG_X)
    Y.box(V((0, 1.05, 19.0)), (3.6, 0.5, 0.07), "hazard", bevel=0.0)
    # roof hatch and vents
    Y.box(V((0, -1.4, 19.0)), (1.4, 1.4, 0.14), "hull2", bevel=0.05)
    Y.box(V((0, -1.4, 19.08)), (1.1, 1.1, 0.04), "dark", bevel=0.0)
    # rear magazine
    Y.box(V((0, -4.45, 17.3)), (4.8, 1.6, 2.0), "hull2", bevel=0.06)
    Y.box(V((0, -5.27, 17.3)), (4.0, 0.06, 0.4), "hazard", bevel=0.0)
    for sx in (-1, 1):
        Y.box(V((sx * 2.48, -4.45, 17.3)), (0.12, 1.2, 1.6), "dark", bevel=0.0)
    # ammo feed chutes: magazine -> over the shoulder -> trunnion
    for sx in (-1, 1):
        pts = [V((sx * 2.3, -4.1, 18.25)), V((sx * 2.95, -3.0, 18.95)),
               V((sx * 3.3, -1.0, 19.0)), V((sx * 3.55, 0.8, 18.7)),
               V((sx * 3.62, PITCH_Y - 0.25, 18.15))]
        for a, b in zip(pts, pts[1:]):
            Y.beam(a, b, 0.5, 0.42, "gun")
            n = max(1, int((b - a).length / 0.55))
            for t in range(n):
                c = a.lerp(b, (t + 0.5) / n)
                Y.beam(c - (b - a).normalized() * 0.07, c + (b - a).normalized() * 0.07,
                       0.6, 0.5, "dark")
    # rear radiator fins
    for sx in (-1, 1):
        Y.beam(V((sx * 2.4, -4.0, 17.6)), V((sx * 2.9, -4.4, 17.6)), 0.3, 0.3, "dark")
        Y.box(V((sx * 3.0, -5.55, 17.6)), (0.12, 3.0, 1.9), "radiator", bevel=0.0)
        for k in range(5):
            Y.box(V((sx * 3.0, -6.75 + k * 0.6, 17.6)), (0.2, 0.06, 1.8), "hull2", bevel=0.0)
        Y.box(V((sx * 3.0, -5.55, 18.6)), (0.22, 3.1, 0.14), "dark", bevel=0.0)
        Y.box(V((sx * 3.0, -7.05, 18.6)), (0.25, 0.25, 0.2), "light", bevel=0.0)
    # sensor dish on a mast (rear left), status beacon post (rear right)
    Y.cyl(V((-2.2, -2.6, 19.3)), 0.3, 0.2, 0.7, "dark", segs=8)
    Y.cyl(V((-2.2, -2.6, 19.62)), 0.18, 0.18, 0.2, "gun", segs=8)
    parts.dish(Y, V((-2.2, -2.6, 19.62)), 0.95, (0.0, 0.7, 0.7), "hull", "dark", depth=0.38,
               segs=14)
    Y.cyl(V((2.2, -2.8, 19.25)), 0.22, 0.22, 0.6, "dark", segs=8)
    Y.cyl(V((2.2, -2.8, 19.56)), 0.55, 0.55, 0.06, "gun", segs=10)
    # small corner lights
    for sx in (-1, 1):
        Y.box(V((sx * 2.75, -3.6, 18.7)), (0.22, 0.22, 0.16), "light", bevel=0.0)


def build_status_light():
    S.cyl(V((2.2, -2.8, 19.8)), 0.55, 0.48, 0.42, "status", segs=12)
    S.cyl(V((2.2, -2.8, 20.06)), 0.36, 0.14, 0.12, "status", segs=12)


# ---------------------------------------------------------------- guns (pitch)
def build_guns():
    P.box(V((0, 2.55, PITCH_Z)), (4.0, 1.9, 2.0), "gun", bevel=0.14)
    P.box(V((0, 3.55, PITCH_Z)), (3.5, 0.2, 1.7), "dark", bevel=0.04)
    P.box(V((0, 2.4, PITCH_Z + 1.12)), (0.9, 1.0, 0.45), "dark", bevel=0.1)   # sight
    P.box(V((0, 2.92, PITCH_Z + 1.12)), (0.5, 0.06, 0.22), "gun", bevel=0.0)
    for sx in (-1, 1):
        x = sx * GUN_X
        P.cyl(V((x, 4.55, PITCH_Z)), 0.52, 0.5, 2.1, "gun", segs=14, axis_rot=ALONG_Y)
        for y in (3.75, 5.45):
            P.cyl(V((x, y, PITCH_Z)), 0.58, 0.58, 0.16, "dark", segs=14, axis_rot=ALONG_Y)
        P.cyl(V((x, 4.6, PITCH_Z)), 0.54, 0.54, 0.3, "orange", segs=14, axis_rot=ALONG_Y)
        P.cyl(V((x, 7.95, PITCH_Z)), 0.31, 0.29, 4.7, "gun", segs=12, axis_rot=ALONG_Y)
        P.cyl(V((x, 7.6, PITCH_Z)), 0.38, 0.38, 0.35, "dark", segs=12, axis_rot=ALONG_Y)
        P.cyl(V((x, 10.62, PITCH_Z)), 0.44, 0.42, 0.85, "dark", segs=8, axis_rot=ALONG_Y)
        for y in (10.38, 10.72):
            P.box(V((x, y, PITCH_Z)), (1.0, 0.14, 0.5), "gun", bevel=0.0)
        P.cyl(V((x, MUZZLE_Y - 0.02, PITCH_Z)), 0.2, 0.2, 0.04, "dark", segs=8, axis_rot=ALONG_Y)


# ---------------------------------------------------------------- assembly
def build():
    global B, Y, P, S
    build_materials()
    B = parts.PanelPart("turret_base", MATS)
    Y = parts.PanelPart("turret_yaw", MATS)
    P = parts.PanelPart("turret_pitch", MATS)
    S = parts.PanelPart("turret_status_light", MATS)
    for f in (build_platform, build_port, build_radiators, build_truss, build_housing,
              build_status_light, build_guns):
        f()
    root = parts.make_root("defense_turret", size=6)
    objs = [p.finish(root) for p in (B, Y, P, S)]
    objs[3].data.uv_layers.remove(objs[3].data.uv_layers["panel"])
    return root, objs


def reorigin(obj, parent, world_origin, parent_world):
    o = V(world_origin)
    obj.data.transform(Matrix.Translation(-o))
    obj.parent = parent
    obj.location = o - V(parent_world)


def rig(root, objs):
    base, yaw, pitch, light = objs
    yaw_o = V((0, 0, YAW_Z))
    pitch_o = V((0, PITCH_Y, PITCH_Z))
    light_o = V((2.2, -2.8, 19.8))
    reorigin(yaw, root, yaw_o, (0, 0, 0))
    reorigin(pitch, yaw, pitch_o, yaw_o)
    reorigin(light, yaw, light_o, yaw_o)
    for name, sx in (("muzzle_l", -1), ("muzzle_r", 1)):
        parts.add_empty(name, pitch, V((sx * GUN_X, MUZZLE_Y, PITCH_Z)) - pitch_o, size=1.0)
    parts.add_empty("link_point", base, (0.0, LINK_Y, LINK_Z), size=3)


# ---------------------------------------------------------------- textures
def texture(objs):
    st.ATLAS_RES = ATLAS_RES
    st.KINDS.update(EXTRA_KINDS)
    atlas_keys = [k for k in st.KINDS if k in MATS]
    atlas_mats = {MATS[k] for k in atlas_keys}
    emissive = {MATS[k] for k in EMISSIVE}
    st.unwrap_atlas(objs, atlas_mats)
    for o in objs:
        st.zero_uvs(o, emissive)
    st.setup_cycles(8)
    dummy = st.new_image("bake_dummy", 8, False)
    for m in emissive:
        st.add_dummy_target(m, dummy)
    masks = st.new_image("turret_masks", ATLAS_RES, True)
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

    albedo = st.new_image("turret_albedo", ATLAS_RES, False)
    mr = st.new_image("turret_mr", ATLAS_RES, True)
    normal = st.new_image("turret_normal", ATLAS_RES, True)
    for i, k in enumerate(atlas_keys):
        nb = st.NB(MATS[k])
        # pad rings / scorch need a pad centre; put it far away (no landing pad here)
        outs = st.build_surface(nb, k, st.KINDS[k], masks, i + 1, [(1e4, 1e4)])
        bms[k] = st.BakeMat(MATS[k], outs, nb)
    for name, img, kind in (("albedo", albedo, "EMIT"), ("mr", mr, "EMIT"),
                            ("normal", normal, "NORMAL")):
        for bm in bms.values():
            bm.set_pass(name, img)
        st.bake(objs, kind, 8, img)
    p_alb = st.save_image(albedo, "defense_turret_albedo.jpg", "JPEG", 92)
    p_mr = st.save_image(mr, "defense_turret_mr.png", "PNG")
    p_nrm = st.save_image(normal, "defense_turret_normal.png", "PNG")
    for m in emissive:
        st.remove_dummy_target(m)

    hull = st.pbr_material("defense_turret_hull", st.load_saved(p_alb, False),
                           st.load_saved(p_mr, True), st.load_saved(p_nrm, True))
    mapping = {m: hull for m in atlas_mats}
    for o in objs:
        st.remap_materials(o, mapping)
        o.data.uv_layers.remove(o.data.uv_layers["panel"])
    for img in (dummy, masks, albedo, mr, normal):
        bpy.data.images.remove(img)
    for m in atlas_mats:
        if m.users == 0:
            bpy.data.materials.remove(m)


# ---------------------------------------------------------------- previews
def previews(objs):
    target = (0.0, 0.5, 11.5)
    common.setup_preview(cam_loc=(-30, 34, 40), cam_target=target, ortho_scale=31,
                         res=(1600, 1200), key_dir=(-0.5, 0.45, 0.75), key_energy=3.5)
    common.render(os.path.join(common.PREVIEW_DIR, "defense_turret_preview.png"))
    scene = bpy.context.scene
    cam = scene.camera

    cam.location = (0, 0, 80)
    cam.rotation_euler = (0, 0, 0)
    cam.data.ortho_scale = 27
    scene.render.resolution_x, scene.render.resolution_y = 1200, 1200
    common.render(os.path.join(common.PREVIEW_DIR, "defense_turret_top.png"))
    # pivot proof: yaw 45 deg, pitch up 20 deg
    yaw, pitch = objs[1], objs[2]
    yaw.rotation_euler = (0, 0, math.radians(45))
    pitch.rotation_euler = (math.radians(20), 0, 0)
    key = bpy.data.objects["key"]   # relight from the camera side for this view
    key.rotation_euler = (-V((0.6, -0.3, 0.7)).normalized()).to_track_quat("-Z", "Y").to_euler()
    cam.location = (40.0, -4.0, 24.0)
    cam.rotation_euler = (V((0.0, 1.5, 13.0)) - V(cam.location)).to_track_quat("-Z", "Y").to_euler()
    cam.data.ortho_scale = 31
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1200
    common.render(os.path.join(common.PREVIEW_DIR, "defense_turret_posed.png"))
    yaw.rotation_euler = (0, 0, 0)
    pitch.rotation_euler = (0, 0, 0)


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build()
    if "--no-textures" not in argv:
        texture(objs[:3])        # bake while every mesh still sits at the world origin
    rig(root, objs)
    bpy.context.view_layer.update()
    total = 0
    for o in objs:
        tris = sum(len(pl.vertices) - 2 for pl in o.data.polygons)
        total += tris
        bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
        lo = [min(v[i] for v in bb) for i in range(3)]
        hi = [max(v[i] for v in bb) for i in range(3)]
        print(f"STAT {o.name} tris={tris} mats={[m.name for m in o.data.materials]} "
              f"origin={[round(c, 2) for c in o.matrix_world.translation]} "
              f"bbox={[round(c, 2) for c in lo]}..{[round(c, 2) for c in hi]}")
    print(f"STAT total tris={total}")
    parts.save_blend(BLEND)
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_mainfile(filepath=BLEND)
    common.export_glb(root, OUT, export_image_format="JPEG", export_image_quality=90)
    if "--no-preview" not in argv:
        previews(objs)


main()
