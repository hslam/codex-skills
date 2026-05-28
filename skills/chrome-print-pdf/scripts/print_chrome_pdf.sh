#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  print_chrome_pdf.sh --url URL --out-dir DIR --name NAME [--pages N-M] [--merge] [--repo-subdir | --subdir NAME] [--save-click X,Y]

Examples:
  print_chrome_pdf.sh --url "https://github.com/owner/repo/pulls?q=is%3Apr" --out-dir "$HOME/Documents/dev-pdf" --name repo-prs.pdf
  print_chrome_pdf.sh --url "https://github.com/owner/repo/pulls?q=is%3Apr" --out-dir "$HOME/Documents/dev-pdf" --name repo-prs --pages 1-3 --merge --repo-subdir
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) url="$2"; shift 2 ;;
    --out-dir) out_dir="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --pages) pages="$2"; shift 2 ;;
    --merge) merge=1; shift ;;
    --repo-subdir) repo_subdir=1; shift ;;
    --subdir) subdir="$2"; shift 2 ;;
    --save-click) save_click="$2"; shift 2 ;;
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

click_accessible_chrome_save() {
  osascript <<'OSA' >/dev/null 2>&1
with timeout of 2 seconds
  tell application "System Events"
    tell process "Google Chrome"
      set frontmost to true
      click (first button of window 1 whose name is "Save")
    end tell
  end tell
end timeout
OSA
}

press_chrome_print_save() {
  local click_point="$save_click"

  if [[ -n "$click_point" ]]; then
    echo "==> Pressing Chrome Save at override $click_point"
    cliclick m:"$click_point" w:300 dd:. w:200 du:.
    return
  fi

  local x=""
  local y=""
  local w=""
  local h=""
  local bounds=""

  for attempt in 1 2 3; do
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

  if click_accessible_chrome_save; then
    echo "==> Pressed Chrome Save with Accessibility"
    sleep 1.5
    if macos_save_dialog_visible; then
      return
    fi
  fi

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

  press_chrome_print_save
  sleep 1

  echo "==> Saving as $outfile"
  save_macos_pdf_dialog "$file" "$out_dir"

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
