#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="${CODEX_HOME:-$HOME/.codex}/skills"
check_only=0
skills=()

usage() {
  cat <<'EOF'
Usage:
  install.sh [--dest DIR] [--check] [SKILL...]

Options:
  --dest DIR   Target skills directory. Defaults to $CODEX_HOME/skills or ~/.codex/skills.
  --check      Compare source and target without writing.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) dest="$2"; shift 2 ;;
    --check) check_only=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    *) skills+=("$1"); shift ;;
  esac
done

if [[ $# -gt 0 ]]; then
  skills+=("$@")
fi

if [[ "${#skills[@]}" -eq 0 ]]; then
  for skill_dir in "$repo_root"/skills/*; do
    [[ -d "$skill_dir" ]] || continue
    skills+=("$(basename "$skill_dir")")
  done
fi

if [[ "$check_only" -eq 0 ]]; then
  mkdir -p "$dest"
fi

for skill_name in "${skills[@]}"; do
  skill_dir="$repo_root/skills/$skill_name"
  if [[ ! -d "$skill_dir" ]]; then
    echo "Skill not found: $skill_name" >&2
    exit 2
  fi

  if [[ "$check_only" -eq 1 ]]; then
    echo "Checking $skill_name -> $dest/$skill_name"
    diff -qr "$skill_dir" "$dest/$skill_name"
  else
    echo "Installing $skill_name -> $dest/$skill_name"
    rsync -a --delete "$skill_dir/" "$dest/$skill_name/"
  fi
done

if [[ "$check_only" -eq 1 ]]; then
  echo "All checked skills match."
else
  echo "Done."
fi
