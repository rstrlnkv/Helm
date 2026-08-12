// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmRuntime
@testable import Module_VPN_Engine

/// Stands in for macOS's notification centre, which no test may touch: the real
/// one raises `bundleProxyForCurrentProcess is nil` outside an app bundle and
/// ends the whole run.
///
/// Locked rather than actor-isolated because the banner is posted from a
/// detached task while the test reads the result on the main actor.
final class FakeAutomationNotice: AutomationNoticePort, @unchecked Sendable {
    private let lock = NSLock()
    private var _state: NoticeAuthorization
    private var _requests = 0
    private var _posted: [(title: String, body: String)] = []

    init(state: NoticeAuthorization = .authorized) { _state = state }

    /// How many times the person was actually prompted. macOS shows that
    /// prompt once ever, so this number is the whole point of `prepare`.
    var requests: Int { lock.withLock { _requests } }
    /// What the person was actually shown — see `post`.
    var posted: [(title: String, body: String)] { lock.withLock { _posted } }

    /// What the mode is judged against at the moment a rule fires. Settable so
    /// a test can revoke the permission behind the app's back, which is the
    /// only way System Settings ever does it.
    var state: NoticeAuthorization {
        get { lock.withLock { _state } }
        set { lock.withLock { _state = newValue } }
    }

    func authorizationState() async -> NoticeAuthorization { lock.withLock { _state } }

    func requestAuthorization() async -> NoticeAuthorization {
        lock.withLock { _requests += 1; return _state }
    }

    /// A banner posted without the permission is dropped by macOS and nobody
    /// sees it, so this records what arrived rather than what was attempted.
    /// Recording the attempt would let "the person was told" pass on a firing
    /// that went nowhere — which is the whole of the defect these tests guard.
    func post(title: String, body: String) async {
        lock.withLock {
            guard _state == .authorized else { return }
            _posted.append((title, body))
        }
    }
}
