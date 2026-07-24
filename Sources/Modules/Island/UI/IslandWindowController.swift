import AppKit
import SwiftUI

/// RISK-GATE PROTOTYPE (Task 2): an invisible, borderless, non-activating
/// window over the notch that registers as a dragging destination and logs
/// what it receives. Proves (or disproves) that drag-detection works over a
/// fully transparent window before the real shell is built on top of it.
@MainActor public final class IslandWindowController {
    private let panel: NSPanel
    private let dragView: IslandDragProbeView

    public init?() {
        // Notch geometry straight from the screen; nil on no-notch displays.
        guard let screen = NSScreen.main,
              let aux = screen.auxiliaryTopLeftArea, aux.width > 0,
              screen.safeAreaInsets.top > 0 else { return nil }
        let notchWidth = screen.frame.width - 2 * aux.width
        let rect = NSRect(x: screen.frame.midX - notchWidth / 2 - 60,
                          y: screen.frame.maxY - screen.safeAreaInsets.top,
                          width: notchWidth + 120,
                          height: screen.safeAreaInsets.top)

        let panel = NSPanel(contentRect: rect,
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.panel = panel

        let view = IslandDragProbeView(frame: NSRect(origin: .zero, size: rect.size))
        self.dragView = view
        panel.contentView = view
        panel.setFrame(rect, display: true)
        panel.orderFrontRegardless()
        IslandDragProbeView.log("prototype window up at \(rect)")
    }
}

final class IslandDragProbeView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { nil }

    static func log(_ m: String) {
        let line = String(format: "%.2f ", Date().timeIntervalSince1970) + m + "\n"
        if let d = line.data(using: .utf8), let h = FileHandle(forWritingAtPath: "/tmp/helm-island.log") {
            h.seekToEndOfFile(); h.write(d); h.closeFile()
        } else {
            try? line.write(toFile: "/tmp/helm-island.log", atomically: false, encoding: .utf8)
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.log("draggingEntered")
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        Self.log("draggingExited")
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        Self.log("performDrag urls=\(urls.map(\.lastPathComponent))")
        return true
    }
}
