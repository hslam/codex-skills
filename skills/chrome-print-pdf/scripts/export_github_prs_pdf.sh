#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  export_github_prs_pdf.sh --repo OWNER/REPO|GITHUB_URL --out-dir DIR [--author USER] [--state closed|open|all] [--name NAME] [--resume] [--save-click X,Y] [--page-settle-seconds N] [--print-retries N] [--print-url]

Examples:
  export_github_prs_pdf.sh --repo tidbcloud/tidb-operator-cse --out-dir /tmp/exports
  export_github_prs_pdf.sh --repo https://github.com/tidbcloud/tidb-operator-cse --out-dir /tmp/exports --author hslam
  export_github_prs_pdf.sh --repo "https://github.com/tidbcloud/tidb-operator-cse/pulls?page=1&q=is%3Apr+is%3Aclosed+author%3Ahslam" --print-url
  export_github_prs_pdf.sh --repo https://github.com/tidbcloud/tidb-operator-cse --print-url
EOF
}

repo_input=""
out_dir=""
author=""
state="closed"
name=""
resume=0
save_click=""
page_settle_seconds=""
print_retries=""
print_url=0
author_provided=0
state_provided=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo_input="$2"; shift 2 ;;
    --out-dir) out_dir="$2"; shift 2 ;;
    --author) author="$2"; author_provided=1; shift 2 ;;
    --state) state="$2"; state_provided=1; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --resume) resume=1; shift ;;
    --save-click) save_click="$2"; shift 2 ;;
    --page-settle-seconds) page_settle_seconds="$2"; shift 2 ;;
    --print-retries) print_retries="$2"; shift 2 ;;
    --print-url) print_url=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$repo_input" || ( -z "$out_dir" && "$print_url" -eq 0 ) ]]; then
  usage >&2
  exit 2
fi

case "$state" in
  closed|open|all) ;;
  *) echo "--state must be closed, open, or all." >&2; exit 2 ;;
esac

command -v gh >/dev/null
command -v rg >/dev/null
if [[ "$print_url" -eq 0 ]]; then
  command -v pdfinfo >/dev/null
  command -v pdftotext >/dev/null
  command -v osascript >/dev/null
fi

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

filename_part() {
  sed -E 's#[^A-Za-z0-9._-]+#-#g; s#-+#-#g; s#^-##; s#-$##' <<< "$1"
}

url_encode_query() {
  local raw="$1"
  local out=""
  local c=""
  local encoded=""
  local i=0
  for ((i = 0; i < ${#raw}; i++)); do
    c="${raw:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out+="$c" ;;
      " ") out+="+" ;;
      *) printf -v encoded '%%%02X' "'$c"; out+="$encoded" ;;
    esac
  done
  printf '%s\n' "$out"
}

repo_full_name="$(normalize_repo "$repo_input")"
repo_name="${repo_full_name##*/}"
input_query="$(query_param "$repo_input" q || true)"
input_author=""
input_state=""
if [[ "$input_query" =~ (^|[[:space:]])author:([^[:space:]]+) ]]; then
  input_author="${BASH_REMATCH[2]}"
fi
if [[ "$input_query" =~ (^|[[:space:]])is:(open|closed)([[:space:]]|$) ]]; then
  input_state="${BASH_REMATCH[2]}"
fi

if [[ -z "$author" ]]; then
  if [[ -n "$input_author" ]]; then
    author="$input_author"
    author_source="input URL q"
  else
    author="$(gh api user --jq .login)"
    author_source="current GitHub login"
  fi
else
  author_source="--author"
fi

if [[ "$state_provided" -eq 0 && -n "$input_state" ]]; then
  state="$input_state"
  state_source="input URL q"
elif [[ "$state_provided" -eq 1 ]]; then
  state_source="--state"
else
  state_source="default"
fi

if [[ "$state" == "all" ]]; then
  github_query="is:pr author:$author"
  state_label="all"
else
  github_query="is:pr is:$state author:$author"
  state_label="$state"
fi
query_source="generated"

if [[ -n "$input_query" && "$author_provided" -eq 0 && "$state_provided" -eq 0 ]]; then
  github_query="$input_query"
  query_source="input URL q"
  if [[ "$github_query" != *"is:pr"* ]]; then
    github_query="is:pr $github_query"
  fi
  if [[ -z "$input_state" ]]; then
    state_label="search"
  fi
fi

encoded_query="$(url_encode_query "$github_query")"
target_url="https://github.com/$repo_full_name/pulls?page=1&q=$encoded_query"
search_query="repo:$repo_full_name $github_query"
result_count="$(gh api -X GET search/issues -f q="$search_query" --jq '.total_count')"
if [[ ! "$result_count" =~ ^[0-9]+$ ]]; then
  echo "Could not infer GitHub PR result count for query: $search_query" >&2
  exit 1
fi
page_count=$(( (result_count + 24) / 25 ))
if [[ "$page_count" -lt 1 ]]; then
  page_count=1
fi

if [[ -z "$name" ]]; then
  name="$repo_name-$(filename_part "$state_label")-prs-$author"
fi

if [[ "$print_url" -eq 1 ]]; then
  echo "Repository: $repo_full_name"
  echo "Author: $author"
  echo "Author source: $author_source"
  echo "State: $state"
  echo "State source: $state_source"
  echo "Query: $github_query"
  echo "Query source: $query_source"
  echo "Result count: $result_count"
  echo "Page range: 1-$page_count"
  echo "Target URL: $target_url"
  echo "Default name: $name"
  exit 0
fi

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
  --auto-github-pages
  --merge
  --repo-subdir
)

if [[ "$resume" -eq 1 ]]; then
  cmd+=(--resume)
fi
if [[ -n "$save_click" ]]; then
  cmd+=(--save-click "$save_click")
fi
if [[ -n "$page_settle_seconds" ]]; then
  cmd+=(--page-settle-seconds "$page_settle_seconds")
fi
if [[ -n "$print_retries" ]]; then
  cmd+=(--print-retries "$print_retries")
fi

"${cmd[@]}"

after_windows="$(osascript -e 'tell application "Google Chrome" to return count of windows')"

echo "==> GitHub PR export audit"
echo "Repository: $repo_full_name"
echo "Author: $author"
echo "Author source: $author_source"
echo "State: $state"
echo "State source: $state_source"
echo "Query: $github_query"
echo "Query source: $query_source"
echo "Result count: $result_count"
echo "Page range: 1-$page_count"
echo "Target URL: $target_url"
echo "Chrome windows before: $before_windows"
echo "Chrome windows after: $after_windows"

pdf_metadata=""
if [[ -f "$merged_pdf" ]]; then
  pdf_metadata="$(pdfinfo "$merged_pdf" | rg '^(Title|Pages|Creator|Producer|CreationDate)' || true)"
  if [[ -n "$pdf_metadata" ]]; then
    printf '%s\n' "$pdf_metadata"
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
  echo "GitHub PR export audit"
  echo "Generated at: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "Repository: $repo_full_name"
  echo "Author: $author"
  echo "Author source: $author_source"
  echo "State: $state"
  echo "State source: $state_source"
  echo "Query: $github_query"
  echo "Query source: $query_source"
  echo "Result count: $result_count"
  echo "Page range: 1-$page_count"
  echo "Target URL: $target_url"
  echo "Output directory: $repo_out_dir"
  echo "Merged PDF: $merged_pdf"
  echo "Merged PDF exists: $([[ -f "$merged_pdf" ]] && echo yes || echo no)"
  echo "Per-page PDF count: $per_page_pdf_count"
  echo "Chrome windows before: $before_windows"
  echo "Chrome windows after: $after_windows"
  if [[ -n "$pdf_metadata" ]]; then
    echo
    echo "PDF metadata:"
    printf '%s\n' "$pdf_metadata"
  fi
  if [[ -n "$per_page_pdf_list" ]]; then
    echo
    echo "Per-page PDFs:"
    printf '%s\n' "$per_page_pdf_list"
  fi
} > "$audit_file"

echo "Audit file: $audit_file"
