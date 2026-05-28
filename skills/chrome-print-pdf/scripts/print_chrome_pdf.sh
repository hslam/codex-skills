#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  print_chrome_pdf.sh --url URL --out-dir DIR --name NAME [--pages N-M | --auto-github-pages] [--merge] [--repo-subdir | --subdir NAME] [--resume] [--save-click X,Y]

Examples:
  print_chrome_pdf.sh --url "https://github.com/owner/repo/pulls?q=is%3Apr" --out-dir "$HOME/Documents/dev-pdf" --name repo-prs.pdf
  print_chrome_pdf.sh --url "https://github.com/owner/repo/pulls?q=is%3Apr" --out-dir "$HOME/Documents/dev-pdf" --name repo-prs --auto-github-pages --merge --repo-subdir
  print_chrome_pdf.sh --url "https://github.com/owner/repo/pulls?q=is%3Apr" --out-dir "$HOME/Documents/dev-pdf" --name repo-prs --pages 1-10 --merge --repo-subdir --resume
EOF
}

url=""
out_dir=""
name=""
pages=""
merge=0
repo_subdir=0
subdir=""
save_click=""
resume=0
auto_github_pages=0
github_result_count=""
github_query=""
github_repo_full_name=""
export_chrome_window_id=""
export_chrome_tab_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) url="$2"; shift 2 ;;
    --out-dir) out_dir="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --pages) pages="$2"; shift 2 ;;
    --auto-github-pages) auto_github_pages=1; shift ;;
    --merge) merge=1; shift ;;
    --repo-subdir) repo_subdir=1; shift ;;
    --subdir) subdir="$2"; shift 2 ;;
    --resume) resume=1; shift ;;
    --save-click) save_click="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$url" || -z "$out_dir" || -z "$name" ]]; then
  usage >&2
  exit 2
fi

root_out_dir="$out_dir"

command -v cliclick >/dev/null
command -v osascript >/dev/null
command -v pdfinfo >/dev/null
command -v pdftotext >/dev/null

if [[ -n "$save_click" && ! "$save_click" =~ ^-?[0-9]+,-?[0-9]+$ ]]; then
  echo "--save-click must be X,Y." >&2
  exit 2
fi

derive_github_repo_name() {
  local raw_url="$1"
  local path_part="${raw_url#*github.com/}"
  [[ "$path_part" != "$raw_url" ]] || return 1
  path_part="${path_part%%\?*}"
  path_part="${path_part%%#*}"
  local owner=""
  local repo=""
  IFS=/ read -r owner repo _ <<< "$path_part"
  repo="${repo%.git}"
  [[ -n "$owner" && -n "$repo" ]] || return 1
  printf '%s\n' "$repo"
}

derive_github_repo_full_name() {
  local raw_url="$1"
  local path_part="${raw_url#*github.com/}"
  [[ "$path_part" != "$raw_url" ]] || return 1
  path_part="${path_part%%\?*}"
  path_part="${path_part%%#*}"
  local owner=""
  local repo=""
  IFS=/ read -r owner repo _ <<< "$path_part"
  repo="${repo%.git}"
  [[ -n "$owner" && -n "$repo" ]] || return 1
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

infer_github_pages() {
  command -v gh >/dev/null
  github_repo_full_name="$(derive_github_repo_full_name "$url")" || {
    echo "Could not derive GitHub owner/repo from URL." >&2
    exit 2
  }
  github_query="$(query_param "$url" q)" || {
    echo "Could not find q= query parameter in GitHub PR URL." >&2
    exit 2
  }
  if [[ "$github_query" != *"is:pr"* ]]; then
    github_query="is:pr $github_query"
  fi

  local search_query="repo:$github_repo_full_name $github_query"
  github_result_count="$(gh api -X GET search/issues -f q="$search_query" --jq '.total_count')"
  [[ "$github_result_count" =~ ^[0-9]+$ ]] || {
    echo "Could not infer GitHub result count for query: $search_query" >&2
    exit 1
  }

  local page_count=$(( (github_result_count + 24) / 25 ))
  if [[ "$page_count" -lt 1 ]]; then
    page_count=1
  fi
  if [[ "$github_result_count" -gt 1000 ]]; then
    echo "==> Warning: GitHub search returned more than 1000 results; GitHub search pagination may be capped. Narrow the query or verify rendered pagination before relying on the full export." >&2
  fi
  pages="1-$page_count"
  echo "==> Inferred GitHub PR result count: $github_result_count"
  echo "==> Inferred GitHub page range: $pages"
}

if [[ "$auto_github_pages" -eq 1 ]]; then
  if [[ -n "$pages" ]]; then
    echo "Use only one of --pages or --auto-github-pages." >&2
    exit 2
  fi
  infer_github_pages
fi

if [[ -n "$subdir" && "$repo_subdir" -eq 1 ]]; then
  echo "Use only one of --repo-subdir or --subdir." >&2
  exit 2
fi

if [[ "$repo_subdir" -eq 1 ]]; then
  subdir="$(derive_github_repo_name "$url")" || {
    echo "Could not derive GitHub repo name from URL. Use --subdir NAME instead." >&2
    exit 2
  }
fi

if [[ -n "$subdir" ]]; then
  out_dir="$out_dir/$subdir"
fi

mkdir -p "$out_dir"

append_page_param() {
  local base="$1"
  local page="$2"
  local page_param_re='^(.*[?&])page=[^&]*(.*)$'
  if [[ "$base" =~ $page_param_re ]]; then
    printf '%spage=%s%s' "${BASH_REMATCH[1]}" "$page" "${BASH_REMATCH[2]}"
  elif [[ "$base" == *\?* ]]; then
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

applescript_escape() {
  sed 's/\\/\\\\/g; s/"/\\"/g' <<< "$1"
}

front_chrome_print_window_bounds() {
  osascript <<'OSA'
tell application "Google Chrome" to activate
tell application "System Events"
  tell process "Google Chrome"
    set frontmost to true
    delay 0.2
    repeat with candidateWindow in windows
      try
        set windowName to name of candidateWindow as text
      on error
        set windowName to ""
      end try
      if windowName is "Print" or windowName contains "Print" then
        set windowPosition to position of candidateWindow
        set windowSize to size of candidateWindow
        return (item 1 of windowPosition as text) & "," & (item 2 of windowPosition as text) & "," & (item 1 of windowSize as text) & "," & (item 2 of windowSize as text)
      end if
    end repeat

    set candidateWindow to window 1
    set windowPosition to position of candidateWindow
    set windowSize to size of candidateWindow
    return (item 1 of windowPosition as text) & "," & (item 2 of windowPosition as text) & "," & (item 1 of windowSize as text) & "," & (item 2 of windowSize as text)
  end tell
end tell
OSA
}

chrome_print_window_visible() {
  osascript <<'OSA' >/dev/null 2>&1
tell application "Google Chrome" to activate
tell application "System Events"
  tell process "Google Chrome"
    repeat with candidateWindow in windows
      try
        set windowName to name of candidateWindow as text
      on error
        set windowName to ""
      end try
      if windowName is "Print" or windowName contains "Print" then return
    end repeat
    error "Chrome print window is not visible"
  end tell
end tell
OSA
}

click_accessible_chrome_save() {
  osascript <<'OSA' >/dev/null 2>&1
with timeout of 2 seconds
  tell application "System Events"
    tell process "Google Chrome"
      set frontmost to true
      repeat with candidateWindow in windows
        try
          click (first button of candidateWindow whose name is "Save")
          return
        end try
      end repeat
      click (first button of window 1 whose name is "Save")
    end tell
  end tell
end timeout
OSA
}

wait_for_chrome_print_window() {
  for _ in {1..40}; do
    if chrome_print_window_visible; then
      return
    fi
    sleep 0.25
  done
  echo "Timed out waiting for Chrome print preview window" >&2
  return 1
}

press_chrome_print_save() {
  local click_point="$save_click"

  if [[ -n "$click_point" ]]; then
    echo "==> Pressing Chrome Save at override $click_point"
    cliclick m:"$click_point" w:300 dd:. w:200 du:.
    return
  fi

  for attempt in 1 2 3; do
    echo "==> Pressing Chrome Save with Accessibility (attempt $attempt)"
    if click_accessible_chrome_save; then
      sleep 1.5
      if macos_save_dialog_visible; then
        return
      fi
    fi
  done

  local x=""
  local y=""
  local w=""
  local h=""
  local bounds=""

  for attempt in 1 2 3 4 5; do
    bounds="$(front_chrome_print_window_bounds)"
    IFS=, read -r x y w h <<< "$bounds"
    click_point="$((x + w - 53)),$((y + h - 42))"
    echo "==> Pressing Chrome Save at estimated $click_point (attempt $attempt)"
    cliclick m:"$click_point" w:300 dd:. w:200 du:.
    sleep 1.5
    if macos_save_dialog_visible; then
      return
    fi
  done

  echo "Could not locate Chrome print Save button." >&2
  return 1
}

macos_save_dialog_visible() {
  osascript <<'OSA' >/dev/null 2>&1
tell application "System Events"
  tell process "Google Chrome"
    try
      if exists sheet 1 of window 1 then
        if description of sheet 1 of window 1 is "save" then return
      end if
    end try
    try
      if description of window 1 is "save" then return
    end try
    error "macOS Save dialog is not visible"
  end tell
end tell
OSA
}

wait_for_macos_save_dialog() {
  for _ in {1..60}; do
    if macos_save_dialog_visible; then
      return
    fi
    sleep 0.25
  done
  echo "Timed out waiting for macOS Save dialog" >&2
  return 1
}

go_to_folder_sheet_visible() {
  osascript <<'OSA' >/dev/null 2>&1
tell application "System Events"
  tell process "Google Chrome"
    try
      if exists sheet 1 of sheet 1 of window 1 then return
    end try
    error "Go to folder sheet is not visible"
  end tell
end tell
OSA
}

wait_for_go_to_folder_sheet_closed() {
  for _ in {1..10}; do
    if ! go_to_folder_sheet_visible; then
      return
    fi
    osascript -e 'tell application "System Events" to key code 36'
    sleep 0.4
  done
  echo "Timed out waiting for Go to Folder sheet to close" >&2
  return 1
}

click_macos_dialog_button() {
  local button_name="$1"
  local escaped_name=""
  escaped_name="$(applescript_escape "$button_name")"
  osascript <<OSA >/dev/null 2>&1
on clickButtonByName(containerElement, buttonName)
  tell application "System Events"
    try
      if role of containerElement is "AXButton" and name of containerElement is buttonName then
        click containerElement
        return true
      end if
    end try

    try
      repeat with childElement in UI elements of containerElement
        if my clickButtonByName(childElement, buttonName) then return true
      end repeat
    end try
  end tell
  return false
end clickButtonByName

tell application "System Events"
  tell process "Google Chrome"
    set frontmost to true
    try
      if exists sheet 1 of window 1 then
        if my clickButtonByName(sheet 1 of window 1, "$escaped_name") then return
      end if
    end try
    if my clickButtonByName(window 1, "$escaped_name") then return
    error "Button not found: $escaped_name"
  end tell
end tell
OSA
}

save_macos_pdf_dialog() {
  local file="$1"
  local target_dir="$2"
  local escaped_file=""
  local escaped_dir=""
  escaped_file="$(applescript_escape "$file")"
  escaped_dir="$(applescript_escape "$target_dir")"

  wait_for_macos_save_dialog

  osascript <<OSA
tell application "System Events"
  tell process "Google Chrome"
    set frontmost to true
    keystroke "$escaped_file"
    delay 0.2
    keystroke "g" using {command down, shift down}
    delay 0.4
    keystroke "$escaped_dir"
    delay 0.2
    key code 36
  end tell
end tell
OSA
  wait_for_go_to_folder_sheet_closed
  sleep 0.3

  click_macos_dialog_button "Save" || {
    # Some macOS versions keep focus inside the dialog after "Go to folder".
    osascript -e 'tell application "System Events" to key code 36'
  }

  # Replace stale files if Chrome or macOS still prompts despite rm -f.
  sleep 0.3
  click_macos_dialog_button "Replace" || true
}

open_chrome_export_tab() {
  local target_url="$1"
  local escaped_target_url=""
  local ids=""
  escaped_target_url="$(applescript_escape "$target_url")"

  if [[ -z "$export_chrome_window_id" || -z "$export_chrome_tab_id" ]]; then
    ids="$(osascript <<OSA
tell application "Google Chrome"
  activate
  if (count of windows) is 0 then
    make new window
    set URL of active tab of front window to "$escaped_target_url"
  else
    tell front window
      make new tab at end of tabs with properties {URL:"$escaped_target_url"}
      set active tab index to (count of tabs)
    end tell
  end if
  set windowId to id of front window
  set tabId to id of active tab of front window
  return (windowId as text) & "," & (tabId as text)
end tell
OSA
)"
  else
    ids="$(osascript <<OSA
tell application "Google Chrome"
  activate
  set targetWindowId to $export_chrome_window_id
  set targetTabId to $export_chrome_tab_id
  set targetWindow to missing value

  repeat with candidateWindow in windows
    if id of candidateWindow is targetWindowId then
      set targetWindow to candidateWindow
      exit repeat
    end if
  end repeat

  if targetWindow is missing value then
    make new window
    set URL of active tab of front window to "$escaped_target_url"
  else
    set targetIndex to 0
    set i to 1
    repeat with candidateTab in tabs of targetWindow
      if id of candidateTab is targetTabId then
        set targetIndex to i
        exit repeat
      end if
      set i to i + 1
    end repeat

    if targetIndex is 0 then
      tell targetWindow
        make new tab at end of tabs with properties {URL:"$escaped_target_url"}
        set active tab index to (count of tabs)
      end tell
    else
      set URL of tab targetIndex of targetWindow to "$escaped_target_url"
      set active tab index of targetWindow to targetIndex
    end if
    set index of targetWindow to 1
  end if

  set windowId to id of front window
  set tabId to id of active tab of front window
  return (windowId as text) & "," & (tabId as text)
end tell
OSA
)"
  fi

  IFS=, read -r export_chrome_window_id export_chrome_tab_id <<< "$ids"
}

wait_for_chrome_page_load() {
  local expected_url="$1"
  local escaped_url=""
  escaped_url="$(applescript_escape "$expected_url")"

  for _ in {1..80}; do
    if osascript <<OSA >/dev/null 2>&1
tell application "Google Chrome"
  if (count of windows) is 0 then error "No Chrome window"
  set tabUrl to URL of active tab of front window as text
  if tabUrl does not contain "$escaped_url" and "$escaped_url" does not contain tabUrl then error "URL has not settled"
  set readyState to execute active tab of front window javascript "document.readyState"
  if readyState is not "complete" then error "Page is not complete"
end tell
OSA
    then
      sleep 0.8
      return
    fi
    sleep 0.25
  done

  echo "Timed out waiting for Chrome page load: $expected_url" >&2
  return 1
}

print_rerun_hint() {
  local page="$1"
  if [[ "$page" != "single" ]]; then
    echo "==> To retry this page after fixing the UI state:" >&2
    printf '    %q --url %q --out-dir %q --name %q --pages %q' "$0" "$url" "$root_out_dir" "$name" "$page" >&2
    if [[ "$repo_subdir" -eq 1 ]]; then
      printf ' --repo-subdir' >&2
    elif [[ -n "$subdir" ]]; then
      printf ' --subdir %q' "$subdir" >&2
    fi
    printf ' --resume\n' >&2
    if [[ -n "$pages" ]]; then
      echo "==> Then rebuild the merged PDF with the original full page range plus --merge --resume." >&2
    fi
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
  if [[ "$resume" -eq 1 && -f "$outfile" ]] && pdfinfo "$outfile" >/dev/null 2>&1; then
    echo "==> Reusing existing valid PDF: $outfile"
    pdfinfo "$outfile" | grep -E '^(Title|Pages|Creator|Producer|CreationDate)' || true
    return
  fi

  rm -f "$outfile"

  echo "==> Opening $target_url"
  open_chrome_export_tab "$target_url"
  wait_for_chrome_page_load "$target_url" || return 1

  echo "==> Opening print preview"
  osascript -e 'tell application "Google Chrome" to activate' \
    -e 'tell application "System Events" to keystroke "p" using command down'
  wait_for_chrome_print_window || return 1

  press_chrome_print_save || return 1
  sleep 1

  echo "==> Saving as $outfile"
  save_macos_pdf_dialog "$file" "$out_dir" || return 1

  for _ in {1..30}; do
    [[ -f "$outfile" ]] && break
    sleep 0.5
  done

  if [[ ! -f "$outfile" ]]; then
    screencapture -x "/tmp/chrome-print-pdf-missing-${page}.png" || true
    echo "Missing expected PDF: $outfile" >&2
    return 1
  fi

  ls -lh "$outfile"
  pdfinfo "$outfile" | grep -E '^(Title|Pages|Creator|Producer|CreationDate)' || true
}

generated=()
generated_pages=()
while IFS= read -r page; do
  if ! save_one "$page"; then
    print_rerun_hint "$page"
    exit 1
  fi
  if [[ "$page" == "single" ]]; then
    [[ "$name" == *.pdf ]] && generated+=("$out_dir/$name") || generated+=("$out_dir/$name.pdf")
  else
    [[ "$name" == *.pdf ]] && generated+=("$out_dir/${name%.pdf}-page-$page.pdf") || generated+=("$out_dir/$name-page-$page.pdf")
  fi
  generated_pages+=("$page")
done < <(expand_pages "$pages")

if [[ "$merge" -eq 1 ]]; then
  command -v pdfunite >/dev/null
  merged="$out_dir/${name%.pdf}-all-pages.pdf"
  rm -f "$merged"
  pdfunite "${generated[@]}" "$merged"
  echo "==> Merged: $merged"
  pdfinfo "$merged" | grep -E '^(Title|Pages|Producer)' || true
fi

validate_github_pr_exports() {
  [[ -n "$github_repo_full_name" ]] || github_repo_full_name="$(derive_github_repo_full_name "$url" 2>/dev/null || true)"
  [[ -n "$github_query" ]] || github_query="$(query_param "$url" q 2>/dev/null || true)"
  [[ -n "$github_repo_full_name" && -n "$github_query" ]] || return 0

  echo "==> GitHub PR export validation"
  echo "Repository: $github_repo_full_name"
  echo "Query: $github_query"
  if [[ -n "$github_result_count" ]]; then
    echo "Expected result count: $github_result_count"
  fi

  local f=""
  local sample=""
  local expected_page=""
  local i=0
  for f in "${generated[@]}"; do
    echo "-- $(basename "$f")"
    pdftotext "$f" - | grep -F -m 3 "$github_repo_full_name" || true
    pdftotext "$f" - | grep -F -m 3 "$github_query" || true
    if [[ "${#generated[@]}" -gt 1 ]]; then
      expected_page="${generated_pages[$i]}"
      pdftotext "$f" - | grep -F -m 1 "page=$expected_page" || true
    fi
    pdftotext "$f" - | grep -E -m 10 '[0-9]+ Open [0-9]+ Closed|#[0-9]+ by ' || true
    i=$((i + 1))
  done

  if [[ "${#generated[@]}" -gt 1 ]]; then
    echo "==> Per-page distinctness sample"
    for f in "${generated[@]}"; do
      sample="$(pdftotext "$f" - | grep -E -m 3 '#[0-9]+ by ' | tr '\n' ' ' || true)"
      printf '%s: %s\n' "$(basename "$f")" "$sample"
    done
  fi

  if [[ "$merge" -eq 1 && -n "${merged:-}" ]]; then
    echo "-- $(basename "$merged")"
    pdftotext "$merged" - | grep -F -m 3 "$github_repo_full_name" || true
    pdftotext "$merged" - | grep -F -m 3 "$github_query" || true
    pdftotext "$merged" - | grep -E -m 10 '[0-9]+ Open [0-9]+ Closed|#[0-9]+ by ' || true
    if [[ "${#generated[@]}" -gt 1 ]]; then
      echo "==> Merged PDF first/last page samples"
      local first_sample=""
      local last_sample=""
      local last_index=$((${#generated[@]} - 1))
      first_sample="$(pdftotext "${generated[0]}" - | grep -E -m 3 '#[0-9]+ by ' | tr '\n' ' ' || true)"
      last_sample="$(pdftotext "${generated[$last_index]}" - | grep -E -m 3 '#[0-9]+ by ' | tr '\n' ' ' || true)"
      printf 'first source page: %s\n' "$first_sample"
      printf 'last source page: %s\n' "$last_sample"
    fi
  fi
}

validate_github_pr_exports

echo "==> Export summary"
echo "Output directory: $out_dir"
if [[ -n "$github_repo_full_name" ]]; then
  echo "Repository: $github_repo_full_name"
fi
if [[ -n "$github_query" ]]; then
  echo "Query: $github_query"
fi
if [[ -n "$github_result_count" ]]; then
  echo "Result count: $github_result_count"
fi
if [[ -n "$pages" ]]; then
  echo "Page range: $pages"
fi
echo "Per-page PDFs:"
printf '  %s\n' "${generated[@]}"
if [[ "$merge" -eq 1 && -n "${merged:-}" ]]; then
  echo "Merged PDF: $merged"
  pdfinfo "$merged" | grep -E '^(Pages)' || true
fi
