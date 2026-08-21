import Foundation
import HelmRuntime

/// What a disk scan that nobody watched is allowed to write down.
///
/// **The refusal is here and not in the descent, and that is the difference
/// between this module and the duplicate finder.** Duplicates refuses to walk
/// into `~/Library` at all, because nobody points a duplicate finder there on
/// purpose. Disk's whole answer is «where did the space go», and that question
/// cannot be answered with the largest folder on the volume left out — so
/// `DiskScanner(unattended:)` refuses only an application's own database, the
/// walk measures the Library, and the ring a person opens shows it.
///
/// What must not happen is the *journal* naming those paths. It is written at
/// 0600 and readable by any process running as this user, including ones macOS
/// refuses to let read `~/Library/Mail` — so an unattended scan that recorded
/// them would launder the Full Disk Access grant the person gave Helm into one
/// they gave nobody. Measured on the owner's machine on 2026-08-20: 12 items in
/// the disk journal, 1 of them under `~/Library`.
///
/// A scan somebody started still reports everything they asked about: this is
/// reached from `backgroundScan` alone. The distinction is unattended versus
/// asked-for, never `~/Library` versus everything else.
enum UnattendedAdvice {

    /// The journal's view of a finished unattended scan.
    ///
    /// **The totals are derived from what survived the gate**, in one place.
    /// Filtering the list and summing the original leaves a journal entry whose
    /// figure disagrees with its own list — and the figure is what a settings
    /// row draws and what `ScanNews` measures a banner against.
    ///
    /// - Parameter home: a parameter so the rule is a fact rather than something
    ///   that happens to be true of this Mac, the way `ScanRoot`'s own gate
    ///   takes one.
    static func report(of advice: [DiskAdvice],
                       home: String = ScanRoot.canonicalHome) -> ScanReport {
        let items = advice
            .filter { !ScanRoot.refusesDescentInHome(into: $0.path, home: home) }
            .map { ScanItem(path: $0.path, bytes: $0.bytes) }
        return ScanReport(bytes: items.reduce(0) { $0 + $1.bytes },
                          count: items.count, items: items)
    }
}
