#!/usr/bin/env bash
# assemble.sh — Block assembly command for tricycle CLI

cmd_assemble() {
  local flags=()

  if [ $DRY_RUN -eq 1 ]; then
    flags+=("--dry-run")
  fi

  # Check for --verbose in positional args
  local i=1
  while [ "$i" -lt "${#POSITIONALS[@]}" ]; do
    case "${POSITIONALS[$i]}" in
      --verbose) flags+=("--verbose") ;;
    esac
    i=$((i + 1))
  done

  local script_path="$TOOLKIT_ROOT/core/scripts/bash/assemble-commands.sh"
  if [ ! -f "$script_path" ]; then
    error "Assembly script not found: $script_path"
    exit 1
  fi

  echo ""
  echo "Assembling commands from blocks..."

  # Run assembly with project-local blocks and output
  local blocks_dir="$CWD/.trc/blocks"
  local output_dir="$CWD/.claude/commands"

  # Fall back to core blocks if .trc/blocks doesn't exist
  if [ ! -d "$blocks_dir" ]; then
    blocks_dir="$TOOLKIT_ROOT/core/blocks"
  fi

  # Pass 1: always assemble from base config (committed output)
  bash "$script_path" \
    --blocks-dir="$blocks_dir" \
    --output-dir="$output_dir" \
    --config="$CWD/tricycle.config.yml" \
    ${flags[@]+"${flags[@]}"}

  # Pass 2: if local override exists, assemble from merged config (local overlay)
  local override_path="$CWD/tricycle.config.local.yml"
  if [ -f "$override_path" ]; then
    local base_data override_data valid_override merged_data
    base_data=$(parse_yaml "$CWD/tricycle.config.yml")

    if override_data=$(parse_yaml "$override_path" 2>/dev/null) && [ -n "$override_data" ]; then
      valid_override=$(validate_override "$override_data" 2>/dev/null)
      if [ -n "$valid_override" ]; then
        merged_data=$(merge_config_data "$base_data" "$valid_override")

        local tmp_config
        tmp_config=$(mktemp "${TMPDIR:-/tmp}/tricycle-merged-XXXXXX.yml")
        flat_to_yaml "$merged_data" > "$tmp_config"

        local local_output="$CWD/.trc/local/commands"
        mkdir -p "$local_output"

        echo "  Assembling local overlay from merged config..."
        bash "$script_path" \
          --blocks-dir="$blocks_dir" \
          --output-dir="$local_output" \
          --config="$tmp_config" \
          ${flags[@]+"${flags[@]}"}

        rm -f "$tmp_config"
      fi
    fi
  fi

  echo ""
}
