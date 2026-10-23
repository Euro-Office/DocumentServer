```
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
```

## what we want to test

UI and relation with darkmode
- button darkmode being disabled in light theme
- button darkmode being enabled in dark theme
- click on button darkmode enable darkmode
- interface theme's effect on content dark mode (forces off / restores)

background and foreground colors cells
- 100% automatic colors , before/after darkmode
- automatic background color + user text color , before/after darkmode
- user background color + automatic text color , before/after darkmode
- user background color + user text color , before/after darkmode
- merged cells with automatic colors
- search-highlighted cell text contrast
- a cell actively being edited (mid-edit toggle)

borders
- 100% automatic colors , before/after darkmode
- user/explicit color , before/after darkmode
- column resize guide visibility

print (simplified test)
- backgroundcolor of document , before/after darkmode

## running these tests

Each file in this folder is a normal Playwright spec, discovered directly --
no index, no special setup.

```bash
# all of them
npx playwright test tests/spreadsheeteditor/darkmode/

# just one
npx playwright test tests/spreadsheeteditor/darkmode/resize-guide.spec.ts

# by name
npx playwright test tests/spreadsheeteditor/darkmode/ -g "resize guide"

# everything except one
npx playwright test tests/spreadsheeteditor/darkmode/ --grep-invert "resize guide"
```

If a test fails with `page.goto` timing out or a `test.describe()`-related error
that doesn't match the actual file content, clear Playwright's transform cache
before assuming it's a real bug -- this has recurred a few times after
renaming/moving spec files in this folder:

```bash
rm -rf /tmp/playwright-transform-cache-*
```
