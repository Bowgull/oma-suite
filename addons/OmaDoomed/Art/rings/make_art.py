#!/usr/bin/env python3
# Omashu Plates art: every texture the addon loads, drawn from the approved mockup
# (mockups/omashu/wow/15-glows-and-nameplates.html, section C, style 3 "Omashu skin", drawNP style===3).
#
# Run from anywhere:  python3 -I make_art.py            (writes next to this file)
#                     python3 -I make_art.py --preview DIR   (also writes a contact sheet PNG into DIR)
#
# Only Python + PIL. Every size is a fraction of one icon cell (cell = 1), copied from the mockup where the cell is
# 70 canvas units and the round art radius r = 0.42 cell. All textures are 256x256, 32-bit, uncompressed,
# bottom-left origin (the same TGA flavour as OmashuShards.tga), and each one covers the whole cell, so the addon
# just does SetAllPoints on every layer.
import math, os, struct, sys

N = 256                       # texture size in pixels (power of two; ~158 px on the TV for a 56-unit cell)
R = 0.42                      # mockup: r = size * .42
ICON_R = 0.82 * R             # the icon is clipped to r * .82
BEZEL_R, BEZEL_W = 0.86 * R, 2.8 / 70     # brass bezel: arc at r * .86, lineWidth 2.8s
RING_R, RING_W = 1.05 * R, 3.4 / 70       # colour ring: arc at r * 1.05, lineWidth 3.4s
TRACK_W = 4.4 / 70            # the dark track that covers the spent part of the ring (mockup 4s, a touch wider so
                              # it fully hides the coloured ring underneath it)
BACK_R = R + 3 / 70           # dark backing disc: r + 3s
PLAIN_R, PLAIN_W = 0.9 * R, 2 / 42        # other players' plain ring: r * .9, lineWidth 2s on a 42s cell

HERE = os.path.dirname(os.path.abspath(__file__))


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else hi if v > hi else v


def hexrgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def disc_cov(d, radius):
    # antialiased coverage of a disc: d and radius in cell units
    return clamp(0.5 - (d - radius) * N)


def ring_cov(d, radius, width):
    return clamp(0.5 - (abs(d - radius) - width / 2) * N)


def blur_edge(d, radius, sigma):
    # a disc of `radius` blurred by a gaussian of `sigma` (canvas shadowBlur is ~2 sigma)
    return 0.5 * math.erfc((d - radius) / (sigma * math.sqrt(2)))


def edge_fade(d):
    # soft effects must reach zero before the texture edge, or bilinear filtering shows a hard square
    return clamp((0.5 - d) / 0.035)


def over(dst, src):
    # straight-alpha "source over": (r, g, b, a) with rgb 0-255, a 0-1
    sr, sg, sb, sa = src
    dr, dg, db, da = dst
    oa = sa + da * (1 - sa)
    if oa <= 0:
        return (sr, sg, sb, 0.0)
    f = lambda s, d: (s * sa + d * da * (1 - sa)) / oa
    return (f(sr, dr), f(sg, dg), f(sb, db), oa)


def lerp_stops(stops, t):
    # stops: [(t, (r, g, b, a)), ...]; interpolates in premultiplied space like a canvas gradient
    t = clamp(t)
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            k = 0 if t1 == t0 else (t - t0) / (t1 - t0)
            a = c0[3] + (c1[3] - c0[3]) * k
            if a <= 0:
                return (c1[0], c1[1], c1[2], 0.0)
            pm = [(c0[i] * c0[3] + (c1[i] * c1[3] - c0[i] * c0[3]) * k) / a for i in range(3)]
            return (pm[0], pm[1], pm[2], a)
    return stops[-1][1]


def render(fn):
    # fn(x, y, d) -> (r, g, b, a); x, y in cell units with y going DOWN (like the canvas), d = distance to centre
    px = []
    for j in range(N):
        y = (j + 0.5) / N
        row = []
        for i in range(N):
            x = (i + 0.5) / N
            d = math.hypot(x - 0.5, y - 0.5)
            row.append(fn(x, y, d))
        px.append(row)
    return px


def write_tga(path, px):
    # type 2 (uncompressed true colour), 32 bpp, descriptor 0x08 = 8 alpha bits, bottom-left origin
    out = bytearray(struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 0x08))
    for row in reversed(px):
        for r, g, b, a in row:
            out += bytes((int(round(clamp(b / 255) * 255)), int(round(clamp(g / 255) * 255)),
                          int(round(clamp(r / 255) * 255)), int(round(clamp(a) * 255))))
    with open(path, 'wb') as f:
        f.write(out)


# ---------- the textures ----------
def backing(x, y, d):
    # mockup: shadowColor rgba(0,0,0,.8), shadowBlur 5s, fill #120803 disc of r + 3s
    shadow = (0, 0, 0, 0.8 * blur_edge(d, BACK_R, 5 / 70 / 2) * edge_fade(d))
    disc = hexrgb('#120803') + (disc_cov(d, BACK_R),)
    return over(shadow, disc)


def mask(x, y, d):
    # icon mask: white, alpha = the round icon (r * .82)
    return (255, 255, 255, disc_cov(d, ICON_R))


BRASS = [(0.0, hexrgb('#f3d78a') + (1.0,)), (0.45, hexrgb('#b8862a') + (1.0,)), (1.0, hexrgb('#4a2e08') + (1.0,))]
GLOSS = [(0.0, (255, 255, 255, 0.18)), (0.6, (0, 0, 0, 0.0)), (1.0, (0, 0, 0, 0.45))]


def bezel(x, y, d):
    # gloss over the icon (radial: highlight up-left, shade at the rim), then the brass bezel ring on top.
    # The brass gradient runs top to bottom over cy - r .. cy + r, exactly like the mockup's createLinearGradient.
    gx, gy = 0.5 - 0.3 * R, 0.5 - 0.4 * R
    g = lerp_stops(GLOSS, (math.hypot(x - gx, y - gy) - 0.1 * R) / (0.9 * R))
    gloss = (g[0], g[1], g[2], g[3] * disc_cov(d, ICON_R))
    b = lerp_stops(BRASS, (y - (0.5 - R)) / (2 * R))
    ring = (b[0], b[1], b[2], ring_cov(d, BEZEL_R, BEZEL_W))
    return over(gloss, ring)


def ring(x, y, d):
    # white colour ring (the addon tints it), with the mockup's soft glow (shadowBlur 8s in the ring colour)
    out_d = max(0.0, abs(d - RING_R) - RING_W / 2)
    glow = (255, 255, 255, 0.4 * math.exp(-(out_d ** 2) / (2 * (8 / 70 / 2) ** 2)) * edge_fade(d))
    return over(glow, (255, 255, 255, ring_cov(d, RING_R, RING_W)))


def ring_plain(x, y, d):
    # other players' DoTs: a plain thin ring, tinted dark brass by the addon, no glow
    return (255, 255, 255, ring_cov(d, PLAIN_R, PLAIN_W))


def swipe_inner(x, y, d):
    # cooldown swipe on the icon: rgba(0,0,0,.5) over the spent part, clipped to the icon circle
    return (0, 0, 0, 0.5 * disc_cov(d, ICON_R))


def swipe_track(x, y, d):
    # cooldown swipe on the ring: a near-opaque dark track that hides the spent part of the coloured ring
    return (10, 5, 3, 0.92 * ring_cov(d, RING_R, TRACK_W))


# sheet 39 A 'Bold': the colour ring twice as thick, growing inward so its outer edge stays put
BOLD_W = 2 * RING_W
BOLD_R = RING_R - RING_W / 2


def ring_bold(x, y, d):
    out_d = max(0.0, abs(d - BOLD_R) - BOLD_W / 2)
    glow = (255, 255, 255, 0.4 * math.exp(-(out_d ** 2) / (2 * (8 / 70 / 2) ** 2)) * edge_fade(d))
    return over(glow, (255, 255, 255, ring_cov(d, BOLD_R, BOLD_W)))


def swipe_track_bold(x, y, d):
    return (10, 5, 3, 0.92 * ring_cov(d, BOLD_R, BOLD_W + (TRACK_W - RING_W)))


# sheet 41 'Bold, richer' ("Let's try bold richer in game"): the same Bold pieces with depth.
# ring_light lies over the tinted Bold ring: cream lift on the top 40%, shade on the bottom, a warm sheen up-left
# (mockup: gradient 20..236 of 256, stops cream .45 / colour / black .6; sheen at 80,60 radius 90). No glowing tip.
def ring_light(x, y, d):
    cov = ring_cov(d, BOLD_R, BOLD_W)
    if cov <= 0:
        return (0, 0, 0, 0.0)
    t = clamp((y - 20 / 256) / (216 / 256))
    base = (255, 244, 220, 0.45 * (1 - t / 0.4)) if t < 0.4 else (0, 0, 0, 0.6 * (t - 0.4) / 0.6)
    sh = clamp(1 - math.hypot(x - 80 / 256, y - 60 / 256) / (90 / 256))
    out = over((255, 236, 200, 0.45 * sh), base)
    return (out[0], out[1], out[2], out[3] * cov)


def ring_shadow(x, y, d):
    # a soft shadow under the whole ring so it sits in the world (mockup: centre 12/256 low, .6 fading out by 124/256)
    ds = math.hypot(x - 0.5, y - 0.5 - 12 / 256)
    return (0, 0, 0, 0.6 * clamp(1 - (ds - 60 / 256) / (64 / 256)) * edge_fade(d))


def numspot(x, y, d):
    # the icon stays clear; only the middle darkens so the number reads (mockup: centre 4/256 low, radius 58/256)
    ds = math.hypot(x - 0.5, y - 0.5 - 4 / 256) / (58 / 256)
    a = 0.6 + (0.35 - 0.6) * ds / 0.6 if ds < 0.6 else 0.35 * clamp((1 - ds) / 0.4)
    return (0, 0, 0, a)


TEXTURES = {
    'backing': backing, 'mask': mask, 'bezel': bezel, 'ring': ring, 'ring_plain': ring_plain,
    'swipe_inner': swipe_inner, 'swipe_track': swipe_track,
    'ring_bold': ring_bold, 'swipe_track_bold': swipe_track_bold,
    'ring_light': ring_light, 'ring_shadow': ring_shadow, 'numspot': numspot,
}


# ---------- OmashuRing.ttf: one glyph, "O", drawn as the colour ring ----------
# Why a font: on Forever the only thing that changes colour and alpha by "seconds left" is a duration text inside
# Blizzard's aura button (DurationTextBinding:SetTextColorCurve). A font whose "O" is our ring turns that text into a
# ring that can go gold and breathe in the last 3 seconds. em = 1 cell, the ring is centred on the baseline (ascent
# and descent are both half an em), and the advance is half an em with the ring centred on it, so the string is
# narrower than its font string (no "..." truncation) and centring the string centres the ring.
EM = 1024
ADV = 512


def _circle(cx, cy, radius, clockwise, n=16):
    # quadratic TrueType circle: n on-curve points with an off-curve control between each pair
    pts = []
    for k in range(n):
        a0 = 2 * math.pi * k / n
        a1 = a0 + math.pi / n
        if clockwise:
            a0, a1 = -a0, -a1
        pts.append((round(cx + radius * math.cos(a0)), round(cy + radius * math.sin(a0)), 1))
        rc = radius / math.cos(math.pi / n)
        pts.append((round(cx + rc * math.cos(a1)), round(cy + rc * math.sin(a1)), 0))
    return pts


def _checksum(data):
    data = data + b'\0' * (-len(data) % 4)
    return sum(struct.unpack('>%dI' % (len(data) // 4), data)) & 0xFFFFFFFF


def make_font(path):
    cx, cy = ADV // 2, 0
    outer = _circle(cx, cy, (RING_R + RING_W / 2) * EM, clockwise=True)     # outer contour clockwise
    inner = _circle(cx, cy, (RING_R - RING_W / 2) * EM, clockwise=False)    # hole counter-clockwise
    contours = [outer, inner]
    allp = outer + inner
    xmin, xmax = min(p[0] for p in allp), max(p[0] for p in allp)
    ymin, ymax = min(p[1] for p in allp), max(p[1] for p in allp)

    g = struct.pack('>hhhhh', len(contours), xmin, ymin, xmax, ymax)
    end = -1
    for c in contours:
        end += len(c)
        g += struct.pack('>H', end)
    g += struct.pack('>H', 0)                                   # no instructions
    g += bytes(p[2] for p in allp)                              # flags: on-curve bit only, coords as int16 deltas
    px = py = 0
    xs = ys = b''
    for x, y, _ in allp:
        xs += struct.pack('>h', x - px); ys += struct.pack('>h', y - py); px, py = x, y
    g += xs + ys
    g += b'\0' * (-len(g) % 4)

    glyf = g                                                    # glyph 0 (.notdef) is empty, glyph 1 is the ring
    loca = struct.pack('>HHH', 0, 0, len(g) // 2)
    lsb = xmin
    hmtx = struct.pack('>Hh', ADV, 0) + struct.pack('>Hh', ADV, lsb)
    head = struct.pack('>IIIIHHqqhhhhHHhhh', 0x00010000, 0x00010000, 0, 0x5F0F3CF5, 0x000B, EM, 0, 0,
                       xmin, ymin, xmax, ymax, 0, 8, 2, 0, 0)
    hhea = struct.pack('>IhhhHhhhhhhhhhhhH', 0x00010000, EM // 2, -EM // 2, 0, ADV, lsb, ADV - xmax, xmax,
                       1, 0, 0, 0, 0, 0, 0, 0, 2)
    maxp = struct.pack('>IHHHHHHHHHHHHHH', 0x00010000, 2, len(allp), len(contours), 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0)
    os2 = struct.pack('>HhHHHhhhhhhhhhhh10sIIII4sHHHhhhHHIIhhHHH',
                      4, ADV, 400, 5, 0, 650, 600, 0, 75, 650, 600, 0, 350, 50, 300, 0, b'\0' * 10,
                      1, 0, 0, 0, b'OMSH', 0x40, 0x4F, 0x4F, EM // 2, -EM // 2, 0, EM // 2, EM // 2,
                      1, 0, 0, 0, 0, 32, 1)
    post = struct.pack('>IIhhIIIII', 0x00030000, 0, -100, 50, 0, 0, 0, 0, 0)
    # cmap: Windows Unicode BMP, format 4, two segments: 'O' -> glyph 1, then the 0xFFFF terminator
    seg_end, seg_start, seg_delta = [0x4F, 0xFFFF], [0x4F, 0xFFFF], [(1 - 0x4F) & 0xFFFF, 1]
    f4 = struct.pack('>HHHHHHH', 4, 16 + 8 * 2, 0, 4, 4, 1, 0)
    f4 += struct.pack('>2H', *seg_end) + struct.pack('>H', 0) + struct.pack('>2H', *seg_start)
    f4 += struct.pack('>2H', *seg_delta) + struct.pack('>2H', 0, 0)
    f4 = f4[:2] + struct.pack('>H', len(f4)) + f4[4:]
    cmap = struct.pack('>HHHHI', 0, 1, 3, 1, 12) + f4
    names = {1: 'OmashuRing', 2: 'Regular', 3: 'OmashuRing-Regular-1', 4: 'OmashuRing Regular', 6: 'OmashuRing-Regular'}
    recs, strs = b'', b''
    for nid in sorted(names):
        s = names[nid].encode('utf-16-be')
        recs += struct.pack('>HHHHHH', 3, 1, 0x409, nid, len(s), len(strs))
        strs += s
    name = struct.pack('>HHH', 0, len(names), 6 + 12 * len(names)) + recs + strs

    tables = {'OS/2': os2, 'cmap': cmap, 'glyf': glyf, 'head': head, 'hhea': hhea, 'hmtx': hmtx,
              'loca': loca, 'maxp': maxp, 'name': name, 'post': post}
    tags = sorted(tables)
    n = len(tags)
    es = int(math.log2(n))
    sr = 16 * (2 ** es)
    out = struct.pack('>IHHHH', 0x00010000, n, sr, es, n * 16 - sr)
    offset = 12 + 16 * n
    body = b''
    for t in tags:
        data = tables[t]
        out += struct.pack('>4sIII', t.encode('ascii'), _checksum(data), offset + len(body), len(data))
        body += data + b'\0' * (-len(data) % 4)
    font = bytearray(out + body)
    adj = (0xB1B0AFBA - _checksum(bytes(font))) & 0xFFFFFFFF
    hoff = offset + sum(len(tables[t]) + (-len(tables[t]) % 4) for t in tags[:tags.index('head')])
    font[hoff + 8:hoff + 12] = struct.pack('>I', adj)
    with open(path, 'wb') as f:
        f.write(font)


def preview(outdir):
    # contact sheet: each texture on a mid-grey tile, a composed icon, and the font glyph rendered by FreeType
    from PIL import Image, ImageDraw, ImageFont
    tiles = []
    for nm in TEXTURES:
        im = Image.open(os.path.join(HERE, nm + '.tga')).convert('RGBA')
        bg = Image.new('RGBA', (N, N), (90, 90, 96, 255)); bg.alpha_composite(im); tiles.append((nm, bg))
    # composed own DoT (Corruption green), as the addon stacks it: backing, icon, gloss+bezel, inner swipe,
    # ring, track swipe. Here: 30% of the time gone. A flat purple disc stands in for the spell icon.
    def tga(nm):
        return Image.open(os.path.join(HERE, nm + '.tga')).convert('RGBA')
    comp = Image.new('RGBA', (N, N), (70, 80, 60, 255))
    comp.alpha_composite(tga('backing'))
    icon = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(icon).rectangle([int(N * .122), int(N * .122), int(N * .878), int(N * .878)], fill=(120, 60, 150, 255))
    icon.putalpha(Image.eval(tga('mask').getchannel('A'), lambda v: v))
    comp.alpha_composite(icon); comp.alpha_composite(tga('bezel'))
    ring = tga('ring'); r, g, b, a = ring.split()
    tint = Image.merge('RGBA', (r.point(lambda v: v * 0x7f // 255), g.point(lambda v: v * 0xe3 // 255), b.point(lambda v: v * 0x6a // 255), a))
    comp.alpha_composite(tint)
    def wedge(im, frac):
        m = Image.new('L', (N, N), 0)
        ImageDraw.Draw(m).pieslice([-N, -N, 2 * N, 2 * N], -90, -90 + 360 * frac, fill=255)
        out = im.copy(); out.putalpha(Image.composite(im.getchannel('A'), Image.new('L', (N, N), 0), m)); return out
    comp.alpha_composite(wedge(tga('swipe_inner'), .3)); comp.alpha_composite(wedge(tga('swipe_track'), .3))
    tiles.append(('composed', comp))
    font = ImageFont.truetype(os.path.join(HERE, 'OmashuRing.ttf'), N)
    gl = Image.new('RGBA', (N, N), (90, 90, 96, 255)); dr = ImageDraw.Draw(gl)
    dr.text((N / 2, N / 2), 'O', font=font, fill=(255, 240, 176, 255), anchor='mm')
    dr.line([(N / 2, 0), (N / 2, N)], fill=(255, 0, 0, 120)); dr.line([(0, N / 2), (N, N / 2)], fill=(255, 0, 0, 120))
    tiles.append(('font O (FreeType)', gl))
    sheet = Image.new('RGBA', ((N + 10) * 5, (N + 30) * 2), (30, 30, 30, 255))
    d = ImageDraw.Draw(sheet)
    for k, (nm, im) in enumerate(tiles):
        x, y = (k % 5) * (N + 10), (k // 5) * (N + 30)
        sheet.paste(im, (x, y + 20)); d.text((x + 4, y + 4), nm, fill=(230, 230, 230, 255))
    sheet.save(os.path.join(outdir, 'omashuplates_preview.png'))
    print('font metrics (ascent, descent):', font.getmetrics(), ' glyph bbox at 256px:', font.getbbox('O'))


if __name__ == '__main__':
    for nm, fn in TEXTURES.items():
        write_tga(os.path.join(HERE, nm + '.tga'), render(fn))
    make_font(os.path.join(HERE, 'OmashuRing.ttf'))
    print('wrote', ', '.join(n + '.tga' for n in TEXTURES), 'and OmashuRing.ttf')
    if '--preview' in sys.argv:
        preview(sys.argv[sys.argv.index('--preview') + 1])
