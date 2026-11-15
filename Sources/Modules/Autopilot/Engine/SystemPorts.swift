import Foundation
import HelmRuntime

/// The production answer: whatever `FileManager` says, resolved for this user.
public struct SystemPresetFolders: PresetFolderPort {
    public init() {}

    public func path(of folder: PresetFolder) -> String? {
        // **A suite run has no preset folders.** This is the question every site
        // in the tree that resolves a folder of somebody's own has to ask: a
        // page built in a test would otherwise hold their real Desktop and
        // Downloads, offer five rules over them, and be one press away from
        // watching them. A test that wants an offer plants the paths through
        // the port, which is what the port is for.
        guard !TestProcess.isRunning else { return nil }
        let directory: FileManager.SearchPathDirectory = switch folder {
        case .desktop: .desktopDirectory
        case .downloads: .downloadsDirectory
        }
        return try? FileManager.default
            .url(for: directory, in: .userDomainMask, appropriateFor: nil, create: false)
            .path
    }
}

struct SystemUndoFiles: UndoFiles {
    func identity(of path: String) -> PathCanonical.FileIdentity? {
        PathCanonical.identity(of: path)
    }

    func ancestry(of path: String) -> PathCanonical.AncestryIdentity? {
        PathCanonical.ancestryIdentity(of: path)
    }

    func directoryExists(_ path: String) -> Bool {
        var directory: ObjCBool = false
        let there = FileManager.default.fileExists(atPath: path, isDirectory: &directory)
        return there && directory.boolValue
    }

    func move(_ from: String, to: String) throws {
        try FileManager.default.moveItem(atPath: from, toPath: to)
    }

    func tags(of path: String) throws -> [String] {
        try URL(fileURLWithPath: path).resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
    }

    func setTags(_ tags: [String], on path: String) throws {
        var values = URLResourceValues()
        values.tagNames = tags
        var url = URL(fileURLWithPath: path)
        try url.setResourceValues(values)
    }

    func stamp(_ path: String, rule: String, key: Data) -> Bool {
        RuleStamp(key: key).stamp(path, by: rule)
    }
}
