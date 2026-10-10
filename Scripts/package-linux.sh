#!/bin/bash
# Lays out a movable Linux build of the configurator in dist/ (cross-platform
# plan §3):
#
#   dist/SMKConfigurator                              the executable (release)
#   dist/SMKConfigurator_SMKConfigurator.bundle/      the icons (Bundle.module;
#                                                     `.resources` under
#                                                     --build-system native)
#   dist/MetalUISDLShaders/                           MetalUI's compiled SDL GPU
#                                                     shaders (MetalUI PX-P: looked
#                                                     for beside the executable)
#
# Not copied: libSDL3.so (3.4 or later, built with X11/Wayland -- a
# distribution package or SDL's default build; MetalUI's CI image's SDL is
# offscreen-only), libhidapi-hidraw.so and the fonts, which come from the
# system. AccessKit is linked statically.
#
# Usage: bash Scripts/package-linux.sh [DIST_DIR]
#   SCRATCH=/path   SwiftPM scratch path (default: .build)
set -euo pipefail
cd "$(dirname "$0")/.."

dist="${1:-dist}"
scratch="${SCRATCH:-.build}"

swift build -c release --scratch-path "$scratch"
bin="$(swift build -c release --scratch-path "$scratch" --show-bin-path)"
shaders="$scratch/checkouts/MetalUI/Backends/SDL/Shaders/compiled"
[ -d "$shaders" ] || { echo "no compiled shaders at $shaders" >&2; exit 1; }

rm -rf "$dist"
mkdir -p "$dist"
cp "$bin/SMKConfigurator" "$dist/"
# Swift 6.4's default build system (swiftbuild) names the resource bundle
# `.bundle` on Linux too; the native build system names it `.resources`.
# Bundle.module looks for that name beside the executable.
bundles=("$bin"/SMKConfigurator_SMKConfigurator.bundle "$bin"/SMKConfigurator_SMKConfigurator.resources)
copied=0
for b in "${bundles[@]}"; do
    if [ -d "$b" ]; then cp -R "$b" "$dist/"; copied=1; fi
done
[ "$copied" = 1 ] || { echo "no resource bundle in $bin" >&2; exit 1; }
cp -R "$shaders" "$dist/MetalUISDLShaders"
echo "packaged into $dist:"
ls -1 "$dist"
