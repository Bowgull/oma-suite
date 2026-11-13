# Soul crystal look: paint the iron claw (the cradle under each crystal) in the pet frame's border brass, light on
# its top edge (sheet 47 C, approved 2026-11-13 "yes build it ... the optical center and brass").
# Reads OmashuShards-crystal-iron.png (the original art, kept), writes OmashuShards-crystal.png + .tga.
# Safe to run twice. Run: python -I make_brass.py
from PIL import Image, ImageDraw
import os
SRC = 'OmashuShards-crystal-iron.png'
if not os.path.exists(SRC):
    os.replace('OmashuShards-crystal.png', SRC); print('kept the original as', SRC)
sheet = Image.open(SRC).convert('RGBA')
L, T, R, B = 80, 0, 160, 96                    # the empty socket cell (Shards.lua CELL.empty); lit gems sit on it
POLY = [(40, 2), (23, 30), (23, 64), (40, 90), (57, 64), (57, 30)]   # the crystal inside the cell
LO, HI, RIM = (60, 40, 18), (176, 134, 72), (226, 186, 116)
inside = Image.new('L', (R - L, B - T), 0); ImageDraw.Draw(inside).polygon(POLY, fill=255)
claw = set()
for y in range(58, B - T):
    for x in range(R - L):
        if sheet.getpixel((L + x, T + y))[3] > 20 and not inside.getpixel((x, y)): claw.add((x, y))
for (x, y) in claw:
    r, g, b, a = sheet.getpixel((L + x, T + y)); l = min(1, (r + g + b) / 3 / 90)
    open_above = y == 0 or sheet.getpixel((L + x, T + y - 1))[3] < 20     # light only on the claw's outer top edge
    col = RIM if open_above else tuple(int(LO[i] + (HI[i] - LO[i]) * l) for i in range(3))
    sheet.putpixel((L + x, T + y), col + (a,))
sheet.save('OmashuShards-crystal.png'); sheet.save('OmashuShards-crystal.tga')
print('brass claw pixels:', len(claw))
