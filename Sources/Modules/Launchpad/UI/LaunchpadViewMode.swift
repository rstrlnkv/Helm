import HelmRuntime

/// What the window shows: the person's arrangement, or every app in the block of its category.
///
/// **Not sealed**, as the grid keys are not: it steers nothing unattended, and a forged value can only pick one of two views.
/// A key that is missing or any other value reads as `apps`. Read when the model is made and when a window is about to
/// open, written only through the model; never in a SwiftUI initial value.
enum LaunchpadViewMode: String, Equatable, Sendable {
    case apps, categories

    /// Deployed stored data: this name never moves.
    static let key = "view.mode"

    static func read(from store: NamespacedStore) -> LaunchpadViewMode {
        LaunchpadViewMode(rawValue: store.string(key, default: "")) ?? .apps
    }
}
