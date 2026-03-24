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

load_config() {
  local config_path="$CWD/tricycle.config.yml"
  if [ ! -f "$config_path" ]; then
    error "tricycle.config.yml not found in current directory."
    echo "Run \`tricycle init\` to create one." >&2
    exit 1
  fi
  CONFIG_DATA=$(parse_yaml "$config_path")
}

cfg_get() {
  local key="$1"
  echo "$CONFIG_DATA" | grep -m1 "^${key}=" | cut -d= -f2-
}

cfg_has() {
  echo "$CONFIG_DATA" | grep -q "^${1}"
}

cfg_get_or() {
  local val
  val=$(cfg_get "$1")
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

write_file() {
  local filepath="$1" content="$2"
  mkdir -p "$(dirname "$filepath")"
  printf '%s' "$content" > "$filepath"
}

# ─── Lock File ───────────────────────────────────────────────────────────────
# LOCK_FILES: tab-separated lines of filepath\tchecksum\tcustomized

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
      if (/"[^"]*"[[:space:]]*:[[:space:]]*\{/ && !/checksum|customized|version|installed|files/) {
        line = $0
        sub(/^[[:space:]]*"/, "", line)
        sub(/".*/, "", line)
        cur = line
      }
      if (cur != "" && /"checksum"/) {
        line = $0
        sub(/.*"checksum"[[:space:]]*:[[:space:]]*"/, "", line)
        sub(/".*/, "", line)
        cs = line
      }
      if (cur != "" && /customized/) {
        line = $0
        sub(/.*:[[:space:]]*/, "", line)
        sub(/[,[:space:]}].*/, "", line)
        printf "%s\t%s\t%s\n", cur, cs, line
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
      while IFS=$'\t' read -r filepath checksum customized; do
        [ -z "$filepath" ] && continue
        [ $first -eq 0 ] && printf ','
        printf '\n    "%s": {\n' "$filepath"
        printf '      "checksum": "%s",\n' "$checksum"
        printf '      "customized": %s\n' "$customized"
        printf '    }'
        first=0
      done <<< "$LOCK_FILES"
    fi

    printf '\n  }\n}\n'
  } > "$lock_path"
}

lock_get_checksum() {
  echo "$LOCK_FILES" | awk -F'\t' -v path="$1" '$1 == path { print $2; exit }'
}

lock_is_customized() {
  local val
  val=$(echo "$LOCK_FILES" | awk -F'\t' -v path="$1" '$1 == path { print $3; exit }')
  [ "$val" = "true" ]
}

lock_has() {
  echo "$LOCK_FILES" | grep -q "^${1}	"
}

lock_set() {
  local filepath="$1" checksum="$2" customized="$3"
  local new_entry
  new_entry=$(printf '%s\t%s\t%s' "$filepath" "$checksum" "$customized")

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

# ─── File Installation ───────────────────────────────────────────────────────

install_file() {
  local src="$1" dest_rel="$2"
  local dest="$CWD/$dest_rel"
  local content checksum

  content=$(cat "$src")
  checksum=$(sha256_str "$content")

  # Check if file exists and was locally modified
  if [ -f "$dest" ] && lock_has "$dest_rel"; then
    local current_checksum
    current_checksum=$(sha256_str "$(cat "$dest")")
    local stored_checksum
    stored_checksum=$(lock_get_checksum "$dest_rel")
    if [ "$current_checksum" != "$stored_checksum" ]; then
      info "SKIP $dest_rel (locally modified)"
      lock_set "$dest_rel" "$stored_checksum" "true"
      return 1
    fi
  fi

  mkdir -p "$(dirname "$dest")"
  printf '%s' "$content" > "$dest"

  case "$src" in
    *.sh) chmod +x "$dest" ;;
  esac

  lock_set "$dest_rel" "$checksum" "false"
  info "WRITE $dest_rel"
  return 0
}

install_dir() {
  local src_dir="$1" dest_rel_dir="$2"
  [ -d "$src_dir" ] || return 0

  # Use process substitution to keep while loop in current shell
  # so that LOCK_FILES modifications persist
  while IFS= read -r src_path; do
    local rel="${src_path#"$src_dir"/}"
    install_file "$src_path" "$dest_rel_dir/$rel"
  done < <(find "$src_dir" -type f | sort)
}
