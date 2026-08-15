import Foundation
import Module_Autopilot_Engine

/// A stand-in for the two folders `FileManager` is asked about.
///
/// The twin of the engine tests' file of the same name, and separate for the
/// only reason two test targets ever duplicate anything here: test plumbing is
/// shared through `HelmTestSupport`, which may reach `HelmRuntime` and no
/// module — so a stand-in for a *module's* port has nowhere else to live. Keep
/// the two in step; the engine's copy carries the paragraph on why the port can
/// answer nothing at all.
struct FakePresetFolders: PresetFolderPort {
    var paths: [PresetFolder: String]

    init(_ paths: [PresetFolder: String]) { self.paths = paths }

    init(home: String) {
        self.init([.desktop: home + "/Desktop", .downloads: home + "/Downloads"])
    }

    func path(of folder: PresetFolder) -> String? { paths[folder] }
}
