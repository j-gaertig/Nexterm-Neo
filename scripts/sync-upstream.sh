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
# Keep our removal of landing/ and docs/ on upstream merges (see .gitattributes).
git config merge.ours.driver true

# Paths we own and always keep on upstream merges. Git merge drivers do not
# apply to deleted files, so these are auto-resolved in the merge step below.
readonly ours_paths=(
  "landing/"
  "docs/"
  "crowdin.yml"
  "CODE_OF_CONDUCT.md"
  ".github/workflows/mobile-v2-apk.yml"
)

is_ours_path() {
  local path="$1"
  local entry
  for entry in "${ours_paths[@]}"; do
    if [[ "$entry" == */ ]]; then
      [[ "$path" == "$entry"* ]] && return 0
    elif [[ "$path" == "$entry" ]]; then
      return 0
    fi
  done
  return 1
}

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
  unmerged=$(git diff --name-only --diff-filter=U || true)

  if [[ -z "$unmerged" ]]; then
    git merge --abort >/dev/null 2>&1 || true
    echo "Git merge failed for a reason other than file conflicts (exit $merge_status)." >&2
    exit "$merge_status"
  fi

  all_ours=true
  while IFS= read -r path; do
    if ! is_ours_path "$path"; then
      all_ours=false
      break
    fi
  done <<< "$unmerged"

  if [[ "$all_ours" != "true" ]]; then
    git merge --abort
    error_message="ERROR: Upstream changes conflict with main. No changes were pushed. Resolve the conflicts manually, then rerun this workflow."
    echo "$error_message" >&2
    append_summary "## Upstream sync failed: $error_message"
    exit 1
  fi

  echo "Conflicts are limited to Neo-owned paths. Resolving in our favor."
  while IFS= read -r path; do
    if git cat-file -e "HEAD:$path" 2>/dev/null; then
      git checkout --ours -- "$path"
      git add -- "$path"
    else
      git rm -- "$path" >/dev/null
    fi
  done <<< "$unmerged"

  git commit --no-edit
  git push origin "HEAD:refs/heads/$target_branch"
  echo "Merged upstream commits and pushed to $target_branch (Neo-owned paths kept)."
  append_summary "Merged upstream commits from \`gnmyt/Nexterm:main\` into \`$target_branch\` (conflicts in Neo-owned paths auto-resolved)."
  exit 0
fi
