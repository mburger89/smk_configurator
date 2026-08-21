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
            // A "mods" array containing even one modifier outside this
            // build's vocabulary must not silently drop the whole array
            // (including the modifiers it *does* recognize) -- the whole
            // step is preserved instead. Same principle for "k": a key
            // string this build can't resolve must not be silently stripped
            // down to a modifiers-only chord.
            let mods: [ModifierName]
            if c.contains(.mods) {
                guard let decodedMods = try? c.decode([ModifierName].self, forKey: .mods) else {
                    self = .raw(try JSONValue(from: decoder))
                    return
                }
                mods = decodedMods
            } else {
                mods = []
            }

            let key: KeyName?
            if c.contains(.k) {
                guard let keyString = try? c.decode(String.self, forKey: .k),
                      keyString.hasPrefix("key:"),
                      let resolved = KeyName(rawValue: String(keyString.dropFirst(4)))
                else {
                    self = .raw(try JSONValue(from: decoder))
                    return
                }
                key = resolved
            } else {
                key = nil
            }

            self = .keystroke(mods: mods, key: key,
                              holdMs: (try? c.decode(Int.self, forKey: .hold)) ?? 40)
        case "text":
            // An unrecognized delivery value (e.g. a future build's
            // "clipboard") must not silently normalize to "keystrokes" --
            // that would change what the step does when replayed.
            let delivery: TextDelivery
            if c.contains(.delivery) {
                guard let decoded = try? c.decode(TextDelivery.self, forKey: .delivery) else {
                    self = .raw(try JSONValue(from: decoder))
                    return
                }
                delivery = decoded
            } else {
                delivery = .keystrokes
            }
            self = .text((try? c.decode(String.self, forKey: .s)) ?? "",
                         delivery: delivery,
                         msPerChar: (try? c.decode(Int.self, forKey: .cpm)) ?? 12)
        case "delay":
            self = .delay(ms: (try? c.decode(Int.self, forKey: .ms)) ?? 0)
        case "layer":
            // Same reasoning as "delivery" above: an unrecognized op (e.g. a
            // future "osl") must not silently normalize to "momentary".
            let op: LayerOp
            if c.contains(.op) {
                guard let decoded = try? c.decode(LayerOp.self, forKey: .op) else {
                    self = .raw(try JSONValue(from: decoder))
                    return
                }
                op = decoded
            } else {
                op = .momentary
            }
            self = .layer(op: op, n: (try? c.decode(Int.self, forKey: .n)) ?? 0)
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

    /// Any per-macro field this build doesn't have a model property for --
    /// e.g. a future build's "enabled" flag. Carried through unchanged on
    /// save, same lossless principle as `MacroStep.raw`: this build not
    /// knowing a field must not mean it gets to delete it.
    private var unknownFields: [String: JSONValue] = [:]

    init(id: Int, name: String, steps: [MacroStep]) {
        self.id = id
        self.name = name
        self.steps = steps
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, steps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        steps = try c.decode([MacroStep].self, forKey: .steps)

        let dynamic = try decoder.container(keyedBy: DynamicCodingKey.self)
        for key in dynamic.allKeys where CodingKeys(stringValue: key.stringValue) == nil {
            unknownFields[key.stringValue] = try dynamic.decode(JSONValue.self, forKey: key)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(steps, forKey: .steps)

        var dynamic = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in unknownFields {
            guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
            try dynamic.encode(value, forKey: codingKey)
        }
    }
}

/// A `CodingKey` that accepts any string, used to enumerate and re-emit
/// JSON object fields `MacroDefinition`'s `CodingKeys` doesn't name.
private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// A way a `MacroStep` or `MacroDefinition` would overflow a one-byte field
/// in the on-board bytecode layout (see `MacroStep.compiledSize`'s doc
/// comment for the full layout). The JSON model itself has no such limits
/// (a `String` can be any length), so nothing else catches this before the
/// firmware would receive a length byte that has wrapped around.
enum MacroOverflow: Equatable, Hashable {
    /// A `.text` step's payload exceeds `MacroStep.maxTextPayloadBytes`
    /// (255), the most the one-byte `length` field can express.
    case textPayloadTooLong(byteCount: Int)
    /// A macro's `name` exceeds `MacroDefinition.maxNameBytes` (255), the
    /// most the one-byte `nameLength` field can express.
    case macroNameTooLong(byteCount: Int)
    /// A macro has more top-level steps than `MacroDefinition.maxStepCount`
    /// (255), the most the one-byte `stepCount` field can express.
    case tooManySteps(count: Int)

    /// A human-readable description the UI can show as-is.
    var message: String {
        switch self {
        case .textPayloadTooLong(let byteCount):
            return "Text payload is \(byteCount) bytes; the board format allows at most \(MacroStep.maxTextPayloadBytes)."
        case .macroNameTooLong(let byteCount):
            return "Macro name is \(byteCount) bytes; the board format allows at most \(MacroDefinition.maxNameBytes)."
        case .tooManySteps(let count):
            return "Macro has \(count) steps; the board format allows at most \(MacroDefinition.maxStepCount)."
        }
    }
}

// MARK: - Compiled size

/// The on-board bytecode layout. These widths are the contract between this
/// editor's byte meter and the firmware's macro player; changing one without
/// the other makes the meter lie. See contract C3 in
/// `docs/superpowers/specs/2026-08-20-macro-creation-design.md`, and
/// `CLAUDE.md`'s "Firmware coupling" section for the full wire-format
/// contract (opcode values, endianness, modifier bit order, keycode
/// derivation) this table summarizes.
///
///   keystroke   opcode(1) + mods(1) + keycode(1) + holdMs(2)              = 5
///   delay       opcode(1) + ms(2)                                         = 3
///   layer       opcode(1) + op(1) + index(1)                              = 3
///   text        opcode(1) + delivery(1) + msPerChar(1) + length(1)
///               + payload                                                 = 4 + n
///   repeat      opcode(1) + count(1) + bodyLength(2) + body               = 4 + body
///   macro       id(1) + nameLength(1) + name + stepCount(1)               = 3 + name + steps
///
/// `length(1)`, `nameLength(1)`, and `stepCount(1)` are one-byte fields, so
/// each has a hard 255 maximum the JSON model doesn't otherwise enforce --
/// see `MacroStep.overflows` and `MacroDefinition.overflows` below.
extension MacroStep {
    /// The largest UTF-8 byte count a `.text` step's payload can have: the
    /// on-board layout's `length` field is one byte.
    static let maxTextPayloadBytes = 255

    var compiledSize: Int {
        switch self {
        case .keystroke: return 5
        case .delay: return 3
        case .layer: return 3
        case .text(let s, _, _): return 4 + s.utf8.count
        case .repeatBlock(_, let steps): return 4 + steps.reduce(0) { $0 + $1.compiledSize }
        case .raw: return 0 // never compiled, so it costs no board memory
        }
    }

    /// Every way this step (or, for `.repeatBlock`, a step nested inside it)
    /// would overflow a one-byte bytecode field the on-board layout can't
    /// express. Empty for a step that compiles cleanly. `.raw` never
    /// overflows -- it is never compiled, so it never reaches the firmware.
    var overflows: [MacroOverflow] {
        switch self {
        case .text(let s, _, _):
            let n = s.utf8.count
            return n > Self.maxTextPayloadBytes ? [.textPayloadTooLong(byteCount: n)] : []
        case .repeatBlock(_, let steps):
            return steps.flatMap(\.overflows)
        default:
            return []
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

// MARK: - Row display

extension MacroStep {
    /// The middle column of a sequence row.
    var payloadSummary: String {
        switch self {
        case .keystroke(let mods, let key, _):
            let parts = mods.map(\.displayLabel) + (key.map { [$0.displayLabel] } ?? [])
            return parts.joined(separator: " + ")
        case .text(let s, _, _):
            return "\"\(s)\""
        case .delay(let ms):
            return "Wait \(ms) ms"
        case .layer(let op, let n):
            return op == .momentary
                ? "Momentary layer \(n) while running"
                : "Toggle layer \(n)"
        case .repeatBlock(let count, let steps):
            let noun = steps.count == 1 ? "step" : "steps"
            return "Repeat \(steps.count) \(noun) \(count) times"
        case .raw:
            return "Unsupported step (kept on save)"
        }
    }

    /// The right-aligned metadata of a sequence row. Empty when the payload
    /// already says everything.
    var metadataLabel: String {
        switch self {
        case .keystroke(_, _, let holdMs): return "hold \(holdMs) ms"
        case .text(let s, _, _): return "\(s.count) chars"
        case .delay: return ""
        case .layer(let op, let n): return "\(op.rawValue.uppercased())\(n)"
        case .repeatBlock(let count, _): return "\(count)×"
        case .raw: return ""
        }
    }
}

extension MacroDefinition {
    /// The largest UTF-8 byte count a macro's `name` can have: the on-board
    /// layout's `nameLength` field is one byte.
    static let maxNameBytes = 255

    /// The largest number of top-level steps a macro can have: the on-board
    /// layout's `stepCount` field is one byte. (Steps nested inside a
    /// `.repeatBlock` aren't counted against this -- the block's body has
    /// its own two-byte `bodyLength`, not a step count.)
    static let maxStepCount = 255

    var compiledSize: Int {
        3 + name.utf8.count + steps.reduce(0) { $0 + $1.compiledSize }
    }

    /// Every way this macro would overflow a one-byte bytecode field the
    /// on-board layout can't express: its own `name`/`steps.count`, plus
    /// anything reported by its steps (e.g. an oversized `.text` payload,
    /// including one nested inside a `.repeatBlock`). Empty for a macro
    /// that compiles cleanly. The UI should consult this (or
    /// `isCompilable`) before offering to flash.
    var overflows: [MacroOverflow] {
        var result: [MacroOverflow] = []
        let nameBytes = name.utf8.count
        if nameBytes > Self.maxNameBytes {
            result.append(.macroNameTooLong(byteCount: nameBytes))
        }
        if steps.count > Self.maxStepCount {
            result.append(.tooManySteps(count: steps.count))
        }
        result.append(contentsOf: steps.flatMap(\.overflows))
        return result
    }

    /// Whether this macro's compiled form fits the on-board bytecode
    /// layout's one-byte fields. Equivalent to `overflows.isEmpty`.
    var isCompilable: Bool { overflows.isEmpty }

    var estimatedDurationMs: Int {
        steps.reduce(0) { $0 + $1.estimatedDurationMs }
    }

    /// "0.52 s est." as shown under the macro name in the canvas header.
    var estimatedDurationLabel: String {
        String(format: "%.2f s est.", Double(estimatedDurationMs) / 1000)
    }

    /// "macro:5 · 2 steps · 0.50 s est." -- the canvas header's metadata
    /// line, under the macro name. Named distinctly from `MacroStep`'s own
    /// `metadataLabel` (a sequence row's right-aligned string) since the two
    /// are unrelated strings for different views that happened to want the
    /// same generic name.
    var canvasSummary: String {
        "macro:\(id) · \(steps.count) steps · \(estimatedDurationLabel)"
    }
}
