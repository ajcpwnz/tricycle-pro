#!/usr/bin/env bash
# json_builder.sh — JSON generation helpers using printf

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

json_kv() {
  printf '"%s": "%s"' "$1" "$(json_escape "$2")"
}

json_kv_bool() {
  printf '"%s": %s' "$1" "$2"
}

json_kv_raw() {
  printf '"%s": %s' "$1" "$2"
}

json_str_array() {
  local result="["
  local first=1
  local item
  for item in "$@"; do
    [ $first -eq 0 ] && result="$result, "
    result="$result\"$(json_escape "$item")\""
    first=0
  done
  result="$result]"
  printf '%s' "$result"
}
