import MetalUI

// DEV mode -- placeholders until lane 2 of the port (plan §1.8). Final names
// and initialisers. (The device monitor's start/stop moves onto the main
// pane's `onAppear`/`onDisappear` there.)

/// DEV rail mode's list column: the transport cards.
struct DeviceListColumnView: Component {
    let editor: EditorState

    var content: some ElementGroup {
        PanePlaceholder(label: "Transports — not yet ported", width: 260, background: Chrome.column)
    }
}

/// DEV rail mode's main content: status, Send to Device, progress.
struct DeviceMainContentView: Component {
    let editor: EditorState

    var content: some ElementGroup {
        PanePlaceholder(label: "Device — not yet ported", width: nil, background: Chrome.canvas)
    }
}

/// DEV rail mode's inspector: device info.
struct DeviceInspectorView: Component {
    let editor: EditorState

    var content: some ElementGroup {
        PanePlaceholder(label: "Device info — not yet ported", width: 300, background: Chrome.column)
    }
}
