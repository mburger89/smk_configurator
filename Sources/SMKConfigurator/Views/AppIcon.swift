import Foundation
import SwiftCrossUI

/// The 10 platform-native icons used by the icon rail and titlebar
/// toolbar. Each case name is also the exact PNG filename (without
/// extension) under `Resources/<Platform>/Icons/<light|dark>/` --
/// see `Scripts/generate-icons.sh`.
enum AppIcon: String, CaseIterable {
    case key, designs, themes, device
    case newDoc, open, save, saveAs, importFile, exportFile
}

/// Resolves an `AppIcon` to the bundled PNG for the current platform and
/// color scheme. SwiftCrossUI's `Image` has no live OS-symbol API and no
/// runtime tinting, so every icon is a pre-rendered, pre-tinted asset
/// (see `Scripts/generate-icons.sh`) -- this just picks the right file.
/// Platform selection happens in `Package.swift` (only the current
/// platform's icon subtree, `Resources/<Platform>/Icons/`, is ever
/// bundled). SwiftPM's resource copy preserves only the resource's
/// basename ("Icons") as the top-level folder in the bundle, so every
/// platform's assets land at the same in-bundle path --
/// `Icons/<light|dark>/<icon>.png` -- with no `<Platform>` subdirectory
/// to select here.
enum IconLoader {
    static func url(for icon: AppIcon, colorScheme: ColorScheme) -> URL? {
        let schemeDir = colorScheme == .dark ? "dark" : "light"
        return Bundle.module.url(
            forResource: icon.rawValue,
            withExtension: "png",
            subdirectory: "Icons/\(schemeDir)"
        )
    }
}
