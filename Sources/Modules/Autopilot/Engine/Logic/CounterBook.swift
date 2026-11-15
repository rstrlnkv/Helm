import Foundation

/// What `{counter}` is for one sweep: the lowest number nobody in the folder
/// wears, handed out once and then marked used.
///
/// One book per pass (a sweep, a watcher batch, a dry run), shared by every
/// file in it. The folder is listed once and each pattern's used numbers are
/// parsed from that listing once, so a folder of a thousand files costs one
/// read and not a thousand, and two files of one pass cannot be given the same
/// number. `RuleRunner` and `PlannedDestination` both ask this and nothing
/// else, in the same order over the same listing, so the dry run shows the
/// numbers the sweep will give — as long as the folder is not changed between
/// the two; `FreeName` at the move is what stops a late arrival being
/// overwritten. A file the sweep skips (stamped, out of scope) takes no number
/// in the run and one in the dry run, which does not read stamps.
final class CounterBook {

    enum Answer: Equatable {
        case name(String)
        /// The pattern itself is not usable (`RenamePattern.apply` refused it).
        case unusable
        /// Every number from 1 to `RenamePattern.maxCounter` is worn.
        case exhausted
        /// The folder could not be listed. Not an empty folder: nothing is
        /// known about what is in it, so no number is a guess worth making.
        case unreadable
    }

    private struct Key: Hashable {
        let folder: String
        let template: String
        let ext: String
    }

    private let list: (String) throws -> [String]
    private var listings: [String: Result<[String], Error>] = [:]
    private var used: [Key: Set<Int>] = [:]

    init(list: @escaping (String) throws -> [String] = {
        try FileManager.default.contentsOfDirectory(atPath: $0)
    }) {
        self.list = list
    }

    /// The name this file gets in `folder`, `{counter}` being the lowest unworn
    /// number. A file already wearing a name the pattern describes comes back
    /// as it is, and a pattern without `{counter}` never reads the folder.
    func name(for pattern: String, facts: FileFacts, in folder: String) -> Answer {
        guard let first = RenamePattern.apply(pattern, to: facts, counter: 1) else {
            return .unusable
        }
        guard pattern.contains(RenamePattern.counterToken), first != facts.name else {
            return .name(first)
        }
        let names: [String]
        switch listing(folder) {
        case let .success(found): names = found
        case .failure: return .unreadable
        }
        let template = RenamePattern.resolving(pattern, facts)
        let ext = Self.fold((facts.name as NSString).pathExtension)
        let key = Key(folder: folder, template: template, ext: ext)
        var taken = used[key] ?? Self.numbers(wornBy: names, template: template, ext: ext)
        guard let number = (1...RenamePattern.maxCounter).first(where: { !taken.contains($0) }),
              let name = RenamePattern.apply(pattern, to: facts, counter: number) else {
            used[key] = taken
            return .exhausted
        }
        taken.insert(number)
        used[key] = taken
        return .name(name)
    }

    private func listing(_ folder: String) -> Result<[String], Error> {
        if let known = listings[folder] { return known }
        let read = Result { try list(folder) }
        listings[folder] = read
        return read
    }

    /// Case folded on both sides, as APFS holds names: `Invoice-001.pdf` wears
    /// `001` for `invoice-{counter}`. Only the files of the same extension are
    /// asked, because the extension is the file's own and `a-001.txt` does not
    /// stand in the way of `a-001.pdf`.
    private static func numbers(wornBy names: [String], template: String, ext: String) -> Set<Int> {
        let shape = RenameShape(resolved: template, ignoringCase: true)
        var found: Set<Int> = []
        for name in names where fold((name as NSString).pathExtension) == ext {
            found.formUnion(shape.numbers(in: (name as NSString).deletingPathExtension))
        }
        return found
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: .caseInsensitive, locale: nil)
    }
}
