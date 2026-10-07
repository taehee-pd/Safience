#!/bin/zsh
# A simulator recording as App Store Connect takes an app preview:
#     preview.sh <recording.mov> <out.mp4> iphone|ipad [start seconds] [length seconds]
# 30 frames a second, H.264 at about 10 Mb/s, and a silent stereo AAC
# track, which App Store Connect requires even of a silent preview. The
# iPhone 6.9-inch size is 886 by 1920: the capture's 1320 by 2868 scaled to
# the width, which leaves 5 rows over, cut from the top and the bottom. The
# iPad 13-inch size is 1200 by 1600, the capture's own shape. A preview
# runs 15 to 30 seconds.
set -e
in=$1; out=$2; kind=$3; start=${4:-0}; length=${5:-30}
case $kind in
  iphone) filter="scale=886:1925:flags=lanczos,crop=886:1920:0:2" ;;
  ipad) filter="scale=1200:1600:flags=lanczos" ;;
  *) echo "usage: preview.sh <recording.mov> <out.mp4> iphone|ipad [start] [length]" >&2; exit 1 ;;
esac
ffmpeg -y -loglevel error -ss $start -t $length -i $in \
  -f lavfi -t $length -i anullsrc=channel_layout=stereo:sample_rate=48000 \
  -vf "$filter,fps=30,format=yuv420p" -c:v libx264 -profile:v high -b:v 10M -maxrate 12M -bufsize 20M \
  -c:a aac -b:a 256k -ar 48000 -shortest -movflags +faststart $out
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate:format=duration -of default=nw=1 $out
