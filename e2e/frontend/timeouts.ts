// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The waits that depend on the document server, defined once so a slow runner
// is tuned in one place and the per-test budget in playwright.config.ts is
// derived from them instead of drifting out of step.

// The editor iframe appears quickly once the editor page has loaded.
export const EDITOR_IFRAME_ATTACH = 15_000;

// The document behind the iframe has to be converted and loaded, and the first
// opens of a run pay for a cold editor bundle while the other workers do the
// same. 30 s expired on CI for tests that then passed in seconds later in the
// same run.
export const EDITOR_LOAD = 60_000;

// The editor drops the unsaved-changes "*" from its title once the change is
// accepted by the server.
export const DOCUMENT_SAVED = 30_000;

// After a reopen the editor can rebuild its iframe shortly after opening, so
// focus, select and read are retried as a unit within this budget.
export const EDITOR_CONTENT_READ = 30_000;

// docservice writes the file back to storage only a few seconds after the last
// editor disconnects.
export const STORED_FILE_SAVED = 60_000;

// One test opens at most two editors (create the file, then reopen it from the
// list); the slack covers the typing and assertions around them.
const TEST_SLACK = 30_000;
export const TEST_TIMEOUT = 2 * (EDITOR_IFRAME_ATTACH + EDITOR_LOAD) + TEST_SLACK;

// A users-menu test opens two editors (one each for two co-authors), then
// retries the setup of the co-edit, the click and a check of the result while
// the co-author's cursor reaches the other editor.
export const USERS_MENU_RETRY = 30_000;
export const USERS_MENU_TEST_TIMEOUT =
  2 * (EDITOR_IFRAME_ATTACH + EDITOR_LOAD) + 3 * USERS_MENU_RETRY + TEST_SLACK;
// The late-join test opens three editors and retries five steps.
export const USERS_MENU_JOIN_TEST_TIMEOUT =
  3 * (EDITOR_IFRAME_ATTACH + EDITOR_LOAD) + 5 * USERS_MENU_RETRY + TEST_SLACK;

// How often a stored file is read while checking that it does not change.
export const STORED_FILE_POLL_INTERVAL = 1_000;

// How long to watch for a save that must not happen: docservice waits
// savetimeoutdelay (5 s by default) after an editor disconnects before it saves,
// and the conversion follows.
export const FINAL_SAVE_QUIET_PERIOD = 15_000;

// A final-save test opens up to three editors and opens each again after saving:
// six opens, a save wait per editor and one storage wait.
export const FINAL_SAVE_TEST_TIMEOUT =
  6 * (EDITOR_IFRAME_ATTACH + EDITOR_LOAD) +
  3 * DOCUMENT_SAVED +
  STORED_FILE_SAVED +
  FINAL_SAVE_QUIET_PERIOD +
  TEST_SLACK;
