import Foundation
@testable import Module_Autopilot_Engine

/// A stand-in for the two folders `FileManager` is asked about.
///
/// The twin of the engine tests' file of the same name: `HelmTestSupport` may
/// reach no module, so a stand-in for a *module's* port has nowhere shared to
/// live. Keep the two in step; the engine's copy says why the port can answer
/// nothing at all.
struct FakePresetFolders: PresetFolderPort {
    var paths: [PresetFolder: String]

    init(_ paths: [PresetFolder: String]) { self.paths = paths }

    init(home: String) {
        self.init([.desktop: home + "/Desktop", .downloads: home + "/Downloads"])
    }

    func path(of folder: PresetFolder) -> String? { paths[folder] }
}
