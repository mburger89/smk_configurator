import Foundation

/// The KEY-mode palette drawer's layout: its sections, how many chips a row
/// holds, and the drawer's height bounds, which feed the window's minimum and
/// launch heights (`WindowMetrics`). Moved verbatim out of the old
/// `PaletteDrawerView`'s static members (port plan §4.3 item 3) under a new
/// name, since `PaletteDrawerView` is now the drawn `Component`; pinned by
/// `PaletteDrawerLayoutTests`, `KeyVocabularyTests` and `MacroPaletteTests`.
enum PaletteLayout {
    /// One `PaletteChip`'s fixed height (see `PaletteChip.body`'s
    /// `.frame(width: 44, height: 26)`) and the spacing between wrapped
    /// chip rows within a section (e.g. the two `Letters` rows).
    static let chipRowHeight: Double = 26
    static let chipRowSpacing: Double = 8
    /// `layersAndSpecialSection`'s row height: `layerPickerGroup`'s tallest
    /// child (`PaletteChip`, 26) plus its own `.padding(4)` on both sides.
    static let layersRowHeight: Double = chipRowHeight + 8
    /// Each section's 10pt bold title line plus the 4pt spacing down to its
    /// chip row (`section`'s and `layersAndSpecialSection`'s own
    /// `VStack(spacing: 4)`).
    static let sectionTitleHeight: Double = 12
    static let sectionTitleSpacing: Double = 4
    /// Spacing between sections in `body`'s outer `VStack`.
    static let sectionSpacing: Double = 12
    /// `body`'s outer `.padding(10)`, top and bottom.
    static let outerPadding: Double = 10

    /// Chips per row before a section wraps to another row.
    ///
    /// This is a hard layout constraint now that nothing in the drawer scrolls
    /// horizontally: a row wider than the drawer clips rather than scrolls, so
    /// chips past the edge would be unreachable. 13 chips is 668pt against a
    /// drawer that is never narrower than ~793pt, which
    /// `PaletteDrawerLayoutTests` pins -- raise this and that test fails rather
    /// than the palette silently losing chips. 13 is also what keeps Letters at
    /// the 2 rows it has always rendered; changing it re-flows every section, so
    /// it is the one number here worth eyeballing in the running app.
    static let chipsPerRow = 13

    /// Every palette section in display order: the generated key groups (see
    /// `KeyName.allGroups`, ordered by how often they get used), then Modifiers,
    /// which is not manifest-driven since it comes from `ModifierName`.
    ///
    /// The drawer (`PaletteDrawerView`) and `contentHeight` BOTH derive from this. They used to be
    /// maintained separately, which is how adding the Function Keys/System
    /// sections once silently clipped "Layers & Special" out of view -- see
    /// `maxHeight`. Row counts are computed, not authored, for the same reason.
    static var keySections: [(title: String, tokens: [ActionToken], rows: Int)] {
        var sections = KeyName.allGroups.map { group in
            (title: group.title,
             tokens: group.keys.map { ActionToken.key($0) },
             rows: max(1, Int((Double(group.keys.count) / Double(chipsPerRow)).rounded(.up))))
        }
        let modifiers = (title: "Modifiers",
                         tokens: ModifierName.allCases.map { ActionToken.modifier($0) },
                         rows: 1)
        // Straight after Navigation, not appended at the end: modifiers are among
        // the most-reached-for chips here, and anything past the `maxHeight` cap
        // costs a scroll. Appending would bury them below Keypad/International/
        // Legacy, which are the sections that genuinely belong down there.
        if let navigation = sections.firstIndex(where: { $0.title == "Navigation" }) {
            sections.insert(modifiers, at: navigation + 1)
        } else {
            sections.append(modifiers)
        }
        return sections
    }

    private static func sectionHeight(rows: Int) -> Double {
        sectionTitleHeight + sectionTitleSpacing
            + Double(rows) * chipRowHeight + Double(rows - 1) * chipRowSpacing
    }

    /// One chip per saved macro, in slot order.
    static func macroTokens(for document: KeymapDocument) -> [ActionToken] {
        document.macroList.sorted { $0.id < $1.id }.map { .macro($0.id) }
    }

    /// The MACROS section is deliberately fixed at one row no matter how many
    /// macros exist -- including zero, where it still
    /// renders (as "No macros yet.") rather than disappearing. `maxHeight`
    /// and `contentHeight` here are static and feed
    /// `WindowMetrics.minWindowHeight`; a section that grew with the document,
    /// or that appeared/disappeared based on it, would make the window's
    /// minimum height depend on how many macros the user happens to own.
    static let macroSectionHeight: Double = sectionHeight(rows: 1)

    /// Sum of every section's rendered height, derived from `keySections`
    /// rather than hand-enumerated, plus the Layers & Special row, the
    /// MACROS row, the gaps between sections, and the outer padding.
    private static var contentHeight: Double {
        let sections = keySections
        let sectionsHeight = sections.reduce(0.0) { $0 + sectionHeight(rows: $1.rows) }
        let layersAndSpecial = sectionTitleHeight + sectionTitleSpacing + layersRowHeight
        // +1 section gap: MACROS is an additional section beyond `sections.count`.
        let sectionGaps = Double(sections.count + 1) * sectionSpacing
        return sectionsHeight + layersAndSpecial + macroSectionHeight + sectionGaps + 2 * outerPadding
    }

    /// Safety margin over `contentHeight` covering font-metric variance on
    /// platforms this can't be run/verified on locally (Windows/Linux CI is
    /// build-only, no test step -- see the repo's CLAUDE.md).
    private static let heightSafetyMargin: Double = 60

    /// Ceiling on how tall the drawer may ask to be. `contentHeight` is what it
    /// would take to show all 12 sections (10 generated key groups, Modifiers,
    /// and Layers & Special) without internal scrolling -- about 1010pt now that
    /// the full keyboard-page vocabulary is in, which is taller than a 1366x768
    /// or 1440x900 laptop can spare. So the drawer asks for the smaller of
    /// "everything fits" and this cap, and the rare tail sections scroll
    /// vertically instead.
    ///
    /// Sections are ordered by how often they get used (see `KeyName.allGroups`),
    /// so what lands above the fold is what people actually reach for. The cap is
    /// set so everything through Modifiers clears it: Layers & Special, Letters,
    /// Numbers, Editing & Punctuation, Navigation, Modifiers. Function Keys
    /// onward -- and especially Keypad/International/Legacy -- scroll.
    ///
    /// It stays a *maximum*, paired with `minHeight` and an explicit min/max frame
    /// at the call site (see `KeyMainContentView`) rather than a strict
    /// `.frame(height:)`, so a short window can still squeeze the drawer down to
    /// `minHeight` instead of forcing a window `minHeight` taller than the
    /// screen.
    private static let heightCap: Double = 530
    static var maxHeight: Double { min(contentHeight + heightSafetyMargin, heightCap) }

    /// Floor for the drawer when the window is too short to give it
    /// `maxHeight` -- roughly three sections plus the vertical scrollbar
    /// that appears once the rest overflows. This (not `maxHeight`) is what
    /// `WindowMetrics.minWindowHeight` has to reserve.
    static let minHeight: Double = 260

    /// Splits `tokens` into `rows` roughly-equal, left-to-right chunks (e.g.
    /// a-z into two rows of 13) rather than wrapping automatically -- the
    /// drawer's rows are fixed so `contentHeight` stays exact.
    static func chunk(_ tokens: [ActionToken], into rows: Int) -> [[ActionToken]] {
        guard rows > 1 else { return [tokens] }
        let perRow = Int((Double(tokens.count) / Double(rows)).rounded(.up))
        return stride(from: 0, to: tokens.count, by: perRow).map {
            Array(tokens[$0..<min($0 + perRow, tokens.count)])
        }
    }
}
