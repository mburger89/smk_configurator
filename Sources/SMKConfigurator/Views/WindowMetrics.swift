import MetalUI

/// The window's fixed sizes: a 1440-wide minimum and a height computed from
/// the chrome plus KEY mode's main column, the tallest of the five.
enum WindowMetrics {
    /// The window's width, opened at and never narrower than.
    static let width: Double = 1440

    /// The status bar's height.
    static let statusBarHeight: Double = 26
    /// The strip MetalUI draws for a `.toolbar` where the platform has no
    /// native toolbar -- SDL, on Linux and Windows -- above the root, taking
    /// its height from the root without growing the window (MetalUI
    /// divergence 136, ruling MD-K; its own constant is internal). 0 on
    /// macOS, where the app declares no toolbar.
    #if os(macOS)
    static let toolbarStripHeight: Double = 0
    #else
    static let toolbarStripHeight: Double = 39
    #endif

    /// Everything the window holds above and below the pane row: the drawn
    /// toolbar strip off macOS, the 1-point divider over the status bar and
    /// the status bar. (The previous build also stacked a 50-point fake
    /// titlebar and its 2-point line here.)
    static let chromeHeight: Double = toolbarStripHeight + statusBarHeight + 1

    /// Guaranteed minimum for KEY mode's board scroll area -- without it the
    /// palette drawer below could take everything and squeeze the board down
    /// to near nothing at the window's minimum size.
    static let boardMinHeight: Double = 240
    /// KEY main column's padding, 20 top and 20 bottom.
    static let keyContentVerticalPadding: Double = 40
    /// The two 16-point gaps between KEY main column's three children.
    static let keyContentStackSpacing: Double = 32

    /// What KEY mode's main column needs at the window floor: the board's
    /// guaranteed minimum plus the drawer squeezed to its own floor.
    static let keyMinContentHeight: Double =
        keyContentVerticalPadding + keyContentStackSpacing + boardMinHeight + PaletteLayout.minHeight
    /// What it needs for the drawer to show every palette section through
    /// Modifiers without scrolling, with the board still at its minimum.
    static let keyIdealContentHeight: Double =
        keyContentVerticalPadding + keyContentStackSpacing + boardMinHeight + PaletteLayout.maxHeight

    /// The window floor. Kept under the ~730pt of usable height a 1366x768
    /// laptop has -- a floor taller than the screen leaves the status bar
    /// unreachable with no way to shrink the window.
    static let minWindowHeight: Double = chromeHeight + keyMinContentHeight
    /// Launch height: enough for the palette to show its common sections
    /// without scrolling. The OS clamps it to the display; the window stays
    /// resizable down to `minWindowHeight`.
    static let idealWindowHeight: Double = chromeHeight + keyIdealContentHeight

    static var minSize: Size<Pixels> {
        Size(width: Pixels(Float(width)), height: Pixels(Float(minWindowHeight.rounded(.up))))
    }

    static var idealSize: Size<Pixels> {
        Size(width: Pixels(Float(width)), height: Pixels(Float(idealWindowHeight.rounded(.up))))
    }
}
