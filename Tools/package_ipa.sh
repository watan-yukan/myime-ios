#!/usr/bin/env bash
# 將 xcodebuild 產出的 .app 以 ad-hoc 簽章（嵌入 App Group entitlements）後打包成 .ipa。
# 之後在 Windows 由 Sideloadly / AltStore 以自己的 Apple ID 重新簽章安裝。
set -euo pipefail

APP="build/Build/Products/Release-iphoneos/MyIME.app"
APPEX="$APP/PlugIns/MyIMEKeyboard.appex"

if [ ! -d "$APPEX" ]; then
  echo "::error::找不到鍵盤擴充 $APPEX"
  exit 1
fi

# 碼表防護（R-LIU-1）：安裝檔內不得含任何 .cin
if find "$APP" -iname '*.cin' | grep -q .; then
  echo "::error::安裝檔內發現 .cin 碼表，停止打包"
  exit 1
fi

# 先簽擴充、再簽主 App；ad-hoc 簽章 (-) 只為了把 entitlements 帶進去，側載工具會再重簽
codesign --force --sign - --entitlements KeyboardExtension/MyIMEKeyboard.entitlements "$APPEX"
codesign --force --sign - --entitlements App/MyIME.entitlements "$APP"
codesign -d --entitlements - "$APPEX"

rm -rf dist
mkdir -p dist/Payload
cp -R "$APP" dist/Payload/
(cd dist && zip -qry MyIME.ipa Payload)
rm -rf dist/Payload

echo "已產生 dist/MyIME.ipa"
ls -lh dist/MyIME.ipa
