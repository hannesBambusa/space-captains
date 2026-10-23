"""Generate the escape pod .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python /Users/hannesalm/code/games/space-majesty/blender/gen_escape_pod.py
  Add `-- --no-preview` to skip the PNG renders.

Design: Soyuz/Orion-style re-entry capsule lying on its side. A truncated-cone crew
capsule (white, orange band) with the docking hatch tunnel at the narrow front end and a
small brown ablative heat shield at the wide rear end, an RCS quad ring around the cone,
two small windows, grab rails, an orange emergency beacon on a short mast, and a stub
service module behind the shield with one small thruster bell. About 2.8 m wide, 3.8 m
long. Top-down it reads as a blunt cone with a short stub.

Layout (Blender Z up, exported +Y up). Centre at origin on the play plane z=0.
Nose along Blender +Y, which the exporter turns into Godot -Z (forward).
Hierarchy: escape_pod (empty root) -> pod_hull, pod_details, beacon, engine_glow.
engine_glow: origin on the thruster exit plane (Blender y = NOZZLE_Y), plume along
Blender -Y (Godot local +Z), so scaling it on Z lengthens the glow backwards.
beacon: small emissive dome, origin at its own centre.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
from parts import ALONG_Y, V  # noqa: E402

OUT = os.path.join(common.ROOT, "assets", "models", "ships", "escape_pod.glb")
NOZZLE_Y = -1.95
NOZZLE_R = 0.36
BEACON_POS = V((0, 0.55, 1.42))
# (r, y) from the hatch face on the axis to the heat shield centre on the axis
PROFILE = [(0.0, 1.8), (0.42, 1.8), (0.45, 1.55), (0.62, 1.47), (0.85, 1.05), (1.07, 0.62),
           (1.3, 0.2), (1.38, 0.07), (1.36, -0.07), (1.1, -0.2), (0.6, -0.27), (0.0, -0.3)]
SHIELD_FROM = 8

MATS = {}


def build_materials():
    m = common.make_material
    MATS["white"] = m("pod_hull_white", (0.82, 0.82, 0.78), roughness=0.45, metallic=0.1)
    MATS["orange"] = m("pod_paint_orange", (0.85, 0.28, 0.03), roughness=0.5, metallic=0.1)
    MATS["grey"] = m("pod_trim_grey", (0.25, 0.26, 0.27), roughness=0.5, metallic=0.6)
    MATS["dark"] = m("pod_frame_dark", (0.05, 0.05, 0.055), roughness=0.5, metallic=0.6)
    MATS["shield"] = m("pod_heat_shield", (0.22, 0.15, 0.1), roughness=0.85, metallic=0.0)
    MATS["window"] = m("pod_window", (0.4, 0.7, 0.9), roughness=0.15,
                       emission=(0.35, 0.65, 1.0), emission_strength=2.0)
    MATS["beacon"] = m("pod_beacon", (1.0, 0.45, 0.05), roughness=0.2,
                       emission=(1.0, 0.4, 0.03), emission_strength=8.0)
    MATS["glow"] = m("pod_engine_glow", (0.5, 0.8, 1.0), roughness=0.2,
                     emission=(0.45, 0.8, 1.0), emission_strength=6.0)


def cone_point(y):
    """Point on the capsule cone surface radius at height y (between profile points 3..6)."""
    for (r0, y0), (r1, y1) in zip(PROFILE[3:7], PROFILE[4:7]):
        if y1 <= y <= y0:
            t = (y0 - y) / (y0 - y1)
            return r0 + (r1 - r0) * t
    return PROFILE[6][0]


def build_hull():
    p = parts.Part("pod_hull", MATS)

    def mat_fn(i, j):
        if j >= SHIELD_FROM:
            return "shield"
        if j in (0, 1, 2):
            return "grey"
        return "orange" if j == 4 else "white"
    p.lathe(PROFILE, 24, mat_fn, matrix=ALONG_Y)
    return p


def build_details():
    p = parts.Part("pod_details", MATS)
    # Docking hatch on the nose: dark ring, grey door, handle
    p.cyl(V((0, 1.82, 0)), 0.36, 0.36, 0.06, "dark", segs=16, axis_rot=ALONG_Y)
    p.box(V((0, 1.86, -0.15)), (0.36, 0.05, 0.07), "orange", bevel=0.0)
    for k in range(4):  # docking latches
        a = math.pi / 4 + k * math.pi / 2
        p.box(V((0.5 * math.cos(a), 1.55, 0.5 * math.sin(a))), (0.12, 0.2, 0.12), "dark",
              bevel=0.0)
    # Two small windows on the upper cone, looking forward
    for sx in (-1, 1):
        a = math.radians(90 - 35 * sx)
        y = 1.0
        r = cone_point(y)
        d = V((math.cos(a), 0.35, math.sin(a))).normalized()
        q = V((r * math.cos(a), y, r * math.sin(a)))
        p.tube(q - d * 0.03, q + d * 0.05, 0.16, 0.16, "grey", segs=10)
        p.tube(q + d * 0.04, q + d * 0.07, 0.11, 0.11, "window", segs=10)
    # RCS quad ring around the cone
    y = 0.35
    r = cone_point(y)
    for k in range(6):
        a = math.pi / 6 + k * math.pi / 3
        n = V((math.cos(a), 0.0, math.sin(a)))
        parts.rcs_quad(p, n * (r + 0.05) + V((0, y, 0)), n, "orange", "dark", s=0.22)
    # Grab rails along the top of the cone
    for sx in (-0.3, 0.3):
        a = V((sx, 1.35, cone_point(1.35) + 0.12))
        b = V((sx, 0.3, cone_point(0.3) + 0.12))
        p.beam(a, b, 0.05, 0.05, "dark")
        for q in (a, b):
            p.beam(q, q - V((0, 0, 0.16)), 0.05, 0.05, "dark")
    # Beacon mast and guard on top of the cone
    base_z = cone_point(BEACON_POS.y)
    p.cyl(V((0, BEACON_POS.y, base_z + 0.05)), 0.2, 0.24, 0.15, "grey", segs=10)
    p.cyl(V((0, BEACON_POS.y, (base_z + BEACON_POS.z) / 2)), 0.05, 0.05,
          BEACON_POS.z - base_z, "dark", segs=6)
    # Service stub behind the heat shield: short cylinder, orange band, small bell
    p.cyl(V((0, -0.65, 0)), 0.8, 0.72, 0.7, "grey", segs=16, axis_rot=ALONG_Y)
    p.cyl(V((0, -0.55, 0)), 0.82, 0.82, 0.14, "orange", segs=16, axis_rot=ALONG_Y)
    for sx in (-1, 1):  # flush radiator strips and a whip antenna
        parts.radiator(p, V((sx * 0.74, -0.7, 0)), 0.5, 0.5, (sx, 0, 0), "dark", "grey", ribs=3,
                       t=0.04)
    p.cyl(V((0.4, -0.75, 0.95)), 0.02, 0.015, 0.7, "dark", segs=4)
    p.cyl(V((0, -1.05, 0)), 0.42, 0.3, 0.15, "dark", segs=12, axis_rot=ALONG_Y)
    parts.bell(p, NOZZLE_Y, NOZZLE_R, 0.82, "grey", "dark", segs=14)
    return p


def build_beacon():
    p = parts.Part("beacon", MATS)
    r = 0.18
    prof = [(r * math.sin(math.pi / 2 * k / 4), r * math.cos(math.pi / 2 * k / 4))
            for k in range(5)] + [(r, -0.1), (0.0, -0.1)]
    p.lathe(prof, 12, lambda i, j: "beacon")
    return p


def build_glow():
    p = parts.Part("engine_glow", MATS)
    parts.exhaust_glow(p, NOZZLE_R * 0.85, 0.45, "glow", segs=14)
    return p


def build_pod():
    build_materials()
    root = parts.make_root("escape_pod", size=2)
    objs = [build_hull().finish(root, sharp_deg=50), build_details().finish(root),
            build_beacon().finish(root, sharp_deg=60), build_glow().finish(root)]
    objs[2].location = tuple(BEACON_POS)
    objs[3].location = (0, NOZZLE_Y, 0)
    return root, objs


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_pod()
    parts.print_stats(objs)
    parts.save_blend(os.path.join(common.ROOT, "blender", "escape_pod.blend"))
    common.export_glb(root, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews("escape_pod", 5.0, target=(0, -0.1, 0.2))


if __name__ == "__main__":
    main()
