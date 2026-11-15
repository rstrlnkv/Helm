# Permissions

`PermissionCheck.probeURLs` (`Sources/HelmRuntime/PermissionCheck.swift`) probes Full
Disk Access by reading protected files, one byte each (`canRead`). The doc comments
there hold the reasons: the probe is a read, since a write is refused even where access
is granted; every entry is a file, never a directory, since opening a directory throws
whatever the grant; and the entry that is on every Mac and gated by this grant alone, the
system-wide `TCC.db`, is asked first. The probe runs off the thread that draws:
`PermissionCheck.fullDiskAccess` hops through `offTheCooperativePool`, and the settings page, the panel and
`PermissionAudit` read it through the trackers or that call, never inline. What a declared permission stands behind
(`.fullDisk`, `.accessibility`, `.screenRecording` to a `PermissionNeed`, `.adminHelper` to none) is one mapping,
`PermissionSummary.need(for:)` in `Sources/HelmApp/PermissionSummary.swift`; the settings page and the panel both count
what is withheld through it.
