"""Baked surface textures for the home station (used by gen_station.py).

Procedural shading per surface kind (hull plates, seams, rivets, MLI quilting, hazard paint,
pad deck, wear) is built as Cycles node trees and baked to images, because glTF cannot carry
procedural nodes.

  atlas, 2048: core + ring + docks + solar structure in one UV layout
               albedo (JPEG), metal/rough (PNG, G = roughness, B = metallic), normal (PNG)
  solar tile, 1024: one 3 x 3 m photovoltaic plate, UV 0..1 per plate (same three maps)

Needs the "panel" UV layer that gen_station.Part writes (metres in each primitive's frame).
That layer drives the plate layout and is removed before export.
"""
import math
import os
import time

import bmesh
import bpy
from bpy_extras import bmesh_utils
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import common

TEX_DIR = os.path.join(common.ROOT, "blender", "textures")
ATLAS_RES = 2048
SOLAR_RES = 1024
SOLAR_PLATE = 3.0          # solar plate edge in metres (gen_station.build_solar)
EMISSIVE = ("window", "light")
BOTTOM_UV_SCALE = 0.45     # texel density for downward faces (the RTS camera looks down)
SOLAR_STRUCT_UV_SCALE = 0.5

# Surface kinds baked into the atlas. Colours are linear.
KINDS = {
    "hull": dict(panel=(2.0, 1.5), tones=[(0.70, 0.70, 0.68), (0.66, 0.665, 0.66),
                                          (0.62, 0.63, 0.64), (0.69, 0.68, 0.65)],
                 rough=(0.40, 0.14), metal=0.05, seam_dark=0.32, rivets=True,
                 chip=(0.42, 0.43, 0.45), chip_metal=0.85, chip_k=1.0, grime_k=1.0,
                 bleach=0.6),
    "hull2": dict(panel=(2.0, 1.0), tones=[(0.36, 0.38, 0.41), (0.31, 0.33, 0.36),
                                           (0.40, 0.41, 0.43), (0.28, 0.30, 0.32)],
                  rough=(0.42, 0.14), metal=0.3, seam_dark=0.5, rivets=True,
                  chip=(0.55, 0.56, 0.58), chip_metal=0.9, chip_k=0.8, grime_k=0.9,
                  bleach=0.4),
    "dark": dict(panel=(1.0, 1.0), tones=[(0.060, 0.064, 0.070), (0.050, 0.054, 0.058),
                                          (0.072, 0.074, 0.078), (0.045, 0.047, 0.050)],
                 rough=(0.50, 0.16), metal=0.6, seam_dark=0.4, rivets=False,
                 chip=(0.30, 0.30, 0.31), chip_metal=1.0, chip_k=0.7, grime_k=0.5,
                 bleach=0.2),
    "orange": dict(panel=(2.0, 2.0), tones=[(0.78, 0.25, 0.03), (0.72, 0.22, 0.025),
                                            (0.80, 0.29, 0.04), (0.74, 0.24, 0.03)],
                   rough=(0.45, 0.10), metal=0.0, seam_dark=0.4, rivets=False,
                   chip=(0.40, 0.40, 0.41), chip_metal=0.8, chip_k=1.4, grime_k=0.9,
                   bleach=0.3),
    "hazard": dict(panel=(2.0, 2.0), tones=[(0.80, 0.55, 0.02), (0.76, 0.52, 0.02),
                                            (0.82, 0.58, 0.03), (0.78, 0.53, 0.02)],
                   rough=(0.48, 0.10), metal=0.0, seam_dark=0.3, rivets=False,
                   chip=(0.38, 0.38, 0.39), chip_metal=0.8, chip_k=1.6, grime_k=1.0,
                   bleach=0.25, stripes=0.9),
    "pad": dict(panel=(1.5, 1.5), tones=[(0.13, 0.13, 0.14), (0.11, 0.115, 0.12),
                                         (0.15, 0.15, 0.155), (0.12, 0.12, 0.125)],
                rough=(0.72, 0.10), metal=0.2, seam_dark=0.45, rivets=True,
                chip=(0.35, 0.35, 0.36), chip_metal=0.9, chip_k=0.8, grime_k=1.0,
                bleach=0.2, pad=True),
    "mli": dict(panel=(2.0, 1.6), tones=[(0.76, 0.76, 0.73), (0.72, 0.72, 0.69),
                                         (0.78, 0.77, 0.73), (0.74, 0.74, 0.72)],
                rough=(0.85, 0.08), metal=0.0, seam_dark=0.15, rivets=False,
                chip=(0.7, 0.7, 0.7), chip_metal=0.0, chip_k=0.0, grime_k=1.1,
                bleach=0.3, quilt=0.6),
    "mli_gold": dict(panel=(2.0, 1.6), tones=[(0.80, 0.52, 0.16), (0.74, 0.47, 0.13),
                                              (0.82, 0.56, 0.19), (0.77, 0.50, 0.15)],
                     rough=(0.30, 0.10), metal=0.95, seam_dark=0.2, rivets=False,
                     chip=(0.7, 0.7, 0.7), chip_metal=1.0, chip_k=0.0, grime_k=0.6,
                     bleach=0.0, quilt=0.4, gold=True),
}
GRIME_TINT = (0.50, 0.47, 0.42)       # brownish outgassing film, multiplied in


# ------------------------------------------------------------------ node helpers
class NB:
    """Tiny node-graph builder. Values may be sockets or constants."""

    def __init__(self, mat):
        self.nt = mat.node_tree
        self.nt.nodes.clear()

    def n(self, kind, **props):
        node = self.nt.nodes.new(kind)
        for k, v in props.items():
            setattr(node, k, v)
        return node

    def put(self, sock, v):
        if v is None:
            return
        if isinstance(v, bpy.types.NodeSocket):
            self.nt.links.new(v, sock)
        else:
            if sock.type == "RGBA" and len(v) == 3:
                v = (*v, 1.0)
            sock.default_value = v

    def m(self, op, a, b=None, c=None, clamp=False):
        node = self.n("ShaderNodeMath", operation=op, use_clamp=clamp)
        for s, v in zip(node.inputs, (a, b, c)):
            self.put(s, v)
        return node.outputs[0]

    def v(self, op, a, b=None, scale=None):
        node = self.n("ShaderNodeVectorMath", operation=op)
        self.put(node.inputs[0], a)
        self.put(node.inputs[1], b)
        self.put(node.inputs[3], scale)
        return node.outputs[1] if op in ("DOT_PRODUCT", "LENGTH", "DISTANCE") else node.outputs[0]

    def mixf(self, fac, a, b):
        node = self.n("ShaderNodeMix", data_type="FLOAT")
        self.put(node.inputs[0], fac)
        self.put(node.inputs[2], a)
        self.put(node.inputs[3], b)
        return node.outputs[0]

    def mixv(self, fac, a, b):
        node = self.n("ShaderNodeMix", data_type="VECTOR")
        self.put(node.inputs[0], fac)
        self.put(node.inputs[4], a)
        self.put(node.inputs[5], b)
        return node.outputs[1]

    def ss(self, e0, e1, x):
        """smoothstep(e0, e1, x), clamped 0..1 (e0 < e1)."""
        node = self.n("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP", clamp=True)
        self.put(node.inputs[0], x)
        self.put(node.inputs[1], e0)
        self.put(node.inputs[2], e1)
        return node.outputs[0]

    def inv(self, x):
        return self.m("SUBTRACT", 1.0, x)

    def clamp01(self, x):
        return self.m("ADD", x, 0.0, clamp=True)

    def sep(self, vec):
        node = self.n("ShaderNodeSeparateXYZ")
        self.put(node.inputs[0], vec)
        return node.outputs[0], node.outputs[1], node.outputs[2]

    def comb(self, x, y, z):
        node = self.n("ShaderNodeCombineXYZ")
        for s, v in zip(node.inputs, (x, y, z)):
            self.put(s, v)
        return node.outputs[0]

    def noise(self, vec, scale, detail=2.0, rough=0.5):
        node = self.n("ShaderNodeTexNoise", noise_dimensions="3D")
        self.put(node.inputs["Vector"], vec)
        node.inputs["Scale"].default_value = scale
        node.inputs["Detail"].default_value = detail
        node.inputs["Roughness"].default_value = rough
        return node.outputs["Fac"]

    def white(self, vec):
        node = self.n("ShaderNodeTexWhiteNoise", noise_dimensions="3D")
        self.put(node.inputs["Vector"], vec)
        return node.outputs["Value"]

    def voronoi(self, vec, scale):
        node = self.n("ShaderNodeTexVoronoi", voronoi_dimensions="3D", feature="F1")
        self.put(node.inputs["Vector"], vec)
        node.inputs["Scale"].default_value = scale
        return node.outputs["Distance"]

    def ramp(self, fac, colours):
        node = self.n("ShaderNodeValToRGB")
        cr = node.color_ramp
        cr.interpolation = "CONSTANT"
        while len(cr.elements) < len(colours):
            cr.elements.new(0.5)
        for i, (el, c) in enumerate(zip(cr.elements, colours)):
            el.position = i / len(colours)
            el.color = (*c, 1.0)
        self.put(node.inputs[0], fac)
        return node.outputs[0]

    def lum(self, col):
        return self.v("DOT_PRODUCT", col, (0.2126, 0.7152, 0.0722))

    def uvmap(self, name):
        return self.n("ShaderNodeUVMap", uv_map=name).outputs[0]

    def image(self, img, vec=None):
        node = self.n("ShaderNodeTexImage", image=img)
        self.put(node.inputs[0], vec)
        return node


def new_image(name, res, data):
    old = bpy.data.images.get(name)
    if old:
        bpy.data.images.remove(old)
    img = bpy.data.images.new(name, res, res, alpha=False, float_buffer=False, is_data=data)
    if data:
        img.colorspace_settings.name = "Non-Color"
    return img


# ------------------------------------------------------------------ shading per kind
def panel_fields(nb, cfg, seed):
    """Plate grid in panel space: seam (1 in the groove), rivet (1 on a rivet head),
    rnd (0..1 per plate), P (panel-space vector)."""
    P = nb.v("ADD", nb.uvmap("panel"), (seed * 17.0, seed * 31.0, seed * 7.0))
    sx, sy = cfg["panel"]
    q = nb.v("DIVIDE", P, (sx, sy, 1.0))
    fx, fy, _ = nb.sep(nb.v("FRACTION", q))
    dx = nb.m("MULTIPLY", nb.m("MINIMUM", fx, nb.inv(fx)), sx)
    dy = nb.m("MULTIPLY", nb.m("MINIMUM", fy, nb.inv(fy)), sy)
    d = nb.m("MINIMUM", dx, dy)
    seam = nb.inv(nb.ss(0.014, 0.036, d))
    rnd = nb.white(nb.v("FLOOR", q))
    rivet = 0.0
    if cfg.get("rivets"):
        ri, rp, rr = 0.11, 0.22, 0.03
        px, py, _ = nb.sep(P)
        ax = nb.m("ABSOLUTE", nb.m("SUBTRACT", dx, ri))
        ay = nb.m("MULTIPLY", nb.m("ABSOLUTE", nb.m("SUBTRACT", nb.m("FRACT", nb.m("DIVIDE", py, rp)), 0.5)), rp)
        bx = nb.m("MULTIPLY", nb.m("ABSOLUTE", nb.m("SUBTRACT", nb.m("FRACT", nb.m("DIVIDE", px, rp)), 0.5)), rp)
        by = nb.m("ABSOLUTE", nb.m("SUBTRACT", dy, ri))
        r1 = nb.v("LENGTH", nb.comb(ax, ay, 0.0))
        r2 = nb.v("LENGTH", nb.comb(bx, by, 0.0))
        rivet = nb.inv(nb.ss(rr * 0.35, rr, nb.m("MINIMUM", r1, r2)))
    return P, seam, rivet, rnd, dx, dy


def build_surface(nb, kind, cfg, masks_img, seed, pad_centres):
    """Returns dict of output sockets: albedo (vector), rough, metal, height (metres)."""
    geo = nb.n("ShaderNodeNewGeometry")
    pos, nrm = geo.outputs["Position"], geo.outputs["Normal"]
    P, seam, rivet, rnd, dx, dy = panel_fields(nb, cfg, seed)

    mk = nb.image(masks_img, nb.uvmap("UVMap"))
    ao_n, ao_f, edge = nb.sep(mk.outputs["Color"])
    grime = nb.m("MULTIPLY", nb.inv(ao_n), cfg["grime_k"], clamp=True)

    # wear fields (3D position based, continuous across UV islands)
    patch = nb.ss(0.42, 0.68, nb.noise(pos, 0.07, 3.0))
    sx_, sy_, _ = nb.sep(P)
    streak_vec = nb.comb(nb.m("MULTIPLY", sx_, 4.0), nb.m("MULTIPLY", sy_, 0.22), float(seed))
    streak = nb.ss(0.52, 0.78, nb.noise(streak_vec, 1.0, 4.0, 0.55))
    streak = nb.m("MULTIPLY", streak,
                  nb.m("ADD", nb.m("MULTIPLY", nb.inv(ao_f), 2.4), nb.m("MULTIPLY", patch, 0.45)),
                  clamp=True)
    pit = nb.inv(nb.ss(0.05, 0.11, nb.voronoi(pos, 7.0)))
    pit = nb.m("MULTIPLY", pit, nb.ss(0.48, 0.66, nb.noise(pos, 0.35, 2.0)))
    chip = nb.m("MULTIPLY", edge, nb.ss(0.47, 0.58, nb.noise(pos, 2.2, 6.0, 0.6)))
    chip = nb.m("MULTIPLY", chip, cfg["chip_k"], clamp=True)
    top = nb.ss(0.3, 0.95, nb.sep(nrm)[2])
    zpos = nb.sep(pos)[2]
    soot = nb.m("MULTIPLY", nb.ss(12.0, 17.5, nb.m("MULTIPLY", zpos, -1.0)),
                nb.m("ADD", 0.55, nb.m("MULTIPLY", nb.noise(pos, 0.5, 3.0), 0.6)), clamp=True)

    height = nb.m("ADD", nb.m("MULTIPLY", seam, -0.012), nb.m("MULTIPLY", rivet, 0.006))
    height = nb.m("SUBTRACT", height, nb.m("MULTIPLY", pit, 0.003))

    base = nb.ramp(rnd, cfg["tones"])
    rough = nb.m("ADD", cfg["rough"][0], nb.m("MULTIPLY", nb.m("SUBTRACT", rnd, 0.5), cfg["rough"][1]))
    metal = cfg["metal"]

    if cfg.get("stripes"):
        px, py, _ = nb.sep(P)
        sfr = nb.m("FRACT", nb.m("DIVIDE", nb.m("ADD", px, py), cfg["stripes"]))
        black = nb.m("MULTIPLY", nb.ss(0.47, 0.53, sfr), nb.inv(nb.ss(0.97, 0.995, sfr)))
        base = nb.mixv(black, base, (0.018, 0.018, 0.02))

    if cfg.get("quilt"):
        qs = cfg["quilt"]
        qx, qy, _ = nb.sep(nb.v("FRACTION", nb.v("DIVIDE", P, (qs, qs, 1.0))))

        def pillow(t):  # 1 - (2t - 1)^4
            w = nb.m("SUBTRACT", nb.m("MULTIPLY", t, 2.0), 1.0)
            return nb.inv(nb.m("POWER", nb.m("ABSOLUTE", w), 4.0))
        pil = nb.m("MULTIPLY", pillow(qx), pillow(qy))
        crinkle = nb.noise(pos, 2.6 if cfg.get("gold") else 1.6, 8.0, 0.62)
        height = nb.m("ADD", height, nb.m("MULTIPLY", pil, 0.014))
        height = nb.m("ADD", height, nb.m("MULTIPLY", nb.m("SUBTRACT", crinkle, 0.5),
                                          0.012 if cfg.get("gold") else 0.005))
        wrinkle = nb.noise(pos, 0.9, 4.0, 0.55)
        shade = nb.m("ADD", 0.86, nb.m("ADD", nb.m("MULTIPLY", pil, 0.06),
                                       nb.m("MULTIPLY", wrinkle, 0.14)))
        base = nb.v("SCALE", base, scale=shade)
        height = nb.m("ADD", height, nb.m("MULTIPLY", wrinkle, 0.02))
        tape = nb.inv(nb.ss(0.05, 0.08, nb.m("MINIMUM", dx, dy)))
        base = nb.mixv(nb.m("MULTIPLY", tape, 0.5), base, nb.v("SCALE", base, scale=0.88))
        if cfg.get("gold"):
            base = nb.v("SCALE", base, scale=nb.m("ADD", 0.8, nb.m("MULTIPLY", crinkle, 0.4)))
            rough = nb.m("ADD", rough, nb.m("MULTIPLY", nb.m("SUBTRACT", crinkle, 0.5), 0.5))
        else:
            rough = nb.m("SUBTRACT", rough, nb.m("MULTIPLY", tape, 0.25))

    scorch = 0.0
    if cfg.get("pad"):
        px, py, _ = nb.sep(pos)
        dists = [nb.v("LENGTH", nb.comb(nb.m("SUBTRACT", px, c[0]), nb.m("SUBTRACT", py, c[1]), 0.0))
                 for c in pad_centres]
        dd = nb.m("MINIMUM", *dists[:2]) if len(dists) > 1 else dists[0]
        ring1 = nb.inv(nb.ss(0.10, 0.16, nb.m("ABSOLUTE", nb.m("SUBTRACT", dd, 3.9))))
        ring2 = nb.inv(nb.ss(0.05, 0.09, nb.m("ABSOLUTE", nb.m("SUBTRACT", dd, 2.3))))
        paint = nb.m("MAXIMUM", ring1, ring2)
        paint = nb.m("MULTIPLY", paint, nb.ss(0.30, 0.48, nb.noise(pos, 2.5, 4.0)))
        base = nb.mixv(nb.m("MULTIPLY", paint, 0.9), base, (0.72, 0.72, 0.68))
        rough = nb.mixf(paint, rough, 0.5)
        grain = nb.noise(pos, 40.0, 2.0)
        rough = nb.m("ADD", rough, nb.m("MULTIPLY", nb.m("SUBTRACT", grain, 0.5), 0.2))
        height = nb.m("ADD", height, nb.m("MULTIPLY", grain, 0.0015))
        scorch = nb.m("MULTIPLY", nb.inv(nb.ss(0.6, 3.4, dd)),
                      nb.m("ADD", 0.5, nb.m("MULTIPLY", nb.noise(pos, 1.2, 3.0), 0.5)))

    # seams and rivets
    base = nb.v("SCALE", base, scale=nb.inv(nb.m("MULTIPLY", seam, cfg["seam_dark"])))
    base = nb.v("SCALE", base, scale=nb.inv(nb.m("MULTIPLY", rivet, 0.18)))
    # edge chipping to bare metal
    base = nb.mixv(chip, base, cfg["chip"])
    # sun bleaching on up-facing surfaces: desaturate and lift a touch
    l = nb.lum(base)
    bleached = nb.mixv(0.35, base, nb.comb(*(nb.m("ADD", nb.m("MULTIPLY", l, 1.1), 0.02),) * 3))
    base = nb.mixv(nb.m("MULTIPLY", top, cfg["bleach"]), base, bleached)
    # grime in crevices, streaks off protrusions, pitting, soot
    base = nb.v("MULTIPLY", base, nb.mixv(grime, (1.0, 1.0, 1.0), GRIME_TINT))
    base = nb.v("SCALE", base, scale=nb.inv(nb.m("MULTIPLY", streak, 0.3)))
    base = nb.v("SCALE", base, scale=nb.inv(nb.m("MULTIPLY", pit, 0.28)))
    # large-scale mottling (uneven exposure / outgassing film), +-8 %
    mottle = nb.noise(pos, 0.045, 4.0, 0.55)
    base = nb.v("SCALE", base, scale=nb.m("ADD", 0.92, nb.m("MULTIPLY", nb.m("SUBTRACT", mottle, 0.5), 0.32)))
    dark = nb.m("MAXIMUM", soot, scorch)
    base = nb.v("SCALE", base, scale=nb.inv(nb.m("MULTIPLY", dark, 0.72)))

    rough = nb.m("ADD", rough, nb.m("MULTIPLY", seam, 0.15))
    rough = nb.m("ADD", rough, nb.m("MULTIPLY", grime, 0.12))
    rough = nb.m("ADD", rough, nb.m("MULTIPLY", streak, 0.08))
    rough = nb.m("ADD", rough, nb.m("MULTIPLY", nb.m("MAXIMUM", pit, dark), 0.15))
    rough = nb.mixf(chip, rough, 0.32)
    rough = nb.m("MAXIMUM", nb.m("MINIMUM", rough, 0.95), 0.08)
    metal = nb.mixf(chip, metal, cfg["chip_metal"])
    metal = nb.mixf(dark, metal, 0.0)
    return dict(albedo=base, rough=rough, metal=metal, height=height)


def build_solar_cells(nb):
    """One 3 x 3 m plate on UV 0..1: 12 x 12 mono cells, busbars, fingers, alloy frame."""
    uv = nb.uvmap("UVMap")
    P = nb.v("SCALE", uv, scale=SOLAR_PLATE)
    px, py, _ = nb.sep(P)
    L = SOLAR_PLATE
    d_edge = nb.m("MINIMUM", nb.m("MINIMUM", px, nb.m("SUBTRACT", L, px)),
                  nb.m("MINIMUM", py, nb.m("SUBTRACT", L, py)))
    frame = nb.inv(nb.ss(0.022, 0.028, d_edge))
    border = nb.inv(nb.ss(0.036, 0.04, d_edge))
    pitch = (L - 0.08) / 12
    q = nb.v("DIVIDE", nb.v("SUBTRACT", P, (0.04, 0.04, 0.0)), (pitch, pitch, 1.0))
    fx, fy, _ = nb.sep(nb.v("FRACTION", q))
    gd = nb.m("MULTIPLY", nb.m("MINIMUM", nb.m("MINIMUM", fx, nb.inv(fx)),
                                nb.m("MINIMUM", fy, nb.inv(fy))), pitch)
    gap = nb.inv(nb.ss(0.004, 0.007, gd))
    diag = nb.m("MULTIPLY", nb.m("ADD", nb.m("ABSOLUTE", nb.m("SUBTRACT", fx, 0.5)),
                                 nb.m("ABSOLUTE", nb.m("SUBTRACT", fy, 0.5))), pitch)
    corner = nb.ss(0.206, 0.212, diag)
    back = nb.m("MAXIMUM", nb.m("MAXIMUM", gap, corner), border)
    g3 = nb.m("FRACT", nb.m("MULTIPLY", fx, 3.0))
    bus = nb.inv(nb.ss(0.0022, 0.0036, nb.m("MULTIPLY", nb.m("ABSOLUTE", nb.m("SUBTRACT", g3, 0.5)),
                                                pitch / 3)))
    g20 = nb.m("FRACT", nb.m("MULTIPLY", fy, 20.0))
    finger = nb.inv(nb.ss(0.0004, 0.0009, nb.m("MULTIPLY", nb.m("ABSOLUTE", nb.m("SUBTRACT", g20, 0.5)),
                                                     pitch / 20)))
    cell_rnd = nb.white(nb.v("FLOOR", q))
    big = nb.noise(P, 0.6, 2.0)
    tone = nb.m("ADD", 0.82, nb.m("ADD", nb.m("MULTIPLY", cell_rnd, 0.22), nb.m("MULTIPLY", big, 0.12)))
    cell = nb.v("SCALE", (0.006, 0.016, 0.068), scale=tone)
    metal_line = nb.m("MULTIPLY", nb.m("MAXIMUM", bus, nb.m("MULTIPLY", finger, 0.25)), nb.inv(back))
    col = nb.mixv(back, cell, (0.07, 0.075, 0.09))
    col = nb.mixv(metal_line, col, (0.32, 0.33, 0.35))
    col = nb.mixv(frame, col, (0.42, 0.43, 0.45))
    rough = nb.mixf(back, nb.m("ADD", 0.13, nb.m("MULTIPLY", big, 0.08)), 0.42)
    rough = nb.mixf(metal_line, rough, 0.3)
    rough = nb.mixf(frame, rough, 0.4)
    metal = nb.m("MAXIMUM", metal_line, frame)
    height = nb.m("ADD", nb.m("MULTIPLY", back, -0.0015), nb.m("MULTIPLY", bus, 0.0006))
    height = nb.m("ADD", height, nb.m("MULTIPLY", frame, 0.003))
    return dict(albedo=col, rough=rough, metal=metal, height=height)


# ------------------------------------------------------------------ bake plumbing
class BakeMat:
    """A material rebuilt for baking: procedural outputs + switchable output wiring."""

    def __init__(self, mat, outputs, nb):
        self.mat, self.o, self.nb = mat, outputs, nb
        self.out = nb.n("ShaderNodeOutputMaterial", target="CYCLES")
        self.emit = nb.n("ShaderNodeEmission")
        self.diff = nb.n("ShaderNodeBsdfDiffuse")
        bump = nb.n("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 1.0
        bump.inputs["Distance"].default_value = 1.0
        if outputs.get("height") is not None:
            nb.put(bump.inputs["Height"], outputs["height"])
        nb.put(self.diff.inputs["Normal"], bump.outputs["Normal"])
        if outputs.get("rough") is not None:
            self.mr = nb.comb(1.0, outputs["rough"], outputs["metal"])
        self.target = nb.n("ShaderNodeTexImage")

    def set_pass(self, name, img):
        nb, links = self.nb, self.nb.nt.links
        for lk in list(self.out.inputs["Surface"].links):
            links.remove(lk)
        if name == "normal":
            links.new(self.diff.outputs[0], self.out.inputs["Surface"])
        else:
            src = {"albedo": self.o.get("albedo"), "mr": getattr(self, "mr", None),
                   "masks": self.o.get("masks")}[name]
            for lk in list(self.emit.inputs["Color"].links):
                links.remove(lk)
            if src is not None:
                nb.put(self.emit.inputs["Color"], src)
            links.new(self.emit.outputs[0], self.out.inputs["Surface"])
        self.target.image = img
        nb.nt.nodes.active = self.target


def add_dummy_target(mat, img):
    """Non-atlas materials still need an active image node or the bake refuses."""
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.name = node.label = "bake_dummy"
    node.image = img
    mat.node_tree.nodes.active = node


def remove_dummy_target(mat):
    node = mat.node_tree.nodes.get("bake_dummy")
    if node:
        mat.node_tree.nodes.remove(node)


def setup_cycles(samples):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = False
    scene.render.bake.margin = 6
    scene.render.bake.margin_type = "EXTEND"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        gpus = [d for d in prefs.devices if d.type == "METAL"]
        for d in prefs.devices:
            d.use = d.type == "METAL"
        scene.cycles.device = "GPU" if gpus else "CPU"
    except Exception as e:  # CPU is fine, just slower
        print("cycles GPU setup skipped:", e)
        scene.cycles.device = "CPU"
    print("BAKE device", scene.cycles.device)


def bake(objs, kind, samples, img):
    bpy.context.scene.cycles.samples = samples
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    t = time.time()
    bpy.ops.object.bake(type=kind, use_clear=True, margin=6)
    print(f"BAKE {img.name} {kind} {time.time() - t:.1f}s")


def save_image(img, fname, fmt, quality=92):
    os.makedirs(TEX_DIR, exist_ok=True)
    path = os.path.join(TEX_DIR, fname)
    img.filepath_raw = path
    img.file_format = fmt
    img.save(filepath=path, quality=quality)
    return path


# ------------------------------------------------------------------ UV layout
def buried_faces(objs, atlas_mats):
    """Per object, the set of atlas face indices that sit inside another solid (box bottoms
    sunk into the hull and so on). A point is inside when every probe ray first hits a
    back face. Those faces get no atlas space."""
    trees = []
    for o in objs:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        trees.append(BVHTree.FromBMesh(bm))
        bm.free()

    def first_hit_back(origin, d):
        best = None
        for t in trees:
            loc, nrm, _, dist = t.ray_cast(origin, d)
            if loc is not None and (best is None or dist < best[0]):
                best = (dist, nrm)
        return best is not None and best[1].dot(d) > 0

    out = {}
    for o in objs:
        me = o.data
        hidden = set()
        for pl in me.polygons:
            if me.materials[pl.material_index] not in atlas_mats:
                continue
            n = pl.normal
            tang = (me.vertices[pl.vertices[0]].co - pl.center).normalized()
            dirs = [n, (n + tang).normalized(), (n - tang).normalized(), tang, -tang]
            pts = [pl.center] + [pl.center.lerp(me.vertices[v].co, 0.8) for v in pl.vertices]
            if all(first_hit_back(p + n * 0.01, d) for p in pts for d in dirs):
                hidden.add(pl.index)
        out[o.name] = hidden
    print("BURIED faces", {k: len(v) for k, v in out.items()})
    return out


def unwrap_atlas(objs, atlas_mats):
    """Pack the atlas faces of all objects into one shared 0..1 layout."""
    buried = buried_faces(objs, atlas_mats)
    # Start from the panel UVs: metres, undistorted, one island per flat face or lathe strip
    # chunk. Packing rectangles fills the atlas far better than smart-project arcs.
    for o in objs:
        me = o.data
        uv = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
        buf = [0.0] * (len(me.loops) * 2)
        me.uv_layers["panel"].data.foreach_get("uv", buf)
        uv.data.foreach_set("uv", buf)
        me.uv_layers.active = uv
        uv.active_render = True
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.context.scene.tool_settings.use_uv_select_sync = True
    bpy.ops.object.mode_set(mode="EDIT")
    for o in objs:
        bm = bmesh.from_edit_mesh(o.data)
        hid = buried[o.name]
        for f in bm.faces:
            f.select_set(o.data.materials[f.material_index] in atlas_mats and f.index not in hid)
        bmesh.update_edit_mesh(o.data)
    # less texture for faces the top-down camera never sees
    for o in objs:
        bm = bmesh.from_edit_mesh(o.data)
        uvl = bm.loops.layers.uv["UVMap"]
        for isl in bmesh_utils.bmesh_linked_uv_islands(bm, uvl):
            if not all(f.select for f in isl):
                continue
            area = sum(f.calc_area() for f in isl) or 1.0
            nz = sum(f.normal.z * f.calc_area() for f in isl) / area
            k = BOTTOM_UV_SCALE if nz < -0.5 else 1.0
            if o.name == "station_solar":
                k *= SOLAR_STRUCT_UV_SCALE   # backing mostly hidden under the cells
            if k < 1.0:
                loops = [lp for f in isl for lp in f.loops]
                cx = sum(lp[uvl].uv.x for lp in loops) / len(loops)
                cy = sum(lp[uvl].uv.y for lp in loops) / len(loops)
                for lp in loops:
                    u = lp[uvl].uv
                    lp[uvl].uv = (cx + (u.x - cx) * k, cy + (u.y - cy) * k)
        bmesh.update_edit_mesh(o.data)
    # absolute margin (~3 px at 2048); the default SCALED margin wastes most of the
    # space with this many small islands
    bpy.ops.uv.pack_islands(rotate=True, rotate_method="ANY", margin_method="FRACTION",
                            margin=0.0015)
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in objs:   # buried faces: one corner texel, never seen
        uvd = o.data.uv_layers["UVMap"].data
        for pl in o.data.polygons:
            if pl.index in buried[o.name]:
                for i in pl.loop_indices:
                    uvd[i].uv = (0.0005, 0.9995)

    # texel density report (atlas faces only)
    area3d = area_uv = 0.0
    for o in objs:
        me = o.data
        uvd = me.uv_layers["UVMap"].data
        for pl in me.polygons:
            if me.materials[pl.material_index] not in atlas_mats:
                continue
            area3d += pl.area
            pts = [uvd[i].uv for i in pl.loop_indices]
            a = 0.0
            for k in range(1, len(pts) - 1):
                e1, e2 = pts[k] - pts[0], pts[k + 1] - pts[0]
                a += abs(e1.x * e2.y - e1.y * e2.x) / 2
            area_uv += a
    dens = math.sqrt(area_uv * ATLAS_RES ** 2 / max(area3d, 1e-6))
    print(f"ATLAS area3d={area3d:.0f} m2 uv_fill={area_uv:.2f} avg_px_per_m={dens:.1f}")


def set_solar_uvs(obj, solar_mat):
    """Solar plate tops get UV 0..1 per plate (the tiling cell texture); their thin sides
    and bottoms land on the frame corner."""
    me = obj.data
    uvd = me.uv_layers["UVMap"].data
    pan = me.uv_layers["panel"].data
    for pl in me.polygons:
        if me.materials[pl.material_index] != solar_mat:
            continue
        for i in pl.loop_indices:
            if pl.normal.z > 0.9:
                u, v = pan[i].uv
                uvd[i].uv = ((u % 64.0) / SOLAR_PLATE, (v % 64.0) / SOLAR_PLATE)
            else:
                uvd[i].uv = (0.004, 0.004)


def zero_uvs(obj, mats):
    me = obj.data
    uvd = me.uv_layers["UVMap"].data
    for pl in me.polygons:
        if me.materials[pl.material_index] in mats:
            for i in pl.loop_indices:
                uvd[i].uv = (0.002, 0.002)


# ------------------------------------------------------------------ final materials
def pbr_material(name, albedo, mr, normal, uv_map="UVMap"):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_backface_culling = True
    nb = NB(mat)
    out = nb.n("ShaderNodeOutputMaterial")
    bsdf = nb.n("ShaderNodeBsdfPrincipled")
    nb.put(out.inputs["Surface"], bsdf.outputs["BSDF"])
    uv = nb.uvmap(uv_map)
    a = nb.image(albedo, uv)
    nb.put(bsdf.inputs["Base Color"], a.outputs["Color"])
    m = nb.image(mr, uv)
    sep = nb.n("ShaderNodeSeparateColor")
    nb.put(sep.inputs[0], m.outputs["Color"])
    nb.put(bsdf.inputs["Roughness"], sep.outputs[1])
    nb.put(bsdf.inputs["Metallic"], sep.outputs[2])
    nm = nb.image(normal, uv)
    nmap = nb.n("ShaderNodeNormalMap", space="TANGENT", uv_map=uv_map)
    nb.put(nmap.inputs["Color"], nm.outputs["Color"])
    nb.put(bsdf.inputs["Normal"], nmap.outputs["Normal"])
    return mat


def remap_materials(obj, mapping):
    """Swap slot materials by `mapping` and merge slots that end up identical."""
    me = obj.data
    old = list(me.materials)
    new = []
    for m in old:
        t = mapping.get(m, m)
        if t not in new:
            new.append(t)
    idx = [new.index(mapping.get(m, m)) for m in old]
    mi = [0] * len(me.polygons)
    me.polygons.foreach_get("material_index", mi)
    mi = [idx[i] for i in mi]
    me.materials.clear()
    for m in new:
        me.materials.append(m)
    me.polygons.foreach_set("material_index", mi)
    me.update()


def load_saved(path, data):
    img = bpy.data.images.load(path, check_existing=False)
    img.colorspace_settings.name = "Non-Color" if data else "sRGB"
    return img


# ------------------------------------------------------------------ entry point
def texture_station(objs, mats, pad_centres):
    """objs: station mesh objects. mats: gen_station.MATS (key -> material)."""
    t0 = time.time()
    atlas_keys = [k for k in KINDS if k in mats]
    atlas_mats = {mats[k] for k in atlas_keys}
    solar_obj = next(o for o in objs if o.name == "station_solar")

    unwrap_atlas(objs, atlas_mats)
    set_solar_uvs(solar_obj, mats["solar"])
    for o in objs:
        zero_uvs(o, {mats[k] for k in EMISSIVE})

    setup_cycles(8)
    dummy = new_image("bake_dummy", 8, False)
    for k in EMISSIVE + ("solar",):
        add_dummy_target(mats[k], dummy)

    # pass 1: masks (R ao 0.8 m, G ao 4 m, B edge) shared by every kind
    masks = new_image("station_masks", ATLAS_RES, True)
    bms = {}
    for k in atlas_keys:
        nb = NB(mats[k])
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
        bm = BakeMat(mats[k], dict(masks=col), nb)
        bm.set_pass("masks", masks)
        bms[k] = bm
    bake(objs, "EMIT", 16, masks)

    # passes 2-4: full procedural surfaces
    albedo = new_image("station_hull_albedo", ATLAS_RES, False)
    mr = new_image("station_hull_mr", ATLAS_RES, True)
    normal = new_image("station_hull_normal", ATLAS_RES, True)
    for i, k in enumerate(atlas_keys):
        nb = NB(mats[k])
        outs = build_surface(nb, k, KINDS[k], masks, i + 1, pad_centres)
        bms[k] = BakeMat(mats[k], outs, nb)
    for name, img, kind, spp in (("albedo", albedo, "EMIT", 8), ("mr", mr, "EMIT", 8),
                                 ("normal", normal, "NORMAL", 8)):
        for bm in bms.values():
            bm.set_pass(name, img)
        bake(objs, kind, spp, img)
    p_alb = save_image(albedo, "station_hull_albedo.jpg", "JPEG", 92)
    p_mr = save_image(mr, "station_hull_mr.png", "PNG")
    p_nrm = save_image(normal, "station_hull_normal.png", "PNG")

    # solar cell tile on a temporary 3 x 3 m plate
    for k in EMISSIVE:
        remove_dummy_target(mats[k])
    me = bpy.data.meshes.new("solar_tile")
    me.from_pydata([(0, 0, 0), (SOLAR_PLATE, 0, 0), (SOLAR_PLATE, SOLAR_PLATE, 0), (0, SOLAR_PLATE, 0)],
                   [], [(0, 1, 2, 3)])
    uvl = me.uv_layers.new(name="UVMap")
    for lp, uv in zip(uvl.data, ((0, 0), (1, 0), (1, 1), (0, 1))):
        lp.uv = uv
    tile_mat = bpy.data.materials.new("solar_tile_bake")
    me.materials.append(tile_mat)
    tile = bpy.data.objects.new("solar_tile", me)
    bpy.context.scene.collection.objects.link(tile)
    nb = NB(tile_mat)
    sbm = BakeMat(tile_mat, build_solar_cells(nb), nb)
    s_alb = new_image("station_solar_albedo", SOLAR_RES, False)
    s_mr = new_image("station_solar_mr", SOLAR_RES, True)
    s_nrm = new_image("station_solar_normal", SOLAR_RES, True)
    for name, img, kind in (("albedo", s_alb, "EMIT"), ("mr", s_mr, "EMIT"), ("normal", s_nrm, "NORMAL")):
        sbm.set_pass(name, img)
        bake([tile], kind, 8, img)
    ps_alb = save_image(s_alb, "station_solar_albedo.jpg", "JPEG", 92)
    ps_mr = save_image(s_mr, "station_solar_mr.png", "PNG")
    ps_nrm = save_image(s_nrm, "station_solar_normal.png", "PNG")
    bpy.data.objects.remove(tile)
    bpy.data.meshes.remove(me)
    bpy.data.materials.remove(tile_mat)

    # final glTF materials from the saved files
    hull = pbr_material("station_hull", load_saved(p_alb, False), load_saved(p_mr, True),
                        load_saved(p_nrm, True))
    solar = pbr_material("station_solar_panel_cells", load_saved(ps_alb, False),
                         load_saved(ps_mr, True), load_saved(ps_nrm, True))
    mapping = {m: hull for m in atlas_mats}
    mapping[mats["solar"]] = solar
    for o in objs:
        remap_materials(o, mapping)
        o.data.uv_layers.remove(o.data.uv_layers["panel"])
    for img in (dummy, masks, albedo, mr, normal, s_alb, s_mr, s_nrm):
        bpy.data.images.remove(img)
    for m in list(atlas_mats) + [mats["solar"]]:
        if m.users == 0:
            bpy.data.materials.remove(m)
    print(f"TEXTURE done in {time.time() - t0:.0f}s")
