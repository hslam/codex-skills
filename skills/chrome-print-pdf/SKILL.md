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

1. Open the target URL in the user's signed-in Google Chrome.
2. Wait for the page to load and confirm the title/URL if needed.
3. Open print preview with `Cmd-P`.
4. Use Chrome print preview settings as requested. For normal GitHub lists, keep `Destination: Save as PDF`. To reduce pagination: open More settings, set Margins to None, lower Scale, use a larger Paper size, and turn off Headers and footers.
5. Press the blue Save button. The script reads the print window bounds, clicks the lower-right Save location with retries, then tries Accessibility by label, and finally accepts `--save-click X,Y` as a manual override.
6. In the macOS Save dialog, type the file name, use `Cmd-Shift-G` to jump to the destination directory, then click the dialog's Save button through Accessibility.
7. If the GUI automation misses, take a screenshot before guessing and rerun with `--save-click X,Y` only as a last-mile override.
8. Validate the output with `pdfinfo` and `pdftotext`.

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
  --pages 1-3 \
  --merge \
  --repo-subdir
```

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
pdfinfo "$file" | rg '^(Title|Pages|Creator|Producer|CreationDate)'
pdftotext "$file" - | rg -m 5 'expected text|repo name|query'
```

For GitHub PR lists, verify the repository name, query text, and expected count such as `0 Open 63 Closed`.

## Notes

- Chrome UI cannot make a truly infinite one-page PDF. It can only reduce pagination by paper size, margins, and scale. For a real single long page, create a local HTML or use DevTools/Playwright with custom page dimensions.
- Do not reuse existing PDFs when the user is teaching or requesting the generation workflow. Generate from the current Chrome page and validate the new file.
- Do not name a shell variable `path` in zsh scripts; it can shadow `PATH` and make commands like `osascript` disappear.
