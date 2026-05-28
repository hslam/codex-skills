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
5. Press the blue Save button with `cliclick` using a slow down/up sequence. A simple click often fails on Chrome's print preview.
6. In the macOS Save dialog, type the file name. If the folder is not already correct, use `Cmd-Shift-G`, type the destination path, then double-click the result row to enter the folder.
7. Press/click the Save button in the macOS Save dialog.
8. Validate the output with `pdfinfo` and `pdftotext`.

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
  --merge
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
