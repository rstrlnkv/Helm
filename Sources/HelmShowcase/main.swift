import AppKit
import HelmUI
import SwiftUI

/// A window of the kit's components, each in every state that can be drawn. Arguments only: it reads no
/// defaults and writes none, and its window is not restored.
let options: ShowcaseOptions
do {
    options = try ShowcaseOptions(arguments: CommandLine.arguments)
} catch let refusal as ShowcaseOptions.Refusal {
    FileHandle.standardError.write(Data("HelmShowcase: \(refusal.message)\n\(ShowcaseOptions.usage)\n".utf8))
    exit(64)
}

let application = NSApplication.shared
application.appearance = options.appearance.flatMap { NSAppearance(named: $0.name) }

// Set on the board, nearer the reader than the tracker `helmRoot()` adds above it, so the kit's own value
// says what the appearance asked for in both directions, whatever the machine's switch is.
var accessibility = HelmAccessibility.system
if let appearance = options.appearance { accessibility.increasedContrast = appearance.increasedContrast }

// The kit's own words read in this language, whatever the Mac's: a setter over a lock and a field, no defaults.
if let language = options.language { AppLanguage.override = language }

let host = HostWindow(onClose: { NSApp.terminate(nil) })
host.present(ShowcaseBoards.view(for: options).environment(\.helmAccessibility, accessibility),
             title: "HelmShowcase", styleMask: [.titled, .closable, .miniaturizable])
for window in application.windows { window.isRestorable = false }
// SwiftUI sizes the window after `present` centred it at no size, so centre it again whenever it is sized
// (a drag moves it without sizing it): a board wider than half the screen would run past the right edge.
for window in application.windows {
    NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { _ in
        MainActor.assumeIsolated { window.center() }
    }
}
application.run()
