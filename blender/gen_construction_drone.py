"""Generate the construction drone .glb (decorative, flies around structures being built).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_construction_drone.py -- [--scale-png /abs/out.png]

Design: ~1.6 m quad-drone. Off-white worn body with grey frame, four ducted thrusters on
diagonal pylons, a sensor eye at the front (+Y -> Godot -Z), one tool arm hanging under the
nose with a welding tip. Hazard-yellow accents, small nav lights. Flat Principled materials.

Layout (Blender Z up). Origin at body centre.
Hierarchy: construction_drone (root) -> drone_body, drone_arm (-> weld_tip), drone_light,
drone_thrusters. drone_arm origin is the shoulder joint (swing it on its local X axis);
weld_tip is an Empty at the arm tip, parented to the arm so it follows swings.
drone_light origin is its own centre (scale/pulse in place).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import parts  # noqa: E402
from parts import ALONG_Y, V, rot  # noqa: E402

OUT = os.path.join(common.ROOT, "assets", "models", "ships", "construction_drone.glb")
SHOULDER = V((0, 0.28, -0.17))
DUCT_X, DUCT_Y, DUCT_Z = 0.58, 0.5, 0.06
DUCT_R = 0.21
LIGHT_POS = V((0, -0.1, 0.27))
MATS = {}


def build_materials():
    m = common.make_material
    MATS["hull"] = m("drone_hull_offwhite", (0.70, 0.69, 0.65), roughness=0.55, metallic=0.1)
    MATS["hull2"] = m("drone_hull_grey", (0.38, 0.40, 0.43), roughness=0.5, metallic=0.25)
    MATS["dark"] = m("drone_structure_dark", (0.06, 0.065, 0.07), roughness=0.55, metallic=0.5)
    MATS["yellow"] = m("drone_accent_yellow", (0.95, 0.62, 0.02), roughness=0.45)
    MATS["eye"] = m("drone_sensor_eye", (0.9, 0.2, 0.1), roughness=0.2,
                    emission=(1.0, 0.25, 0.1), emission_strength=3.0)
    MATS["nav_r"] = m("drone_nav_red", (1.0, 0.1, 0.05), roughness=0.3,
                      emission=(1.0, 0.08, 0.04), emission_strength=4.0)
    MATS["nav_g"] = m("drone_nav_green", (0.1, 1.0, 0.3), roughness=0.3,
                      emission=(0.1, 1.0, 0.25), emission_strength=4.0)
    MATS["status"] = m("drone_status_light", (1.0, 0.6, 0.1), roughness=0.3,
                       emission=(1.0, 0.55, 0.08), emission_strength=5.0)
    MATS["glow"] = m("drone_thruster_glow", (0.75, 0.92, 1.0), roughness=0.2,
                     emission=(0.6, 0.88, 1.0), emission_strength=3.0)
    MATS["weld"] = m("drone_weld_tip", (1.0, 0.9, 0.7), roughness=0.3,
                     emission=(1.0, 0.85, 0.6), emission_strength=4.0)


def duct_centres():
    return [(sx * DUCT_X, sy * DUCT_Y, DUCT_Z) for sx in (-1, 1) for sy in (-1, 1)]


def build_body():
    p = parts.Part("drone_body", MATS)
    p.box(V((0, 0, 0)), (0.62, 0.9, 0.3), "hull", bevel=0.18)
    p.box(V((0, -0.05, 0.16)), (0.5, 0.55, 0.06), "hull2", bevel=0.1)       # top plate
    p.box(V((0, -0.46, 0.0)), (0.5, 0.12, 0.22), "hull2", bevel=0.1)         # rear pack
    p.box(V((0, -0.0, -0.17)), (0.3, 0.5, 0.06), "dark", bevel=0.0)          # belly plate
    p.hazard(-0.28, 0.28, 0.1, 0.0, 0.0, matrix=parts.Matrix.Translation((0, 0.4, 0.0))
             @ rot(rx=math.pi / 2), pitch=0.14) if False else None
    p.box(V((0, 0.43, 0.09)), (0.5, 0.06, 0.08), "yellow", bevel=0.0)        # nose stripe
    p.box(V((0.0, -0.1, 0.0)), (0.64, 0.12, 0.1), "yellow", bevel=0.0)       # waist band
    # sensor eye
    p.cyl(V((0, 0.5, 0.0)), 0.15, 0.15, 0.1, "dark", segs=10, axis_rot=ALONG_Y)
    p.sphere(V((0, 0.56, 0.0)), 0.1, "eye", segs=8, rings=5)
    # pylons to ducts + ducts
    for (x, y, z) in duct_centres():
        sx = 1 if x > 0 else -1
        p.beam(V((sx * 0.25, y * 0.55, 0.0)), V((x - sx * DUCT_R * 0.8, y, z)), 0.1, 0.08, "hull2")
        prof = [(DUCT_R + 0.035, 0.09), (DUCT_R + 0.035, -0.09), (DUCT_R - 0.02, -0.09),
                (DUCT_R - 0.02, 0.09), (DUCT_R + 0.035, 0.09)]
        p.lathe(prof, 12, lambda i, j: "yellow" if j == 4 and False else "hull",
                matrix=parts.Matrix.Translation((x, y, z)))
        p.cyl(V((x, y, z + 0.0)), 0.04, 0.04, 0.12, "dark", segs=6)          # motor hub
        p.beam(V((x - DUCT_R, y, z)), V((x + DUCT_R, y, z)), 0.03, 0.03, "dark")
    # nav lights on front ducts
    p.box(V((-DUCT_X - 0.2, DUCT_Y, DUCT_Z + 0.02)), (0.05, 0.05, 0.05), "nav_r", bevel=0.0)
    p.box(V((DUCT_X + 0.2, DUCT_Y, DUCT_Z + 0.02)), (0.05, 0.05, 0.05), "nav_g", bevel=0.0)
    # shoulder mount
    p.cyl(SHOULDER + V((0, 0, 0.06)), 0.1, 0.1, 0.1, "dark", segs=8)
    return p


def build_arm():
    """Built in local space relative to the shoulder (object origin = shoulder joint)."""
    p = parts.Part("drone_arm", MATS)
    p.sphere(V((0, 0, 0)), 0.075, "dark", segs=8, rings=5)
    elbow = V((0, 0.06, -0.3))
    tip = V((0, 0.34, -0.5))
    p.beam(V((0, 0, 0)), elbow, 0.08, 0.08, "hull2")
    p.sphere(elbow, 0.065, "dark", segs=8, rings=5)
    p.beam(elbow, tip - V((0, 0.07, -0.05)), 0.07, 0.07, "hull")
    p.box(elbow * 0.5 + V((0, 0.0, 0.0)), (0.1, 0.1, 0.06), "yellow", bevel=0.0,
          r=rot(rx=math.atan2(-0.3, 0.06) + math.pi / 2 * 0))
    p.tube(tip - V((0, 0.07, -0.05)), tip, 0.045, 0.02, "dark", segs=6)       # torch nozzle
    p.sphere(tip, 0.022, "weld", segs=6, rings=4)
    return p, tip


def build_light():
    p = parts.Part("drone_light", MATS)
    p.sphere(V((0, 0, 0)), 0.06, "status", segs=8, rings=5, scale=(1, 1, 0.8))
    return p


def build_thrusters():
    p = parts.Part("drone_thrusters", MATS)
    for (x, y, z) in duct_centres():
        p.cyl(V((x, y, z - 0.06)), DUCT_R - 0.04, DUCT_R - 0.06, 0.03, "glow", segs=12)
    return p


def build():
    build_materials()
    root = parts.make_root("construction_drone", size=1.0)
    body = build_body().finish(root)
    arm_p, tip = build_arm()
    arm = arm_p.finish(root)
    arm.location = SHOULDER
    light = build_light().finish(root)
    light.location = LIGHT_POS
    thr = build_thrusters().finish(root)
    e = parts.add_empty("weld_tip", arm, tip, size=0.15)
    return root, [body, arm, light, thr], e


def scale_preview(path, root):
    import bpy
    shuttle = os.path.join(common.ROOT, "assets", "models", "ships", "cargo_shuttle.glb")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=shuttle)
    for o in set(bpy.data.objects) - before:
        if o.parent is None:
            o.location.x += 5.0
    root.location = (-0.5, -2.0, 0.0)
    common.setup_preview(cam_loc=(-2, -14, 9), cam_target=(2.5, -0.5, 0), res=(1600, 1000),
                         key_dir=(-0.5, 0.4, 0.75), key_energy=3.5)
    common.render(path)
    # close-up of the drone from low front-side to check the arm
    cam = bpy.context.scene.camera
    cam.location = (root.location.x - 1.6, root.location.y + 2.2, -0.9)
    d = V(root.location) + V((0, 0, -0.2)) - V(cam.location)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    common.render(path.replace(".png", "_close.png"))


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs, tip = build()
    parts.print_stats(objs)
    parts.save_blend(os.path.join(common.ROOT, "blender", "construction_drone.blend"))
    common.export_glb(root, OUT)
    if "--scale-png" in argv:
        scale_preview(argv[argv.index("--scale-png") + 1], root)


main()
