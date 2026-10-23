#!/bin/bash
# macOS and Windows ship the same version number. Fails if Info.plist, Cargo.toml and tauri.conf.json disagree.
set -euo pipefail
cd "$(dirname "$0")/.."
mac=$(grep -A1 CFBundleShortVersionString Resources/Info.plist | sed -n 's:.*<string>\(.*\)</string>.*:\1:p')
cargo=$(sed -n 's/^version = "\(.*\)"/\1/p' rust/Cargo.toml | head -1)
tauri=$(sed -n 's/^  "version": "\(.*\)",/\1/p' rust/app/src-tauri/tauri.conf.json)
npm=$(sed -n 's/^  "version": "\(.*\)",/\1/p' rust/app/package.json)
echo "macOS $mac · Cargo $cargo · tauri $tauri · npm $npm"
[[ "$mac" == "$cargo" && "$cargo" == "$tauri" && "$tauri" == "$npm" ]] || { echo "versions differ"; exit 1; }
