#!/bin/zsh
# Fetches Apple's pictures of the devices the frames are drawn in, from the
# Apple Design Resources (developer.apple.com/design/resources, Product
# Bezels), into bezels/, which git leaves out: Apple's licence lets them be
# used in mock-ups of software for Apple's platforms, which the App Store
# pictures are, and not passed on. The screen's place in each picture is in
# the frames files (hole), measured from the picture's transparent screen.
set -e
here=${0:A:h}
mkdir -p $here/bezels
tmp=$(mktemp -d)
fetch() {  # fetch <dmg name> <volume> <file in the dmg's PNG folder> <name here>
  local dmg=$tmp/$1.dmg
  [[ -f $dmg ]] || curl -sSL -o $dmg "https://devimages-cdn.apple.com/design/resources/download/Bezel-$1.dmg"
  # The disk image asks you to accept the licence as it opens: read it in the image.
  local volume=$(yes | hdiutil attach -nobrowse -readonly -noautoopen $dmg 2>/dev/null | grep -o '/Volumes/.*' | tail -1)
  cp "$volume/PNG/$3" $here/bezels/$4
  hdiutil detach "$volume" -quiet
  echo "bezels/$4"
}
fetch iPhone-17 Bezel-iPhone-17 "iPhone 17 Pro Max/iPhone 17 Pro Max - Silver - Portrait.png" promax-silver.png
fetch iPhone-17 Bezel-iPhone-17 "iPhone 17 Pro Max/iPhone 17 Pro Max - Deep Blue - Portrait.png" promax-blue.png
fetch "iPad-Pro-(M5)" "Bezel-iPad-Pro-(M5)" 'iPad Pro (M5) 13" - Silver - Portrait.png' ipad13-silver.png
fetch "iPad-Pro-(M5)" "Bezel-iPad-Pro-(M5)" 'iPad Pro (M5) 13" - Space Black - Portrait.png' ipad13-black.png
fetch iPhone-Duo Bezel-iPhone-Duo "iPhone Duo - Star White - Inner Open Portrait.png" duo-inner-white.png
fetch iPhone-Duo Bezel-iPhone-Duo "iPhone Duo - Star White - Outer Closed Portrait.png" duo-outer-white.png
fetch iPhone-Duo Bezel-iPhone-Duo "iPhone Duo - Night Sky - Inner Open Portrait.png" duo-inner-night.png
fetch iPhone-Duo Bezel-iPhone-Duo "iPhone Duo - Night Sky - Outer Closed Portrait.png" duo-outer-night.png
rm -rf $tmp
