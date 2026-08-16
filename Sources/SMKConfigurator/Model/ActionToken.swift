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

/// Matches `KeyCode.fromCString` exactly.
enum KeyName: String, CaseIterable, Hashable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
    case n1 = "1", n2 = "2", n3 = "3", n4 = "4", n5 = "5"
    case n6 = "6", n7 = "7", n8 = "8", n9 = "9", n0 = "0"
    case enter, escape, backspace, tab, space
    case minus, equal, leftBracket, rightBracket, backslash, semicolon, quote, grave, comma, period, slash
    case capsLock, delete
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    case printScreen, scrollLock, pause, application
    case left, right, up, down, home, pageUp, pageDown, end

    static let letters: [KeyName] = [.a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m,
                                      .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z]
    static let digits: [KeyName] = [.n1, .n2, .n3, .n4, .n5, .n6, .n7, .n8, .n9, .n0]
    /// All symbol/punctuation keys on a standard US ANSI keyboard, in HID
    /// usage order -- matches `KeyCode`'s case order in the firmware's
    /// `LayerEngine.swift` exactly (`minus` 0x2D through `slash` 0x38), plus
    /// the two other common single-purpose editing keys (`capsLock`,
    /// `delete` -- forward delete, distinct from `backspace`).
    static let editing: [KeyName] = [.enter, .escape, .backspace, .tab, .space,
                                      .minus, .equal, .leftBracket, .rightBracket, .backslash,
                                      .semicolon, .quote, .grave, .comma, .period, .slash,
                                      .capsLock, .delete]
    static let functionKeys: [KeyName] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]
    /// Keys that don't move the cursor/selection but round out the standard
    /// HID keyboard usage table (0x46-0x48, 0x65) -- grouped separately from
    /// `editing` since they're rarer/system-facing rather than everyday
    /// editing actions.
    static let system: [KeyName] = [.printScreen, .scrollLock, .pause, .application]
    static let navigation: [KeyName] = [.left, .right, .up, .down, .home, .pageUp, .pageDown, .end]

    var displayLabel: String {
        switch self {
        case .enter: return "⏎"
        case .escape: return "Esc"
        case .backspace: return "⌫"
        case .tab: return "⇥"
        case .space: return "␣"
        case .minus: return "-"
        case .equal: return "="
        case .leftBracket: return "["
        case .rightBracket: return "]"
        case .backslash: return "\\"
        case .semicolon: return ";"
        case .quote: return "'"
        case .grave: return "`"
        case .comma: return ","
        case .period: return "."
        case .slash: return "/"
        case .capsLock: return "Caps"
        case .delete: return "⌦"
        case .printScreen: return "PrtSc"
        case .scrollLock: return "ScrLk"
        case .pause: return "Pause"
        case .application: return "Menu"
        case .left: return "←"
        case .right: return "→"
        case .up: return "↑"
        case .down: return "↓"
        case .home: return "Home"
        case .pageUp: return "PgUp"
        case .pageDown: return "PgDn"
        case .end: return "End"
        default: return rawValue.uppercased()
        }
    }
}

/// Matches `Modifier.fromCString` exactly.
enum ModifierName: String, CaseIterable, Hashable {
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
