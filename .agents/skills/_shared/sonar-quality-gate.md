# Emulated Quality Gate (SonarQube-style) — rubric

There is **no SonarQube** in the project. This sheet defines an **emulated** gate that `audit`
applies over the diff. **CodeQL** does run in CI (security) — note **parity** with its findings where
applicable. This gate **does not block**; it is a quality snapshot for the human to decide.

## Finding categories

- **Bugs** — reliability defects (incorrect logic, null/undefined, race conditions).
- **Vulnerabilities** — exploitable security flaws.
- **Security Hotspots** — security-sensitive code that needs manual review (not necessarily a flaw).
- **Code Smells** — maintainability (complexity, local duplication, naming, dead code).
- **Duplications** — % of duplicated lines introduced.
- **Coverage** — test coverage of the new/modified code (if measurable).

## Ratings (A–E) over the NEW/modified code

| Rating | Reliability (Bugs) | Security (Vulns) | Maintainability (tech debt) |
|---|---|---|---|
| **A** | 0 bugs | 0 vulns | debt ratio ≤ 5% |
| **B** | ≥1 Minor | ≥1 Minor | ≤ 10% |
| **C** | ≥1 Major | ≥1 Major | ≤ 20% |
| **D** | ≥1 Critical | ≥1 Critical | ≤ 50% |
| **E** | ≥1 Blocker | ≥1 Blocker | > 50% |

Severities: **Blocker > Critical > Major > Minor > Info**.

## Quality Gate condition (default, on "new code")

**PASS** if ALL hold; otherwise **FAIL** (informational):
- Reliability = **A** (0 new bugs)
- Security = **A** (0 new vulns)
- Security Hotspots: **100% reviewed**
- Maintainability = **A** (debt ≤ 5%)
- Duplications on new code ≤ **3%**
- Coverage of new code ≥ **80%** (or `n/a` if not measurable — note it, do not count it as a failure)

## Expected output (block in `review.md`)

```
### Quality Gate (emulated) — PASS | FAIL
Reliability: A   Security: A   Maintainability: B
Bugs: 0 · Vulnerabilities: 0 · Hotspots: 1 (review) · Code Smells: 4 · Duplications: 1.2% · Coverage(new): n/a
CodeQL parity: no known findings | [list]
Top items: 1) …  2) …
```
