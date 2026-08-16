#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Builds and runs the app as a real macOS .app bundle (icon, Info.plist,
# bundle identifier) via swift-bundler + Bundler.toml, rather than the bare
# executable `swift run` produces.
#
# Exists only to carry the `--build-system native` flag: swift-bundler
# shells out to `swift build` itself, so a bare `swift-bundler run` hits the
# same AndroidBackendShim/`android/log.h` failure a bare `swift build` does
# on an Xcode-resolved toolchain (see CLAUDE.md). swift-bundler has no
# Bundler.toml key or env var for default SwiftPM arguments -- one
# `--Xswiftpm` per token at the call site is the only way to pass it.
#
# Extra arguments are forwarded to `swift-bundler run`, e.g.
#   bash Scripts/run.sh --configuration release
#
# Can be run from any directory: bash Scripts/run.sh

exec swift-bundler run --Xswiftpm --build-system --Xswiftpm native "$@"
