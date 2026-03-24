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
  local blocks_dir="$CWD/.specify/blocks"
  local output_dir="$CWD/.claude/commands"

  # Fall back to core blocks if .specify/blocks doesn't exist
  if [ ! -d "$blocks_dir" ]; then
    blocks_dir="$TOOLKIT_ROOT/core/blocks"
  fi

  bash "$script_path" \
    --blocks-dir="$blocks_dir" \
    --output-dir="$output_dir" \
    --config="$CWD/tricycle.config.yml" \
    "${flags[@]}"

  echo ""
}
