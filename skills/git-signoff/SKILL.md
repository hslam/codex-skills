---
name: git-signoff
description: "Use when creating, amending, rebasing, cherry-picking, squashing, merging, or otherwise rewriting Git commits in repositories that require Signed-off-by trailers. Ensures every affected commit carries the required trailer and verifies the result before finishing."
---

# Git Signoff

## Requirement

Every commit produced or rewritten by the task must include a `Signed-off-by` trailer that matches the current Git committer identity for that repository.

Compute the expected trailer from Git before committing or validating:

```bash
signoff_identity="$(git var GIT_COMMITTER_IDENT | sed -E 's/ [0-9]+ [-+][0-9]+$//')"
signoff_trailer="Signed-off-by: $signoff_identity"
```

Do not assume a personal name or email. Always derive the identity from the repository's active Git configuration.

This applies to ordinary commits and to history-changing operations such as amend, rebase, cherry-pick, squash/fixup, merge commits, revert commits, and conflict-resolution commits.

## Workflow

1. Before changing history, inspect the current branch and worktree:

```bash
git status --short
git branch --show-current
git rev-parse --abbrev-ref --symbolic-full-name @{u}
```

If there is no upstream, choose an explicit base only when it is clear from context. Otherwise ask before rebasing or validating a commit range.

2. Prefer signoff-aware commands when creating commits:

```bash
git commit -s -m "Subject"
git commit --amend -s --no-edit
git cherry-pick -s <commit>
git revert -s <commit>
git merge --signoff <branch>
git rebase --signoff <base>
```

If the local Git identity might not produce the required exact trailer, amend with `git interpret-trailers` and verify.

3. After any operation that creates or rewrites commits, validate every affected commit, not just `HEAD`.

For a single commit:

```bash
signoff_identity="$(git var GIT_COMMITTER_IDENT | sed -E 's/ [0-9]+ [-+][0-9]+$//')"
signoff_trailer="Signed-off-by: $signoff_identity"
git log -1 --format=%B | rg -Fx "$signoff_trailer"
```

For a branch range:

```bash
base="$(git merge-base HEAD @{u})"
signoff_identity="$(git var GIT_COMMITTER_IDENT | sed -E 's/ [0-9]+ [-+][0-9]+$//')"
signoff_trailer="Signed-off-by: $signoff_identity"
git rev-list --reverse "$base"..HEAD |
while read -r commit; do
  git log -1 --format=%B "$commit" |
    rg -Fxq "$signoff_trailer" ||
    echo "$commit"
done
```

The range check prints commits missing the required trailer. No output means the range is signed off.

## Repair

For only `HEAD`, add the trailer without changing the patch:

```bash
tmp_msg="$(mktemp)"
signoff_identity="$(git var GIT_COMMITTER_IDENT | sed -E 's/ [0-9]+ [-+][0-9]+$//')"
git log -1 --format=%B |
  git interpret-trailers --if-exists addIfDifferent \
    --trailer "Signed-off-by: $signoff_identity" > "$tmp_msg"
git commit --amend -F "$tmp_msg"
rm -f "$tmp_msg"
```

For multiple local commits, use an interactive rebase with an `exec` step that amends each picked commit:

```bash
base="$(git merge-base HEAD @{u})"
GIT_SEQUENCE_EDITOR=: git rebase -i --exec 'tmp_msg="$(mktemp)" && signoff_identity="$(git var GIT_COMMITTER_IDENT | sed -E "s/ [0-9]+ [-+][0-9]+$//")" && git log -1 --format=%B | git interpret-trailers --if-exists addIfDifferent --trailer "Signed-off-by: $signoff_identity" > "$tmp_msg" && git commit --amend -F "$tmp_msg" && rm -f "$tmp_msg"' "$base"
```

After repair, rerun the range validation.

## Notes

- Do not use `--no-verify` to bypass signoff checks unless the user explicitly asks and understands the policy impact.
- Do not rewrite commits that are not part of the current task unless the user asks.
- If a rebase, cherry-pick, or merge stops for conflicts, resolve conflicts first, continue the operation, then rerun signoff validation for the affected range.
