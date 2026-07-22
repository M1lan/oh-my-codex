#!/usr/bin/env bash
# menu.bash -- THE human menu: compact splash header + guided command builder.
#
#   menu.bash
#
# The one and only human UI (agents get entry.bash's terse dump instead):
#   * Compact splash header: repo facts parsed from files -- never spawns
#     node/cargo. The old full-screen info-screen splash + countdown are gone.
#   * `gum filter` IS the menu -- full grouped list visible, narrows live,
#     --no-fuzzy gives word-prefix matching ("te" hits test, not pretest).
#   * Recipes with parameters become fill-in-the-blank forms (gum input per
#     argument, defaults skippable), then gum confirm.
#   * Items self-generate from `just --dump` with modules recursed -- the
#     menu can never go stale. Module recipes show as "test node" etc.
#   * NO separator/header pseudo-entries -- grouping is a [group] column.
#   * Terminal DEFAULT colors only (gum defaults + ANSI indexes) -- no themes.
#   * SIGINT-safe: trap + rc-capture (never `|| true` around gum).
#   * Iron Rule 5: never clear -- a `printf '\n'` spacer at every loop top;
#     gum filter redraws its own region inline.
#
# Pure GNU Bash 5.3+.

# shellcheck source=lib.bash disable=SC2154,SC1091
source "$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)/lib.bash"
cd "$REPO_ROOT" || exit 1
trap 'exit 130' INT TERM HUP

for dep in gum jq just; do
  has "$dep" || die "error: $dep required for the menu -- run: just doctor-install"
done

# group display order (anything unknown sorts last, alphabetically)
GROUP_ORDER=(meta gate build test lint rust omx ai dev sync util clean)

# ── build the item list from the live recipe inventory ───────────────────
# tab-separated: name <TAB> group <TAB> doc <TAB> params(space-joined)
# name may be "recipe" (root) or "module recipe". group = module name, or the
# [group] attribute for root recipes.
# param suffixes: `?` = has default (skippable) · `*` = variadic (skippable)
recipe_rows() {
  just --dump --dump-format json | jq -r '
        def rows($prefix; $grp):
            .recipes
            | to_entries[]
            | select(.key | startswith("_") | not)
            | select(.key != "default")
            | select([.value.attributes[]? | strings] | index("private") | not)
            | [ ($prefix + .key),
                (if $grp != "" then $grp
                 else (([.value.attributes[]? | objects | .group] | first) // "misc")
                 end),
                (.value.doc // ""),
                ([.value.parameters[]?
                  | .name
                    + (if .kind == "star" or .kind == "plus" then "*"
                       elif .default != null then "?"
                       else "" end)
                 ] | join(" "))
              ]
            | @tsv;
        rows(""; ""),
        (.modules | to_entries[]
         | (.key) as $m
         | ([$m, $m, "the bare verb -- runs this module'\''s default recipe", ""] | @tsv),
           (.value | rows($m + " "; $m)))'
}

build_items() {
  declare -gA ITEM_PARAMS=()
  ITEMS=()
  local -A by_group=()
  local name group doc params
  while IFS=$'\t' read -r name group doc params; do
    ITEM_PARAMS[$name]=$params
    local tag suffix=''
    [[ -n "$params" ]] && suffix=" ($params)"
    printf -v tag '%-22s %-7s %s%s' "$name" "[$group]" "$doc" "$suffix"
    by_group[$group]+="$tag"$'\n'
  done < <(recipe_rows | LC_ALL=C sort -t $'\t' -k2,2 -k1,1)

  local g line
  for g in "${GROUP_ORDER[@]}"; do
    [[ -n "${by_group[$g]:-}" ]] || continue
    while IFS= read -r line; do [[ -n "$line" ]] && ITEMS+=("$line"); done <<<"${by_group[$g]}"
    unset "by_group[$g]"
  done
  for g in $(printf '%s\n' "${!by_group[@]}" | LC_ALL=C sort); do
    while IFS= read -r line; do [[ -n "$line" ]] && ITEMS+=("$line"); done <<<"${by_group[$g]}"
  done
  # a real, actionable entry -- NOT a separator
  printf -v line '%-22s %-7s %s' 'quit' '[menu]' 'leave the menu'
  ITEMS+=("$line")
}

# ── splash header (facts are FILE-PARSE ONLY -- instant) ─────────────────
splash() {
  local branch dirty last pkg_v built deps state
  branch=$(fact_branch)
  dirty=$(fact_dirty)
  last=$(fact_last_commit)
  ((${#last} > 40)) && last="${last:0:39}…"
  pkg_v=$(fact_pkg_version)
  built=$(fact_built)
  deps=$(fact_deps)
  state="deps ${deps:-MISSING -> just setup} · build ${built:-MISSING -> just build}"
  gum style --border rounded --border-foreground "$G_ACCENT" \
    --padding "0 2" --margin "0 1" \
    "$(printf '%s%s %s v%s%s  %s%s · %s dirty · %s%s' \
      "$C_BOLD$C_CYAN" "$I_NODE" "$PKGNAME" "$pkg_v" "$C_RESET" \
      "$C_DIM" "$branch" "$dirty" "$last" "$C_RESET")" \
    "$(printf '%s%s · gates: just ci · params become forms%s' "$C_DIM" "$state" "$C_RESET")"
}

# ── preview + parameter form + confirm + run ─────────────────────────────
show_recipe() { # <name> ("recipe", "module recipe", or bare module name)
  local -a words
  read -r -a words <<<"$1"
  local src
  if ! src=$(just --show "${words[@]}" 2>/dev/null); then
    # bare module: --show rejects it -- preview the module's recipe list
    just --list "${words[0]}" 2>/dev/null || return 0
    return 0
  fi
  if has bat; then
    bat --language=make --color=always --style=plain --paging=never <<<"$src" 2>/dev/null ||
      printf '%s\n' "$src"
  else
    printf '%s\n' "$src"
  fi
}

run_recipe() { # <name>
  local name="$1" args=() p val rc words
  local -a cmd
  read -r -a cmd <<<"$name"
  printf '\n'
  gum style --border rounded --border-foreground "$G_ACCENT" \
    --padding "0 2" --margin "1 2" \
    "$(printf '%s just %s' "$I_BOLT" "$name")"
  show_recipe "$name"
  printf '\n'
  for p in ${ITEM_PARAMS[$name]:-}; do
    local label="$p" skippable=0 variadic=0
    case "$p" in
      *'?')
        skippable=1
        label="${p%\?} (optional, enter to skip)"
        ;;
      *'*')
        skippable=1
        variadic=1
        label="${p%\*} (variadic, space-separated, enter to skip)"
        ;;
    esac
    rc=0
    val=$(gum input \
      --header="$(printf '%sparam ›%s %s%s%s' "$C_DIM" "$C_RESET" "$C_BOLD" "$label" "$C_RESET")" \
      --header.foreground="6" \
      --placeholder="value for {{${p%[?*]}}}" \
      --prompt='  ❯ ' \
      --prompt.foreground="6" \
      --cursor.foreground="6") || rc=$?
    ((rc != 0)) && return 0 # cancelled -> back to menu
    # empty value for a skippable param: stop here, let just fill the rest
    if [[ -z "$val" ]]; then
      ((skippable)) && break
      args+=("$val") # required param given empty: pass it through
    elif ((variadic)); then
      read -r -a words <<<"$val"
      args+=("${words[@]+"${words[@]}"}")
    else
      args+=("$val")
    fi
  done
  rc=0
  gum confirm --affirmative=" run" --negative=" back" \
    --prompt.foreground="6" \
    "$(printf 'just %s %s' "$name" "${args[*]:-}")" || rc=$?
  ((rc != 0)) && return 0 # back to menu
  exec just "${cmd[@]}" "${args[@]+"${args[@]}"}"
}

# ── main loop ────────────────────────────────────────────────────────────
build_items
header=$(printf '%s recipes · type to filter · esc esc quits' "${#ITEMS[@]}")

while true; do
  printf '\n' # Iron Rule 5: spacer, never clear
  splash

  height=$(($(term_lines) - 10))
  ((height < 8)) && height=8
  rc=0
  choice=$(printf '%s\n' "${ITEMS[@]}" |
    gum filter --no-fuzzy --reverse --height="$height" \
      --placeholder='type a recipe…' --header="$header" \
      --indicator='▌' \
      --indicator.foreground="6" \
      --match.foreground="6" \
      --header.foreground="3" \
      --prompt='  › ' \
      --prompt.foreground="6") || rc=$?
  ((rc != 0)) && exit 0 # esc / ctrl-c
  [[ -z "$choice" ]] && exit 0

  # item name = everything before the [group] column (1 or 2 words)
  recipe=$(gawk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\[/) { NF = i - 1; break } } 1' <<<"$choice")
  recipe=${recipe%"${recipe##*[![:space:]]}"} # rtrim
  case "$recipe" in
    quit) exit 0 ;;
    *) run_recipe "$recipe" ;;
  esac
done
