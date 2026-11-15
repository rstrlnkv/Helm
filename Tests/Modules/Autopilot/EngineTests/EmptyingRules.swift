import Foundation
@testable import Module_Autopilot_Engine

/// A rule that empties the folder — the reviewer's demonstration, shrunk to one
/// file. `.trash` rather than `.move` because what it did is then visible as an
/// absence and nothing else.
func emptyingRules(in root: URL, id: String = "planted") -> [WatchedFolder] {
    [WatchedFolder(id: id, path: root.path, enabled: true, rules: [
        Rule(id: "r", name: "take it", enabled: true, match: .all,
             conditions: [.fileExtension(["pdf"])], action: .trash),
    ], depth: 1)]
}
