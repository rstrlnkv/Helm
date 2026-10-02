# Hosts

`Sources/Modules/Hosts/` edits `/etc/hosts` and manages SSH keys, and both halves
are built around the same idea: the bytes are canonical and a parse is a reading
rather than a representation (`HostsFile.swift`, `HostsViewModel.swift`,
`KnownHostsFile.swift`: a parsed hosts file is a reading, and the known-hosts
document keeps every line byte-for-byte, its only edit dropping a line whole).

Privilege crosses one door, `HostsWrite.command(base64:)`: root gets the content
and never a staged path, base64 is the gate on root's AppleScript literal, and the
shell counts the decoded bytes before the redirect exists. Why each is so, and the
ceiling `HostsWrite.fits` makes legible, are on the doc comments of
`HostsWrite.swift`. Every Apply is one dialog, `PrivilegedOutcome` keeps "you
cancelled" and "the write failed" apart all the way to the screen, and a port
reporting success is believed by nothing but the read-back, compared by digest
(`HostsEngine.apply`'s doc comment gives why, `HexDigest.swift`).

There is no rule in `/etc/sudoers.d` for this module — of every module naming it,
only Keep Awake's is a rule of its own:

```bash
command grep -rln 'sudoers.d' Sources/ --include='*.swift' | command grep 'Modules/'
```

The keys tab holds the one secret this app has: it is taken `inout` and zeroed on
every path out, a failed spawn and the deadline included, and no `String` is made of
it inside `PTYProcess.swift`; the terminal's echo is switched off before the child
is spawned. The copies outside that file (the field's own `String`, the base64 in
the JSON on the wire) are accepted residuals, listed on the doc comment of
`Secret.swift`. `KeyGeneration.swift` never aims
`ssh-keygen` at a name already in the directory (`KeyGeneration.Refusal.nameTaken`).
