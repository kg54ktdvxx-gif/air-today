"""Checks a header PNG against Apple's API spec i3840x1646a0 and measures white-text contrast on its background."""
import sys, os, re, struct
from PIL import Image
path, bgpath, blocktxt = sys.argv[1:]
im = Image.open(path)
ok = lambda b: "PASS" if b else "FAIL"
print(f"== {os.path.basename(path)}")
print(f"  dimensions {im.size}: {ok(im.size == (3840, 1646))}")
print(f"  format {im.format}: {ok(im.format == 'PNG')}  (API spec lists image/png only)")
print(f"  mode {im.mode}, alpha channel: {ok('A' not in im.mode and im.info.get('transparency') is None)}")
# Colour: either an iCCP profile naming sRGB, or PNG's own sRGB chunk (which ImageIO writes).
raw = open(path, "rb").read()
chunks, i = set(), 8
while i < len(raw):
    n, = struct.unpack(">I", raw[i:i + 4]); chunks.add(raw[i + 4:i + 8].decode()); i += 12 + n
icc = im.info.get("icc_profile")
srgb = "sRGB" in chunks or (bool(icc) and b"sRGB" in icc)
print(f"  colour space declared sRGB ({'sRGB chunk' if 'sRGB' in chunks else 'ICC profile' if icc else 'nothing'}): {ok(srgb)}")
size = os.path.getsize(path)
print(f"  file size {size/1e6:.1f} MB (limit 524.3 MB): {ok(size <= 524288000)}")
m = re.search(r"x (\d+)–(\d+), y (\d+)–(\d+); inside safe area: (\w+)", open(blocktxt).read())
x0, x1, y0, y1 = map(int, m.groups()[:4])
print(f"  text ink box x {x0}-{x1}, y {y0}-{y1}; inside safe area 1097-2743 x 493-1154: {ok(m.group(5) == 'true')}"
      f"  (margins L{x0-1097} R{2743-x1} T{y0-493} B{1154-y1})")
bg = Image.open(bgpath).convert("RGB").crop((x0, y0, x1, y1))
def lum(c):
    c = [v / 255 for v in c]
    c = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
px = list(bg.getdata())[::7]
ls = sorted(lum(p) for p in px)
mean = sum(ls) / len(ls); p95 = ls[int(len(ls) * 0.95)]
cr = lambda L: 1.05 / (L + 0.05)
print(f"  white text on background, before text shadow: mean {cr(mean):.2f}:1, brightest 5% {cr(p95):.2f}:1"
      f"  (WCAG large text 3:1: {ok(cr(mean) >= 3)})")
