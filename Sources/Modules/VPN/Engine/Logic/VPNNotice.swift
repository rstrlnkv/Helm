// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// How loudly the module says that a rule fired.
///
/// The ring spins in all three: that is feedback that the app did something,
/// not a notification, and switching it off would leave the quietest mode with
/// no way to tell an automation from a tunnel that simply changed.
public enum VPNNotice: String, CaseIterable, Codable, Sendable {
    case silent, menuBar, system

    public var showsMenuBarName: Bool { self == .menuBar }
    public var postsBanner: Bool { self == .system }

    /// What actually happens, given whether macOS let us post banners.
    ///
    /// A refused banner becomes the label, never silence: the person chose to
    /// be told loudly, and the one outcome the app must not produce is quietly
    /// not telling them. The settings row says the same thing in words.
    public func effective(bannerAuthorized: Bool) -> VPNNotice {
        self == .system && !bannerAuthorized ? .menuBar : self
    }
}
