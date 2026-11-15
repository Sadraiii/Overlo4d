#!/bin/sh
# Runs the app's own exercise-figure drawing (MotionFigureView.swift) outside the app: compiles it
# against a small stand-in for SwiftUI that records drawing as SVG, and writes a page of every move.
# The app can't be built on Linux, so this is also the only type check that code gets here.
#   scripts/motion/preview.sh [page.html]
# Needs a Swift toolchain.
set -e
cd "$(dirname "$0")/../.."
repo="$PWD"
case "${1:-motion-preview.html}" in /*) out="$1" ;; *) out="$PWD/${1:-motion-preview.html}" ;; esac
build="$(mktemp -d)"
{ cat scripts/motion/preview/App.swift; sed -n '/Parses an SVG path string/,/^}/p' Sources/Overlo4d/Exercises/Anatomy.swift; } > "$build/App.swift"
cd "$build"
module() { name="$1"; shift; swiftc -swift-version 6 -I . -L . -emit-module -emit-library -static -parse-as-library -module-name "$name" "$@"; }
module SwiftUI "$repo/scripts/motion/preview/SwiftUI.swift"
module Overlo4dKit "$repo/scripts/motion/preview/Overlo4dKit.swift"
module Overlo4dCore "$repo"/Packages/Overlo4dCore/Sources/Overlo4dCore/*.swift
swiftc -swift-version 6 -I . -L . -lSwiftUI -lOverlo4dKit -lOverlo4dCore -module-name Preview -o preview \
    "$repo/scripts/motion/preview/main.swift" App.swift \
    "$repo/Sources/Overlo4d/Exercises/MotionFigureView.swift" "$repo/Sources/Overlo4d/Exercises/MotionShapes.swift"
./preview > "$out"
rm -rf "$build"
echo "$out"
