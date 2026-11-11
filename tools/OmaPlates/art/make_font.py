# Builds OmashuRing.ttf with fontTools (a standard, valid TrueType file: WoW refused the hand-packed one).
# Same geometry as make_art.py's make_font: one glyph "O" = the colour ring, em 1024, advance 512,
# ring centred on the baseline (ascent = descent = half an em). Run with a Python that has fontTools:
#   python -m venv v && v/bin/pip install fonttools && v/bin/python make_font.py
import math, os, importlib.util
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('art', os.path.join(HERE, 'make_art.py'))
art = importlib.util.module_from_spec(spec); spec.loader.exec_module(art)   # only for RING_R / RING_W / EM / ADV
EM, ADV = art.EM, art.ADV
def circle(pen, cx, cy, r, clockwise, n=32):
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n * (-1 if clockwise else 1)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    pen.moveTo(pts[0])
    for i in range(1, n + 1):          # quadratic through midpoints keeps it smooth
        p = pts[i % n]; q = pts[(i - 1) % n]
        rc = r / math.cos(math.pi / n); a = (2 * math.pi * (i - .5) / n) * (-1 if clockwise else 1)
        pen.qCurveTo((cx + rc * math.cos(a), cy + rc * math.sin(a)), p)
    pen.closePath()
pen = TTGlyphPen(None)
circle(pen, ADV / 2, 0, (art.RING_R + art.RING_W / 2) * EM, clockwise=True)
circle(pen, ADV / 2, 0, (art.RING_R - art.RING_W / 2) * EM, clockwise=False)
ring = pen.glyph()
empty = TTGlyphPen(None).glyph()
fb = FontBuilder(EM, isTTF=True)
fb.setupGlyphOrder(['.notdef', 'space', 'O'])
fb.setupCharacterMap({0x20: 'space', 0x4F: 'O'})
fb.setupGlyf({'.notdef': empty, 'space': empty, 'O': ring})
fb.setupHorizontalMetrics({'.notdef': (ADV, 0), 'space': (ADV, 0), 'O': (ADV, ring.xMin)})
fb.setupHorizontalHeader(ascent=EM // 2, descent=-EM // 2)
fb.setupNameTable({'familyName': 'OmashuRing', 'styleName': 'Regular'})
fb.setupOS2(sTypoAscender=EM // 2, sTypoDescender=-EM // 2, usWinAscent=EM // 2, usWinDescent=EM // 2)
fb.setupPost()
fb.save(os.path.join(HERE, 'OmashuRing.ttf'))
print('wrote OmashuRing.ttf', ring.xMin, ring.yMin, ring.xMax, ring.yMax)
