import SwiftCrossUI

/// The dense action palette below the board in KEY mode: every action the
/// firmware understands, grouped into sections and shown simultaneously
/// (not tabbed), white background, as tall as `maxHeight` allows with the
/// rarer sections scrolling below the fold (see that comment) -- see the
/// handoff's "List column"/"Main content" KEY description. Tapping a chip arms it (see `KeyCapView`);
/// tapping the armed chip again disarms it.
struct PaletteDrawerView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    /// One `PaletteChip`'s fixed height (see `PaletteChip.body`'s
    /// `.frame(width: 44, height: 26)`) and the spacing between wrapped
    /// chip rows within a section (e.g. the two `Letters` rows).
    private static let chipRowHeight: Double = 26
    private static let chipRowSpacing: Double = 8
    /// `layersAndSpecialSection`'s row height: `layerPickerGroup`'s tallest
    /// child (`PaletteChip`, 26) plus its own `.padding(4)` on both sides.
    private static let layersRowHeight: Double = chipRowHeight + 8
    /// Each section's 10pt bold title line plus the 4pt spacing down to its
    /// chip row (`section`'s and `layersAndSpecialSection`'s own
    /// `VStack(spacing: 4)`).
    private static let sectionTitleHeight: Double = 12
    private static let sectionTitleSpacing: Double = 4
    /// Spacing between sections in `body`'s outer `VStack`.
    private static let sectionSpacing: Double = 12
    /// `body`'s outer `.padding(10)`, top and bottom.
    private static let outerPadding: Double = 10

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
    /// `body` and `contentHeight` BOTH derive from this. They used to be
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
    /// `ContentView.minWindowHeight`; a section that grew with the document,
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
    /// It stays a *maximum*, paired with `minHeight` and a `.layoutPriority(1)`
    /// at the call site (see `KeyMainContentView`) rather than a strict
    /// `.frame(height:)`, so a short window can still squeeze the drawer down to
    /// `minHeight` instead of forcing a window `minHeight` taller than the
    /// screen.
    private static let heightCap: Double = 530
    static var maxHeight: Double { min(contentHeight + heightSafetyMargin, heightCap) }

    /// Floor for the drawer when the window is too short to give it
    /// `maxHeight` -- roughly three sections plus the vertical scrollbar
    /// that appears once the rest overflows. This (not `maxHeight`) is what
    /// `ContentView`'s window `minHeight` has to reserve.
    static let minHeight: Double = 260

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                // First, not last. It holds the only controls with no other
                // access path in the UI -- the layer picker feeding MO/TG, plus
                // trans/none/toggle_conn -- and `maxHeight`'s cap means whatever
                // sits at the bottom is reachable only by scrolling. One row is
                // a cheap price for those never being below the fold.
                layersAndSpecialSection
                ForEach(Self.keySections, id: \.title) { s in
                    section(s.title, tokens: s.tokens, rows: s.rows)
                }
                macroSection
            }
            .padding(10)
        }
        .frame(minHeight: Self.minHeight, maxHeight: Self.maxHeight)
        .background(RoundedRectangle(cornerRadius: 10).fill(chrome.surface))
    }

    private func section(_ title: String, tokens: [ActionToken], rows: Int = 1) -> some View {
        let chunks = chunk(tokens, into: rows)
        let contentHeight =
            Double(rows) * Self.chipRowHeight + Double(rows - 1) * Self.chipRowSpacing
        return VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(chrome.textTertiary)
            // Deliberately NOT wrapped in `ScrollView(.horizontal)`. Chips
            // already wrap: `chunk(_:into:)` splits a group across `rows`, so
            // Letters is two rows of 13 rather than one long scrolling strip.
            // The scroll view that used to be here could never scroll --- a
            // full 13-chip row is 668pt and the drawer is never narrower than
            // ~793pt (see `PaletteDrawerLayoutTests`) --- but it did steal
            // wheel events from the drawer's own vertical scroll, because
            // swift-cross-ui maps every `ScrollView` onto a plain
            // `NSScrollView` and never tells it which axis it owns. That made
            // vertical scrolling work or not depending on whether the pointer
            // happened to sit over a section's chips.
            VStack(spacing: 8) {
                ForEach(chunks.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        ForEach(chunks[i]) { token in
                            PaletteChip(token: token)
                        }
                    }
                }
            }
            .frame(height: contentHeight)
        }
    }

    /// Splits `tokens` into `rows` roughly-equal, left-to-right chunks (e.g.
    /// a-z into two rows of 13) rather than wrapping automatically, since
    /// SwiftCrossUI has no wrapping stack/grid layout.
    private func chunk(_ tokens: [ActionToken], into rows: Int) -> [[ActionToken]] {
        guard rows > 1 else { return [tokens] }
        let perRow = Int((Double(tokens.count) / Double(rows)).rounded(.up))
        return stride(from: 0, to: tokens.count, by: perRow).map {
            Array(tokens[$0..<min($0 + perRow, tokens.count)])
        }
    }

    private var layersAndSpecialSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LAYERS & SPECIAL")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(chrome.textTertiary)
            // Six chips and a stepper, ~300pt: the narrowest section here and
            // the one least in need of the scroll view it used to carry.
            HStack(spacing: 12) {
                layerPickerGroup
                HStack(spacing: 8) {
                    PaletteChip(token: .transparent)
                    PaletteChip(token: .none)
                    PaletteChip(token: .toggleConnection)
                }
            }
            .frame(height: Self.layersRowHeight, alignment: .leading)
        }
    }

    /// The layer-index stepper plus the MO/TG chips it feeds, boxed
    /// together with a shared background/border and a "→" connector so
    /// it reads as one control ("this number is which layer MO/TG jump
    /// to") rather than a run of unrelated chips like the rest of the row.
    private var layerPickerGroup: some View {
        HStack(spacing: 4) {
            TapTarget(background: chrome.chipBackground, cornerRadius: 4, action: {
                editor.pendingLayerIndex = max(0, editor.pendingLayerIndex - 1)
            }) {
                Text("–").font(.system(size: 11)).foregroundColor(chrome.textPrimary)
            }
            .frame(width: 20, height: 20)
            Text("\(editor.pendingLayerIndex)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(chrome.textPrimary)
                .frame(width: 16)
            TapTarget(background: chrome.chipBackground, cornerRadius: 4, action: {
                editor.pendingLayerIndex = min(editor.maxAssignableLayerIndex, editor.pendingLayerIndex + 1)
            }) {
                Text("+").font(.system(size: 11)).foregroundColor(chrome.textPrimary)
            }
            .frame(width: 20, height: 20)
            Text("→")
                .font(.system(size: 11))
                .foregroundColor(chrome.textTertiary)
            PaletteChip(token: .momentaryLayer(editor.pendingLayerIndex))
            PaletteChip(token: .toggleLayer(editor.pendingLayerIndex))
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 6).fill(chrome.chipBackground.opacity(0.5)))
        .overlay {
            RoundedRectangle(cornerRadius: 6).stroke(chrome.chipBorder, style: StrokeStyle(width: 1))
        }
    }

    /// One saved-macro chip per macro, exactly like a generated key
    /// section, except this one is document-driven rather than
    /// manifest-driven. Deliberately fixed at one row regardless of how
    /// many macros exist (see `macroSectionHeight`) -- including zero,
    /// where it still renders ("No macros yet.") rather than disappearing,
    /// since a section that appears/disappears would also change the
    /// drawer's height, which is the thing `macroSectionHeight` being a
    /// `static let` exists to prevent.
    private var macroSection: some View {
        let tokens = Self.macroTokens(for: editor.document)
        return VStack(alignment: .leading, spacing: 4) {
            Text("MACROS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(chrome.textTertiary)
            if tokens.isEmpty {
                Text("No macros yet.")
                    .font(.system(size: 11))
                    .foregroundColor(chrome.textTertiary)
                    .frame(height: Self.chipRowHeight, alignment: .leading)
            } else {
                // The only section whose contents can genuinely outgrow a row,
                // and the only one that can't answer by wrapping: it is pinned
                // to one row so the drawer's height doesn't depend on how many
                // macros the document happens to hold (see `macroSectionHeight`).
                // So it caps at a row and says how many it is not showing,
                // rather than clipping the overflow silently. The MACROS rail
                // mode lists all of them; this strip is a placement shortcut.
                HStack(spacing: 8) {
                    ForEach(Array(tokens.prefix(Self.chipsPerRow))) { token in
                        PaletteChip(token: token)
                    }
                    if tokens.count > Self.chipsPerRow {
                        Text("+\(tokens.count - Self.chipsPerRow) more")
                            .font(.system(size: 11))
                            .foregroundColor(chrome.textTertiary)
                    }
                }
                .frame(height: Self.chipRowHeight, alignment: .leading)
            }
        }
    }
}

/// One 11px chip in the palette drawer: `#f2f2f4` fill, hairline `#e0e0e2`
/// border, 4px radius.
private struct PaletteChip: View {
    @Environment(EditorState.self) var editor
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }
    var token: ActionToken

    var body: some View {
        let isSelected = editor.selectedToken == token

        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(chrome.chipBackground)
            Text(token.displayLabel)
                .font(.system(size: 11))
                .foregroundColor(chrome.textPrimary)
        }
        .frame(width: 44, height: 26)
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? chrome.accent : chrome.chipBorder, style: StrokeStyle(width: isSelected ? 2 : 1))
        }
        .onTapGesture {
            editor.toggleSelection(token)
        }
    }
}
