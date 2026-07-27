// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import Foundation
import HelmRuntime
import Security

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

// MARK: - VPNSystemPorts

/// Bundles the production, system-backed ports the VPN engine needs at
/// runtime. AppKit/Foundation only — kept in this one file so the rest of the
/// engine target stays SwiftUI/AppKit-free and unit-testable with fakes.
public struct VPNSystemPorts {
    public let runner = ScutilRunner()
    public let credentials = KeychainCredentials()
    public let apps = WorkspaceAppObserver()
    public init() {}
}
