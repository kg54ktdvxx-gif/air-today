"""Device-size previews of a 3840x1646 header: the whole frame at iPad 13-inch landscape width (1376 pt),
and the safe area alone at iPhone width (402 pt) as a worst case. Rendered at 2x so the sheet stays sharp."""
import sys
from PIL import Image, ImageDraw, ImageFont
out, *paths = sys.argv[1:]
SAFE = (1097, 493, 2743, 1154)
f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 30)
rows = []
for p in paths:
    im = Image.open(p).convert("RGB")
    ipad = im.resize((1376 * 2 // 2, round(1646 * 1376 / 3840)), Image.LANCZOS)  # 1x pt for the sheet
    phone = im.crop(SAFE).resize((402, round(661 * 402 / 1646)), Image.LANCZOS)
    rows.append((p.rsplit("/", 1)[-1], ipad, phone))
W = 40 + rows[0][1].width + 40 + 402 + 40
H = sum(r[1].height + 80 for r in rows) + 40
sheet = Image.new("RGB", (W, H), (24, 24, 26)); d = ImageDraw.Draw(sheet); y = 40
for name, ipad, phone in rows:
    d.text((40, y), f"{name}   ·   whole frame at iPad landscape width (1376 pt)", fill=(200, 200, 205), font=f)
    d.text((40 + ipad.width + 40, y), "safe area at iPhone width (402 pt)", fill=(200, 200, 205), font=f)
    sheet.paste(ipad, (40, y + 44)); sheet.paste(phone, (40 + ipad.width + 40, y + 44))
    y += ipad.height + 80
sheet.save(out, quality=88)
