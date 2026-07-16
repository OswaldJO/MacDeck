#!/usr/bin/env bash
# Regenerate Mac + companion app icons from assets/app-icon-source.png (1024×1024).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASTER="$ROOT/assets/app-icon-source.png"

if [[ ! -f "$MASTER" ]]; then
  echo "Missing $MASTER — add a 1024×1024 PNG first." >&2
  exit 1
fi

resize() {
  sips -z "$1" "$1" "$MASTER" --out "$2" >/dev/null
}

MAC_ICON="$ROOT/GBear/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$MAC_ICON"
resize 16 "$MAC_ICON/icon_16x16.png"
resize 32 "$MAC_ICON/icon_16x16@2x.png"
resize 32 "$MAC_ICON/icon_32x32.png"
resize 64 "$MAC_ICON/icon_32x32@2x.png"
resize 128 "$MAC_ICON/icon_128x128.png"
resize 256 "$MAC_ICON/icon_128x128@2x.png"
resize 256 "$MAC_ICON/icon_256x256.png"
resize 512 "$MAC_ICON/icon_256x256@2x.png"
resize 512 "$MAC_ICON/icon_512x512.png"
resize 1024 "$MAC_ICON/icon_512x512@2x.png"

IOS_ICON="$ROOT/companion_app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
resize 20 "$IOS_ICON/Icon-App-20x20@1x.png"
resize 40 "$IOS_ICON/Icon-App-20x20@2x.png"
resize 60 "$IOS_ICON/Icon-App-20x20@3x.png"
resize 29 "$IOS_ICON/Icon-App-29x29@1x.png"
resize 58 "$IOS_ICON/Icon-App-29x29@2x.png"
resize 87 "$IOS_ICON/Icon-App-29x29@3x.png"
resize 40 "$IOS_ICON/Icon-App-40x40@1x.png"
resize 80 "$IOS_ICON/Icon-App-40x40@2x.png"
resize 120 "$IOS_ICON/Icon-App-40x40@3x.png"
resize 120 "$IOS_ICON/Icon-App-60x60@2x.png"
resize 180 "$IOS_ICON/Icon-App-60x60@3x.png"
resize 76 "$IOS_ICON/Icon-App-76x76@1x.png"
resize 152 "$IOS_ICON/Icon-App-76x76@2x.png"
resize 167 "$IOS_ICON/Icon-App-83.5x83.5@2x.png"
resize 1024 "$IOS_ICON/Icon-App-1024x1024@1x.png"

ANDROID_RES="$ROOT/companion_app/android/app/src/main/res"
resize 48 "$ANDROID_RES/mipmap-mdpi/ic_launcher.png"
resize 72 "$ANDROID_RES/mipmap-hdpi/ic_launcher.png"
resize 96 "$ANDROID_RES/mipmap-xhdpi/ic_launcher.png"
resize 144 "$ANDROID_RES/mipmap-xxhdpi/ic_launcher.png"
resize 192 "$ANDROID_RES/mipmap-xxxhdpi/ic_launcher.png"

echo "App icons regenerated from $MASTER"
