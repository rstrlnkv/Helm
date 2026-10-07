import AppKit
@testable import HelmApp

/// **Where a window's pane and sidebar are, whichever way the window is built:
/// the settings window's own shell, or the split view a test rig still mounts.**
///
/// The settings window's content is `SettingsShellViewController`: its pane is
/// the one view inside the card's clip, its sidebar the first child's view. A rig
/// that mounts an `NSSplitViewController` answers by its items. A window of
/// neither kind answers nil and 0, so a caller that needs the pane unwraps it and
/// fails naming the window rather than measuring nothing.
@MainActor
enum SettingsWindowParts {

    static func pane(of window: NSWindow) -> NSView? {
        if let shell = window.contentViewController as? SettingsShellViewController {
            return shell.shell.clip.subviews.first
        }
        return (window.contentViewController as? NSSplitViewController)?
            .splitViewItems.last?.viewController.view
    }

    static func sidebarWidth(of window: NSWindow) -> CGFloat {
        if let shell = window.contentViewController as? SettingsShellViewController {
            return shell.children.first?.view.frame.width ?? 0
        }
        return (window.contentViewController as? NSSplitViewController)?
            .splitViewItems.first?.viewController.view.frame.width ?? 0
    }
}
