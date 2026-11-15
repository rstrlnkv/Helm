// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmRuntime

/// `-HelmOpenPage <id>` opens Settings on that page for `Scripts/shoot.sh`
/// (ARCHITECTURE.md § Two screen instruments).
///
/// Read from the argument domain only: `string(forKey:)` falls through to the
/// persistent domain, so a `defaults write` of the same key would open a page at
/// every launch. A page that cannot be opened is logged and refused, never
/// replaced by General: a shot of the wrong page would look like the right one.
@MainActor enum LaunchPage {
    static let argument = "-HelmOpenPage"
    static let key = "HelmOpenPage"

    enum Verdict {
        case none
        case open(SettingsSelection, id: String)
        case unknown(String)
        case off(String)
        case noID
    }

    /// Tab ids first, then module ids from the registry; a module that is switched off has no page.
    static func verdict(argumentDomain: [String: Any], argv: [String], enabled: Set<String>) -> Verdict {
        guard let id = argumentDomain[key] as? String else {
            return argv.contains(argument) ? .noID : .none
        }
        if let tab = SettingsTabs.selection(id) { return .open(tab, id: id) }
        guard let module = ModuleRegistry.descriptor(id) else { return .unknown(id) }
        return enabled.contains(module.idRaw) ? .open(.module(id), id: id) : .off(id)
    }

    static func openRequested(by status: StatusItemController, enabled: Set<String>) {
        let domain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        switch verdict(argumentDomain: domain, argv: ProcessInfo.processInfo.arguments, enabled: enabled) {
        case .none:
            break
        case .open(let page, let id):
            HelmLog.shared.info("app", "launch page: \(id)")
            status.showSettings(page: page)
        case .unknown(let id):
            HelmLog.shared.warn("app", "launch page refused: \"\(id.prefix(64))\" names no page")
        case .off(let id):
            HelmLog.shared.warn("app", "launch page refused: \(id) is switched off")
        case .noID:
            HelmLog.shared.warn("app", "launch page refused: \(argument) has no id")
        }
    }
}
