#!/usr/bin/env bash
# helpers.sh — Shared utilities: config access, checksums, file ops, prompts, lock file

# ─── Output ──────────────────────────────────────────────────────────────────

info() { echo "  $*"; }
error() { echo "Error: $*" >&2; }

# ─── SHA-256 ─────────────────────────────────────────────────────────────────

SHA_CMD=""

detect_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    SHA_CMD="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    SHA_CMD="shasum -a 256"
  else
    error "No SHA-256 tool found (need sha256sum or shasum)"
    exit 1
  fi
}

sha256_str() {
  printf '%s' "$1" | $SHA_CMD | cut -c1-16
}

sha256_file() {
  $SHA_CMD "$1" | cut -c1-16
}

# ─── Config Access ───────────────────────────────────────────────────────────
# CONFIG_DATA is a newline-delimited string of KEY=VALUE pairs set by load_config

CONFIG_DATA=""

# Prefixes eligible for local override (whitelist)
OVERRIDABLE_PREFIXES=(
  "push."
  "qa."
  "worktree."
  "workflow.blocks."
  "stealth."
)

# merge_config_data BASE_DATA OVERRIDE_DATA
# Merges two flat key=value datasets. Override scalars win.
# Override arrays replace base arrays entirely (detected by numeric index).
merge_config_data() {
  local base_data="$1" override_data="$2"
  [ -z "$override_data" ] && { printf '%s' "$base_data"; return; }

  # Collect array prefixes from override (patterns like "prefix.N." or "prefix.N=")
  local arr_prefixes=""
  arr_prefixes=$(printf '%s\n' "$override_data" | sed -n 's/^\(.*\)\.[0-9][0-9]*[.=].*$/\1/p' | sort -u)

  # Start with base data, stripping any keys that override will replace
  local merged=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local key="${line%%=*}"

    # Check if this key is directly overridden (scalar)
    if printf '%s\n' "$override_data" | grep -q "^${key}="; then
      continue
    fi

    # Check if this key belongs to an array prefix being replaced
    local dominated=0
    if [ -n "$arr_prefixes" ]; then
      while IFS= read -r prefix; do
        [ -z "$prefix" ] && continue
        case "$key" in
          "${prefix}".*)  dominated=1; break ;;
        esac
      done <<< "$arr_prefixes"
    fi

    [ "$dominated" -eq 1 ] && continue
    merged="${merged:+${merged}
}${line}"
  done <<< "$base_data"

  # Append all override entries
  if [ -n "$merged" ]; then
    printf '%s\n%s' "$merged" "$override_data"
  else
    printf '%s' "$override_data"
  fi
}

# validate_override OVERRIDE_DATA
# Checks override keys against OVERRIDABLE_PREFIXES. Warns on non-overridable keys.
# Prints only valid override lines to stdout.
validate_override() {
  local override_data="$1"
  [ -z "$override_data" ] && return 0

  local valid_lines=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local key="${line%%=*}"
    local allowed=0

    for prefix in "${OVERRIDABLE_PREFIXES[@]}"; do
      case "$key" in
        "${prefix}"*) allowed=1; break ;;
      esac
    done

    if [ "$allowed" -eq 1 ]; then
      valid_lines="${valid_lines:+${valid_lines}
}${line}"
    else
      echo "  Warning: '$key' cannot be overridden locally (shared team config). Overridable sections: push, qa, worktree, workflow.blocks, stealth." >&2
    fi
  done <<< "$override_data"

  [ -n "$valid_lines" ] && printf '%s' "$valid_lines"
  return 0
}

# flat_to_yaml FLAT_DATA
# Reconstructs YAML from flat KEY=VALUE lines. Output is valid for parse_yaml() round-trip.
flat_to_yaml() {
  local flat_data="$1"
  [ -z "$flat_data" ] && return 0

  printf '%s\n' "$flat_data" | awk -F= '
  {
    key = $1
    val = substr($0, length(key) + 2)

    n = split(key, parts, ".")
    # Determine indent level by walking parts
    line = ""
    depth = 0

    for (i = 1; i <= n; i++) {
      p = parts[i]
      # Build the path up to this level
      path = ""
      for (j = 1; j <= i; j++) {
        if (path != "") path = path SUBSEP
        path = path parts[j]
      }

      if (i == n) {
        # Leaf — check if parent was an array element
        # If previous part is numeric, this is object inside array
        indent = ""
        for (d = 0; d < i - 1; d++) indent = indent "  "

        # Check if this part is a numeric index (bare array value)
        if (p ~ /^[0-9]+$/ && i == n) {
          # bare array value: parent.N=val
          printf "%s- %s\n", indent, val
        } else {
          printf "%s%s: %s\n", indent, p, val
        }
      } else {
        # Check if we already printed this parent path
        if (!(path in seen)) {
          seen[path] = 1
          indent = ""
          for (d = 0; d < i - 1; d++) indent = indent "  "

          if (p ~ /^[0-9]+$/) {
            # Array element — print dash prefix
            printf "%s-\n", indent
          } else {
            printf "%s%s:\n", indent, p
          }
        }
      }
    }
  }'
}

load_config() {
  local config_path="$CWD/tricycle.config.yml"
  if [ ! -f "$config_path" ]; then
    error "tricycle.config.yml not found in current directory."
    echo "Run \`tricycle init\` to create one." >&2
    exit 1
  fi
  CONFIG_DATA=$(parse_yaml "$config_path")

  # Check for local override file
  local override_path="$CWD/tricycle.config.local.yml"
  if [ -f "$override_path" ]; then
    if [ ! -r "$override_path" ]; then
      echo "  Warning: tricycle.config.local.yml exists but is not readable. Using base config only." >&2
      return 0
    fi

    local override_data
    if ! override_data=$(parse_yaml "$override_path" 2>/dev/null); then
      echo "  Warning: tricycle.config.local.yml has invalid YAML. Using base config only." >&2
      return 0
    fi

    # Empty override file — nothing to merge
    [ -z "$override_data" ] && return 0

    # Validate and filter to overridable keys only
    local valid_override
    valid_override=$(validate_override "$override_data")

    # Merge valid overrides into base config
    if [ -n "$valid_override" ]; then
      CONFIG_DATA=$(merge_config_data "$CONFIG_DATA" "$valid_override")
    fi
  fi
}

# Prints the value, or nothing for a missing key. Always returns 0, so a missing
# key never aborts a caller running under `set -e -o pipefail`.
cfg_get() {
  local key="$1"
  echo "$CONFIG_DATA" | grep -m1 "^${key}=" | cut -d= -f2- || true
}

cfg_has() {
  echo "$CONFIG_DATA" | grep -q "^${1}"
}

cfg_get_or() {
  local val
  val=$(cfg_get "$1") || true
  if [ -n "$val" ]; then
    printf '%s' "$val"
  else
    printf '%s' "$2"
  fi
}

cfg_count() {
  local prefix="$1"
  local i=0
  while echo "$CONFIG_DATA" | grep -q "^${prefix}\.${i}\."; do
    i=$((i + 1))
  done
  # Also check bare value arrays (no sub-keys, just prefix.N=value)
  if [ $i -eq 0 ]; then
    while echo "$CONFIG_DATA" | grep -q "^${prefix}\.${i}="; do
      i=$((i + 1))
    done
  fi
  echo "$i"
}

# ─── Interactive Prompts ─────────────────────────────────────────────────────

prompt() {
  local question="$1" default="$2"
  local suffix=""
  [ -n "$default" ] && suffix=" [$default]"
  printf '%s%s: ' "$question" "$suffix" >&2
  local answer
  read -r answer
  answer="${answer## }"
  answer="${answer%% }"
  if [ -n "$answer" ]; then
    printf '%s' "$answer"
  else
    printf '%s' "$default"
  fi
}

choose() {
  local question="$1" default_idx="$2"
  shift 2
  local options=("$@")
  local i

  printf '\n%s\n' "$question" >&2
  for i in "${!options[@]}"; do
    local marker=" "
    [ "$i" -eq "$default_idx" ] && marker=">"
    printf '  %s %d. %s\n' "$marker" "$((i + 1))" "${options[$i]}" >&2
  done

  local answer
  answer=$(prompt "Choice (1-${#options[@]})" "$((default_idx + 1))")
  local idx=$((answer - 1))
  if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#options[@]}" ]; then
    echo "$idx"
  else
    echo "$default_idx"
  fi
}

# ─── File Operations ─────────────────────────────────────────────────────────

# ─── Lock File ───────────────────────────────────────────────────────────────
# LOCK_FILES: tab-separated lines of filepath\tchecksum

LOCK_VERSION="0.1.0"
LOCK_INSTALLED=""
LOCK_FILES=""

load_lock() {
  local lock_path="$CWD/.tricycle.lock"
  LOCK_VERSION="0.1.0"
  LOCK_INSTALLED="$(date +%Y-%m-%d)"
  LOCK_FILES=""

  [ -f "$lock_path" ] || return 0

  LOCK_VERSION=$(awk '/"version"/ { gsub(/.*: *"/, ""); gsub(/".*/, ""); print; exit }' "$lock_path")
  LOCK_INSTALLED=$(awk '/"installed"/ { gsub(/.*: *"/, ""); gsub(/".*/, ""); print; exit }' "$lock_path")

  LOCK_FILES=$(awk '
    BEGIN { in_files = 0; cur = ""; cs = "" }
    /"files"/ { in_files = 1; next }
    !in_files { next }
    {
      if (/"[^"]*"[[:space:]]*:[[:space:]]*\{/) {
        line = $0
        sub(/^[[:space:]]*"/, "", line)
        sub(/".*/, "", line)
        cur = line
      }
      if (cur != "" && /"checksum"/) {
        line = $0
        sub(/.*"checksum"[[:space:]]*:[[:space:]]*"/, "", line)
        sub(/".*/, "", line)
        printf "%s\t%s\n", cur, line
        cur = ""
      }
    }
  ' "$lock_path")
}

save_lock() {
  local lock_path="$CWD/.tricycle.lock"
  {
    printf '{\n'
    printf '  "version": "%s",\n' "$LOCK_VERSION"
    printf '  "installed": "%s",\n' "$LOCK_INSTALLED"
    printf '  "files": {'

    local first=1
    if [ -n "$LOCK_FILES" ]; then
      while IFS=$'\t' read -r filepath checksum; do
        [ -z "$filepath" ] && continue
        [ $first -eq 0 ] && printf ','
        printf '\n    "%s": {\n' "$filepath"
        printf '      "checksum": "%s"\n' "$checksum"
        printf '    }'
        first=0
      done <<< "$LOCK_FILES"
    fi

    printf '\n  }\n}\n'
  } > "$lock_path"
}

lock_has() {
  echo "$LOCK_FILES" | grep -q "^${1}	"
}

lock_remove() {
  LOCK_FILES=$(echo "$LOCK_FILES" | awk -F'\t' -v p="$1" '$1 != p' | sed '/^$/d')
}

lock_set() {
  local filepath="$1" checksum="$2"
  local new_entry
  new_entry=$(printf '%s\t%s' "$filepath" "$checksum")

  if [ -z "$LOCK_FILES" ]; then
    LOCK_FILES="$new_entry"
    return
  fi

  local filtered
  filtered=$(echo "$LOCK_FILES" | awk -F'\t' -v p="$filepath" '$1 != p' | sed '/^$/d')
  if [ -z "$filtered" ]; then
    LOCK_FILES="$new_entry"
  else
    LOCK_FILES="${filtered}"$'\n'"${new_entry}"
  fi
}

# ─── Skills ──────────────────────────────────────────────────────────────────

skill_checksum() {
  local skill_dir="$1"
  local combined=""
  while IFS= read -r f; do
    combined="${combined}$(cat "$f")"
  done < <(find "$skill_dir" -type f ! -name SOURCE | sort)
  sha256_str "$combined"
}

generate_source_file() {
  local skill_dir="$1" origin="$2" commit="${3:-}"
  local cs
  cs=$(skill_checksum "$skill_dir")
  {
    printf 'origin: %s\n' "$origin"
    [ -n "$commit" ] && printf 'commit: %s\n' "$commit"
    printf 'installed: %s\n' "$(date +%Y-%m-%d)"
    printf 'checksum: %s\n' "$cs"
  } > "$skill_dir/SOURCE"
}

source_get() {
  local source_file="$1" key="$2"
  grep -m1 "^${key}: " "$source_file" 2>/dev/null | cut -d' ' -f2-
}

install_skills() {
  local src_base="$1" dest_rel_base="$2"
  [ -d "$src_base" ] || return 0

  # Build disabled skills list
  local disabled=""
  local dc
  dc=$(cfg_count "skills.disable")
  local di=0
  while [ "$di" -lt "$dc" ]; do
    local dname
    dname=$(cfg_get "skills.disable.$di")
    disabled="${disabled} ${dname} "
    di=$((di + 1))
  done

  local skill_name skill_path
  for skill_path in "$src_base"/*/; do
    [ -d "$skill_path" ] || continue
    skill_path="${skill_path%/}"
    skill_name=$(basename "$skill_path")

    # Skip disabled
    if echo "$disabled" | grep -q " ${skill_name} "; then
      info "SKIP .claude/skills/$skill_name (disabled)"
      # A disabled skill that trc installed is removed; a repo's own copy stays.
      if [ -d "$CWD/$dest_rel_base/$skill_name" ]; then
        if lock_has "$dest_rel_base/$skill_name/SKILL.md"; then
          rm -rf "${CWD:?}/$dest_rel_base/$skill_name"
          LOCK_FILES=$(echo "$LOCK_FILES" | awk -F'\t' -v p="$dest_rel_base/$skill_name/" 'index($1, p) != 1' | sed '/^$/d')
          info "REMOVE $dest_rel_base/$skill_name (disabled)"
        else
          info "NOTICE: $dest_rel_base/$skill_name is disabled but is not managed by trc; it stays"
        fi
      fi
      continue
    fi

    # SOURCE is always regenerated below with run-specific content (date,
    # commit), so never install core's copy: installing it would lock a
    # checksum the regeneration immediately invalidates, leaving SOURCE
    # permanently "locally modified" in every consumer repo.
    install_dir "$skill_path" "$dest_rel_base/$skill_name" SOURCE

    # Generate SOURCE for vendored skills
    local dest_skill="$CWD/$dest_rel_base/$skill_name"
    if [ -d "$dest_skill" ]; then
      # SOURCE changes only when the skill content changes, so an update with
      # no new skill content leaves it as it is. The commit is the toolkit's.
      if [ "$(source_get "$dest_skill/SOURCE" checksum 2>/dev/null)" != "$(skill_checksum "$dest_skill")" ] \
         || [ "$(source_get "$dest_skill/SOURCE" origin 2>/dev/null)" != "vendored:core/skills/$skill_name" ]; then
        local commit=""
        commit=$(git -C "$skill_path" rev-parse HEAD 2>/dev/null || true)
        generate_source_file "$dest_skill" "vendored:core/skills/$skill_name" "$commit"
        info "WRITE $dest_rel_base/$skill_name/SOURCE"
      fi
      # Lock SOURCE as it is, so it reads as clean on the next run.
      lock_set "$dest_rel_base/$skill_name/SOURCE" \
        "$(sha256_str "$(cat "$dest_skill/SOURCE")")"
    fi
  done
}

fetch_external_skill() {
  local source_uri="$1" dest_base="$2"
  local scheme="${source_uri%%:*}"
  local path="${source_uri#*:}"

  # Detect name collision with vendored skill
  local ext_name
  ext_name=$(basename "$path")
  if [ -d "$CWD/$dest_base/$ext_name" ] && [ -f "$CWD/$dest_base/$ext_name/SOURCE" ]; then
    local existing_origin
    existing_origin=$(source_get "$CWD/$dest_base/$ext_name/SOURCE" "origin")
    case "$existing_origin" in
      vendored:*)
        info "WARNING: external skill '$ext_name' overrides vendored default"
        ;;
    esac
  fi

  case "$scheme" in
    github)
      # Parse github:owner/repo/skill-path
      local owner repo skill_path skill_name
      owner=$(echo "$path" | cut -d/ -f1)
      repo=$(echo "$path" | cut -d/ -f2)
      skill_path=$(echo "$path" | cut -d/ -f3-)
      skill_name=$(basename "$skill_path")

      if [ -z "$owner" ] || [ -z "$repo" ] || [ -z "$skill_path" ]; then
        error "Invalid github source: $source_uri (expected github:owner/repo/path)"
        return 1
      fi

      local tmpdir
      tmpdir=$(mktemp -d)

      info "FETCH $source_uri"
      if ! git clone --depth=1 --filter=blob:none --sparse \
        "https://github.com/${owner}/${repo}.git" "$tmpdir" 2>/dev/null; then
        error "Failed to clone https://github.com/${owner}/${repo}.git"
        rm -rf "$tmpdir"
        return 1
      fi

      if ! git -C "$tmpdir" sparse-checkout set "$skill_path" 2>/dev/null; then
        error "Failed to sparse-checkout $skill_path from $owner/$repo"
        rm -rf "$tmpdir"
        return 1
      fi

      if [ ! -d "$tmpdir/$skill_path" ]; then
        error "Skill path $skill_path not found in $owner/$repo"
        rm -rf "$tmpdir"
        return 1
      fi

      local dest_skill="$CWD/$dest_base/$skill_name"
      mkdir -p "$dest_skill"
      cp -R "$tmpdir/$skill_path"/* "$dest_skill/" 2>/dev/null || true
      cp -R "$tmpdir/$skill_path"/.* "$dest_skill/" 2>/dev/null || true

      local commit
      commit=$(git -C "$tmpdir" rev-parse HEAD 2>/dev/null || echo "")
      generate_source_file "$dest_skill" "$source_uri" "$commit"
      lock_set "$dest_base/$skill_name/SOURCE" \
        "$(sha256_str "$(cat "$dest_skill/SOURCE")")" "false"
      info "WRITE $dest_base/$skill_name/SOURCE"

      rm -rf "$tmpdir"
      ;;
    local)
      local skill_name
      skill_name=$(basename "$path")
      local src_path="$path"
      # Resolve relative paths from CWD
      [[ "$src_path" != /* ]] && src_path="$CWD/$src_path"

      if [ ! -d "$src_path" ]; then
        error "Local skill path not found: $path"
        return 1
      fi

      local dest_skill="$CWD/$dest_base/$skill_name"
      mkdir -p "$dest_skill"
      cp -R "$src_path"/* "$dest_skill/" 2>/dev/null || true
      cp -R "$src_path"/.* "$dest_skill/" 2>/dev/null || true

      generate_source_file "$dest_skill" "$source_uri" ""
      lock_set "$dest_base/$skill_name/SOURCE" \
        "$(sha256_str "$(cat "$dest_skill/SOURCE")")" "false"
      info "FETCH local:$path"
      info "WRITE $dest_base/$skill_name/SOURCE"
      ;;
    *)
      error "Unknown skill source scheme: $scheme (expected github: or local:)"
      return 1
      ;;
  esac
  return 0
}

# ─── File Installation ───────────────────────────────────────────────────────

install_file() {
  local src="$1" dest_rel="$2"
  local dest="$CWD/$dest_rel"
  local content checksum

  content=$(cat "$src")
  checksum=$(sha256_str "$content")

  # An identical file is not rewritten.
  if cmp -s "$src" "$dest"; then
    lock_set "$dest_rel" "$checksum"
    return 0
  fi

  # Copy the bytes, then rename: a hook that another session runs at this
  # moment sees the old file or the new one, never a partial write.
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest.tmp.$$"
  case "$src" in
    *.sh) chmod +x "$dest.tmp.$$" ;;
  esac
  mv -f "$dest.tmp.$$" "$dest"

  lock_set "$dest_rel" "$checksum"
  info "WRITE $dest_rel"
  return 0
}

# A core hook is wanted when its config switch is on and it is not named in
# claude.disable_core_hooks. `generate settings` registers only wanted hooks,
# and init/update install only their scripts.
core_hook_wanted() { # <name without .sh>
  local i=0 n
  n=$(cfg_count "claude.disable_core_hooks")
  while [ "$i" -lt "$n" ]; do
    [ "$(cfg_get_or "claude.disable_core_hooks.$i" "")" = "$1" ] && return 1
    i=$((i + 1))
  done
  case "$1" in
    guard-main-checkout) [ "$(cfg_get "worktree.enabled")" = "true" ] ;;
    style-gate) [ "$(cfg_get_or "style.artifacts" "")" = "ste-short" ] ;;
    session-context)
      # The hook injects the constitution, context.session_start.files, and the
      # ste-short skill when style.artifacts is ste-short.
      [ "$(cfg_get_or "context.session_start.constitution" "true")" != "false" ] \
        || [ "$(cfg_count "context.session_start.files")" -gt 0 ] \
        || [ "$(cfg_get_or "style.artifacts" "")" = "ste-short" ] ;;
    *) return 0 ;;
  esac
}

# Install the core hook scripts that core_hook_wanted accepts.
install_core_hooks() { # <src_dir> <dest_rel_dir>
  local f name
  for f in "$1"/*.sh; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .sh)
    core_hook_wanted "$name" && install_file "$f" "$2/$name.sh"
  done
  return 0
}

install_dir() {
  local src_dir="$1" dest_rel_dir="$2" exclude_name="${3:-}"
  [ -d "$src_dir" ] || return 0

  # Use process substitution to keep while loop in current shell
  # so that LOCK_FILES modifications persist
  while IFS= read -r src_path; do
    local rel="${src_path#"$src_dir"/}"
    install_file "$src_path" "$dest_rel_dir/$rel"
  done < <(
    if [ -n "$exclude_name" ]; then
      find "$src_dir" -type f ! -name "$exclude_name" | sort
    else
      find "$src_dir" -type f | sort
    fi
  )
  return 0
}
