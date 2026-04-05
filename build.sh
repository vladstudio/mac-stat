#!/bin/bash
set -e
cd "$(dirname "$0")"
source ../mac-scripts/build-kit.sh
build_app "Stat" \
  --info app/Stat/Info.plist \
  --resources "icons/cpu.png icons/gpu.png icons/download-k.png icons/download-m.png icons/upload-k.png icons/upload-m.png fonts/Oswald-Light.ttf"
