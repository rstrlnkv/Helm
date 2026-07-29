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

    /// What macOS last said about banners — a mirror, not the truth.
    ///
    /// It is here rather than in memory because macOS is asked once and the
    /// answer outlives the launch that got it: a flag that reset every morning
    /// would demote `.system` to the menu-bar label for someone who granted the
    /// permission months ago. The cost of mirroring is that the person can
    /// revoke banners in System Settings and this will not hear about it, so it
    /// has to be refreshed from `AutomationNotice.prepare` — a read, never a
    /// request — when the module comes up.
    public var bannerAuthorized: Bool { store.bool("bannerAuthorized", default: false) }
    public func setBannerAuthorized(_ authorized: Bool) {
        store.set(authorized, for: "bannerAuthorized")
    }

    public var lastUsedName: String? {
        let s = store.string("lastUsedName", default: "")
        return s.isEmpty ? nil : s
    }
    public func setLastUsed(_ name: String) { store.set(name, for: "lastUsedName") }
}
