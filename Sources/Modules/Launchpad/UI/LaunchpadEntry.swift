import Foundation
import Module_Launchpad_Engine

/// One tile of the window: an app, or a folder with the apps it holds as the snapshot resolved them; or the gap a lifted
/// tile leaves, which draws nothing and keeps one identity for as long as it is shown.
enum LaunchpadEntry: Equatable, Identifiable {
    case app(CatalogApp)
    /// `large`: drawn as a 2×2 block (the folder's own setting).
    case folder(id: UUID, name: String, apps: [CatalogApp], large: Bool = false)
    case gap

    /// The gap's id: a space, which no bundle id can hold, so that no app's id is it.
    static let gapID = " gap"

    var id: String {
        switch self {
        case .app(let app): app.id
        case .folder(let id, _, _, _): id.uuidString
        case .gap: Self.gapID
        }
    }

    var isLarge: Bool {
        if case .folder(_, _, _, let large) = self { large } else { false }
    }
}
