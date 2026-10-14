#!/bin/sh
# Builds the replay tool with the app's own counter sources, so the dataset runs through the real code.
# Add the file of any new counter to the list below.
HERE="$(cd "$(dirname "$0")" && pwd)"
MOTION="$HERE/../../Rebond/Motion"
swiftc -O "$HERE/kinect.swift" "$HERE/main.swift" \
    "$MOTION/RepCounter.swift" "$MOTION/RepCycle.swift" "$MOTION/ArmRaiseCounter.swift" \
    "$MOTION/SitToStandCounter.swift" "$MOTION/LegRaiseCounter.swift" "$MOTION/PoseAnalyzer.swift" \
    -o "$HERE/replay" 2>&1 | grep -E "error|warning" | head -20
