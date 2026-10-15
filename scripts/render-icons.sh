#!/bin/bash
# Renders the app icon and in-app seal from Assets/*.svg (needs librsvg2-bin: rsvg-convert).
set -euo pipefail
cd "$(dirname "$0")/.."

rsvg-convert -w 1024 -h 1024 Assets/AppIcon.svg -o Resources/AppIcon.png
rsvg-convert -w 180 -h 180 Assets/AppIcon.svg -o Resources/AppIcon60x60@3x.png
rsvg-convert -w 120 -h 120 Assets/AppIcon.svg -o Resources/AppIcon60x60@2x.png
rsvg-convert -w 240 -h 240 Assets/Seal.svg -o Resources/Seal.png
rsvg-convert -w 524 -h 460 Assets/Glyph.svg -o Resources/Glyph.png
