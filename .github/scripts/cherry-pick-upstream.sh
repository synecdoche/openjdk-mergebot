#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HISTORY_FILE="$SCRIPT_DIR/jvmci-merge-history.json"
SOURCE_BRANCH="upstream/master"

cd jdk

if [ ! -f "$HISTORY_FILE" ]; then
    echo '{"cherry_picks": {}, "conflicts": {}}' > "$HISTORY_FILE"
fi

TEMP_HISTORY=".git/tmp-merge-history.json"
cp "$HISTORY_FILE" "$TEMP_HISTORY"

mapfile -t COMMITS < <(git log --reverse --format="%H" "HEAD..${SOURCE_BRANCH}")

echo "Commits to cherry-pick: ${#COMMITS[@]}"

if [ ${#COMMITS[@]} -eq 0 ]; then
    echo "No commits to cherry-pick. Already up to date."
    rm -f "$TEMP_HISTORY"
    exit 0
fi

for COMMIT in "${COMMITS[@]}"; do
    SUBJECT=$(git log -1 --format="%s" "$COMMIT")
    echo "Cherry-picking $COMMIT: $SUBJECT"

    if git cherry-pick --allow-empty "$COMMIT" 2>/dev/null; then
        NEW_COMMIT=$(git rev-parse HEAD)
        echo "  Success: $NEW_COMMIT"

        UPDATED=$(jq --arg src "$COMMIT" --arg dst "$NEW_COMMIT" \
            '.cherry_picks[$src] = $dst' "$TEMP_HISTORY")
        echo "$UPDATED" > "$TEMP_HISTORY"
    else
        echo "  Conflict detected, resolving with openjdk-keep-jvmci-alive's code..."

        CONFLICT_DIFF=$(git diff -U5)

        git checkout --ours .
        git add -A

        if ! git -c core.editor=true cherry-pick --continue 2>/dev/null; then
            git commit --allow-empty --no-edit
        fi

        NEW_COMMIT=$(git rev-parse HEAD)
        echo "  Resolved: $NEW_COMMIT"

        UPDATED=$(jq --arg src "$COMMIT" --arg dst "$NEW_COMMIT" \
            '.cherry_picks[$src] = $dst' "$TEMP_HISTORY")
        echo "$UPDATED" > "$TEMP_HISTORY"

        UPDATED=$(jq --arg src "$COMMIT" --arg diff "$CONFLICT_DIFF" \
            '.conflicts[$src] = $diff' "$TEMP_HISTORY")
        echo "$UPDATED" > "$TEMP_HISTORY"
    fi
done

cp "$TEMP_HISTORY" "$HISTORY_FILE"
rm -f "$TEMP_HISTORY"

echo ""
echo "Done. Cherry-picked ${#COMMITS[@]} commits."
