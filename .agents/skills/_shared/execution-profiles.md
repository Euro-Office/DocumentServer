# Execution profiles (mode / model / effort per skill)

Each skill runs best in a certain **mode**, **model**, and reasoning **effort**. These are
**recommendations, not enforcement**: Claude Code's `SKILL.md` frontmatter cannot set model/effort/
mode (verified — those keys are rejected), and the concepts are Claude-Code-specific (Codex/Cursor
ignore them). So each skill **announces** its recommended profile when it starts and **you apply it**:

- **Mode** — plan mode via `/plan` or Shift+Tab (cycles modes); leave plan mode to run edits.
- **Model** — `/model <opus|sonnet|haiku>`. **If you only have one model available, ignore this.**
- **Effort** — `/effort <low|medium|high|xhigh|max>`. If you raised effort earlier and a skill wants
  less, **lower it now** (e.g. `/effort medium`) — skills remind you so you don't stay on max by accident.

## Recommended profiles

| Skill | Mode | Model | Effort | Why |
|---|---|---|---|---|
| `blueprint` | plan mode | Opus | high | investigate + define; deep reasoning, no code changes |
| `breakdown` | plan mode | Sonnet (Opus if complex) | medium | decompose the plan into atomic steps |
| `apply` | normal | Sonnet | low–medium | apply one small, well-scoped step |
| `audit` | normal (read-only review) | Opus | high (max if security-critical) | catch bugs / security / quality |
| `prepare-pr` | normal | Sonnet (or Haiku) | low | draft the PR body from plan.md |

Notes:
- Starting points — scale **up** for unusually complex tasks, **down** for trivial ones.
- Only the human switches model/effort/mode; skills recommend and remind, never enforce.
