/*


  /$$$$$$   /$$$$$$  /$$$$$$$$       /$$$$$$$                      /$$
 /$$__  $$ /$$__  $$| $$_____/      | $$__  $$                    | $$
| $$  \__/| $$  \__/| $$            | $$  \ $$  /$$$$$$   /$$$$$$ | $$   /$$
|  $$$$$$ |  $$$$$$ | $$$$$         | $$  | $$ |____  $$ /$$__  $$| $$  /$$/
 \____  $$ \____  $$| $$__/         | $$  | $$  /$$$$$$$| $$  \__/| $$$$$$/
 /$$  \ $$ /$$  \ $$| $$            | $$  | $$ /$$__  $$| $$      | $$_  $$
|  $$$$$$/|  $$$$$$/| $$$$$$$$      | $$$$$$$/|  $$$$$$$| $$      | $$ \  $$
 \______/  \______/ |________/      |_______/  \_______/|__/      |__/  \__/
 /$$      /$$                 /$$                 /$$$$$$$$                    /$$
| $$$    /$$$                | $$                |__  $$__/                   | $$
| $$$$  /$$$$  /$$$$$$   /$$$$$$$  /$$$$$$          | $$  /$$$$$$   /$$$$$$$ /$$$$$$
| $$ $$/$$ $$ /$$__  $$ /$$__  $$ /$$__  $$         | $$ /$$__  $$ /$$_____/|_  $$_/
| $$  $$$| $$| $$  \ $$| $$  | $$| $$$$$$$$         | $$| $$$$$$$$|  $$$$$$   | $$
| $$\  $ | $$| $$  | $$| $$  | $$| $$_____/         | $$| $$_____/ \____  $$  | $$ /$$
| $$ \/  | $$|  $$$$$$/|  $$$$$$$|  $$$$$$$         | $$|  $$$$$$$ /$$$$$$$/  |  $$$$/
|__/     |__/ \______/  \_______/ \_______/         |__/ \_______/|_______/    \___/



what we want to test

UI and relation with darkmode
- button darkmode beeing dsiabled in light theme
- button darkmode beeing enabled in dark theme
- click on button darkmode enable darkmode

background and foreground colors cells
- 100% automatic colors , before/after darkmode
- automatic background color + usertextcolor , before/after darkmode
- user background color + automatic text color , before/after darkmode
- user background color + user text color , before/after darkmode

borders
- 100% automatic colors , before/after darkmode
-

print
- backgroundcolor of document , before/after darkmode


*/





// Index for the spreadsheet dark-mode suite -- imports each test file under
// spreadsheeteditor/darkmode/ for its side effect (registering its test()
// calls). Those files use a plain .ts extension (not .spec.ts/.test.ts) so
// Playwright's own file discovery doesn't also pick them up directly and
// run them a second time.
//
// Run this suite with --workers=1, e.g.:
//   npx playwright test tests/spreadsheeteditor-darkmode.spec.ts --workers=1
// Splitting into one file per test lets Playwright schedule up to ~7
// workers in parallel by default on this machine (cpus/2). Confirmed live:
// running 3 grouped files already used 3 workers and produced page.goto
// navigation timeouts against the shared dev container under that
// concurrent load -- 9 separate files would make more workers available,
// not fewer. Forcing one worker keeps these tests running against the
// shared container one at a time, like the rest of this suite already
// does when run as a single file.

import './spreadsheeteditor/darkmode/toggle-button';
import './spreadsheeteditor/darkmode/interface-theme';
import './spreadsheeteditor/darkmode/cell-colors';
import './spreadsheeteditor/darkmode/cell-borders';
import './spreadsheeteditor/darkmode/merged-cells';
import './spreadsheeteditor/darkmode/search-highlight';
import './spreadsheeteditor/darkmode/resize-guide';
import './spreadsheeteditor/darkmode/mid-edit-toggle';
import './spreadsheeteditor/darkmode/print-preview';

