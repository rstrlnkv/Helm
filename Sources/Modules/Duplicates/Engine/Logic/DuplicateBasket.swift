import Foundation
import HelmRuntime

/// What the marks on the screen are worth, and what a press on them asks for.
///
/// **It sits beside `KeptCopies` on purpose.** This module's recurring defect is
/// two arithmetics about one basket — the bar quoting 300 MB above the list and
/// the banner 321 MB below it about the same two files — and both times the two
/// spellings were a page's and an engine's. The page's half is here now, in the
/// engine's own target, so the fold the bar shows, the plans the press sends and
/// the gate the batch is read against are one file apart rather than one target
/// apart.
///
/// Nothing here reads a disk or holds any state: it is the group list and the
/// marks, and the same inputs always give the same answer.
public enum DuplicateBasket {

    /// The extras of one group that Helm may actually take.
    ///
    /// The first copy is the one that stays — the invariant the whole page rests
    /// on — and of the rest, `UserFileScope` is what decides. Read both by the
    /// figure above the list and by the press underneath it, because a total and
    /// the marks it promises must not be two answers to «which copies can go»:
    /// pointed at `/`, at `/Library` or at `/opt`, the walk turns up copies the
    /// gate refuses, and a total counting those offers space no press can
    /// reclaim.
    public static func removableExtras(of group: DuplicateGroup) -> [String] {
        group.paths.dropFirst().filter(UserFileScope.isRemovable)
    }

    /// What emptying the basket would free.
    ///
    /// **Not the sum of the ticked copies' sizes.** A clone shares its blocks
    /// with the copy it was made from, and in this module that copy is usually
    /// one that stays — so its removal returns nothing, and adding the sizes up
    /// promised exactly double on the case Finder's own Duplicate command
    /// creates.
    public static func worth(marking marked: [String], in groups: [DuplicateGroup]) -> Int {
        DuplicateGroup.reclaimable(marking: Set(marked), in: groups)
    }

    /// One copy's own figure. A group's size is the copy that stays, so quoting
    /// it against a path promised a clone's nothing for a real file, or the
    /// reverse — the basket bar and the menu under it both ask this.
    public static func bytes(of path: String, in groups: [DuplicateGroup]) -> Int {
        groups.lazy.compactMap { group in
            group.copies.first { $0.path == path }
        }.first?.bytes ?? 0
    }

    /// What acting on the whole screen would free.
    ///
    /// Through `DuplicateGroup.reclaimable`, which is the same fold the basket
    /// bar and the confirmation use and the same slate `HelmTrash` opens for the
    /// batch — so the line above the list, the bar under it and the banner after
    /// the press are one arithmetic (ARCHITECTURE.md § What a copy actually
    /// costs).
    public static func wasted(in groups: [DuplicateGroup]) -> Int {
        DuplicateGroup.reclaimable(marking: Set(groups.flatMap(removableExtras)), in: groups)
    }

    /// What one press of «Move to the Trash» asks for: the copies that go, each
    /// paired with the copy it duplicates, and every copy that stays.
    ///
    /// A group's first copy is the survivor, so it is never in a plan; a marked
    /// path whose group has gone is dropped rather than sent unpaired, because
    /// unpaired is the one shape the engine cannot re-read before it moves
    /// anything.
    ///
    /// **The second list is the part that is easy to leave out.** What a removal
    /// frees is arithmetic over clone families, and a family is held by *any*
    /// copy of it that is not going — an extra the person left unticked exactly
    /// as much as a survivor. The engine cannot recover that from the disk:
    /// there is no reverse lookup from a family to its members (`HelmTrash`), so
    /// it has to be told, and the telling starts here.
    public static func removal(marking marked: [String], in groups: [DuplicateGroup])
    -> (plans: [DuplicatePlan], staying: [String]) {
        let chosen = Set(marked)
        let plans: [DuplicatePlan] = groups.flatMap { group -> [DuplicatePlan] in
            guard let survivor = group.copies.first?.path else { return [] }
            return group.copies.dropFirst()
                .filter { chosen.contains($0.path) }
                .map { DuplicatePlan(remove: $0.path, keep: survivor) }
        }
        let going = Set(plans.map(\.remove))
        return (plans, groups.flatMap(\.paths).filter { !going.contains($0) })
    }
}
