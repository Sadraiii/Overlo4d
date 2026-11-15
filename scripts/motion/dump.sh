#!/bin/sh
# Rebuilds scripts/mockups/motion-data.js from Overlo4dCore's MotionLibrary. Needs a Swift toolchain.
set -e
cd "$(dirname "$0")/../.."
swiftc -O Packages/Overlo4dCore/Sources/Overlo4dCore/Motion.swift Packages/Overlo4dCore/Sources/Overlo4dCore/MotionLibrary.swift \
    scripts/motion/main.swift -o "${TMPDIR:-/tmp}/motion-dump"
"${TMPDIR:-/tmp}/motion-dump" > scripts/mockups/motion-data.js
