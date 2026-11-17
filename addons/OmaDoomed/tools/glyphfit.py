# tools/glyphfit.py: fit circles to the /omadoomed glyph test (band art blue, raw glyph red) in a screen capture.
# Usage: python tools/glyphfit.py <capture.png|jpg>; edit the boxes list to where the three test pairs are.
# Least-squares circle fit (Kasa) of the ring art (blue) and the ring-font glyph (red) in the 19:40 /omadoomed glyph
# capture, at the three sizes. Prints each ring's centre and radius, the glyph/art size ratio and the centre offset
# as a fraction of the box size.
import sys
import numpy as np
from PIL import Image
im = np.asarray(Image.open(sys.argv[1]).convert('RGB')).astype(int)
boxes = [(768, 361, 866, 459, 128), (653, 385, 701, 433, 64), (547, 397, 575, 425, 34)]
def fit(mask, x0, y0):
    ys, xs = np.nonzero(mask)
    xs = xs + x0; ys = ys + y0
    A = np.c_[2 * xs, 2 * ys, np.ones(len(xs))]
    b = xs ** 2 + ys ** 2
    (cx, cy, c), *_ = np.linalg.lstsq(A, b, rcond=None)
    r = np.sqrt(c + cx ** 2 + cy ** 2)
    res = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2) - r
    return cx, cy, r, len(xs), res.std()
for x0, y0, x1, y1, size in boxes:
    sub = im[y0:y1, x0:x1]
    R, G, B = sub[..., 0], sub[..., 1], sub[..., 2]
    blue = (B > 150) & (R < 120)            # art band (where the red glyph doesn't cover it)
    red = (R > 150) & (G < 90) & (B < 110)  # glyph band (red over background)
    px = (x1 - x0)                           # the box (size + 2 px border at this capture scale)
    bc = fit(blue, x0, y0); rc = fit(red, x0, y0)
    print(f'size {size}: box {px}px | art c=({bc[0]:.2f},{bc[1]:.2f}) r={bc[2]:.2f} n={bc[3]} sd={bc[4]:.2f} | '
          f'glyph c=({rc[0]:.2f},{rc[1]:.2f}) r={rc[2]:.2f} n={rc[3]} sd={rc[4]:.2f}')
    print(f'   ratio glyph/art = {rc[2] / bc[2]:.4f}; centre offset dx = {(rc[0] - bc[0]) / bc[2] / 2 * 0.9305:.4f} of size, '
          f'dy = {(rc[1] - bc[1]) / bc[2] / 2 * 0.9305:.4f} of size')
