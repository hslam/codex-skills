# Codex Skills

Personal Codex skills collection.

## Skills

| Skill | Purpose |
| --- | --- |
| `chrome-print-pdf` | Export logged-in Google Chrome pages, especially private GitHub PR/search/commits pages, to PDF with Chrome print preview. |

For GitHub commits-by-author exports, prefer `skills/chrome-print-pdf/scripts/export_github_commits_pdf.sh`; it resolves the branch and author from explicit flags, commits URLs, or the current GitHub context, exports rendered Next pages, merges PDFs, and saves a short SHA coverage audit next to the merged PDF.

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
```

## Publishing Notes

Do not commit generated PDFs, screenshots, logs, browser profiles, cookies, tokens, or machine-specific output.
