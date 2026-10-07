"""The Duo's outer screen from iPhone captures: python3 duo-outer.py
There is no Duo simulator yet. The outer screen (1398 by 2034) shows Safience's phone layout like an
iPhone, only shorter, so each picture is the iPhone capture's top (status bar and page) above its bar,
the page cut where a shorter screen would cut it, and the iPhone's Dynamic Island painted out."""
from PIL import Image, ImageDraw
BAR = 2490          # where the phone bar starts in a 1320 by 2868 capture (378 px: the bar and the home indicator)
H = round(1320 * 2034 / 1398)
for name in ("6-notes", "3-client", "5-start"):
    src = Image.open(f"raw-iphone/{name}.png").convert("RGB")
    out = Image.new("RGB", (1320, H))
    out.paste(src.crop((0, 0, 1320, H - (2868 - BAR))), (0, 0))
    out.paste(src.crop((0, BAR, 1320, 2868)), (0, H - (2868 - BAR)))
    ImageDraw.Draw(out).rectangle((440, 30, 880, 165), fill=src.getpixel((660, 20)))
    out.save(f"raw-duo/outer-{name}.png")
    print(name, out.size)
