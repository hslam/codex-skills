#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="${CODEX_HOME:-$HOME/.codex}/skills"

mkdir -p "$dest"

for skill_dir in "$repo_root"/skills/*; do
  [[ -d "$skill_dir" ]] || continue
  skill_name="$(basename "$skill_dir")"
  echo "Installing $skill_name -> $dest/$skill_name"
  rsync -a --delete "$skill_dir/" "$dest/$skill_name/"
done

echo "Done."
