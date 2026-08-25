import Foundation

// Binary keymap cell encoding: one action tag byte + one parameter byte.
// See ~/esp/SMK/docs/superpowers/specs/2026-08-21-binary-keymap-format-design.md.
//
// This is the wire/storage format the firmware decodes
// (~/esp/SMK/Sources/SMKCore/KeymapBinary.swift) -- a fixed two-byte stride
// per cell, chosen so 16 layers fit inside the existing 4085-byte keymap
// store (the JSON encoding this replaces costs ~11.9 bytes/cell and never
// actually fit 16 layers). The tag table below must stay in lockstep with
// the firmware's `KeymapCellTag`.

/// The action-tag byte of a two-byte binary keymap cell. Raw values are the
/// wire format, pinned against the firmware's own `KeymapCellTag`
/// (`~/esp/SMK/Sources/SMKCore/KeymapBinary.swift:15-24`) -- do not renumber
/// existing cases without also updating the firmware.
enum KeymapCellTag: UInt8 {
    case none = 0
    case key = 1
    case modifier = 2
    case momentaryLayer = 3
    case toggleLayer = 4
    case transparent = 5
    case toggleConnection = 6
    case macro = 7
}

/// A token this build cannot put on the wire.
///
/// `KeymapDocument` keeps cells as raw strings so a token this build doesn't
/// understand survives a load/save round trip -- but a two-byte cell can't
/// encode an arbitrary string, so that guarantee cannot cross the wire. The
/// resolution is a split: the file stays lossless, and the compiler refuses.
/// A token the firmware has no tag for is one the board could never have
/// executed anyway, so refusing to flash it -- naming it -- is better than
/// silently dropping it. The same reasoning applies to a parameter that
/// doesn't fit one byte: silently wrapping (`macro:256` truncating to
/// `macro:0`) would bind a key to a completely different macro than the
/// user chose, a bug that presents as a hardware fault.
enum KeymapCompileError: Error, Equatable, CustomStringConvertible {
    /// `token`'s canonical string has no binary tag at all -- an
    /// `ActionToken.raw` this build's grammar didn't recognize.
    case unsupportedToken(token: String)
    /// `token`'s parameter doesn't fit the one-byte wire field: either it
    /// overflows `UInt8` outright (a macro slot), or it names a layer at or
    /// past the firmware's actual ceiling (`firmwareLayerCeiling`, matching
    /// `EditorState.maxLayerCount`) even though the raw number would
    /// otherwise fit in a byte.
    case parameterOutOfRange(token: String, value: Int, limit: Int)
    /// A cell somewhere in the document failed to compile -- wraps the
    /// per-cell failure (`reason`, that error's own `description`) with
    /// where it lives, so the message names both the token and its
    /// layer/row/column rather than just the token.
    case invalidCell(layer: Int, row: Int, col: Int, token: String, reason: String)
    /// A `.text` macro step contains a character the firmware's typing
    /// table has no entry for. That table (see
    /// `~/esp/SMK/Sources/SMKCore/` -- the ASCII-to-keystroke lookup the
    /// macro player's text step drives) covers only printable ASCII
    /// (`0x20`...`0x7E`) and assumes a US QWERTY host layout; anything else
    /// returns nil and the firmware aborts the macro rather than typing a
    /// substitute. Refusing here, before the byte ever reaches the board,
    /// is the same reasoning as `unsupportedToken`: a keyboard that types
    /// something else is worse than one that types nothing, so this is
    /// named and refused rather than silently dropped or substituted.
    /// `token` is a description of the macro/step this character was found
    /// in (not an `ActionToken`), matching how `parameterOutOfRange` already
    /// reuses that label for a non-token description.
    case unsupportedCharacter(token: String, character: Character, index: Int)

    var description: String {
        switch self {
        case .unsupportedToken(let token):
            return "Cannot compile \"\(token)\": the firmware has no binary tag for this token."
        case .parameterOutOfRange(let token, let value, let limit):
            return "Cannot compile \"\(token)\": parameter \(value) exceeds the maximum of \(limit) the one-byte wire field allows."
        case .invalidCell(let layer, let row, let col, let token, let reason):
            return "Layer \(layer), row \(row), col \(col) (\"\(token)\"): \(reason)"
        case .unsupportedCharacter(let token, let character, let index):
            let codepoint = character.unicodeScalars.first.map { String(format: "U+%04X", $0.value) } ?? "?"
            return "Cannot compile \"\(token)\": character '\(character)' (\(codepoint)) at position \(index) is outside the printable ASCII range the firmware can type (0x20-0x7E)."
        }
    }
}

/// Whether `self` is a single printable-ASCII character (`0x20`...`0x7E`)
/// the firmware's text-typing table can look up. A grapheme cluster made of
/// more than one Unicode scalar (e.g. a base letter plus a combining mark)
/// is never printable ASCII on its own, so it's rejected without inspecting
/// its scalars individually.
private extension Character {
    var isPrintableASCII: Bool {
        guard unicodeScalars.count == 1, let scalar = unicodeScalars.first else { return false }
        return (0x20...0x7E).contains(scalar.value)
    }
}

/// The first character in `s` (if any) the firmware's text-typing table
/// cannot look up, paired with its character-index for a message that lets
/// a user locate it inside a long string rather than just naming the
/// character in isolation.
private func firstUnsupportedCharacter(in s: String) -> (character: Character, index: Int)? {
    for (index, character) in s.enumerated() where !character.isPrintableASCII {
        return (character, index)
    }
    return nil
}

/// Encodes one keymap cell's parsed token as the (tag, parameter) byte pair
/// the firmware's `decodeCell` reads back
/// (`~/esp/SMK/Sources/SMKCore/KeymapBinary.swift:28-47`). Throws rather
/// than truncating or dropping anything that doesn't fit -- see
/// `KeymapCompileError`'s doc comment for why.
func encodeCell(_ token: ActionToken) throws -> (UInt8, UInt8) {
    switch token {
    case .none:
        return (KeymapCellTag.none.rawValue, 0)
    case .transparent:
        return (KeymapCellTag.transparent.rawValue, 0)
    case .toggleConnection:
        return (KeymapCellTag.toggleConnection.rawValue, 0)
    case .key(let name):
        return (KeymapCellTag.key.rawValue, name.hidUsage)
    case .modifier(let mod):
        return (KeymapCellTag.modifier.rawValue, modifierBit(mod))
    case .momentaryLayer(let layer):
        return (KeymapCellTag.momentaryLayer.rawValue, try layerIndexByte(layer, token: token))
    case .toggleLayer(let layer):
        return (KeymapCellTag.toggleLayer.rawValue, try layerIndexByte(layer, token: token))
    case .macro(let slot):
        return (KeymapCellTag.macro.rawValue, try oneByteParameter(slot, token: token))
    case .raw:
        throw KeymapCompileError.unsupportedToken(token: token.canonicalString)
    }
}

/// Decodes a (tag, parameter) byte pair back into an `ActionToken`.
///
/// This exists for tests only, so the round-trip assertion in
/// `KeymapCompilerTests` means something. Nothing in the app should call
/// it: the document model stays JSON text end to end, and decoding binary
/// cells back into the app is not a real code path -- the firmware is the
/// only thing that ever reads the wire format this decodes. Do not wire
/// this into `EditorState` or any view.
func decodeCell(_ tag: UInt8, _ param: UInt8) -> ActionToken {
    guard let cellTag = KeymapCellTag(rawValue: tag) else { return .none }
    switch cellTag {
    case .none:
        return .none
    case .transparent:
        return .transparent
    case .toggleConnection:
        return .toggleConnection
    case .key:
        guard let name = KeyName.allCases.first(where: { $0.hidUsage == param }) else { return .none }
        return .key(name)
    case .modifier:
        guard let mod = modifier(fromBit: param) else { return .none }
        return .modifier(mod)
    case .momentaryLayer:
        return .momentaryLayer(Int(param))
    case .toggleLayer:
        return .toggleLayer(Int(param))
    case .macro:
        return .macro(Int(param))
    }
}

// MARK: - Modifier bit packing

/// `ModifierName`'s bit is its position in `CaseIterable` declaration order,
/// LSB first -- `leftCtrl, leftShift, leftAlt, leftGUI, rightCtrl,
/// rightShift, rightAlt, rightGUI` are bits 0-7. That is deliberately the
/// standard USB HID modifier byte layout; the firmware verified its own
/// `Modifier` agrees.
private func modifierBit(_ mod: ModifierName) -> UInt8 {
    guard let index = ModifierName.allCases.firstIndex(of: mod) else {
        // Unreachable: every ModifierName case appears exactly once in its
        // own CaseIterable.allCases.
        return 0
    }
    return UInt8(1 << index)
}

private func modifier(fromBit bit: UInt8) -> ModifierName? {
    let cases = ModifierName.allCases
    for index in cases.indices where (1 << index) == Int(bit) {
        return cases[index]
    }
    return nil
}

// MARK: - Parameter range checks

/// The firmware's own layer ceiling -- see `EditorState.maxLayerCount`'s doc
/// comment for why this is 16 (`LayerEngine`'s `toggledLayers`/
/// `momentaryCounts` are sized `count: 16`). Duplicated as a plain
/// non-isolated constant, rather than referring to `EditorState.maxLayerCount`
/// directly, because `EditorState` is `@MainActor`-isolated and this
/// compiler must run synchronously off the main actor; bump both together
/// if the firmware's ceiling ever changes.
private let firmwareLayerCeiling = 16

/// Validates a `mo:`/`tg:` layer index against both limits that apply: the
/// one-byte wire field, and the firmware's actual layer ceiling
/// (`firmwareLayerCeiling`, 16). A value like 16 fits in a byte fine but
/// names a layer `LayerEngine` can never activate, so it's refused here
/// rather than encoded as a token that would silently never fire.
private func layerIndexByte(_ layer: Int, token: ActionToken) throws -> UInt8 {
    guard layer >= 0, layer < firmwareLayerCeiling else {
        throw KeymapCompileError.parameterOutOfRange(
            token: token.canonicalString, value: layer, limit: firmwareLayerCeiling - 1)
    }
    return UInt8(layer)
}

/// Validates a parameter that only needs to fit the one-byte wire field
/// itself (currently just the macro slot -- there is no separate macro
/// ceiling below 256 the way there is for layers).
private func oneByteParameter(_ value: Int, token: ActionToken) throws -> UInt8 {
    guard value >= 0, value <= Int(UInt8.max) else {
        throw KeymapCompileError.parameterOutOfRange(
            token: token.canonicalString, value: value, limit: Int(UInt8.max))
    }
    return UInt8(value)
}

// MARK: - Whole-document compile

/// Same one-byte range check as `oneByteParameter(_:token:)` above, but for
/// a header/matrix/macro field that has no `ActionToken` to name -- these
/// take a plain description string instead, reusing `.parameterOutOfRange`
/// rather than adding a parallel error case for a field that doesn't fit.
private func oneBytePayloadField(_ value: Int, describedAs description: String) throws -> UInt8 {
    guard value >= 0, value <= Int(UInt8.max) else {
        throw KeymapCompileError.parameterOutOfRange(token: description, value: value, limit: Int(UInt8.max))
    }
    return UInt8(value)
}

/// Same idea as `oneBytePayloadField(_:describedAs:)`, for the little-endian
/// two-byte fields (`holdMs`, `ms`, `bodyLength`).
private func twoByteLEPayloadField(_ value: Int, describedAs description: String) throws -> (UInt8, UInt8) {
    guard value >= 0, value <= Int(UInt16.max) else {
        throw KeymapCompileError.parameterOutOfRange(token: description, value: value, limit: Int(UInt16.max))
    }
    let widened = UInt16(value)
    return (UInt8(widened & 0xFF), UInt8((widened >> 8) & 0xFF))
}

/// `ModifierName`'s bits OR'd together -- a keystroke step's `mods` is a
/// chord, not a single modifier, but the wire byte packs the same way
/// `modifierBit(_:)` packs one.
private func modifierBits(_ mods: [ModifierName]) -> UInt8 {
    mods.reduce(UInt8(0)) { $0 | modifierBit($1) }
}

/// Encodes one macro step to the bytes `~/esp/SMK/Sources/SMKCore/
/// KeymapBinary.swift`'s `decodeMacroStep` reads back (that file,
/// lines 250-332). Opcode values, field order, and endianness all match
/// that decoder and the format spec's step table.
///
/// `.raw` -- a step this build doesn't recognize, kept only so saving a
/// file never drops it -- is never sent to the firmware: it emits no bytes
/// at all, matching `MacroStep.compiledSize`'s `.raw` case (which returns 0
/// for the same reason, see that doc comment in Model/Macro.swift). Callers
/// must exclude `.raw` steps when computing a stepCount/body byte range,
/// not just when writing bytes -- see `compiledMacroSteps(_:)`.
private func encodeMacroStep(_ step: MacroStep, describedAs macroDescription: String) throws -> [UInt8] {
    switch step {
    case .keystroke(let mods, let key, let holdMs):
        let (lo, hi) = try twoByteLEPayloadField(holdMs, describedAs: "\(macroDescription) keystroke holdMs")
        return [0x01, modifierBits(mods), key?.hidUsage ?? 0, lo, hi]

    case .delay(let ms):
        let (lo, hi) = try twoByteLEPayloadField(ms, describedAs: "\(macroDescription) delay ms")
        return [0x02, lo, hi]

    case .layer(let op, let n):
        let index = try oneBytePayloadField(n, describedAs: "\(macroDescription) layer index")
        return [0x03, op == .momentary ? 0x00 : 0x01, index]

    case .text(let s, _, let msPerChar):
        if let (character, index) = firstUnsupportedCharacter(in: s) {
            throw KeymapCompileError.unsupportedCharacter(
                token: macroDescription, character: character, index: index)
        }
        let payload = Array(s.utf8)
        let length = try oneBytePayloadField(payload.count, describedAs: "\(macroDescription) text length")
        let msPerCharByte = try oneBytePayloadField(msPerChar, describedAs: "\(macroDescription) text msPerChar")
        // Paste cannot work board-side -- a keyboard has no way to put text
        // on the host's clipboard, only send keystrokes -- so a text step
        // always compiles as keystrokes (0x00) regardless of its stored
        // `delivery`. The byte itself stays reserved rather than removed:
        // the firmware's decoder (`~/esp/SMK/Sources/SMKCore/
        // KeymapBinary.swift`) expects this exact stride, and changing it
        // would churn a wire-format contract four implementations share
        // for no gain. `TextDelivery.paste` still round-trips through the
        // JSON model (see Model/Macro.swift) so an existing keymap.json
        // that carries `"delivery": "paste"` still loads losslessly --
        // it just never reaches the board as anything but keystrokes.
        let deliveryByte: UInt8 = 0x00
        return [0x04, deliveryByte, msPerCharByte, length] + payload

    case .repeatBlock(let count, let steps):
        let repeatCount = try oneBytePayloadField(count, describedAs: "\(macroDescription) repeat count")
        // Nested repeat blocks can't occur -- the model refuses them at
        // decode -- so `steps` here never itself contains a `.repeatBlock`.
        var body: [UInt8] = []
        for inner in compiledMacroSteps(steps) {
            let innerBytes = try encodeMacroStep(inner, describedAs: macroDescription)
            assert(innerBytes.count == inner.compiledSize,
                   "encoded \(innerBytes.count) bytes for a repeat-body step whose compiledSize is \(inner.compiledSize)")
            body.append(contentsOf: innerBytes)
        }
        let (lenLo, lenHi) = try twoByteLEPayloadField(body.count, describedAs: "\(macroDescription) repeat bodyLength")
        return [0x05, repeatCount, lenLo, lenHi] + body

    case .raw:
        return []
    }
}

/// `steps` with `.raw` entries removed -- the ones that actually reach the
/// wire, and therefore the ones a `stepCount`/body byte range must count.
private func compiledMacroSteps(_ steps: [MacroStep]) -> [MacroStep] {
    steps.filter { if case .raw = $0 { return false } else { return true } }
}

/// Encodes one macro to `id(1) + nameLength(1) + name + stepCount(1) +
/// steps` -- the layout `~/esp/SMK/Sources/SMKCore/KeymapBinary.swift`'s
/// `decodeMacroEntry` reads back (that file, lines 220-242).
private func encodeMacro(_ macro: MacroDefinition) throws -> [UInt8] {
    let description = "macro:\(macro.id) (\"\(macro.name)\")"

    var bytes: [UInt8] = []
    bytes.append(try oneBytePayloadField(macro.id, describedAs: "\(description) id"))

    let nameBytes = Array(macro.name.utf8)
    bytes.append(try oneBytePayloadField(nameBytes.count, describedAs: "\(description) name length"))
    bytes.append(contentsOf: nameBytes)

    let steps = compiledMacroSteps(macro.steps)
    bytes.append(try oneBytePayloadField(steps.count, describedAs: "\(description) step count"))
    for step in steps {
        let stepBytes = try encodeMacroStep(step, describedAs: description)
        assert(stepBytes.count == step.compiledSize,
               "encoded \(stepBytes.count) bytes for a step whose compiledSize is \(step.compiledSize)")
        bytes.append(contentsOf: stepBytes)
    }
    return bytes
}

/// Compiles a whole `KeymapDocument` -- matrix, every layer's cells, and
/// every macro -- to the binary payload
/// `~/esp/SMK/Sources/SMKCore/KeymapBinary.swift`'s `decodeKeymapPayload`
/// reads back (that file, lines 167-213). Byte order: the 6-byte header
/// (`rowCount`, `colCount`, `colsAreDriven`, `layerCount`, `macroCount`,
/// reserved), `rows[]`, `cols[]`, every cell of every layer at two bytes
/// each, then each macro.
///
/// Any cell parsing to `ActionToken.raw` -- a token this build has no
/// binary tag for -- fails the whole compile rather than silently dropping
/// or truncating it; see `KeymapCompileError`'s doc comment for why. The
/// on-disk `keymap.json` is unaffected: it keeps the raw string, so nothing
/// is lost by refusing to flash it.
func compileKeymap(_ document: KeymapDocument) throws -> [UInt8] {
    let rowCount = document.matrix.rows.count
    let colCount = document.matrix.cols.count
    let layerCount = document.layers.count
    // A disabled macro is omitted from the payload entirely, and every cell
    // bound to it compiles as a dead key below -- see the plan/spec for why
    // `none` rather than a dangling `macro:` reference the frozen firmware
    // decoder would have to tolerate.
    let macros = document.macroList.filter(\.enabled)
    let disabledMacroIDs = Set(document.macroList.filter { !$0.enabled }.map(\.id))

    var bytes: [UInt8] = []
    bytes.reserveCapacity(6 + rowCount + colCount + layerCount * rowCount * colCount * 2)

    bytes.append(try oneBytePayloadField(rowCount, describedAs: "matrix row count"))
    bytes.append(try oneBytePayloadField(colCount, describedAs: "matrix col count"))
    bytes.append(try oneBytePayloadField(document.matrix.colsAreDriven, describedAs: "matrix colsAreDriven"))
    bytes.append(try oneBytePayloadField(layerCount, describedAs: "layer count"))
    bytes.append(try oneBytePayloadField(macros.count, describedAs: "macro count"))
    bytes.append(0) // reserved

    for gpio in document.matrix.rows {
        bytes.append(try oneBytePayloadField(gpio, describedAs: "matrix row GPIO"))
    }
    for gpio in document.matrix.cols {
        bytes.append(try oneBytePayloadField(gpio, describedAs: "matrix col GPIO"))
    }

    for (layerIndex, layer) in document.layers.enumerated() {
        for (rowIndex, row) in layer.enumerated() {
            for (colIndex, cellString) in row.enumerated() {
                let token = ActionToken.parse(cellString)
                // The cell keeps its `macro:N` string in `keymap.json`;
                // only what reaches the board changes, so re-enabling the
                // macro brings the key back with no re-binding.
                var effective = token
                if case .macro(let slot) = token, disabledMacroIDs.contains(slot) {
                    effective = .none
                }
                do {
                    let (tag, param) = try encodeCell(effective)
                    bytes.append(tag)
                    bytes.append(param)
                } catch let underlying as KeymapCompileError {
                    // Names the token the user actually wrote, not the
                    // substitution.
                    throw KeymapCompileError.invalidCell(
                        layer: layerIndex, row: rowIndex, col: colIndex,
                        token: token.canonicalString, reason: underlying.description)
                }
            }
        }
    }

    for macro in macros {
        let macroBytes = try encodeMacro(macro)
        assert(macroBytes.count == macro.compiledSize,
               "encoded \(macroBytes.count) bytes for macro:\(macro.id) whose compiledSize is \(macro.compiledSize)")
        bytes.append(contentsOf: macroBytes)
    }

    return bytes
}
