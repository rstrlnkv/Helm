# Duplicates

`Sources/Modules/Duplicates/` decides which of several identical files is the extra
one, and that decision is a belief rather than a fact the disk holds. The two
beliefs, `byPlace` (the default) and `byDate`, are `KeepPolicy.swift`; one ladder
answers both what stays and why (its doc comment, read by `SurvivingCopy.swift`).

A group's size is what `CloneShare.reclaimable` (`Sources/HelmRuntime/CloneShare.swift`)
says removing it returns, not the sum of its files.

Acting on a finding re-reads the pair: `DuplicateVerification` is its own phase
beside the removal. `DuplicateVerification.Batch` memoises the survivor's reading
only, for the life of one press; the copy about to stop existing is read from disk
in full every time.

The unattended walk is narrower than the watched one: it asks
`ScanRoot.refusesDescentInHome` of every directory it meets, so the `~/Library`
subtrees macOS guards with TCC stay out of the 0600 journal
(`DuplicateScanner`'s `unattended`).
