"""The Duo's inner screen from iPad Pro 11-inch captures: python3 duo-inner.py
There is no Duo simulator yet. Unfolded, the Duo is wide enough for Safience's iPad layout, so the
inner pictures are the iPad Pro 11-inch simulator's (frame.html crops them to the Duo's shape). That
simulator's status bar gives Oct 3 the wrong weekday, so the clock and date are redrawn from the
13-inch capture of the same shot, which has them right: its text as a mask, on this capture's own
background."""
from PIL import Image
PAIRS = [("1-hero", "1-hero"), ("2-split", "2-split"), ("3-client", "3-client"), ("4-palette", "5-palette"), ("5-start", "4-start")]
BOX = (30, 6, 480, 58)  # the clock, the date and the app's name, on the left of both status bars
for duo, ipad in PAIRS:
    a = Image.open(f"raw-duo/inner-{duo}.png").convert("RGB")
    b = Image.open(f"raw/{ipad}.png").convert("RGB")
    here, there = a.getpixel((5, 5)), b.getpixel((5, 5))
    ink = (0, 0, 0) if sum(there) > 384 else (255, 255, 255)
    for x in range(BOX[0], BOX[2]):
        for y in range(BOX[1], BOX[3]):
            p = b.getpixel((x, y))
            k = max(0.0, min(1.0, sum(abs(p[c] - there[c]) for c in range(3)) / max(1, sum(abs(ink[c] - there[c]) for c in range(3)))))
            a.putpixel((x, y), tuple(round(here[c] + (ink[c] - here[c]) * k) for c in range(3)))
    a.save(f"raw-duo/inner-{duo}.png")
    print(duo, here, there)
