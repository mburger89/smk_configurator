import Foundation

/// Arbitrary JSON, used to carry a macro step this build doesn't understand
/// through a load/save cycle unchanged. Same lossless principle as
/// `KeymapDocument`'s raw cell strings and `ActionToken.raw`.
enum JSONValue: Codable, Equatable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrepresentable JSON")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v):
            // Whole numbers encode as integers so a round-tripped "ms": 400
            // doesn't become 400.0 in the file the firmware parses.
            if v == v.rounded(), abs(v) < 9_007_199_254_740_992 { try c.encode(Int(v)) }
            else { try c.encode(v) }
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

/// How a `.text` step reaches the host.
enum TextDelivery: String, Codable, Equatable, Hashable, CaseIterable {
    case keystrokes, paste
}

/// The layer action a `.layer` step performs, mirroring the `mo:`/`tg:`
/// tokens `ActionToken` already understands.
enum LayerOp: String, Codable, Equatable, Hashable, CaseIterable {
    case momentary = "mo"
    case toggle = "tg"
}

/// One step of a macro. Mirrors the `steps` schema in
/// `docs/superpowers/specs/2026-08-20-macro-creation-design.md` (C1).
///
/// `.raw` carries a step type this build doesn't know. It is preserved on
/// save and never executed, so a macro authored by a newer build survives
/// an older build opening and saving the file.
enum MacroStep: Codable, Equatable, Hashable, Identifiable {
    case keystroke(mods: [ModifierName], key: KeyName?, holdMs: Int)
    case text(String, delivery: TextDelivery, msPerChar: Int)
    case delay(ms: Int)
    case layer(op: LayerOp, n: Int)
    case repeatBlock(count: Int, steps: [MacroStep])
    case raw(JSONValue)

    var id: String { typeCode + String(describing: self).hashValue.description }

    /// The three-letter badge shown in the palette and on sequence rows.
    var typeCode: String {
        switch self {
        case .keystroke: return "KEY"
        case .text: return "TXT"
        case .delay: return "DLY"
        case .layer: return "LYR"
        case .repeatBlock: return "RPT"
        case .raw: return "???"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case t, k, mods, hold, s, cpm, delivery, ms, op, n, count, steps
    }

    init(from decoder: Decoder) throws {
        // A step whose "t" is missing or unrecognized is kept verbatim.
        guard let c = try? decoder.container(keyedBy: CodingKeys.self),
              let t = try? c.decode(String.self, forKey: .t)
        else {
            self = .raw(try JSONValue(from: decoder))
            return
        }
        switch t {
        case "key":
            let mods = (try? c.decode([ModifierName].self, forKey: .mods)) ?? []
            let keyString = try? c.decode(String.self, forKey: .k)
            let key = keyString.flatMap { s -> KeyName? in
                guard s.hasPrefix("key:") else { return nil }
                return KeyName(rawValue: String(s.dropFirst(4)))
            }
            self = .keystroke(mods: mods, key: key,
                              holdMs: (try? c.decode(Int.self, forKey: .hold)) ?? 40)
        case "text":
            self = .text((try? c.decode(String.self, forKey: .s)) ?? "",
                         delivery: (try? c.decode(TextDelivery.self, forKey: .delivery)) ?? .keystrokes,
                         msPerChar: (try? c.decode(Int.self, forKey: .cpm)) ?? 12)
        case "delay":
            self = .delay(ms: (try? c.decode(Int.self, forKey: .ms)) ?? 0)
        case "layer":
            self = .layer(op: (try? c.decode(LayerOp.self, forKey: .op)) ?? .momentary,
                          n: (try? c.decode(Int.self, forKey: .n)) ?? 0)
        case "rpt":
            let inner = (try? c.decode([MacroStep].self, forKey: .steps)) ?? []
            // Repeat blocks don't nest — the firmware's player uses a single
            // loop counter, not a stack. A nested block written by some other
            // tool is kept verbatim so saving can't destroy it, but it is
            // never executed or edited as a repeat block.
            let nests = inner.contains { if case .repeatBlock = $0 { return true } else { return false } }
            if nests {
                self = .raw(try JSONValue(from: decoder))
            } else {
                self = .repeatBlock(count: (try? c.decode(Int.self, forKey: .count)) ?? 1, steps: inner)
            }
        default:
            self = .raw(try JSONValue(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        if case .raw(let value) = self {
            try value.encode(to: encoder)
            return
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .keystroke(let mods, let key, let holdMs):
            try c.encode("key", forKey: .t)
            if let key { try c.encode("key:\(key.rawValue)", forKey: .k) }
            try c.encode(mods, forKey: .mods)
            try c.encode(holdMs, forKey: .hold)
        case .text(let s, let delivery, let msPerChar):
            try c.encode("text", forKey: .t)
            try c.encode(s, forKey: .s)
            try c.encode(delivery, forKey: .delivery)
            try c.encode(msPerChar, forKey: .cpm)
        case .delay(let ms):
            try c.encode("delay", forKey: .t)
            try c.encode(ms, forKey: .ms)
        case .layer(let op, let n):
            try c.encode("layer", forKey: .t)
            try c.encode(op, forKey: .op)
            try c.encode(n, forKey: .n)
        case .repeatBlock(let count, let steps):
            try c.encode("rpt", forKey: .t)
            try c.encode(count, forKey: .count)
            try c.encode(steps, forKey: .steps)
        case .raw:
            break // handled above
        }
    }
}

/// One macro. `id` is the slot the firmware stores it in and the number the
/// `macro:<id>` action token names.
struct MacroDefinition: Codable, Equatable, Hashable, Identifiable {
    var id: Int
    var name: String
    var steps: [MacroStep]

    init(id: Int, name: String, steps: [MacroStep]) {
        self.id = id
        self.name = name
        self.steps = steps
    }
}

// MARK: - Compiled size

/// The on-board bytecode layout. These widths are the contract between this
/// editor's byte meter and the firmware's macro player; changing one without
/// the other makes the meter lie. See contract C3 in
/// `docs/superpowers/specs/2026-08-20-macro-creation-design.md`.
///
///   keystroke   opcode(1) + mods(1) + keycode(1) + holdMs(2)      = 5
///   delay       opcode(1) + ms(2)                                 = 3
///   layer       opcode(1) + op(1) + index(1)                      = 3
///   text        opcode(1) + msPerChar(1) + length(1) + payload    = 3 + n
///   repeat      opcode(1) + count(1) + bodyLength(2) + body       = 4 + body
///   macro       id(1) + nameLength(1) + name + stepCount(1)       = 3 + name + steps
extension MacroStep {
    var compiledSize: Int {
        switch self {
        case .keystroke: return 5
        case .delay: return 3
        case .layer: return 3
        case .text(let s, _, _): return 3 + s.utf8.count
        case .repeatBlock(_, let steps): return 4 + steps.reduce(0) { $0 + $1.compiledSize }
        case .raw: return 0 // never compiled, so it costs no board memory
        }
    }

    /// Milliseconds this step is expected to take when the board runs it.
    var estimatedDurationMs: Int {
        switch self {
        case .keystroke(_, _, let holdMs): return holdMs
        case .delay(let ms): return ms
        case .text(let s, _, let msPerChar): return s.count * msPerChar
        case .layer: return 0
        case .repeatBlock(let count, let steps):
            return count * steps.reduce(0) { $0 + $1.estimatedDurationMs }
        case .raw: return 0
        }
    }
}

extension MacroDefinition {
    var compiledSize: Int {
        3 + name.utf8.count + steps.reduce(0) { $0 + $1.compiledSize }
    }

    var estimatedDurationMs: Int {
        steps.reduce(0) { $0 + $1.estimatedDurationMs }
    }

    /// "0.52 s est." as shown under the macro name in the canvas header.
    var estimatedDurationLabel: String {
        String(format: "%.2f s est.", Double(estimatedDurationMs) / 1000)
    }
}
