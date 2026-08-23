"""Precompute dominant background colors for expand-mode camera fill.

Decodes every stage .astc with tools/bin/astcenc, samples the dominant
color (same stepped algorithm as Stage.sampleDominantColor), and writes
assets/embeds/data/expandBgColors.json keyed by the runtime graphic.key
(assets/images/....png). Re-run whenever stage backgrounds change.
Stores 0xRRGGBB (no alpha) to stay within Haxe's signed 32-bit Int.
"""
import os, subprocess, json, glob, tempfile
from PIL import Image
from collections import Counter

import pathlib
ROOT = str(pathlib.Path(__file__).resolve().parent.parent)
ASTCENC = os.path.join(ROOT, 'tools/bin/astcenc-avx2')

def runtime_key(repo_path):
    # repo assets/legacy/images/... or assets/embeds/images/... or assets/game/images/...
    # -> runtime 'assets/images/....png' (Project.xml renames legacy/embeds/game -> assets)
    p = repo_path
    for pref in ('assets/legacy/', 'assets/embeds/', 'assets/game/'):
        if p.startswith(pref):
            p = 'assets/' + p[len(pref):]
            break
    if p.endswith('.astc'): p = p[:-5] + '.png'
    return p

def dominant(img):
    img = img.convert('RGBA')
    w, h = img.size
    px = img.load()
    stepx = max(1, w // 100)
    stepy = max(1, h // 100)
    cnt = Counter()
    x = 0
    while x < w:
        y = 0
        while y < h:
            r, g, b, a = px[x, y]
            if a / 255.0 > 0.05:
                cnt[(r, g, b)] += 1
            y += stepy
        x += stepx
    if not cnt: return None
    # never pick pure black (matches runtime: it seeds BLACK count 0 then >=)
    cnt[(0, 0, 0)] = 0
    (r, g, b), c = max(cnt.items(), key=lambda kv: kv[1])
    if c <= 0: return None
    return (r << 16) | (g << 8) | b

# All stage images (astc + any png), under images/stages/
files = []
for base in ('assets/legacy', 'assets/embeds', 'assets/game'):
    files += glob.glob(os.path.join(ROOT, base, 'images/stages/**/*.astc'), recursive=True)

out = {}
done = 0
for f in sorted(files):
    rel = os.path.relpath(f, ROOT)
    key = runtime_key(rel)
    try:
        with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp:
            tmpname = tmp.name
        r = subprocess.run([ASTCENC, '-ds', f, tmpname], capture_output=True, timeout=60)
        if r.returncode != 0 or not os.path.exists(tmpname):
            continue
        col = dominant(Image.open(tmpname))
        os.unlink(tmpname)
        if col is not None:
            out[key] = col
            done += 1
    except Exception as e:
        pass

os.makedirs(os.path.join(ROOT, 'assets/embeds/data'), exist_ok=True)
dst = os.path.join(ROOT, 'assets/embeds/data/expandBgColors.json')
with open(dst, 'w') as fh:
    json.dump(out, fh, separators=(',', ':'), sort_keys=True)
print(f'wrote {done} colors to {dst}, size={os.path.getsize(dst)} bytes')
