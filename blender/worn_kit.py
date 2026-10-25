"""Shared kit for the worn-industrial free-standing structures (raider dock, salvage yard,
claim garrison). Same material language and bake as gen_station_addons.py:
station_textures.WORN_KINDS surfaces baked into one 2048 atlas per model, flat emissive
materials for lamps and windows (no atlas, near-black base so only the emission shows).

Extra worn kinds added here: "rust" (bare corroded steel), "scrap" (mixed old paint on
junk), "ore" (broken reprocessed ore), "paint" (light neutral paint that becomes the
separate "faction_paint" material Godot tints).
"""
import math
import os
import shutil

import bpy
from mathutils import Matrix, Vector

import common
import parts
import station_textures as st

V = Vector
SCRATCH = "/private/tmp/claude-501/-Users-hannesalm-code-games/559853a4-05f8-403b-881d-863d1678ad65/scratchpad"

EXTRA_WORN = {
    "rust": dict(big=(2.0, 1.5), plate=(1.0, 0.75),
                 tones=[(0.16, 0.07, 0.03), (0.12, 0.055, 0.025), (0.19, 0.09, 0.04),
                        (0.10, 0.06, 0.04), (0.17, 0.08, 0.035), (0.13, 0.07, 0.045)],
                 plate_var=0.12, rough=(0.82, 0.12), metal=0.25, seam_big=0.3,
                 seam_small=0.15, rivets=True, hatches=0.0, chip=(0.22, 0.2, 0.19),
                 chip_metal=0.8, chip_k=1.2, grime_k=1.2, streak_k=0.5, bleach=0.15),
    "scrap": dict(big=(1.2, 0.9), plate=(0.6, 0.45),
                  tones=[(0.26, 0.10, 0.04), (0.08, 0.16, 0.15), (0.30, 0.29, 0.26),
                         (0.10, 0.10, 0.11), (0.25, 0.18, 0.05), (0.16, 0.07, 0.035)],
                  plate_var=0.25, rough=(0.7, 0.2), metal=0.3, seam_big=0.4,
                  seam_small=0.2, rivets=False, hatches=0.0, chip=(0.28, 0.27, 0.27),
                  chip_metal=0.9, chip_k=1.8, grime_k=1.3, streak_k=0.5, bleach=0.2),
    "ore": dict(big=(0.7, 0.6), plate=(0.35, 0.3),
                tones=[(0.20, 0.11, 0.052), (0.27, 0.15, 0.07), (0.15, 0.115, 0.09),
                       (0.31, 0.175, 0.08), (0.22, 0.135, 0.075), (0.18, 0.17, 0.16)],
                plate_var=0.3, rough=(0.88, 0.08), metal=0.1, seam_big=0.5,
                seam_small=0.3, rivets=False, hatches=0.0, chip=(0.4, 0.33, 0.24),
                chip_metal=0.6, chip_k=0.6, grime_k=1.0, streak_k=0.0, bleach=0.1),
    "paint": dict(big=(4.0, 3.0), plate=(2.0, 1.5),
                  tones=[(0.80, 0.80, 0.80), (0.76, 0.76, 0.76), (0.83, 0.83, 0.83),
                         (0.73, 0.73, 0.73), (0.79, 0.79, 0.79), (0.75, 0.75, 0.75)],
                  plate_var=0.05, rough=(0.5, 0.1), metal=0.0, seam_big=0.3,
                  seam_small=0.08, rivets=True, hatches=0.0, chip=(0.25, 0.25, 0.25),
                  chip_metal=0.8, chip_k=1.1, grime_k=0.9, streak_k=0.4, bleach=0.1),
}
st.WORN_KINDS.update(EXTRA_WORN)

INK_DARK = (0.035, 0.035, 0.038)
INK_LIGHT = (0.42, 0.42, 0.39)
FLAT = ("window", "window_dim", "window_cool", "glass", "light", "red", "cyan", "amber",
        "green")


def build_materials(pre, mats, extra=()):
    """Station material language (WORN_KINDS keys) + flat emissives. `extra` adds the
    worn kinds from EXTRA_WORN that this model uses."""
    m = common.make_material
    mats.clear()
    mats["hull"] = m(f"{pre}_hull_white", (0.5, 0.5, 0.48), roughness=0.5)
    mats["hull2"] = m(f"{pre}_hull_grey", (0.2, 0.21, 0.22), roughness=0.55)
    mats["hull3"] = m(f"{pre}_hull_warm", (0.33, 0.32, 0.29), roughness=0.58)
    mats["dark"] = m(f"{pre}_structure_dark", (0.055, 0.058, 0.062), roughness=0.5,
                     metallic=0.55)
    mats["metal"] = m(f"{pre}_bare_metal", (0.3, 0.3, 0.31), roughness=0.36, metallic=0.9)
    mats["accent"] = m(f"{pre}_accent_paint", (0.28, 0.12, 0.045), roughness=0.6)
    mats["hazard"] = m(f"{pre}_hazard", (0.21, 0.165, 0.065), roughness=0.62)
    mats["pad"] = m(f"{pre}_deck", (0.095, 0.095, 0.1), roughness=0.72, metallic=0.2)
    mats["radiator"] = m(f"{pre}_radiator", (0.47, 0.475, 0.48), roughness=0.45, metallic=0.15)
    mats["mli"] = m(f"{pre}_mli_white", (0.5, 0.49, 0.455), roughness=0.86)
    cols = dict(rust=(0.15, 0.07, 0.03), scrap=(0.2, 0.15, 0.1), ore=(0.24, 0.14, 0.07),
                paint=(0.78, 0.78, 0.78))
    for k in extra:
        mats[k] = m(f"{pre}_{k}", cols[k], roughness=0.7)
    glow = (0.03, 0.028, 0.025)
    mats["window"] = m(f"{pre}_window_warm", glow, roughness=0.25,
                       emission=(1.0, 0.6, 0.28), emission_strength=2.0)
    mats["window_dim"] = m(f"{pre}_window_amber", glow, roughness=0.25,
                           emission=(1.0, 0.5, 0.18), emission_strength=1.1)
    mats["window_cool"] = m(f"{pre}_window_cool", glow, roughness=0.25,
                            emission=(0.7, 0.82, 1.0), emission_strength=1.5)
    mats["glass"] = m(f"{pre}_glass_dark", (0.012, 0.016, 0.02), roughness=0.1)
    mats["light"] = m(f"{pre}_light_amber", glow, roughness=0.3,
                      emission=(1.0, 0.55, 0.2), emission_strength=3.5)
    mats["red"] = m(f"{pre}_light_red", glow, roughness=0.3,
                    emission=(1.0, 0.08, 0.03), emission_strength=6.0)
    mats["cyan"] = m(f"{pre}_light_white", glow, roughness=0.3,
                     emission=(0.85, 0.92, 1.0), emission_strength=4.0)
    mats["green"] = m(f"{pre}_light_green", glow, roughness=0.3,
                      emission=(0.15, 1.0, 0.3), emission_strength=4.0)
    mats["amber"] = m(f"{pre}_unload_amber", (1.0, 0.62, 0.12), roughness=0.3,
                      emission=(1.0, 0.55, 0.06), emission_strength=8.0)
    for k in FLAT:
        mats[k].use_backface_culling = False
    return mats


# ---------------------------------------------------------------- small shapes
def lamp(L, pos, s=0.4, mat="light"):
    s = min(s, 0.5)
    L.box(V(pos), (s, s, s * 0.6), mat, bevel=0.0)


def beacon(H, L, pos, r=0.5, mat="light"):
    p = V(pos)
    H.cyl(p - V((0, 0, 0.5)), 0.22, 0.22, 1.0, "dark", segs=6)
    L.cyl(p + V((0, 0, 0.25)), r, r * 0.8, r * 0.9, mat, segs=8)


def polar(r, a, z=0.0):
    return V((r * math.cos(a), r * math.sin(a), z))


def win_row(L, rng, c0, c1, normal, n, w=0.5, h=0.6, mode="hab"):
    c0, c1 = V(c0), V(c1)
    for k in range(n):
        c = c0.lerp(c1, (k + 0.5) / n)
        up = V((0, 0, 1)) if abs(V(normal).z) < 0.9 else V((0, -1, 0))
        parts.window(L, c, normal, up, w, h, parts.pick_lit(rng, mode))


def tank_v(H, c, r, h, mat_body, band="accent", segs=14):
    """Vertical tank with domes, base at c.z."""
    x, y, z0 = c
    dome = r * 0.6
    prof = [(0.0, z0)]
    for k in range(1, 4):
        a = math.pi / 2 * k / 3
        prof.append((r * math.sin(a), z0 + dome * (1 - math.cos(a))))
    zb0, zb1 = z0 + dome + (h - 2 * dome) * 0.62, z0 + dome + (h - 2 * dome) * 0.72
    prof += [(r, zb0), (r, zb1)]
    for k in range(0, 4):
        a = math.pi / 2 * k / 3
        prof.append((r * math.cos(a), z0 + h - dome + dome * math.sin(a)))
    prof[-1] = (0.0, z0 + h)
    H.lathe(prof, segs, lambda i, j: band if j == 4 else mat_body,
            matrix=Matrix.Translation((x, y, 0)))


def lattice_mast(H, base, top_z, w0, w1, bays, mat="dark", chord=0.35, brace=0.18):
    """Square tapering lattice tower from base (x, y, z) to top_z."""
    b = V(base)
    h = top_z - b.z
    for dx in (-1, 1):
        for dy in (-1, 1):
            parts.strut(H, b + V((dx * w0, dy * w0, 0)), b + V((dx * w1, dy * w1, h)), chord,
                        chord, mat)
    for k in range(bays):
        t0, t1 = k / bays, (k + 1) / bays
        wa, wb = w0 + (w1 - w0) * t0, w0 + (w1 - w0) * t1
        za, zb = b.z + h * t0, b.z + h * t1
        for s in range(4):
            a = s * math.pi / 2
            n = V((math.cos(a), math.sin(a), 0))
            t = V((-math.sin(a), math.cos(a), 0))
            parts.strut(H, b.xy.to_3d() + n * wa - t * wa + V((0, 0, za)),
                        b.xy.to_3d() + n * wb + t * wb + V((0, 0, zb)), brace, brace, mat)
            parts.strut(H, b.xy.to_3d() + n * wb - t * wb + V((0, 0, zb)),
                        b.xy.to_3d() + n * wb + t * wb + V((0, 0, zb)), brace, brace, mat)


def landing_pad(H, L, c, r, rng=None, n_lamps=8, lamp_mat="light"):
    """Octagonal landing pad with a hazard rim and rim lamps, top at c.z."""
    c = V(c)
    prof = [(0.0, -1.2), (r - 0.8, -1.2), (r, -0.6), (r, 0.0), (r - 0.9, 0.0), (0.0, 0.0)]
    pm = {0: "dark", 1: "dark", 2: "hull2", 3: "hazard", 4: "pad"}
    H.lathe(prof, 8, lambda i, j: pm[j], matrix=Matrix.Translation(c), start=math.pi / 8)
    for k in range(n_lamps):
        a = math.pi / 8 + k * 2 * math.pi / n_lamps
        lamp(L, c + polar(r - 0.45, a, 0.15), 0.35, lamp_mat)


def cargo_pod(H, c, size, rot_z=0.0, body="hull3", band="accent", frame="dark"):
    """ISO-style cargo pod: chamfered box body in a dark corner frame, a paint band."""
    c = V(c)
    w, l, h = size
    r = Matrix.Rotation(rot_z, 4, "Z")
    H.box(c, (w - 0.15, l - 0.3, h - 0.15), body, r=r, bevel=0.06)
    for sx in (-1, 1):   # end frames
        H.box(c + r.to_3x3() @ V((0, sx * (l / 2 - 0.15), 0)), (w, 0.3, h), frame, r=r,
              bevel=0.0)
    H.box(c + r.to_3x3() @ V((0, l * 0.18, 0)), (w + 0.02, l * 0.12, h + 0.02), band, r=r,
          bevel=0.0)


# ---------------------------------------------------------------- texture + export
def texture(objs, mats, pre, pad_centres, scorch=(), decals=(), labels=(), seed0=21,
            paint_key=None, res=2048):
    """Bake one worn atlas for `objs`. With paint_key, the faces using mats[paint_key] get
    their own material named "faction_paint" (same atlas images; the atlas there is light
    neutral paint and the base colour factor carries the default tint)."""
    p_alb, p_mr, p_nrm, atlas_mats = st.bake_worn_atlas(
        objs, mats, pre, res, pad_centres, scorch=scorch, decals=decals, labels=labels,
        seed0=seed0)
    alb, mr, nrm = (st.load_saved(p_alb, False), st.load_saved(p_mr, True),
                    st.load_saved(p_nrm, True))
    hull = st.pbr_material(f"{pre}_hull", alb, mr, nrm)
    mapping = {m: hull for m in atlas_mats}
    if paint_key:
        paint = faction_material(alb, mr, nrm)
        mapping[mats[paint_key]] = paint
    for o in objs:
        st.remap_materials(o, mapping)
        o.data.uv_layers.remove(o.data.uv_layers["panel"])
    for m in atlas_mats:
        if m.users == 0:
            bpy.data.materials.remove(m)


FACTION_DEFAULT = (0.5, 0.07, 0.045)   # hostile red until Godot tints it


def faction_material(alb, mr, nrm):
    """'faction_paint': atlas albedo multiplied by a colour factor. The glTF exporter
    writes the factor as baseColorFactor, so Godot can set albedo_color to tint it."""
    mat = st.pbr_material("faction_paint", alb, mr, nrm)
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = next(n for n in nt.nodes if n.type == "TEX_IMAGE" and n.image == alb)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    mix.inputs[7].default_value = (*FACTION_DEFAULT, 1.0)
    nt.links.new(tex.outputs["Color"], mix.inputs[6])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    return mat


def stats(objs):
    total = 0
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for o in objs:
        tris = sum(len(pl.vertices) - 2 for pl in o.data.polygons)
        total += tris
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
        print(f"STAT {o.name} tris={tris} mats={[m.name for m in o.data.materials]}")
    print(f"STAT total tris={total} bbox x {lo[0]:.1f}..{hi[0]:.1f} y {lo[1]:.1f}..{hi[1]:.1f}"
          f" z {lo[2]:.1f}..{hi[2]:.1f} -> {hi[0]-lo[0]:.1f} x {hi[1]-lo[1]:.1f} x "
          f"{hi[2]-lo[2]:.1f} m")
    return total


def save_and_export(root, blend, out):
    parts.save_blend(blend)
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_mainfile(filepath=blend)
    common.export_glb(root, out, export_image_format="JPEG", export_image_quality=90)


def previews(name, target, ortho, top_ortho, cam_off=(-45, -75, 80)):
    """3/4 preview + top-down into blender/previews, copied to the session scratchpad."""
    tx, ty, tz = target
    common.setup_preview(cam_loc=(tx + cam_off[0], ty + cam_off[1], tz + cam_off[2]),
                         cam_target=target, ortho_scale=ortho, res=(1600, 1200),
                         key_dir=(-0.6, -0.35, 0.7), key_energy=3.5)
    a = os.path.join(common.PREVIEW_DIR, f"{name}_preview.png")
    common.render(a)
    scene = bpy.context.scene
    cam = scene.camera
    cam.location = (tx, ty, 200)
    cam.rotation_euler = (0, 0, 0)
    cam.data.ortho_scale = top_ortho
    scene.render.resolution_x, scene.render.resolution_y = 1200, 1200
    b = os.path.join(common.PREVIEW_DIR, f"{name}_top.png")
    common.render(b)
    if os.path.isdir(SCRATCH):
        for p in (a, b):
            shutil.copy(p, SCRATCH)
