import Foundation
import SwiftCrossUI

/// The 10 platform-native icons used by the icon rail and titlebar
/// toolbar. Each case name is also the exact PNG filename (without
/// extension) under `Resources/Icons/<Platform>/<light|dark>/` --
/// see `Scripts/generate-icons.sh`.
enum AppIcon: String {
    case key, designs, themes, device
    case newDoc, open, save, saveAs, importFile, exportFile
}

/// Resolves an `AppIcon` to the bundled PNG for the current platform and
/// color scheme. SwiftCrossUI's `Image` has no live OS-symbol API and no
/// runtime tinting, so every icon is a pre-rendered, pre-tinted asset
/// (see `Scripts/generate-icons.sh`) -- this just picks the right file.
enum IconLoader {
    static func url(for icon: AppIcon, colorScheme: ColorScheme) -> URL? {
        let platformDir: String
        #if os(macOS)
        platformDir = "macOS"
        #elseif os(Windows)
        platformDir = "Windows"
        #else
        platformDir = "Linux"
        #endif
        let schemeDir = colorScheme == .dark ? "dark" : "light"
        return Bundle.module.url(
            forResource: icon.rawValue,
            withExtension: "png",
            subdirectory: "Icons/\(platformDir)/\(schemeDir)"
        )
    }
}
