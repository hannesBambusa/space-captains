"""Baked surface textures for the mining outpost (used by gen_mining_outpost.py).

Same technique as station_textures.py (and reuses its node builder, surface kinds, UV
packer and bake plumbing): procedural Cycles shading per surface kind, baked to images.
On top of the station kinds this adds
  yellow  plain safety-yellow paint (crane, hopper)
  ore     broken ore rock (piles, hopper heap, silo fill, grab load)
  ore dust + grime: a brown dust film that builds up around the ore handling points
          (berth, hopper, belt, silos, stockpile), stronger on up-facing surfaces.

  atlas, 2048: every outpost mesh in one UV layout
               albedo (JPEG), metal/rough (JPEG, G = roughness, B = metallic), normal (PNG)
  belt tile, 512 x 1024: one 2.4 x 4.8 m stretch of cleated conveyor belt with ore lumps,
               seamless along V (the belt direction), for the scrolling ore_belt material.

Needs the "panel" UV layer that gen_mining_outpost.Part writes. It is removed before export.
"""
import math
import os
import time

import bpy

import common
import station_textures as st

ATLAS_RES = 2048
BELT_W, BELT_TILE = 2.4, 4.8      # belt tile size in metres (across, along)
BELT_RES = (512, 1024)
DUST = (0.165, 0.105, 0.062)      # ore dust colour (linear)
ORE_TONES = [(0.20, 0.110, 0.052), (0.27, 0.150, 0.070), (0.150, 0.115, 0.090),
             (0.31, 0.175, 0.080), (0.22, 0.135, 0.075)]
EMISSIVE = ("window", "light", "amber")

KINDS = {k: dict(st.KINDS[k]) for k in ("hull", "hull2", "dark", "orange", "hazard", "pad")}
KINDS["yellow"] = dict(st.KINDS["hazard"], tones=[(0.82, 0.50, 0.02), (0.78, 0.47, 0.02),
                                                  (0.84, 0.53, 0.03), (0.80, 0.49, 0.02)])
del KINDS["yellow"]["stripes"]


# ------------------------------------------------------------------ shading
def voronoi(nb, vec, scale, feature="F1"):
    node = nb.n("ShaderNodeTexVoronoi", voronoi_dimensions="3D", feature=feature)
    nb.put(node.inputs["Vector"], vec)
    node.inputs["Scale"].default_value = scale
    return node.outputs


def apply_dust(nb, outs, masks_img, sources):
    """Ore dust film: distance to the handling points, broken up by noise, heavier on
    up-facing faces and in crevices."""
    geo = nb.n("ShaderNodeNewGeometry")
    pos, nrm = geo.outputs["Position"], geo.outputs["Normal"]
    ao_n = nb.sep(nb.image(masks_img, nb.uvmap("UVMap")).outputs["Color"])[0]
    px, py, _ = nb.sep(pos)
    acc = None
    for cx, cy, r, k in sources:
        d = nb.v("LENGTH", nb.comb(nb.m("SUBTRACT", px, cx), nb.m("SUBTRACT", py, cy), 0.0))
        f = nb.m("MULTIPLY", nb.inv(nb.ss(r * 0.2, r, d)), k)
        acc = f if acc is None else nb.m("MAXIMUM", acc, f)
    up = nb.ss(-0.3, 0.9, nb.sep(nrm)[2])
    breakup = nb.ss(0.32, 0.68, nb.noise(pos, 0.5, 4.0, 0.6))
    fine = nb.noise(pos, 7.0, 3.0)
    crev = nb.inv(ao_n)
    amt = nb.m("ADD", nb.m("MULTIPLY", up, 0.7), 0.3)
    amt = nb.m("MULTIPLY", amt, nb.m("ADD", nb.m("MULTIPLY", breakup, 0.75), nb.m("MULTIPLY", crev, 0.9)))
    dust = nb.m("MULTIPLY", acc, amt, clamp=True)
    speck = nb.m("MULTIPLY", nb.ss(0.6, 0.68, fine), acc)
    dust = nb.m("MAXIMUM", dust, nb.m("MULTIPLY", speck, 0.6))
    col = nb.v("SCALE", DUST, scale=nb.m("ADD", 0.75, nb.m("MULTIPLY", fine, 0.5)))
    outs["albedo"] = nb.mixv(nb.m("MULTIPLY", dust, 0.88), outs["albedo"], col)
    outs["rough"] = nb.mixf(dust, outs["rough"], 0.92)
    outs["metal"] = nb.mixf(dust, outs["metal"], 0.0)
    outs["height"] = nb.m("ADD", outs["height"], nb.m("MULTIPLY", nb.m("MULTIPLY", dust, fine), 0.003))
    return outs


def build_ore(nb, masks_img):
    """Broken ore rock: per-chunk tone, cracks, grain, a few metallic vein flecks."""
    geo = nb.n("ShaderNodeNewGeometry")
    pos = geo.outputs["Position"]
    ao_n = nb.sep(nb.image(masks_img, nb.uvmap("UVMap")).outputs["Color"])[0]
    cells = voronoi(nb, pos, 1.3)
    tone = nb.ramp(nb.sep(cells["Color"])[0], ORE_TONES)
    crack_d = voronoi(nb, pos, 3.2, "DISTANCE_TO_EDGE")["Distance"]
    crack = nb.inv(nb.ss(0.02, 0.06, crack_d))
    grain = nb.noise(pos, 9.0, 4.0, 0.6)
    big = nb.noise(pos, 0.8, 3.0)
    vein_c = voronoi(nb, pos, 7.0)
    vein = nb.m("MULTIPLY", nb.ss(0.9, 0.94, nb.sep(vein_c["Color"])[1]),
                nb.inv(nb.ss(0.25, 0.4, vein_c["Distance"])))
    base = nb.v("SCALE", tone, scale=nb.m("ADD", 0.72, nb.m("ADD", nb.m("MULTIPLY", grain, 0.35),
                                                             nb.m("MULTIPLY", big, 0.2))))
    base = nb.v("SCALE", base, scale=nb.inv(nb.m("MULTIPLY", crack, 0.6)))
    base = nb.v("SCALE", base, scale=nb.m("ADD", 0.5, nb.m("MULTIPLY", ao_n, 0.5)))
    base = nb.mixv(vein, base, (0.58, 0.44, 0.24))
    rough = nb.m("SUBTRACT", nb.m("ADD", 0.84, nb.m("MULTIPLY", grain, 0.1)), nb.m("MULTIPLY", vein, 0.5))
    metal = nb.m("MULTIPLY", vein, 0.85)
    height = nb.m("ADD", nb.m("MULTIPLY", crack, -0.03), nb.m("MULTIPLY", grain, 0.025))
    return dict(albedo=base, rough=rough, metal=metal, height=height)


def build_belt(nb):
    """Cleated rubber belt carrying ore lumps. UV u across (0..1 = 2.4 m), v along
    (0..1 = 4.8 m). Every field is periodic in v (cylinder-mapped noise, cleats every
    1.2 m), so the tile repeats seamlessly along the belt."""
    uv = nb.uvmap("UVMap")
    u, v, _ = nb.sep(uv)
    R = BELT_TILE / (2 * math.pi)
    ang = nb.m("MULTIPLY", v, 2 * math.pi)
    C = nb.comb(nb.m("MULTIPLY", u, BELT_W), nb.m("MULTIPLY", nb.m("COSINE", ang), R),
                nb.m("MULTIPLY", nb.m("SINE", ang), R))
    wear = nb.noise(C, 2.5, 4.0, 0.6)
    base = nb.v("SCALE", (0.034, 0.034, 0.037), scale=nb.m("ADD", 0.75, nb.m("MULTIPLY", wear, 0.5)))
    rough = nb.m("ADD", 0.78, nb.m("MULTIPLY", wear, 0.12))
    edge_d = nb.m("MINIMUM", u, nb.inv(u))
    inner = nb.m("MULTIPLY", nb.ss(0.06, 0.09, u), nb.ss(0.06, 0.09, nb.inv(u)))
    # chevron cleats, 4 per tile
    t = nb.m("FRACT", nb.m("ADD", nb.m("MULTIPLY", v, 4.0),
                           nb.m("MULTIPLY", nb.m("ABSOLUTE", nb.m("SUBTRACT", u, 0.5)), 0.55)))
    cd = nb.m("MULTIPLY", nb.m("ABSOLUTE", nb.m("SUBTRACT", t, 0.5)), BELT_TILE / 4)
    cleat = nb.m("MULTIPLY", nb.inv(nb.ss(0.03, 0.05, cd)), inner)
    base = nb.mixv(cleat, base, (0.07, 0.07, 0.072))
    # worn belt edges
    edge = nb.inv(nb.ss(0.025, 0.045, edge_d))
    base = nb.mixv(edge, base, (0.11, 0.11, 0.115))
    # ore dust film
    film = nb.m("MULTIPLY", nb.ss(0.4, 0.7, nb.noise(C, 1.4, 3.0)), inner)
    base = nb.mixv(nb.m("MULTIPLY", film, 0.55), base, DUST)
    # ore lumps (cells ~0.3 m), concentrated in the middle of the trough
    cells = voronoi(nb, C, 3.4)
    rnd_r, rnd_g, _ = nb.sep(cells["Color"])
    band = nb.m("MULTIPLY", nb.ss(0.12, 0.2, u), nb.ss(0.12, 0.2, nb.inv(u)))
    dens = nb.ss(0.32, 0.55, nb.noise(C, 0.9, 2.0))
    present = nb.m("MULTIPLY", nb.m("MULTIPLY", nb.ss(0.3, 0.34, rnd_r), band), dens)
    shape = nb.inv(nb.ss(0.18, 0.42, cells["Distance"]))
    lump = nb.m("MULTIPLY", shape, present)
    lump_m = nb.ss(0.02, 0.12, lump)
    grain = nb.noise(C, 12.0, 3.0)
    ore = nb.v("SCALE", nb.ramp(rnd_g, ORE_TONES), scale=nb.m("ADD", 0.6, nb.m("MULTIPLY", lump, 0.4)))
    ore = nb.v("SCALE", ore, scale=nb.m("ADD", 0.8, nb.m("MULTIPLY", grain, 0.4)))
    base = nb.mixv(lump_m, base, ore)
    rough = nb.mixf(cleat, rough, 0.7)
    rough = nb.mixf(lump_m, rough, 0.9)
    height = nb.m("ADD", nb.m("MULTIPLY", cleat, 0.03), nb.m("MULTIPLY", lump, 0.09))
    height = nb.m("ADD", height, nb.m("MULTIPLY", nb.m("MULTIPLY", grain, lump_m), 0.01))
    return dict(albedo=base, rough=rough, metal=0.0, height=height)


# ------------------------------------------------------------------ helpers
def new_image(name, w, h, data):
    old = bpy.data.images.get(name)
    if old:
        bpy.data.images.remove(old)
    img = bpy.data.images.new(name, w, h, alpha=False, float_buffer=False, is_data=data)
    if data:
        img.colorspace_settings.name = "Non-Color"
    return img


def bake_belt_tile():
    """Bake the belt tile on a temporary 2.4 x 4.8 m plane. Returns saved paths."""
    me = bpy.data.meshes.new("belt_tile")
    me.from_pydata([(0, 0, 0), (BELT_W, 0, 0), (BELT_W, BELT_TILE, 0), (0, BELT_TILE, 0)],
                   [], [(0, 1, 2, 3)])
    uvl = me.uv_layers.new(name="UVMap")
    for lp, uv in zip(uvl.data, ((0, 0), (1, 0), (1, 1), (0, 1))):
        lp.uv = uv
    mat = bpy.data.materials.new("belt_tile_bake")
    me.materials.append(mat)
    tile = bpy.data.objects.new("belt_tile", me)
    bpy.context.scene.collection.objects.link(tile)
    mat.use_nodes = True
    nb = st.NB(mat)
    bm = st.BakeMat(mat, build_belt(nb), nb)
    imgs = {k: new_image("outpost_belt_" + k, *BELT_RES, k != "albedo")
            for k in ("albedo", "mr", "normal")}
    for name, kind in (("albedo", "EMIT"), ("mr", "EMIT"), ("normal", "NORMAL")):
        bm.set_pass(name, imgs[name])
        st.bake([tile], kind, 8, imgs[name])
    paths = (st.save_image(imgs["albedo"], "outpost_belt_albedo.jpg", "JPEG", 92),
             st.save_image(imgs["mr"], "outpost_belt_mr.png", "PNG"),
             st.save_image(imgs["normal"], "outpost_belt_normal.png", "PNG"))
    bpy.data.objects.remove(tile)
    bpy.data.meshes.remove(me)
    bpy.data.materials.remove(mat)
    for img in imgs.values():
        bpy.data.images.remove(img)
    return paths


# ------------------------------------------------------------------ entry point
def texture_outpost(objs, mats, belt_obj, pad_centres, dust_sources):
    """objs: atlas mesh objects (all with origin at the world origin while baking).
    mats: gen_mining_outpost.MATS. belt_obj gets the tiled ore_belt material."""
    t0 = time.time()
    st.ATLAS_RES = ATLAS_RES
    atlas_keys = [k for k in KINDS if k in mats] + ["ore"]
    atlas_mats = {mats[k] for k in atlas_keys}
    emissive = {mats[k] for k in EMISSIVE}

    st.unwrap_atlas(objs, atlas_mats)
    for o in objs:
        st.zero_uvs(o, emissive)

    st.setup_cycles(8)
    dummy = st.new_image("bake_dummy", 8, False)
    for m in emissive:
        st.add_dummy_target(m, dummy)

    # pass 1: masks (R ao 0.8 m, G ao 4 m, B edge)
    masks = st.new_image("outpost_masks", ATLAS_RES, True)
    bms = {}
    for k in atlas_keys:
        nb = st.NB(mats[k])
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
        bm = st.BakeMat(mats[k], dict(masks=col), nb)
        bm.set_pass("masks", masks)
        bms[k] = bm
    st.bake(objs, "EMIT", 16, masks)

    # passes 2-4: surfaces
    albedo = st.new_image("outpost_albedo", ATLAS_RES, False)
    mr = st.new_image("outpost_mr", ATLAS_RES, True)
    normal = st.new_image("outpost_normal", ATLAS_RES, True)
    for i, k in enumerate(atlas_keys):
        nb = st.NB(mats[k])
        if k == "ore":
            outs = build_ore(nb, masks)
        else:
            outs = st.build_surface(nb, k, KINDS[k], masks, i + 1, pad_centres)
        outs = apply_dust(nb, outs, masks, dust_sources)
        bms[k] = st.BakeMat(mats[k], outs, nb)
    for name, img, kind in (("albedo", albedo, "EMIT"), ("mr", mr, "EMIT"),
                            ("normal", normal, "NORMAL")):
        for bm in bms.values():
            bm.set_pass(name, img)
        st.bake(objs, kind, 8, img)
    p_alb = st.save_image(albedo, "outpost_albedo.jpg", "JPEG", 92)
    p_mr = st.save_image(mr, "outpost_mr.jpg", "JPEG", 92)  # PNG would push the glb past 10 MB
    p_nrm = st.save_image(normal, "outpost_normal.png", "PNG")
    for m in emissive:
        st.remove_dummy_target(m)

    b_alb, b_mr, b_nrm = bake_belt_tile()

    hull = st.pbr_material("outpost_hull", st.load_saved(p_alb, False), st.load_saved(p_mr, True),
                           st.load_saved(p_nrm, True))
    belt = st.pbr_material("ore_belt", st.load_saved(b_alb, False), st.load_saved(b_mr, True),
                           st.load_saved(b_nrm, True))
    mapping = {m: hull for m in atlas_mats}
    for o in objs:
        st.remap_materials(o, mapping)
        o.data.uv_layers.remove(o.data.uv_layers["panel"])
    belt_obj.data.materials.clear()
    belt_obj.data.materials.append(belt)
    for img in (dummy, masks, albedo, mr, normal):
        bpy.data.images.remove(img)
    for m in atlas_mats:
        if m.users == 0:
            bpy.data.materials.remove(m)
    print(f"TEXTURE done in {time.time() - t0:.0f}s")
