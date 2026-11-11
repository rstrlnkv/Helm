// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmRuntime

/// Whether the one-time removal of the old credential cache should run, and where
/// the record that it has lives.
///
/// The purge itself deletes every `com.helm.vpn` keychain item, because items
/// written by the first implementation carry an access list that let
/// `/usr/bin/security` read them with no prompt at all. It must happen once per
/// installation and never again, and two things would run it on **every**
/// run of anything that links this module:
///
/// - `VPNDescriptor.makeModule` builds `VPNSystemPorts()` unconditionally, which
///   constructs `KeychainCredentials`. A purge in its `init` runs from every test
///   that builds every descriptor's module, and `swift test` deletes the
///   person's real VPN secrets.
/// - A latch in `UserDefaults.standard` is the *calling process's* domain. The
///   test domain never holds it, and the deletion is retried on every run.
///
/// Both halves are answered here, and both are the lesson ARCHITECTURE.md
/// § Diagnostics log already records after a per-process latch let a test target
/// wipe the real `helm.log`: **a latch belongs to what it guards, not to whoever
/// asks.** What it guards is a keychain item, and a marker *inside* the keychain
/// would mean a keychain read during `init` — which on this ad-hoc-signed bundle
/// is a system dialog in front of the launch (ARCHITECTURE.md § Sealed
/// settings). So the record sits with Helm's own state on disk, which is per
/// installation rather than per process, and the app is asked whether it is the
/// app before any of it happens.
enum CredentialCachePurge {

    /// - Parameter bundledApp: whether this process is Helm and not a test
    ///   runner or a script. `AppBuild.isBundledApp` is the live answer; it is a
    ///   parameter so both states can be written down.
    /// - Parameter recorded: whether the marker says the purge has already run.
    static func shouldRun(bundledApp: Bool, recorded: Bool) -> Bool {
        bundledApp && !recorded
    }

    /// The record, beside Helm's own state. A dot-file because it is bookkeeping
    /// rather than anything a person put there.
    static var markerURL: URL {
        HelmSupport.directory.appendingPathComponent(".vpn-credential-cache-purged")
    }
}
