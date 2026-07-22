#!/usr/bin/env bash
# doctor.bash -- dependency audit for the Justfile AND the oh-my-codex project.
#
#   doctor.bash             full table; exit 1 if a REQUIRED dep is missing
#   doctor.bash --summary   one-line toolbelt status (used by the info screen)
#   doctor.bash --factoid   single most important fact, frugal wording (splash)
#   doctor.bash --install   interactive multi-select install TUI for missing deps
#
# Backends: node comes from fnm (operator rule -- never the Homebrew node),
# pnpm from corepack, the Rust toolchain from rustup, and the UI/GNU
# stragglers from brew. The SRC map routes each tool to the right installer so
# hints and the picker are correct.
#
# Pure GNU Bash 5.3+. Colors: terminal defaults via tput only.

# shellcheck source=lib.bash disable=SC2154,SC1091
source "$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)/lib.bash"

# ── dependency catalogue ─────────────────────────────────────────────────
# tool -> install backend (fnm | corepack | rustup | brew)
declare -A SRC=(
  [bash]=brew [gum]=brew [fzf]=brew [bat]=brew [fd]=brew [rg]=brew
  [jq]=brew [gawk]=brew [gsed]=brew [gdate]=brew [figlet]=brew [git]=brew
  [biome]=brew [shellcheck]=brew [shfmt]=brew [rumdl]=brew [typos]=brew
  [gitleaks]=brew
  [node]=fnm [pnpm]=corepack
  [cargo]=rustup [rustc]=rustup [clippy]=rustup [rustfmt]=rustup
)
# tool -> brew formula (only where the name differs from the command)
declare -A PKG=(
  [rg]=ripgrep [gdate]=coreutils [gsed]=gnu-sed [typos]=typos-cli
)
# install_cmd <tool> -> echoes the install command string (backend-aware)
install_cmd() {
  local t="$1"
  local src="${SRC[$t]:-brew}"
  case "$src" in
    fnm) printf 'fnm install --lts && fnm default lts-latest' ;;
    corepack) printf 'corepack enable && corepack prepare pnpm@latest --activate' ;;
    rustup) printf 'rustup component add %s' "$t" ;;
    *) printf 'brew install %s' "${PKG[$t]:-$t}" ;;
  esac
}
# tool -> one-line purpose
declare -A WHY=(
  [bash]='helper runtime (GNU >= 5.3)'
  [node]='JS/TS runtime (>= 20, via fnm)'
  [pnpm]='package manager (the ONLY one allowed)'
  [git]='version control'
  [jq]='JSON wrangling (menus, package.json facts)'
  [rg]='search engine (never grep)'
  [fd]='file finder (never find)'
  [gawk]='GNU awk for fact extraction'
  [gsed]='GNU sed'
  [gum]='TUI: menu, splash, install picker'
  [fzf]='TUI: fzf launcher + pickers'
  [bat]='syntax-highlighted previews'
  [gdate]='GNU date for timestamps'
  [figlet]='banner art on the splash'
  [cargo]='build/test the Rust crates'
  [rustc]='the Rust compiler (rustup)'
  [clippy]='Rust lint gate (cargo clippy)'
  [rustfmt]='Rust format gate (cargo fmt)'
  [biome]='TS/JS lint + format (just lint/fmt)'
  [shellcheck]='lint the bash helpers'
  [shfmt]='format the bash helpers'
  [rumdl]='markdown linting (just lint md)'
  [typos]='spell check (just typos)'
  [gitleaks]='secret scanning (just secrets)'
)

REQUIRED=(bash node pnpm git jq rg fd gawk)
RECOMMENDED=(gum fzf bat gdate gsed figlet cargo rustc)
OPTIONAL=(biome shellcheck shfmt rumdl typos gitleaks)

# ── checks ───────────────────────────────────────────────────────────────
# version_of <tool> -- short version string, best effort
version_of() {
  case "$1" in
    bash) printf '%s' "${BASH_VERSION%%(*}" ;;
    node) node --version 2>/dev/null | rg -No '[0-9][0-9.]*' | head -1 || true ;;
    pnpm) pnpm --version 2>/dev/null | head -1 || true ;;
    cargo) cargo --version 2>/dev/null | gawk '{print $2}' ;;
    rustc) rustc --version 2>/dev/null | gawk '{print $2}' ;;
    gum) gum --version 2>/dev/null | gawk '{print $3}' ;;
    fzf) fzf --version 2>/dev/null | gawk '{print $1}' ;;
    figlet) figlet -v 2>&1 | rg -No 'Version: ([0-9.]+)' -r '$1' | head -1 || true ;;
    clippy | rustfmt) printf 'rustup' ;;
    *) "$1" --version 2>/dev/null | head -1 | rg -No '[0-9]+\.[0-9][0-9.]*' | head -1 || true ;;
  esac
}

# check_tool <tool> -> sets CHECK_STATE (ok|missing|outdated) + CHECK_NOTE
check_tool() {
  local t="$1"
  CHECK_STATE=ok CHECK_NOTE=''
  case "$t" in
    clippy)
      cargo clippy --version >/dev/null 2>&1 || CHECK_STATE=missing
      return
      ;;
    rustfmt)
      cargo fmt --version >/dev/null 2>&1 || CHECK_STATE=missing
      return
      ;;
  esac
  if ! has "$t"; then
    CHECK_STATE=missing
    return
  fi
  case "$t" in
    bash)
      ((BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 3))) ||
        {
          CHECK_STATE=outdated
          CHECK_NOTE="need GNU >= 5.3, got $BASH_VERSION"
        }
      ;;
    node)
      local maj
      maj=$(node --version 2>/dev/null | rg -No '[0-9]+' | head -1)
      [[ -n $maj ]] && ((maj < 20)) && {
        CHECK_STATE=outdated
        CHECK_NOTE="need node >= 20, got $(node --version 2>/dev/null)"
      }
      ;;
  esac
}

# ── project-level checks (beyond CLI tools) ──────────────────────────────
project_rows=() # "state|name|note"
project_checks() {
  project_rows=()
  local state note
  # dependencies installed
  if [[ -n "$(fact_deps)" ]]; then
    state=ok
    note='node_modules present'
  else
    state=warn
    note='not installed -- run: just setup'
  fi
  project_rows+=("$state|deps|$note")
  # compiled CLI entrypoint
  if [[ -n "$(fact_built)" ]]; then
    state=ok
    note="$ENTRY present (just run works)"
  else
    state=warn
    note='not built yet -- run: just build'
  fi
  project_rows+=("$state|build|$note")
  # rust workspace
  local crates
  crates=$(fact_crates)
  if ((crates > 0)); then
    state=ok
    note="$crates workspace crate(s) (just rust)"
  else
    state=warn
    note='no Cargo workspace found'
  fi
  project_rows+=("$state|rust|$note")
  # working tree
  local dirty
  dirty=$(fact_dirty)
  if ((dirty == 0)); then
    state=ok
    note="clean on $(fact_branch)"
  else
    state=warn
    note="$dirty dirty file(s) -- just ci before commit"
  fi
  project_rows+=("$state|git tree|$note")
}

# ── missing collection ───────────────────────────────────────────────────
collect_missing() {
  MISSING_REQ=() MISSING_OPT=()
  local t
  for t in "${REQUIRED[@]}"; do
    check_tool "$t"
    [[ $CHECK_STATE == ok ]] || MISSING_REQ+=("$t")
  done
  for t in "${RECOMMENDED[@]}" "${OPTIONAL[@]}"; do
    check_tool "$t"
    [[ $CHECK_STATE == ok ]] || MISSING_OPT+=("$t")
  done
}

# ── output: summary (one line, splash toolbelt) ──────────────────────────
cmd_summary() {
  collect_missing
  local total=$((${#REQUIRED[@]} + ${#RECOMMENDED[@]} + ${#OPTIONAL[@]}))
  local bad=$((${#MISSING_REQ[@]} + ${#MISSING_OPT[@]}))
  local ok=$((total - bad))
  if ((bad == 0)); then
    printf '%s %d/%d tools ready\n' "$I_OK" "$ok" "$total"
  else
    local -a all_missing=("${MISSING_REQ[@]+"${MISSING_REQ[@]}"}" "${MISSING_OPT[@]+"${MISSING_OPT[@]}"}")
    printf '%s %d/%d ready -- missing: %s\n' "$I_WARN" "$ok" "$total" "${all_missing[*]}"
  fi
  ((${#MISSING_REQ[@]} == 0))
}

# ── output: factoid (ONE frugal line for the splash exit) ────────────────
# priority: missing required > missing optional > deps > not built > dirty > tip
cmd_factoid() {
  collect_missing
  if ((${#MISSING_REQ[@]} > 0)); then
    printf 'missing required tools: %s -- just doctor-install\n' "${MISSING_REQ[*]}"
    return 0
  fi
  if [[ -z "$(fact_deps)" ]]; then
    printf 'dependencies not installed -- just setup\n'
    return 0
  fi
  if [[ -z "$(fact_built)" ]]; then
    printf 'not built yet -- just build (then: just run --help)\n'
    return 0
  fi
  if ((${#MISSING_OPT[@]} > 0)); then
    printf 'missing optional tools: %s -- just doctor-install\n' "${MISSING_OPT[*]}"
    return 0
  fi
  local dirty
  dirty=$(fact_dirty)
  if ((dirty > 0)); then
    printf '%s uncommitted file(s) on %s -- just ci before commit\n' "$dirty" "$(fact_branch)"
    return 0
  fi
  # shellcheck disable=SC2016  # literal backticks are intentional output
  printf 'all green -- `just ci` is the exact pre-push gate\n'
}

# ── output: full table ───────────────────────────────────────────────────
print_row() { # <state> <name> <version> <note>
  local mark color
  case "$1" in
    ok) mark="$I_OK" color="$C_GREEN" ;;
    warn) mark="$I_WARN" color="$C_YELLOW" ;;
    outdated) mark="$I_WARN" color="$C_YELLOW" ;;
    *) mark="$I_MISS" color="$C_RED" ;;
  esac
  printf '  %s%s%s  %-16s %-12s %s%s%s\n' \
    "$color" "$mark" "$C_RESET" "$2" "${3:-}" "$C_MUTED" "${4:-}" "$C_RESET"
}

print_tier() { # <title> <tools...>
  local title="$1"
  shift
  printf '\n%s%s── %s ──%s\n' "$C_BOLD" "$C_HEAD" "$title" "$C_RESET"
  local t v
  for t in "$@"; do
    check_tool "$t"
    v=''
    [[ $CHECK_STATE != missing ]] && v=$(version_of "$t")
    case "$CHECK_STATE" in
      ok) print_row ok "$t" "$v" "${WHY[$t]:-}" ;;
      outdated) print_row outdated "$t" "$v" "$CHECK_NOTE" ;;
      missing) print_row missing "$t" '' "${WHY[$t]:-} -- $(install_cmd "$t")" ;;
    esac
  done
}

cmd_table() {
  printf '%s%s%s doctor %s-- %s%s\n' "$C_BOLD" "$C_ACCENT" "$I_GEAR" "$C_RESET$C_MUTED" "$PKGNAME" "$C_RESET"
  print_tier 'required' "${REQUIRED[@]}"
  print_tier 'recommended' "${RECOMMENDED[@]}"
  print_tier 'optional' "${OPTIONAL[@]}"

  printf '\n%s%s── project ──%s\n' "$C_BOLD" "$C_HEAD" "$C_RESET"
  project_checks
  local row state name note
  for row in "${project_rows[@]}"; do
    IFS='|' read -r state name note <<<"$row"
    print_row "$state" "$name" '' "$note"
  done

  collect_missing
  printf '\n'
  if ((${#MISSING_REQ[@]} > 0)); then
    printf '%s%s required deps missing:%s %s\n' "$C_RED" "$I_MISS" "$C_RESET" "${MISSING_REQ[*]}"
    printf '%sfix interactively:%s just doctor-install\n' "$C_MUTED" "$C_RESET"
    return 1
  fi
  if ((${#MISSING_OPT[@]} > 0)); then
    printf '%s%s optional deps missing:%s %s  %s(just doctor-install)%s\n' \
      "$C_YELLOW" "$I_WARN" "$C_RESET" "${MISSING_OPT[*]}" "$C_MUTED" "$C_RESET"
  else
    printf '%s%s all dependencies satisfied%s\n' "$C_GREEN" "$I_OK" "$C_RESET"
  fi
  return 0
}

# ── output: interactive install TUI ──────────────────────────────────────
cmd_install() {
  trap 'exit 130' INT TERM HUP
  collect_missing
  local -a missing=("${MISSING_REQ[@]+"${MISSING_REQ[@]}"}" "${MISSING_OPT[@]+"${MISSING_OPT[@]}"}")
  if ((${#missing[@]} == 0)); then
    printf '%s%s nothing to install -- everything is already there%s\n' "$C_GREEN" "$I_OK" "$C_RESET"
    return 0
  fi

  # label each candidate "tool -- backend -- why" (NO separators / headers!)
  local -a items=() chosen=()
  local t
  for t in "${missing[@]}"; do
    items+=("$(printf '%-16s %-8s %s' "$t" "${SRC[$t]:-brew}" "${WHY[$t]:-}")")
  done

  if has gum && [[ -t 0 && -t 1 ]]; then
    local sel rc=0
    sel=$(printf '%s\n' "${items[@]}" |
      gum choose --no-limit --selected='*' \
        --header="$I_BOX select deps to install (space toggles, enter confirms)" \
        --cursor='› ') || rc=$?
    ((rc != 0)) && {
      printf 'aborted\n'
      return 130
    }
    [[ -z "$sel" ]] && {
      printf 'nothing selected\n'
      return 0
    }
    mapfile -t chosen <<<"$sel"
  else
    printf 'run:\n'
    for t in "${missing[@]}"; do printf '  %s\n' "$(install_cmd "$t")"; done
    return 0
  fi

  local line tool failed=0
  for line in "${chosen[@]}"; do
    tool=${line%% *}
    printf '%s%s installing %s%s%s (%s)\n' "$C_ACCENT" "$I_BOX" "$C_RESET$C_BOLD" "$tool" "$C_RESET" "$(install_cmd "$tool")"
    if has gum; then
      gum spin --spinner=dot --title="$(install_cmd "$tool")" -- bash -c "$(install_cmd "$tool")" || failed=1
    else
      bash -c "$(install_cmd "$tool")" || failed=1
    fi
  done
  ((failed)) && {
    printf '%s%s some installs failed -- re-run: just doctor%s\n' "$C_RED" "$I_MISS" "$C_RESET"
    return 1
  }
  printf '%s%s done -- re-checking:%s\n' "$C_GREEN" "$I_OK" "$C_RESET"
  cmd_table
}

# ── dispatch (only when executed directly, not when sourced) ─────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --summary) cmd_summary ;;
    --factoid) cmd_factoid ;;
    --install) cmd_install ;;
    '') cmd_table ;;
    *) die "usage: doctor.bash [--summary|--factoid|--install]" ;;
  esac
fi
