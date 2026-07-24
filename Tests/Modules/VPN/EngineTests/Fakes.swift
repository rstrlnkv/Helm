// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
@testable import Module_VPN_Engine

final class FakeRunner: VPNRunnerPort {
    var issued: [[String]] = []
    var listOutput: String = ""

    func run(_ args: [String]) -> String {
        issued.append(args)
        if args == ["--nc", "list"] { return listOutput }
        return ""
    }
}

final class FakeCreds: VPNCredentialsPort {
    var map: [String: VPNCredentials] = [:]
    func credentials(for name: String) -> VPNCredentials? { map[name] }
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
