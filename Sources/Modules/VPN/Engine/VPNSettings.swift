import HelmRuntime

public struct VPNSettings {
    let store: NamespacedStore
    public init(store: NamespacedStore) { self.store = store }

    public var rulesJSON: String { store.string("vpnAppRules", default: "{}") }
    public func setRulesJSON(_ json: String) { store.set(json, for: "vpnAppRules") }

    /// How loudly a *rule* firing is announced — an app launched, an app quit,
    /// and Helm did what it was told.
    public var notice: VPNNotice {
        VPNNotice(rawValue: store.string("automationNotice", default: "")) ?? .menuBar
    }
    public func setNotice(_ notice: VPNNotice) {
        store.set(notice.rawValue, for: "automationNotice")
    }

    /// How loudly a tunnel **falling over by itself** is announced.
    ///
    /// A separate setting because it is separate news. Everything else this
    /// module announces is something the person arranged; this is the arrangement
    /// failing, and the moment it fails they are sending in clear while the last
    /// thing they were told was that they were not. Somebody who wants their
    /// rules silent can still want to hear about that.
    ///
    /// Its own account rather than a derivation of `notice`: a stored setting
    /// that steers what the app says is the person's, and one computed from
    /// another cannot be set to less than it.
    ///
    /// Defaulted to the same `.menuBar` the rules get. `.system` would be the
    /// louder default and it would be a lie: macOS grants the banner permission
    /// only when somebody asks for it, this module asks only when a person picks
    /// that mode, and a page showing "Notification" selected for a mode that has
    /// never been allowed says something the app will not do.
    public var dropNotice: VPNNotice {
        VPNNotice(rawValue: store.string("dropNotice", default: "")) ?? .menuBar
    }
    public func setDropNotice(_ notice: VPNNotice) {
        store.set(notice.rawValue, for: "dropNotice")
    }

    /// The one both sides read, so no caller decides for itself which of the
    /// two settings a firing answers to. The rule itself is `VPNNotice.mode`,
    /// which is pure and says there why a teardown is not the rules' volume.
    public func notice(for kind: VPNAutomation.Kind) -> VPNNotice {
        VPNNotice.mode(for: kind, rules: notice, drop: dropNotice)
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
        store.string(Self.spinTintKey(kind), default: kind.goingUp ? "green" : "orange")
    }
    public func setSpinTint(_ token: String, for kind: VPNAutomation.Kind) {
        store.set(token, for: Self.spinTintKey(kind))
    }
    /// **Two keys for three kinds.** `.dropped` is a third kind of news and not
    /// a third colour: the ring says which way the tunnel went, and there are
    /// two ways. Deriving the key from `rawValue` would have opened a
    /// `spinTint.dropped` nobody sets, so a tunnel that fell over would have
    /// turned the ring in the default orange while the person's own colour for
    /// a tunnel going down sat in the store unread.
    private static func spinTintKey(_ kind: VPNAutomation.Kind) -> String {
        "spinTint.\(kind.goingUp ? "connected" : "disconnected")"
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
