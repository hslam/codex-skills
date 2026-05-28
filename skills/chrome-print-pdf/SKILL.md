---
name: chrome-print-pdf
description: Export logged-in Google Chrome pages to PDF with Chrome's native print preview and macOS Save as PDF. Use when Codex needs to print private GitHub pages, authenticated web pages, GitHub PR/search pagination, or other pages where headless Chrome would lose login state or return 404. Supports multi-page URL pagination, saving into a requested directory, and validating PDFs with poppler.
---

# Chrome Print PDF

## Overview

Use the signed-in Google Chrome GUI when the page depends on the user's browser session. Do not use headless Chrome for private GitHub pages unless the user explicitly accepts the risk: it may not reuse Chrome's login state and can print a 404 page.

Prefer `scripts/print_chrome_pdf.sh` for repeat work. Read `references/macos-chrome-print.md` when the GUI gets stuck or coordinates need adjustment.

## Prerequisites

Require:

```bash
brew install cliclick poppler
```

Require macOS permissions for the app running commands:

- System Settings -> Privacy & Security -> Accessibility: Codex, Codex Computer Use, Terminal
- System Settings -> Privacy & Security -> Screen & System Audio Recording: Codex, Terminal

Verify:

```bash
cliclick -V
pdfinfo -v
pdftotext -v
```

## Workflow

1. Determine the full export scope before printing. For GitHub PR/search result pages, prefer `--auto-github-pages` when `gh` can access the repository; otherwise identify the number of result pages and export every page.
2. Open the target URL in the user's signed-in Google Chrome.
3. Wait for the page to load and confirm the title/URL if needed.
4. Open print preview with `Cmd-P`.
5. Use Chrome print preview settings as requested. For normal GitHub lists, keep `Destination: Save as PDF`. To reduce pagination: open More settings, set Margins to None, lower Scale, use a larger Paper size, and turn off Headers and footers.
6. Press the blue Save button. The script reads the print window bounds, clicks the lower-right Save location with several retries, then tries Accessibility by label, and finally accepts `--save-click X,Y` as a manual override.
7. In the macOS Save dialog, type the file name, use `Cmd-Shift-G` to jump to the destination directory, then click the dialog's Save button through Accessibility.
8. If the GUI automation misses, take a screenshot before guessing and rerun with `--save-click X,Y` only as a last-mile override.
9. Validate every saved page and the merged PDF with `pdfinfo` and `pdftotext`.

## GitHub Pagination

For GitHub PR/search pagination, do not assume the user-provided `page=1` is the only page.

Preferred ways to determine page count:

- If `gh` can access the repository, use `scripts/print_chrome_pdf.sh --auto-github-pages` for GitHub PR list URLs with a `q=` filter. The script queries GitHub search for `repo:owner/repo <decoded q>` and uses the result count to set `--pages` internally. GitHub PR lists normally show 25 items per page, so `ceil(count / 25)` gives the browser page range.
- If the page is public, inspect the rendered or fetched pagination controls and use the last page number.
- If unauthenticated `curl` returns 404 or incomplete content, treat the page as private/session-dependent and use Chrome login state or `gh`; do not rely on headless browser output or public fetches for the final scope.

When exporting a GitHub list, report the result count or page range you used, such as `0 Open 63 Closed` and `pages 1-3`.

## Output Layout

When exporting several PDFs for one GitHub repository, save them under a repository-named folder. Prefer `--repo-subdir` for GitHub URLs, or `--subdir NAME` when the URL is not a standard GitHub repo URL.

Example output:

```text
$HOME/Documents/dev-pdf/
  tidb-operator-cse/
    tidb-operator-cse-closed-prs-hslam-page-1.pdf
    tidb-operator-cse-closed-prs-hslam-page-2.pdf
    tidb-operator-cse-closed-prs-hslam-all-pages.pdf
```

## Common Commands

Single page:

```bash
~/.codex/skills/chrome-print-pdf/scripts/print_chrome_pdf.sh \
  --url "https://github.com/owner/repo/pulls?q=is%3Apr+is%3Aclosed+author%3Auser" \
  --out-dir "$HOME/Documents/dev-pdf" \
  --name "repo-prs-page-1.pdf"
```

GitHub search pagination:

```bash
~/.codex/skills/chrome-print-pdf/scripts/print_chrome_pdf.sh \
  --url "https://github.com/owner/repo/pulls?q=is%3Apr+is%3Aclosed+author%3Auser" \
  --out-dir "$HOME/Documents/dev-pdf" \
  --name "repo-prs" \
  --auto-github-pages \
  --merge \
  --repo-subdir
```

Find the page range first when `gh` is available:

```bash
gh api 'repos/owner/repo/pulls?state=closed&per_page=100' --paginate \
  --jq '[.[] | select(.user.login=="user")] | length'
```

Then export `1-ceil(count/25)` with `--pages` only if `--auto-github-pages` is unavailable or the URL is not a normal GitHub PR list.

Manual print-preview Save override:

```bash
~/.codex/skills/chrome-print-pdf/scripts/print_chrome_pdf.sh \
  --url "https://github.com/owner/repo/pulls?q=is%3Apr" \
  --out-dir "$HOME/Documents/dev-pdf" \
  --name "repo-prs" \
  --pages 1-3 \
  --merge \
  --repo-subdir \
  --save-click 1620,942
```

Manual subdirectory:

```bash
~/.codex/skills/chrome-print-pdf/scripts/print_chrome_pdf.sh \
  --url "https://example.com/report" \
  --out-dir "$HOME/Documents/dev-pdf" \
  --name "report.pdf" \
  --subdir "example-report"
```

## Validation

After saving, always report:

```bash
pdfinfo "$file" | rg '^(Title|Pages|Creator|Producer|CreationDate)' || true
pdftotext "$file" - | rg -m 8 'expected text|repo name|query|result count'
```

For GitHub PR lists, verify the repository name, query text, and expected count such as `0 Open 63 Closed`. Also verify that the per-page PDFs are not all the same page by checking the saved page URLs or distinct text from each page when possible.

When the script can identify a GitHub PR list, it prints a validation block after export:

- repository and decoded query
- expected result count when `--auto-github-pages` was used
- matching text from every generated PDF
- a per-page distinctness sample using the first few PR numbers from each page

Merged PDFs created by `pdfunite` may not preserve `Title`, `Creator`, or `CreationDate`. That is acceptable if `pdfinfo` reports the expected page count and `pdftotext` verifies the repository, query, and result count.

## Notes

- Chrome UI cannot make a truly infinite one-page PDF. It can only reduce pagination by paper size, margins, and scale. For a real single long page, create a local HTML or use DevTools/Playwright with custom page dimensions.
- Do not reuse existing PDFs when the user is teaching or requesting the generation workflow. Generate from the current Chrome page and validate the new file.
- Do not name a shell variable `path` in zsh scripts; it can shadow `PATH` and make commands like `osascript` disappear.
- If Chrome print preview opens but the Save button click does not show the macOS save dialog, wait for the script retries first; clicking the Save location multiple times is acceptable. If it still fails, take a screenshot, then rerun with `--save-click X,Y` using the observed Save button center.
