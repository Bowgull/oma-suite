# Builds OmashuDemon's three textures (sheet 15 B, approved 2026-11-09). Geometry in units of the portrait
# radius r, exactly as the mockup's drawPet: texture spans 2.2r each side of centre.
#   bloom: soft violet, clipped to start just outside the gold ring (38/36 r) and fade out by 2.2 r
#   rim:   thin ring at 39/36 r, lit from above (#e6c2ff top -> #7832c8 bottom), 2.5/36 r wide
#   sheen: a short bright arc on the rim with a fading tail; the addon spins it once every 3.5 s
# Run: python3 -I make_art.py   (writes .tga + .png previews)
import math
from PIL import Image
N = 256; C = (N - 1) / 2; U = (N / 2) / 2.2           # pixels per r
# 2026-11-13 warning colours (Joshua: "fel green and hellfire amber ... lets work with those"). '' = soul purple, unchanged.
PALETTES = {
    '':       dict(b=((166, 92, 255), (140, 70, 230), (120, 50, 200)), rim=((230, 194, 255), (120, 50, 200)), sheen=(245, 225, 255), edge=((166, 92, 255), (90, 42, 160))),
    '-fel':   dict(b=((96, 232, 64), (70, 200, 48), (40, 150, 30)),   rim=((210, 255, 180), (40, 150, 30)),  sheen=(230, 255, 215), edge=((96, 232, 64), (36, 120, 24))),
    '-ember': dict(b=((255, 122, 30), (230, 96, 20), (190, 70, 10)),  rim=((255, 214, 150), (190, 70, 10)),  sheen=(255, 236, 200), edge=((255, 122, 30), (150, 52, 10))),
}
P = PALETTES['']
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
    if t < .35: k = .9 + (.38 - .9) * t / .35; col = mix(P['b'][0], P['b'][1], t / .35)
    else: k = .38 * (1 - (t - .35) / .65) ** 1.4; col = mix(P['b'][1], P['b'][2], (t - .35) / .65)
    soft = min(1, (d - r0) / .04)                       # 1 px soft inner edge so it never shows a seam
    # x1.8: measured in game 2026-11-10 the bloom read about half as strong as the approved sheet (WoW's
    # texture blend on the dark frame art eats it), so it is lifted to match the sheet, capped at full.
    return (*col, min(255, round(255 * k * soft * 1.8)))
def rim(d, a, yy):
    rr, hw = 39 / 36, 1.25 / 36
    k = max(0.0, 1 - abs(d - rr) / hw)
    if k <= 0: return (0, 0, 0, 0)
    t = (yy + 1) / 2                                    # 0 top .. 1 bottom
    top, bot = P['rim']
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
    return (*P['sheen'], round(255 * .55 * f * k))
def make_rings(sfx):
    for name, f in (('bloom', bloom), ('rim', rim), ('sheen', sheen)):
        im = ring_img(f); im.save(name + sfx + '.tga'); im.save(name + sfx + '.png')
        print(name + sfx, im.getbbox())

# ---- edge (sheet 17, approved 2026-11-10 "Yes the purple is perfect"): a soul-purple screen-edge band, same size as
# Blizzard's red low-health edge. 16:9 texture stretched over the whole screen; band = 16% of the height on every side,
# #a65cff at the edge -> #5a2aa0 at 30% in -> clear at the band's inner edge; the corners a little stronger (radial).
def make_edge(sfx=''):
    W, H = 1024, 576; d = round(H * .16)
    c1, c2 = P['edge']
    im = Image.new('RGBA', (W, H)); px = im.load()
    def band(t):                       # t: 0 at the edge .. 1 at the inner edge of the band
        if t >= 1: return 0.0
        return .95 - .4 * (t / .3) if t < .3 else .55 * (1 - (t - .3) / .7)
    for y in range(H):
        for x in range(W):
            dx, dy = min(x, W - 1 - x), min(y, H - 1 - y)
            t = min(dx, dy) / d
            a = band(t)
            cd = math.hypot(dx, dy) / (d * 1.15)          # the corner glow
            if cd < 1: a = max(a, .95 * (1 - cd) if cd < .5 else .55 * (1 - cd) / .5 * 1.0)
            tt = min(1.0, t if t < 1 else 1.0)
            col = tuple(round(c1[i] + (c2[i] - c1[i]) * min(1, tt / .3)) for i in range(3))
            px[x, y] = (*col, round(255 * min(1, a)))
    im.save('edge' + sfx + '.tga'); im.save('edge' + sfx + '.png')
for sfx, pal in PALETTES.items():
    P = pal; make_rings(sfx); make_edge(sfx)
