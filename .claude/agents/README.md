# Helm's crew

Thirteen agents, each a role in the release loop. Models are chosen per role,
not per prestige: judgment-heavy roles run on opus, checklist-driven roles on
sonnet — the judgment there lives in the checklist.

| Agent | Model | Writes? | Why this model |
|---|---|---|---|
| helm-architect | opus | no (+Skill) | design trade-offs; invokes `superpowers:brainstorming` |
| helm-critic | opus | no | product judgment, argues against the roadmap |
| helm-engineer | opus | yes (+Skill) | production code; `test-driven-development`, `systematic-debugging` |
| helm-tester | opus | tests only (+Skill) | adversarial inputs are judgment; race-proof assertions |
| helm-security | opus | no | a missed finding is the expensive kind |
| helm-localizer | opus | no | eight languages of register and idiom |
| helm-ui-designer | opus | no | pixel judgment (drew the flag set) |
| helm-ux-designer | opus | no | flow critique |
| helm-innovator | opus | no | competitor study, method extraction |
| helm-a11y | sonnet | no | label/contrast checklist, measured by scripts |
| helm-performance | sonnet | no | measures and reports; the engineer applies |
| helm-release | sonnet | plist+shell | fixed checklist: package, seal, digests |
| helm-scribe | sonnet | yes (+Skill) | docs upkeep; `writing-clearly-and-concisely` |

Read-only reviewers stay read-only on purpose: findings flow to helm-engineer,
which keeps one writer per change and reviews honest.

## Worth installing (not present today)

Command-line, via Homebrew — these agents shell out, so tools are capability:

- `swiftlint` — engineer/tester: mechanical style findings stop reaching review.
- `xcbeautify` — release/tester: readable build and test logs.
- `periphery` — architect: dead-code detection across the package.
- `hyperfine` — performance: honest before/after timing instead of one run.
- `create-dmg` — release: styled DMGs with a background and an /Applications alias.

Claude-side, per agent:

- helm-engineer / helm-tester already get the superpowers TDD and debugging
  skills; the `verification-before-completion` skill from the same plugin is
  worth adding to helm-release once release steps are scripted.
- An `elements-of-style` plugin serves helm-scribe and helm-localizer; scribe
  references it already.
