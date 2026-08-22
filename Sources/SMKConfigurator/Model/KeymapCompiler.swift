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

    var description: String {
        switch self {
        case .unsupportedToken(let token):
            return "Cannot compile \"\(token)\": the firmware has no binary tag for this token."
        case .parameterOutOfRange(let token, let value, let limit):
            return "Cannot compile \"\(token)\": parameter \(value) exceeds the maximum of \(limit) the one-byte wire field allows."
        }
    }
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
