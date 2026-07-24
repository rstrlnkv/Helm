import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let host = ModuleHost.shared
    var statusController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        host.bootstrap()
        statusController = StatusItemController(host: host)
    }
}
