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
    init() {}
    public func run(_ args: [String]) -> HelmProcess.Result {
        HelmProcess.run("/usr/sbin/scutil", args)
    }
    /// The query form: a `scutil` still running at `timeout` is terminated and
    /// the answer is `HelmProcess.timedOutStatus` with no output.
    public func read(_ args: [String], timeout: TimeInterval) -> HelmProcess.Result {
        HelmProcess.run("/usr/sbin/scutil", args, timeout: timeout)
    }

    /// The start that carries a secret, in this process: `scutil --nc start`
    /// takes `--user`, `--password` and `--secret` only as arguments, which every
    /// process of this user can read while the child lives.
    ///
    /// Called on the module's work queue like `run`, and it does not block:
    /// `SCNetworkConnectionStart` hands the start to the system and returns
    /// (`linger` true, or the start would be undone when `connection` is
    /// released at the end of this function). Nothing here is logged: a name
    /// would be, and the answer is a code.
    public func start(_ name: String, supplying credentials: VPNCredentials) -> VPNStartAnswer {
        // Unreadable and absent are different news: only a list that was read
        // and held no such name is `.noSuchService`.
        guard let prefs = SCPreferencesCreate(nil, "Helm" as CFString, nil),
              let set = SCNetworkSetCopyCurrent(prefs),
              let services = SCNetworkSetCopyServices(set) as? [SCNetworkService]
        else { return .unreadable }
        guard let service = services.first(where: { SCNetworkServiceGetName($0) as String? == name })
        else { return .noSuchService }
        guard let serviceID = SCNetworkServiceGetServiceID(service),
              let connection = SCNetworkConnectionCreateWithServiceID(nil, serviceID, nil, nil)
        else { return .unreadable }
        // `scutil` hands over by the service's own interface type; a PPP service
        // says nothing about its transport, the interface under it does.
        let outer = SCNetworkServiceGetInterface(service)
        let kind = outer.flatMap { SCNetworkInterfaceGetInterfaceType($0) as String? } ?? ""
        let inner = outer.flatMap { SCNetworkInterfaceGetInterface($0) }
            .flatMap { SCNetworkInterfaceGetInterfaceType($0) as String? }
        let options = VPNStartOptions.userOptions(credentials, interface: kind, inner: inner)
        guard SCNetworkConnectionStart(connection, options as CFDictionary?, true) else {
            return .refused(code: SCError())
        }
        return .started
    }
}

// MARK: - WorkspaceAppObserver

/// Production `AppObserverPort`: reads/observes `NSWorkspace.runningApplications`.
/// KVO rather than launch/terminate notifications, because KVO is more reliable
/// for Catalyst apps.
public final class WorkspaceAppObserver: AppObserverPort {
    private var observation: NSKeyValueObservation?

    init() {}

    /// Through `RunningApps`, never straight to AppKit: the engine calls this
    /// from its own serial queue, and reading the live list off main crashes
    /// when a program quits at the wrong moment.
    public func runningBundleIDs() -> Set<String> { RunningApps.shared.bundleIDs() }

    /// The signature of what is running under that identifier.
    ///
    /// *Where* the bundle is comes from the snapshot `RunningApps` took on the
    /// main thread; reading the signature at that path is Security's, which is
    /// safe anywhere. Asking AppKit here instead would be the off-main crash.
    public func identity(of bundleID: String) -> CodeIdentity? {
        RunningApps.shared.bundleURL(of: bundleID).flatMap(CodeIdentity.of(bundleAt:))
    }

    public func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        // No .initial: the engine seeds already-running apps itself, so firing
        // on registration would just cause a redundant full app-list scan.
        observation?.invalidate()
        observation = NSWorkspace.shared.observe(\.runningApplications) { _, _ in
            // KVO arrives on the thread that changed the list — the main one.
            // The snapshot is taken here, while it is safe to read, so that the
            // engine's queue has something correct to read a moment later.
            RunningApps.shared.refreshOnMain(then: onChange)
        }
    }

    public func stopObserving() {
        observation?.invalidate()
        observation = nil
    }
}

// MARK: - DynamicStoreNetworkWatch

/// Production `NetworkWatchPort`: a `SCDynamicStore` session on the keys that
/// move when a tunnel does, so a VPN started from the macOS menu bar, stopped in
/// System Settings, or dropped by the network is seen without asking Helm.
public final class DynamicStoreNetworkWatch: NetworkWatchPort {

    /// The callback's context, and the reason this is a class rather than the
    /// closure itself.
    ///
    /// `SCDynamicStoreCreate` retains what the context holds and releases it
    /// when the session goes, so a notification already on the queue when the
    /// module is switched off resolves to a live object rather than to freed
    /// memory (Architecture/StateAndLifetime.md § An observer outlives the thing it points at).
    /// Clearing the action is what makes that late notification a no-op.
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

    init() {}
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
        // System Settings, which the rule editor's list must follow.
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
/// L2TP/IPSec VPN needs, so that a start does not prompt for the IPSec shared
/// secret.
///
/// macOS gates every read of a VPN secret in the System keychain by a
/// third-party app behind a prompt (System Settings is exempt as an Apple
/// binary). So the System keychain is read at most once, the values are cached
/// in Helm's own login-keychain items (read back without a prompt), and the
/// cache answers thereafter. Answers `.notNeeded` for VPNs without a stored
/// shared secret (e.g. IKEv2). Secrets stay in memory and the keychain, never
/// in an argument list, the environment, a file or the log.
public final class KeychainCredentials: VPNCredentialsPort {
    /// Service used for Helm's own cached copy of a VPN's credentials, spelled
    /// in this one place for the cache and for its one-time purge. Both literals
    /// are data on the owner's Mac once written and are never re-keyed: the real
    /// Helm's is `com.helm.vpn`, Helm Dev's is `com.helm.vpn.dev`, so Dev's cache
    /// writes never rebind the real item's access list to Dev's identity.
    static func service(for bundleIdentifier: String?) -> String {
        AppBuild.isDevIdentifier(bundleIdentifier) ? "com.helm.vpn.dev" : "com.helm.vpn"
    }

    /// Whether this build may run the one-time purge. Helm Dev may not: the items
    /// with the readable access list are the real Helm's, and Dev's own service
    /// never held any.
    static func mayPurge(for bundleIdentifier: String?) -> Bool {
        !AppBuild.isDevIdentifier(bundleIdentifier)
    }

    /// The keychain query for Helm's cache: every item of the service, or one
    /// account's item. The read, the write and the purge all build it here.
    static func cacheQuery(account: String? = nil,
                           bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service(for: bundleIdentifier)]
        if let account { q[kSecAttrAccount as String] = account }
        return q
    }

    /// The purge's delete, with the keychain call as a parameter so a test can
    /// read the query it sends without touching the keychain.
    static func deleteEveryCacheItem(_ delete: (CFDictionary) -> OSStatus = SecItemDelete) -> OSStatus {
        delete(cacheQuery() as CFDictionary)
    }

    /// Asks `scutil --nc show` through the module's runner, so the read has the
    /// same deadline and the same seam as every other.
    private let runner: VPNRunnerPort

    /// How long the System-keychain read may wait. The read can sit behind a
    /// dialog a person is reading, so this is long: it bounds a hang, not the
    /// person. Without it a dialog nobody answers parks `VPNWorkQueue` for the
    /// life of the process.
    static let systemKeychainDeadline: TimeInterval = 600

    private let keychainTool: String
    private let keychainDeadline: TimeInterval

    convenience init() { self.init(purge: { Self.purgeItemsWithTheOldAccessList() }) }

    /// The purge as an action, so a test can watch when it runs without ever
    /// reaching a keychain.
    ///
    /// **The decision is not injected, only the doing.**
    /// `CredentialCachePurge.shouldRun` asks `AppBuild.isBundledApp` inside the
    /// default action, so `swift test` never deletes the owner's real VPN
    /// secrets. Internal rather than public: no other target may forget which
    /// one it is taking.
    ///
    /// **And it runs off the thread that built this.** That thread is the main
    /// one (`VPNDescriptor.makeModule` is `@MainActor`), and a `SecItemDelete`
    /// there is a launch-time keychain call: a hang, and on an ad-hoc-signed
    /// bundle a dialog at every install (Architecture/StoredSettings.md § Sealed settings).
    /// Nothing waits for the answer: the port re-reads the System keychain past
    /// any item the purge has not reached yet.
    ///
    /// A global queue rather than `offTheCooperativePool`, which is the bridge
    /// *out of* an async context, and there is none here; and a keychain dialog
    /// holds its thread for as long as a person looks at it, which the
    /// cooperative pool must never be spent on.
    ///
    /// The tool and its deadline are parameters so a test can put a stub that
    /// sleeps in place of `security` and wait a second instead of ten minutes.
    init(purge: @escaping @Sendable () -> Void, runner: VPNRunnerPort = ScutilRunner(),
         keychainTool: String = "/usr/bin/security",
         keychainDeadline: TimeInterval = KeychainCredentials.systemKeychainDeadline) {
        self.runner = runner
        self.keychainTool = keychainTool
        self.keychainDeadline = keychainDeadline
        DispatchQueue.global(qos: .utility).async(execute: purge)
    }

    /// Items that carry an access list letting `/usr/bin/security` read them with
    /// no prompt give the secret to anything running as this user. Updating them
    /// in place would keep that list, so they are removed once; the next connect
    /// re-reads the System keychain (one prompt) and re-caches them.
    ///
    /// **Who may run this, and the record that it has, are `CredentialCachePurge`'s
    /// to answer**: this deletes somebody's stored secrets. Internal, with the
    /// keychain call a parameter, so a test can watch that nothing is sent.
    static func purgeItemsWithTheOldAccessList(delete: (CFDictionary) -> OSStatus = SecItemDelete) {
        let marker = CredentialCachePurge.markerURL
        // The bundle question first, so a test runner reaches neither the disk nor
        // the keychain.
        guard CredentialCachePurge.shouldRun(bundledApp: AppBuild.isBundledApp,
                                             recorded: FileManager.default.fileExists(atPath: marker.path))
        else { return }
        purgeTheCache(bundleIdentifier: Bundle.main.bundleIdentifier, marker: marker, delete: delete)
    }

    /// The deleting and the recording, with the keychain call and the marker as
    /// parameters so a test reads the query sent without a keychain. A build that
    /// may not purge (Helm Dev) sends nothing and records nothing.
    static func purgeTheCache(bundleIdentifier: String?, marker: URL,
                              delete: (CFDictionary) -> OSStatus = SecItemDelete) {
        guard mayPurge(for: bundleIdentifier) else { return }
        let status = KeychainCredentials.deleteEveryCacheItem(delete)
        // Only once it is actually gone. Helm starts at login, when the keychain
        // can still be locked (`errSecInteractionNotAllowed`); marking the purge
        // done first would leave the readable-by-anything item in place forever.
        guard status == errSecSuccess || status == errSecItemNotFound else { return }
        let recorded = PrivateFile.writeMakingTheFolder(Data(), at: marker)
        if status == errSecSuccess {
            HelmLog.shared.info(VPNEngine.moduleID, "cleared the old credential cache")
        }
        // An unrecorded purge runs again and its second `SecItemDelete` finds
        // nothing, which is safe. The warning explains the line above, which
        // would otherwise announce the same clearing at every launch.
        if !recorded {
            HelmLog.shared.warn(VPNEngine.moduleID, "the credential-cache purge could not be "
                                + "recorded — it will run again at the next launch")
        }
    }

    /// Answers `.unreadable` when `--nc show` timed out or exited non-zero (a
    /// warning names the status or the timeout, the name redacted);
    /// `.notNeeded` only for a show that ran to the end and kept no secret —
    /// no `AuthPassword` field, or no output at all.
    public func credentials(for name: String, promptingAllowed: Bool) -> VPNCredentialRead {
        let shown = runner.read(["--nc", "show", name], timeout: vpnReadDeadline)
        // A read that ran out of time or failed is not an empty one: nobody knows
        // whether a secret is kept, and a connect without it would report
        // success either way (`--nc start` answers nothing), so a rule would
        // announce "connected" with no tunnel. The engine neither starts nor
        // announces on `.unreadable`.
        if shown.status != 0 {
            HelmLog.shared.warn(VPNEngine.moduleID, "the configuration of \(Redact.vpn(name)) could not be read "
                + "(\(vpnReadFailureReason(shown.status))); "
                + "the secret is not known")
            return .unreadable
        }
        let show = shown.output
        // No `AuthPassword` line: this configuration keeps no secret Helm has to
        // supply, and `--nc start` connects it on its own (`VPNCredentialRead`).
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
        // **An item that is there and unreadable is not an empty cache.**
        // `SecItemAdd` binds the access list to the code identity that wrote it,
        // and this bundle is ad-hoc signed — every install is a different identity
        // to macOS (Architecture/Release.md § Signing and grants) — so this is the
        // ordinary state of the cache after an update. Logged with the status, so
        // the line is not mistaken for an empty cache.
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
        let secret = keychainSecret(service: "\(uuid).SS", account: nil,
                                    keychain: "/Library/Keychains/System.keychain")
        // Still `.behindAPrompt`: there *is* a secret — the configuration named
        // the keychain item that holds it — and this read did not come back with
        // it. A declined dialog and a locked keychain both land here, and both
        // leave the same fact behind for the screen to say.
        guard let secret, !secret.isEmpty else { return .behindAPrompt }
        let password = keychainSecret(service: uuid, account: authName,
                                      keychain: "/Library/Keychains/System.keychain")

        // 3. Cache in Helm's login keychain so future connects need no prompt.
        helmCacheWrite("\(uuid).ss", secret)
        if let password, !password.isEmpty { helmCacheWrite("\(uuid).pw", password) }

        return .ready(VPNCredentials(user: authName, password: password, secret: secret))
    }

    private func query(_ account: String) -> [String: Any] {
        Self.cacheQuery(account: account)
    }

    /// What a read of Helm's own cache found — **three answers, for the reason
    /// `VPNCredentialRead` has three.**
    ///
    /// «There and this build may not read it» is the ordinary state after every
    /// install: an item's access list names the code identity that created it,
    /// and an ad-hoc signed bundle has a new identity in every build. A caller
    /// that took it for «nothing there» would report «no cached credentials» for
    /// a cache that is full.
    ///
    /// **`KeychainItem.read` in `HelmRuntime` is this same triage**, and it stays a
    /// second spelling on purpose: this read is a security-critical path with no
    /// test that reaches a keychain, and moving it would change it untested.
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

    /// Written through the keychain API, never through the `security` tool,
    /// which takes the value only as a command-line argument: every process of
    /// this user can read a child's arguments while it lives. `SecItemAdd` gives
    /// the item an access list naming only the app that created it. Delete
    /// before add, so an item with a wider access list loses it rather than
    /// keeping it through an update.
    ///
    /// **What protects this item is that access list, and nothing else.**
    /// Without `kSecUseDataProtectionKeychain` the item lands in the file-based
    /// login keychain, where `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` does
    /// not apply, so that attribute is not set to look as if it did.
    ///
    /// The data-protection keychain needs the flag on the write, the read *and*
    /// the delete (they must agree or the read stops finding the write), and an
    /// `application-identifier` entitlement this ad-hoc-signed bundle has not
    /// got. `TheRulesTheCompilerCannotHoldTests` holds the pair together: the
    /// attribute may come back only with the flag beside it.
    private func helmCacheWrite(_ account: String, _ value: String) {
        var attributes = query(account)
        SecItemDelete(attributes as CFDictionary)
        attributes[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            HelmLog.shared.warn(VPNEngine.moduleID, "could not cache credentials: \(HelmFailure.osStatus(status))")
        }
    }

    /// The value of a `Field : value` line in `scutil --nc show` output, read by
    /// `VPNStatusParser.value(of:in:)`. A line with an empty value is skipped and
    /// the first non-empty one wins; none means nil, so an empty `AuthPassword` is
    /// no secret.
    private static func value(inScutilShow output: String, field: String) -> String? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let v = VPNStatusParser.value(of: field, in: trimmed), !v.isEmpty { return v }
        }
        return nil
    }

    /// Reads a generic password value from `keychain` (nil = the default/login
    /// keychain) through `security find-generic-password -w`: the arguments name
    /// only the item, and the secret comes back on stdout, read here and never
    /// logged. Returns nil if absent, unreadable or not answered within
    /// `keychainDeadline`; a timeout is logged, with no name.
    private func keychainSecret(service: String, account: String?, keychain: String?) -> String? {
        var args = ["find-generic-password", "-w", "-s", service]
        if let account, !account.isEmpty { args += ["-a", account] }
        if let keychain { args.append(keychain) }
        let result = HelmProcess.run(keychainTool, args, timeout: keychainDeadline)
        guard result.status == 0 else {
            if result.status == HelmProcess.timedOutStatus {
                HelmLog.shared.warn(VPNEngine.moduleID, "the System keychain did not answer within "
                    + "\(Int(keychainDeadline)) s; the secret is not known")
            }
            return nil
        }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

// MARK: - DynamicStoreInterfaces

/// Production `VPNInterfacePort`: the dynamic store, which is where macOS keeps
/// what is up right now.
///
/// **The global key only.** «Which interface is service `<id>` on» cannot be
/// asked of `State:/Network/Service/<id>/IPv4` with the id the module has:
/// `scutil --nc list` names a *configuration*, the store is keyed by *network
/// service*, and for a NetworkExtension tunnel those differ. The tunnel's own
/// interface comes from `scutil --nc status <name>` (`VPNStatusParser`); what
/// is here is the routing half of the verdict, which the global key answers
/// by no identifier at all.
///
/// The counters are the one answer that does not come from the store: the store
/// says which interface a service is on, and only the kernel knows what that
/// interface has carried (`VPNInterfaceCounters`).
public final class DynamicStoreInterfaces: VPNInterfacePort {

    public init() {}

    public func bytes(on interface: String) -> (in: UInt64, out: UInt64)? {
        VPNInterfaceCounters.bytes(on: interface)
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
/// **A region code is all that is kept.** The endpoint answers plain text, one
/// `key=value` per line, and the whole of it — the `ip=` line included — is in
/// this process for as long as it takes to read `loc=NL` out of it. The address
/// is never stored, returned or logged: `regionCode()` answers a two-letter
/// code, and `region(in:)` refuses anything else. The country the person sees
/// is `Locale`'s own name for that code, in the app's language, so no third
/// party names a place in Helm's window.
///
/// Chosen for its size and for answering without an API key. It is a third party
/// nevertheless: it learns that this machine asked, and that is the cost the
/// check has. It is made only while a tunnel is up. A tunnel coming up asks whatever
/// country is on record and skips the checks (`force`, `VPNEngine.checkExit`). Every
/// other refresh asks only when no country is on record, no request is in flight and
/// no attempt that came back empty was started in the last minute (`VPNExitAsk.quietPeriod`,
/// `VPNExitAsk.should`). A default-route move clears the country, so it falls under
/// that rule.
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
    /// what it is while it runs (Architecture/DiagnosticsLog.md § The activity registry).
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
/// deadline is generous because the tool takes `typicalRun` and a run killed
/// early prints half its JSON, which `VPNSpeedReading.parse` refuses.
///
/// **Nothing binds, and the parameter stays.** `networkQuality -c -I utunN`
/// against a live tunnel prints `"error_code": -1009`, exits 0 and carries no
/// throughput keys, while the same tool unbound answers normally: a socket
/// bound to a point-to-point tun's address does not reach the network. So the
/// engine measures unbound and says why (`VPNEngine.measureSpeed`); this keeps
/// the seam a working bind would go through.
public final class NetworkQualitySpeed: VPNSpeedPort {

    /// **How long a run of `networkQuality -c` takes on a Mac**, and the one
    /// place the number lives. Near the *top* of the measured spread rather
    /// than the middle, because the two ways of being wrong are not equal: set
    /// short, the page's arc fills and hands over to the indeterminate spinner
    /// on half of all runs, and a signal that fires half the time says nothing.
    ///
    /// **The fallback, not the answer.** A reading carries its own run's length
    /// (`VPNSpeedReading.took`), so this is what the page draws against before
    /// this Mac has ever measured its own link.
    public static let typicalRun: TimeInterval = 22

    private let now: @Sendable () -> Date
    private let run: @Sendable ([String]) -> HelmProcess.Result

    /// The tool is a parameter so the case below is a test rather than a memory.
    /// A port whose only path to its own refusals is a live network is a port
    /// whose refusals are never exercised.
    public init(now: @escaping @Sendable () -> Date = Date.init,
                run: @escaping @Sendable ([String]) -> HelmProcess.Result = {
                    HelmProcess.run("/usr/bin/networkQuality", $0, timeout: 60)
                }) {
        self.now = now
        self.run = run
    }

    public func measure(onInterface interface: String?) -> VPNSpeedReading? {
        HelmActivity.phase("vpn.speed") {
            var args = ["-c"]
            if let interface { args += ["-I", interface] }
            // Timed here: `HelmActivity.phase` is a registry of what is running
            // now, not a stopwatch, and hands nothing back when it ends.
            let began = now()
            let result = run(args)
            let ended = now()
            // **A status of 0 is not a success from this tool**: a failed run can
            // exit 0 with no throughput keys. So this guard catches only the tool
            // that could not be launched or was killed at its deadline; the
            // parser's «both throughput figures or nothing» refuses the rest.
            guard result.status == 0 else { return nil }
            // A run that took no measurable time did not take twenty seconds
            // either: nil rather than zero, which the page would draw an arc
            // against and `HelmExpectedWait` would answer «no claim» to by
            // arithmetic rather than by anybody deciding it.
            let took = ended.timeIntervalSince(began)
            return VPNSpeedReading.parse(result.output, at: ended,
                                         took: took > 0 ? took : nil)
        }
    }
}

// MARK: - VPNSystemPorts

/// Bundles the production, system-backed ports the VPN engine needs at
/// runtime. AppKit/Foundation only — kept in this one file so the rest of the
/// engine target stays SwiftUI/AppKit-free and unit-testable with fakes.
///
/// **All of them.** A bundle that lists some of the ports is worse than none:
/// the reader takes the list for the answer.
public struct VPNSystemPorts {
    public let runner = ScutilRunner()
    public let credentials = KeychainCredentials()
    public let apps = WorkspaceAppObserver()
    public let network = DynamicStoreNetworkWatch()
    public let interfaces = DynamicStoreInterfaces()
    /// The one server this app talks to that is not the update feed.
    public let exit = TraceExit()
    public let speed = NetworkQualitySpeed()
    public init() {}
}
