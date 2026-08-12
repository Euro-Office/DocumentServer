# Contribution Guidelines (Process)

This document defines how contributions should be made and reviewed. 

## Design rules

- Software should be as simple as possible and not get in the way.
- Automate what you can, leave choice to users only if you can’t choose for them.
- Focus on what matters and try to avoid confusing the user with lots of details. Show more details only when the user asks for it.
- Protect user data at all cost.
- Provide undo instead of confirmation: [users might not read confirmations and click them away](http://www.alistapart.com/articles/neveruseawarning/).
- Provide feedback about what is going on. For example, show a loading indicator when the application is doing something. When a user makes a choice, provide immediate feedback.
- Ask for design feedback and take the feedback serious! [There is science to usability.](http://uxmag.com/articles/quantifying-usability)

## Coding guidelines

As the code base is large and diverse, hard rules are difficult. Generally, the approach should try to follow the 'local' coding practices, that is, new code should not look completely out-of-place from it's context. Beyond that, we would like to see these guidelines follwed as much as they don't conflict with the file being edited:

* Maximum line-length of 120 characters
* Use spaces to indent
* A tab is 4 spaces wide
* End of Lines : Unix style (LF / '\\n') only
* Code should be tested, ideally with unit and integration tests.
* When you `git pull`, always `git pull --rebase` to avoid generating extra commits like: *merged main into main*
* Commits are required to be signed

## Development process

Summarizing, the typical flow for getting changes merged runs like this:

1. Start with an issue
   - For small fixes: you may directly open a PR.
     - This would be typically for changes that are self-contained, touch few files, and require no design decisions.
   - For larger changes: open an issue first describing:
     - The problem
     - Your proposed solution
     - The general approach
2. Discuss
   - Maintainers and contributors may provide feedback.
   - Aim for rough consensus before starting major work.
3. Implement
   - Work on your change and submit a PR.
   - Link the PR to the relevant issue.
4. Review
   - Your PR will be reviewed and may require changes before merging.
5. Once at least two people reviewed the PR and approved, a project member will merge it.

General rules:

- All changes must go through a pull request (PR)
- Work is done in branches, not directly on main
- Only complete, working features are merged into main
- Incomplete or unstable features should not be merged
- Prefer no feature over a broken one
- Keep changes separate and small. Bigger PR’s are harder to review and merge, so split where you can in smaller steps. 
  - For example, if you need an API change for a bigger improvement, get the API change in first.
- And all contributions should be fully compliant with the AGPLv3 or compatible open source licenses we use! Do we want any?

## Pull requests 

A PR should:

* Clearly describe:
  * The problem it solves
  * The approach taken
* Link to the relevant issue (if applicable)
* Be scoped and focused (avoid unrelated changes)
* Use descriptive branch names (e.g. fix/login-crash)
* Use clear commit messages
* Include tests for all new features and bug fixes

### Issues First

- Every pull request must be (ideally) linked to:
  - A bug report, or
  - A feature request
  - For really small changes an explanation in the PR is sufficient.
- For larger changes:
  - Create an issue before starting implementation
  - Describe:
    - Goal
    - Proposed approach
    - Use feedback to refine direction before coding

## Review Process

* Use the draft state in pull requests, when ready, mark your PR for review:
  * using labels is helpful - they should speak for themselves.
* For merging a review approval of a member of the project is required
* Reviewers should:
  * Be familiar with the relevant area, or
  * Be active project contributors
  * All automated tests must pass
  * Review feedback must be addressed before merging
* if your PR hasn't been reviewed within 7 days, feel free to ping a maintainer!
* Decisions are made by consensus. Our goal is to make the best technical decisions, and as no single person knows everything, we involve each other where possible.
  - A first negative comment might thus not be the final word, nor is a positive reply reason to merge right away. We let multiple viewpoints weigh in where possible!
  - In case of disagreement we involve other experienced contributors.

## Merging

* Only project members can merge PRs
* Merges happen after:
  * Approval requirements are met
  * CI/tests are green
  * No outstanding concerns remain

## Quality Expectations

* Code must:
  * Work as intended
  * Be maintainable
  * Fit the overall direction of the project
* Contributions should align with:
  * Existing architecture
  * Project roadmap (where applicable)

## AI-assisted contributions

Euro-Office allows contributions made with the help of AI tools. You are the author of everything you submit — AI assistance does not change that responsibility.

* **Disclosure:** Declare AI tool use in the PR description and add an `Assisted-by: AGENT_NAME:MODEL_VERSION` git trailer to each affected commit.
* **Accountability:** You must be able to explain, defend, and modify every line you submit. If a reviewer asks why something works a certain way, "the AI wrote it" is not an answer.
* **Communication:** PR descriptions, review comments, and issue reports must be written in your own words. This applies throughout the review process — passing reviewer feedback to an AI and posting whatever comes out is not acceptable.
* **Quality:** AI output must be reviewed, cleaned up, and tested by you before submission. New features must be tested on a live instance by you, not by an agent. Code that has never been executed, or that shifts debugging work onto maintainers, will not be accepted.
* **Licensing:** Ensure AI-generated code contains no material incompatible with the AGPLv3 or the license of any third-party component you are contributing to.
* **Sign-off:** Only the human contributor may add the `Signed-off-by` trailer. An agent must never sign off on your behalf.

For the full policy including autonomous agent rules, security reports, and beginner issues, read the [AI Contribution Policy][aipolicy].

[aipolicy]: https://github.com/Euro-Office/.github/blob/main/AI_POLICY.md
