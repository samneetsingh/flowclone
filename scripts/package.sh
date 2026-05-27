#!/bin/bash
set -euo pipefail

APP_PATH="build/Release/FlowClone.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_PATH not found. Build the project in Xcode first (Product → Build)."
    exit 1
fi

codesign --deep --force --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

cd build/Release
zip -r ../../FlowClone.zip FlowClone.app

echo "✓ FlowClone.zip ready for distribution"
