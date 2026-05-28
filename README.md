# Codex Skills

Personal Codex skills collection.

## Skills

| Skill | Purpose |
| --- | --- |
| `chrome-print-pdf` | Export logged-in Google Chrome pages, especially private GitHub PR/search/commits pages, to PDF with Chrome print preview. |

For GitHub PR-by-author exports, prefer `skills/chrome-print-pdf/scripts/export_github_prs_pdf.sh`; it resolves the current GitHub author from a repository URL, preserves `q=` from GitHub pulls URLs when provided, builds the closed PR search URL, exports every inferred page, merges PDFs, and saves text/JSON audits next to the merged PDF. Use `--dry-run` to preview URLs and output paths without opening Chrome.

For GitHub commits-by-author exports, prefer `skills/chrome-print-pdf/scripts/export_github_commits_pdf.sh`; it resolves the branch and author from explicit flags, commits/tree URLs, or the current GitHub context, exports rendered Next pages, merges PDFs, and saves text/JSON short SHA coverage audits next to the merged PDF. Use `--dry-run` to preview the target URL and estimated output paths without opening Chrome.

## Layout

```text
skills/
  <skill-name>/
    SKILL.md
    agents/openai.yaml
    scripts/
    references/
```

## Install Locally

Sync every skill in this repo into the local Codex skills directory:

```bash
./scripts/install.sh
```

Check that an installed skill matches this repository:

```bash
./scripts/install.sh --check chrome-print-pdf
```

Install one skill manually:

```bash
rsync -a skills/chrome-print-pdf/ "$HOME/.codex/skills/chrome-print-pdf/"
```

## Output Convention

Generated artifacts should live outside this repository. For repeated exports from one source repo, create a matching folder under the output directory, for example:

```text
/path/to/output/example-repo/
```

## Validate

Validate a skill:

```bash
python3 "$HOME/.codex/skills/.system/skill-creator/scripts/quick_validate.py" skills/chrome-print-pdf
tests/chrome-print-pdf.sh
```

## Publishing Notes

Do not commit generated PDFs, screenshots, logs, browser profiles, cookies, tokens, or machine-specific output.
