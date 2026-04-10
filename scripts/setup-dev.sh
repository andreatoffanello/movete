#!/bin/bash
set -e

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
  xcrun simctl create "movete-dev" "iPhone 16 Pro" "iOS 18.5"
  echo "✓ Creato movete-dev"
else
  echo "✓ movete-dev già esistente"
fi

echo ""
echo "✓ Tutti i prerequisiti sono installati."
