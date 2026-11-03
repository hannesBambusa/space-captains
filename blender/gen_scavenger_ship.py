"""Generate the scavenger raider .glb and previews (3/4 and top-down).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python blender/gen_scavenger_ship.py
  Options after `--`: --no-preview, --no-textures (flat materials, no Cycles bake).
Textures: one 2048 worn atlas (worn_kit / station_textures.WORN_KINDS plus a local
"olive" kind), saved as blender/textures/scavenger_*.jpg and embedded as JPEG.

Design: a salvaged belter hauler turned raider. Arrowhead silhouette from above: a
narrow armoured ram prow with plough plates, teeth and three forward spikes, glowing red
visor slits in its face; a long chamfered hull of mismatched olive / rust / scrap plates
with an open-rib waist (bare frames over a dark core with pipes); a rust-red cargo
container welded to the starboard flank and caged propellant spheres on the port flank;
two bolted-on engine pods on pylons flanking one big salvaged main bell; antenna mast
cluster, cables, welded patch plates, red running lights. A twin autocannon turret sits
on the fore deck with the barrels running out along the prow.

Layout (Blender Z up, exported +Y up). Ship centre near origin on the play plane z=0.
The nose points along Blender +Y, which the exporter turns into Godot -Z (forward).
  engines  bell exits y = NOZZLE_Y (-7.0): main bell x = 0, pods x = +-POD_X
  aft hull y -5.6..-3.2, rib waist y -3.2..-1.0, fore hull y -1.0..3.0,
  prow y 3.0..5.9 (+ spikes / teeth to ~6.6), container x 1.5..2.8 at y -1.0..2.2
  turret ring at GUN (y 1.3, deck z 1.1), muzzles y = MUZZLE_Y (6.1)
Hierarchy: scavenger (empty root) -> scav_hull, scav_rig, engine_glow,
  muzzle_l (empty), muzzle_r (empty).
engine_glow has its origin on the bell exit plane (Blender y = NOZZLE_Y, x = ENG_X) and
its plumes (main + two pods, all exits on that plane) extend along Godot local +Z, so
scaling it on Z lengthens the glow backwards. Muzzle empties are unrotated, so their
Godot -Z points forward along the barrels.
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
from parts import ALONG_Y, V, oct_ring, rot  # noqa: E402

PRE = "scavenger"
OUT = os.path.join(common.ROOT, "assets", "models", "ships", "scavenger.glb")
BLEND = os.path.join(common.ROOT, "blender", "scavenger.blend")
ENG_X = 0.0
NOZZLE_Y = -7.0
MAIN_R, MAIN_LEN = 0.95, 1.4
POD_X, POD_Z, POD_R = 2.6, -0.15, 0.62
POD_BELL_R, POD_BELL_LEN = 0.52, 0.85
POD_Y0, POD_Y1 = NOZZLE_Y + POD_BELL_LEN, -2.3
HULL_W, HULL_H = 3.0, 2.2
DECK_Z = HULL_H / 2
RIB_Y0, RIB_Y1 = -3.2, -1.0
CONT_POS, CONT_SIZE = V((2.15, 0.6, -0.05)), (1.3, 3.2, 1.55)
TANK_POS = V((-2.2, 0.4, -0.1))
GUN = V((0.0, 1.3, DECK_Z))
BARREL_Z = DECK_Z + 0.62
BARREL_DX = 0.27
MUZZLE_Y = 6.1

MATS = {}
SCORCH = [(0.0, -5.6, 0.0, 1.6), (POD_X, -6.0, POD_Z, 1.0), (-POD_X, -6.0, POD_Z, 1.0),
          (0.0, 5.6, -0.2, 1.2)]

# Olive drab paint over rust: local worn kind (adds to this process's WORN_KINDS only).
OLIVE = dict(big=(2.2, 1.6), plate=(1.1, 0.8),
             tones=[(0.105, 0.115, 0.05), (0.09, 0.10, 0.045), (0.12, 0.125, 0.06),
                    (0.08, 0.085, 0.045), (0.115, 0.11, 0.055), (0.095, 0.105, 0.06)],
             plate_var=0.18, rough=(0.78, 0.12), metal=0.15, seam_big=0.35,
             seam_small=0.18, rivets=True, hatches=0.0, chip=(0.16, 0.075, 0.035),
             chip_metal=0.4, chip_k=1.6, grime_k=1.3, streak_k=0.6, bleach=0.15)
# Mismatched salvage plates in the raider palette (worn_kit "scrap" has teal and white).
JUNK = dict(big=(1.2, 0.9), plate=(0.6, 0.45),
            tones=[(0.22, 0.09, 0.04), (0.11, 0.12, 0.06), (0.17, 0.15, 0.12),
                   (0.08, 0.075, 0.07), (0.20, 0.14, 0.05), (0.14, 0.065, 0.035)],
            plate_var=0.22, rough=(0.72, 0.18), metal=0.3, seam_big=0.4,
            seam_small=0.2, rivets=True, hatches=0.0, chip=(0.24, 0.22, 0.2),
            chip_metal=0.85, chip_k=1.7, grime_k=1.3, streak_k=0.5, bleach=0.1)
st.WORN_KINDS.setdefault("olive", OLIVE)
st.WORN_KINDS.setdefault("junk", JUNK)


def build_materials():
    m = common.make_material
    MATS.clear()
    MATS["olive"] = m("scav_plate_olive", (0.10, 0.11, 0.05), roughness=0.8, metallic=0.2)
    MATS["rust"] = m("scav_hull_rust", (0.15, 0.065, 0.03), roughness=0.85, metallic=0.3)
    MATS["junk"] = m("scav_plate_scrap", (0.13, 0.115, 0.095), roughness=0.75, metallic=0.4)
    MATS["accent"] = m("scav_container_paint", (0.30, 0.075, 0.025), roughness=0.75,
                       metallic=0.25)
    MATS["hull3"] = m("scav_plate_grey", (0.2, 0.19, 0.17), roughness=0.6)
    MATS["dark"] = m("scav_frame_dark", (0.045, 0.04, 0.035), roughness=0.6, metallic=0.6)
    MATS["metal"] = m("scav_bare_metal", (0.3, 0.3, 0.31), roughness=0.4, metallic=0.9)
    MATS["hazard"] = m("scav_hazard", (0.45, 0.30, 0.03), roughness=0.7, metallic=0.2)
    glow = (0.03, 0.02, 0.015)
    MATS["window"] = m("scav_window_red", glow, roughness=0.3,
                       emission=(1.0, 0.22, 0.05), emission_strength=4.0)
    MATS["light"] = m("scav_light_red", glow, roughness=0.3,
                      emission=(1.0, 0.06, 0.02), emission_strength=6.0)
    MATS["glow"] = m("scav_engine_glow", (1.0, 0.3, 0.08), roughness=0.2,
                     emission=(1.0, 0.2, 0.035), emission_strength=5.0)
    MATS["glass"] = m("scav_glass_dark", (0.012, 0.01, 0.01), roughness=0.1)
    for k in ("window", "light", "glow", "glass"):
        MATS[k].use_backface_culling = False


# ---------------------------------------------------------------- small shapes
def cable(p, a, b, sag, r=0.06, n=6, mat="dark"):
    """Sagging cable as a chain of open pipes (sag along -Z)."""
    pts = []
    for k in range(n + 1):
        t = k / n
        q = a.lerp(b, t)
        q.z -= sag * 4 * t * (1 - t)
        pts.append(q)
    for q0, q1 in zip(pts, pts[1:]):
        parts.pipe(p, q0, q1, r, mat, segs=5)


def frame(c, normal, up):
    """4x4 frame at c: local X across, local Y = up, local Z = normal."""
    n = V(normal).normalized()
    u = (V(up) - n * V(up).dot(n)).normalized()
    r = u.cross(n)
    return Matrix.Translation(c) @ Matrix((r, u, n)).transposed().to_4x4()


def ragged_plate(p, c, normal, up, w, h, t, rng, mat, cut=0.35, spin=0.06):
    """Welded armour plate with irregular corner cuts, lying on a face (normal out).
    The slab runs from -t/2 to +t/2 around c along the normal."""
    m = frame(c, normal, up) @ Matrix.Rotation(rng.uniform(-spin, spin), 4, "Z")
    hw, hh = w / 2, h / 2
    pts = []
    for sx, sy in ((1, -1), (1, 1), (-1, 1), (-1, -1)):
        a = rng.uniform(0.05, cut) * min(w, h)
        b = rng.uniform(0.05, cut) * min(w, h)
        # corner (sx*hw, sy*hh) replaced by two cut points, kept in CCW order
        if sx * sy > 0:
            pts += [(sx * hw, sy * (hh - a)), (sx * (hw - b), sy * hh)]
        else:
            pts += [(sx * (hw - b), sy * hh), (sx * hw, sy * (hh - a))]
    # CCW check: the order above walks +x side up, top leftwards, -x side down, bottom
    p.slab(pts, -t / 2, t / 2, mat, matrix=m)


def spike(p, base, tip, r, mat="metal", segs=5):
    p.tube(base, tip, r, 0.015, mat, segs=segs)


def bolts(p, a, b, n, s=0.09, mat="dark", nrm=V((0, 0, 1))):
    for k in range(n):
        c = a.lerp(b, (k + 0.5) / n)
        p.box(c + nrm * s * 0.3, (s, s, s), mat, bevel=0.0)


def rib_frame(p, y, w, h, c, mat, bar=0.2, depth=0.22, z0=0.0):
    """Open chamfered ring frame (8 beams) around the hull axis at y."""
    ring = oct_ring(y, w, h, c, z0=z0)
    for i in range(8):
        a, b = ring[i], ring[(i + 1) % 8]
        mid = (a + b) / 2
        out = V((mid.x, 0, mid.z - z0)).normalized()
        ext = (b - a).normalized() * bar * 0.5
        p.beam(a - ext, b + ext, depth, bar, mat, up=out)


# ---------------------------------------------------------------- hull
def olive_rust(i, j):
    return "olive" if j in (1, 2, 3) else ("rust" if j in (0, 4) else "junk")


def build_hull(rng):
    p = parts.PanelPart("scav_hull", MATS)
    W, H = HULL_W, HULL_H
    # --- aft hull block (engine room), slight taper into the thrust plate
    p.loft([oct_ring(-5.6, 2.3, 1.8, 0.5), oct_ring(-5.0, 2.8, 2.1, 0.6),
            oct_ring(-4.4, W, H, 0.62), oct_ring(RIB_Y0, W, H, 0.62)], "rust",
           mat_fn=lambda i, j: "dark" if i == 0 else ("olive" if j in (2,) else "rust"))
    # --- rib waist: dark core, bare frames, pipes and stringers
    parts.prism(p, RIB_Y0 - 0.05, RIB_Y1 + 0.05, (1.7, 1.35, 0.35), (1.7, 1.35, 0.35), "dark")
    for k in range(5):
        y = RIB_Y0 + 0.12 + k * (RIB_Y1 - RIB_Y0 - 0.24) / 4
        rib_frame(p, y, W - 0.08, H - 0.08, 0.6, "rust" if k % 2 else "olive", bar=0.2,
                  depth=0.24)
    for x, z in ((1.25, 0.75), (-1.25, 0.75), (1.25, -0.75), (-1.25, -0.75)):
        p.beam(V((x, RIB_Y0, z)), V((x, RIB_Y1, z)), 0.16, 0.16, "dark")
    for x, z, r in ((0.55, 0.62, 0.11), (0.25, 0.68, 0.08), (-0.6, 0.6, 0.13),
                    (0.95, 0.0, 0.1), (-0.95, -0.2, 0.12), (0.9, -0.35, 0.07)):
        p.cyl(V((x, (RIB_Y0 + RIB_Y1) / 2, z)), r, r, RIB_Y1 - RIB_Y0, "metal", segs=6,
              axis_rot=ALONG_Y)
    # top spine plate bridging the ribs (kept partly open on the port side)
    p.box(V((0.35, -2.1, DECK_Z - 0.02)), (1.0, 2.3, 0.1), "junk", r=rot(rz=0.04), bevel=0.0)
    # --- fore hull, then the ram prow
    p.loft([oct_ring(RIB_Y1, W, H, 0.62), oct_ring(1.6, W, H, 0.62),
            oct_ring(3.0, 2.8, 2.0, 0.6)], "olive", mat_fn=olive_rust)
    prow = [oct_ring(3.0, 2.8, 2.0, 0.6), oct_ring(4.4, 2.2, 1.45, 0.5, z0=-0.12),
            oct_ring(5.5, 1.1, 0.75, 0.25, z0=-0.3), oct_ring(5.95, 0.55, 0.4, 0.12, z0=-0.36)]
    p.loft(prow, "rust", mat_fn=lambda i, j: "olive" if (j == 2 and i == 0) else "rust")
    # red visor slits on the prow's upper chamfers (the crew looks out through the ram)
    r0, r1 = prow[0], prow[1]
    for sx, (ia, ib) in ((1, (1, 2)), (-1, (3, 4))):
        e0 = (r0[ia] + r0[ib]) / 2
        e1 = (r1[ia] + r1[ib]) / 2
        along = (e1 - e0).normalized()
        n = along.cross(r0[ib] - r0[ia]).normalized()
        if n.x * sx < 0:
            n = -n
        for k in range(3):
            c = e0.lerp(e1, 0.28 + k * 0.2)
            parts.quad(p, c + n * 0.035, n, along, 0.5, 0.11, "glass")
            parts.quad(p, c + n * 0.06, n, along, 0.42, 0.07, "window")
    # plough blades: a V-shaped cowcatcher flaring out from the prow, ending in teeth
    for sx in (-1, 1):
        a = V((sx * 1.85, 2.3, -0.2))
        b = V((sx * 0.45, 6.25, -0.5))
        d = (b - a)
        ln = d.length
        # blade plane: contains d, tilted 35 deg outward from vertical
        side = V((sx, 0, 0))
        out = (side - d.normalized() * side.dot(d.normalized())).normalized()
        up = V((0, 0, 1))
        nrm = (out * math.cos(0.6) + up * math.sin(0.6)).normalized()
        m = frame((a + b) / 2, nrm, d)  # local Y = along the blade (front = +Y)
        pts = [(-0.75, -ln / 2), (0.1, -ln / 2 - 0.1), (0.45, -ln / 2 + 0.6), (0.3, ln / 2),
               (-0.15, ln / 2 + 0.1)]
        p.slab([(x * sx, y) for x, y in pts], -0.06, 0.06,
               "junk" if sx > 0 else "rust", matrix=m)
        for k in range(5):  # teeth along the outer edge of the blade
            t = 0.25 + k * 0.16
            q = a.lerp(b, t) + out * 0.25 - nrm * 0.05
            spike(p, q, q + out * 0.35 + d.normalized() * 0.45, 0.08, "metal")
        bolts(p, a.lerp(b, 0.1) + nrm * 0.03, a.lerp(b, 0.85) + nrm * 0.03, 7, 0.08, "dark",
              nrm=nrm)
        p.beam(a + V((-sx * 0.3, 0.2, 0.0)), V((sx * 1.3, 2.6, 0.1)), 0.18, 0.18, "dark")
    # forward ram spikes off the prow face
    for x, z, ln in ((0.0, -0.36, 0.7), (-0.32, -0.15, 0.45), (0.32, -0.15, 0.45)):
        spike(p, V((x, 5.85, z)), V((x * 1.2, 5.9 + ln, z - 0.02)), 0.11, "metal", segs=6)
    p.box(V((0, 5.92, -0.36)), (0.7, 0.14, 0.42), "dark", bevel=0.1)
    # --- welded armour plates: sides and deck, mismatched
    for sx in (-1, 1):
        for y, w, h in ((-0.3, 1.5, 1.1), (1.1, 1.3, 1.0), (2.3, 1.0, 0.9),
                        (-4.0, 1.2, 1.0)):
            if sx > 0 and -1.0 < y < 2.2:
                continue  # the container covers the starboard fore flank
            ragged_plate(p, V((sx * (W / 2 + 0.04), y + rng.uniform(-0.1, 0.1),
                               rng.uniform(-0.25, 0.15))), V((sx, 0, 0)), V((0, 0, 1)),
                         w, h, 0.08, rng, rng.choice(["junk", "olive", "hull3", "rust"]))
    for y, x, w, ln in ((-0.2, -0.75, 1.0, 1.3), (2.35, 0.5, 1.1, 0.9), (-4.1, 0.3, 1.3, 1.1),
                        (-4.9, -0.6, 0.8, 0.6), (0.4, 0.75, 0.6, 0.7)):
        ragged_plate(p, V((x, y, DECK_Z + 0.035)), V((0, 0, 1)), V((0, 1, 0)), w, ln, 0.07, rng,
                     rng.choice(["junk", "hull3", "rust", "olive"]))
    # weld-bead strips and bolt rows along the deck edges
    for sx in (-1, 1):
        p.beam(V((sx * 1.18, RIB_Y1, DECK_Z + 0.02)), V((sx * 1.12, 3.0, DECK_Z - 0.02)), 0.12,
               0.08, "dark")
        bolts(p, V((sx * 1.18, -4.6, DECK_Z)), V((sx * 1.18, -3.3, DECK_Z)), 5, 0.08)
    # ventral keel plate + belly greebles
    p.box(V((0, -1.0, -DECK_Z - 0.06)), (1.2, 7.2, 0.14), "rust", bevel=0.2)
    for y in (-4.2, -2.4, 0.4, 2.0):
        p.box(V((rng.uniform(-0.5, 0.5), y, -DECK_Z - 0.18)), (0.5, 0.7, 0.18), "dark", bevel=0.1)
    # hazard band round the aft hull, hatch, vents
    p.box(V((0, -3.45, DECK_Z + 0.01)), (2.0, 0.28, 0.06), "hazard", bevel=0.0)
    p.box(V((-0.55, 1.95, DECK_Z + 0.03)), (0.75, 0.75, 0.06), "dark", bevel=0.15)
    p.box(V((-0.55, 1.95, DECK_Z + 0.07)), (0.55, 0.55, 0.05), "junk", bevel=0.1)
    for k in range(5):  # vent grille slats on the engine room top
        p.box(V((-0.05, -4.75 + k * 0.17, DECK_Z + 0.04)), (0.45, 0.07, 0.07), "dark", bevel=0.0)
    # --- starboard cargo container (welded on, strapped)
    c, (w, ln, h) = CONT_POS, CONT_SIZE
    p.box(c, CONT_SIZE, "accent", r=rot(rz=-0.03), bevel=0.04)
    for k in range(10):  # corrugation ribs on the outer side and roof
        y = -ln / 2 + 0.25 + k * (ln - 0.5) / 9
        p.box(c + V((w / 2 + 0.02, y, 0)), (0.06, 0.1, h - 0.2), "rust", bevel=0.0)
        p.box(c + V((0.1, y, h / 2 + 0.02)), (w - 0.35, 0.1, 0.05), "rust", bevel=0.0)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box(c + V((sx * w / 2, sy * ln / 2, 0)), (0.16, 0.16, h + 0.04), "dark", bevel=0.0)
    for y in (-0.9, 0.9):  # straps over the roof down onto the hull
        p.box(c + V((0, y, h / 2 + 0.05)), (w + 0.1, 0.16, 0.06), "dark", bevel=0.0)
        p.beam(c + V((-w / 2, y, h / 2)), V((W / 2 - 0.2, c.y + y, DECK_Z)), 0.16, 0.08, "dark")
    p.hazard(-w / 2 + 0.1, w / 2 - 0.1, 0.22, -0.02, 0.02,
             matrix=Matrix.Translation((c.x, c.y + ln / 2 + 0.02, c.z - 0.45)) @
             rot(rx=math.pi / 2), pitch=0.35, cols=("hazard", "dark"))
    ragged_plate(p, c + V((w / 2 + 0.07, -0.8, 0.2)), V((1, 0, 0)), V((0, 0, 1)), 1.1, 0.8,
                 0.06, rng, "olive")
    # --- port propellant spheres in a strap cage
    for cc, r in ((TANK_POS, 0.78), (TANK_POS + V((0.15, -1.55, 0.05)), 0.58)):
        p.sphere(cc, r, "olive" if r > 0.7 else "junk", segs=14, rings=8)
        p.torus(cc, r + 0.015, 0.05, "rust", segs=14, minor_segs=4, matrix=rot(ry=math.pi / 2))
        p.torus(cc, r + 0.015, 0.05, "rust", segs=14, minor_segs=4)
        p.beam(cc + V((r * 0.7, 0, 0)), V((-W / 2 + 0.05, cc.y, cc.z)), 0.16, 0.16, "dark")
        p.beam(cc + V((r * 0.5, 0, r * 0.5)), V((-W / 2 + 0.3, cc.y, DECK_Z - 0.2)), 0.1, 0.1,
               "dark")
        p.cyl(cc + V((0, 0, r + 0.05)), 0.12, 0.12, 0.18, "metal", segs=6)
    # --- engine section: thrust plate, main bell, heat rings
    p.box(V((ENG_X, -5.75, 0)), (1.9, 0.35, 1.6), "dark", bevel=0.1)
    p.cyl(V((ENG_X, -5.9, 0)), 0.72, 0.6, 0.3, "metal", segs=14, axis_rot=ALONG_Y)
    parts.bell(p, NOZZLE_Y, MAIN_R, MAIN_LEN, "junk", "dark", x=ENG_X, segs=18)
    for y, rr in ((-6.35, 0.8), (-6.8, 0.93)):
        p.torus(V((ENG_X, y, 0)), rr, 0.045, "dark", segs=18, minor_segs=4,
                matrix=rot(rx=math.pi / 2))
    for k in range(4):  # actuator rods to the bell
        a = math.pi / 4 + k * math.pi / 2
        q = V((math.cos(a), 0, math.sin(a)))
        p.tube(V((ENG_X, -5.7, 0)) + q * 0.8, V((ENG_X, -6.3, 0)) + q * 0.72, 0.05, 0.05, "metal",
               segs=5)
    # --- bolted-on engine pods on pylons
    for sx in (-1, 1):
        px = sx * POD_X
        parts.capsule(p, POD_Y0, POD_Y1, POD_R,
                      lambda i, j: "rust" if j in (0, 1) else ("junk" if i % 4 == 0 else "olive"),
                      segs=12, x=px, z=POD_Z, dome0=0.15, dome1=1.1)
        parts.bell(p, NOZZLE_Y, POD_BELL_R, POD_BELL_LEN, "junk", "dark", x=px, z=POD_Z,
                   segs=12)
        for y in (POD_Y0 + 0.35, -4.2, -3.1):  # clamp bands
            p.cyl(V((px, y, POD_Z)), POD_R + 0.05, POD_R + 0.05, 0.16, "dark", segs=12,
                  axis_rot=ALONG_Y)
        # intake / ram spike off the pod nose
        spike(p, V((px, POD_Y1 + 0.5, POD_Z)), V((px, POD_Y1 + 1.4, POD_Z)), 0.14, "metal", 6)
        # pylons: a plate and a strut truss to the hull
        hx = sx * (HULL_W / 2 - 0.1)
        wing = [(1.4, -5.35), (2.15, -5.75), (2.3, -3.2), (1.75, -2.75), (1.4, -2.65)]
        p.slab([(sx * x, y) for x, y in wing], 0.14, 0.3, "rust")
        for k in range(4):  # stiffener ribs on the wing plate
            y = -5.1 + k * 0.6
            p.box(V((sx * 1.85, y, 0.33)), (0.75, 0.08, 0.08), "dark", bevel=0.0)
        ragged_plate(p, V((sx * 1.8, -4.1, 0.33)), V((0, 0, 1)), V((0, 1, 0)), 0.6, 0.9, 0.05,
                     rng, "junk" if sx > 0 else "olive")
        p.beam(V((hx, -3.3, 0.1)), V((px, -3.6, POD_Z + 0.1)), 0.3, 0.16, "dark")
        parts.strut(p, V((hx, -3.4, -0.5)), V((px, -4.4, POD_Z - 0.3)), 0.12, 0.12, "dark")
        parts.strut(p, V((hx, -4.8, -0.5)), V((px, -3.7, POD_Z - 0.3)), 0.12, 0.12, "dark")
        # side spikes on the pod outer flank (menace, also debris breakers)
        for y in (-5.2, -4.0, -2.9):
            b = V((px + sx * POD_R * 0.9, y, POD_Z + 0.15))
            spike(p, b, b + V((sx * 0.55, 0.35, 0.12)), 0.08, "metal")
        # top patch plate and light
        ragged_plate(p, V((px, -4.6, POD_Z + POD_R + 0.02)), V((0, 0, 1)), V((0, 1, 0)), 0.7,
                     1.2, 0.05, rng, "junk")
        p.box(V((px + sx * 0.3, -3.0, POD_Z + 0.55)), (0.14, 0.14, 0.14), "light",
              bevel=0.0)
    # --- ragged dorsal fin on the engine room (shark fin out of a hull offcut), lit tip
    fin = [(-1.4, 0.0), (0.6, 0.0), (0.25, 0.55), (-0.55, 1.25), (-0.9, 1.3), (-1.2, 0.7)]
    fm = Matrix.Translation((0.62, -4.5, DECK_Z)) @ Matrix(((0, 0, 1, 0), (1, 0, 0, 0),
                                                            (0, 1, 0, 0), (0, 0, 0, 1)))
    p.slab(fin, -0.06, 0.06, "rust", matrix=fm)
    p.box(V((0.62, -4.45, DECK_Z + 0.04)), (0.26, 2.1, 0.1), "dark", bevel=0.0)
    for k in range(3):
        p.box(V((0.62, -5.2 + k * 0.5, DECK_Z + 0.35)), (0.16, 0.08, 0.5), "dark", bevel=0.0)
    p.box(V((0.62, -5.4, DECK_Z + 1.32)), (0.1, 0.1, 0.1), "light", bevel=0.0)
    # --- antenna cluster on the engine room roof, red tip lights
    base = V((-0.75, -4.35, DECK_Z + 0.05))
    p.box(base, (0.55, 0.55, 0.18), "dark", bevel=0.15)
    for dx, dy, hgt, r in ((0.0, 0.0, 1.5, 0.045), (0.18, 0.12, 1.0, 0.035),
                           (-0.15, 0.15, 0.75, 0.035), (0.12, -0.18, 1.2, 0.03)):
        top = base + V((dx, dy - hgt * 0.15, hgt))
        p.tube(base + V((dx, dy, 0.05)), top, r, r * 0.6, "metal", segs=5)
        if hgt > 0.9:
            p.box(top, (0.12, 0.12, 0.12), "light", bevel=0.0)
    parts.dish(p, V((0.85, -2.0, DECK_Z + 0.25)), 0.38, (0.3, -0.4, 1.0), "junk", "dark",
               depth=0.14, segs=10)
    p.cyl(V((0.85, -2.0, DECK_Z + 0.1)), 0.06, 0.06, 0.25, "dark", segs=6)
    # --- port flank pipe run and exhaust stubs (starboard is the container)
    for z, r in ((-0.15, 0.09), (-0.4, 0.07)):
        x = -W / 2 - 0.12
        parts.pipe(p, V((x, -4.6, z)), V((x, -1.35, z)), r, "metal", segs=6)
        parts.pipe(p, V((x, 1.15, z)), V((x, 2.8, z)), r, "metal", segs=6)
        for y in (-4.2, -2.9, -1.6, 1.5, 2.5):
            p.box(V((x + 0.05, y, z)), (0.12, 0.1, r * 3), "dark", bevel=0.0)
    for y in (-4.9, -4.4):
        p.cyl(V((-W / 2 + 0.25, y, DECK_Z + 0.25)), 0.11, 0.13, 0.45, "dark", segs=6)
    # --- grapple claws under the prow (they drag salvage in)
    for sx in (-1, 1):
        a = V((sx * 0.45, 3.4, -0.95))
        b = V((sx * 0.55, 5.0, -1.15))
        c = V((sx * 0.2, 5.75, -0.95))
        p.beam(a, b, 0.2, 0.22, "dark")
        p.beam(b, c, 0.16, 0.18, "metal")
        spike(p, c, c + V((-sx * 0.15, 0.25, 0.15)), 0.08, "metal")
        p.cyl(b, 0.16, 0.16, 0.3, "rust", segs=8, axis_rot=parts.ALONG_X)
    p.box(V((0, 3.3, -0.95)), (1.2, 0.5, 0.3), "rust", bevel=0.15)
    # --- cables and RCS
    cable(p, V((-0.9, -3.0, DECK_Z + 0.15)), V((-0.6, -1.1, DECK_Z + 0.15)), 0.35)
    cable(p, V((0.4, -3.1, DECK_Z + 0.1)), V((1.0, -1.2, DECK_Z + 0.05)), 0.25, r=0.05)
    cable(p, V((W / 2, -2.2, -0.3)), V((CONT_POS.x - 0.5, -1.0, -0.5)), 0.3, r=0.07)
    parts.rcs_quad(p, V((-W / 2 + 0.2, 2.6, DECK_Z - 0.2)), (-1, 0, 1), "rust", "dark", s=0.26)
    parts.rcs_quad(p, V((W / 2 - 0.2, -4.6, DECK_Z - 0.2)), (1, 0, 1), "olive", "dark", s=0.26)
    # --- red running lights
    for pos in (V((-W / 2 - 0.06, 2.0, 0.3)), V((CONT_POS.x + 0.66, CONT_POS.y + 1.55, 0.6)),
                V((-0.45, 5.6, 0.05)), V((0.45, 5.6, 0.05))):
        p.box(pos, (0.15, 0.15, 0.15), "light", bevel=0.0)
    return p


# ---------------------------------------------------------------- turret
def build_rig(rng):
    """Twin autocannon on a turret ring on the fore deck, barrels out along the prow."""
    p = parts.PanelPart("scav_rig", MATS)
    g = GUN
    p.cyl(g + V((0, 0, 0.08)), 0.85, 0.9, 0.16, "dark", segs=16)
    p.cyl(g + V((0, 0, 0.2)), 0.72, 0.78, 0.12, "metal", segs=16)
    # turret body: chamfered wedge, sloped front
    p.loft([oct_ring(g.y - 0.8, 1.35, 0.55, 0.15, z0=g.z + 0.5),
            oct_ring(g.y + 0.25, 1.45, 0.7, 0.2, z0=g.z + 0.56),
            oct_ring(g.y + 0.75, 1.0, 0.45, 0.12, z0=g.z + 0.56)], "olive",
           mat_fn=lambda i, j: "rust" if j in (0, 4) else "olive")
    # mantlet plate and barrel housings
    p.box(V((g.x, g.y + 0.8, BARREL_Z)), (0.95, 0.12, 0.5), "junk", bevel=0.12)
    ammo = V((g.x + 0.8, g.y - 0.25, g.z + 0.45))
    p.box(ammo, (0.38, 0.75, 0.42), "accent", bevel=0.08)  # ammo drum box
    p.box(ammo + V((0.2, 0, 0)), (0.04, 0.5, 0.25), "hazard", bevel=0.0)
    cable(p, ammo + V((-0.1, 0.35, 0.15)), V((g.x + 0.3, g.y + 0.75, BARREL_Z + 0.1)), 0.12,
          r=0.05, n=5)
    p.box(V((g.x - 0.45, g.y - 0.1, g.z + 0.93)), (0.28, 0.45, 0.22), "dark", bevel=0.1)  # sight
    p.box(V((g.x - 0.45, g.y + 0.13, g.z + 0.95)), (0.12, 0.03, 0.06), "light", bevel=0.0)
    ragged_plate(p, V((g.x + 0.15, g.y - 0.35, g.z + 0.87)), V((0, 0, 1)), V((0, 1, 0)), 0.7,
                 0.6, 0.05, rng, "junk")
    y0 = g.y + 0.86
    for sx in (-1, 1):
        x = g.x + sx * BARREL_DX
        p.cyl(V((x, y0 + 0.6, BARREL_Z)), 0.17, 0.17, 1.2, "olive", segs=8, axis_rot=ALONG_Y)
        for k in range(4):  # cooling jacket rings
            p.cyl(V((x, y0 + 0.12 + k * 0.32, BARREL_Z)), 0.2, 0.2, 0.08, "dark", segs=8,
                  axis_rot=ALONG_Y)
        p.cyl(V((x, (y0 + MUZZLE_Y) / 2, BARREL_Z)), 0.1, 0.1, MUZZLE_Y - y0, "metal",
              segs=8, axis_rot=ALONG_Y)
        p.cyl(V((x, MUZZLE_Y - 0.18, BARREL_Z)), 0.14, 0.14, 0.36, "dark", segs=6,
              axis_rot=ALONG_Y)  # muzzle brake
        for k in range(2):
            p.box(V((x, MUZZLE_Y - 0.25 + k * 0.15, BARREL_Z)), (0.32, 0.05, 0.08), "dark",
                  bevel=0.0)
    for yy in (y0 + 1.6, y0 + 3.0):  # barrel clamps
        p.box(V((g.x, yy, BARREL_Z)), (0.72, 0.14, 0.24), "rust", bevel=0.0)
    return p


def build_glow(rng):
    p = parts.Part("engine_glow", MATS)
    # Built around the bell exit plane at y = 0; the object origin is moved to NOZZLE_Y.
    parts.exhaust_glow(p, MAIN_R * 0.85, 1.0, "glow", segs=16)
    for sx in (-1, 1):
        parts.exhaust_glow(p, POD_BELL_R * 0.85, 0.7, "glow", x=sx * POD_X - ENG_X, z=POD_Z,
                           segs=12)
    return p


def build_ship():
    rng = random.Random(6613)
    build_materials()
    root = parts.make_root("scavenger")
    objs = [b(rng).finish(root) for b in (build_hull, build_rig, build_glow)]
    objs[-1].location = (ENG_X, NOZZLE_Y, 0)
    for name, sx in (("muzzle_l", -1), ("muzzle_r", 1)):
        parts.add_empty(name, root, (GUN.x + sx * BARREL_DX, MUZZLE_Y + 0.03, BARREL_Z))
    return root, objs


def main():
    argv = parts.script_args(sys.argv)
    common.reset_scene()
    root, objs = build_ship()
    if "--no-textures" not in argv:
        wk.texture(objs[:2], MATS, PRE, [(0.0, 0.0)], scorch=SCORCH, seed0=41, res=2048)
    wk.stats(objs)
    wk.save_and_export(root, BLEND, OUT)
    if "--no-preview" not in argv:
        parts.ship_previews("scavenger", 16.0, target=(0, -0.3, 0))


if __name__ == "__main__":
    main()
