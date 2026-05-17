#!/bin/bash
# Build CockpitDev and package as a proper .app bundle

set -e

echo "Building CockpitDev..."
swift build -c debug

echo "Packaging into .app bundle..."
cp .build/arm64-apple-macosx/debug/CockpitDev "CockpitDev.app/Contents/MacOS/CockpitDev"

echo "Done! Run with:"
echo "  open CockpitDev.app"
