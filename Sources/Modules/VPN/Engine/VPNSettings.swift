import HelmRuntime

public struct VPNSettings {
    let store: NamespacedStore
    public init(store: NamespacedStore) { self.store = store }

    public var rulesJSON: String { store.string("vpnAppRules", default: "{}") }
    public func setRulesJSON(_ json: String) { store.set(json, for: "vpnAppRules") }

    public var notice: VPNNotice {
        VPNNotice(rawValue: store.string("automationNotice", default: "")) ?? .menuBar
    }
    public func setNotice(_ notice: VPNNotice) {
        store.set(notice.rawValue, for: "automationNotice")
    }

    public var lastUsedName: String? {
        let s = store.string("lastUsedName", default: "")
        return s.isEmpty ? nil : s
    }
    public func setLastUsed(_ name: String) { store.set(name, for: "lastUsedName") }
}
