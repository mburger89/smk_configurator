import Foundation

/// A key/action the firmware understands, exactly matching the vocabulary
/// parsed by `KeyAction.fromCString` / `KeyCode.fromCString` /
/// `Modifier.fromCString` in `~/esp/SMK/Sources/smk/LayerEngine.swift`.
/// Nothing produced by `canonicalString` should ever resolve to `.noKey`
/// on the firmware side unless it's genuinely meant to be empty.
enum ActionToken: Equatable, Identifiable, Hashable {
    case key(KeyName)
    case modifier(ModifierName)
    case momentaryLayer(Int)
    case toggleLayer(Int)
    case transparent
    case none
    case toggleConnection
    /// Anything loaded from a file that doesn't match the known vocabulary.
    /// Preserved verbatim so loading never silently drops data.
    case raw(String)

    var id: String { canonicalString }

    var canonicalString: String {
        switch self {
        case .key(let name): return "key:\(name.rawValue)"
        case .modifier(let mod): return "mod:\(mod.rawValue)"
        case .momentaryLayer(let n): return "mo:\(n)"
        case .toggleLayer(let n): return "tg:\(n)"
        case .transparent: return "trans"
        case .none: return "none"
        case .toggleConnection: return "toggle_conn"
        case .raw(let s): return s
        }
    }

    var displayLabel: String {
        switch self {
        case .key(let name): return name.displayLabel
        case .modifier(let mod): return mod.displayLabel
        case .momentaryLayer(let n): return "MO\(n)"
        case .toggleLayer(let n): return "TG\(n)"
        case .transparent: return "▽"
        case .none: return ""
        case .toggleConnection: return "⇄ Conn"
        case .raw(let s): return s
        }
    }

    /// Parses a raw `keymap.json` cell string. Falls back to `.raw` for
    /// anything unrecognized rather than losing the original text.
    static func parse(_ s: String) -> ActionToken {
        if s == "none" { return .none }
        if s == "trans" || s == "transparent" { return .transparent }
        if s == "toggle_conn" { return .toggleConnection }
        if s.hasPrefix("key:"), let name = KeyName(rawValue: String(s.dropFirst(4))) {
            return .key(name)
        }
        if s.hasPrefix("mod:"), let mod = ModifierName(rawValue: String(s.dropFirst(4))) {
            return .modifier(mod)
        }
        if s.hasPrefix("mo:"), let n = Int(s.dropFirst(3)) {
            return .momentaryLayer(n)
        }
        if s.hasPrefix("tg:"), let n = Int(s.dropFirst(3)) {
            return .toggleLayer(n)
        }
        return .raw(s)
    }
}

// KeyName lives in KeyCodesGenerated.swift now -- generated from
// ~/esp/SMK/keycodes.json by that repo's generate_keycodes.sh, which emits
// the matching KeyCode into the firmware from the same manifest. The grammar
// above (ActionToken's key:/mod:/mo:/tg: prefixes) stays hand-written; only
// the vocabulary it dispatches into is generated.

/// Matches `Modifier.fromCString` exactly.
enum ModifierName: String, CaseIterable, Hashable, Codable {
    case leftCtrl, leftShift, leftAlt, leftGUI
    case rightCtrl, rightShift, rightAlt, rightGUI

    var displayLabel: String {
        switch self {
        case .leftCtrl: return "LCtl"
        case .leftShift: return "LSft"
        case .leftAlt: return "LAlt"
        case .leftGUI: return "LGUI"
        case .rightCtrl: return "RCtl"
        case .rightShift: return "RSft"
        case .rightAlt: return "RAlt"
        case .rightGUI: return "RGUI"
        }
    }
}
