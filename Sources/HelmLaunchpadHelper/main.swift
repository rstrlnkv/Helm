// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import os

/// The Dock icon of the Launchpad: a click opens `HelmLaunchpadURL` at the Helm this bundle sits in, and the
/// helper quits. No dependency on any other target, as `HelmReadout`: Helm's code is not its to import.
///
/// **It never activates.** It is an accessory app (`LSUIElement`), asks `NSWorkspace` not to activate the
/// parent, and holds nothing on screen, so the Launchpad panel's "another app came forward" ender never fires
/// for the click that closes it. The URL goes to one explicit application, the parent whose bundle id the
/// plist names, never to whatever LaunchServices thinks owns the scheme: Helm Dev's helper cannot wake the release.
/// Failures go to the unified log only; the person sees nothing, and there is nobody to ask.
private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.helm.app.launchpad", category: "helper")

private func finish(_ status: Int32) -> Never {
    exit(status)
}

/// The Helm this helper is nested in (`Helm.app/Contents/Helpers/<this>.app`), accepted only when it carries the
/// parent id the plist names; otherwise the one app LaunchServices knows by that id.
private func parentApp(id: String) -> URL? {
    let nested = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    if Bundle(url: nested)?.bundleIdentifier == id { return nested }
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
}

private final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let info = Bundle.main.infoDictionary
        guard let parentID = info?["HelmParentBundleID"] as? String,
              let link = (info?["HelmLaunchpadURL"] as? String).flatMap(URL.init(string:)) else {
            log.error("the plist names no parent or no link")
            finish(1)
        }
        guard let parent = parentApp(id: parentID) else {
            log.error("no app with id \(parentID, privacy: .public) to open the link at")
            finish(1)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open([link], withApplicationAt: parent, configuration: configuration) { _, error in
            if let error { log.error("the link was not delivered: \(error.localizedDescription, privacy: .public)") }
            finish(error == nil ? 0 : 1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            log.error("the link was not delivered within 10 s")
            finish(1)
        }
    }
}

private let delegate = Delegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
