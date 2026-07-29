// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Where the tour is and what its buttons may do.
///
/// It cannot close the window: closing is the window's business, and a flow
/// that could do it could not be asked what it would do without one. `next()`
/// at the end is therefore a no-op rather than a dismissal — the view reads
/// `isLastStep` and calls the window's own close.
public struct WelcomeFlow: Equatable, Sendable {
    public let stepCount: Int
    public private(set) var step: Int = 0

    public init(stepCount: Int) {
        self.stepCount = max(0, stepCount)
    }

    public var canGoBack: Bool { step > 0 }
    /// True for an empty tour as well, so a window with no steps still offers
    /// a way out that is not only Skip.
    public var isLastStep: Bool { step >= stepCount - 1 }

    public mutating func next() {
        guard !isLastStep else { return }
        step += 1
    }

    public mutating func back() {
        guard canGoBack else { return }
        step -= 1
    }
}
