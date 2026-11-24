# OmaWay's arrow (sheet 112, "Soul well", approved 2026-11-17): a cast-gold arrowhead around a swirling soul well.
# Painted as pixels, not vectors: gold bevel lit from the top-left, grime, glints, rivets, hard black outline.
# Fully procedural (no game art inside). Writes Art/arrow_{on,off}.tga (256) and Art/arrow_{on,off}_s.tga (128,
# a simpler cut for small sizes: no stars, brighter core, thicker frame), uncompressed 32-bit TGA for WoW.
#   python art/omaway/paint_arrow.py addons/OmaWay/Art
import sys, os, numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as nd

OUT = sys.argv[1] if len(sys.argv) > 1 else '.'
S = 512
rng = np.random.default_rng(7)
yy, xx = np.mgrid[0:S, 0:S]

def poly_mask(pts):
    im = Image.new('L', (S, S), 0); ImageDraw.Draw(im).polygon(pts, fill=255); return np.asarray(im) > 127

def shape(scale=1.0):
    c = S / 2
    P = [(0, -205), (38, -110), (80, -20), (150, 120), (158, 150), (128, 150), (0, 78), (-128, 150), (-158, 150),
         (-150, 120), (-80, -20), (-38, -110)]
    return [(c + x * scale, c + 20 + y * scale) for x, y in P]

def noise(scale, seed):
    r = np.random.default_rng(seed).random((S // scale + 2, S // scale + 2))
    im = Image.fromarray((r * 255).astype(np.uint8)).resize((S + 2 * scale, S + 2 * scale), Image.BICUBIC)
    return np.asarray(im)[scale:scale + S, scale:scale + S] / 255.0

def ramp(t, pal):
    pal = np.array(pal, float)
    t = np.clip(t, 0, 1) * (len(pal) - 1); i = np.clip(np.floor(t).astype(int), 0, len(pal) - 2); f = (t - i)[..., None]
    return pal[i] * (1 - f) + pal[i + 1] * f

GOLD = [[34, 20, 6], [96, 60, 16], [170, 116, 34], [226, 176, 70], [255, 236, 170], [255, 252, 232]]

def paint(small, hue):
    outer = poly_mask(shape(1.0))
    ring_w = 34 if small else 26
    inner = nd.binary_erosion(outer, iterations=ring_w)
    rim = outer & ~inner
    pnt = 0.5 * noise(4, 1) + 0.3 * noise(12, 2) + 0.2 * noise(40, 3)
    streak = nd.gaussian_filter(rng.random((S, S)), (0.6, 7)); streak = (streak - streak.min()) / (streak.max() - streak.min())
    d_out = nd.distance_transform_edt(outer); d_in = nd.distance_transform_edt(~inner)
    h = np.sin(np.clip(np.minimum(d_out, d_in) / (ring_w / 2), 0, 1) * np.pi / 2)
    hs = nd.gaussian_filter(h, 1.6); gy, gx = np.gradient(hs)
    L = np.array([-0.65, -0.75]); L /= np.linalg.norm(L)
    lam = np.clip(-(gx * L[0] + gy * L[1]) * 14, -1, 1)
    shade = (0.48 + 0.62 * lam + 0.35 * (hs - 0.5)) * (0.82 + 0.3 * pnt) * (0.9 + 0.18 * streak)
    gold = ramp(shade * 0.92, GOLD)
    grime = np.clip(1 - d_in / 7.0, 0, 1) * rim
    gold *= (1 - 0.55 * grime)[..., None]
    glint = (d_out > 0) & (d_out < 3.5) & rim & (lam > 0.35)
    gold[glint] = gold[glint] * 0.4 + np.array([255, 248, 220]) * 0.6
    lip = (d_in > 0) & (d_in < 2.5) & rim & (lam < -0.2)
    gold[lip] = gold[lip] * 0.5 + np.array([255, 214, 120]) * 0.5

    # the soul well: a swirl around the body's centre, deep violet (or red when you're facing away)
    cy, cx = nd.center_of_mass(inner)
    dx, dy = (xx - cx) / 120.0, (yy - (cy + 10)) / 120.0
    r = np.sqrt(dx * dx + dy * dy) + 1e-6; th = np.arctan2(dy, dx)
    sw = th + 3.2 * np.log(r + 0.08)
    smooth = nd.gaussian_filter(pnt, 5 if small else 3)
    n1 = 0.5 + 0.5 * np.sin(sw * 3 + 1.7 * smooth * 6)
    n2 = 0.5 + 0.5 * np.sin(sw * 5 - r * 7)
    v = (0.6 * n1 + 0.4 * n2) * np.clip(1.25 - r, 0, 1) ** 1.4
    core = np.clip(1 - r / (0.3 if small else 0.22), 0, 1) ** 2
    WELL = {'on': [[4, 2, 10], [30, 10, 60], [92, 30, 150], [176, 90, 240], [236, 196, 255], [255, 255, 255]],
            'off': [[10, 2, 2], [60, 8, 6], [150, 30, 20], [240, 90, 60], [255, 200, 180], [255, 255, 255]]}[hue]
    STONE = [[6, 4, 10], [20, 14, 30], [44, 32, 62], [82, 62, 112]]
    light = np.clip(1.15 - (yy / S) * 0.9 - (xx / S) * 0.25, 0, 1.2)
    stone = ramp(np.clip((0.6 * pnt + 0.4 * streak) * 0.55 * light, 0, 1), STONE)
    edge_dark = np.clip(nd.distance_transform_edt(inner) / 26.0, 0, 1)[..., None]
    body = stone * 0.25 + ramp(np.clip(v * 0.75 + core * (1.1 if small else 0.9), 0, 1), WELL) * edge_dark * 0.95
    if not small:
        stars = nd.binary_dilation((np.random.default_rng(3).random((S, S)) > 0.9988) & inner & (r > 0.25), iterations=1)
        body[stars] = [255, 240, 255] if hue == 'on' else [255, 230, 220]
    glow_rgb = [190, 110, 255] if hue == 'on' else [255, 90, 60]
    aura_rgb = [120, 50, 230] if hue == 'on' else [230, 50, 30]

    rgb = np.zeros((S, S, 3)); rgb[rim] = gold[rim]; rgb[inner] = body[inner]
    spill = nd.gaussian_filter((np.clip(v * 0.8 + core, 0, 1) * inner), 10) * rim
    rgb = rgb + np.clip(spill, 0, 1)[..., None] * np.array(glow_rgb) * 0.8
    c = S / 2
    for rx, ry in [(c - 112, c + 150), (c + 112, c + 150), (c, c - 132)]:
        m = (xx - rx) ** 2 + (yy - ry) ** 2 < 81
        sh = np.clip(1 - np.sqrt(((xx - rx + 3) ** 2 + (yy - ry + 3) ** 2)) / 9, 0, 1)
        rgb[m] = ramp(0.25 + 0.75 * sh, GOLD)[m]
    ol = nd.binary_dilation(outer, iterations=9 if small else 7) & ~outer
    shadow = np.clip(nd.gaussian_filter(nd.shift(outer.astype(float), (10, 6), order=0), 8) * 0.75, 0, 1)
    aura = np.clip(nd.gaussian_filter(outer.astype(float), 28) * 1.1, 0, 1)
    out = np.zeros((S, S, 4)); out[..., :3] = np.array(aura_rgb); out[..., 3] = aura * 0.5
    out[..., :3] *= (1 - shadow[..., None]); out[..., 3] = np.maximum(out[..., 3], shadow)
    out[ol, :3] = [8, 5, 3]; out[ol, 3] = 1
    out[outer, :3] = np.clip(rgb[outer], 0, 255); out[outer, 3] = 1
    out[..., 3] *= 255
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGBA')

os.makedirs(OUT, exist_ok=True)
for hue in ('on', 'off'):
    paint(False, hue).resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, f'arrow_{hue}.tga'))
    paint(True, hue).resize((128, 128), Image.LANCZOS).save(os.path.join(OUT, f'arrow_{hue}_s.tga'))
print('ok')
