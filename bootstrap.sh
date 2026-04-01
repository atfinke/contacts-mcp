#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pushd "$ROOT_DIR" >/dev/null
npm install
npm run build
npm run build:helper-app
popd >/dev/null

echo "Bootstrap complete."
echo "Helper app: $ROOT_DIR/ContactsMCPHelperApp/build/Build/Products/Release/ContactsMCPHelperApp.app"
echo "MCP server: $ROOT_DIR/dist/index.js"
