#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Safe publish to the public Pluralsight course repo.
#
# Every commit on the published branch is rewritten so that BOTH author and
# committer metadata become "Rupesh Tiwari <330383+rupeshtiwari@users.noreply
# .github.com>". The original (Claude / rupesh-india / roopkt2 / noreply
# @anthropic.com / any other) identity is dropped before the push hits the
# public repo's main branch.
#
# Usage:
#   scripts/publish_public_as_rupesh.sh [<source-branch>]
#
# Example:
#   scripts/publish_public_as_rupesh.sh claude/admiring-meitner-Z7gUH
#
# Never run:
#   git push pluralsight <branch>:main --force
# That bypasses the author rewrite and can republish the wrong identity.
# ─────────────────────────────────────────────────────────────────────────────

TARGET_NAME="Rupesh Tiwari"
TARGET_EMAIL="330383+rupeshtiwari@users.noreply.github.com"
PUBLIC_REMOTE="pluralsight"
PUBLIC_REPO="rupeshtiwari/pluralsight-designing-data-systems-llms"
SOURCE_BRANCH="${1:-$(git branch --show-current)}"
PUBLISH_BRANCH="publish-rupesh-clean"

echo "Checking public remote..."
REMOTE_URL="$(git remote get-url "$PUBLIC_REMOTE")"

case "$REMOTE_URL" in
  *"$PUBLIC_REPO"* )
    echo "Public remote is correct: $REMOTE_URL"
    ;;
  * )
    echo "ERROR: Remote '$PUBLIC_REMOTE' does not point to $PUBLIC_REPO"
    echo "Current value: $REMOTE_URL"
    exit 1
    ;;
esac

echo "Setting Git author for this repo..."
git config user.name "$TARGET_NAME"
git config user.email "$TARGET_EMAIL"

echo "Fetching latest refs..."
git fetch origin
git fetch "$PUBLIC_REMOTE"

echo "Creating clean publish branch from: $SOURCE_BRANCH"
git switch -C "$PUBLISH_BRANCH" "$SOURCE_BRANCH"

echo "Rewriting author and committer to Rupesh..."
FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f --env-filter '
GIT_AUTHOR_NAME="Rupesh Tiwari"
GIT_AUTHOR_EMAIL="330383+rupeshtiwari@users.noreply.github.com"
GIT_COMMITTER_NAME="Rupesh Tiwari"
GIT_COMMITTER_EMAIL="330383+rupeshtiwari@users.noreply.github.com"
export GIT_AUTHOR_NAME
export GIT_AUTHOR_EMAIL
export GIT_COMMITTER_NAME
export GIT_COMMITTER_EMAIL
' "$PUBLISH_BRANCH"

echo "Verifying commit authors..."
BAD_AUTHOR="$(git log "$PUBLISH_BRANCH" --format="%an <%ae>" | grep -v "^$TARGET_NAME <$TARGET_EMAIL>$" | head -1 || true)"

if [ -n "$BAD_AUTHOR" ]; then
  echo "ERROR: Wrong author still exists:"
  echo "$BAD_AUTHOR"
  exit 1
fi

echo "Top commits after cleanup:"
git --no-pager log "$PUBLISH_BRANCH" -10 --format="%h %an <%ae> | %cn <%ce> | %s"

echo "Pushing clean history to public repo main..."
git push --force-with-lease "$PUBLIC_REMOTE" "$PUBLISH_BRANCH:main"

echo ""
echo "Done. Public repo main now uses Rupesh Tiwari identity."
