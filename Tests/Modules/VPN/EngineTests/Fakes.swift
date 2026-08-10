// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
@testable import Module_VPN_Engine

final class FakeRunner: VPNRunnerPort {
    var issued: [[String]] = []
    var listOutput: String = ""
    /// What `start` and `stop` answer.
    ///
    /// It was hard-coded to `""`, which is what the real tool prints when it
    /// **succeeded** — so «scutil refused» was a state no test could write
    /// down, whatever anybody wrote, and none did. The tool reports failure by
    /// printing a line and exiting 0 (`No service`), and both call sites threw
    /// that line away for as long as this fake could not produce one.
    var reply: String = ""

    func run(_ args: [String]) -> String {
        issued.append(args)
        if args == ["--nc", "list"] { return listOutput }
        return reply
    }
}

final class FakeCreds: VPNCredentialsPort {
    var map: [String: VPNCredentials] = [:]
    func credentials(for name: String) -> VPNCredentials? { map[name] }
}

/// Records the observer's lifetime as well as its callback: an observer a
/// module starts has to stop, and "did it stop" is the assertion that catches
/// the callback landing on a freed engine.
final class FakeNetwork: NetworkWatchPort {
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var onChange: (@Sendable () -> Void)?

    func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        starts += 1
        self.onChange = onChange
    }
    func stopObserving() {
        stops += 1
        onChange = nil
    }
    /// Only fires while something is watching, like the real store.
    func fire() { onChange?() }
}

final class FakeApps: AppObserverPort {
    var bundleIDs: Set<String> = []
    private(set) var onChange: (@Sendable () -> Void)?

    func runningBundleIDs() -> Set<String> { bundleIDs }
    func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }
    func fire() { onChange?() }
}
