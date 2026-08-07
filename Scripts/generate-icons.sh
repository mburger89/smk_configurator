#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Regenerates every platform-native icon PNG bundled under
# Sources/SMKConfigurator/Resources/{macOS,Windows,Linux}/Icons/. Re-run
# only if the icon set changes -- the output is checked into the repo, not
# generated at build time.
#
# Requires: swiftc (Xcode command line tools, for the macOS/SF Symbols
# step), curl, rsvg-convert (`brew install librsvg` on macOS).
#
# Can be run from any directory: bash Scripts/generate-icons.sh

ICON_ROOT="Sources/SMKConfigurator/Resources"
RAIL_SIZE=66
TOOLBAR_SIZE=48

scratch_dir="$(mktemp -d)"
trap 'rm -rf "$scratch_dir"' EXIT

mkdir -p "$ICON_ROOT/macOS/Icons/light" "$ICON_ROOT/macOS/Icons/dark"
mkdir -p "$ICON_ROOT/Windows/Icons/light" "$ICON_ROOT/Windows/Icons/dark"
mkdir -p "$ICON_ROOT/Linux/Icons/light" "$ICON_ROOT/Linux/Icons/dark"

# --- macOS: real SF Symbols, rendered via AppKit -----------------------

swiftc Scripts/RenderSFSymbol.swift -o "$scratch_dir/RenderSFSymbol" -framework AppKit

render_macos_icon() {
    local icon="$1" symbol="$2" size="$3"
    "$scratch_dir/RenderSFSymbol" "$symbol" "$size" 000000 "$ICON_ROOT/macOS/Icons/light/${icon}.png"
    "$scratch_dir/RenderSFSymbol" "$symbol" "$size" FFFFFF "$ICON_ROOT/macOS/Icons/dark/${icon}.png"
}

render_macos_icon key        "keyboard"              "$RAIL_SIZE"
render_macos_icon designs    "square.grid.3x3"        "$RAIL_SIZE"
render_macos_icon themes     "paintpalette"           "$RAIL_SIZE"
render_macos_icon device     "cable.connector"        "$RAIL_SIZE"
render_macos_icon newDoc     "doc.badge.plus"         "$TOOLBAR_SIZE"
render_macos_icon open       "folder"                 "$TOOLBAR_SIZE"
render_macos_icon save       "square.and.arrow.down"  "$TOOLBAR_SIZE"
render_macos_icon saveAs     "doc.on.doc"             "$TOOLBAR_SIZE"
render_macos_icon importFile "tray.and.arrow.down"    "$TOOLBAR_SIZE"
render_macos_icon exportFile "tray.and.arrow.up"      "$TOOLBAR_SIZE"

# --- Windows (Fluent System Icons, MIT) and Linux (Adwaita) ------------
# Both are SVG sources, fetched then rasterized with rsvg-convert. Fills
# are rewritten via `sed` (both `fill="..."` attributes and CSS `fill:`
# declarations, covering `currentColor` and literal hex alike) rather than
# rsvg-convert's --stylesheet flag, which is less reliable across SVGs
# with mixed fill styles -- verified against real Fluent and Adwaita
# source files during this script's authoring.

render_svg_icon() {
    local svg_url="$1" size="$2" out_light="$3" out_dark="$4"
    curl -fsSL "$svg_url" -o "$scratch_dir/source-icon.svg"
    # NOTE: this blanket-rewrites every `fill="..."` / `fill:...` to a
    # solid color. A source SVG using `fill="none"` for a genuinely
    # transparent/outline path would incorrectly become solid
    # `fill="#000000"` here. None of the current 10 icon sources hit this
    # (all pixel-verified correct), but check for `fill="none"` in any
    # future icon source before adding it.
    sed -E 's/fill="[^"]*"/fill="#000000"/g; s/fill:[^;"]*/fill:#000000/g' "$scratch_dir/source-icon.svg" > "$scratch_dir/tinted-light.svg"
    sed -E 's/fill="[^"]*"/fill="#FFFFFF"/g; s/fill:[^;"]*/fill:#FFFFFF/g' "$scratch_dir/source-icon.svg" > "$scratch_dir/tinted-dark.svg"
    rsvg-convert -w "$size" -h "$size" "$scratch_dir/tinted-light.svg" -o "$out_light"
    rsvg-convert -w "$size" -h "$size" "$scratch_dir/tinted-dark.svg" -o "$out_dark"
}

# Windows: Fluent System Icons (github.com/microsoft/fluentui-system-icons)
FLUENT_BASE="https://raw.githubusercontent.com/microsoft/fluentui-system-icons/main/assets"
render_svg_icon "$FLUENT_BASE/Keyboard/SVG/ic_fluent_keyboard_24_regular.svg" "$RAIL_SIZE" "$ICON_ROOT/Windows/Icons/light/key.png" "$ICON_ROOT/Windows/Icons/dark/key.png"
render_svg_icon "$FLUENT_BASE/Grid/SVG/ic_fluent_grid_24_regular.svg" "$RAIL_SIZE" "$ICON_ROOT/Windows/Icons/light/designs.png" "$ICON_ROOT/Windows/Icons/dark/designs.png"
render_svg_icon "$FLUENT_BASE/Color/SVG/ic_fluent_color_24_regular.svg" "$RAIL_SIZE" "$ICON_ROOT/Windows/Icons/light/themes.png" "$ICON_ROOT/Windows/Icons/dark/themes.png"
render_svg_icon "$FLUENT_BASE/Plug%20Connected/SVG/ic_fluent_plug_connected_24_regular.svg" "$RAIL_SIZE" "$ICON_ROOT/Windows/Icons/light/device.png" "$ICON_ROOT/Windows/Icons/dark/device.png"
render_svg_icon "$FLUENT_BASE/Document%20Add/SVG/ic_fluent_document_add_24_regular.svg" "$TOOLBAR_SIZE" "$ICON_ROOT/Windows/Icons/light/newDoc.png" "$ICON_ROOT/Windows/Icons/dark/newDoc.png"
render_svg_icon "$FLUENT_BASE/Folder/SVG/ic_fluent_folder_24_regular.svg" "$TOOLBAR_SIZE" "$ICON_ROOT/Windows/Icons/light/open.png" "$ICON_ROOT/Windows/Icons/dark/open.png"
render_svg_icon "$FLUENT_BASE/Document%20Save/SVG/ic_fluent_document_save_24_regular.svg" "$TOOLBAR_SIZE" "$ICON_ROOT/Windows/Icons/light/save.png" "$ICON_ROOT/Windows/Icons/dark/save.png"
render_svg_icon "$FLUENT_BASE/Document%20Copy/SVG/ic_fluent_document_copy_24_regular.svg" "$TOOLBAR_SIZE" "$ICON_ROOT/Windows/Icons/light/saveAs.png" "$ICON_ROOT/Windows/Icons/dark/saveAs.png"
render_svg_icon "$FLUENT_BASE/Arrow%20Import/SVG/ic_fluent_arrow_import_24_regular.svg" "$TOOLBAR_SIZE" "$ICON_ROOT/Windows/Icons/light/importFile.png" "$ICON_ROOT/Windows/Icons/dark/importFile.png"
render_svg_icon "$FLUENT_BASE/Arrow%20Export/SVG/ic_fluent_arrow_export_24_regular.svg" "$TOOLBAR_SIZE" "$ICON_ROOT/Windows/Icons/light/exportFile.png" "$ICON_ROOT/Windows/Icons/dark/exportFile.png"

# Linux: Adwaita symbolic icons (gitlab.gnome.org/GNOME/adwaita-icon-theme)
ADWAITA_BASE="https://gitlab.gnome.org/GNOME/adwaita-icon-theme/-/raw/master/Adwaita/symbolic"
render_svg_icon "$ADWAITA_BASE/devices/input-keyboard-symbolic.svg" "$RAIL_SIZE" "$ICON_ROOT/Linux/Icons/light/key.png" "$ICON_ROOT/Linux/Icons/dark/key.png"
render_svg_icon "$ADWAITA_BASE/actions/view-grid-symbolic.svg" "$RAIL_SIZE" "$ICON_ROOT/Linux/Icons/light/designs.png" "$ICON_ROOT/Linux/Icons/dark/designs.png"
render_svg_icon "$ADWAITA_BASE/actions/color-select-symbolic.svg" "$RAIL_SIZE" "$ICON_ROOT/Linux/Icons/light/themes.png" "$ICON_ROOT/Linux/Icons/dark/themes.png"
render_svg_icon "$ADWAITA_BASE/devices/network-wired-symbolic.svg" "$RAIL_SIZE" "$ICON_ROOT/Linux/Icons/light/device.png" "$ICON_ROOT/Linux/Icons/dark/device.png"
render_svg_icon "$ADWAITA_BASE/actions/document-new-symbolic.svg" "$TOOLBAR_SIZE" "$ICON_ROOT/Linux/Icons/light/newDoc.png" "$ICON_ROOT/Linux/Icons/dark/newDoc.png"
render_svg_icon "$ADWAITA_BASE/actions/document-open-symbolic.svg" "$TOOLBAR_SIZE" "$ICON_ROOT/Linux/Icons/light/open.png" "$ICON_ROOT/Linux/Icons/dark/open.png"
render_svg_icon "$ADWAITA_BASE/actions/document-save-symbolic.svg" "$TOOLBAR_SIZE" "$ICON_ROOT/Linux/Icons/light/save.png" "$ICON_ROOT/Linux/Icons/dark/save.png"
render_svg_icon "$ADWAITA_BASE/actions/document-save-as-symbolic.svg" "$TOOLBAR_SIZE" "$ICON_ROOT/Linux/Icons/light/saveAs.png" "$ICON_ROOT/Linux/Icons/dark/saveAs.png"
render_svg_icon "$ADWAITA_BASE/actions/insert-object-symbolic.svg" "$TOOLBAR_SIZE" "$ICON_ROOT/Linux/Icons/light/importFile.png" "$ICON_ROOT/Linux/Icons/dark/importFile.png"
render_svg_icon "$ADWAITA_BASE/actions/document-send-symbolic.svg" "$TOOLBAR_SIZE" "$ICON_ROOT/Linux/Icons/light/exportFile.png" "$ICON_ROOT/Linux/Icons/dark/exportFile.png"

echo "Generated $(find "$ICON_ROOT" -name '*.png' | wc -l) icon PNGs under $ICON_ROOT"
