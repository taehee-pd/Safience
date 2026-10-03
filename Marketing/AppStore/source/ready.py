"""Exit 0 when a capture shows its page drawn: python3 ready.py <png> <mode>"""
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB"); mode = sys.argv[2]
def count(box, test, step=8):
    x0, y0, x1, y1 = box; n = 0
    for x in range(x0, x1, step):
        for y in range(y0, y1, step):
            if test(im.getpixel((x, y))): n += 1
    return n
yellow = lambda p: p[0] > 230 and 180 < p[1] < 225 and p[2] < 110
dark = lambda p: sum(p) < 120
if mode == "hero": ok = count((300, 300, 2000, 1400), yellow) > 300
elif mode == "split": ok = count((0, 300, 1100, 1300), yellow) > 150 and count((1200, 300, 2000, 700), dark) > 40
elif mode == "client": ok = count((0, 300, 2064, 2000), lambda p: 40 < p[0] < 60 and 40 < p[1] < 60) > 2000
elif mode == "start": ok = count((200, 300, 1900, 900), yellow) > 20
else: ok = False
sys.exit(0 if ok else 1)
