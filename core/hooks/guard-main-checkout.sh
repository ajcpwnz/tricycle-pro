#!/bin/bash
# PreToolUse(Bash): no feature branch is created in the main checkout.
#
# In a worktree `.git` is a FILE pointing at .git/worktrees/<name>. In the main
# checkout it is a DIRECTORY. The directory judged is the payload cwd, moved by
# any `cd <dir>` and `git -C <dir>` in the command.

# Dogfood bypass: set TRICYCLE_DEV=1 to allow branch creation in the main checkout
if [ "$TRICYCLE_DEV" = "1" ]; then exit 0; fi

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" = "Bash" ] || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$CMD" ] || exit 0
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] || CWD="$PWD"

block() { jq -nc --arg r "$1" '{decision:"block", reason:$r}'; exit 0; }

# Main checkout iff the repo root's .git is a directory.
is_main_checkout() { # <dir>
  local root
  [ -d "$1" ] || return 1
  root=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -n "$root" ] && [ -d "$root/.git" ]
}

resolve() { # <base> <path>
  case "$2" in /*) printf '%s' "$2" ;; "~"*) printf '%s' "$HOME${2#\~}" ;; *) printf '%s/%s' "$1" "$2" ;; esac
}

# Split on ; | & outside quotes, one segment per line.
split_segments() {
  awk '{
    line = $0; out = ""; q = ""
    for (i = 1; i <= length(line); i++) {
      c = substr(line, i, 1)
      if (q != "") { if (c == "\\" && q == "\"") { out = out c substr(line, ++i, 1); continue }
                     if (c == q) q = ""; out = out c; continue }
      if (c == "\"" || c == "'"'"'") { q = c; out = out c; continue }
      if (c == ";" || c == "|" || c == "&") { out = out "\n"; continue }
      out = out c
    }
    print out
  }'
}

# Does this `git ...` word list create a branch? Sets GIT_DIR_ARG for -C.
creates_branch() {
  local w sub="" args=() skip=0
  GIT_DIR_ARG=""
  for w in "${@:2}"; do
    if [ -z "$sub" ]; then
      if [ "$skip" = C ]; then GIT_DIR_ARG="$w"; skip=0; continue; fi
      if [ "$skip" = 1 ]; then skip=0; continue; fi
      case "$w" in
        -C) skip=C ;;
        -c|--git-dir|--work-tree|--namespace) skip=1 ;;
        -*) ;;
        *) sub="$w" ;;
      esac
      continue
    fi
    args+=("$w")
  done
  case "$sub" in
    checkout|switch)
      for w in "${args[@]}"; do
        case "$w" in -b|-B|-c|-C|--orphan|--create|--force-create|--create=*|--force-create=*|--orphan=*) return 0 ;; esac
      done
      return 1 ;;
    branch)
      local name=0
      for w in "${args[@]}"; do
        case "$w" in
          -d|-D|--delete|-m|-M|--move|-l|--list|-a|--all|-r|--remotes|-v|-vv|--verbose|--show-current|--contains|--no-contains|--merged|--no-merged|--points-at|-u|--set-upstream-to|--set-upstream-to=*|--unset-upstream|--edit-description|--format|--format=*|--sort|--sort=*) return 1 ;;
          -*|*'>'*|*'<'*) ;;
          *) name=1 ;;
        esac
      done
      [ "$name" = 1 ] ;;
    *) return 1 ;;
  esac
}

EFF="$CWD"
while IFS= read -r SEG; do
  SEG=$(printf '%s' "$SEG" | sed -E 's/^[[:space:]]*//; s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)+//')
  [ -n "$SEG" ] || continue
  read -ra W <<< "$SEG"
  case "${W[0]}" in
    cd) [ -n "${W[1]}" ] && EFF=$(resolve "$EFF" "${W[1]//[\"\']/}") ;;
    git)
      if creates_branch "${W[@]}"; then
        DIR="$EFF"; [ -n "$GIT_DIR_ARG" ] && DIR=$(resolve "$EFF" "${GIT_DIR_ARG//[\"\']/}")
        is_main_checkout "$DIR" && block "BLOCKED: Do not create feature branches in the main checkout. Use a git worktree: git worktree add -b <branch-name> ../<project>-<branch-name> origin/<base-branch>, then cd into it and install dependencies. Skip only if the user explicitly said to work on the current branch."
      fi ;;
  esac
done <<< "$(printf '%s\n' "$CMD" | split_segments)"

exit 0
