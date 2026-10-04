import AppKit
import Module_Screenshots_Engine

/// The two drop-down menus of the capture panel, as `NSMenu`s popped up under their cells (`popUp`): the timer's
/// lengths, and the gear's «Save to», options and «Put the Panel Back». Built **at each press** from what the model says
/// now: a check mark read from a menu made earlier would be the answer the page has since replaced.
@MainActor enum PanelMenus {
    /// 5, 10, 30 seconds and none, the current one checked.
    static func timer(_ current: CaptureTimer, choose: @escaping (CaptureTimer) -> Void) -> NSMenu {
        let menu = menu()
        for length in [CaptureTimer.five, .ten, .thirty, .none] {
            if length == .none { menu.addItem(.separator()) }
            menu.addItem(item(ScStr.timer(length), isOn: length == current) { choose(length) })
        }
        return menu
    }

    /// Where it is saved, the options, and the way back for the panel's place. The timer is not here: it has its own cell.
    static func options(_ model: CapturePanelModel) -> NSMenu {
        let settings = model.settings
        let menu = menu()
        menu.addItem(.sectionHeader(title: ScStr.saveTo))
        for target in SaveTarget.allCases {
            menu.addItem(item(ScStr.target(target), isOn: target == settings.saveTarget) { model.choose(target) })
        }
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: ScStr.options))
        menu.addItem(item(ScStr.floatingThumbnail, isOn: settings.thumbnail) { model.setThumbnail(!settings.thumbnail) })
        menu.addItem(item(ScStr.rememberSelection, isOn: settings.rememberSelection) { model.setRemember(!settings.rememberSelection) })
        menu.addItem(item(ScStr.showCursor, isOn: settings.showCursor) { model.setCursor(!settings.showCursor) })
        menu.addItem(.separator())
        menu.addItem(item(ScStr.putPanelBack, isOn: false) { model.putBack() })
        return menu
    }

    private static func menu() -> NSMenu {
        // A menu sends an item's action through the application object, which a process that has not made it yet lacks.
        _ = NSApplication.shared
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false
        return menu
    }

    private static func item(_ title: String, isOn: Bool, run: @escaping () -> Void) -> NSMenuItem {
        let action = Action(run)
        let item = NSMenuItem(title: title, action: #selector(Action.fire), keyEquivalent: "")
        item.state = isOn ? .on : .off
        // A menu item holds its target weakly: the item holds the object that runs it as its represented object.
        item.target = action
        item.representedObject = action
        return item
    }

    @MainActor private final class Action: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }
}
