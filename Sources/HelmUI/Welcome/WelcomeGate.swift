// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Whether this installation has seen the tour.
///
/// A revision, not a flag. Nobody holds this key at 0.8.0, so a fresh install
/// and an upgrade both answer yes exactly once — which is the intent: people
/// upgrading have had Autopilot and Duplicates arrive without ever being told
/// what they are. A later tour bumps `revision` deliberately, or does not run.
public enum WelcomeGate {
    /// The key in the app's own namespace. Read and written in one place.
    public static let storeKey = "welcomeSeenRevision"
    public static let revision = 1

    public static func shouldShow(seenRevision: Int) -> Bool {
        seenRevision < revision
    }
}
