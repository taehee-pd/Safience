#!/bin/zsh
# Puts a simulator's app in a shot and captures it once its page is drawn:
# shot.sh <device> <shot> <out.png> [yellow pixels needed]
D=$1; SHOT=$2; OUT=$3; NEED=${4:-300}
here=${0:A:h}
xcrun simctl terminate $D net.taehee.safience 2>/dev/null
C=$(xcrun simctl get_app_container $D net.taehee.safience data)
python3 $here/state.py "$C" $SHOT
# The window opens on the workspace's first space, not the one it was last in.
rm -rf "$C/Library/Saved Application State/net.taehee.safience.savedState"
# The last frame of the app quit before, so a capture of it doesn't pass as this shot.
sleep 8
xcrun simctl launch $D net.taehee.safience >/dev/null
until xcrun simctl io $D screenshot $OUT >/dev/null 2>&1 && python3 -c "
import sys
from PIL import Image
im=Image.open('$OUT').convert('RGB'); w,h=im.size
px=[im.getpixel((x,y)) for x in range(0,w,8) for y in range(200,h-400,8)]
# The canvas's yellow, or for other pages enough that isn't the page's plain background.
n=sum(1 for p in px if p[0]>230 and 180<p[1]<225 and p[2]<110) if $NEED>0 else sum(1 for p in px if sum(p)<600)
sys.exit(0 if n>=max($NEED,1)*(1 if $NEED>0 else 3000) else 1)"; do sleep 4; done
echo captured $SHOT
