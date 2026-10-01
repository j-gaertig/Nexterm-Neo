#!/usr/bin/env bash
set -euo pipefail

readonly upstream_url="https://github.com/gnmyt/Nexterm.git"
readonly upstream_branch="main"
readonly target_branch="main"

append_summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"
  fi
}

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# Always compare and merge against the latest target branch state.
git fetch --no-tags origin "$target_branch"
git checkout -B "$target_branch" "origin/$target_branch"

git remote add upstream "$upstream_url" 2>/dev/null || git remote set-url upstream "$upstream_url"
git fetch --no-tags upstream "$upstream_branch"

upstream_commits=$(git rev-list --count "HEAD..upstream/$upstream_branch")
if [[ "$upstream_commits" == "0" ]]; then
  echo "No new commits from gnmyt/Nexterm:main. Skipping."
  append_summary "No new commits from \`gnmyt/Nexterm:main\`; nothing to merge."
  exit 0
fi

echo "Found $upstream_commits upstream commit(s). Checking whether they merge cleanly."
if git merge --no-edit "upstream/$upstream_branch"; then
  git push origin "HEAD:refs/heads/$target_branch"
  echo "Merged upstream commits and pushed to $target_branch."
  append_summary "Merged upstream commits from \`gnmyt/Nexterm:main\` into \`$target_branch\`."
  exit 0
else
  merge_status=$?
  if [[ -n "$(git ls-files --unmerged)" ]]; then
    git merge --abort
    error_message="ERROR: Upstream changes conflict with main. No changes were pushed. Resolve the conflicts manually, then rerun this workflow."
    echo "$error_message" >&2
    append_summary "## Upstream sync failed: $error_message"
    exit 1
  fi

  git merge --abort >/dev/null 2>&1 || true
  echo "Git merge failed for a reason other than file conflicts (exit $merge_status)." >&2
  exit "$merge_status"
fi
