import Foundation

/// The 11 platform-native icons: five drawn by the icon rail, six (the old
/// titlebar's file actions, now File-menu items) bundled but undrawn. Each
/// case name is also the exact PNG filename (without extension) under
/// `Resources/<Platform>/Icons/<light|dark>/` -- see
/// `Scripts/generate-icons.sh`.
enum AppIcon: String, CaseIterable {
    case key, designs, themes, device, macros
    case newDoc, open, save, saveAs, importFile, exportFile

    /// Short text shown instead of the icon if `IconLoader`
    /// (`Views/IconLoader.swift`) can't resolve a bundled PNG for this platform (e.g. a filename mismatch
    /// between `AppIcon`'s cases and `Scripts/generate-icons.sh`'s output)
    /// -- keeps the button legible instead of rendering blank. Matches the
    /// abbreviations these buttons showed before icons replaced text
    /// labels.
    var fallbackLabel: String {
        switch self {
        case .key: return "KEY"
        case .designs: return "DSN"
        case .themes: return "THM"
        case .device: return "DEV"
        case .macros: return "MAC"
        case .newDoc: return "N"
        case .open: return "O"
        case .save: return "S"
        case .saveAs: return "S+"
        case .importFile: return "I"
        case .exportFile: return "E"
        }
    }
}

