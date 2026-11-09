#!/usr/bin/env python3
"""Decode the Omashu chat strip from a screenshot (test for the pixel strip; see OmashuChatLog.lua).
   python3 -I wow-addon/strip_decode.py shot.png
Reads the bottom-left of the screen: 4x2-pixel blocks, magenta then cyan, then 6 bits per block."""
import sys
from PIL import Image

W, H = 4, 2
img = Image.open(sys.argv[1]).convert('RGB')
w, h = img.size
y = h - 1  # bottom row; sample the middle of each block horizontally
def px(i): return img.getpixel((i * W + W // 2, y))
def lvl(v): return min(3, round(v / 85))
a, b = px(0), px(1)
print('start blocks:', a, b)
if not (a[0] > 200 and a[1] < 60 and a[2] > 200 and b[0] < 60 and b[1] > 200 and b[2] > 200):
    sys.exit('no strip found')
bits, raw, i, worst = '', [], 2, 0
while i * W < w:
    c = px(i)
    worst = max(worst, *(abs(v - lvl(v) * 85) for v in c))
    bits += ''.join(format(lvl(v), '02b') for v in c)
    i += 1
    if len(bits) >= 8:
        n = int(bits[:8], 2)
        if len(bits) >= 8 * (n + 1):
            break
n = int(bits[:8], 2)
data = bytes(int(bits[8 + 8 * k: 16 + 8 * k], 2) for k in range(n))
print('length:', n, 'bytes; strip width:', i * W, 'px; worst colour error:', worst, '(of 42 allowed)')
print('decoded:', data.decode('utf-8', errors='replace'))
