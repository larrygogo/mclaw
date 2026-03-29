#!/bin/bash
# Xcode Build Phase Script for SwiftLint
# Add as: Build Phases → New Run Script Phase
# Script: ${SRCROOT}/scripts/swiftlint.sh

if command -v swiftlint >/dev/null 2>&1; then
    swiftlint lint --config "${SRCROOT}/.swiftlint.yml"
elif [ -f "/opt/homebrew/bin/swiftlint" ]; then
    /opt/homebrew/bin/swiftlint lint --config "${SRCROOT}/.swiftlint.yml"
else
    echo "warning: SwiftLint not installed. Run: brew install swiftlint"
fi
