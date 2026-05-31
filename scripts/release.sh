#!/bin/bash
# Release script for Catalyst.
#
# On every push to main:
#   - Bump the patch version in .claude-plugin/plugin.json.
#   - Commit the bump with [skip ci] and push it back to main.
#   - Tag the bump commit v$NEW_VERSION and push the tag.
#   - GitHub Actions then creates a GitHub Release from the tag.
#
# Loop prevention: bump commits include [skip ci] in the subject so the
# release workflow skips them. A maintainer who wants a minor or major
# bump should edit plugin.json directly; the next merge continues
# patch-bumping from whatever was set.
#
# Adapted from hevoio/hevo-ai-plugin (CircleCI) for GitHub Actions.

set -euo pipefail

PLUGIN_JSON=".claude-plugin/plugin.json"
BRANCH="${GITHUB_REF_NAME:-main}"
MAX_PUSH_RETRIES=3

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not installed." >&2
  exit 1
fi

# Skip if the head commit is itself a CI bump. Squash-merge commit bodies
# may quote "[skip ci]" descriptively, so only inspect the subject line.
LAST_COMMIT_SUBJECT=$(git log -1 --pretty=%s)
if echo "$LAST_COMMIT_SUBJECT" | grep -qF "[skip ci]"; then
  echo "Last commit subject contains [skip ci] — assuming CI bump, nothing to do."
  echo "skipped=true" >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi

bump_and_push() {
  # Defensive identity: release.yml configures github-actions[bot], but ensure
  # a committer is set if this is ever run in a bare environment. The bot
  # identity also satisfies the release workflow's committer-based loop guard.
  if ! git config user.email >/dev/null 2>&1; then
    git config user.name "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  fi

  git fetch origin "$BRANCH"
  git reset --hard "origin/$BRANCH"

  CURRENT_VERSION=$(jq -r '.version' "$PLUGIN_JSON")

  if [ -z "$CURRENT_VERSION" ] || [ "$CURRENT_VERSION" = "null" ]; then
    echo "ERROR: .version is missing or null in $PLUGIN_JSON" >&2
    exit 1
  fi
  if ! [[ "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: $PLUGIN_JSON version '$CURRENT_VERSION' is not a plain MAJOR.MINOR.PATCH triple — refusing to auto-bump." >&2
    exit 1
  fi

  IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
  NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"
  TAG="v${NEW_VERSION}"

  echo "Bumping version: $CURRENT_VERSION -> $NEW_VERSION"

  jq --arg v "$NEW_VERSION" '.version = $v' "$PLUGIN_JSON" > "$PLUGIN_JSON.tmp"
  mv "$PLUGIN_JSON.tmp" "$PLUGIN_JSON"

  git add "$PLUGIN_JSON"
  git commit -m "chore: bump version to ${NEW_VERSION} [skip ci]"
  git tag -a "$TAG" -m "Release ${NEW_VERSION}"

  # --no-verify: the CI runner has no local git hooks; skips an unnecessary
  # hook-load step. Do NOT copy this into a dev environment where pre-push
  # hooks are meaningful.
  git push origin "HEAD:${BRANCH}" --no-verify
  git push origin "$TAG" --no-verify

  # Surface the version and tag for downstream workflow steps.
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "version=${NEW_VERSION}"
      echo "tag=${TAG}"
      echo "skipped=false"
    } >> "$GITHUB_OUTPUT"
  fi
  return 0
}

attempt=1
while [ "$attempt" -le "$MAX_PUSH_RETRIES" ]; do
  if bump_and_push; then
    echo "Bumped to ${NEW_VERSION:-?} and pushed tag ${TAG:-?}"
    exit 0
  fi
  echo "Push attempt $attempt failed (likely non-fast-forward). Retrying..."
  attempt=$((attempt + 1))
done

echo "ERROR: failed to bump and push after $MAX_PUSH_RETRIES attempts." >&2
exit 1
