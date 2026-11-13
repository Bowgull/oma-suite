# OmaDemon edge looks (sheet 50 v6, approved 2026-11-13 "Yes, build all four"): Default, Fel, Smoke, Soul drain.
# Every look is Blizzard's edge band (edge-<colour>.tga) plus a few WHITE alpha textures the game tints with the
# Warning colour's ramp (deep / colour / hot). Screen-shaped textures are 1024x576 (stretched over the screen like
# edge.tga); tiles wrap. Nothing flashes; the band's own breath drives all of it.
#   fel_inner / fel_mid / fel_hot  screen  the band's inner edge shaped into still, uneven flame tongues (3 ramp steps)
#   smoke                          512x512 tile   soft billows with near-empty gaps (scrolled up under the band mask)
#   strands                        1024x256 tile  thin threads along x (scrolled along each side under its side mask)
#   mask_band                      screen  the band, widened a little (what the smoke shows through)
#   mask_t/b/l/r                   screen  the same, one side each, soft seams (what the strands show through)
#   edgerim                        screen  the outermost part of the band (the hot layer for Smoke)
# Run: python -I make_looks.py      (from this folder; writes .tga + .png)
import numpy as np
from PIL import Image
W, H = 1024, 576

def ss(a, b, x): x = np.clip((x - a) / (b - a), 0, 1); return x * x * (3 - 2 * x)
def save(a, name):
    a = (np.clip(a, 0, 1) * 255).astype('uint8'); im = Image.new('RGBA', (a.shape[1], a.shape[0]), (255, 255, 255, 0))
    im.putalpha(Image.fromarray(a)); im.save(name + '.tga'); im.save(name + '.png'); print(name, a.shape)
def fbm(w, h, power, lo, hi, stretch, seed):
    r = np.random.default_rng(seed)
    fy = np.fft.fftfreq(h)[:, None] * stretch[1]; fx = np.fft.fftfreq(w)[None, :] * stretch[0]
    f = np.sqrt(fx * fx + fy * fy); f[0, 0] = 1
    amp = 1 / f ** power; amp[f > hi] = 0; amp[f < lo] = 0
    n = np.real(np.fft.ifft2(amp * np.exp(2j * np.pi * r.random((h, w))))); n -= n.min(); return n / n.max()

B = np.array(Image.open('edge.png').convert('RGBA')).astype(float)[..., 3] / 255
yy, xx = np.mgrid[0:H, 0:W]

# ---- Fel: tongues along the band's inner edge, uneven, fading out at the corners ----
dl, dr, dt, db = xx, W - 1 - xx, yy, H - 1 - yy
near = np.argmin(np.stack([dt, dr, db, dl]), axis=0)
s = np.where(near == 0, xx, np.where(near == 1, W + yy, np.where(near == 2, W + H + (W - xx), 2 * W + H + (H - yy)))).astype(float)
L = 2 * (W + H); r = np.random.default_rng(11)
pos, p = [], 0
while p < L: p += r.uniform(64, 136); pos.append(p)
T = np.zeros_like(s)
for c in pos:
    hgt, wid = r.uniform(.35, 1) ** 1.3, r.uniform(13, 24)
    d = np.abs(((s - c + L / 2) % L) - L / 2); T = np.maximum(T, hgt * np.exp(-(d / wid) ** 2))
along = np.minimum(np.abs(np.minimum(xx, W - 1 - xx) - np.minimum(yy, H - 1 - yy)), 160) / 160
T *= ss(0, 1, along)
e = 1.6 * (1 - ss(0, .35, T)) + np.where(T > 0, 1 / (.45 + 1.6 * T), 1.6) * ss(0, .35, T)
F = B ** e
save(ss(.03, .4, F), 'fel_inner'); save(ss(.35, .8, F), 'fel_mid'); save(ss(.72, 1, F), 'fel_hot')

# ---- masks ----
wide = ss(0, .55, B); save(wide, 'mask_band')
dx, dy = (xx - W / 2) / (W / 2), (yy - H / 2) / (H / 2)
wv = ss(-.15, .15, np.abs(dy) - np.abs(dx)); wh = 1 - wv
for k, w in {'t': wv * (dy < 0), 'b': wv * (dy >= 0), 'l': wh * (dx < 0), 'r': wh * (dx >= 0)}.items(): save(w * wide, 'mask_' + k)
save(ss(.82, 1, B) ** 1.4, 'edgerim')

# ---- tiles ----
sm = fbm(512, 512, 2.0, 1 / 256, 1 / 40, (1, 1.6), 23)
save(ss(.15, .75, np.clip((sm - .3) / .55, 0, 1) ** 1.2), 'smoke')
st = fbm(1024, 256, 1.6, 1 / 200, 1 / 4, (7, 1), 31)
save(np.clip((st - .5) / .35, 0, 1) ** 1.4, 'strands')
