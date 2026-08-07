# Third-Party Notices

This project bundles platform-native icon assets derived from the
following third-party icon sets (see `Scripts/generate-icons.sh`).
Each source SVG is rasterized to PNG and recolored (solid black for
light mode, solid white for dark mode) at build-time-fixed sizes; no
other modifications are made to the artwork.

## Windows icons -- Fluent System Icons

- **Source:** https://github.com/microsoft/fluentui-system-icons
- **License:** MIT License
- **Copyright:** Copyright (c) Microsoft Corporation
- **Bundled at:** `Sources/SMKConfigurator/Resources/Windows/Icons/`

## Linux icons -- Adwaita Icon Theme

- **Source:** https://gitlab.gnome.org/GNOME/adwaita-icon-theme
- **License:** Dual-licensed under LGPL-3.0-or-later and
  CC-BY-SA-3.0-or-later
- **Copyright:** Copyright the GNOME Project and contributors
- **Bundled at:** `Sources/SMKConfigurator/Resources/Linux/Icons/`

## macOS icons -- SF Symbols

- **Source:** Apple SF Symbols
- **License:** Governed by Apple's SF Symbols license
  (https://developer.apple.com/support/downloads/terms/sf-symbols/SF-Symbols-License.pdf).
  Per that license, SF-Symbols-derived glyphs are only ever bundled
  into the macOS build of this app (see `Package.swift`), never into
  the Windows or Linux builds.
- **Bundled at:** `Sources/SMKConfigurator/Resources/macOS/Icons/`
