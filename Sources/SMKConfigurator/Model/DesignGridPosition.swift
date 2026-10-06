import Foundation

/// A cell coordinate in the DSN grid editor, distinct from `KeyPosition`
/// (which identifies a key on the *active* design for the Key inspector) --
/// this identifies a cell within whatever design is currently being
/// drafted, which may not be saved/active yet.
struct DesignGridPosition: Equatable {
    var row: Int
    var col: Int
}
