# Builds OmashuDemon's three textures (sheet 15 B, approved 2026-11-09). Geometry in units of the portrait
# radius r, exactly as the mockup's drawPet: texture spans 2.2r each side of centre.
#   bloom: soft violet, clipped to start just outside the gold ring (38/36 r) and fade out by 2.2 r
#   rim:   thin ring at 39/36 r, lit from above (#e6c2ff top -> #7832c8 bottom), 2.5/36 r wide
#   sheen: a short bright arc on the rim with a fading tail; the addon spins it once every 3.5 s
# Run: python3 -I make_art.py   (writes .tga + .png previews)
import math
from PIL import Image
N = 256; C = (N - 1) / 2; U = (N / 2) / 2.2           # pixels per r
def ring_img(f):
    im = Image.new('RGBA', (N, N)); px = im.load()
    for y in range(N):
        for x in range(N):
            d = math.hypot(x - C, y - C) / U; a = math.atan2(y - C, x - C)
            px[x, y] = f(d, a, (y - C) / U)
    return im
def bloom(d, a, yy):
    r0 = 38 / 36
    if d < r0 or d > 2.2: return (0, 0, 0, 0)
    t = (d - r0) / (2.2 - r0)
    mix = lambda p, q, u: tuple(round(p[i] + (q[i] - p[i]) * u) for i in range(3))
    if t < .35: k = .9 + (.38 - .9) * t / .35; col = mix((166, 92, 255), (140, 70, 230), t / .35)
    else: k = .38 * (1 - (t - .35) / .65) ** 1.4; col = mix((140, 70, 230), (120, 50, 200), (t - .35) / .65)
    soft = min(1, (d - r0) / .04)                       # 1 px soft inner edge so it never shows a seam
    return (*col, round(255 * k * soft))
def rim(d, a, yy):
    rr, hw = 39 / 36, 1.25 / 36
    k = max(0.0, 1 - abs(d - rr) / hw)
    if k <= 0: return (0, 0, 0, 0)
    t = (yy + 1) / 2                                    # 0 top .. 1 bottom
    top, bot = (230, 194, 255), (120, 50, 200)
    col = tuple(round(top[i] + (bot[i] - top[i]) * min(1, max(0, t))) for i in range(3))
    return (*col, round(255 * min(1, k * 1.6) * (.95 - .1 * t)))
def sheen(d, a, yy):
    rr, hw = 39 / 36, 2.2 / 36
    k = max(0.0, 1 - abs(d - rr) / hw)
    if k <= 0: return (0, 0, 0, 0)
    # head at -90 deg (top), tail trailing anticlockwise over ~0.55 rad
    da = (a - (-math.pi / 2)) % (2 * math.pi)
    tail = .55
    if da > tail: return (0, 0, 0, 0)
    f = (1 - da / tail) ** 1.5
    return (245, 225, 255, round(255 * .55 * f * k))
for name, f in (('bloom', bloom), ('rim', rim), ('sheen', sheen)):
    im = ring_img(f); im.save(name + '.tga'); im.save(name + '.png')
    print(name, im.getbbox())
