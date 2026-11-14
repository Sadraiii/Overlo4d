#!/bin/sh
# Rebuilds scripts/mockups/motion-data.js from TallyCore's MotionLibrary. Needs a Swift toolchain.
set -e
cd "$(dirname "$0")/../.."
swiftc -O Packages/TallyCore/Sources/TallyCore/Motion.swift Packages/TallyCore/Sources/TallyCore/MotionLibrary.swift \
    scripts/motion/main.swift -o "${TMPDIR:-/tmp}/motion-dump"
"${TMPDIR:-/tmp}/motion-dump" > scripts/mockups/motion-data.js
