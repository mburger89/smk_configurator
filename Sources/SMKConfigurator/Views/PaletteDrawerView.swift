import SwiftCrossUI

/// The dense action palette below the board in KEY mode: every action the
/// firmware understands, grouped into sections and shown simultaneously
/// (not tabbed), white background, tall enough to fit every section
/// (see `maxHeight`'s comment) -- see the handoff's "List column"/"Main
/// content" KEY description. Tapping a chip arms it (see `KeyCapView`);
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
    /// Headroom reserved below each section's chip row for a horizontal
    /// scrollbar. SwiftCrossUI's `ScrollView(.horizontal)` only grows its
    /// own layout height to make room for the scrollbar when its content
    /// actually overflows the available width (see swift-cross-ui's
    /// `ScrollView.computeLayout`), so without a fixed frame here,
    /// sections whose chips happen to overflow render taller than ones
    /// that don't -- an inconsistent gap/border-like artifact between
    /// sections. Giving every section the same fixed height (content +
    /// this reserve) makes them uniform regardless of whether that
    /// section's row overflows.
    private static let scrollBarReserve: Double = 15
    /// `layersAndSpecialSection`'s row height: `layerPickerGroup`'s tallest
    /// child (`PaletteChip`, 26) plus its own `.padding(4)` on both sides.
    private static let layersRowHeight: Double = chipRowHeight + 8
    /// Each section's 10pt bold title line plus the 4pt spacing down to its
    /// chip row (`section`'s and `layersAndSpecialSection`'s own
    /// `VStack(spacing: 4)`).
    private static let sectionTitleHeight: Double = 12
    private static let sectionTitleSpacing: Double = 4
    /// Spacing between the 8 sections in `body`'s outer `VStack`.
    private static let sectionSpacing: Double = 12
    /// `body`'s outer `.padding(10)`, top and bottom.
    private static let outerPadding: Double = 10

    private static func sectionHeight(rows: Int) -> Double {
        sectionTitleHeight + sectionTitleSpacing
            + Double(rows) * chipRowHeight + Double(rows - 1) * chipRowSpacing
            + scrollBarReserve
    }

    /// Sum of every section's actual rendered height: the 7 `section(...)`
    /// calls in `body` (Letters is 2 rows, the rest are 1) plus
    /// `layersAndSpecialSection`, their spacing, and the outer padding.
    private static var contentHeight: Double {
        let letters = sectionHeight(rows: 2)
        let oneRowSections = 6 * sectionHeight(rows: 1)
        let layersAndSpecial = sectionTitleHeight + sectionTitleSpacing + layersRowHeight + scrollBarReserve
        let sectionGaps = 7 * sectionSpacing
        return letters + oneRowSections + layersAndSpecial + sectionGaps + 2 * outerPadding
    }

    /// Safety margin over `contentHeight` covering font-metric variance on
    /// platforms this can't be run/verified on locally (Windows/Linux CI is
    /// build-only, no test step -- see the repo's CLAUDE.md).
    private static let heightSafetyMargin: Double = 60

    /// The height the drawer wants: tall enough to fit all 8 sections
    /// (Letters through Layers & Special) without its own internal
    /// `ScrollView(.vertical)` needing to scroll. Derived from
    /// `contentHeight` (rather than a hand-picked constant) plus
    /// `heightSafetyMargin` so it can't quietly fall behind again the way
    /// the old flat `413` did once the Function Keys/System sections were
    /// added, silently clipping "Layers & Special" out of view.
    ///
    /// It's a *maximum*, paired with `minHeight` and a `.layoutPriority(1)`
    /// at the call site (see `KeyMainContentView`) rather than a strict
    /// `.frame(height:)`: the priority makes the containing `VStack` hand
    /// the drawer this full height before the board gets any of what's
    /// left, so the no-scroll case still holds whenever the window has the
    /// room -- but a short window can still squeeze the drawer down to
    /// `minHeight` instead of forcing a window `minHeight` taller than a
    /// 1366x768 or 1440x900 laptop screen.
    static let maxHeight: Double = contentHeight + heightSafetyMargin

    /// Floor for the drawer when the window is too short to give it
    /// `maxHeight` -- roughly three sections plus the vertical scrollbar
    /// that appears once the rest overflows. This (not `maxHeight`) is what
    /// `ContentView`'s window `minHeight` has to reserve.
    static let minHeight: Double = 260

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                section("Letters", tokens: KeyName.letters.map { ActionToken.key($0) }, rows: 2)
                section("Numbers", tokens: KeyName.digits.map { ActionToken.key($0) })
                section("Editing & Punctuation", tokens: KeyName.editing.map { ActionToken.key($0) })
                section("Function Keys", tokens: KeyName.functionKeys.map { ActionToken.key($0) })
                section("Navigation", tokens: KeyName.navigation.map { ActionToken.key($0) })
                section("System", tokens: KeyName.system.map { ActionToken.key($0) })
                section("Modifiers", tokens: ModifierName.allCases.map { ActionToken.modifier($0) })
                layersAndSpecialSection
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
            ScrollView(.horizontal) {
                VStack(spacing: 8) {
                    ForEach(chunks.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            ForEach(chunks[i]) { token in
                                PaletteChip(token: token)
                            }
                        }
                    }
                }
            }
            .frame(height: contentHeight + Self.scrollBarReserve)
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
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    layerPickerGroup
                    HStack(spacing: 8) {
                        PaletteChip(token: .transparent)
                        PaletteChip(token: .none)
                        PaletteChip(token: .toggleConnection)
                    }
                }
            }
            .frame(height: Self.layersRowHeight + Self.scrollBarReserve)
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
