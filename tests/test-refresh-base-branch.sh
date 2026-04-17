#!/usr/bin/env bash
# TRI-32: covers refresh_base_branch inside create-new-feature.sh via a
# bare-repo fixture. Exercises every path from quickstart.md cases (a)-(i).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CREATE="$REPO_ROOT/core/scripts/bash/create-new-feature.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── Fixture helpers ────────────────────────────────────────────────────────

# Build an isolated fixture: bare "origin" + clone + initial "main" commit.
# Each scenario gets its own fixture to avoid cross-contamination.
make_fixture() {
    local name="$1"
    local root="$TMP/$name"
    mkdir -p "$root/origin"
    git init -q --bare "$root/origin"
    git clone -q "$root/origin" "$root/work"
    (
        cd "$root/work"
        git checkout -q -b main 2>/dev/null || git checkout -q main
        printf 'seed\n' > seed.txt
        git add seed.txt
        git -c user.email=fix@test -c user.name=fix commit -q -m "seed"
        git push -q origin main
    )
    printf '%s\n' "$root/work"
}

advance_origin() {
    local work="$1"
    local origin="${work%/*}/origin"
    local stash
    stash=$(mktemp -d)
    git clone -q "$origin" "$stash/scratch"
    (
        cd "$stash/scratch"
        git checkout -q main
        printf 'upstream advance %s\n' "$RANDOM" >> upstream.txt
        git add upstream.txt
        git -c user.email=fix@test -c user.name=fix commit -q -m "upstream advance"
        git push -q origin main
    )
    rm -rf "$stash"
}

# Script expects to find a tricycle.config.yml; use feature-name style so
# we don't need --issue each invocation.
write_config() {
    local work="$1"
    cat > "$work/tricycle.config.yml" <<'YAML'
project:
  name: fixture
  type: single-app
  package_manager: npm
  base_branch: main
push:
  pr_target: main
YAML
}

# ── Case (a): stale local main is fast-forwarded ──────────────────────────

work=$(make_fixture case_a)
write_config "$work"
advance_origin "$work"      # origin/main is now ahead of local main
pre_local=$(git -C "$work" rev-parse main)
pre_origin=$(git -C "$work" ls-remote origin main | awk '{print $1}')
[ "$pre_local" != "$pre_origin" ] || { echo "FAIL [a]: fixture setup — local should lag origin"; exit 1; }

out=$(cd "$work" && bash "$CREATE" "test stale" --style feature-name --short-name "test-stale" --json 2>&1 1>/dev/null || true)
post_local=$(git -C "$work" rev-parse main)
[ "$post_local" = "$pre_origin" ] || { echo "FAIL [a]: local main not fast-forwarded. pre=$pre_local origin=$pre_origin post=$post_local"; exit 1; }
# The advance-detection line must have fired on stderr.
printf '%s' "$out" | grep -q 'fast-forwarded to' || { echo "FAIL [a]: expected fast-forward log; got: $out"; exit 1; }
# New branch root must equal fresh origin SHA.
branch_sha=$(git -C "$work" rev-parse test-stale)
[ "$branch_sha" = "$pre_origin" ] || { echo "FAIL [a]: new branch SHA != origin tip"; exit 1; }

# ── Case (b): up-to-date local main is silent ─────────────────────────────

work=$(make_fixture case_b)
write_config "$work"
out=$(cd "$work" && bash "$CREATE" "test fresh" --style feature-name --short-name "test-fresh" --json 2>&1 1>/dev/null || true)
if printf '%s' "$out" | grep -q 'fast-forwarded to'; then
    echo "FAIL [b]: expected no advance-detection line on an up-to-date main; got: $out"; exit 1
fi

# ── Case (c): dirty base halts with exit 20 ───────────────────────────────

work=$(make_fixture case_c)
write_config "$work"
printf 'dirty\n' >> "$work/seed.txt"    # modify tracked file without committing
set +e
(cd "$work" && bash "$CREATE" "dirty test" --style feature-name --short-name "dirty-test" --json >/tmp/.dirty_out 2>/tmp/.dirty_err)
rc=$?
set -e
if [ "$rc" -ne 20 ]; then
    echo "FAIL [c]: expected exit 20, got $rc"; cat /tmp/.dirty_err; exit 1
fi
grep -q 'Working tree on main has uncommitted changes' /tmp/.dirty_err \
    || { echo "FAIL [c]: missing dirty-tree error message"; cat /tmp/.dirty_err; exit 1; }
# Branch must not exist.
git -C "$work" branch --list dirty-test | grep -q . \
    && { echo "FAIL [c]: branch created despite dirty-tree halt"; exit 1; } || true

# ── Case (d): unreachable origin warns, continues with exit 0 ─────────────

work=$(make_fixture case_d)
write_config "$work"
git -C "$work" remote set-url origin "https://127.0.0.1:1/nope.git"
set +e
(cd "$work" && bash "$CREATE" "offline test" --style feature-name --short-name "offline-test" --json >/tmp/.off_out 2>/tmp/.off_err)
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
    echo "FAIL [d]: expected exit 0 (offline degrades gracefully), got $rc"
    cat /tmp/.off_err
    exit 1
fi
grep -q 'origin unreachable' /tmp/.off_err \
    || { echo "FAIL [d]: missing unreachable warning"; cat /tmp/.off_err; exit 1; }
git -C "$work" branch --list offline-test | grep -q . \
    || { echo "FAIL [d]: branch not created after graceful degradation"; exit 1; }

# ── Case (e): divergent local halts with exit 21 ──────────────────────────

work=$(make_fixture case_e)
write_config "$work"
# Diverge: local commit + origin commit.
(
    cd "$work"
    printf 'local-only\n' > local.txt
    git add local.txt
    git -c user.email=fix@test -c user.name=fix commit -q -m "local-only"
)
advance_origin "$work"
set +e
(cd "$work" && bash "$CREATE" "divergent" --style feature-name --short-name "divergent-test" --json >/tmp/.div_out 2>/tmp/.div_err)
rc=$?
set -e
if [ "$rc" -ne 21 ]; then
    echo "FAIL [e]: expected exit 21 on divergent local, got $rc"
    cat /tmp/.div_err
    exit 1
fi
grep -q 'cannot fast-forward' /tmp/.div_err \
    || { echo "FAIL [e]: missing fast-forward error message"; cat /tmp/.div_err; exit 1; }
git -C "$work" branch --list divergent-test | grep -q . \
    && { echo "FAIL [e]: branch created despite FF halt"; exit 1; } || true

# ── Case (f): --no-base-refresh flag skips silently ───────────────────────

work=$(make_fixture case_f)
write_config "$work"
advance_origin "$work"
out=$(cd "$work" && bash "$CREATE" "skip flag" --no-base-refresh --style feature-name --short-name "skip-flag" --json 2>&1 1>/dev/null || true)
if printf '%s' "$out" | grep -q 'fast-forwarded\|origin unreachable'; then
    echo "FAIL [f]: --no-base-refresh should produce no refresh output; got: $out"; exit 1
fi
# Branch exists, rooted at the stale pre-advance SHA.
post_local=$(git -C "$work" rev-parse main)
pre_origin=$(git -C "$work" ls-remote origin main | awk '{print $1}')
[ "$post_local" != "$pre_origin" ] || { echo "FAIL [f]: refresh appears to have run anyway"; exit 1; }

# ── Case (g): TRC_SKIP_BASE_REFRESH=1 env var skips silently ──────────────

work=$(make_fixture case_g)
write_config "$work"
advance_origin "$work"
out=$(cd "$work" && TRC_SKIP_BASE_REFRESH=1 bash "$CREATE" "skip env" --style feature-name --short-name "skip-env" --json 2>&1 1>/dev/null || true)
if printf '%s' "$out" | grep -q 'fast-forwarded\|origin unreachable'; then
    echo "FAIL [g]: TRC_SKIP_BASE_REFRESH=1 should produce no refresh output; got: $out"; exit 1
fi

# ── Case (h): non-git repo — silent no-op ─────────────────────────────────

nogit="$TMP/nogit"
mkdir -p "$nogit/.trc/templates"
cat > "$nogit/tricycle.config.yml" <<'YAML'
project:
  name: nogit
  type: single-app
YAML
# Minimal template so the script can copy it.
printf '# Spec\n' > "$nogit/.trc/templates/spec-template.md"
out=$(cd "$nogit" && bash "$CREATE" "nogit test" --style feature-name --short-name "nogit-test" --json 2>&1 1>/dev/null || true)
if printf '%s' "$out" | grep -q 'fast-forwarded\|origin unreachable'; then
    echo "FAIL [h]: non-git repo should be silent; got: $out"; exit 1
fi

# ── Case (i): chain proxy — two back-to-back kickoffs, origin advances between ─

work=$(make_fixture case_i)
write_config "$work"
# First kickoff.
(cd "$work" && bash "$CREATE" "first ticket" --style feature-name --short-name "first-ticket" --json >/dev/null 2>&1)
first_branch_sha=$(git -C "$work" rev-parse first-ticket)
# Advance origin to simulate ticket 1 merging to main between kickoffs.
advance_origin "$work"
advanced_sha=$(git -C "$work" ls-remote origin main | awk '{print $1}')
# Get back on main so the second kickoff runs the on-base path.
git -C "$work" checkout -q main
# Second kickoff.
(cd "$work" && bash "$CREATE" "second ticket" --style feature-name --short-name "second-ticket" --json >/dev/null 2>&1)
second_branch_sha=$(git -C "$work" rev-parse second-ticket)
[ "$second_branch_sha" = "$advanced_sha" ] \
    || { echo "FAIL [i]: chain-proxy: second ticket not rooted at post-advance origin tip. expected=$advanced_sha got=$second_branch_sha"; exit 1; }
[ "$first_branch_sha" != "$second_branch_sha" ] \
    || { echo "FAIL [i]: chain-proxy: second ticket root matches first ticket (origin advance had no effect)"; exit 1; }

echo "refresh-base-branch: OK"
