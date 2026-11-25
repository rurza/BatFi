#!/bin/bash
set -e

defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES

# Replace the committed AnalyticsDSN.swift stub with the real Sentry DSN.
# A shipped build must never fall back to the stub's empty DSN, so stop here
# when the CI has no DSN to write.
if [ -z "${SENTRY_DSN}" ]; then
    echo "error: SENTRY_DSN is not set; refusing to build with the empty analytics stub."
    exit 1
fi

CLIENTS_PATH="${CI_PRIMARY_REPOSITORY_PATH}/BatFiKit/Sources/ClientsLive"
if [ ! -d "${CLIENTS_PATH}" ]; then
    echo "Directory not found!"
    exit 1
fi
cd "${CLIENTS_PATH}"

echo "import Foundation" > AnalyticsDSN.swift
echo "" >> AnalyticsDSN.swift
echo "// This file is generated in the CI process from SENTRY_DSN." >> AnalyticsDSN.swift
echo "// The committed version is an empty stub; do not commit the real DSN." >> AnalyticsDSN.swift
echo "let analyticsDSN = \"${SENTRY_DSN}\"" >> AnalyticsDSN.swift
cat AnalyticsDSN.swift
