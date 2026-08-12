import Foundation

/// "Keep the Mac awake while this app runs" — optionally narrowed to the
/// situation the user actually cares about: at the desk (external display) or
/// plugged in. Both qualifiers on one rule mean both must hold.
public struct AppTrigger: Codable, Equatable, Sendable, Identifiable {
    public var id: String { bundleID }
    public var bundleID: String
    public var needsExternalDisplay: Bool
    public var needsPower: Bool

    public init(bundleID: String, needsExternalDisplay: Bool = false, needsPower: Bool = false) {
        self.bundleID = bundleID
        self.needsExternalDisplay = needsExternalDisplay
        self.needsPower = needsPower
    }

    /// The four states the two flags can express, named the way the row reads.
    /// One control instead of two switches: "only with a display" and "only on
    /// power" together mean both must hold, which two independent toggles do
    /// not say out loud.
    public enum Condition: String, CaseIterable, Sendable {
        case always, externalDisplay, power, displayAndPower
    }

    public var condition: Condition {
        switch (needsExternalDisplay, needsPower) {
        case (false, false): .always
        case (true, false): .externalDisplay
        case (false, true): .power
        case (true, true): .displayAndPower
        }
    }

    public mutating func set(_ condition: Condition) {
        needsExternalDisplay = condition == .externalDisplay || condition == .displayAndPower
        needsPower = condition == .power || condition == .displayAndPower
    }

    func isSatisfied(running: Set<String>, externalDisplay: Bool, onPower: Bool) -> Bool {
        guard running.contains(bundleID) else { return false }
        if needsExternalDisplay && !externalDisplay { return false }
        if needsPower && !onPower { return false }
        return true
    }
}

enum AppTriggerRules {
    static func isHolding(_ rules: [AppTrigger], running: Set<String>,
                          externalDisplay: Bool, onPower: Bool) -> Bool {
        !holding(rules, running: running, externalDisplay: externalDisplay,
                 onPower: onPower).isEmpty
    }

    /// **Which** rules are satisfied, not merely whether any is.
    ///
    /// The screen said «App» — the only rule type anybody actually uses, and
    /// the only one that could not say what it was talking about. A person with
    /// four apps in the list could not tell which of them was holding the Mac,
    /// on the screen whose whole job is to answer that.
    ///
    /// Bundle ids, not names: the ids are what the module stores and what it
    /// matched on, and turning one into a name is a Launch Services lookup that
    /// belongs on the screen doing the drawing. It keeps names off the wire and
    /// out of the log, which is the standing rule.
    static func holding(_ rules: [AppTrigger], running: Set<String>,
                        externalDisplay: Bool, onPower: Bool) -> [String] {
        rules.filter { $0.isSatisfied(running: running, externalDisplay: externalDisplay,
                                      onPower: onPower) }
             .map(\.bundleID)
    }

    static func encode(_ rules: [AppTrigger]) -> String {
        guard let data = try? JSONEncoder().encode(rules) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ raw: String) -> [AppTrigger] { readable(raw) ?? [] }

    /// The most rules this module will read, and the longest a bundle id may be.
    ///
    /// **The value is unbounded input read on every recompute.** It is one string
    /// in `~/Library/Preferences`, which any process running as this user can
    /// write, and `recompute()` runs from three observers — a display moving, the
    /// charger, an app launching. Measured on what a plist can hold: 4.7 MB of
    /// rules decodes to 50 001 of them at about 57 ms a recompute, and one bundle
    /// id can be a million characters long.
    ///
    /// Nobody reaches these numbers by choosing apps: the picker adds one at a
    /// time from a file dialog, and 256 characters is already far past
    /// `com.microsoft.VSCode`. Over either ceiling the value is **refused**, not
    /// truncated — silently keeping the first 200 is the one outcome nobody could
    /// see, a page drawing rules that hold nothing or a Mac held awake by rules
    /// the page does not draw. A refusal has a place to go: the banner
    /// (`KeepAwakeSettings.AppRulesReading.unreadable`).
    static let maxRules = 200
    static let maxBundleIDLength = 256
    /// Checked **before** anything is decoded, which is where the cost is: a
    /// refusal after `JSONDecoder` has already parsed 4.7 MB still pays the 57 ms
    /// on every event. 128 KB is comfortably above the worst legitimate file —
    /// `maxRules` rules whose ids are all `maxBundleIDLength` long encode to about
    /// 64 KB — and far below anything written to be expensive.
    static let maxEncodedBytes = 128 * 1024

    /// `nil` for a string that is not rules, told apart from `[]` — which is a
    /// legitimate thing for the file to say and means the person has chosen no
    /// apps. The two are the same answer to the module and a different thing to
    /// say about somebody's file.
    static func readable(_ raw: String) -> [AppTrigger]? {
        guard raw.utf8.count <= maxEncodedBytes,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([AppTrigger].self, from: data),
              decoded.count <= maxRules,
              decoded.allSatisfy({ $0.bundleID.count <= maxBundleIDLength })
        else { return nil }
        return deduplicated(decoded)
    }

    /// One rule per app, first one wins.
    ///
    /// `AppTrigger` is `Identifiable` on its bundle id and the settings page
    /// draws `ForEach(id: \.element.bundleID)`, whose behaviour with a repeated
    /// id SwiftUI's own documentation leaves undefined — in the list that
    /// carries a per-row condition menu and a remove button keyed on the index.
    /// Two writers produce duplicates without anybody using the picker: a
    /// hand-edited plist, and `migrating(from:)` over an `autoApps` array that
    /// nothing ever deduplicated.
    private static func deduplicated(_ rules: [AppTrigger]) -> [AppTrigger] {
        var seen = Set<String>()
        return rules.filter { seen.insert($0.bundleID).inserted }
    }

    /// Earlier versions stored a plain list of bundle ids. Those apps kept the
    /// Mac awake unconditionally, so that is what they migrate to.
    ///
    /// **The ceilings above guard one of the two readers, and the file chooses
    /// which reader it goes to.** This one mapped whatever it found and answered
    /// with all of it: 50 001 rules, ids a million characters long, on
    /// `recompute`'s path — which runs from three observers. And reaching it takes
    /// no cunning at all, because an absent or empty `autoAppRules` is exactly
    /// what an older file looks like: the whole ceiling was one missing key away
    /// from not existing.
    ///
    /// So `nil` here means the same as `nil` from `readable` — refused, not
    /// truncated, and the refusal has a place to go (`AppRulesReading.unreadable`,
    /// and the banner over the list).
    ///
    /// Both ceilings are checked before anything is built, for the reason
    /// `maxEncodedBytes` is checked before anything is decoded: the cost is the
    /// work, not the answer. The byte ceiling needs no check of its own here —
    /// `maxRules` ids of `maxBundleIDLength` are about 64 KB encoded, half of it —
    /// and `testTheTwoCheckedCeilingsKeepTheThirdOutOfReach` is what keeps that
    /// arithmetic true if any of the three moves.
    static func migrating(from bundleIDs: [String]) -> [AppTrigger]? {
        guard bundleIDs.count <= maxRules,
              bundleIDs.allSatisfy({ $0.count <= maxBundleIDLength })
        else { return nil }
        return deduplicated(bundleIDs.map { AppTrigger(bundleID: $0) })
    }
}
