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

    /// Whether the menu-bar ring turns when a rule fires.
    ///
    /// Off by default, which reverses what the automation-feedback spec
    /// decided: it argued the movement is feedback rather than a notification
    /// and should always play. Sound, and overruled — movement in the menu bar
    /// is a person's to switch off. The cost is exact and is stated under the
    /// switch: with this off *and* the notice set to nothing, a rule fires with
    /// no sign at all.
    public var automationSpin: Bool { store.bool("automationSpin", default: false) }
    public func setAutomationSpin(_ on: Bool) { store.set(on, for: "automationSpin") }

    /// The colour the ring turns in, per kind of firing. A tunnel going up and
    /// a tunnel going down are the two things worth telling apart at a glance,
    /// and `VPNAutomation.Kind` already distinguishes them.
    public func spinTint(for kind: VPNAutomation.Kind) -> String {
        store.string(Self.spinTintKey(kind), default: kind == .connected ? "green" : "orange")
    }
    public func setSpinTint(_ token: String, for kind: VPNAutomation.Kind) {
        store.set(token, for: Self.spinTintKey(kind))
    }
    private static func spinTintKey(_ kind: VPNAutomation.Kind) -> String {
        "spinTint.\(kind.rawValue)"
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
