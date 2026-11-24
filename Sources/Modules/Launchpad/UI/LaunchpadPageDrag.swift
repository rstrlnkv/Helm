import SwiftUI

/// Where the fingers hold the page, in points from its place. Its own object so that the 120 Hz of a swipe republishes this
/// and nothing else: the state's views do not re-run for it, only what reads `offset` (`PageDragOffset`).
@MainActor final class LaunchpadPageDrag: ObservableObject {
    @Published var offset: CGFloat = 0
}
