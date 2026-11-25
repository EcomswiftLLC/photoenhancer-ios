#!/bin/bash
# Screenshots of every debug screen and the store captures on one booted simulator. Usage: take-shots.sh <device id>
DEST="$1"
xcrun simctl boot "$DEST" || true
xcrun simctl bootstatus "$DEST" -b || true
xcrun simctl ui "$DEST" appearance dark || true
APP=$(find build/dd -name Clarivo.app -maxdepth 6 | head -1)
xcrun simctl install "$DEST" "$APP"
mkdir -p shots store
for SCREEN in $SCREENS; do
  xcrun simctl terminate "$DEST" "$BUNDLE_ID" || true
  xcrun simctl launch "$DEST" "$BUNDLE_ID" -cvNoAds YES -cvScreen "$SCREEN" || true
  sleep 12
  xcrun simctl io "$DEST" screenshot "shots/$SCREEN.png" || true
done
# A clean status bar (9:41, full battery and signal), as on the store listing.
xcrun simctl status_bar "$DEST" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true
for SHOT in $STORE_SHOTS; do
  xcrun simctl terminate "$DEST" "$BUNDLE_ID" || true
  xcrun simctl launch "$DEST" "$BUNDLE_ID" -cvNoAds YES -cvScreen "shot-$SHOT" || true
  # Real engine output on the CPU simulator: model shots need time.
  sleep 40
  xcrun simctl io "$DEST" screenshot "store/$SHOT.png" || true
done
xcrun simctl status_bar "$DEST" clear || true
ls shots store
