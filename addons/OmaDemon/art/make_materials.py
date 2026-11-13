# OmaDemon edge looks as MATERIALS of Blizzard's edge band (2026-11-13 interview): the band stays the same shape
# (edge.png's alpha); a look changes what it is made of and how that moves. Everything is drawn white (alpha only)
# so the game tints it with the Warning colour, and every texture tiles, so the game can scroll it under a mask.
#   noise_soft.png  - large, soft fbm (smoke body, smoulder base)        512x512, tiles
#   noise_fine.png  - finer fbm, taller than wide (flame tongues)        512x512, tiles
#   streaks.png     - long soft streaks along one axis (soul drain)       256x512, tiles
#   band.png        - the edge band's own alpha (from edge.png), white   1024x576
#   rim.png         - just the outermost part of the band, white         1024x576
# Run: python -I make_materials.py <outdir>
import sys, os
import numpy as np
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else '.'
HERE = os.path.dirname(os.path.abspath(__file__))
rng = np.random.default_rng(66)

def fbm(w, h, power, lo=0, hi=None, stretch=(1, 1)):
    # tileable noise from a random spectrum with a 1/f^power falloff (periodic by construction)
    fy = np.fft.fftfreq(h)[:, None] * stretch[1]; fx = np.fft.fftfreq(w)[None, :] * stretch[0]
    f = np.sqrt(fx * fx + fy * fy); f[0, 0] = 1
    amp = 1 / f ** power
    if hi: amp[f > hi] = 0
    amp[f < lo] = 0
    spec = amp * np.exp(2j * np.pi * rng.random((h, w)))
    n = np.real(np.fft.ifft2(spec)); n -= n.min(); n /= n.max()
    return n

def white(alpha):
    a = (np.clip(alpha, 0, 1) * 255).astype('uint8'); h, w = a.shape
    im = Image.new('RGBA', (w, h), (255, 255, 255, 0)); im.putalpha(Image.fromarray(a)); return im

os.makedirs(OUT, exist_ok=True)
soft = fbm(512, 512, 1.6, lo=1 / 256, hi=1 / 18); white(np.clip((soft - .25) / .6, 0, 1) ** 1.4).save(os.path.join(OUT, 'noise_soft.png'))
fine = fbm(512, 512, 1.3, lo=1 / 128, hi=1 / 7, stretch=(1, 2.2)); white(np.clip((fine - .4) / .45, 0, 1) ** 1.8).save(os.path.join(OUT, 'noise_fine.png'))
st = fbm(256, 512, 1.5, lo=1 / 64, hi=1 / 14, stretch=(1, 4)); white(np.clip((st - .5) / .4, 0, 1) ** 1.6).save(os.path.join(OUT, 'streaks.png'))
edge = np.array(Image.open(os.path.join(HERE, 'edge.png')).convert('RGBA')).astype(float)[..., 3] / 255
white(edge).save(os.path.join(OUT, 'band.png'))
white(np.clip((edge - .55) / .4, 0, 1) ** 1.5).save(os.path.join(OUT, 'rim.png'))
print('wrote', OUT)
