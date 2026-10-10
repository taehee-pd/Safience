"""The Duo's outer screen from iPhone captures: python3 duo-outer.py
There is no Duo simulator yet. The outer screen (1398 by 2034) shows Safience's phone layout like an
iPhone, only shorter, so each picture is the iPhone capture cut to the shorter screen, with the
iPhone's bar laid over the bottom and the Dynamic Island painted out. The bar's blur begins 24
points above it, over page that on the iPhone is further down than it is here; so those points are
this page's own, blurred more and more on the way down, and the iPhone's strip fades in over them,
itself blurred there so that its page does not show through as a ghost."""
from PIL import Image, ImageDraw, ImageFilter
BAR = 2382          # where the phone bar's blur starts in a 1320 by 2868 capture: 24 points above the bar (104), the home indicator's 34 below
FADE = 72           # those 24 points
CAPSULE = 90        # where the address capsule begins in the strip
H = round(1320 * 2034 / 1398)
STRIP = 2868 - BAR
W = 1320

def ramp(y0, y1, height):
    """A mask that is 0 above y0, 1 below y1, and rises between them."""
    mask = Image.new("L", (W, height), 0)
    draw = ImageDraw.Draw(mask)
    for y in range(y0, height):
        draw.line((0, y, W, y), fill=255 if y >= y1 else round(255 * (y - y0) / (y1 - y0)))
    return mask

for name in ("6-notes", "3-client", "5-start"):
    src = Image.open(f"raw-iphone/{name}.png").convert("RGB")
    out = src.crop((0, 0, W, H))
    page = out.crop((0, H - STRIP, W, H))
    # The page under the strip, blurred in three steps over the 24 points.
    for i, radius in enumerate((4, 9, 14)):
        page = Image.composite(page.filter(ImageFilter.GaussianBlur(radius)), page, ramp(i * FADE // 3, (i + 1) * FADE // 3, STRIP))
    strip = src.crop((0, BAR, W, 2868))
    # The iPhone's page shows through the top of its bar too, down to the address capsule
    # (90 px into the strip); blurred there, it is a haze rather than another page's words.
    haze = ramp(CAPSULE - 8, CAPSULE, STRIP).point(lambda v: 255 - v)
    strip = Image.composite(strip.filter(ImageFilter.GaussianBlur(16)), strip, haze)
    page.paste(strip, (0, 0), ramp(0, FADE, STRIP))
    out.paste(page, (0, H - STRIP))
    ImageDraw.Draw(out).rectangle((440, 30, 880, 165), fill=src.getpixel((660, 20)))
    out.save(f"raw-duo/outer-{name}.png")
    print(name, out.size)
