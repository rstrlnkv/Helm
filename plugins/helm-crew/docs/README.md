# Helm's crew

Fourteen agents, each a role in the release loop. Models are chosen per role,
not per prestige: judgment-heavy roles run on opus, checklist-driven roles on
sonnet — the judgment there lives in the checklist — and one locator on haiku,
where being wrong costs one more question.

| Agent | Model | Writes? | Why this model |
|---|---|---|---|
| helm-architect | opus | no (+Skill) | design trade-offs; invokes `superpowers:brainstorming` |
| helm-critic | opus | no | product judgment, argues against the roadmap |
| helm-engineer | opus | yes (+Skill) | production code; `test-driven-development`, `systematic-debugging` |
| helm-tester | opus | tests only (+Skill) | adversarial inputs are judgment; race-proof assertions |
| helm-security | opus | no (probes in scratchpad) | a missed finding is the expensive kind |
| helm-localizer | opus | no (+Skill) | eight languages of register and idiom; `writing-clearly-and-concisely` |
| helm-ui-designer | opus | no | pixel judgment, measured with `Scripts/design` |
| helm-ux-designer | opus | no | flow critique against the built app |
| helm-innovator | opus | no | competitor study, method extraction |
| helm-a11y | sonnet | no | label/contrast checklist. **Not haiku**: a missed label is somebody unable to use the app |
| helm-performance | sonnet | benchmarks only | measures and reports; the engineer applies the fix |
| helm-release | sonnet | plist+shell (+Skill) | fixed checklist; `verification-before-completion` |
| helm-scribe | sonnet | yes (+Skill) | docs upkeep; `writing-clearly-and-concisely` |
| helm-locator | haiku | no | file:line answers; the one role where a wrong answer costs a re-ask |

Read-only reviewers stay read-only on purpose: findings flow to helm-engineer,
which keeps one writer per change and reviews honest. They all have `Bash`,
because measuring beats reasoning — and `Bash` can write, so each of their
briefs says plainly that it must not: no redirect into a tracked file, no
`sed -i`, no committing. Scratch work goes to the scratchpad and is deleted
before they answer.

The three roles that do write are scoped: helm-engineer to production code,
helm-tester to `Tests/`, helm-performance to benchmarks under `Tests/` behind
`HELM_BENCH=1`, helm-release to version numbers and release artefacts, and
helm-scribe to documentation.

## Dispatching them

**Never run helm-tester and helm-security on the same module at the same time.**
Dispatched together on Autopilot they independently found the same three bugs
and spent about 300k tokens doing it. Tester first — a failing test is the
cheapest form of a finding, being reproducible and permanent — then security,
with the tester's report in hand, looking for the ground tests cannot cover:
TCC reach, symlinks, what a hostile plist can plant, what the log leaks.

Use helm-locator before anything that spans files. It is there so the expensive
agents start from a map instead of building one.

## Loading them

These live in a plugin because a bare `.claude/agents/` directory is not picked
up everywhere Claude Code runs — in one session the whole crew was invisible and
the work went through `general-purpose` with the briefs pasted in by hand, which
works and wastes the model selection. Install once:

```
/plugin marketplace add ~/Documents/Claude/Helm
/plugin install helm-crew@helm
```

`.claude/agents/` is kept in step with `plugins/helm-crew/agents/` for the
environments that do read it.

## Command line, and why each is a capability

All five are installed. These agents shell out, so a missing tool is a missing
method rather than an inconvenience:

- `swiftlint` — engineer/tester: mechanical findings stop reaching review.
  Configured in `.swiftlint.yml` to report signal: 1004 findings became 349,
  because a rule that is always wrong here teaches everyone to ignore the run.
- `xcbeautify` — release/tester: readable build and test logs.
- `periphery` — architect: dead code across the package.
- `hyperfine` — performance: honest before/after timing instead of one run.
- `create-dmg` — release: styled DMGs with a background and an /Applications alias.

## Claude-side

- `superpowers` TDD and systematic-debugging: engineer and tester invoke them.
- `elements-of-style` (`writing-clearly-and-concisely`): scribe and localizer.
- The screenshot harness is *not* a plugin and is not committed. Designers add
  the `HELM_DEBUG_SHOT` hook to `AppDelegate`, shoot, and take it out again —
  `grep -r HELM_DEBUG Sources/` must be clean before any commit.
