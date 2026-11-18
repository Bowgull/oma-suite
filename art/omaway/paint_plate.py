# OmaWay's plate (under the arrow) and its "you're here" marker, painted like the arrow (sheet 115 v2, 2026-11-17:
# "the you're here and the 120 yd apothecary ... very AI driven, lets make it a bit more rich").
#   plate.tga       256x80  dark stone in a cast-gold frame, a diamond on each end cap; drawn 9-sliced in game
#                           (margins 30 left/right, 18 top/bottom) so the caps never stretch
#   plate_warn.tga  the same with an ember-red inner edge (facing away)
#   here.tga        128x128 a gold ring with a soft violet well and four chevrons pointing in at the spot
# Fully procedural.   python art/omaway/paint_plate.py addons/OmaWay/Art
import sys, os, numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as nd
OUT = sys.argv[1] if len(sys.argv) > 1 else '.'
GOLD = [[34, 20, 6], [96, 60, 16], [170, 116, 34], [226, 176, 70], [255, 236, 170], [255, 252, 232]]

def ramp(t, pal):
    pal = np.array(pal, float)
    t = np.clip(t, 0, 1) * (len(pal) - 1); i = np.clip(np.floor(t).astype(int), 0, len(pal) - 2); f = (t - i)[..., None]
    return pal[i] * (1 - f) + pal[i + 1] * f

def noise(W, H, scale, seed):
    r = np.random.default_rng(seed).random((H // scale + 2, W // scale + 2))
    im = Image.fromarray((r * 255).astype(np.uint8)).resize((W + 2 * scale, H + 2 * scale), Image.BICUBIC)
    return np.asarray(im)[scale:scale + H, scale:scale + W] / 255.0

def bevel(mask, inner, width, W, H, seed=1):
    pnt = 0.5 * noise(W, H, 4, seed) + 0.3 * noise(W, H, 12, seed + 1) + 0.2 * noise(W, H, 40, seed + 2)
    streak = nd.gaussian_filter(np.random.default_rng(seed).random((H, W)), (0.6, 7)); streak = (streak - streak.min()) / (streak.max() - streak.min())
    d_out = nd.distance_transform_edt(mask); d_in = nd.distance_transform_edt(~inner)
    h = np.sin(np.clip(np.minimum(d_out, d_in) / (width / 2), 0, 1) * np.pi / 2)
    hs = nd.gaussian_filter(h, 1.4); gy, gx = np.gradient(hs)
    L = np.array([-0.65, -0.75]); L /= np.linalg.norm(L)
    lam = np.clip(-(gx * L[0] + gy * L[1]) * 14, -1, 1)
    shade = (0.48 + 0.62 * lam + 0.35 * (hs - 0.5)) * (0.82 + 0.3 * pnt) * (0.9 + 0.18 * streak)
    g = ramp(shade * 0.92, GOLD)
    rim = mask & ~inner
    grime = np.clip(1 - d_in / 5.0, 0, 1) * rim; g *= (1 - 0.5 * grime)[..., None]
    glint = (d_out > 0) & (d_out < 2.5) & rim & (lam > 0.35); g[glint] = g[glint] * 0.4 + np.array([255, 248, 220]) * 0.6
    return g, pnt, streak

def finish(rgb, mask, W, H, outline=4):
    ol = nd.binary_dilation(mask, iterations=outline) & ~mask
    shadow = np.clip(nd.gaussian_filter(nd.shift(mask.astype(float), (4, 3), order=0), 4) * .7, 0, 1)
    out = np.zeros((H, W, 4)); out[..., 3] = shadow
    out[ol, :3] = [8, 5, 3]; out[ol, 3] = 1
    out[mask, :3] = np.clip(rgb[mask], 0, 255); out[mask, 3] = 1
    out[..., 3] *= 255
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGBA')

def plate(warn):
    W, H = 512, 160                                   # painted at 2x, saved 256x80 (two lines of text)
    im = Image.new('L', (W, H), 0); d = ImageDraw.Draw(im)
    pad = 10
    d.rounded_rectangle([pad + 30, pad + 18, W - pad - 30, H - pad - 18], radius=10, fill=255)
    for cx in (pad + 34, W - pad - 34):              # the end caps: a diamond each
        d.polygon([(cx - 34, H / 2), (cx, pad + 4), (cx + 34, H / 2), (cx, H - pad - 4)], fill=255)
    mask = np.asarray(im) > 127
    inn = Image.new('L', (W, H), 0); d2 = ImageDraw.Draw(inn)
    d2.rounded_rectangle([pad + 46, pad + 30, W - pad - 46, H - pad - 30], radius=6, fill=255)
    for cx in (pad + 34, W - pad - 34):
        d2.polygon([(cx - 16, H / 2), (cx, pad + 26), (cx + 16, H / 2), (cx, H - pad - 26)], fill=255)
    inner = np.asarray(inn) > 127
    gold, pnt, streak = bevel(mask, inner, 22, W, H)
    yy, xx = np.mgrid[0:H, 0:W]
    STONE = [[6, 4, 10], [18, 13, 26], [34, 26, 48], [60, 46, 84]]
    light = np.clip(1.1 - (yy / H) * 0.7, 0, 1.2)
    stone = ramp(np.clip((0.6 * pnt + 0.4 * streak) * 0.6 * light, 0, 1), STONE)
    edge = np.clip(nd.distance_transform_edt(inner) / 10.0, 0, 1)[..., None]
    body = stone * (0.55 + 0.45 * edge)
    # the diamonds' cores: a violet gem (or an ember when facing away)
    gem = np.zeros((H, W), bool)
    for cx in (pad + 34, W - pad - 34):
        gm = Image.new('L', (W, H), 0); ImageDraw.Draw(gm).polygon([(cx - 14, H / 2), (cx, pad + 30), (cx + 14, H / 2), (cx, H - pad - 30)], fill=255)
        gem |= np.asarray(gm) > 127
    gpal = [[30, 6, 50], [110, 40, 190], [220, 170, 255], [255, 255, 255]] if not warn else [[50, 6, 4], [190, 40, 20], [255, 170, 130], [255, 255, 255]]
    gt = np.clip(1.15 - (yy - (pad + 30)) / 70.0 - np.abs(xx - W / 2) * 0, 0, 1)
    body[gem] = ramp(gt * 0.9, gpal)[gem]
    if warn:   # an ember edge inside the frame
        ring = np.clip(1 - nd.distance_transform_edt(inner) / 8.0, 0, 1) * inner
        body = body + ring[..., None] * np.array([200, 50, 20]) * 0.8
    rgb = np.zeros((H, W, 3)); rgb[mask & ~inner] = gold[mask & ~inner]; rgb[inner] = body[inner]
    return finish(rgb, mask, W, H).resize((256, 80), Image.LANCZOS)

def here():
    S = 256
    yy, xx = np.mgrid[0:S, 0:S]; r = np.sqrt((xx - S / 2) ** 2 + (yy - S / 2) ** 2)
    mask = (r < 100) & (r > 74)
    for k in range(4):   # chevrons pointing in, on the compass points
        a = k * np.pi / 2
        cx, cy = S / 2 + np.cos(a) * 112, S / 2 + np.sin(a) * 112
        ch = Image.new('L', (S, S), 0); dd = ImageDraw.Draw(ch)
        tip = (S / 2 + np.cos(a) * 92, S / 2 + np.sin(a) * 92)
        l = (cx + np.cos(a + 2.3) * 22, cy + np.sin(a + 2.3) * 22); rr = (cx + np.cos(a - 2.3) * 22, cy + np.sin(a - 2.3) * 22)
        dd.polygon([tip, l, (cx + np.cos(a) * 6, cy + np.sin(a) * 6), rr], fill=255)
        mask |= np.asarray(ch) > 127
    inner = nd.binary_erosion(mask, iterations=6)
    gold, pnt, _ = bevel(mask, inner, 12, S, S, seed=4)
    rgb = gold.copy()
    well = r < 74
    WELL = [[4, 2, 10], [40, 12, 80], [130, 60, 220], [235, 200, 255]]
    sw = np.arctan2(yy - S / 2, xx - S / 2) + 3.0 * np.log(r / 80 + 0.08)
    v = (0.5 + 0.5 * np.sin(sw * 3 + nd.gaussian_filter(pnt, 3) * 8)) * np.clip(1.1 - r / 74, 0, 1)
    wcol = ramp(np.clip(v * 0.7 + np.clip(1 - r / 26, 0, 1) ** 2, 0, 1), WELL)
    out = finish(rgb, mask, S, S, outline=5)
    a = np.asarray(out).astype(float)
    wa = np.clip(1.15 - r / 74, 0, 1) * 0.85 * well
    a[..., :3] = a[..., :3] * (1 - wa[..., None] * (a[..., 3:] < 1)) + wcol * wa[..., None] * (a[..., 3:] < 1)
    a[..., 3] = np.maximum(a[..., 3], wa * 255)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGBA').resize((128, 128), Image.LANCZOS)

os.makedirs(OUT, exist_ok=True)
plate(False).save(os.path.join(OUT, 'plate.tga')); plate(True).save(os.path.join(OUT, 'plate_warn.tga')); here().save(os.path.join(OUT, 'here.tga'))
print('ok')
