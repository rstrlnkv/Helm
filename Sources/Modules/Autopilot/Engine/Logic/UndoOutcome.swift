import Foundation

/// What putting one action back came to.
///
/// A value rather than a `Bool`, for the reason `RuleOutcome` is one: a rule
/// that could not put three files back has to be able to say which three and
/// why, and a report built from flags can only say "some of them".
public enum UndoOutcome: Codable, Equatable, Sendable {
    /// The file is back, at this path — which is not always the path it came
    /// from: a name taken in the meantime is numbered, the way an arrival is,
    /// and the report names what it settled on.
    ///
    /// `stamped` is whether the mark went back on with it. A file put back
    /// without one is a file the same rule takes again on the next sweep, so
    /// this is the difference between a return and a return that undoes itself
    /// within the hour — reported rather than shrugged off, because there is
    /// something the person can do about it.
    case restored(to: String, stamped: Bool)
    case refused(UndoRefusal)
    case failed(String)
}

/// Why an action was not put back.
///
/// Ten of them, and each is a different thing to tell somebody: waiting helps
/// with none, but "the folder you took it from is gone" and "that is not the
/// file any more" ask for different next moves. The `rawValue` is storage and
/// nothing else — every one of these is spoken in the reader's language from
/// the day it ships, which is the lesson `ARefusalSpeaksTheLanguageTests` was
/// written for after a row read «refused changedSinceCheck» in eight languages.
public enum UndoRefusal: String, Codable, CaseIterable, Equatable, Sendable {
    /// Nothing is at the path the record says the file went to.
    case notThere
    /// Something is, and it is not the file Helm moved.
    case notTheSameFile
    /// The folder it came from is not there any more. **Not created**: a person
    /// who deleted that folder asked for their file back, not for the folder.
    case originGone
    /// Either end of the return is somewhere no rule may reach. A record is
    /// data in a plist anything can write, so a forged one is a ready-made
    /// instruction to move a file — and this is the gate that refuses it.
    case originOutOfScope
    /// Where one of the two ends leads changed between the check and the move.
    case changedSinceCheck
    /// The old name is taken, and this was a rename — whose subject *is* the
    /// name, so numbering it would put the file back under a name nobody gave
    /// it. A move numbers instead.
    case nameTaken
    /// The file is not in the Trash any more. One phrasing for two facts,
    /// because from here emptying the Trash and taking the file out by hand are
    /// the same fact.
    case trashEmptied
    /// Already put back — or, for a tag, already gone.
    case alreadyUndone
    /// The history itself is not Helm's. Nothing is put back until it is
    /// cleared, because every field a return acts on comes out of it.
    case historyRefused
    /// The record does not say who the file was, so there is no way to check
    /// that the thing at that path is the thing Helm acted on. Every record
    /// written before this build is in this state, and so is every refusal and
    /// failure — they moved nothing, so there is nothing to identify.
    case noIdentity
}

/// What a whole return came to: one line per action, in the order they were
/// tried.
///
/// **The counts are read off the lines rather than kept beside them.** A run
/// put back one at a time is not atomic — the fourth file can refuse after
/// three have moved — and a report carrying its own tallies is a report that
/// can say "3 restored" about a batch where two of them failed.
public struct UndoReport: Codable, Equatable, Sendable {
    public struct Line: Codable, Equatable, Sendable, Identifiable {
        /// The record's own id, so the page can find the row this is about.
        public let id: String
        public let file: String
        public let outcome: UndoOutcome

        public init(id: String, file: String, outcome: UndoOutcome) {
            self.id = id
            self.file = file
            self.outcome = outcome
        }

        public var restored: Bool {
            if case .restored = outcome { return true }
            return false
        }

        /// The name it settled on when that is not the name it had — the one
        /// thing a successful line still has to say out loud.
        public var landedAs: String? {
            guard case let .restored(to: path, stamped: _) = outcome else { return nil }
            let name = (path as NSString).lastPathComponent
            return name == file ? nil : name
        }

        /// Whether the rule may take this file again, because the mark that
        /// stops it did not stick.
        public var unmarked: Bool {
            if case let .restored(to: _, stamped: stamped) = outcome { return !stamped }
            return false
        }
    }

    public let lines: [Line]

    public init(lines: [Line]) { self.lines = lines }

    public var restored: [Line] { lines.filter(\.restored) }
    public var notPutBack: [Line] { lines.filter { !$0.restored } }
    public var unmarked: [Line] { lines.filter(\.unmarked) }
}
