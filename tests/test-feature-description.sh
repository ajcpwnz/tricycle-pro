#!/usr/bin/env bash
# derive-branch-name.sh and create-new-feature.sh keep apostrophes, quotes,
# backticks and newlines in the description, and refuse whitespace-only input.
set -euo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/core/scripts/bash"

DESC=$(cat <<'TASK'
  TRI-2355 — Create link stays enabled when its required Name is empty.

With Name empty, the Create link is enabled while the source's action is disabled.
Keep "Shared by" and don't create an extra Source. Read `ShareLinks.tsx`.
TASK
)
EXPECTED="TRI-2355-link-name-validation"

DERIVED=$(bash "$BASH_DIR/derive-branch-name.sh" --style issue-number --prefix TRI --short-name link-name-validation "$DESC")
[ "$DERIVED" = "$EXPECTED" ] || { echo "FAIL: derived '$DERIVED'"; exit 1; }
AUTO=$(bash "$BASH_DIR/derive-branch-name.sh" --style issue-number --prefix TRI "$DESC")
[[ "$AUTO" == TRI-2355-* && "$AUTO" != *$'\n'* ]] || { echo "FAIL: auto name '$AUTO'"; exit 1; }

for S in derive-branch-name.sh create-new-feature.sh; do
  if bash "$BASH_DIR/$S" $' \t\n\r ' >/dev/null 2>&1; then
    echo "FAIL: $S accepts a whitespace-only description"; exit 1
  fi
done

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.trc/scripts/bash"
cp "$BASH_DIR/derive-branch-name.sh" "$BASH_DIR/create-new-feature.sh" "$BASH_DIR/common.sh" "$T/.trc/scripts/bash/"
git -C "$T" init -q
git -C "$T" -c user.name=t -c user.email=t@example.test commit --allow-empty -qm base
OUT=$(cd "$T" && bash .trc/scripts/bash/create-new-feature.sh "$DESC" --json --no-base-refresh --style issue-number --prefix TRI --short-name link-name-validation)
printf '%s' "$OUT" | python3 -c 'import json,sys; v=json.load(sys.stdin); assert v["BRANCH_NAME"]=="TRI-2355-link-name-validation", v; assert v["FEATURE_NUM"]=="TRI-2355", v'
[ "$(git -C "$T" branch --show-current)" = "$EXPECTED" ] || { echo "FAIL: branch not created"; exit 1; }
[ ! -e "$T/specs" ] || { echo "FAIL: create-new-feature wrote specs/"; exit 1; }
echo "feature-description: OK"
