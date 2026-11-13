# OmaDemon edge looks, drawn in code (2026-11-13, replacing Wisps / Essence / Soul fire, which read cheap).
# Three calm, rich warlock looks, all drawn WHITE so the game can tint them to the warning colour
# (Default soul purple, Fel green, Hellfire ember), like the ring and edge art:
#   sigil   - summoning-circle arcs in the four corners: two fine rings with fel runes between them
#   grasp   - shadow claws reaching in from the left and right edges, light only on their inner rims
#   runes   - a thin engraved rune band around the whole screen edge, strongest in the corners
# Writes PNGs at screen size (1920x1080) for mockups; the add-on's TGAs are cut from these once approved.
# Run: python -I make_edge_looks.py <outdir>
import math, random, sys, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else '.'
W, H = 1920, 1080
SS = 2                                   # draw at 2x, shrink for smooth lines

# ---------- runes: angular glyphs on a 3x4 grid, the same set every run ----------
GRID = [(x, y) for y in range(4) for x in range(3)]
STROKES = [(0, 3), (1, 4), (2, 5), (3, 6), (4, 7), (5, 8), (6, 9), (7, 10), (8, 11),   # verticals
           (0, 4), (2, 4), (3, 7), (5, 7), (6, 10), (8, 10), (4, 6), (4, 8),              # diagonals
           (0, 1), (1, 2), (3, 4), (6, 7), (7, 8), (9, 10), (10, 11)]                       # bars
rng = random.Random(1717)
def make_glyph():
    spine = rng.choice([(1, 4), (4, 7), (7, 10)])
    picks = {spine, (4, 7) if spine != (4, 7) else (1, 4)}
    while len(picks) < rng.randint(4, 5): picks.add(rng.choice(STROKES))
    return list(picks)
GLYPHS = [make_glyph() for _ in range(24)]
def draw_glyph(d, cx, cy, size, angle, g, width, fill):
    ca, sa = math.cos(angle), math.sin(angle)
    def P(i):
        gx, gy = GRID[i]; x = (gx - 1) * size * .32; y = (gy - 1.5) * size * .3
        return (cx + x * ca - y * sa, cy + x * sa + y * ca)
    for a, b in g: d.line([P(a), P(b)], fill=fill, width=width)

def glowed(layer, blur, k):
    g = layer.filter(ImageFilter.GaussianBlur(blur)); arr = np.array(g).astype(float)
    arr[..., 3] = np.clip(arr[..., 3] * k, 0, 255); g = Image.fromarray(arr.astype('uint8'))
    g.alpha_composite(layer); return g

def finish(im, name):
    im = im.resize((W, H), Image.LANCZOS); im.save(os.path.join(OUT, name)); return im

# ---------- 1. sigil: summoning-circle arcs in the corners ----------
def sigil():
    im = Image.new('RGBA', (W * SS, H * SS)); d = ImageDraw.Draw(im)
    R = int(H * .28) * SS; gap = 26 * SS
    for (cx, cy, a0) in [(0, 0, 0), (W * SS, 0, 90), (W * SS, H * SS, 180), (0, H * SS, 270)]:
        box = lambda r: (cx - r, cy - r, cx + r, cy + r)
        d.arc(box(R), a0, a0 + 90, fill=(255, 255, 255, 235), width=2 * SS)
        d.arc(box(R - gap), a0, a0 + 90, fill=(255, 255, 255, 200), width=SS)
        d.arc(box(R + 14 * SS), a0 + 4, a0 + 86, fill=(255, 255, 255, 90), width=SS)
        for k in range(0, 90, 3):                                        # fine ticks outside, like a dial
            t = math.radians(a0 + k + 1.5)
            r1, r2 = R + 4 * SS, R + (10 if k % 15 == 0 else 7) * SS
            d.line([(cx + r1 * math.cos(t), cy + r1 * math.sin(t)), (cx + r2 * math.cos(t), cy + r2 * math.sin(t))], fill=(255, 255, 255, 140), width=SS)
        n = 9
        for i in range(n):                                               # runes between the two rings
            t = math.radians(a0 + 6 + (78 / (n - 1)) * i); rr = R - gap / 2
            draw_glyph(d, cx + rr * math.cos(t), cy + rr * math.sin(t), 15 * SS, t + math.pi / 2, GLYPHS[(i + a0 // 90 * 5) % len(GLYPHS)], int(1.6 * SS), (255, 255, 255, 230))
        R2 = int(R * .58)                                                # a small inner arc with three marks
        d.arc(box(R2), a0 + 12, a0 + 78, fill=(255, 255, 255, 110), width=SS)
        for k in (25, 45, 65):
            t = math.radians(a0 + k)
            d.ellipse([cx + R2 * math.cos(t) - 3 * SS, cy + R2 * math.sin(t) - 3 * SS, cx + R2 * math.cos(t) + 3 * SS, cy + R2 * math.sin(t) + 3 * SS], fill=(255, 255, 255, 170))
    return finish(glowed(im, 6 * SS, 1.4), 'look_sigil.png')

# ---------- 2. grasp: shadow claws from the sides ----------
def noise(w, h, seed):
    r = np.random.default_rng(seed); acc = np.zeros((h, w))
    for s, k in ((8, .5), (16, .25), (32, .15), (64, .1)):
        small = r.random((h // s + 2, w // s + 2))
        acc += k * np.array(Image.fromarray((small * 255).astype('uint8')).resize((w + s, h + s), Image.BICUBIC))[:h, :w] / 255
    return acc
def talon(pts_spine, w0):
    # a tapered shape along a list of spine points; returns polygon points
    left, right = [], []
    n = len(pts_spine)
    for i, (x, y) in enumerate(pts_spine):
        x2, y2 = pts_spine[min(i + 1, n - 1)]; x1, y1 = pts_spine[max(i - 1, 0)]
        dx, dy = x2 - x1, y2 - y1; L = math.hypot(dx, dy) or 1; nx, ny = -dy / L, dx / L
        w = w0 * (1 - i / (n - 1)) ** 1.15
        left.append((x + nx * w, y + ny * w)); right.append((x - nx * w, y - ny * w))
    return left + right[::-1]
def bez(p0, p1, p2, p3, n=60):
    out = []
    for i in range(n):
        t = i / (n - 1); u = 1 - t
        out.append((u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
                    u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1]))
    return out
def grasp():
    shadow = Image.new('L', (W * SS, H * SS), 0); rim = Image.new('L', (W * SS, H * SS), 0)
    ds, dr = ImageDraw.Draw(shadow), ImageDraw.Draw(rim)
    S = SS
    claws = [  # (root y, reach, rise, width) for the left side; mirrored for the right
        (.70, .20, -.20, 30), (.80, .25, -.12, 34), (.90, .19, -.05, 26), (.58, .12, -.22, 18)]
    for side in (0, 1):
        for (ry, reach, rise, w0) in claws:
            x0 = 0; y0 = H * ry
            p0 = (x0, y0); p1 = (W * reach * .45, y0 + H * .02); p2 = (W * reach * .9, y0 + H * rise * .4); p3 = (W * reach, y0 + H * rise)
            spine = bez(p0, p1, p2, p3)
            if side: spine = [(W - x, y) for x, y in spine]
            spine = [(x * S, y * S) for x, y in spine]
            poly = talon(spine, w0 * S)
            ds.polygon(poly, fill=255)
            # light on the inner (upper) rim only: the claw's top edge, toward the screen centre
            edge = poly[:len(spine)]
            dr.line(edge[4:-2], fill=255, width=int(2.2 * S))
        # the smoky root mass along the edge, lower half
        x0 = 0 if side == 0 else W * S
        for i in range(14):
            yy = H * S * (.50 + .48 * i / 13); rr = (90 - 20 * abs(i - 9) / 9) * S
            ds.ellipse([x0 - rr * 1.3, yy - rr, x0 + rr * .6, yy + rr], fill=255)
    n = noise(W * S // 4, H * S // 4, 7); n = np.array(Image.fromarray((n * 255 / n.max()).astype('uint8')).resize((W * S, H * S), Image.BICUBIC)) / 255
    sh = np.array(shadow.filter(ImageFilter.GaussianBlur(10 * S))) / 255
    sh = np.clip(sh * (.55 + .7 * n), 0, 1)                               # smoky, uneven body
    rm = np.array(rim.filter(ImageFilter.GaussianBlur(1.2 * S))) / 255
    rmglow = np.array(rim.filter(ImageFilter.GaussianBlur(9 * S))) / 255
    rm = np.clip(rm + rmglow * .9, 0, 1) * (np.array(shadow.filter(ImageFilter.GaussianBlur(3 * S))) / 255 > .05)
    # fade from the screen edge (root) toward the tips, so the claws read as reaching in, not as lines
    xx = np.mgrid[0:H * S, 0:W * S][1]; dist = np.minimum(xx, W * S - xx) / (W * S * .26)
    fade = np.clip(1 - dist, 0, 1) ** .8
    body = np.clip(sh * (.35 + .65 * fade), 0, 1) * .62
    lum = np.clip(body + rm * .9, 0, 1)
    a = Image.fromarray((lum * 255).astype('uint8')).resize((W, H), Image.LANCZOS)
    lit = Image.new('RGBA', (W, H), (255, 255, 255, 0)); lit.putalpha(a); lit.save(os.path.join(OUT, 'look_grasp.png'))
    core = np.clip(sh * .55 * fade, 0, 1)
    dark = Image.new('RGBA', (W, H), (6, 2, 10, 0)); dark.putalpha(Image.fromarray((core * 200).astype('uint8')).resize((W, H), Image.LANCZOS))
    dark.save(os.path.join(OUT, 'look_grasp_shadow.png'))

# ---------- 3. runes: an engraved band round the edge ----------
def runes():
    im = Image.new('RGBA', (W * SS, H * SS)); d = ImageDraw.Draw(im)
    m = 12 * SS; band = 30 * SS
    for inset, a, w in ((m, 220, 2), (m + band, 170, 1)):
        d.rectangle([inset, inset, W * SS - inset, H * SS - inset], outline=(255, 255, 255, a), width=w * SS)
    step = 36 * SS; mid = m + band / 2; k = 0
    def put(x, y, ang):
        nonlocal k; draw_glyph(d, x, y, 17 * SS, ang, GLYPHS[k % len(GLYPHS)], int(1.8 * SS), (255, 255, 255, 235)); k += 1
    x = m + band + step / 2
    while x < W * SS - m - band: put(x, mid, 0); put(W * SS - x, H * SS - mid, math.pi); x += step
    y = m + band + step / 2
    while y < H * SS - m - band: put(mid, H * SS - y, -math.pi / 2); put(W * SS - mid, y, math.pi / 2); y += step
    for cx, cy in ((mid, mid), (W * SS - mid, mid), (mid, H * SS - mid), (W * SS - mid, H * SS - mid)):   # corner seals
        d.ellipse([cx - 9 * SS, cy - 9 * SS, cx + 9 * SS, cy + 9 * SS], outline=(255, 255, 255, 230), width=2 * SS)
        d.ellipse([cx - 3 * SS, cy - 3 * SS, cx + 3 * SS, cy + 3 * SS], fill=(255, 255, 255, 230))
    # strongest in the corners, quieter mid-edge
    arr = np.array(im).astype(float); yy, xx = np.mgrid[0:H * SS, 0:W * SS]
    fx = np.minimum(xx, W * SS - xx) / (W * SS / 2); fy = np.minimum(yy, H * SS - yy) / (H * SS / 2)
    f = np.clip(1 - .55 * np.minimum(np.maximum(fx, fy) * 1.0, 1) ** 0 * np.clip(np.minimum(fx, fy) * 0 + np.maximum(fx, fy), 0, 1), .45, 1)
    arr[..., 3] *= f; im = Image.fromarray(arr.astype('uint8'))
    return finish(glowed(im, 5 * SS, 1.3), 'look_runes.png')

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    sigil(); grasp(); runes(); print('wrote', OUT)
