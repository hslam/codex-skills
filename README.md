# Codex Skills

Personal Codex skills collection.

## Skills

| Skill | Purpose |
| --- | --- |
| `chrome-print-pdf` | Export logged-in Google Chrome pages, especially private GitHub pages, to PDF with Chrome print preview. |

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
$HOME/Documents/dev-pdf/tidb-operator-cse/
```

## Validate

Validate a skill:

```bash
python3 "$HOME/.codex/skills/.system/skill-creator/scripts/quick_validate.py" skills/chrome-print-pdf
```

## Publishing Notes

Do not commit generated PDFs, screenshots, logs, browser profiles, cookies, tokens, or machine-specific output.
