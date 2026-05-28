#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  export_github_prs_pdf.sh --repo OWNER/REPO|GITHUB_URL --out-dir DIR [--author USER] [--state closed|open|all] [--name NAME] [--resume] [--save-click X,Y] [--page-settle-seconds N] [--print-retries N] [--dry-run] [--print-url]

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
dry_run=0
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
    --dry-run|--plan) dry_run=1; shift ;;
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
if [[ "$print_url" -eq 0 && "$dry_run" -eq 0 ]]; then
  command -v python3 >/dev/null
  command -v rg >/dev/null
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
    if [[ "$github_query" =~ ^[[:space:]]*is:pr[[:space:]]*$ ]]; then
      state_label="all"
    else
      state_label="search"
    fi
  fi
fi

query_author=""
if [[ "$github_query" =~ (^|[[:space:]])author:([^[:space:]]+) ]]; then
  query_author="${BASH_REMATCH[2]}"
fi
if [[ -n "$query_author" ]]; then
  author_filter="$query_author"
  if [[ "$author_provided" -eq 1 ]]; then
    author_filter_source="--author"
  elif [[ -n "$input_author" ]]; then
    author_filter_source="input URL q"
  else
    author_filter_source="$author_source"
  fi
else
  author_filter="none"
  author_filter_source="query has no author filter"
fi

query_state=""
if [[ "$github_query" =~ (^|[[:space:]])is:(open|closed)([[:space:]]|$) ]]; then
  query_state="${BASH_REMATCH[2]}"
fi
if [[ -n "$query_state" ]]; then
  state_filter="$query_state"
  if [[ "$state_provided" -eq 1 ]]; then
    state_filter_source="--state"
  elif [[ -n "$input_state" ]]; then
    state_filter_source="input URL q"
  else
    state_filter_source="$state_source"
  fi
else
  state_filter="all"
  if [[ "$state_provided" -eq 1 && "$state" == "all" ]]; then
    state_filter_source="--state"
  else
    state_filter_source="query has no state filter"
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
  if [[ "$author_filter" == "none" ]]; then
    name="$repo_name-$(filename_part "$state_label")-prs"
  else
    name="$repo_name-$(filename_part "$state_label")-prs-$author_filter"
  fi
fi

if [[ "$print_url" -eq 1 ]]; then
  echo "Repository: $repo_full_name"
  echo "Author filter: $author_filter"
  echo "Author filter source: $author_filter_source"
  echo "State filter: $state_filter"
  echo "State filter source: $state_filter_source"
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
audit_json_file="$repo_out_dir/${name%.pdf}-audit.json"

if [[ "$dry_run" -eq 1 ]]; then
  echo "Mode: dry-run"
  echo "Repository: $repo_full_name"
  echo "Author filter: $author_filter"
  echo "Author filter source: $author_filter_source"
  echo "State filter: $state_filter"
  echo "State filter source: $state_filter_source"
  echo "Query: $github_query"
  echo "Query source: $query_source"
  echo "Result count: $result_count"
  echo "Page range: 1-$page_count"
  echo "Target URL: $target_url"
  echo "Output directory: $repo_out_dir"
  echo "Merged PDF: $merged_pdf"
  echo "Audit file: $audit_file"
  echo "Audit JSON: $audit_json_file"
  echo "Per-page PDFs:"
  for page in $(seq 1 "$page_count"); do
    page_url="${target_url/page=1/page=$page}"
    printf '  page=%s url=%s file=%s\n' "$page" "$page_url" "$repo_out_dir/${name%.pdf}-page-$page.pdf"
  done
  exit 0
fi

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
echo "Author filter: $author_filter"
echo "Author filter source: $author_filter_source"
echo "State filter: $state_filter"
echo "State filter source: $state_filter_source"
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
  echo "Author filter: $author_filter"
  echo "Author filter source: $author_filter_source"
  echo "State filter: $state_filter"
  echo "State filter source: $state_filter_source"
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

page_url_list=""
for page in $(seq 1 "$page_count"); do
  page_url="${target_url/page=1/page=$page}"
  page_url_list+="$page_url"$'\n'
done

JSON_FILE="$audit_json_file" \
REPO_FULL_NAME="$repo_full_name" \
AUTHOR_FILTER="$author_filter" \
AUTHOR_FILTER_SOURCE="$author_filter_source" \
STATE_FILTER="$state_filter" \
STATE_FILTER_SOURCE="$state_filter_source" \
QUERY="$github_query" \
QUERY_SOURCE="$query_source" \
RESULT_COUNT="$result_count" \
PAGE_RANGE="1-$page_count" \
TARGET_URL="$target_url" \
OUTPUT_DIRECTORY="$repo_out_dir" \
MERGED_PDF="$merged_pdf" \
MERGED_PDF_EXISTS="$([[ -f "$merged_pdf" ]] && echo true || echo false)" \
PER_PAGE_PDF_COUNT="$per_page_pdf_count" \
CHROME_WINDOWS_BEFORE="$before_windows" \
CHROME_WINDOWS_AFTER="$after_windows" \
PDF_METADATA="$pdf_metadata" \
PER_PAGE_PDFS="$per_page_pdf_list" \
PAGE_URLS="$page_url_list" \
python3 <<'PY'
import json
import os

def lines(name):
    return [line for line in os.environ.get(name, "").splitlines() if line]

def as_int(name):
    value = os.environ.get(name, "")
    return int(value) if value.isdigit() else value

data = {
    "type": "github_pr_export",
    "repository": os.environ["REPO_FULL_NAME"],
    "author": None if os.environ["AUTHOR_FILTER"] == "none" else os.environ["AUTHOR_FILTER"],
    "author_filter": None if os.environ["AUTHOR_FILTER"] == "none" else os.environ["AUTHOR_FILTER"],
    "author_filter_source": os.environ["AUTHOR_FILTER_SOURCE"],
    "state": os.environ["STATE_FILTER"],
    "state_filter": os.environ["STATE_FILTER"],
    "state_filter_source": os.environ["STATE_FILTER_SOURCE"],
    "query": os.environ["QUERY"],
    "query_source": os.environ["QUERY_SOURCE"],
    "result_count": as_int("RESULT_COUNT"),
    "page_range": os.environ["PAGE_RANGE"],
    "target_url": os.environ["TARGET_URL"],
    "page_urls": lines("PAGE_URLS"),
    "output_directory": os.environ["OUTPUT_DIRECTORY"],
    "merged_pdf": os.environ["MERGED_PDF"],
    "merged_pdf_exists": os.environ["MERGED_PDF_EXISTS"] == "true",
    "per_page_pdf_count": as_int("PER_PAGE_PDF_COUNT"),
    "per_page_pdfs": lines("PER_PAGE_PDFS"),
    "chrome_windows_before": as_int("CHROME_WINDOWS_BEFORE"),
    "chrome_windows_after": as_int("CHROME_WINDOWS_AFTER"),
    "pdf_metadata": os.environ.get("PDF_METADATA", ""),
}

with open(os.environ["JSON_FILE"], "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
PY

echo "Audit JSON: $audit_json_file"
