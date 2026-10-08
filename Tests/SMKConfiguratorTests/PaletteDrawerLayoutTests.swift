import Testing
@testable import SMKConfigurator

/// Guards the premise behind removing the palette's per-section
/// `ScrollView(.horizontal)`, and that the drawer keeps needing none.
///
/// Today the drawer is MetalUI's legacy vertical `ScrollView`, which scrolls
/// one axis only: a chip row wider than the drawer could not be scrolled to,
/// so the widest row must fit the narrowest drawer. The history below is why
/// the horizontal scrollers were removed (historical: it describes the
/// SwiftCrossUI build this app was ported from).
///
/// Those inner scroll views were nested inside the drawer's vertical one, and
/// swift-cross-ui's AppKit backend maps every `ScrollView` onto a plain
/// `NSScrollView` without ever telling it which axis it scrolls — the only
/// signals it passes are `hasHorizontalScrollBar`/`hasVerticalScrollBar`,
/// which answer "does content overflow?", not "is this axis enabled?" (see
/// `ScrollView.computeLayout` and `AppKitBackend.updateScrollContainer`). A
/// horizontal scroll view therefore stays a fully capable *vertical*
/// scroller that merely hides its scroller, so it competed with the drawer
/// for wheel events and vertical scrolling worked or didn't depending on
/// where the pointer sat. Flaky, not broken.
///
/// They could be removed outright because they never had anything to scroll:
/// a full chip row is narrower than the drawer ever gets. That is only true
/// while the numbers below hold, so this pins them. If someone raises
/// `chipsPerRow`, widens `PaletteChip`, or narrows the window floor, this
/// fails here rather than silently reintroducing unreachable chips.
// `@MainActor` from the days the layout constants lived on a main-actor view;
// `PaletteLayout` is a plain enum now, and the isolation is harmless.
@MainActor
@Suite("The palette's widest chip row fits without horizontal scrolling")
struct PaletteDrawerLayoutTests {
    /// `PaletteChip`'s fixed frame (`Views/PaletteDrawerView.swift`).
    private static let chipWidth: Double = 44
    /// `HStack(spacing: 8)` between chips in a row.
    private static let chipSpacing: Double = 8

    /// The narrowest the drawer's content area can be, at the window floor.
    ///
    /// `ContentView` sets `minWidth: 1440`; the icon rail is 64
    /// (`IconRailView`), KEY mode's list column 260 and its inspector 300
    /// (`KeyModeViews`), plus three 1pt dividers and the drawer's own
    /// `.padding(10)` on each side.
    private static let minimumDrawerContentWidth: Double = 1440 - 64 - 260 - 300 - 3 - 20

    @Test("a full row of chips is narrower than the drawer ever gets")
    func fullRowFitsMinimumWidth() {
        let perRow = Double(PaletteLayout.chipsPerRow)
        let rowWidth = perRow * Self.chipWidth + (perRow - 1) * Self.chipSpacing
        #expect(
            rowWidth < Self.minimumDrawerContentWidth,
            """
            A full \(Int(perRow))-chip row is \(rowWidth)pt but the drawer can be as \
            narrow as \(Self.minimumDrawerContentWidth)pt. Chips past the edge would \
            now be unreachable, because the per-section horizontal ScrollView that \
            used to make them reachable was removed — it stole wheel events from the \
            drawer's vertical scroll and never actually scrolled anything.
            """
        )
    }

    @Test("no generated key section exceeds the per-row cap")
    func noSectionExceedsTheRowCap() {
        // `keySections` computes `rows` from `chipsPerRow`, so a section whose
        // widest row exceeded the cap would mean that arithmetic is wrong,
        // not just that a group is large.
        for section in PaletteLayout.keySections {
            let widestRow = Int(
                (Double(section.tokens.count) / Double(section.rows)).rounded(.up)
            )
            #expect(
                widestRow <= PaletteLayout.chipsPerRow,
                "\(section.title) puts \(widestRow) chips in a row, over the \(PaletteLayout.chipsPerRow) cap"
            )
        }
    }
}
