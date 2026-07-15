# AGPL-3.0 checklist (licensing)

DocumentServer and its components are **AGPL-3.0**. Every AI-assisted contribution must comply.
Sources: `LICENSE` (root), `CONTRIBUTING.md` §"AI-assisted contributions" (Licensing) and the
[AI Contribution Policy](https://github.com/Euro-Office/.github/blob/main/AI_POLICY.md).

## Checks

- [ ] **License header** on every NEW source file, in the format used by neighboring files in the same
      repo (copy the existing header; do not invent one).
- [ ] **No incompatible material**: no snippet copied from sources whose license is incompatible with
      AGPL-3.0 (proprietary, GPL-incompatible, code with unclear licensing).
- [ ] **Third-party dependencies**: license **compatible** with AGPL-3.0 and **verified against the
      real registry** (npm/PyPI/…); no invented or unverified packages (Euro-Office policy).
- [ ] **Copyright/attribution** preserved when adapting permitted third-party code.
- [ ] **Network use (AGPL §13)**: if a network-accessible feature is added, the obligation to make the
      corresponding source available is not broken.
- [ ] **No secrets or proprietary data** embedded in the code.

## Notes

- The **human** certifies the DCO (`Signed-off-by`); the agent **never** adds it.
- If in doubt about the license of an AI-generated snippet → **flag it in `review.md`** for human
  review; do not silence it.
