#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/jdk" && pwd)"
HISTORY_FILE="$(cd "$(dirname "$0")" && pwd)/jvmci-merge-history.json"
SOURCE_BRANCH="master"
TARGET_BRANCH="openjdk-keep-jvmci-alive"

cd "$REPO_DIR"

git checkout "$TARGET_BRANCH"

MERGE_BASE=$(git merge-base "$SOURCE_BRANCH" "$TARGET_BRANCH")
echo "Merge base: $MERGE_BASE"

mapfile -t COMMITS < <(git log --reverse --format="%H" "${TARGET_BRANCH}..${SOURCE_BRANCH}")

echo "Commits to cherry-pick: ${#COMMITS[@]}"

if [ ${#COMMITS[@]} -eq 0 ]; then
    echo "No commits to cherry-pick. Branches are up to date."
    if [ ! -f "$HISTORY_FILE" ]; then
        echo '{"cherry_picks": {}, "conflicts": {}}' > "$HISTORY_FILE"
    fi
    exit 0
fi

if [ ! -f "$HISTORY_FILE" ]; then
    echo '{"cherry_picks": {}, "conflicts": {}}' > "$HISTORY_FILE"
fi

for COMMIT in "${COMMITS[@]}"; do
    SUBJECT=$(git log -1 --format="%s" "$COMMIT")
    echo "Cherry-picking $COMMIT: $SUBJECT"

    if git cherry-pick "$COMMIT" 2>/dev/null; then
        NEW_COMMIT=$(git rev-parse HEAD)
        echo "  Success: $NEW_COMMIT"

        CHERRY_PICKS=$(jq --arg src "$COMMIT" --arg dst "$NEW_COMMIT" \
            '.cherry_picks[$src] = $dst' "$HISTORY_FILE")
        echo "$CHERRY_PICKS" > "$HISTORY_FILE"
    else
        echo "  Conflict detected, resolving with master's changes..."

        CONFLICT_DIFF=$(git diff -U5)

        git checkout --ours .
        git add -A
        git -c core.editor=true cherry-pick --continue

        NEW_COMMIT=$(git rev-parse HEAD)
        echo "  Resolved: $NEW_COMMIT"

        CHERRY_PICKS=$(jq --arg src "$COMMIT" --arg dst "$NEW_COMMIT" \
            '.cherry_picks[$src] = $dst' "$HISTORY_FILE")
        echo "$CHERRY_PICKS" > "$HISTORY_FILE"

        CONFLICTS=$(jq --arg src "$COMMIT" --arg diff "$CONFLICT_DIFF" \
            '.conflicts[$src] = $diff' "$HISTORY_FILE")
        echo "$CONFLICTS" > "$HISTORY_FILE"
    fi
done

echo ""
echo "Done. Cherry-picked ${#COMMITS[@]} commits."
echo "History written to: $HISTORY_FILE"
