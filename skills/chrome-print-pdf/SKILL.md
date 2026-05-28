---
name: chrome-print-pdf
description: Export logged-in Google Chrome pages to PDF with Chrome's native print preview and macOS Save as PDF. Use when Codex needs to print private GitHub pages, authenticated web pages, GitHub PR/search pagination, GitHub commits-by-author pagination, or other pages where headless Chrome would lose login state and may return 404. Supports multi-page URL pagination, rendered Next pagination, saving into a requested directory, merging, and validating PDFs with poppler.
---

# Chrome Print PDF

## Overview

Use the signed-in Google Chrome GUI when the page depends on the user's browser session. Do not use headless Chrome for private GitHub pages unless the user explicitly accepts the risk: it may not reuse Chrome's login state and can print a 404 page.

Prefer `scripts/export_github_commits_pdf.sh` for GitHub commits-by-author exports and `scripts/export_github_prs_pdf.sh` for GitHub PR-by-author exports from a repository URL. Use `scripts/print_chrome_pdf.sh` for other logged-in pages or lower-level retry work. Read `references/macos-chrome-print.md` when the GUI gets stuck or coordinates need adjustment.

Before starting a Chrome GUI export, briefly tell the user that Chrome may be brought to the foreground while print preview and Save dialogs are automated.

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

1. Determine the full export scope before printing. For GitHub commits pages, prefer `export_github_commits_pdf.sh --repo OWNER/REPO --out-dir DIR`; it resolves author, branch, rendered Next pages, merge output, window count, SHA validation, and writes a `*-audit.txt` file next to the merged PDF. For closed PR pages by author from a repository URL, prefer `export_github_prs_pdf.sh --repo OWNER/REPO --out-dir DIR`; it resolves author, builds the `pulls?page=1&q=is%3Apr+is%3Aclosed+author%3AUSER` URL, exports all inferred pages, merges, and writes a `*-audit.txt` file. For other GitHub PR/search result pages, prefer `print_chrome_pdf.sh --auto-github-pages` when `gh` can access the repository. Otherwise identify every page URL and export every page.
2. Open the target URL in a new tab of the existing signed-in Chrome window so existing browser pages are not overwritten. Only create a new Chrome window when Chrome has no open windows. For multi-page exports, reuse that export tab for later pages.
3. Wait for the page to load and confirm the title/URL if needed.
4. Open print preview with `Cmd-P`. The script falls back to Chrome's `File -> Print...` menu when `Cmd-P` does not surface a print preview window.
5. Use Chrome print preview settings as requested. For normal GitHub lists, keep `Destination: Save as PDF`. To reduce pagination: open More settings, set Margins to None, lower Scale, use a larger Paper size, and turn off Headers and footers.
6. Press the blue Save button. The script first tries Accessibility by label, then falls back to reading the print window bounds and clicking the lower-right Save location with several retries. It finally accepts `--save-click X,Y` as a manual override.
7. In the macOS Save dialog, type the file name, use `Cmd-Shift-G` to jump to the destination directory, then click the dialog's Save button through Accessibility. The Save sheet may attach to Chrome's print preview window rather than `window 1`; search all Chrome windows and sheets before falling back to coordinates.
8. After each PDF is saved, close any Chrome windows that were created by the print flow, while keeping the locked export tab/window and the user's pre-existing windows.
9. If the GUI automation misses, take a screenshot before guessing and rerun with `--save-click X,Y` only as a last-mile override.
10. For long exports or retries, prefer `--resume` so existing PDFs that pass `pdfinfo` are reused and only missing or invalid pages are printed again.
11. Validate every saved page and the merged PDF with `pdfinfo` and `pdftotext`.

## GitHub Pagination

For GitHub PR/search/commits pagination, do not assume the user-provided first URL is the only page.

Preferred ways to determine page count:

- If `gh` can access the repository, use `scripts/print_chrome_pdf.sh --auto-github-pages` for GitHub PR list URLs with a `q=` filter. The script queries GitHub search for `repo:owner/repo <decoded q>` and uses the result count to set `--pages` internally. GitHub PR lists normally show 25 items per page, so `ceil(count / 25)` gives the browser page range.
- For GitHub commits pages, preserve a branch already present in a URL such as `https://github.com/owner/repo/commits/sharding` or `https://github.com/owner/repo/tree/sharding`; only resolve the default branch with `gh api repos/owner/repo --jq .default_branch` when neither `--branch` nor the input URL specifies a branch. Use `--auto-github-next-pages`; GitHub commits pages use rendered `Next` cursor URLs such as `after=<sha>+<n>`, not stable `page=N` URLs.
- To estimate scope for commits-by-author exports, use `gh api 'repos/owner/repo/commits?sha=<branch>&author=<login>&per_page=100' --paginate --jq '.[].sha' | wc -l`. The rendered page count should still come from Chrome's `Next` links.
- If the page is public, inspect the rendered or fetched pagination controls and use the last page number.
- If unauthenticated `curl` returns 404 or incomplete content, treat the page as private/session-dependent and use Chrome login state or `gh`; do not rely on headless browser output or public fetches for the final scope.

If GitHub search reports more than 1000 results, treat the auto-inferred page range as suspicious because GitHub search pagination may be capped. Narrow the query or verify the rendered pagination before doing the final export.

When exporting a GitHub list, report the result count and page range you used, plus the rendered Open/Closed count from the page text, such as `0 Open 63 Closed` and `pages 1-3`.

Final responses for GitHub list exports must include the GitHub login or author used, repository, branch when relevant, result count when known, exported page range, merged PDF path, merged PDF page count, and output directory.

## Output Layout

When exporting several PDFs for one GitHub repository, save them under a repository-named folder. Prefer `--repo-subdir` for GitHub URLs, or `--subdir NAME` when the URL is not a standard GitHub repo URL.

Use stable names that include the repository and a short filter description. Prefer:

- `repo-filter-short-page-N.pdf` for per-page files
- `repo-filter-short-all-pages.pdf` for merged files

Example output:

```text
/path/to/output/
  example-repo/
    example-repo-closed-prs-user-page-1.pdf
    example-repo-closed-prs-user-page-2.pdf
    example-repo-closed-prs-user-all-pages.pdf
```

## Common Commands

Single page:

```bash
~/.codex/skills/chrome-print-pdf/scripts/print_chrome_pdf.sh \
  --url "https://github.com/owner/repo/pulls?q=is%3Apr+is%3Aclosed+author%3Auser" \
  --out-dir "/path/to/output" \
  --name "repo-prs-page-1.pdf"
```

GitHub search pagination:

```bash
~/.codex/skills/chrome-print-pdf/scripts/print_chrome_pdf.sh \
  --url "https://github.com/owner/repo/pulls?q=is%3Apr+is%3Aclosed+author%3Auser" \
  --out-dir "/path/to/output" \
  --name "repo-prs" \
  --auto-github-pages \
  --merge \
  --repo-subdir
```

GitHub closed PRs by author from a repository URL:

```bash
~/.codex/skills/chrome-print-pdf/scripts/export_github_prs_pdf.sh \
  --repo "owner/repo" \
  --out-dir "/path/to/output"
```

Use `--author USER`, `--state open|closed|all`, or `--name NAME` only when overriding the current GitHub login, default `closed` PR state, or output basename. Use `--print-url` when you only need to verify the generated PR URL and page range.

GitHub commits-by-author export:

```bash
~/.codex/skills/chrome-print-pdf/scripts/export_github_commits_pdf.sh \
  --repo "owner/repo" \
  --out-dir "/path/to/output"
```

Use `--author USER`, `--branch BRANCH`, or `--name NAME` only when overriding the current GitHub login, repository default branch, or output basename. Use `--resume` after an interrupted export to reuse valid per-page PDFs.

When the `--repo` value is a GitHub commits or tree URL, `export_github_commits_pdf.sh` preserves `author=` from the URL and the `/commits/<branch>` or `/tree/<branch>` path unless explicit `--author` or `--branch` flags override them. Branch-specific inputs default to names like `repo-branch-commits-user` so they do not overwrite default-branch exports.

Lower-level GitHub commits pagination:

```bash
branch="$(gh api repos/owner/repo --jq .default_branch)"
author="$(gh api user --jq .login)"
~/.codex/skills/chrome-print-pdf/scripts/print_chrome_pdf.sh \
  --url "https://github.com/owner/repo/commits/$branch/?author=$author" \
  --out-dir "/path/to/output" \
  --name "repo-commits-$author" \
  --auto-github-next-pages \
  --merge \
  --repo-subdir
```

Resume an interrupted multi-page export:

```bash
~/.codex/skills/chrome-print-pdf/scripts/print_chrome_pdf.sh \
  --url "https://github.com/owner/repo/pulls?q=is%3Apr+is%3Aclosed+author%3Auser" \
  --out-dir "/path/to/output" \
  --name "repo-closed-prs-user" \
  --pages 1-10 \
  --merge \
  --repo-subdir \
  --resume
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
  --out-dir "/path/to/output" \
  --name "repo-prs" \
  --pages 1-3 \
  --merge \
  --repo-subdir \
  --save-click 1620,942
```

If only one page failed, rerun just that page with `--pages N` and the same `--name`, `--out-dir`, and subdirectory options, then rerun the full page range with `--merge --resume` to rebuild the merged PDF from valid per-page PDFs.

The script prints a page-specific retry command when a per-page export fails. Prefer using that exact command, then rebuild the merged PDF with the original full page range and `--merge --resume`.

Manual subdirectory:

```bash
~/.codex/skills/chrome-print-pdf/scripts/print_chrome_pdf.sh \
  --url "https://example.com/report" \
  --out-dir "/path/to/output" \
  --name "report.pdf" \
  --subdir "example-report"
```

## Validation

After saving, always report:

```bash
pdfinfo "$file" | rg '^(Title|Pages|Creator|Producer|CreationDate)' || true
pdftotext "$file" - | rg -m 8 'expected text|repo name|query|result count'
```

For GitHub PR lists, verify the repository name, query text, and expected count such as `0 Open 63 Closed`. Also verify that the per-page PDFs are not all the same page by checking the saved page URLs or distinct text from each page when possible. When using `export_github_prs_pdf.sh`, use its terminal audit block and saved `*-audit.txt` file as the primary validation: repository, author, state, query, result count, page range, Chrome window count before/after, merged PDF metadata, and per-page PDF count.

For GitHub commits exports, verify the API count, resolved branch, author login, rendered page count, and first/last page samples. Compare API page boundaries when useful, for example first source page `ae13622 ... 10dd66a` and last source page `a8fa6b3 ... bcc088c`.

When using `export_github_commits_pdf.sh`, use its terminal audit block and saved `*-audit.txt` file as the primary validation: repository, branch, author, commit count, Chrome window count before/after, merged PDF metadata, per-page PDF count, and `missing_sha_count=0`.

For merged GitHub list PDFs, verify more than the page count: sample text from the first source page and the last source page, such as representative PR numbers, so the merged file is known to contain the full range. For paginated exports, also check that each page PDF contains the expected `page=N` URL text when Chrome includes it in the printed output.

When the script can identify a GitHub PR list, it prints a validation block after export:

- repository and decoded query
- expected result count when `--auto-github-pages` was used
- rendered page count when `--auto-github-next-pages` was used
- matching text from every generated PDF
- rendered Open/Closed count text such as `4 Open 179 Closed` when present
- expected `page=N` URL text for each per-page PDF when present
- a per-page distinctness sample using the first few PR numbers from each page

Merged PDFs created by `pdfunite` may not preserve `Title`, `Creator`, or `CreationDate`. That is acceptable if `pdfinfo` reports the expected page count and `pdftotext` verifies the repository, query, and result count.

## Final Response

Keep the final response concise but auditable. Include:

- output directory
- merged PDF path
- audit file path for GitHub commits or PR helper exports
- per-page PDF location or count
- GitHub result count and page range when applicable
- merged PDF page count
- the validation signals used, including repository/query text and first/last page distinctness when applicable

## Notes

- Chrome UI cannot make a truly infinite one-page PDF. It can only reduce pagination by paper size, margins, and scale. For a real single long page, create a local HTML or use DevTools/Playwright with custom page dimensions.
- The script creates a Chrome window only if none exists, opens the first target URL in a new export tab in the existing browser window instead of overwriting the current tab, locks onto that export tab for page-load and Next-link checks, waits for `document.readyState` before printing, and waits for the print preview window instead of relying only on fixed sleeps.
- Before opening print preview, the script records the current Chrome window IDs. After the PDF file appears, it closes only the Chrome windows created during that print step so print-preview residue does not pile up as separate browser windows.
- Do not reuse existing PDFs when the user is teaching or requesting the generation workflow. Generate from the current Chrome page and validate the new file.
- `--resume` is for interrupted or long exports. Do not use it when the user explicitly wants a fresh export unless they approve reusing valid existing PDFs.
- Do not name a shell variable `path` in zsh scripts; it can shadow `PATH` and make commands like `osascript` disappear.
- If Chrome print preview opens but the Save button click does not show the macOS save dialog, wait for the script's Accessibility and coordinate retries first. If it still fails, check whether an overwrite or save dialog is already waiting on any Chrome window, take a screenshot, then rerun with `--save-click X,Y` using the observed Save button center.
