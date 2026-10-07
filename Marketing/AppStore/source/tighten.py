"""Takes the waiting out of a screen recording: the stretches where nothing
moves are cut down to a short hold, and the motion stays at its own pace.
    python3 tighten.py <in.mov> <out.mov> [hold seconds, 0.7] [max seconds, 30]
Every frame is compared with the one before (small, grey); frames within
`hold` seconds of a change stay, the rest go. Prints what stays and how long
it adds up to. Needs ffmpeg and Pillow."""
import os, subprocess, sys, tempfile
from PIL import Image, ImageChops

src, out = sys.argv[1], sys.argv[2]
hold = float(sys.argv[3]) if len(sys.argv) > 3 else 0.7
longest = float(sys.argv[4]) if len(sys.argv) > 4 else 30
fps = 30
tmp = tempfile.mkdtemp()
subprocess.run(["ffmpeg", "-v", "error", "-i", src, "-vf", f"fps={fps},scale=120:-1,format=gray", f"{tmp}/%05d.png"], check=True)
frames = sorted(os.listdir(tmp))
moving = []
last = None
for name in frames:
    image = Image.open(f"{tmp}/{name}")
    if last is not None:
        diff = ImageChops.difference(image, last)
        # The mean difference over the frame; a cursor moving is enough.
        moving.append(sum(diff.getdata()) / (diff.width * diff.height) > 0.6)
    else:
        moving.append(False)
    last = image
keep = [False] * len(moving)
pad = int(hold * fps)
for i, m in enumerate(moving):
    if m:
        for j in range(max(0, i - pad), min(len(keep), i + pad + 1)):
            keep[j] = True
# The first moment stays, as the picture the preview opens on.
for j in range(min(len(keep), pad)):
    keep[j] = True
segments = []
start = None
for i, k in enumerate(keep + [False]):
    if k and start is None:
        start = i
    elif not k and start is not None:
        segments.append((start, i))
        start = None
total = sum(b - a for a, b in segments) / fps
print(f"{len(frames)} frames, {len(frames) / fps:.1f} s; kept {len(segments)} stretches, {total:.1f} s")
for a, b in segments:
    print(f"  {a / fps:6.2f} to {b / fps:6.2f} s")
if total > longest:
    print(f"over {longest} s: cut some, or hold less")
select = "+".join(f"between(n,{a},{b - 1})" for a, b in segments)
subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", src, "-vf", f"fps={fps},select='{select}',setpts=N/{fps}/TB",
                "-an", "-c:v", "libx264", "-crf", "16", "-pix_fmt", "yuv420p", out], check=True)
for name in frames:
    os.remove(f"{tmp}/{name}")
os.rmdir(tmp)
