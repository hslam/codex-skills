#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  export_github_commits_pdf.sh --repo OWNER/REPO|GITHUB_URL --out-dir DIR [--author USER] [--branch BRANCH] [--name NAME] [--resume] [--save-click X,Y]

Examples:
  export_github_commits_pdf.sh --repo tidbcloud/ffs --out-dir /tmp/exports
  export_github_commits_pdf.sh --repo https://github.com/ngaut/rfs --out-dir /tmp/exports --author hslam
  export_github_commits_pdf.sh --repo https://github.com/pingcap/badger/commits/sharding --out-dir /tmp/exports
  export_github_commits_pdf.sh --repo https://github.com/ngaut/unistore/tree/sharding --out-dir /tmp/exports
EOF
}

repo_input=""
out_dir=""
author=""
branch=""
name=""
resume=0
save_click=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo_input="$2"; shift 2 ;;
    --out-dir) out_dir="$2"; shift 2 ;;
    --author) author="$2"; shift 2 ;;
    --branch) branch="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --resume) resume=1; shift ;;
    --save-click) save_click="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$repo_input" || -z "$out_dir" ]]; then
  usage >&2
  exit 2
fi

command -v gh >/dev/null
command -v pdfinfo >/dev/null
command -v pdftotext >/dev/null
command -v osascript >/dev/null
command -v rg >/dev/null

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
print_script="$script_dir/print_chrome_pdf.sh"

github_path() {
  local raw="$1"
  raw="${raw#https://github.com/}"
  raw="${raw#http://github.com/}"
  raw="${raw#git@github.com:}"
  raw="${raw%%\?*}"
  raw="${raw%%#*}"
  raw="${raw%/}"
  printf '%s\n' "$raw"
}

url_decode() {
  local encoded="${1//+/ }"
  printf '%b' "${encoded//%/\\x}"
}

query_param() {
  local raw_url="$1"
  local key="$2"
  local query="${raw_url#*\?}"
  [[ "$query" != "$raw_url" ]] || return 1
  query="${query%%#*}"
  local part=""
  IFS='&' read -ra parts <<< "$query"
  for part in "${parts[@]}"; do
    if [[ "$part" == "$key="* ]]; then
      url_decode "${part#*=}"
      return
    fi
  done
  return 1
}

normalize_repo() {
  local raw
  raw="$(github_path "$1")"
  raw="${raw%.git}"
  local owner=""
  local repo=""
  IFS=/ read -r owner repo _ <<< "$raw"
  if [[ -z "$owner" || -z "$repo" ]]; then
    echo "Could not parse GitHub repository from: $1" >&2
    exit 2
  fi
  printf '%s/%s\n' "$owner" "$repo"
}

branch_from_url() {
  local raw
  raw="$(github_path "$1")"
  raw="${raw%.git}"
  local owner=""
  local repo=""
  local section=""
  local branch_path=""
  IFS=/ read -r owner repo section branch_path <<< "$raw"
  if [[ "$section" != "commits" && "$section" != "tree" ]]; then
    return 1
  fi
  if [[ -z "$branch_path" ]]; then
    return 1
  fi
  branch_path="${raw#"$owner/$repo/$section/"}"
  branch_path="${branch_path%/}"
  [[ -n "$branch_path" ]] || return 1
  url_decode "$branch_path"
}

filename_part() {
  sed -E 's#[^A-Za-z0-9._-]+#-#g; s#-+#-#g; s#^-##; s#-$##' <<< "$1"
}

repo_full_name="$(normalize_repo "$repo_input")"
repo_name="${repo_full_name##*/}"
author_from_input="$(query_param "$repo_input" author || true)"
branch_from_input="$(branch_from_url "$repo_input" || true)"

if [[ -z "$author" ]]; then
  if [[ -n "$author_from_input" ]]; then
    author="$author_from_input"
    author_source="input URL author query"
  else
    author="$(gh api user --jq .login)"
    author_source="current GitHub login"
  fi
else
  author_source="--author"
fi

if [[ -z "$branch" ]]; then
  if [[ -n "$branch_from_input" ]]; then
    branch="$branch_from_input"
    branch_source="input branch URL"
  else
    branch="$(gh api "repos/$repo_full_name" --jq .default_branch)"
    branch_source="repository default branch"
  fi
else
  branch_source="--branch"
fi

if [[ -z "$name" ]]; then
  if [[ "$branch_source" == "--branch" || "$branch_source" == "input branch URL" ]]; then
    name="$repo_name-$(filename_part "$branch")-commits-$author"
  else
    name="$repo_name-commits-$author"
  fi
fi

commit_count="$(
  gh api "repos/$repo_full_name/commits?sha=$branch&author=$author&per_page=100" \
    --paginate \
    --jq '.[].sha' |
  wc -l |
  tr -d ' '
)"

target_url="https://github.com/$repo_full_name/commits/$branch/?author=$author"
repo_out_dir="$out_dir/$repo_name"
merged_pdf="$repo_out_dir/${name%.pdf}-all-pages.pdf"
audit_file="$repo_out_dir/${name%.pdf}-audit.txt"

if [[ "$resume" -eq 0 ]]; then
  mkdir -p "$repo_out_dir"
  find "$repo_out_dir" -maxdepth 1 -type f -name "${name%.pdf}*.pdf" -delete
  rm -f "$audit_file"
fi

before_windows="$(osascript -e 'tell application "Google Chrome" to return count of windows')"

cmd=(
  "$print_script"
  --url "$target_url"
  --out-dir "$out_dir"
  --name "$name"
  --auto-github-next-pages
  --merge
  --repo-subdir
)

if [[ "$resume" -eq 1 ]]; then
  cmd+=(--resume)
fi
if [[ -n "$save_click" ]]; then
  cmd+=(--save-click "$save_click")
fi

"${cmd[@]}"

after_windows="$(osascript -e 'tell application "Google Chrome" to return count of windows')"

echo "==> GitHub commits export audit"
echo "Repository: $repo_full_name"
echo "Branch: $branch"
echo "Branch source: $branch_source"
echo "Author: $author"
echo "Author source: $author_source"
echo "Commit count: $commit_count"
echo "Chrome windows before: $before_windows"
echo "Chrome windows after: $after_windows"

pdf_metadata=""
missing=""
missing_sha_count="not_checked"
if [[ -f "$merged_pdf" ]]; then
  pdf_metadata="$(pdfinfo "$merged_pdf" | rg '^(Title|Pages|Creator|Producer|CreationDate)' || true)"
  if [[ -n "$pdf_metadata" ]]; then
    printf '%s\n' "$pdf_metadata"
  fi

  missing="$(
    comm -23 \
      <(gh api "repos/$repo_full_name/commits?sha=$branch&author=$author&per_page=100" --paginate --jq '.[].sha[0:7]' | sort -u) \
      <(pdftotext "$merged_pdf" - | rg -o '[0-9a-f]{7}' | sort -u) || true
  )"

  if [[ -z "$missing" ]]; then
    missing_sha_count=0
    echo "missing_sha_count=0"
  else
    missing_sha_count="$(printf '%s\n' "$missing" | wc -l | tr -d ' ')"
    echo "missing_sha_count=$missing_sha_count"
    printf '%s\n' "$missing"
  fi

  echo "Merged PDF: $merged_pdf"
else
  echo "Merged PDF not found: $merged_pdf" >&2
fi

per_page_pdf_list="$(find "$repo_out_dir" -maxdepth 1 -type f -name "${name%.pdf}-page-*.pdf" -print | sort || true)"
per_page_pdf_count=0
if [[ -n "$per_page_pdf_list" ]]; then
  per_page_pdf_count="$(printf '%s\n' "$per_page_pdf_list" | wc -l | tr -d ' ')"
fi

{
  echo "GitHub commits export audit"
  echo "Generated at: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "Repository: $repo_full_name"
  echo "Branch: $branch"
  echo "Branch source: $branch_source"
  echo "Author: $author"
  echo "Author source: $author_source"
  echo "Commit count: $commit_count"
  echo "Target URL: $target_url"
  echo "Output directory: $repo_out_dir"
  echo "Merged PDF: $merged_pdf"
  echo "Merged PDF exists: $([[ -f "$merged_pdf" ]] && echo yes || echo no)"
  echo "Per-page PDF count: $per_page_pdf_count"
  echo "Chrome windows before: $before_windows"
  echo "Chrome windows after: $after_windows"
  echo "missing_sha_count=$missing_sha_count"
  if [[ -n "$pdf_metadata" ]]; then
    echo
    echo "PDF metadata:"
    printf '%s\n' "$pdf_metadata"
  fi
  if [[ -n "$missing" ]]; then
    echo
    echo "Missing short SHAs:"
    printf '%s\n' "$missing"
  fi
  if [[ -n "$per_page_pdf_list" ]]; then
    echo
    echo "Per-page PDFs:"
    printf '%s\n' "$per_page_pdf_list"
  fi
} > "$audit_file"

echo "Audit file: $audit_file"
