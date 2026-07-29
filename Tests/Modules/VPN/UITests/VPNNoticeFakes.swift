// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
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
    var posted: [(title: String, body: String)] { lock.withLock { _posted } }

    func authorizationState() async -> NoticeAuthorization { lock.withLock { _state } }

    func requestAuthorization() async -> NoticeAuthorization {
        lock.withLock { _requests += 1; return _state }
    }

    func post(title: String, body: String) async {
        lock.withLock { _posted.append((title, body)) }
    }
}
