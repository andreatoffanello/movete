#!/bin/bash
set -e

RT185="com.apple.CoreSimulator.SimRuntime.iOS-18-5"
IP16="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"

echo "Verifica prerequisiti di sviluppo mobile..."

if ! which idb &>/dev/null; then
  echo "→ Installo idb-companion..."
  brew tap facebook/fb
  brew install facebook/fb/idb-companion
  pip3 install fb-idb
else
  echo "✓ idb già installato"
fi

if ! which maestro &>/dev/null; then
  echo "→ Installo Maestro..."
  curl -Ls "https://get.maestro.mobile.dev" | bash
else
  echo "✓ Maestro già installato"
fi

echo ""
echo "Setup simulatore (movete-dev)..."
if ! xcrun simctl list devices | grep -q "movete-dev"; then
  xcrun simctl create "movete-dev" "$IP16" "$RT185"
  echo "✓ Creato movete-dev"
else
  echo "✓ movete-dev già esistente"
fi

echo ""
echo "✓ Tutti i prerequisiti sono installati."
