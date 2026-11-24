import SwiftUI

/// What the page needs of a lift, and republishes only when it changes: the tile carried, and the tile a release would drop
/// it onto. The pointer's place is not here (`LaunchpadLiftPoint`).
struct LaunchpadLiftView: Equatable {
    let entry: LaunchpadEntry
    var onto: String?
}

/// Where the pointer is while a tile is carried, in the window's coordinates (top left), at the event rate. Its own object,
/// as the page's drag is: only the overlay that reads it runs again.
@MainActor final class LaunchpadLiftPoint: ObservableObject {
    @Published var point = CGPoint.zero
    /// From the pointer to the middle of the carried tile's cell, taken when it was lifted.
    var grab = CGPoint.zero
}
