import Foundation
import Testing
@testable import SMKConfigurator

// The view-level logic lane 2 of the port pulled out of the KEY, DSN and DEV
// panes into plain functions (`PaletteDrop`, `DesignGridEditing`,
// `DeviceStatusText`, `DeviceTransportStatus`, the key and cell sizes), so it
// is testable without a window. These types live in `Views/`, so this file is
// macOS-only (Package.swift's Linux/Windows exclude list).

@MainActor
@Suite("Dragging a palette chip onto a key")
struct PaletteDropTests {
    /// Every chip the drawer can show: every key section, the specials, MO/TG
    /// for a few layers and a macro.
    private static var everyChipToken: [ActionToken] {
        PaletteLayout.keySections.flatMap(\.tokens)
            + [.transparent, .none, .toggleConnection, .momentaryLayer(1), .toggleLayer(3), .macro(2)]
    }

    @Test("every chip's drag payload reads back as the same action")
    func everyChipRoundTrips() {
        let tokens = Self.everyChipToken
        #expect(tokens.count > 100)
        for token in tokens {
            #expect(PaletteDrop.token(from: [PaletteDrop.payload(for: token)]) == token, "\(token)")
        }
    }

    @Test("text dragged in from another app is refused, not assigned as a raw cell")
    func foreignTextIsRefused() {
        #expect(PaletteDrop.token(from: ["hello world"]) == nil)
        #expect(PaletteDrop.token(from: []) == nil)
        #expect(PaletteDrop.token(from: ["junk", "key:a"]) == .key(.a))
    }

    @Test("a drop assigns the action on the current layer and marks the document unsaved")
    func aDropChangesTheKeyAndDirtiesTheDocument() throws {
        let editor = EditorState(userDefaults: UserDefaults(suiteName: "PaletteDropTests-\(UUID())")!)
        editor.newDocument()
        #expect(!editor.isDirty)
        let payload = PaletteDrop.payload(for: .modifier(.leftShift))
        // What `KeyCapView`'s drop destination does with the dropped strings.
        let token = try #require(PaletteDrop.token(from: [payload]))
        editor.assign(token, row: 1, col: 2)
        editor.selectKey(row: 1, col: 2)
        #expect(editor.action(row: 1, col: 2) == .modifier(.leftShift))
        #expect(editor.isDirty)
        #expect(editor.selectedKeyPosition == KeyPosition(row: 1, col: 2))
    }
}

@MainActor
@Suite("Key, board and cell sizes")
struct PaneSizeTests {
    @Test("a multi-unit key spans its columns and the gaps between them")
    func keyWidths() {
        #expect(KeyCapView.width(units: 1) == 46)
        #expect(KeyCapView.width(units: 2) == 102)
        #expect(KeyCapView.width(units: 1.5) == 74)
    }

    @Test("the bundled 5-row board's card is 286 tall")
    func boardHeight() {
        #expect(KeyboardBoardView.naturalHeight(of: .gateronLPKBD) == 5 * 46 + 4 * 6 + 32)
    }

    @Test("DSN cells: width text and width")
    func designCells() {
        #expect(DesignCellView.label(forWidth: 1) == "1")
        #expect(DesignCellView.label(forWidth: 2) == "2")
        #expect(DesignCellView.label(forWidth: 1.25) == "1.25")
        #expect(DesignCellView.label(forWidth: 2.75) == "2.75")
        #expect(DesignCellView.width(of: KeyboardDesign.Cell(width: 2, isGap: false)) == 108)
        #expect(DesignCellView.width(of: KeyboardDesign.Cell(width: 2, isGap: true)) == 52)
        #expect(DesignGridEditorView.widthPresets.map(DesignCellView.label(forWidth:))
            == ["1", "1.25", "1.50", "1.75", "2", "2.25", "2.75"])
    }
}

@MainActor
@Suite("The DSN grid editor's edits")
struct DesignGridEditingTests {
    @Test("adding a row and a column wires the next unused GPIO and keeps the grid rectangular")
    func addRowAndColumn() {
        var design = KeyboardDesign.gateronLPKBD
        let rows = design.rowCount, cols = design.colCount
        DesignGridEditing.addRow(to: &design)
        DesignGridEditing.addColumn(to: &design)
        #expect(design.rowCount == rows + 1)
        #expect(design.colCount == cols + 1)
        #expect(design.matrix.rows.last == KeyboardDesign.gateronLPKBD.matrix.rows.max()! + 1)
        #expect(design.matrix.cols.last == KeyboardDesign.gateronLPKBD.matrix.cols.max()! + 1)
        #expect(design.grid.count == design.rowCount)
        #expect(design.grid.allSatisfy { $0.count == design.colCount })
    }

    @Test("removing a row or column clears a selection that falls off the grid, and keeps one in range")
    func removeClearsAnOutOfRangeSelection() {
        var design = KeyboardDesign.gateronLPKBD
        var selection: DesignGridPosition? = DesignGridPosition(row: design.rowCount - 1, col: 0)
        DesignGridEditing.removeRow(from: &design, selection: &selection)
        #expect(selection == nil)

        selection = DesignGridPosition(row: 0, col: 0)
        DesignGridEditing.removeColumn(from: &design, selection: &selection)
        #expect(selection == DesignGridPosition(row: 0, col: 0))

        selection = DesignGridPosition(row: 0, col: design.colCount - 1)
        DesignGridEditing.removeColumn(from: &design, selection: &selection)
        #expect(selection == nil)
        #expect(design.grid.allSatisfy { $0.count == design.colCount })
    }

    @Test("the last row and the last column are never removed")
    func neverBelowOne() {
        var design = KeyboardDesign.blank()
        var selection: DesignGridPosition? = nil
        for _ in 0..<20 {
            DesignGridEditing.removeRow(from: &design, selection: &selection)
            DesignGridEditing.removeColumn(from: &design, selection: &selection)
        }
        #expect(design.rowCount == 1)
        #expect(design.colCount == 1)
    }

    @Test("a width preset makes a gap a key again; the Gap toggle writes the cell")
    func widthAndGap() {
        var design = KeyboardDesign.gateronLPKBD
        let gap = DesignGridPosition(row: 4, col: 6)
        #expect(DesignGridEditing.isGap(at: gap, in: design))
        DesignGridEditing.setWidth(1.5, at: gap, in: &design)
        #expect(!DesignGridEditing.isGap(at: gap, in: design))
        #expect(design.grid[4][6].width == 1.5)
        DesignGridEditing.setGap(true, at: gap, in: &design)
        #expect(design.grid[4][6].isGap)
        // A stale selection (the draft shrank under it) changes nothing.
        let before = design
        DesignGridEditing.setWidth(2, at: DesignGridPosition(row: 40, col: 0), in: &design)
        DesignGridEditing.setGap(true, at: DesignGridPosition(row: 0, col: 40), in: &design)
        #expect(design == before)
        #expect(!DesignGridEditing.isGap(at: DesignGridPosition(row: 40, col: 40), in: design))
    }
}

@MainActor
@Suite("The DEV pane's status text")
struct DeviceStatusTextTests {
    @Test("upload phases")
    func progress() {
        #expect(DeviceStatusText.progress(.begin) == "Starting upload…")
        #expect(DeviceStatusText.progress(.chunk(index: 0, of: 3)) == "Sending chunk 1 of 3…")
        #expect(DeviceStatusText.progress(.commit) == "Committing…")
    }

    @Test("last sent")
    func relativeTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func ago(_ seconds: Double) -> String {
            DeviceStatusText.relativeTime(from: now.addingTimeInterval(-seconds), now: now)
        }
        #expect(ago(0) == "just now")
        #expect(ago(4) == "just now")
        #expect(ago(5) == "5s ago")
        #expect(ago(59) == "59s ago")
        #expect(ago(60) == "1m ago")
        #expect(ago(3599) == "59m ago")
        #expect(ago(7200) == "2h ago")
    }

    @Test("each transport status names its headline and MCU")
    func transportStatus() {
        #expect(DeviceTransportStatus.usb.headline == "Connected via USB")
        #expect(DeviceTransportStatus.usb.mcu == "RP2040")
        #expect(DeviceTransportStatus.bleReady.mcu == "ESP32-C6")
        #expect(DeviceTransportStatus.bleServiceMissing.headline == "Linked — upload service missing")
        #expect(DeviceTransportStatus.bleBusy("Searching…").headline == "Searching…")
        #expect(DeviceTransportStatus.disconnected.headline == "Not connected")
        #expect(DeviceTransportStatus.disconnected.mcu == "—")
    }

    @Test("USB wins over BLE, and nothing connected reads disconnected")
    func currentStatus() {
        let editor = EditorState(userDefaults: UserDefaults(suiteName: "DeviceStatusTextTests-\(UUID())")!)
        editor.usbConnected = false
        #expect(DeviceTransportStatus.current(editor) == .disconnected)
        editor.usbConnected = true
        #expect(DeviceTransportStatus.current(editor) == .usb)
    }
}
