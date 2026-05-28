#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fake_bin="$tmp/bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "api" ]]; then
  echo "unexpected gh command: $*" >&2
  exit 1
fi
shift
args="$*"

case "$args" in
  "user --jq .login")
    echo "hslam"
    ;;
  *"search/issues"*)
    echo "63"
    ;;
  "repos/tidbcloud/tidb-operator-cse --jq .default_branch")
    echo "serverless-on-release-1.4"
    ;;
  *"repos/tidbcloud/tidb-operator-cse/commits?"*)
    for i in $(seq 1 70); do
      printf '%040x\n' "$i"
    done
    ;;
  *)
    echo "unexpected gh api args: $args" >&2
    exit 1
    ;;
esac
FAKE_GH
chmod +x "$fake_bin/gh"

export PATH="$fake_bin:$PATH"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'Expected output to contain %q\nActual output:\n%s\n' "$needle" "$haystack" >&2
    exit 1
  fi
}

bash -n "$repo_root/skills/chrome-print-pdf/scripts/print_chrome_pdf.sh"
bash -n "$repo_root/skills/chrome-print-pdf/scripts/export_github_prs_pdf.sh"
bash -n "$repo_root/skills/chrome-print-pdf/scripts/export_github_commits_pdf.sh"

forbidden_selector="document.querySelector('a[href*=\\\"/pull/\\\"]')"
if rg -F "$forbidden_selector" "$repo_root/skills/chrome-print-pdf/scripts/print_chrome_pdf.sh" >/dev/null; then
  echo "print_chrome_pdf.sh contains AppleScript-breaking embedded double quotes in readiness JavaScript" >&2
  exit 1
fi

print_plan="$("$repo_root/skills/chrome-print-pdf/scripts/print_chrome_pdf.sh" \
  --url "https://github.com/tidbcloud/tidb-operator-cse/pulls?q=is%3Apr" \
  --out-dir "$tmp/out" \
  --name "demo" \
  --pages 1-2 \
  --merge \
  --repo-subdir \
  --page-settle-seconds 2 \
  --print-retries 3 \
  --dry-run)"
assert_contains "$print_plan" "Mode: dry-run"
assert_contains "$print_plan" "Page settle seconds: 2"
assert_contains "$print_plan" "Print retries: 3"
assert_contains "$print_plan" "demo-page-2.pdf"

pr_plan="$("$repo_root/skills/chrome-print-pdf/scripts/export_github_prs_pdf.sh" \
  --repo tidbcloud/tidb-operator-cse \
  --out-dir "$tmp/pdf" \
  --dry-run)"
assert_contains "$pr_plan" "Mode: dry-run"
assert_contains "$pr_plan" "Author filter: hslam"
assert_contains "$pr_plan" "State filter: closed"
assert_contains "$pr_plan" "Result count: 63"
assert_contains "$pr_plan" "Page range: 1-3"
assert_contains "$pr_plan" "Audit JSON: $tmp/pdf/tidb-operator-cse/tidb-operator-cse-closed-prs-hslam-audit.json"
[[ ! -e "$tmp/pdf/tidb-operator-cse" ]]

pr_all_plan="$("$repo_root/skills/chrome-print-pdf/scripts/export_github_prs_pdf.sh" \
  --repo "https://github.com/tidbcloud/tidb-operator-cse/pulls?page=1&q=is%3Apr" \
  --out-dir "$tmp/pdf" \
  --dry-run)"
assert_contains "$pr_all_plan" "Author filter: none"
assert_contains "$pr_all_plan" "Author filter source: query has no author filter"
assert_contains "$pr_all_plan" "State filter: all"
assert_contains "$pr_all_plan" "State filter source: query has no state filter"
assert_contains "$pr_all_plan" "Audit JSON: $tmp/pdf/tidb-operator-cse/tidb-operator-cse-all-prs-audit.json"
[[ ! -e "$tmp/pdf/tidb-operator-cse" ]]

commit_plan="$("$repo_root/skills/chrome-print-pdf/scripts/export_github_commits_pdf.sh" \
  --repo tidbcloud/tidb-operator-cse \
  --out-dir "$tmp/pdf" \
  --dry-run)"
assert_contains "$commit_plan" "Mode: dry-run"
assert_contains "$commit_plan" "Author filter: hslam"
assert_contains "$commit_plan" "Commit count: 70"
assert_contains "$commit_plan" "Estimated page range: 1-2"
assert_contains "$commit_plan" "Audit JSON: $tmp/pdf/tidb-operator-cse/tidb-operator-cse-commits-hslam-audit.json"
[[ ! -e "$tmp/pdf/tidb-operator-cse" ]]

commit_all_plan="$("$repo_root/skills/chrome-print-pdf/scripts/export_github_commits_pdf.sh" \
  --repo tidbcloud/tidb-operator-cse \
  --out-dir "$tmp/pdf" \
  --all-authors \
  --dry-run)"
assert_contains "$commit_all_plan" "Author filter: none"
assert_contains "$commit_all_plan" "Author filter source: --all-authors"
assert_contains "$commit_all_plan" "Target URL: https://github.com/tidbcloud/tidb-operator-cse/commits/serverless-on-release-1.4"
assert_contains "$commit_all_plan" "Audit JSON: $tmp/pdf/tidb-operator-cse/tidb-operator-cse-commits-all-authors-audit.json"
[[ ! -e "$tmp/pdf/tidb-operator-cse" ]]

if "$repo_root/skills/chrome-print-pdf/scripts/export_github_commits_pdf.sh" \
  --repo tidbcloud/tidb-operator-cse \
  --out-dir "$tmp/pdf" \
  --author hslam \
  --all-authors \
  --dry-run >/dev/null 2>&1; then
  echo "--all-authors unexpectedly succeeded with --author" >&2
  exit 1
fi

"$repo_root/scripts/install.sh" --dest "$tmp/skills" chrome-print-pdf >/dev/null
"$repo_root/scripts/install.sh" --dest "$tmp/skills" --check chrome-print-pdf >/dev/null

echo "chrome-print-pdf tests passed"
