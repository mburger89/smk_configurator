import Foundation
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

    /// The width available to a section's chip rows, measured off a
    /// zero-height probe view (see `widthProbe`) since SwiftCrossUI has no
    /// wrapping stack/grid layout to lean on -- sections chunk their
    /// tokens into rows themselves based on this value. Starts at 0 (all
    /// tokens in one row) until the first layout pass measures the real
    /// width.
    @State private var contentWidth: Double = 0

    /// Fixed (not max) height for the drawer's outer frame -- tall enough
    /// to fit all 8 sections (Letters through Layers & Special) without
    /// the drawer's own internal `ScrollView(.vertical)` needing to
    /// scroll/clip. 413 (this constant's old value) predates the
    /// Function Keys/System sections and was no longer tall enough,
    /// silently clipping "Layers & Special" out of view with no visible
    /// scroll affordance. A *fixed* height (rather than
    /// `.frame(maxHeight:)`) is deliberate: `KeyMainContentView`'s
    /// containing `VStack` will happily shrink a flexible/max-height
    /// drawer to make room for the board above it when the window is
    /// short, which reintroduces the same clipping problem -- a strict
    /// height always reserves this much space instead.
    static let maxHeight: Double = 600

    /// `PaletteChip`'s fixed width (see `PaletteChip.body`'s
    /// `.frame(width: 44, height: 26)`), the spacing between chips within
    /// a wrapped row, and the spacing between wrapped rows themselves.
    private static let chipWidth: Double = 44
    private static let chipSpacing: Int = 8
    private static let rowSpacing: Int = 8

    var body: some View {
        // Scrolling both axes (not just `.vertical`) matters even though
        // there's nothing to horizontally scroll in steady state: it's what
        // makes SwiftCrossUI report this view's own width as whatever's
        // *proposed* to it rather than its wrapped content's natural width
        // (see `ScrollView.computeLayout`'s `outerSize.width = proposedSize
        // .width ?? ...`). Without that decoupling, the window-sizing pass
        // that probes the whole app with `proposedSize = .zero` to work out
        // the window's minimum size would see this drawer's *current* wide
        // content width as its structural minimum, permanently pinning the
        // window's minimum (and therefore resize handle) to roughly its
        // current width.
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 12) {
                widthProbe
                section("Letters", tokens: KeyName.letters.map { ActionToken.key($0) })
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
        .frame(height: Self.maxHeight)
        .background(RoundedRectangle(cornerRadius: 10).fill(chrome.surface))
    }

    /// A zero-height view whose sole purpose is reading the width
    /// SwiftCrossUI proposes to the sections column (via a background
    /// `GeometryReader`, which -- unlike the sections themselves -- is
    /// safe to size off the proposal directly since nothing here needs to
    /// report a content-driven size back up the tree) into `contentWidth`,
    /// so sections below can wrap their chip rows to it.
    private var widthProbe: some View {
        Color.clear
            .frame(height: 1)
            .background {
                GeometryReader { proxy in
                    // `proxy.size.width` swings between 0 and .infinity
                    // whenever an ancestor `HStack` (e.g. `ContentView`'s
                    // column layout) is probing this pane's flexibility to
                    // work out the *window's* resizable bounds -- only the
                    // finite readings reflect the column's actual width.
                    // Writing `contentWidth` synchronously here (as
                    // `computeLayout` runs) would recursively kick off a
                    // re-render in the middle of that ancestor's still-in-
                    // progress probe, corrupting it into reporting a fixed
                    // min==max width and locking the window's width resize
                    // handle -- deferring the write to the next run loop
                    // turn lets the probe finish first.
                    let width = proxy.size.width
                    Color.clear
                        .onChange(of: width, initial: true) {
                            guard width.isFinite else { return }
                            DispatchQueue.main.async {
                                contentWidth = width
                            }
                        }
                }
            }
    }

    private func section(_ title: String, tokens: [ActionToken]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(chrome.textTertiary)
            VStack(alignment: .leading, spacing: Self.rowSpacing) {
                let chunks = wrap(tokens, toWidth: contentWidth)
                ForEach(chunks.indices, id: \.self) { i in
                    HStack(spacing: justifiedSpacing(forCount: chunks[i].count)) {
                        ForEach(chunks[i]) { token in
                            PaletteChip(token: token)
                        }
                    }
                }
            }
        }
    }

    /// The gap to put between `count` chips so the row spans `contentWidth`
    /// edge-to-edge instead of leaving whatever's left over from `wrap`'s
    /// floor-based chip count sitting as unused trailing space -- widens
    /// `chipSpacing` just enough to absorb that remainder. Left at the base
    /// spacing for single-chip rows (nothing to stretch) or before
    /// `contentWidth` has been measured.
    private func justifiedSpacing(forCount count: Int) -> Int {
        guard count > 1, contentWidth > 0, contentWidth.isFinite else { return Self.chipSpacing }
        let gap = (contentWidth - Double(count) * Self.chipWidth) / Double(count - 1)
        return max(Self.chipSpacing, Int(gap))
    }

    /// Splits `tokens` into left-to-right rows that each fit within
    /// `width`, wrapping onto additional rows instead of overflowing --
    /// SwiftCrossUI has no wrapping stack/grid layout, so this does the
    /// chunking by hand from the width SwiftCrossUI proposes to
    /// `widthProbe`.
    private func wrap(_ tokens: [ActionToken], toWidth width: Double) -> [[ActionToken]] {
        guard width > 0, width.isFinite else { return [tokens] }
        let spacing = Double(Self.chipSpacing)
        let perRow = max(1, Int((width + spacing) / (Self.chipWidth + spacing)))
        return stride(from: 0, to: tokens.count, by: perRow).map {
            Array(tokens[$0..<min($0 + perRow, tokens.count)])
        }
    }

    private var layersAndSpecialSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LAYERS & SPECIAL")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(chrome.textTertiary)
            HStack(spacing: 12) {
                layerPickerGroup
                HStack(spacing: 8) {
                    PaletteChip(token: .transparent)
                    PaletteChip(token: .none)
                    PaletteChip(token: .toggleConnection)
                }
            }
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
                editor.pendingLayerIndex = min(15, editor.pendingLayerIndex + 1)
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
