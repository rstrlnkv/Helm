// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import Foundation
import HelmRuntime
import Security
import SystemConfiguration
import UserNotifications

// MARK: - Shell

/// Minimal `Process` wrapper for invoking system command-line tools. Local to
/// this file — the rest of the engine target stays free of any shell dependency
/// so the core logic (Ports.swift, VPNEngine, etc.) can be unit-tested with
/// fakes instead.
/// Kept as a name; the body is `HelmProcess`, which every module shares.
enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> HelmProcess.Result {
        HelmProcess.run(path, args)
    }
}

// MARK: - ScutilRunner

/// Production `VPNRunnerPort`: shells out to `/usr/sbin/scutil`.
public final class ScutilRunner: VPNRunnerPort {
    public init() {}
    public func run(_ args: [String]) -> String { Shell.run("/usr/sbin/scutil", args).output }
}

// MARK: - WorkspaceAppObserver

/// Production `AppObserverPort`: reads/observes `NSWorkspace.runningApplications`.
/// Uses KVO (rather than `NSWorkspace` launch/terminate notifications) because
/// KVO is more reliable for Catalyst apps, per the fork's implementation notes.
public final class WorkspaceAppObserver: AppObserverPort {
    private var observation: NSKeyValueObservation?

    public init() {}

    /// Through `RunningApps`, never straight to AppKit: the engine calls this
    /// from its own serial queue, and reading the live list from there
    /// segfaulted the app whenever a program quit at the wrong moment.
    public func runningBundleIDs() -> Set<String> { RunningApps.shared.bundleIDs() }

    public func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        // No .initial: the engine seeds already-running apps itself, so firing
        // on registration would just cause a redundant full app-list scan.
        observation = NSWorkspace.shared.observe(\.runningApplications) { _, _ in
            // KVO arrives on the thread that changed the list — the main one.
            // The snapshot is taken here, while it is safe to read, so that the
            // engine's queue has something correct to read a moment later.
            RunningApps.shared.refreshOnMain(then: onChange)
        }
    }
}

// MARK: - DynamicStoreNetworkWatch

/// Production `NetworkWatchPort`: a `SCDynamicStore` session on the keys that
/// move when a tunnel does.
///
/// The module used to ask `scutil` once per launch and answer from that for the
/// rest of the session, so a VPN started from the macOS menu bar, stopped in
/// System Settings, or dropped by the network left Helm's dot saying whatever
/// it had said at login.
public final class DynamicStoreNetworkWatch: NetworkWatchPort {

    /// The callback's context, and the reason this is a class rather than the
    /// closure itself.
    ///
    /// `SCDynamicStoreCreate` retains what the context holds and releases it
    /// when the session goes — measured, not assumed: one retain on create, one
    /// release on drop. So a notification already sitting on the queue when the
    /// module is switched off resolves to a live object rather than to freed
    /// memory, which is what ARCHITECTURE.md § "An observer outlives the thing
    /// it points at" is about. Clearing the action is what makes that late
    /// notification a no-op.
    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var action: (@Sendable () -> Void)?
        init(_ action: @escaping @Sendable () -> Void) { self.action = action }
        func fire() { lock.lock(); let action = action; lock.unlock(); action?() }
        func clear() { lock.lock(); action = nil; lock.unlock() }
    }

    private let lock = NSLock()
    private var store: SCDynamicStore?
    private var sink: Sink?
    /// Notifications land here, never on the main thread: the engine hops to
    /// its own serial queue to run `scutil` anyway.
    private let queue = DispatchQueue(label: "helm.vpn.network", qos: .utility)

    public init() {}
    deinit { stopObserving() }

    public func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        stopObserving()
        let sink = Sink(onChange)
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(sink).toOpaque(),
            retain: { UnsafeRawPointer(Unmanaged<Sink>.fromOpaque($0).retain().toOpaque()) },
            release: { Unmanaged<Sink>.fromOpaque($0).release() },
            copyDescription: nil)
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue().fire()
        }
        guard let store = SCDynamicStoreCreate(nil, "com.helm.vpn" as CFString,
                                               callback, &context) else {
            HelmLog.shared.warn("vpn", "no network-state session; the connection list "
                + "will only be re-read when Helm is asked")
            return
        }
        // Which key answers which half: the global entity moves when the
        // default route does (a full-tunnel VPN coming up or going away), the
        // per-service state entity when any service gains or loses an address
        // (a split tunnel, and a tunnel that simply dropped), and the Setup
        // pattern when the *configuration* changes — a VPN added or removed in
        // System Settings, which is what left the rule editor offering a list
        // missing the connection the rule was for.
        let keys = [SCDynamicStoreKeyCreateNetworkGlobalEntity(
            nil, kSCDynamicStoreDomainState, kSCEntNetIPv4)]
        let patterns = [
            SCDynamicStoreKeyCreateNetworkServiceEntity(
                nil, kSCDynamicStoreDomainState, kSCCompAnyRegex, kSCEntNetIPv4),
            SCDynamicStoreKeyCreateNetworkServiceEntity(
                nil, kSCDynamicStoreDomainSetup, kSCCompAnyRegex, kSCEntNetInterface),
        ]
        guard SCDynamicStoreSetNotificationKeys(store, keys as CFArray, patterns as CFArray),
              SCDynamicStoreSetDispatchQueue(store, queue) else {
            HelmLog.shared.warn("vpn", "could not subscribe to network-state changes")
            return
        }
        lock.lock()
        self.store = store
        self.sink = sink
        lock.unlock()
    }

    public func stopObserving() {
        lock.lock()
        let store = self.store
        let sink = self.sink
        self.store = nil
        self.sink = nil
        lock.unlock()
        // Cleared before unscheduling, not after: unscheduling stops the next
        // notification, and clearing is what stops the one already on the queue.
        sink?.clear()
        if let store { SCDynamicStoreSetDispatchQueue(store, nil) }
    }
}

// MARK: - KeychainCredentials

/// Production `VPNCredentialsPort`: reads the shared-secret/password an
/// L2TP/IPSec VPN needs so `scutil --nc start` connects silently instead of
/// prompting for the IPSec shared secret.
///
/// macOS gates every read of a VPN secret in the System keychain by a
/// third-party app behind a prompt (System Settings is exempt as an Apple
/// binary). So we read the System keychain at most ONCE, cache the values in
/// Helm's own login-keychain items (which we can read back without a prompt),
/// and use the cache thereafter. Returns nil for VPNs without a stored shared
/// secret (e.g. IKEv2). Secrets stay in memory / the keychain, never logged.
public final class KeychainCredentials: VPNCredentialsPort {
    /// Service used for Helm's own cached copy of a VPN's credentials.
    private let helmVPNKeychainService = "com.helm.vpn"

    public init() { Self.purgeItemsWithTheOldAccessList() }

    /// Items written by the previous implementation carry an access list that
    /// lets `/usr/bin/security` read them with no prompt — anything running as
    /// this user could take the secret. Updating them in place would keep that
    /// list, so they are removed once; the next connect re-reads the System
    /// keychain (one prompt) and re-caches them properly.
    private static func purgeItemsWithTheOldAccessList() {
        let key = "module.vpn.credentialCachePurged"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "com.helm.vpn"] as CFDictionary)
        // Only once it is actually gone. Helm starts at login, when the keychain
        // can still be locked (`errSecInteractionNotAllowed`); marking the purge
        // done first would leave the readable-by-anything item in place forever,
        // which is the one thing this exists to prevent.
        guard status == errSecSuccess || status == errSecItemNotFound else { return }
        UserDefaults.standard.set(true, forKey: key)
        if status == errSecSuccess {
            HelmLog.shared.info("vpn", "cleared the old credential cache")
        }
    }

    public func credentials(for name: String) -> VPNCredentials? {
        let show = Shell.run("/usr/sbin/scutil", ["--nc", "show", name]).output
        guard let uuid = Self.value(inScutilShow: show, field: "AuthPassword") else { return nil }
        let authName = Self.value(inScutilShow: show, field: "AuthName")

        // 1. Helm's own cache (no prompt — we own these items).
        if let secret = helmCacheRead("\(uuid).ss"), !secret.isEmpty {
            return VPNCredentials(user: authName,
                                  password: helmCacheRead("\(uuid).pw"),
                                  secret: secret)
        }

        // 2. First time: read the System keychain (this may prompt once).
        let secret = Self.keychainSecret(service: "\(uuid).SS", account: nil,
                                         keychain: "/Library/Keychains/System.keychain")
        guard let secret, !secret.isEmpty else { return nil }
        let password = Self.keychainSecret(service: uuid, account: authName,
                                           keychain: "/Library/Keychains/System.keychain")

        // 3. Cache in Helm's login keychain so future connects need no prompt.
        helmCacheWrite("\(uuid).ss", secret)
        if let password, !password.isEmpty { helmCacheWrite("\(uuid).pw", password) }

        return VPNCredentials(user: authName, password: password, secret: secret)
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: helmVPNKeychainService,
         kSecAttrAccount as String: account]
    }

    private func helmCacheRead(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Written through the keychain API, not the `security` tool.
    ///
    /// The tool needed the secret as a command-line argument — process
    /// arguments are readable by every process running as this user for as long
    /// as the process lives — and it was given `-T /usr/bin/security`, which
    /// meant `security find-generic-password -w -s com.helm.vpn` handed the
    /// secret to any script with no prompt at all. That is a lower bar than the
    /// System keychain this cache exists to avoid re-reading.
    ///
    /// `SecItemAdd` gives the item an access list containing only the app that
    /// created it, and the value never appears in an argument list. Delete
    /// before add, so an item left behind by the old path loses its access list
    /// rather than keeping it through an update.
    private func helmCacheWrite(_ account: String, _ value: String) {
        var attributes = query(account)
        SecItemDelete(attributes as CFDictionary)
        attributes[kSecValueData as String] = Data(value.utf8)
        // The secret is useless on another Mac and pointless while locked.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            HelmLog.shared.warn("vpn", "could not cache credentials: \(HelmFailure.osStatus(status))")
        }
    }

    /// The value of a `Field : value` line in `scutil --nc show` output.
    private static func value(inScutilShow output: String, field: String) -> String? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(field) :") else { continue }
            let parts = trimmed.components(separatedBy: " : ")
            if parts.count >= 2 {
                let v = parts[1].trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
        }
        return nil
    }

    /// Reads a generic password value (`security -w`) from `keychain` (nil = the
    /// default/login keychain). Returns nil if absent or unreadable. Never logs
    /// the value.
    private static func keychainSecret(service: String, account: String?, keychain: String?) -> String? {
        var args = ["find-generic-password", "-w", "-s", service]
        if let account, !account.isEmpty { args += ["-a", account] }
        if let keychain { args.append(keychain) }
        let result = Shell.run("/usr/bin/security", args)
        guard result.status == 0 else { return nil }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

// MARK: - SystemAutomationNotice

/// Production `AutomationNoticePort`: `UNUserNotificationCenter`.
///
/// **Nothing here may run in a test.** `UNUserNotificationCenter.current()`
/// raises `NSInternalInconsistencyException` — "bundleProxyForCurrentProcess is
/// nil" — in any process that is not a bundled app, which kills the whole
/// `swift test` run rather than failing one case. That is why the centre is
/// reached inside each method and never in `init`: constructing
/// `VPNSystemPorts` must stay free, so the tests that build a descriptor or an
/// engine keep working. The behaviour is tested against fakes through
/// `AutomationNoticePort`; this class is covered by Task 10's manual pass.
public final class SystemAutomationNotice: AutomationNoticePort {
    public init() {}

    public func authorizationState() async -> NoticeAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        // Provisional and ephemeral both post without a prompt, so for the one
        // question this port answers — will a banner appear — they are yes.
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    /// Asked once, when the person picks the banner mode. macOS shows the
    /// prompt only the first time; afterwards this returns the standing answer
    /// without troubling anyone.
    public func requestAuthorization() async -> NoticeAuthorization {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert])
            return granted ? .authorized : .denied
        } catch {
            HelmLog.shared.warn("vpn", "could not ask macOS about banners: "
                + HelmFailure.describe(error))
            return .denied
        }
    }

    /// No trigger: nil means now, which is what a rule that has already fired
    /// needs. The identifier is fresh each time so two firings stack instead of
    /// the second replacing the first.
    public func post(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // The name is in `body`, and the log carries no names.
            HelmLog.shared.warn("vpn", "macOS refused the banner: "
                + HelmFailure.describe(error))
        }
    }
}

// MARK: - VPNSystemPorts

/// Bundles the production, system-backed ports the VPN engine needs at
/// runtime. AppKit/Foundation only — kept in this one file so the rest of the
/// engine target stays SwiftUI/AppKit-free and unit-testable with fakes.
public struct VPNSystemPorts {
    public let runner = ScutilRunner()
    public let credentials = KeychainCredentials()
    public let apps = WorkspaceAppObserver()
    public let network = DynamicStoreNetworkWatch()
    public let notice = SystemAutomationNotice()
    public init() {}
}
