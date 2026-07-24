import AppKit
import IOKit.ps

/// Detects that a file drag session started/ended anywhere on the system, so
/// the island can reveal a drop zone below the menu bar (primary drag-in path;
/// dwelling at the top edge would trigger Mission Control on macOS 26).
@MainActor final class IslandDragMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastChangeCount: Int
    private var dragActive = false

    init(onDragStarted: @escaping () -> Void, onDragEnded: @escaping () -> Void) {
        lastChangeCount = NSPasteboard(name: .drag).changeCount

        let handle: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            switch event.type {
            case .leftMouseDragged:
                let pb = NSPasteboard(name: .drag)
                if pb.changeCount != self.lastChangeCount {
                    self.lastChangeCount = pb.changeCount
                    let hasFiles = pb.types?.contains(where: { $0.rawValue.contains("file-url") || $0 == .fileURL }) ?? false
                    if hasFiles, !self.dragActive {
                        self.dragActive = true
                        onDragStarted()
                    }
                }
            case .leftMouseUp:
                if self.dragActive {
                    self.dragActive = false
                    onDragEnded()
                }
            default: break
            }
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { event in
            MainActor.assumeIsolated { handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { event in
            MainActor.assumeIsolated { handle(event) }
            return event
        }
    }

    /// Explicit teardown from the owner (deinit can't touch main-actor state
    /// under Swift 6); the descriptor calls this before dropping the monitor.
    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}

/// Publishes power-state changes (charger plugged/unplugged) as island events.
final class IslandPowerSource: @unchecked Sendable {
    private var runLoopSource: CFRunLoopSource?
    private var lastOnBattery: Bool?
    private let onEvent: @MainActor (String, String) -> Void

    init(onEvent: @escaping @MainActor (String, String) -> Void) {
        self.onEvent = onEvent
        lastOnBattery = Self.snapshot()?.onBattery

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<IslandPowerSource>.fromOpaque(context).takeUnretainedValue().changed()
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
    }

    private func changed() {
        guard let snap = Self.snapshot() else { return }
        // Only announce transitions, not every capacity tick.
        guard snap.onBattery != lastOnBattery else { return }
        lastOnBattery = snap.onBattery
        let text = (snap.onBattery ? IsStr.onBattery : IsStr.charging) + " · \(snap.percent)%"
        let symbol = snap.onBattery ? "battery.75percent" : "bolt.fill"
        Task { @MainActor in self.onEvent(text, symbol) }
    }

    private static func snapshot() -> (onBattery: Bool, percent: Int)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any]
        else { return nil }
        let onBattery = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
        let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = desc[kIOPSMaxCapacityKey] as? Int ?? 0
        return (onBattery, max > 0 ? Int(Double(current) / Double(max) * 100) : 0)
    }
}
