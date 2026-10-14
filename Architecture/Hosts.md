# Hosts

`Sources/Modules/Hosts/` manages the SSH config, the known hosts and the SSH keys,
and the first two are built around the same idea: the bytes are canonical and a
parse is a reading rather than a representation (`SSHConfigFile.swift`,
`HostsViewModel.swift`, `KnownHostsFile.swift`: the config's text is what is edited
and written, and the known-hosts document keeps every line byte-for-byte, its only
edit dropping a line whole).

The module asks root for nothing, and `NoDoorToRootInHostsTests` holds it. The two
files it rewrites, the config and the known hosts, are the person's own: each write is
gated by `SSHFileScope.swift` and believed by nothing but the read-back
(`HostsEngine.applySSH`'s doc comment gives why). A key's mode, the directory's mode
and a new key are written without that gate; a payload names a key by its bare name,
never by a path.

The keys tab holds the one secret this app has: it is taken `inout` and zeroed on
every path out, a failed spawn and the deadline included, and no `String` is made of
it inside `PTYProcess.swift`; the terminal's echo is switched off before the child
is spawned. The copies outside that file (the field's own `String`, the base64 in
the JSON on the wire) are accepted residuals, listed on the doc comment of
`Secret.swift`. `KeyGeneration.swift` never aims
`ssh-keygen` at a name already in the directory (`KeyGeneration.Refusal.nameTaken`).
