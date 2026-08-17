// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import Foundation
import HelmRuntime
import Security
import SystemConfiguration

// MARK: - ScutilRunner

/// Production `VPNRunnerPort`: shells out to `/usr/sbin/scutil`.
public final class ScutilRunner: VPNRunnerPort {
    public init() {}
    public func run(_ args: [String]) -> HelmProcess.Result {
        HelmProcess.run("/usr/sbin/scutil", args)
    }
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

    /// The signature of what is running under that identifier.
    ///
    /// Two steps, on two sides of the same rule: *where* the bundle is comes from
    /// the snapshot `RunningApps` took on the main thread, and reading the
    /// signature at that path is Security's, which is safe anywhere. Asking AppKit
    /// for the running application here instead would be the crash this whole
    /// arrangement exists to prevent.
    public func identity(of bundleID: String) -> CodeIdentity? {
        RunningApps.shared.bundleURL(of: bundleID).flatMap(CodeIdentity.of(bundleAt:))
    }

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
            HelmLog.shared.warn(VPNEngine.moduleID, "no network-state session; the connection list "
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
            HelmLog.shared.warn(VPNEngine.moduleID, "could not subscribe to network-state changes")
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
    ///
    /// **Who may run this, and the record that it has, are `CredentialCachePurge`'s
    /// to answer** — this deletes somebody's stored secrets, and it used to do so
    /// on every `swift test` run with a latch that could not remember it had.
    private static func purgeItemsWithTheOldAccessList() {
        let marker = CredentialCachePurge.markerURL
        let fm = FileManager.default
        // The bundle question first, so a test runner reaches neither the disk nor
        // the keychain.
        guard CredentialCachePurge.shouldRun(bundledApp: AppBuild.isBundledApp,
                                             recorded: fm.fileExists(atPath: marker.path))
        else { return }
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "com.helm.vpn"] as CFDictionary)
        // Only once it is actually gone. Helm starts at login, when the keychain
        // can still be locked (`errSecInteractionNotAllowed`); marking the purge
        // done first would leave the readable-by-anything item in place forever,
        // which is the one thing this exists to prevent.
        guard status == errSecSuccess || status == errSecItemNotFound else { return }
        PrivateFile.directory(at: marker.deletingLastPathComponent())
        PrivateFile.write(Data(), to: marker)
        if status == errSecSuccess {
            HelmLog.shared.info(VPNEngine.moduleID, "cleared the old credential cache")
        }
    }

    public func credentials(for name: String, promptingAllowed: Bool) -> VPNCredentialRead {
        let show = HelmProcess.run("/usr/sbin/scutil", ["--nc", "show", name]).output
        // No `AuthPassword` line: this configuration keeps no secret Helm has to
        // supply, and `--nc start` connects it on its own. `.notNeeded` rather
        // than the nil this used to be — see `VPNCredentialRead`, and the
        // warning that would otherwise be drawn under every IKEv2 connect.
        guard let uuid = Self.value(inScutilShow: show, field: "AuthPassword") else {
            return .notNeeded
        }
        let authName = Self.value(inScutilShow: show, field: "AuthName")

        // 1. Helm's own cache (no prompt while the item's access list still names
        // this build — see below).
        let cached = helmCacheRead("\(uuid).ss")
        if case .value(let secret) = cached, !secret.isEmpty {
            return .ready(VPNCredentials(user: authName,
                                         password: helmCacheRead("\(uuid).pw").value,
                                         secret: secret))
        }
        // **An item that is there and unreadable is not an empty cache**, and the
        // two were one silent nil. `SecItemAdd` binds the access list to the code
        // identity that wrote it, and this bundle is ad-hoc signed — every install
        // is a different identity to macOS (ARCHITECTURE.md § Permissions) — so
        // this is the ordinary state of the cache after an update, not an exotic
        // one. Logged with the status, because «no cached credentials» sent the
        // last investigation looking for a purge that had run hours earlier.
        if case .refused(let status) = cached {
            HelmLog.shared.warn(VPNEngine.moduleID, "the cached credential for \(Redact.vpn(name)) is not "
                + "readable by this build: \(HelmFailure.osStatus(status))")
        }

        // 2. First time: read the System keychain, which macOS gates behind an
        // authorization dialog — and that is the whole reason a caller may
        // refuse it. A rule out of an unsealed plist decides both which
        // configuration and *when*, so it gets the cache or nothing; the prompt
        // waits for somebody pressing Connect.
        guard promptingAllowed else {
            HelmLog.shared.info(VPNEngine.moduleID, "no cached credentials for \(Redact.vpn(name)); an "
                + "automatic connect does not ask the System keychain")
            return .behindAPrompt
        }
        let secret = Self.keychainSecret(service: "\(uuid).SS", account: nil,
                                         keychain: "/Library/Keychains/System.keychain")
        // Still `.behindAPrompt`: there *is* a secret — the configuration named
        // the keychain item that holds it — and this read did not come back with
        // it. A declined dialog and a locked keychain both land here, and both
        // leave the same fact behind for the screen to say.
        guard let secret, !secret.isEmpty else { return .behindAPrompt }
        let password = Self.keychainSecret(service: uuid, account: authName,
                                           keychain: "/Library/Keychains/System.keychain")

        // 3. Cache in Helm's login keychain so future connects need no prompt.
        helmCacheWrite("\(uuid).ss", secret)
        if let password, !password.isEmpty { helmCacheWrite("\(uuid).pw", password) }

        return .ready(VPNCredentials(user: authName, password: password, secret: secret))
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: helmVPNKeychainService,
         kSecAttrAccount as String: account]
    }

    /// What a read of Helm's own cache found — **three answers, for the reason
    /// `VPNCredentialRead` has three.**
    ///
    /// «Nothing there» and «there and this build may not read it» were one nil, and
    /// the second is the ordinary state after every install: an item's access list
    /// names the code identity that created it, and an ad-hoc signed bundle has a
    /// new identity in every build. A caller that cannot tell them apart reports
    /// «no cached credentials» for a cache that is full.
    ///
    /// **`KeychainSealKey.Read` in `HelmRuntime` is this same triage**, down to the
    /// `errSecItemNotFound` branch and the `HelmFailure.osStatus` line — the second
    /// spelling of it, and therefore a hoist that is owed rather than a shape to
    /// copy a third time. Not taken here: it would refactor an untested,
    /// security-critical read outside this fix.
    ///
    /// **What this cannot tell you**, and it matters for the rule above about
    /// automatic connects never summoning a dialog: whether macOS raises the
    /// «Helm wants to use your confidential information» panel *inside*
    /// `SecItemCopyMatching` when the access list no longer names this build. If it
    /// does, an item left by the previous install is a second route to a prompt an
    /// automatic connect never asked for. `kSecUseAuthenticationUI` would settle it
    /// and cannot be tried without writing to somebody's real keychain, so it is
    /// recorded rather than guessed at.
    private enum CacheRead {
        case value(String)
        /// No such item, or bytes that are not a string.
        case missing
        /// An item macOS would not hand over. The status is kept for the log —
        /// `errSecAuthFailed` and `errSecInteractionNotAllowed` are different
        /// stories and a bare "unreadable" tells neither.
        case refused(OSStatus)

        var value: String? {
            if case .value(let v) = self { return v }
            return nil
        }
    }

    private func helmCacheRead(_ account: String) -> CacheRead {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        guard status == errSecSuccess else {
            return status == errSecItemNotFound ? .missing : .refused(status)
        }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return .missing }
        return .value(value)
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
    ///
    /// **What protects this item is that access list, and nothing else.** It used
    /// to set `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` under a comment saying
    /// the secret was "useless on another Mac and pointless while locked" — a claim
    /// that was not in force. Without `kSecUseDataProtectionKeychain` the item
    /// lands in the file-based login keychain, where that attribute does not
    /// apply: measured on the two live items, neither carried a `pdmn` at all. A
    /// comment claiming a protection that is not applied is worse than no comment,
    /// because it closes the question, so the claim is gone rather than the
    /// attribute being left to look like it does something.
    ///
    /// Moving to the data-protection keychain is the real fix and it is not
    /// available yet: it needs the flag on the write, the read *and* the delete
    /// (they must agree or the read stops finding the write), and it needs an
    /// `application-identifier` entitlement this ad-hoc-signed bundle has not got
    /// — the same Developer ID already blocking `NEVPNManager`, the seal on
    /// `clamshellEnabled` and notarization. It would also be a change to the
    /// credential path that cannot be tested without writing to somebody's real
    /// keychain. `ASecretsProtectionIsNotClaimedTwiceTests` holds the pair
    /// together: the attribute may come back only with the flag beside it.
    private func helmCacheWrite(_ account: String, _ value: String) {
        var attributes = query(account)
        SecItemDelete(attributes as CFDictionary)
        attributes[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            HelmLog.shared.warn(VPNEngine.moduleID, "could not cache credentials: \(HelmFailure.osStatus(status))")
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
        let result = HelmProcess.run("/usr/bin/security", args)
        guard result.status == 0 else { return nil }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

// MARK: - DynamicStoreInterfaces

/// Production `VPNInterfacePort`: the dynamic store, which is where macOS keeps
/// what is up right now.
///
/// **Not `ifconfig`, and not the configuration.** A configuration says what a
/// service would be; `State:/Network/Service/<id>/IPv4` exists only while the
/// service is actually up, and its `InterfaceName` is the `utunN` the tunnel is
/// on this time. The global key answers the other half — which interface the
/// default route goes out of — and that pair is the routing verdict.
///
/// The counters are the one answer that does not come from the store: the store
/// says which interface a service is on, and only the kernel knows what that
/// interface has carried (`VPNInterfaceCounters`).
public final class DynamicStoreInterfaces: VPNInterfacePort {

    public init() {}

    public func bytes(on interface: String) -> (in: UInt64, out: UInt64)? {
        VPNInterfaceCounters.bytes(on: interface)
    }

    public func interface(forServiceID id: String) -> String? {
        value(forKey: "State:/Network/Service/\(id)/IPv4" as CFString, field: "InterfaceName")
    }

    public func primaryInterface() -> String? {
        value(forKey: "State:/Network/Global/IPv4" as CFString, field: "PrimaryInterface")
    }

    private func value(forKey key: CFString, field: String) -> String? {
        guard let store = SCDynamicStoreCreate(nil, "com.helm.vpn.interfaces" as CFString,
                                               nil, nil),
              let dict = SCDynamicStoreCopyValue(store, key) as? [String: Any]
        else { return nil }
        return dict[field] as? String
    }
}

// MARK: - TraceExit

/// Production `VPNExitPort`: Cloudflare's trace endpoint.
///
/// **A region code is all that is taken.** The endpoint answers plain text, one
/// `key=value` per line, and the line that matters is `loc=NL`; the `ip=` line is
/// in the same response and is never read into a variable, so there is nothing
/// holding an address to leak into a log, a payload or a screenshot. The country
/// the person sees is `Locale`'s own name for that code, in the app's language,
/// which is also why no third party gets to name a place in Helm's window.
///
/// Chosen for its size and for answering without an API key. It is a third party
/// nevertheless: it learns that this machine asked, and that is the cost the
/// check has. It is made only when a tunnel comes up.
public final class TraceExit: VPNExitPort {

    private let url: URL
    private let session: URLSession

    public init(url: URL = URL(string: "https://cloudflare.com/cdn-cgi/trace")!,
                session: URLSession = {
                    let config = URLSessionConfiguration.ephemeral
                    config.timeoutIntervalForRequest = 8
                    config.urlCache = nil
                    return URLSession(configuration: config)
                }()) {
        self.url = url
        self.session = session
    }

    /// The phase is named here rather than by the caller: this is the shared path
    /// every exit check goes through, and a wait of up to eight seconds should say
    /// what it is while it runs (CLAUDE.md § A phase names itself while it runs).
    public func regionCode() async -> String? {
        await HelmActivity.phase("vpn.exit") {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let text = String(data: data, encoding: .utf8)
            else { return nil }
            return Self.region(in: text)
        }
    }

    /// `loc=NL` out of the tool's own line-per-field text. Internal rather than
    /// private so the parser has a test that runs no request.
    static func region(in text: String) -> String? {
        for line in text.split(separator: "\n") where line.hasPrefix("loc=") {
            let code = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
            return code.count == 2 ? code.uppercased() : nil
        }
        return nil
    }
}

// MARK: - NetworkQualitySpeed

/// Production `VPNSpeedPort`: the tool macOS ships.
///
/// `-c` for machine-readable output, `-I` to bind the run to one interface. The
/// deadline is generous because the tool takes about 15 s by design and a run
/// killed early prints half its JSON, which `VPNSpeedReading.parse` refuses.
///
/// **Nothing binds today, and the parameter stays.** Measured on this machine,
/// 2026-08-18: `networkQuality -c -I utunN` against a live tunnel prints
/// `"error_code": -1009, "error_domain": "NSURLErrorDomain"`, exits 0 and
/// carries no throughput keys at all, while the same tool unbound answers
/// normally — a socket bound to a point-to-point tun's address does not reach
/// the network here. So the engine measures unbound and says why
/// (`VPNEngine.measureSpeed`); this keeps the seam a build with a working bind
/// goes through, rather than removing the only place the question is asked.
public final class NetworkQualitySpeed: VPNSpeedPort {

    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) { self.now = now }

    public func measure(onInterface interface: String?) -> VPNSpeedReading? {
        HelmActivity.phase("vpn.speed") {
            var args = ["-c"]
            if let interface { args += ["-I", interface] }
            let result = HelmProcess.run("/usr/bin/networkQuality", args, timeout: 60)
            guard result.status == 0 else { return nil }
            return VPNSpeedReading.parse(result.output, at: now())
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
    public init() {}
}
