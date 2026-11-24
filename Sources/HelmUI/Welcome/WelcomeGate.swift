// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Whether this installation has seen the tour.
///
/// A revision, not a flag: a fresh install and an upgrade from before the tour
/// both answer yes exactly once, so people upgrading learn about modules that
/// arrived without a word. A later tour bumps `revision` deliberately.
public enum WelcomeGate {
    /// The key in the app's own namespace. Read and written in one place.
    public static let storeKey = "welcomeSeenRevision"
    public static let revision = 1

    public static func shouldShow(seenRevision: Int) -> Bool {
        seenRevision < revision
    }
}
