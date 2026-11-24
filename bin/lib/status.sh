#!/usr/bin/env bash
# status.sh — progress of the specs under spec.dir (repo store).

status_render_bar() {
  local progress="$1" filled empty bar="" i=0
  filled=$((progress * 12 / 100)); empty=$((12 - filled))
  while [ $i -lt $filled ]; do bar="${bar}█"; i=$((i + 1)); done
  i=0
  while [ $i -lt $empty ]; do bar="${bar}░"; i=$((i + 1)); done
  printf '%s' "$bar"
}

status_scan() {
  local filter="${1:-}" json_mode="${2:-0}"
  local store dir
  store=$(cfg_get_or "spec.store" "repo")
  dir=$(cfg_get_or "spec.dir" "docs/specs")

  if [ "$store" = "obsidian" ]; then
    echo ""
    echo "  Specs live in the Obsidian vault at \$OBSIDIAN_VAULT_PATH, folder $dir (spec.store: obsidian). Check them there."
    echo ""
    return 0
  fi

  if [ "$store" != "repo" ]; then
    echo ""
    echo "  Specs live in the tracker (spec.store: $store). Check them there."
    echo ""
    return 0
  fi

  local found=0 first=1 f id title state done total progress
  [ "$json_mode" = "1" ] && printf '[' || echo ""
  for f in "$CWD/$dir"/*.md; do
    [ -f "$f" ] || continue
    id=$(basename "$f" .md)
    [ -z "$filter" ] || [ "$id" = "$filter" ] || continue
    title=$(grep -m1 '^# ' "$f" | sed 's/^# //')
    state=$(grep -m1 -oE 'Status:[[:space:]]*[a-z]+' "$f" | sed 's/Status:[[:space:]]*//')
    done=$(grep -cE '^- \[[xX]\]' "$f" || true)
    total=$(grep -cE '^- \[[ xX]\]' "$f" || true)
    progress=0
    [ "$total" -gt 0 ] && progress=$((done * 100 / total))
    if [ "$json_mode" = "1" ]; then
      [ "$first" = "0" ] && printf ','
      printf '{%s, %s, %s, %s, %s}' "$(json_kv id "$id")" "$(json_kv title "$title")" \
        "$(json_kv status "${state:-draft}")" "$(json_kv_raw done "$done")" "$(json_kv_raw total "$total")"
      first=0
    else
      printf '  %-24s %-36s %-9s %s %d/%d\n' "$id" "$title" "${state:-draft}" "$(status_render_bar "$progress")" "$done" "$total"
    fi
    found=$((found + 1))
  done
  if [ "$json_mode" = "1" ]; then
    printf ']\n'
  else
    if [ "$found" -eq 0 ]; then
      if [ -n "$filter" ]; then echo "  No spec named $filter in $dir"; else echo "  No specs in $dir. Run /trc.plan to write one."; fi
    fi
    echo ""
  fi
}
