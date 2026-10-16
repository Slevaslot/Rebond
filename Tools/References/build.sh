#!/bin/sh
# Builds the filmed-movement tool with the app's own motion sources (all but the camera and the voice), so real
# videos run through the real learning and counting code on the Mac.
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/../../Rebond"
FILES=$(ls "$APP"/Motion/*.swift | grep -v -e Coach.swift -e MotionSession.swift)
swiftc -O -swift-version 6 -default-isolation MainActor "$HERE/main.swift" $FILES "$APP/Catalog/CatalogExercise.swift" \
    "$APP/Workout/WorkoutPlan.swift" "$APP/Views/Session/AmplitudeTier.swift" \
    -o "$HERE/references" 2>&1 | grep -E "error|warning: var" | head -20
