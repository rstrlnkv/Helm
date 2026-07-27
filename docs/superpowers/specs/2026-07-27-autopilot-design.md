# Autopilot — a folder that keeps itself in order

**Status:** design, awaiting approval
**Module id:** `autopilot` · category: Files · symbol: `location.north.circle`

Named for what it does, not what it is made of. "Rules" named the mechanism and
left the sidebar with an entry that could have belonged to any part of the app;
the folder still holds rules, and the module is the thing that keeps it on
course without hands on it — the instrument Helm is named after, one step
further along.

## What it is

Hazel's core, and only its core: a watched folder, a list of rules, and a file
that matches one gets acted on. Everything else Hazel does — duplicate finding,
app removal, trash cleanup — Helm already has as its own modules, and doing it
twice would be worse than not doing it.

Scope decisions taken before design (asked and answered):

- **The rule engine, not a preset.** A "Downloads autopilot" with no editor is a
  smaller thing to build and a smaller thing to own, but it is also a thing
  nobody can adapt. The engine is the feature.
- **Safe actions only.** Move, rename, tag, sort into subfolders, and Trash
  through the same gate as every other module. **No script action**, which is
  Hazel's most powerful one and the one Helm cannot responsibly ship: Helm is
  ad-hoc signed and unsandboxed, so a script action turns "a file appeared" into
  arbitrary code execution, and the rule that does it would sit in a plist any
  process on the machine can write.

## The model

```
Folder      path, depth, enabled, [Rule]      — order matters
Rule        name, enabled, match, [Condition], [Action]
Condition   field, comparison, value
Action      one of the five below
```

**First match wins.** A file is tested against the folder's rules top to bottom,
and the first rule whose conditions hold is the one that runs; the rest are
skipped for that file. This is Hazel's rule and it is the right one: it makes
the list readable as a decision, top to bottom, instead of as a set of
independent things that may or may not collide. Hazel then adds a "continue
matching" action to escape it — that is a second mechanism to explain, and it is
not in v1.

**`match` is all or any**, per rule. Nested condition groups are Hazel's answer
to the cases those two cannot express; they are also where a rule stops being
readable at a glance. Not in v1.

### Conditions

| field | comparisons | notes |
|---|---|---|
| name | is, contains, begins with, ends with | case-insensitive |
| extension | is one of | `pdf, png, zip` typed as a list |
| kind | is | image, document, archive, video, audio, folder — a fixed list from UTType, not extension guesswork |
| size | larger than, smaller than | MB |
| date added | older than, newer than | days |
| date modified | older than, newer than | days |
| downloaded from | contains | `kMDItemWhereFroms` — the condition that makes "everything Safari got from that one site" a rule |
| tag | is | Finder tag |

### Actions

| action | what it does |
|---|---|
| move to folder | one destination, chosen with the panel |
| sort into subfolder | by kind (`Images/`, `Documents/`…) or by date (`2026-07/`) |
| rename | pattern of name, extension, date, counter |
| add tag | Finder tag |
| move to Trash | through `UserFileScope.partition` **inside the engine** |

A rule carries one action in v1. Two actions in a row is a list to order and a
failure to report half-way through; one action per rule, with rules stacked, is
the same expressiveness with none of that.

## When it runs

Three triggers, because one is not enough:

1. **FSEvents** on each watched folder — a file appears, its rules run. This is
   the responsive path and the one people expect.
2. **A sweep on a timer**, hourly by default. Time conditions — "older than 30
   days" — become true with nothing happening, so nothing would ever wake the
   watcher up.
3. **Run now**, per folder, from the page.

Depth defaults to 1: the top level of the watched folder only. Recursion is a
setting per folder, not per rule, because a rule that reaches into subfolders on
its own is how a tidy Downloads folder becomes a rearranged project tree.

## What must not happen

**A file must not be acted on twice.** A rule that moves a file into a subfolder
of the folder it is watching will see it again on the next sweep, and again
after that. Each acted-on file gets an extended attribute —
`com.helm.autopilot.stamp` — carrying the rule's id and when it ran; a file already
stamped by that rule is skipped. The stamp travels with the file because xattrs
survive a move within a volume, which is exactly the case that matters.

**A rule must not be able to reach outside the user's files.** A watched folder
has to pass `UserFileScope`, and so does every destination. `/System`, a volume
root and the home directory itself are refused at the point the folder is
chosen, not at the point a file is moved.

**Nothing runs before it has been shown.** A new rule is off, and the page
offers a dry run: the files in the folder right now that would match, and what
would happen to each. The rule can only be switched on from that screen. This is
the same discipline as the duplicate basket — the engine decides, the person
confirms — applied one level earlier, because a rule is a decision made once and
executed forever.

**The log carries no names.** Paths through `Redact.path`, counts and outcomes
free, as everywhere else.

## Structure

```
Sources/Modules/Autopilot/
  Engine/
    Logic/                        pure, tests first
      FileFacts.swift             what a rule is allowed to know about a file
      RuleCondition.swift         the condition and its comparison
      RuleMatcher.swift           facts + rule → does it match
      RuleAction.swift            the action and its parameters
      RulePlan.swift              facts + [Rule] → the one thing to do, or nothing
      RenamePattern.swift         pattern + facts → new name
      SortBucket.swift            facts + scheme → subfolder name
    AutopilotEngine.swift             transport, the last word on Trash
    FolderWatcher.swift           FSEvents
    RuleRunner.swift              plan → filesystem, one file at a time
    RuleStamp.swift               the xattr
  UI/
    AutopilotDescriptor.swift
    AutopilotSettingsPage.swift       folders, their rules, run now
    RuleEditor.swift              conditions, action, dry run
    AutopilotViewModel.swift
    AutopilotStrings.swift
```

`RulePlan` is the piece that has to be right: given a file's facts and a
folder's ordered rules, it returns the single action to perform, or nothing. It
touches no filesystem, so every ordering question — first match, disabled rules,
a rule whose conditions are empty — is a unit test.

## Build order

Each step ends green and useful on its own.

1. `FileFacts`, `RuleCondition`, `RuleMatcher` — matching, tested, no IO.
2. `RulePlan` — ordering and first-match, tested.
3. `RenamePattern`, `SortBucket` — the two actions that compute a name, tested.
4. `RuleStamp` — read/write/skip, tested against a temp directory.
5. `RuleRunner` + `RulesEngine` — the filesystem, the Trash gate, the log.
6. `FolderWatcher` — FSEvents and the hourly sweep.
7. The page: folders, rules, dry run, run now.
8. The rule editor.
9. Eight languages, the changelog, a dev release.

## Deliberately not in v1

Nested condition groups · multiple actions per rule · "continue matching" ·
scripts · AppleScript · unarchiving · uploading · custom tokens in rename
patterns · sync of rules between machines · rules on the contents of a matched
folder (Hazel's "run rules on folder contents").

Each is a real Hazel feature and each is a second mechanism to explain. If the
engine is used and the missing piece is felt, it goes in then, with a reason.
