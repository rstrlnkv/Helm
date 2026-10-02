# Permissions

`PermissionCheck.probeURLs` (`Sources/HelmRuntime/PermissionCheck.swift`) probes Full
Disk Access by reading protected files, one byte each (`canRead`). The doc comments
there hold the reasons: the probe is a read, since a write is refused even where access
is granted; every entry is a file, never a directory, since opening a directory throws
whatever the grant; and the entry that is on every Mac and gated by this grant alone, the
system-wide `TCC.db`, is asked first.
