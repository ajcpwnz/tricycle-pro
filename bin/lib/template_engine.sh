#!/usr/bin/env bash
# template_engine.sh — {{var}}, {{#each apps}}, {{#if key}} processor

render_template() {
  local template_file="$1"
  [ -f "$template_file" ] || return 1

  local content=""
  local in_each=0
  local each_block=""

  while IFS= read -r line || [ -n "$line" ]; do
    # Detect {{#each apps}}
    if [[ "$line" == *'{{#each apps}}'* ]]; then
      in_each=1
      each_block=""
      continue
    fi

    # Detect {{/each}}
    if [[ "$line" == *'{{/each}}'* ]]; then
      in_each=0
      local app_count
      app_count=$(cfg_count "apps")
      local i=0
      while [ "$i" -lt "$app_count" ]; do
        local expanded="$each_block"
        expanded="${expanded//\{\{app.name\}\}/$(cfg_get "apps.$i.name")}"
        expanded="${expanded//\{\{app.path\}\}/$(cfg_get "apps.$i.path")}"
        expanded="${expanded//\{\{app.lint\}\}/$(cfg_get "apps.$i.lint")}"
        expanded="${expanded//\{\{app.test\}\}/$(cfg_get "apps.$i.test")}"
        expanded="${expanded//\{\{app.build\}\}/$(cfg_get "apps.$i.build")}"
        expanded="${expanded//\{\{app.dev\}\}/$(cfg_get "apps.$i.dev")}"
        expanded="${expanded//\{\{app.port\}\}/$(cfg_get "apps.$i.port")}"

        # Inline {{#if app.<field>}}...{{/if}}: drop the span when the field is
        # empty, else drop only the markers.
        local field close_if='{{/if}}'
        for field in lint test build dev port; do
          if [ -z "$(cfg_get "apps.$i.$field")" ]; then
            expanded=$(printf '%s' "$expanded" | sed "s/{{#if app\.$field}}[^{}]*{{\/if}}//g")
          fi
        done
        for field in lint test build dev port; do
          expanded="${expanded//\{\{#if app.$field\}\}/}"
        done
        expanded="${expanded//$close_if/}"
        expanded="${expanded%$'\n'}"$'\n'

        content="${content}${expanded}"
        i=$((i + 1))
      done
      continue
    fi

    if [ $in_each -eq 1 ]; then
      each_block="${each_block}${line}"$'\n'
      continue
    fi

    content="${content}${line}"$'\n'
  done < "$template_file"

  # Process standalone {{#if key}}...{{/if}} blocks
  content=$(process_if_blocks "$content")

  # Substitute remaining {{var}} placeholders with fallbacks
  content="${content//\{\{project.name\}\}/$(cfg_get_or "project.name" "my-project")}"
  content="${content//\{\{project.package_manager\}\}/$(cfg_get_or "project.package_manager" "npm")}"
  content="${content//\{\{project.base_branch\}\}/$(cfg_get_or "project.base_branch" "main")}"

  local pr_target
  pr_target=$(cfg_get "push.pr_target")
  [ -z "$pr_target" ] && pr_target=$(cfg_get_or "project.base_branch" "main")
  content="${content//\{\{push.pr_target\}\}/$pr_target}"

  content="${content//\{\{push.merge_strategy\}\}/$(cfg_get_or "push.merge_strategy" "squash")}"
  content="${content//\{\{qa.primary_tool\}\}/$(cfg_get_or "qa.primary_tool" "chrome-devtools")}"
  content="${content//\{\{qa.fallback_tool\}\}/$(cfg_get_or "qa.fallback_tool" "playwright")}"
  content="${content//\{\{qa.results_dir\}\}/$(cfg_get_or "qa.results_dir" "qa/results-{date}")}"

  printf '%s' "$content"
}

process_if_blocks() {
  local content="$1"

  # Iteratively resolve {{#if key}}...{{/if}} blocks
  while true; do
    # Find {{#if ...}} pattern
    local if_pattern='{{#if '
    case "$content" in
      *"$if_pattern"*) ;;
      *) break ;;
    esac

    # Extract key from first occurrence
    local key
    key=$(printf '%s' "$content" | grep -o '{{#if [^}]*}}' | head -1 | sed 's/{{#if //;s/}}//')
    [ -z "$key" ] && break

    local open_tag="{{#if ${key}}}"
    local close_tag='{{/if}}'

    # Check if key has a truthy value
    local val
    val=$(cfg_get "$key")

    if [ -n "$val" ] && [ "$val" != "false" ]; then
      # Include content, remove markers
      content="${content//$open_tag/}"
      content="${content//$close_tag/}"
    else
      # Remove block between markers (handles multiline via awk)
      content=$(printf '%s' "$content" | awk -v otag="$open_tag" -v ctag="$close_tag" '
        BEGIN { skip = 0; found = 0 }
        {
          if (!found && index($0, otag)) {
            found = 1
            # Print content before the open tag on this line
            pos = index($0, otag)
            before = (pos > 1) ? substr($0, 1, pos - 1) : ""
            if (before != "") printf "%s", before

            # Check if close tag is on same line
            if (index($0, ctag)) {
              cpos = index($0, ctag)
              after = substr($0, cpos + length(ctag))
              if (after != "") printf "%s", after
              printf "\n"
              skip = 0
            } else {
              skip = 1
              printf "\n"
            }
            next
          }
          if (skip && index($0, ctag)) {
            cpos = index($0, ctag)
            after = substr($0, cpos + length(ctag))
            if (after != "") print after
            skip = 0
            next
          }
          if (!skip) print
        }
      ')
    fi
  done

  printf '%s' "$content"
}
