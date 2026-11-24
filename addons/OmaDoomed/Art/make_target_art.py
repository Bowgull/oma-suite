#!/usr/bin/env python3
# OmaDoomed mob list: your target's mark (sheet 119, Joshua 2026-11-19: "A + B").
# Run: python -I make_target_art.py   (writes next to this file; needs Pillow)
#
# Every number is the sheet's, in list-local pixels at scale 1 (a row is 348 x 44, top-left = 0,0):
#   A  gold frame round the whole row: rounded rectangle 1,1 .. 347,43, corner radius 8, line 2 px (drawn inward);
#      its glow: rounded rectangle -1,-1 .. 349,45, radius 10, line 5 px at alpha 150/255, Gaussian blur 3 px.
#      Both textures cover x -11 .. 359 and y -10 .. 54 (370 x 64), placed in a 512 x 64 texture from x 0.
#      White, tinted in game with Blizzard's target gold (1, .82, 0).
#   B  arrow left of the face: points (-16,11) (2,22) (-16,33) (-10,22), Blizzard gold (255,209,0) with a dark
#      (90,60,0) edge, on a glow = the same arrow blurred 3 px. Covers x -23 .. 9, y 6 .. 38 (32 x 32). Baked colour.
# Drawn at 4x and box-filtered down, as on the sheet.
import os, struct
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
S = 4


def write_tga(path, im):
    # type 2, 32 bpp, 8 alpha bits, bottom-left origin (the same flavour as the other Art\*.tga)
    w, h = im.size
    out = bytearray(struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x08))
    px = im.load()
    for y in range(h - 1, -1, -1):
        for x in range(w):
            r, g, b, a = px[x, y]
            out += bytes((b, g, r, a))
    with open(path, 'wb') as f:
        f.write(out)


def frame_textures():
    X0, Y0, W, H = -11, -10, 370, 64
    def P(x, y): return ((x - X0) * S, (y - Y0) * S)
    line = Image.new('RGBA', (W * S, H * S), (255, 255, 255, 0))
    ImageDraw.Draw(line).rounded_rectangle([*P(1, 1), *P(347, 43)], radius=8 * S, outline=(255, 255, 255, 255), width=2 * S)
    line = line.resize((W, H), Image.LANCZOS)
    glow = Image.new('RGBA', (W * S, H * S), (255, 255, 255, 0))
    ImageDraw.Draw(glow).rounded_rectangle([*P(-1, -1), *P(349, 45)], radius=10 * S, outline=(255, 255, 255, 150), width=5 * S)
    glow = glow.resize((W, H), Image.LANCZOS).filter(ImageFilter.GaussianBlur(3))
    for name, im in (('list_tgtframe', line), ('list_tgtglow', glow)):
        tex = Image.new('RGBA', (512, 64), (255, 255, 255, 0))
        a = im.split()[3]
        tex.paste(Image.merge('RGBA', (*[Image.new('L', im.size, 255)] * 3, a)), (0, 0))
        write_tga(os.path.join(HERE, name + '.tga'), tex)


def arrow_texture():
    X0, Y0, W, H = -23, 6, 32, 32
    def P(x, y): return ((x - X0) * S, (y - Y0) * S)
    a = Image.new('RGBA', (W * S, H * S), (0, 0, 0, 0))
    ImageDraw.Draw(a).polygon([P(-16, 11), P(2, 22), P(-16, 33), P(-10, 22)], fill=(255, 209, 0, 255), outline=(90, 60, 0, 255))
    a = a.resize((W, H), Image.LANCZOS)
    out = a.filter(ImageFilter.GaussianBlur(3))
    out.alpha_composite(a)
    write_tga(os.path.join(HERE, 'list_tgtarrow.tga'), out)


if __name__ == '__main__':
    frame_textures()
    arrow_texture()
    print('wrote list_tgtframe.tga, list_tgtglow.tga, list_tgtarrow.tga')
