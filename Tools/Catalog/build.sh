#!/bin/sh
# Builds the catalog tool with the app's own measurement sources: the signatures are measured by the same code.
HERE="$(cd "$(dirname "$0")" && pwd)"
MOTION="$HERE/../../Rebond/Motion"
swiftc -O "$HERE/main.swift" "$HERE/../Replay/kinect.swift" \
    "$MOTION/PoseAnalyzer.swift" "$MOTION/MovementMeasurement.swift" "$MOTION/ExerciseSignature.swift" \
    -o "$HERE/catalog" 2>&1 | grep -E "error|warning" | head -20
