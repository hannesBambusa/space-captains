"""Generate the syndicate gunship .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_syndicate_ship.py
  Options after `--`: --no-preview (skip the PNG renders), --no-textures (flat materials,
  no Cycles bake: fast shape iteration), --extra=<dir> (debug close-ups into <dir>).

Design: "Warden" class gunship, the Syndicate's line warship. Navy grade, built along the
thrust axis: a dense wedge of slab armour (stand-off plates over a dark pressure hull, the
gaps read as recessed panel lines) in gunmetal over a charcoal lower hull, with the
faction's amber identity paint. Front to back:
  prow      blunt armoured nose with four torpedo tube ports and a sensor slit, an amber
            nose cap, RCS quads on the cheeks.
  foredeck  lower gun deck with the main battery: a twin heavy cannon turret on a hazard
            ringed barbette (syn_turret), barrels running out over the prow; spaced
            armour slabs and the stencil "SG-21" on the flanks. Under it the keel sensor
            array: gondola, survey dish, blade antennas, lidar dome.
  citadel   the tall armoured block: amber identity band round its front, a missile cell
            battery (two blocks of 2 x 2 hatches) on the deck, the bridge behind it
            (sloped front with recessed amber viewports under an armoured brow, side
            slits, roof hatch, hull number "21" on the roof, sensor mast with radar bar,
            dish and whips), spaced armour slabs on the shoulders, two ventral
            point-defence domes, keel strake.
  flanks    armoured side sponsons (magazines and coolant): flush radiator panels on the
            outer faces, a point-defence dome fore and aft on each with its ammunition
            feed, coolant conduits, RCS quads at the corners, running lights, the crew
            airlock on the port one. Their long forward tapers are amber: with the band
            they make the chevron that marks a Syndicate ship from above.
  stern     engineering deck with two flush radiators and the reactor hatch, then the
            thrust block: four bells (upper pair inboard, lower pair outboard, so all four
            plumes show from above) on gimbal mounts.
Gunmetal and charcoal, amber / hazard yellow markings, stencils, amber lights and glow.

Layout (Blender Z up, exported +Y up). Ship centre at origin on the play plane z=0.
The nose points along Blender +Y, which the exporter turns into Godot -Z (forward).
  length ~19.5 m (bell exits y = NOZZLE_Y -9.95 .. muzzles y = MUZZLE_Y 9.5), width ~7.3 m
  over the sponson radiators and airlock rails, hull z -1.75..1.72, with the fittings
  ~6.6 m tall (mast whips z ~4.0 .. keel blade antennas z ~-2.7).
  thrust block y -9.1..-8.5, engineering y -8.5..-5.3, citadel y -5.0..1.4 (amber band
  y 0.55..1.4), foredeck y 2.0..5.4, prow y 5.4..9.05, sponsons y -8.45..1.3 at
  x +-2.35..3.45 (taper from y -0.9), bridge y -4.6..-1.1, turret ring at TURRET
  (y 3.5, deck z 1.32).
Hierarchy: syndicate_gunship (empty root) -> syn_hull, syn_turret, engine_glow,
  muzzle_l (empty), muzzle_r (empty).
syn_turret has its origin on the turret ring axis (TURRET), unrotated, so Godot could
yaw it about local Y (the muzzle empties are children of the root, as in scavenger.glb,
so they do not follow a yaw).
engine_glow has its origin on the bell exit plane (Blender y = NOZZLE_Y, x = 0) and its
four plumes extend along Godot local +Z, so scaling it on Z lengthens the glow backwards.
Muzzle empties are unrotated, so their Godot -Z points forward along the barrels.
Same node contract as scavenger.glb (gen_scavenger_ship.py).
Textures: one 2048 worn atlas (worn_kit / station_textures bake, kinds re-scaled and
re-coloured for this ship), saved as blender/textures/syndicate_gunship_{albedo,mr,
normal}.jpg (+ _decals.png, the stencil sheet), material "syndicate_gunship_hull" on
syn_hull and syn_turret. Flat materials (no atlas): "syn_seam" (the dark hull under the
armour plates), "syn_glass", and the emissive "syn_window_amber", "syn_light_amber",
"syn_light_white", "syn_light_red", "syn_engine_glow".
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
import worn_kit as wk  # noqa: E402
from parts import ALONG_X, ALONG_Y, V, rot  # noqa: E402

PRE = "syndicate_gunship"
OUT = os.path.join(common.ROOT, "assets", "models", "ships", "syndicate_gunship.glb")
BLEND = os.path.join(common.ROOT, "blender", "syndicate_gunship.blend")

NOZZLE_Y = -9.95
BELL_R = 0.62
BELL_LEN = 0.85
ENG = [(-0.85, 0.62), (0.85, 0.62), (-1.8, -0.66), (1.8, -0.66)]   # (x, z) of the bells
T = 0.07                            # armour plate stand-off thickness
ZC = 1.65                           # citadel deck (substrate)
ZF = 1.25                           # foredeck (substrate)
TURRET = V((0.0, 3.5, ZF + T))      # turret ring centre on the foredeck plates
BARREL_DX = 0.45
BARREL_Z = 0.74                     # barrel height above the ring
MUZZLE_Y = 9.5
SPON_X, SPON_W = 2.9, 1.1           # sponson centre and width
SPON_ZT, SPON_ZB = 0.95, -1.0

# Main hull stations: (y, width, z top, z bottom, top chamfer, bottom chamfer)
HULL = (
    (-8.9, 4.8, 1.3, -1.35, 0.5, 0.7),
    (-8.5, 5.0, 1.5, -1.55, 0.6, 0.9),
    (-5.3, 5.0, 1.5, -1.6, 0.6, 0.95),
    (-5.0, 5.0, ZC, -1.65, 0.7, 1.0),
    (0.55, 5.0, ZC, -1.65, 0.7, 1.0),
    (1.4, 5.0, ZC, -1.65, 0.7, 1.0),
    (2.0, 4.9, ZF, -1.6, 0.6, 1.0),
    (5.4, 3.9, ZF, -1.4, 0.55, 0.85),
    (8.2, 2.7, 0.6, -1.05, 0.4, 0.55),
    (8.9, 2.3, 0.35, -0.95, 0.3, 0.4),
)
BRIDGE = (
    (-4.6, 1.8, 2.15, 0.3),
    (-4.2, 2.6, 2.6, 0.4),
    (-2.0, 2.6, 2.6, 0.4),
    (-1.1, 2.0, 2.05, 0.3),
)
LABELS = ["SG-21", "21", "#CHEV", "#BAR", "NO STEP", "TORPEDO", "DANGER", "KEEP CLEAR",
          "SYNDICATE", "REACTOR", "LOCK 1"]
INK_AMBER = (0.62, 0.36, 0.03)
INK_LIGHT = (0.5, 0.5, 0.47)

MATS = {}
DECALS = []
SCORCH = []

# Worn kinds at ship scale (process-local overrides): gunmetal upper works, charcoal lower
# hull, lighter blued replacement plate, amber identity paint, hazard yellow.
SYN_WORN = {
    "hull": dict(big=(1.6, 1.2), plate=(0.8, 0.6),
                 tones=[(0.185, 0.196, 0.213), (0.168, 0.179, 0.196), (0.2, 0.212, 0.23),
                        (0.157, 0.168, 0.185), (0.19, 0.196, 0.207), (0.174, 0.185, 0.207)],
                 plate_var=0.08, rough=(0.5, 0.12), metal=0.35, seam_big=0.45,
                 seam_small=0.2, rivets=True, hatches=0.12, chip=(0.36, 0.37, 0.38),
                 chip_metal=0.95, chip_k=1.1, grime_k=1.0, streak_k=0.3, bleach=0.08),
    "hull2": dict(big=(1.4, 1.0), plate=(0.7, 0.5),
                  tones=[(0.07, 0.074, 0.082), (0.062, 0.066, 0.074), (0.08, 0.084, 0.09),
                         (0.056, 0.06, 0.068), (0.075, 0.076, 0.08), (0.066, 0.07, 0.08)],
                  plate_var=0.08, rough=(0.56, 0.12), metal=0.3, seam_big=0.45,
                  seam_small=0.2, rivets=True, hatches=0.1, chip=(0.3, 0.31, 0.32),
                  chip_metal=0.95, chip_k=1.0, grime_k=0.9, streak_k=0.25, bleach=0.1),
    "hull3": dict(big=(1.2, 1.2), plate=(0.6, 0.6),
                  tones=[(0.275, 0.288, 0.308), (0.258, 0.272, 0.292), (0.292, 0.303, 0.32),
                         (0.248, 0.26, 0.28), (0.28, 0.286, 0.297), (0.264, 0.275, 0.297)],
                  plate_var=0.06, rough=(0.46, 0.12), metal=0.4, seam_big=0.4,
                  seam_small=0.15, rivets=True, hatches=0.1, chip=(0.4, 0.4, 0.41),
                  chip_metal=0.95, chip_k=1.1, grime_k=1.0, streak_k=0.3, bleach=0.08),
    "dark": dict(big=(1.0, 1.0), plate=(0.5, 0.5),
                 tones=[(0.04, 0.042, 0.046), (0.035, 0.037, 0.04), (0.046, 0.048, 0.05),
                        (0.032, 0.034, 0.037), (0.044, 0.043, 0.042), (0.038, 0.04, 0.044)],
                 plate_var=0.06, rough=(0.5, 0.14), metal=0.6, seam_big=0.35,
                 seam_small=0.15, rivets=False, hatches=0.0, chip=(0.28, 0.28, 0.29),
                 chip_metal=1.0, chip_k=0.9, grime_k=0.5, streak_k=0.2, bleach=0.05),
    "metal": dict(big=(1.0, 0.5), plate=(0.5, 0.5),
                  tones=[(0.30, 0.30, 0.31), (0.27, 0.27, 0.275), (0.33, 0.33, 0.335),
                         (0.25, 0.255, 0.26), (0.31, 0.305, 0.30), (0.28, 0.285, 0.29)],
                  plate_var=0.04, rough=(0.36, 0.1), metal=0.9, seam_big=0.3,
                  seam_small=0.1, rivets=False, hatches=0.0, chip=(0.36, 0.36, 0.37),
                  chip_metal=1.0, chip_k=0.0, grime_k=0.9, streak_k=0.3, bleach=0.0),
    "accent": dict(big=(1.2, 0.8), plate=(0.6, 0.4),
                   tones=[(0.62, 0.36, 0.025), (0.57, 0.33, 0.022), (0.66, 0.39, 0.03),
                          (0.54, 0.31, 0.025), (0.6, 0.35, 0.028), (0.58, 0.34, 0.025)],
                   plate_var=0.06, rough=(0.55, 0.1), metal=0.0, seam_big=0.4,
                   seam_small=0.15, rivets=False, hatches=0.0, chip=(0.1, 0.1, 0.105),
                   chip_metal=0.8, chip_k=0.6, grime_k=0.7, streak_k=0.3, bleach=0.15),
    "hazard": dict(big=(1.2, 1.2), plate=(0.6, 0.6),
                   tones=[(0.60, 0.40, 0.03), (0.57, 0.38, 0.028), (0.63, 0.42, 0.035),
                          (0.55, 0.37, 0.03), (0.61, 0.41, 0.03), (0.58, 0.39, 0.03)],
                   plate_var=0.05, rough=(0.6, 0.08), metal=0.0, seam_big=0.3,
                   seam_small=0.1, rivets=False, hatches=0.0, chip=(0.1, 0.1, 0.105),
                   chip_metal=0.7, chip_k=1.8, grime_k=1.2, streak_k=0.45, bleach=0.15,
                   stripes=0.24),
    # heat-blued engine bells
    "temper": dict(big=(0.6, 0.5), plate=(0.3, 0.5),
                   tones=[(0.17, 0.14, 0.22), (0.24, 0.16, 0.09), (0.12, 0.14, 0.24),
                          (0.27, 0.2, 0.11), (0.15, 0.12, 0.19), (0.2, 0.18, 0.2)],
                   plate_var=0.15, rough=(0.33, 0.1), metal=0.92, seam_big=0.25,
                   seam_small=0.1, rivets=False, hatches=0.0, chip=(0.3, 0.3, 0.3),
                   chip_metal=1.0, chip_k=0.0, grime_k=0.6, streak_k=0.5, bleach=0.0),
    # graphite radiator panels
    "radiator": dict(big=(1.6, 0.4), plate=(1.6, 0.2),
                     tones=[(0.11, 0.115, 0.125), (0.1, 0.105, 0.115), (0.12, 0.125, 0.135),
                            (0.095, 0.1, 0.11), (0.115, 0.118, 0.125), (0.105, 0.11, 0.12)],
                     plate_var=0.04, rough=(0.4, 0.08), metal=0.5, seam_big=0.5,
                     seam_small=0.3, rivets=False, hatches=0.0, chip=(0.3, 0.3, 0.3),
                     chip_metal=0.9, chip_k=0.4, grime_k=0.6, streak_k=0.3, bleach=0.0),
}
st.WORN_KINDS.update(SYN_WORN)


def build_materials():
    m = common.make_material
    MATS.clear()
    MATS["hull"] = m("syn_hull_gunmetal", (0.185, 0.196, 0.213), roughness=0.5, metallic=0.35)
    MATS["hull2"] = m("syn_hull_charcoal", (0.07, 0.074, 0.082), roughness=0.56, metallic=0.3)
    MATS["hull3"] = m("syn_plate_blued", (0.275, 0.288, 0.308), roughness=0.46, metallic=0.4)
    MATS["dark"] = m("syn_frame_dark", (0.04, 0.042, 0.046), roughness=0.5, metallic=0.6)
    MATS["metal"] = m("syn_bare_metal", (0.3, 0.3, 0.31), roughness=0.36, metallic=0.9)
    MATS["accent"] = m("syn_amber_paint", (0.62, 0.36, 0.025), roughness=0.55)
    MATS["hazard"] = m("syn_hazard_yellow", (0.6, 0.4, 0.03), roughness=0.6)
    MATS["temper"] = m("syn_bell_temper", (0.18, 0.15, 0.2), roughness=0.33, metallic=0.92)
    MATS["radiator"] = m("syn_radiator", (0.11, 0.115, 0.125), roughness=0.4, metallic=0.5)
    # flat (no atlas)
    MATS["seam"] = m("syn_seam", (0.016, 0.017, 0.019), roughness=0.7, metallic=0.3)
    glow = (0.03, 0.026, 0.02)
    MATS["glass"] = m("syn_glass", (0.01, 0.01, 0.012), roughness=0.12)
    MATS["window"] = m("syn_window_amber", glow, roughness=0.3,
                       emission=(1.0, 0.58, 0.14), emission_strength=2.2)
    MATS["light"] = m("syn_light_amber", glow, roughness=0.3,
                      emission=(1.0, 0.5, 0.06), emission_strength=6.0)
    MATS["white"] = m("syn_light_white", glow, roughness=0.3,
                      emission=(0.95, 0.93, 0.85), emission_strength=6.0)
    MATS["red"] = m("syn_light_red", glow, roughness=0.3,
                    emission=(1.0, 0.07, 0.03), emission_strength=6.0)
    MATS["glow"] = m("syn_engine_glow", (1.0, 0.85, 0.55), roughness=0.2,
                     emission=(1.0, 0.72, 0.35), emission_strength=5.5)
    for k in ("glass", "window", "light", "white", "red"):
        MATS[k].use_backface_culling = False


# ---------------------------------------------------------------- helpers
def label(text, centre, normal, up, h, colour, opacity=0.85):
    DECALS.append(st.decal(LABELS.index(text), centre, normal, up, h, colour, opacity))


def ring(y, w, zt, zb, ct, cb, x0=0.0):
    """Hull cross-section at y: w across X, top zt, bottom zb, separate top and bottom
    corner chamfers. Same 8-point order as parts.oct_ring (0 = +X side bottom, CCW seen
    from the stern): edge 0 +X side, 1 / 3 upper chamfers, 2 deck, 4 -X side, 5 / 7 lower
    chamfers, 6 belly."""
    hw = w / 2
    pts = [(hw, zb + cb), (hw, zt - ct), (hw - ct, zt), (-hw + ct, zt),
           (-hw, zt - ct), (-hw, zb + cb), (-hw + cb, zb), (hw - cb, zb)]
    return [V((x0 + x, y, z)) for x, z in pts]


def inset(pts, g):
    """Convex CCW 2D polygon moved inward by g on every edge, or None when it vanishes."""
    n = len(pts)
    lines = []
    for i in range(n):
        (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
        dx, dy = x1 - x0, y1 - y0
        ln = math.hypot(dx, dy)
        if ln < 1e-5:
            continue
        nx, ny = -dy / ln, dx / ln
        lines.append((x0 + nx * g, y0 + ny * g, dx / ln, dy / ln))
    if len(lines) < 3:
        return None
    out = []
    m = len(lines)
    for i in range(m):
        ax, ay, adx, ady = lines[i - 1]
        bx, by, bdx, bdy = lines[i]
        den = adx * bdy - ady * bdx
        if abs(den) < 1e-6:
            out.append((bx, by))
            continue
        t = ((bx - ax) * bdy - (by - ay) * bdx) / den
        out.append((ax + adx * t, ay + ady * t))
    area = sum(out[i][0] * out[(i + 1) % m][1] - out[(i + 1) % m][0] * out[i][1]
               for i in range(m)) / 2
    if area < 0.004:
        return None
    for i in range(m):   # an inverted edge means the plate was too small for the inset
        (x0, y0), (x1, y1) = out[i], out[(i + 1) % m]
        if (x1 - x0) * lines[i][2] + (y1 - y0) * lines[i][3] < 1e-4:
            return None
    return out


def plate(p, quad, mat, ref, gap=0.03, t=T, ch=0.03):
    """Stand-off armour plate over the (near-flat) polygon `quad`: inset by `gap`, raised
    by `t` along the normal that points away from `ref`, with a chamfered rim `ch`.
    No back face (it sits on the hull)."""
    quad = [V(q) for q in quad]
    cen = sum(quad, V((0, 0, 0))) / len(quad)
    n = (quad[2] - quad[0]).cross(quad[-1] - quad[1]).normalized()
    if n.dot(cen - V(ref)) < 0:
        n = -n
    u = (quad[1] - quad[0]).normalized()
    u = (u - n * u.dot(n)).normalized()
    v = n.cross(u)
    pts = [((q - cen).dot(u), (q - cen).dot(v)) for q in quad]
    if sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
           for i in range(len(pts))) < 0:
        pts.reverse()
    bot, top = inset(pts, gap), inset(pts, gap + ch)
    if bot is None or top is None or len(bot) != len(top):
        return False
    vb = [p.bm.verts.new(cen + u * x + v * y - n * 0.01) for x, y in bot]
    vt = [p.bm.verts.new(cen + u * x + v * y + n * t) for x, y in top]
    idx = p.mi(mat)
    p.bm.faces.new(vt).material_index = idx
    m = len(vb)
    uvl = getattr(p, "uv", None)
    for i in range(m):
        j = (i + 1) % m
        fc = p.bm.faces.new((vb[i], vb[j], vt[j], vt[i]))
        fc.material_index = idx
        if uvl is not None:   # rim strips: a third of the texel density, they are 8 cm tall
            ln, hh = (vb[j].co - vb[i].co).length * 0.35, (t + 0.03) * 0.5
            for lp, uv in zip(fc.loops, ((0, 0), (ln, 0), (ln, hh), (0, hh))):
                lp[uvl].uv = (900.0 + uv[0], 900.0 + uv[1])
    return True


def skin(p, rings, mat_fn, div_fn=None, sub="seam", t=T, gap=0.022, cap=True, stagger=False):
    """Pressure hull loft in the flat `sub` material with stand-off armour plates on every
    face. mat_fn(i, j, u, v, nu, nv) -> plate material key, None (bare hull shows), or
    ("face", key): no plates, the hull face itself takes `key`.
    div_fn(i, j, width, length) -> (nu, nv) plates across the ring edge and along Y.
    stagger: every other plate column is shifted half a plate (brick bond), so a column
    has nv or nv + 1 plates; mat_fn gets that column's own count."""
    face_mat = {}
    cells = []
    ref_all = sum((q for r in rings for q in r), V((0, 0, 0))) / sum(len(r) for r in rings)
    n = len(rings[0])
    for i in range(len(rings) - 1):
        ref = (sum(rings[i], V((0, 0, 0))) + sum(rings[i + 1], V((0, 0, 0)))) / (2 * n)
        for j in range(n):
            k = (j + 1) % n
            a, b, c, d = rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]
            width = ((b - a).length + (c - d).length) / 2
            length = ((d - a).length + (c - b).length) / 2
            if div_fn:
                nu, nv = div_fn(i, j, width, length)
            else:
                nu, nv = max(1, round(width / 1.15)), max(1, round(length / 0.95))
            for cu in range(nu):
                br = [q / nv for q in range(nv + 1)]
                if stagger and nv > 1 and (cu + j) % 2:
                    br = [0.0] + [(q + 0.5) / nv for q in range(nv)] + [1.0]
                for cv in range(len(br) - 1):
                    key = mat_fn(i, j, cu, cv, nu, len(br) - 1)
                    if isinstance(key, tuple):
                        face_mat[(i, j)] = key[1]
                        continue
                    if key is None:
                        continue
                    s0, s1, t0, t1 = cu / nu, (cu + 1) / nu, br[cv], br[cv + 1]

                    def pt(s, tt):
                        return a.lerp(b, s).lerp(d.lerp(c, s), tt)
                    cells.append(([pt(s0, t0), pt(s1, t0), pt(s1, t1), pt(s0, t1)], key, ref))
    p.loft(rings, sub, cap=cap, mat_fn=lambda i, j: face_mat.get((i, j), sub))
    for quad, key, ref in cells:
        plate(p, quad, key, ref, gap=gap, t=t)
    return ref_all


def frame(n, up=(0, 0, 1)):
    """4x4 rotation: X across, Y = up projected, Z = n (outward)."""
    n = V(n).normalized()
    u = V(up)
    if abs(u.dot(n)) > 0.95:
        u = V((0, 1, 0))
    u = (u - n * u.dot(n)).normalized()
    x = u.cross(n)
    return Matrix((x, u, n)).transposed().to_4x4()


def rail(p, a, b, out, h=0.09, posts=3, mat="metal"):
    """Handhold rail from a to b, standing `h` off the surface along `out`."""
    a, b, o = V(a), V(b), V(out).normalized() * h
    parts.strut(p, a + o, b + o, 0.035, 0.035, mat, up=o)
    for k in range(posts):
        q = a.lerp(b, k / (posts - 1))
        parts.strut(p, q, q + o, 0.03, 0.03, mat, up=(b - a))


def pdc(p, c, up=1, yaw=0.0):
    """Point-defence turret: collar, faceted dome, twin stub barrels, sensor eye."""
    c = V(c)
    m = Matrix.Translation(c) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Diagonal((1, 1, up, 1))
    p.cyl(m @ V((0, 0, 0.05)), 0.4, 0.44, 0.1, "dark", segs=12)
    p.lathe([(0.34, 0.08), (0.34, 0.2), (0.27, 0.36), (0.14, 0.45), (0.0, 0.47)], 10,
            lambda i, j: "hull3" if j < 2 else "hull", matrix=m, start=math.pi / 10)
    p.box(m @ V((0, 0.3, 0.26)), (0.3, 0.3, 0.2), "hull2", r=m.to_3x3().to_4x4(), bevel=0.2)
    for sx in (-1, 1):
        p.tube(m @ V((sx * 0.075, 0.4, 0.26)), m @ V((sx * 0.075, 0.95, 0.26)), 0.04, 0.035,
               "metal", segs=6)
    p.tube(m @ V((0, 0.9, 0.26)), m @ V((0, 0.98, 0.26)), 0.1, 0.1, "dark", segs=8)
    p.box(m @ V((0.2, 0.22, 0.38)), (0.07, 0.07, 0.07), "light", bevel=0.0)
    SCORCH.append((c.x, c.y + 0.9, c.z + up * 0.3, 0.35))


def hatch(p, c, w, ln, mat="hull3", h=0.05):
    """Flush armoured deck hatch with a hinge bar."""
    c = V(c)
    p.box(c, (w + 0.12, ln + 0.12, h * 0.6), "dark", bevel=0.0)
    p.box(c + V((0, 0, h * 0.5)), (w, ln, h), mat, bevel=0.25)
    p.box(c + V((0, -ln / 2 + 0.03, h)), (w * 0.7, 0.05, 0.04), "metal", bevel=0.0)


# ---------------------------------------------------------------- hull
def hull_shell(p):
    rings = [ring(*s) for s in HULL]

    def mf(i, j, u, v, nu, nv):
        h = (i * 31 + j * 17 + u * 7 + v * 13) % 23
        if i == 0:
            return "hull2"
        if j in (5, 6, 7):
            return "hull2"
        if i == 4 and j < 5:
            return "accent"                    # identity band round the citadel front
        if i == 8 and j in (1, 2, 3):
            return "accent"                    # amber nose cap
        if i in (2, 5):
            return "hull2"                     # the steps up to and down from the citadel
        if i == 1 and j in (0, 4):
            return "hull2"
        if h in (3, 11):
            return "hull3"
        if h == 7 and j in (0, 4):
            return "hull2"
        return "hull"

    def div(i, j, width, length):
        nv = max(1, round(length / 1.0))
        nu = max(1, round(width / 1.25))
        return nu, nv
    skin(p, rings, mf, div, stagger=True)
    # hull number and stencils on the citadel flanks
    for sx in (-1, 1):
        x = sx * (2.5 + T)
        label("SG-21", V((sx * 2.3, 3.6, 0.15)), (sx, 0.15, 0), (0, 0, 1), 0.5, INK_LIGHT, 0.9)
        label("SYNDICATE", V((sx * 2.25, 3.6, -0.4)), (sx, 0.15, 0), (0, 0, 1), 0.16,
              INK_AMBER, 0.85)
        label("TORPEDO", V((sx * 1.75, 6.9, -0.25)), (sx, 0.4, 0), (0, 0, 1), 0.14, INK_LIGHT,
              0.8)
    label("KEEP CLEAR", V((-1.55, 2.6, ZF + T)), (0, 0, 1), (1, 0, 0), 0.15, INK_LIGHT, 0.8)
    label("KEEP CLEAR", V((1.55, 2.6, ZF + T)), (0, 0, 1), (-1, 0, 0), 0.15, INK_LIGHT, 0.8)


def applique(p, quad, s0, s1, t0, t1, mat, ref, cut=0.22, t=0.13, lift=T):
    """Thick spaced-armour slab over part of a hull face (quad a, b, c, d as in skin:
    s across a->b, t along a->d), corners cut, standing on four bolt blocks."""
    a, b, c, d = quad

    def pt(s, tt):
        return a.lerp(b, s).lerp(d.lerp(c, s), tt)
    n = (c - a).cross(d - b).normalized()
    if n.dot((a + c) / 2 - V(ref)) < 0:
        n = -n
    ds, dt = (s1 - s0) * cut, (t1 - t0) * cut
    poly = [pt(s0 + ds, t0), pt(s1 - ds, t0), pt(s1, t0 + dt), pt(s1, t1 - dt),
            pt(s1 - ds, t1), pt(s0 + ds, t1), pt(s0, t1 - dt), pt(s0, t0 + dt)]
    plate(p, [q + n * lift for q in poly], mat, ref, gap=0.0, t=t, ch=0.04)
    for s, tt in ((s0 + ds, t0 + dt), (s1 - ds, t0 + dt), (s1 - ds, t1 - dt), (s0 + ds, t1 - dt)):
        p.box(pt(s, tt) + n * (lift + t + 0.01), (0.09, 0.09, 0.05), "dark", r=frame(n),
              bevel=0.0)


def spaced_armour(p):
    """Appliqué slabs: fore hull flanks, citadel shoulders, glacis."""
    rings = [ring(*s) for s in HULL]
    ref = V((0, 0, 0))
    for j in (0, 4):       # fore hull flanks
        q = [rings[6][j], rings[6][j + 1], rings[7][j + 1], rings[7][j]]
        applique(p, q, 0.12, 0.9, 0.05, 0.62, "hull3", ref + V((0, 4, 0)), cut=0.16)
        applique(p, q, 0.12, 0.9, 0.66, 0.96, "hull", ref + V((0, 4, 0)), cut=0.2)
    for j in (1, 3):       # citadel shoulders (upper chamfers)
        q = [rings[3][j], rings[3][j + 1], rings[4][j + 1], rings[4][j]]
        applique(p, q, 0.1, 0.9, 0.34, 0.63, "hull3", ref, cut=0.14, t=0.1)
        applique(p, q, 0.1, 0.9, 0.67, 0.97, "hull", ref, cut=0.14, t=0.1)
    for j in (1, 3):       # prow cheeks
        q = [rings[7][j], rings[7][j + 1], rings[8][j + 1], rings[8][j]]
        applique(p, q, 0.08, 0.92, 0.3, 0.92, "hull", ref + V((0, 6, -0.3)), cut=0.15, t=0.1)
    # keel strake with frames along the belly
    p.box(V((0, -3.4, -1.65 - T - 0.07)), (0.5, 9.4, 0.14), "dark", bevel=0.2)
    for k in range(9):
        y = -7.6 + k * 1.05
        p.box(V((0, y, -1.65 - T - 0.03)), (2.6, 0.12, 0.08), "hull2", bevel=0.0)


def prow(p):
    """Blunt nose block: four torpedo tube ports, sensor slit, tow eyes, nav lamps."""
    y = HULL[-1][0]
    p.loft([ring(*HULL[-1]), ring(y + 0.16, 2.05, 0.27, -0.87, 0.26, 0.36)], "hull2")
    fy = y + 0.16
    p.box(V((0, fy + 0.02, -0.42)), (1.9, 0.06, 0.5), "dark", bevel=0.2)
    for x in (-0.72, -0.24, 0.24, 0.72):
        p.cyl(V((x, fy + 0.06, -0.42)), 0.2, 0.2, 0.14, "metal", segs=12, axis_rot=ALONG_Y)
        p.cyl(V((x, fy + 0.1, -0.42)), 0.145, 0.145, 0.08, "seam", segs=12, axis_rot=ALONG_Y)
        p.box(V((x, fy + 0.05, -0.14)), (0.2, 0.05, 0.05), "hazard", bevel=0.0)
        SCORCH.append((x, fy + 0.1, -0.42, 0.4))
    parts.window(p, V((0, fy, 0.02)), (0, 1, 0), (0, 0, 1), 0.9, 0.1, "window")
    p.box(V((0, fy + 0.02, 0.14)), (1.2, 0.1, 0.05), "hull2", bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 0.98, fy - 0.1, -0.05)), (0.12, 0.12, 0.1), "light", bevel=0.0)
        # cheek sensor blisters on the upper chamfers
        c = V((sx * 1.28, 7.4, 0.58))
        p.box(c, (0.34, 0.9, 0.2), "hull2", r=frame((sx * 0.7, 0.1, 0.7), (0, 1, 0)), bevel=0.25)


def torpedo_bays(p):
    """Reload hatches for the bow tubes on the foredeck flanks, behind the cheek armour."""
    for sx in (-1, 1):
        for k in range(2):
            y = 5.85 + k * 0.95
            w = 3.9 - (y - 5.4) * 0.43
            x = sx * (w / 2 + T - 0.02)
            z = -0.3
            p.box(V((x, y, z)), (0.08, 0.7, 0.55), "hull3",
                  r=Matrix.Rotation(-sx * 0.21, 4, "Z"), bevel=0.25)
            p.box(V((x + sx * 0.03, y, z + 0.33)), (0.06, 0.5, 0.05), "hazard",
                  r=Matrix.Rotation(-sx * 0.21, 4, "Z"), bevel=0.0)


def foredeck(p):
    """Barbette under the main turret with a hazard ring, deck fittings."""
    z = ZF + T
    c = V((TURRET.x, TURRET.y, z))
    p.cyl(c + V((0, 0, -0.02)), 1.72, 1.8, 0.1, "hull2", segs=24)
    for k in range(16):
        a0 = k * math.pi / 8
        p.ring_segment(c + V((0, 0, 0.0)), 1.5, 1.7, a0, a0 + math.pi / 8, 0.03, 0.06,
                       "accent" if k % 2 else "dark", steps=1)
    for sx in (-1, 1):   # ready-use lockers and vents beside the barbette
        p.box(V((sx * 1.85, 2.55, z + 0.1)), (0.5, 0.7, 0.2), "hull2", bevel=0.2)
        for k in range(3):
            p.box(V((sx * 1.85, 2.35 + k * 0.2, z + 0.21)), (0.4, 0.06, 0.03), "dark",
                  bevel=0.0)
        rail(p, V((sx * 1.62, 4.3, z)), V((sx * 1.5, 5.2, z)), (0, 0, 1))
    # torpedo strike-down hatches and mooring cleats on the prow deck
    for sx in (-1, 1):
        c = V((sx * 0.95, 6.5, 1.07))
        r = rot(rx=-0.228)
        p.box(c, (0.5, 0.9, 0.06), "hull2", r=r, bevel=0.25)
        p.box(c + V((0, 0, 0.03)), (0.36, 0.7, 0.05), "hull3", r=r, bevel=0.25)
        p.box(V((sx * 0.75, 7.75, 0.8)), (0.12, 0.3, 0.1), "dark", r=r, bevel=0.0)
    # breakwater plate ahead of the turret
    p.box(V((0, 5.62, z + 0.1)), (2.4, 0.1, 0.24), "hull2", r=rot(rx=-0.35), bevel=0.0)
    for sx in (-1, 1):
        p.box(V((sx * 0.8, 5.5, z + 0.06)), (0.08, 0.3, 0.16), "dark", bevel=0.0)


def keel_array(p):
    """Keel sensor array under the foredeck: gondola, survey dish, blades, lidar dome."""
    p.loft([parts.oct_ring(2.3, 0.9, 0.3, 0.1, z0=-1.72), parts.oct_ring(2.7, 1.5, 0.5, 0.16, z0=-1.82),
            parts.oct_ring(4.9, 1.4, 0.5, 0.16, z0=-1.72), parts.oct_ring(5.5, 0.8, 0.3, 0.1, z0=-1.55)],
           "hull2", mat_fn=lambda i, j: "dark" if j == 6 else "hull2")
    parts.dish(p, V((0, 4.35, -2.02)), 0.46, (0, 0.25, -1), "hull3", "dark", depth=0.16, segs=12)
    p.cyl(V((0, 4.35, -2.0)), 0.12, 0.16, 0.1, "dark", segs=8)
    p.sphere(V((0.38, 3.2, -2.08)), 0.17, "glass", segs=10, rings=6)
    p.cyl(V((0.38, 3.2, -2.05)), 0.2, 0.2, 0.06, "metal", segs=10)
    for x, y, ln in ((-0.42, 3.0, 0.6), (-0.42, 3.5, 0.45), (0.5, 4.0, 0.5), (-0.5, 4.75, 0.4)):
        p.box(V((x, y, -2.07 - ln / 2)), (0.04, 0.22, ln), "metal", bevel=0.0)
    p.box(V((0, 2.75, -2.1)), (0.5, 0.3, 0.08), "hull3", bevel=0.2)
    p.box(V((0, 5.3, -1.72)), (0.14, 0.08, 0.08), "light", bevel=0.0)
    for sx in (-1, 1):   # ventral point defence
        pdc(p, V((sx * 1.05, -2.6, -1.65 - T)), up=-1)
    # docking clamps and belly hatch
    for y in (-0.6, -4.4):
        for sx in (-1, 1):
            p.box(V((sx * 0.55, y, -1.65 - T - 0.08)), (0.3, 0.5, 0.16), "dark", bevel=0.2)
    hatch(p, V((0, -6.9, -1.6 - T - 0.02)), 1.0, 1.2, "hull2")


def bridge(p):
    """Armoured bridge: sloped front with recessed viewports under a brow, side slits,
    roof hatch and sensors."""
    zb = ZC - 0.05
    rings = [ring(y, w, zt, zb, ct, 0.04) for y, w, zt, ct in BRIDGE]

    def mf(i, j, u, v, nu, nv):
        if j in (5, 6, 7):
            return None
        if i == 2 and j in (1, 2, 3):
            return ("face", "glass")
        if i == 1 and j in (0, 4) and v == 1:
            return None
        if i == 0:
            return "hull2"
        return "hull3" if (j == 2 and v == 0 and i == 1) else "hull"

    def div(i, j, width, length):
        if i == 1:
            return 1, (2 if j == 2 else 3)
        return 1, 1
    skin(p, rings, mf, div, t=0.09)
    # recessed amber viewports in the front slope and its two corner facets
    r0, r1 = rings[2], rings[3]
    for j, cols in ((2, 3), (1, 1), (3, 1)):
        a, b, c, d = r0[j], r0[j + 1], r1[j + 1], r1[j]
        n = (c - a).cross(d - b).normalized()
        if n.z < 0:
            n = -n
        up = ((c + d) / 2 - (a + b) / 2)
        for k in range(cols):
            s = (k + 0.5) / cols
            cen = a.lerp(b, s).lerp(d.lerp(c, s), 0.5)
            wd = (a - b).length * 0.4 + (d - c).length * 0.4
            parts.quad(p, cen + n * 0.04, n, up, wd / cols - 0.12, up.length * 0.24, "window")
        # mullions between the panes, standing proud of the glass
        for k in range(cols + 1):
            s = k / cols
            q0, q1 = a.lerp(b, s), d.lerp(c, s)
            parts.strut(p, q0 + n * 0.05, q1 + n * 0.05, 0.09, 0.1, "hull2", up=n)
        parts.strut(p, a + n * 0.05, b + n * 0.05, 0.1, 0.1, "hull2", up=n)
        parts.strut(p, d + n * 0.05, c + n * 0.05, 0.1, 0.1, "hull2", up=n)
    # armoured brow over the viewports
    p.box(V((0, -1.95, 2.72)), (2.0, 0.5, 0.1), "hull2", r=rot(rx=-0.12), bevel=0.3)
    # side slits (in the gap left between the side plates)
    for sx in (-1, 1):
        x = sx * 1.3
        for y in (-3.3, -2.9):
            parts.quad(p, V((x + sx * 0.04, y, 2.02)), (sx, 0, 0), (0, 0, 1), 0.3, 0.14, "window")
        p.box(V((x + sx * 0.08, -3.1, 2.2)), (0.08, 0.86, 0.06), "hull2", bevel=0.0)
    # roof: hull number forward, hatch, sensor dome and beacon aft, hazard strip
    z = 2.6 + 0.09
    label("21", V((0, -2.56, z)), (0, 0, 1), (0, 1, 0), 1.35, INK_LIGHT, 0.95)
    hatch(p, V((-0.5, -3.6, z + 0.02)), 0.55, 0.55)
    p.cyl(V((0.5, -3.55, z + 0.04)), 0.26, 0.3, 0.08, "dark", segs=12)
    p.sphere(V((0.5, -3.55, z + 0.1)), 0.24, "hull3", segs=12, rings=6)
    p.cyl(V((0.0, -3.72, z + 0.05)), 0.1, 0.12, 0.1, "dark", segs=8)
    p.cyl(V((0.0, -3.72, z + 0.14)), 0.08, 0.07, 0.1, "light", segs=8)
    p.box(V((0, -4.05, z + 0.01)), (1.6, 0.14, 0.04), "hazard", bevel=0.0)
    for x, hgt in ((0.95, 1.2), (0.75, 0.8)):
        p.tube(V((x, -3.9, z)), V((x, -4.1, z + hgt)), 0.022, 0.01, "dark", segs=4)


def mast(p):
    """Sensor mast behind the bridge: radar bar, comms dish, yard with whips, beacon."""
    base = V((0, -4.75, 1.5 + T))
    p.box(base + V((0, 0, 0.2)), (0.9, 0.5, 0.4), "hull2", bevel=0.2)
    p.tube(base + V((0, 0, 0.3)), base + V((0, -0.15, 2.05)), 0.11, 0.07, "hull2", segs=6)
    top = base + V((0, -0.15, 2.05))
    p.beam(top + V((-0.75, 0, -0.35)), top + V((0.75, 0, -0.35)), 0.06, 0.06, "dark")
    p.box(top + V((0, 0.05, -0.75)), (1.3, 0.14, 0.28), "hull3", bevel=0.2)   # radar bar
    p.box(top + V((0, 0.13, -0.75)), (1.2, 0.02, 0.2), "dark", bevel=0.0)
    for sx in (-1, 1):
        p.tube(top + V((sx * 0.75, 0, -0.35)), top + V((sx * 0.8, -0.1, 0.35)), 0.02, 0.01,
               "dark", segs=4)
    parts.dish(p, base + V((0, -0.42, 1.0)), 0.36, (0, -0.8, 0.6), "hull3", "dark", depth=0.13,
               segs=12)
    p.box(top + V((0, 0, 0.06)), (0.1, 0.1, 0.1), "red", bevel=0.0)
    for sx in (-1, 1):   # mast stays
        parts.strut(p, base + V((sx * 0.4, 0.1, 0.35)), top + V((0, 0, -0.5)), 0.035, 0.035,
                    "dark")


def citadel_deck(p):
    """Missile cell battery between the bridge and the identity band, airlock, rails."""
    z = ZC + T
    for sx in (-1, 1):
        cx = sx * 1.05
        p.box(V((cx, -0.25, z + 0.015)), (1.25, 1.25, 0.05), "dark", bevel=0.0)
        for ix in (-1, 1):
            for iy in (-1, 1):
                c = V((cx + ix * 0.29, -0.25 + iy * 0.29, z + 0.05))
                p.box(c, (0.48, 0.48, 0.08), "hull3" if (ix + iy + sx) % 3 else "hull",
                      bevel=0.25)
                p.box(c + V((0, -0.2, 0.045)), (0.3, 0.04, 0.03), "metal", bevel=0.0)
        p.box(V((cx, 0.42, z + 0.03)), (1.25, 0.08, 0.04), "hazard", bevel=0.0)
        rail(p, V((sx * 1.72, -4.3, z)), V((sx * 1.72, -1.4, z)), (0, 0, 1), posts=4)
        # deck edge marker lamps
        p.box(V((sx * 1.74, -0.95, z + 0.03)), (0.08, 0.14, 0.06), "light", bevel=0.0)
    label("DANGER", V((0, -0.25, z)), (0, 0, 1), (0, 1, 0), 0.16, INK_AMBER, 0.9)
    # service trunk between the two cell blocks
    p.box(V((0, -0.3, z + 0.04)), (0.22, 1.4, 0.1), "hull2", bevel=0.2)
    # antenna farm and vents on the deck edge beside the bridge
    for sx in (-1, 1):
        for k in range(4):
            p.box(V((sx * 1.55, -4.55 + k * 0.16, z + 0.02)), (0.36, 0.08, 0.04), "dark",
                  bevel=0.0)


def sponson(p, sx):
    """Armoured flank pod: radiators outboard, point defence fore and aft, RCS, lamps.
    Its long forward taper carries the amber shoulder chevron."""
    x = sx * SPON_X
    rs = [ring(-8.45, 0.6, 0.6, -0.7, 0.15, 0.2, x0=sx * 2.72),
          ring(-7.85, SPON_W, SPON_ZT, SPON_ZB, 0.3, 0.38, x0=x),
          ring(-0.9, SPON_W, SPON_ZT, SPON_ZB, 0.3, 0.38, x0=x),
          ring(1.3, 0.36, 0.5, -0.62, 0.1, 0.14, x0=sx * 2.56)]
    out_j, in_j = (0, 4) if sx > 0 else (4, 0)

    def mf(i, j, u, v, nu, nv):
        if j == in_j:
            return None
        if j in (5, 6, 7):
            return "hull2"
        if i == 2:
            return "accent" if j in (1, 2, 3) else "hull"
        if i == 1 and j == out_j:
            return "hull2"
        return "hull3" if (i + j * 3 + v) % 6 == 0 else "hull"

    def div(i, j, width, length):
        if i == 1:
            return 1, (6 if j == 2 else 7)
        return 1, (2 if i == 2 else 1)
    skin(p, rs, mf, div)
    xo = sx * (SPON_X + SPON_W / 2 + T)
    for yc, ln in ((-6.3, 2.6), (-2.75, 2.9)):   # flush radiators, framed
        p.box(V((xo, yc, -0.02)), (0.04, ln + 0.2, 1.2), "dark", bevel=0.0)
        parts.radiator(p, V((xo + sx * 0.035, yc, -0.02)), ln, 1.04, (sx, 0, 0), "radiator",
                       "metal", ribs=round(ln * 3.3), t=0.05)
    if sx > 0:   # starboard: coolant header between the panels
        p.box(V((xo, -4.6, -0.02)), (0.08, 0.34, 1.1), "hull2", bevel=0.0)
        for z in (0.35, -0.4):
            parts.pipe(p, V((xo + sx * 0.03, -4.85, z)), V((xo + sx * 0.03, -4.35, z)), 0.05,
                       "metal", segs=6)
    else:        # port: crew airlock with handholds, lamp and stencil
        p.box(V((xo - 0.01, -4.6, -0.02)), (0.08, 0.72, 1.16), "dark", bevel=0.0)
        p.box(V((xo - 0.05, -4.6, -0.04)), (0.08, 0.56, 0.98), "hull3", bevel=0.2)
        parts.window(p, V((xo - 0.065, -4.6, 0.2)), (-1, 0, 0), (0, 0, 1), 0.18, 0.12, "window")
        p.box(V((xo - 0.05, -4.6, 0.62)), (0.08, 0.3, 0.06), "light", bevel=0.0)
        for y in (-4.98, -4.22):
            rail(p, V((xo - 0.02, y, -0.4)), V((xo - 0.02, y, 0.35)), (-1, 0, 0), posts=3)
        label("LOCK 1", V((xo, -4.6, -0.5)), (-1, 0, 0), (0, 0, 1), 0.07, INK_LIGHT, 0.85)
    zt = SPON_ZT + T
    pdc(p, V((x, -1.6, zt)))
    pdc(p, V((x, -7.0, zt)), yaw=math.pi)
    hatch(p, V((x, -3.4, zt + 0.01)), 0.4, 0.6)
    hatch(p, V((x, -5.2, zt + 0.01)), 0.4, 0.4, "hull2")
    for y, d in ((-2.25, -1), (-6.35, 1)):   # ammunition feeds beside the point defence
        p.box(V((x, y, zt + 0.09)), (0.5, 0.5, 0.18), "hull2", bevel=0.2)
        p.box(V((x, y + d * 0.33, zt + 0.07)), (0.2, 0.2, 0.1), "dark", bevel=0.0)
        p.box(V((x, y, zt + 0.19)), (0.36, 0.1, 0.03), "hazard", bevel=0.0)
    for k in range(5):                       # vent slats
        p.box(V((x, -4.0 - k * 0.13, zt + 0.02)), (0.42, 0.06, 0.04), "dark", bevel=0.0)
    p.hazard(-0.25, 0.25, 0.3, 0.0, 0.03, matrix=Matrix.Translation((x, -7.62, zt)),
             pitch=0.17, cols=("accent", "dark"))
    for y in (-1.25, -7.45):
        parts.rcs_quad(p, V((sx * (SPON_X + SPON_W / 2 - 0.08), y, SPON_ZT - 0.08)), (sx, 0, 1),
                       "hull2", "metal", s=0.3)
        parts.rcs_quad(p, V((sx * (SPON_X + SPON_W / 2 - 0.1), y, SPON_ZB + 0.1)), (sx, 0, -1),
                       "hull2", "metal", s=0.3)
    # coolant conduits along the inboard edge of the sponson top, up to the citadel
    for dz, r in ((0.12, 0.055), (0.24, 0.04)):
        xi = sx * (2.5 + T + 0.07)
        parts.pipe(p, V((xi, -7.4, zt + dz - 0.06)), V((xi, -1.2, zt + dz - 0.06)), r, "metal",
                   segs=6)
    for k in range(6):
        p.box(V((sx * (2.5 + T + 0.07), -7.1 + k * 1.14, zt + 0.1)), (0.16, 0.1, 0.3), "dark",
              bevel=0.0)
    # running lights: amber forward, white aft
    p.box(V((sx * 2.68, 1.3, -0.05)), (0.14, 0.1, 0.14), "light", bevel=0.0)
    p.box(V((xo + sx * 0.02, -0.95, 0.5)), (0.06, 0.2, 0.1), "light", bevel=0.0)
    p.box(V((xo + sx * 0.02, -7.75, 0.5)), (0.06, 0.2, 0.1), "white", bevel=0.0)
    label("NO STEP", V((x, -4.3, zt)), (0, 0, 1), (sx, 0, 0), 0.11, INK_LIGHT, 0.8)


def engineering(p):
    """Engineering deck: two flush radiators, reactor hatch, coolant lines, stern trim."""
    z = 1.5 + T
    for sx in (-1, 1):
        p.box(V((sx * 1.1, -6.9, z + 0.01)), (1.5, 2.7, 0.04), "dark", bevel=0.0)
        parts.radiator(p, V((sx * 1.1, -6.9, z + 0.045)), 2.5, 1.34, (0, 0, 1), "radiator",
                       "metal", ribs=8, t=0.05)
        parts.pipe(p, V((sx * 0.28, -8.2, z + 0.06)), V((sx * 0.28, -5.5, z + 0.06)), 0.06,
                   "metal", segs=6)
        for y in (-7.8, -6.9, -6.0):
            p.box(V((sx * 0.28, y, z + 0.05)), (0.2, 0.1, 0.12), "dark", bevel=0.0)
    hatch(p, V((0, -6.3, z + 0.02)), 0.3, 0.7, "hull3")
    label("REACTOR", V((0, -5.62, z)), (0, 0, 1), (0, 1, 0), 0.12, INK_AMBER, 0.85)
    p.hazard(-1.85, 1.85, 0.2, 0.0, 0.04, matrix=Matrix.Translation((0, -8.33, z)),
             pitch=0.3, cols=("accent", "dark"))
    for sx in (-1, 1):   # RCS and tail lamps on the stern shoulders
        p.box(V((sx * 1.6, -8.75, 1.3)), (0.2, 0.1, 0.1), "white", bevel=0.0)


def engines(p):
    """Thrust block: armoured thrust plate, four bells on gimbal mounts, heat shields."""
    y0 = HULL[0][0]
    p.loft([ring(y0 - 0.22, 4.3, 1.15, -1.2, 0.45, 0.62), ring(*HULL[0])], "dark")
    yf = y0 - 0.22
    p.box(V((0, yf - 0.02, 0.0)), (3.2, 0.06, 0.12), "hazard", bevel=0.0)
    for x, z in ENG:
        p.cyl(V((x, yf - 0.05, z)), 0.5, 0.56, 0.14, "hull2", segs=16, axis_rot=ALONG_Y)
        p.cyl(V((x, yf - 0.14, z)), 0.36, 0.42, 0.1, "metal", segs=16, axis_rot=ALONG_Y)
        parts.bell(p, NOZZLE_Y, BELL_R, BELL_LEN - 0.1, "temper", "dark", x=x, z=z, segs=18)
        p.torus(V((x, NOZZLE_Y + 0.12, z)), BELL_R * 0.96, 0.035, "metal", segs=18,
                minor_segs=4, matrix=rot(rx=math.pi / 2))
        p.torus(V((x, NOZZLE_Y + 0.42, z)), BELL_R * 0.78, 0.03, "dark", segs=18,
                minor_segs=4, matrix=rot(rx=math.pi / 2))
        for k in range(3):
            a = math.pi / 2 + k * 2 * math.pi / 3
            d = V((math.cos(a), 0, math.sin(a)))
            parts.pipe(p, V((x, yf - 0.05, z)) + d * 0.5, V((x, NOZZLE_Y + 0.4, z)) + d * 0.5,
                       0.035, "metal", segs=5)
        SCORCH.append((x, yf - 0.1, z, 1.0))
    # stern service detail between the bells
    p.box(V((0, yf - 0.06, -0.55)), (0.8, 0.12, 0.6), "hull2", bevel=0.2)
    for k in range(4):
        p.box(V((0, yf - 0.13, -0.78 + k * 0.15)), (0.6, 0.03, 0.06), "dark", bevel=0.0)
    p.box(V((0, yf - 0.05, 0.9)), (0.3, 0.08, 0.1), "light", bevel=0.0)


def prow_rcs(p):
    for sx in (-1, 1):
        parts.rcs_quad(p, V((sx * 1.62, 6.1, 0.98)), (sx, 0, 1), "hull2", "metal", s=0.28)
        parts.rcs_quad(p, V((sx * 1.4, 6.1, -1.0)), (sx, 0, -1), "hull2", "metal", s=0.28)


def build_hull():
    p = parts.PanelPart("syn_hull", MATS)
    hull_shell(p)
    spaced_armour(p)
    prow(p)
    torpedo_bays(p)
    foredeck(p)
    keel_array(p)
    bridge(p)
    mast(p)
    citadel_deck(p)
    for sx in (-1, 1):
        sponson(p, sx)
    engineering(p)
    engines(p)
    prow_rcs(p)
    return p


# ---------------------------------------------------------------- turret
def build_turret():
    """Twin heavy cannon turret, built around its ring centre (object origin = TURRET)."""
    p = parts.PanelPart("syn_turret", MATS)
    p.cyl(V((0, 0, 0.08)), 1.42, 1.48, 0.16, "dark", segs=24)
    p.cyl(V((0, 0, 0.2)), 1.3, 1.36, 0.12, "metal", segs=24)
    rings = [ring(-1.5, 1.7, 1.02, 0.32, 0.25, 0.1), ring(-1.15, 2.5, 1.32, 0.28, 0.42, 0.14),
             ring(0.45, 2.5, 1.32, 0.28, 0.42, 0.14), ring(1.3, 1.8, 0.98, 0.4, 0.3, 0.1)]

    def mf(i, j, u, v, nu, nv):
        if j == 6:
            return None
        if j in (5, 7):
            return "hull2"
        if i == 1 and j == 2 and v == 0:
            return "accent"
        if i == 0:
            return "hull2"
        if i == 2 and j == 2:
            return "hull3"
        return "hull"

    def div(i, j, width, length):
        if i == 1 and j == 2:
            return 2, 3
        return 1, (2 if i == 1 else 1)
    skin(p, rings, mf, div, t=0.08)
    zr = 1.32 + 0.08
    # roof: commander's hatch, sight head, whip, hull number
    hatch(p, V((-0.45, -0.1, zr + 0.02)), 0.5, 0.5)
    p.box(V((0.5, 0.15, zr + 0.1)), (0.34, 0.44, 0.2), "hull2", bevel=0.2)
    p.box(V((0.5, 0.38, zr + 0.11)), (0.2, 0.02, 0.09), "window", bevel=0.0)
    p.tube(V((0.75, -0.95, zr)), V((0.8, -1.2, zr + 1.1)), 0.02, 0.01, "dark", segs=4)
    # rangefinder ears
    for sx in (-1, 1):
        c = V((sx * 1.38, -0.2, 0.86))
        p.box(c, (0.26, 0.9, 0.34), "hull2", bevel=0.2)
        p.box(c + V((0, 0.46, 0)), (0.15, 0.03, 0.17), "window", bevel=0.0)
        p.box(c + V((0, -0.2, 0.19)), (0.2, 0.3, 0.05), "hazard", bevel=0.0)
    # rear bustle: ammunition hoist and vents
    p.box(V((0, -1.62, 0.66)), (1.5, 0.36, 0.56), "hull2", bevel=0.2)
    for k in range(5):
        p.box(V((-0.5 + k * 0.25, -1.81, 0.66)), (0.12, 0.03, 0.38), "dark", bevel=0.0)
    p.box(V((0, -1.62, 0.97)), (1.2, 0.2, 0.05), "hazard", bevel=0.0)
    # mantlet and guns
    p.box(V((0, 1.36, 0.7)), (1.72, 0.3, 0.58), "hull2", bevel=0.25)
    y1 = MUZZLE_Y - TURRET.y
    for sx in (-1, 1):
        x = sx * BARREL_DX
        z = BARREL_Z
        p.box(V((x, 1.75, z)), (0.56, 0.7, 0.5), "hull", bevel=0.2)            # recoil housing
        p.cyl(V((x, 2.75, z)), 0.2, 0.2, 1.5, "hull2", segs=10, axis_rot=ALONG_Y)  # sleeve
        for k in range(4):
            p.cyl(V((x, 2.2 + k * 0.38, z)), 0.235, 0.235, 0.1, "dark", segs=10,
                  axis_rot=ALONG_Y)
        p.cyl(V((x, 3.6, z)), 0.215, 0.215, 0.2, "accent", segs=10, axis_rot=ALONG_Y)
        p.cyl(V((x, (3.5 + y1) / 2, z)), 0.125, 0.11, y1 - 3.5, "metal", segs=10,
              axis_rot=ALONG_Y)
        p.cyl(V((x, 4.6, z)), 0.15, 0.15, 0.12, "dark", segs=10, axis_rot=ALONG_Y)
        # muzzle brake: slotted box
        p.box(V((x, y1 - 0.32, z)), (0.3, 0.6, 0.26), "dark", bevel=0.2)
        for k in range(3):
            p.box(V((x, y1 - 0.5 + k * 0.17, z)), (0.34, 0.05, 0.12), "metal", bevel=0.0)
        p.cyl(V((x, y1 - 0.015, z)), 0.085, 0.085, 0.03, "seam", segs=10, axis_rot=ALONG_Y)
        SCORCH.append((x, MUZZLE_Y - 0.2, TURRET.z + z, 0.5))
    p.box(V((0, 2.9, BARREL_Z)), (0.9, 0.16, 0.2), "hull2", bevel=0.0)       # barrel yokes
    p.box(V((0, 4.6, BARREL_Z)), (0.9, 0.1, 0.14), "hull2", bevel=0.0)
    return p


def build_glow():
    p = parts.Part("engine_glow", MATS)
    # Built around the bell exit plane at y = 0; the object origin is moved to NOZZLE_Y.
    for x, z in ENG:
        parts.exhaust_glow(p, BELL_R * 0.85, 1.2, "glow", x=x, z=z, segs=16)
    return p


def build_ship():
    build_materials()
    DECALS.clear()
    SCORCH.clear()
    root = parts.make_root("syndicate_gunship")
    hull = build_hull().finish(root)
    turret = build_turret().finish(root)
    glow = build_glow().finish(root)
    turret.location = TURRET
    glow.location = (0, NOZZLE_Y, 0)
    for name, sx in (("muzzle_l", -1), ("muzzle_r", 1)):
        parts.add_empty(name, root, (TURRET.x + sx * BARREL_DX, MUZZLE_Y + 0.03,
                                     TURRET.z + BARREL_Z))
    return root, hull, turret, glow


def extra_views(out_dir):
    """Debug renders into out_dir; not part of the previews."""
    os.makedirs(out_dir, exist_ok=True)
    scene = bpy.context.scene
    if scene.camera is None:   # --no-preview: set the preview scene up here
        common.setup_preview(cam_loc=(-20, 12, 22), cam_target=(0, 0, 0), ortho_scale=30.0,
                             res=(1600, 1200), key_dir=(-0.5, 0.4, 0.75), key_energy=3.5)
    cam = scene.camera
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1200
    views = (("bow", (-9, 17, 8), (0, 5.0, 0.6), 11.0),
             ("mid", (-12, 3, 11), (0, -1.5, 1.0), 11.0),
             ("rear", (-10, -18, 8), (0, -6, 0.3), 12.0),
             ("belly", (-11, 9, -10), (0, 0, -0.8), 21.0),
             ("side", (-30, 0, 0), (0, 0, 0.3), 21.0),
             ("front", (5, 22, 3), (0, 6, 0), 10.0),
             ("rts", (-7, -15, 32), (0, 0, 0), 30.0))
    for name, loc, tgt, ortho in views:
        cam.location = loc
        cam.rotation_euler = (V(tgt) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        cam.data.ortho_scale = ortho
        common.render(os.path.join(out_dir, f"syn_{name}.png"))


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, hull, turret, glow = build_ship()
    bpy.context.view_layer.update()
    if "--no-textures" not in argv:
        glow.hide_render = True
        wk.texture([hull, turret], MATS, PRE, [(0.0, 0.0)], scorch=SCORCH, decals=DECALS,
                   labels=LABELS, seed0=221, res=2048)
        glow.hide_render = False
    else:
        for o in (hull, turret):
            o.data.uv_layers.remove(o.data.uv_layers["panel"])
    wk.stats([hull, turret, glow])
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews(PRE, 22.0, target=(0, -0.3, 0))
    extra = [a.split("=", 1)[1] for a in argv if a.startswith("--extra=")]
    if extra:
        extra_views(extra[0])


if __name__ == "__main__":
    main()
