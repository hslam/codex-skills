#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  print_chrome_pdf.sh --url URL --out-dir DIR --name NAME [--pages N-M] [--merge]

Examples:
  print_chrome_pdf.sh --url "https://github.com/owner/repo/pulls?q=is%3Apr" --out-dir "$HOME/Documents/dev-pdf" --name repo-prs.pdf
  print_chrome_pdf.sh --url "https://github.com/owner/repo/pulls?q=is%3Apr" --out-dir "$HOME/Documents/dev-pdf" --name repo-prs --pages 1-3 --merge
EOF
}

url=""
out_dir=""
name=""
pages=""
merge=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) url="$2"; shift 2 ;;
    --out-dir) out_dir="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --pages) pages="$2"; shift 2 ;;
    --merge) merge=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$url" || -z "$out_dir" || -z "$name" ]]; then
  usage >&2
  exit 2
fi

command -v cliclick >/dev/null
command -v osascript >/dev/null
command -v pdfinfo >/dev/null
command -v pdftotext >/dev/null

mkdir -p "$out_dir"

append_page_param() {
  local base="$1"
  local page="$2"
  if [[ "$base" == *\?* ]]; then
    printf '%s&page=%s' "$base" "$page"
  else
    printf '%s?page=%s' "$base" "$page"
  fi
}

expand_pages() {
  local spec="$1"
  if [[ -z "$spec" ]]; then
    echo "single"
  elif [[ "$spec" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    seq "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  elif [[ "$spec" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
    echo "$spec" | tr ',' '\n'
  else
    echo "Invalid --pages value: $spec" >&2
    exit 2
  fi
}

save_one() {
  local page="$1"
  local target_url="$url"
  local file="$name"

  if [[ "$page" != "single" ]]; then
    target_url="$(append_page_param "$url" "$page")"
    if [[ "$name" == *.pdf ]]; then
      file="${name%.pdf}-page-$page.pdf"
    else
      file="$name-page-$page.pdf"
    fi
  elif [[ "$file" != *.pdf ]]; then
    file="$file.pdf"
  fi

  local outfile="$out_dir/$file"
  rm -f "$outfile"

  echo "==> Opening $target_url"
  osascript -e 'tell application "Google Chrome" to activate' \
    -e "tell application \"Google Chrome\" to set URL of active tab of front window to \"$target_url\""
  sleep 4

  echo "==> Opening print preview"
  osascript -e 'tell application "Google Chrome" to activate' \
    -e 'tell application "System Events" to keystroke "p" using command down'
  sleep 5

  echo "==> Pressing Chrome Save"
  cliclick m:1582,949 w:500 dd:. w:300 du:.
  sleep 1

  echo "==> Saving as $outfile"
  osascript -e "tell application \"System Events\" to keystroke \"$file\""
  sleep 0.3

  # Only navigate if needed. The Save dialog usually remembers the previous folder.
  osascript -e 'tell application "System Events" to keystroke "g" using {command down, shift down}' \
    -e 'delay 0.4' \
    -e "tell application \"System Events\" to keystroke \"$out_dir\""
  sleep 0.5
  cliclick dc:991,527
  sleep 0.8
  cliclick c:1118,612

  for _ in {1..30}; do
    [[ -f "$outfile" ]] && break
    sleep 0.5
  done

  if [[ ! -f "$outfile" ]]; then
    screencapture -x "/tmp/chrome-print-pdf-missing-${page}.png" || true
    echo "Missing expected PDF: $outfile" >&2
    exit 1
  fi

  ls -lh "$outfile"
  pdfinfo "$outfile" | grep -E '^(Title|Pages|Creator|Producer|CreationDate)' || true
}

generated=()
while IFS= read -r page; do
  save_one "$page"
  if [[ "$page" == "single" ]]; then
    [[ "$name" == *.pdf ]] && generated+=("$out_dir/$name") || generated+=("$out_dir/$name.pdf")
  else
    [[ "$name" == *.pdf ]] && generated+=("$out_dir/${name%.pdf}-page-$page.pdf") || generated+=("$out_dir/$name-page-$page.pdf")
  fi
done < <(expand_pages "$pages")

if [[ "$merge" -eq 1 ]]; then
  command -v pdfunite >/dev/null
  merged="$out_dir/${name%.pdf}-all-pages.pdf"
  rm -f "$merged"
  pdfunite "${generated[@]}" "$merged"
  echo "==> Merged: $merged"
  pdfinfo "$merged" | grep -E '^(Title|Pages|Producer)' || true
fi
