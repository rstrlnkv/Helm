// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmRuntime

/// Whether the one-time removal of the old credential cache should run, and where
/// the record that it has lives.
///
/// The purge itself deletes every item of the service `KeychainCredentials.service(for:)` answers for the real Helm (`com.helm.vpn`; Helm Dev never purges and keeps `com.helm.vpn.dev`), because items
/// in that old cache carry an access list that lets `/usr/bin/security` read
/// them with no prompt at all. It must happen once per installation, and two
/// things would run it on **every** run of anything that links this module:
///
/// - `VPNDescriptor.makeModule` builds `VPNSystemPorts()` unconditionally, which
///   constructs `KeychainCredentials`. A purge in its `init` runs from every test
///   that builds every descriptor's module, and `swift test` deletes the
///   person's real VPN secrets.
/// - A latch in `UserDefaults.standard` is the *calling process's* domain. The
///   test domain never holds it, and the deletion is retried on every run.
///
/// Both halves are answered here: **a latch belongs to what it guards, not to
/// whoever asks** (Architecture/DiagnosticsLog.md). What it guards is a keychain
/// item, and a marker *inside* the keychain would mean a keychain read during
/// `init` — which on this ad-hoc-signed bundle is a system dialog in front of
/// the launch (Architecture/StoredSettings.md § Sealed settings). So the record sits with Helm's own state on disk, which is per
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
