import Foundation
import MetalUI

/// Resolves an `AppIcon` to the bundled PNG for the current color scheme, and
/// decodes it once. MetalUI's `Image` takes an `ImageBitmap` and has no
/// bundle-name initialiser and no template tinting (gap MG-10), so every icon
/// is a pre-rendered, pre-tinted asset (see `Scripts/generate-icons.sh`) and
/// this picks the right file. SwiftPM's resource copy keeps only the resource's
/// basename ("Icons") as the top-level folder in the bundle, so the assets sit
/// at `Icons/<light|dark>/<icon>.png`.
enum IconLoader {
    /// The PNGs are drawn at 22 points from 66-pixel files.
    static let bitmapScale: Float = 3

    static func url(for icon: AppIcon, colorScheme: ColorScheme) -> URL? {
        let schemeDir = colorScheme == .dark ? "dark" : "light"
        return Bundle.module.url(
            forResource: icon.rawValue,
            withExtension: "png",
            subdirectory: "Icons/\(schemeDir)"
        )
    }

    /// Every decode so far, by icon and scheme -- a missing or undecodable
    /// file is remembered as `nil` too, so a frame never retries ImageIO.
    /// `ImageBitmap(contentsOfFile:)` decodes on every call, and the rail asks
    /// for five icons every frame it builds.
    @MainActor private static var cache: [CacheKey: ImageBitmap?] = [:]

    private struct CacheKey: Hashable {
        var icon: AppIcon
        var scheme: ColorScheme
    }

    /// The decoded icon, or `nil` when no PNG resolves (callers draw
    /// `AppIcon.fallbackLabel` instead).
    @MainActor
    static func bitmap(for icon: AppIcon, colorScheme: ColorScheme) -> ImageBitmap? {
        let key = CacheKey(icon: icon, scheme: colorScheme)
        if let cached = cache[key] { return cached }
        let bitmap = url(for: icon, colorScheme: colorScheme).flatMap { ImageBitmap(contentsOfFile: $0.path) }
        cache[key] = .some(bitmap)
        return bitmap
    }
}
