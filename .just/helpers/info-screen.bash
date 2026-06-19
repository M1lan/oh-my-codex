#!/usr/bin/env bash
# info-screen.bash -- the screen-filling welcome shown by a bare `just`.
#
#   info-screen.bash            full splash + countdown (default recipe)
#   info-screen.bash --static   facts only, no countdown (the `info` recipe)
#
# Countdown contract (the whole point of the bare `just`):
#   enter / m   -> exec just menu   (guided gum builder)
#   f           -> exec just fzf    (flat fzf power launcher)
#   d           -> exec just doctor
#   t           -> exec just test
#   any other   -> back to shell immediately
#   timeout     -> print ONE frugal factoid (missing deps first), exit 0
# Default timeout 6.7 s (tenths-resolution display); JUST_SPLASH_SECS overrides
# (accepts "5" or "4.2"). A hi-viz KEYS box shows the hotkeys: vertical rail on
# the left when very wide, horizontal bar at the bottom otherwise.
#
# Layout adapts to the terminal's width:
#   very wide (cols >= 144)          KEYS rail + three panel columns
#   wide      (cols >= 130)          three panel columns + KEYS bar
#   square    (96 <= cols < 130)     two panel columns + KEYS bar
#   portrait  (78 <= cols < 96)      stacked single column + KEYS bar
#   tiny/non-tty/no-gum              degrade to --static (no countdown) --
#                                    NEVER to the bare list (that's `just help`)
#
# Facts are FILE-PARSE ONLY -- this script must never spawn node/cargo.
# Iron Rule 5: never clear the screen / destroy scrollback -- print inline.
# Pure GNU Bash 5.3+. Colors: terminal defaults via tput only; boxes via gum.

# shellcheck source=lib.bash disable=SC2154,SC1091
source "$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)/lib.bash"
cd "$REPO_ROOT" || exit 1

# restore terminal state on EVERY exit path (incl. before exec, which
# skips EXIT traps)
restore() { is_tty && tput cnorm 2>/dev/null; }
trap 'restore; exit 130' INT TERM HUP

STATIC=0
[[ "${1:-}" == "--static" ]] && STATIC=1

# ── degradation: bare `just` ALWAYS shows the info splash ────────────────
# When a real interactive tty of usable size is unavailable, degrade to
# --static (same screen, no countdown) -- NEVER to bare `just --list`.
if ((!STATIC)); then
  { is_tty && [[ -t 0 ]]; } || STATIC=1
fi
COLS=$(term_cols)
LINES_=$(term_lines)
if ! has gum || ((COLS < 78 || LINES_ < 24)); then
  STATIC=1
fi

# ── gather facts (file parsing only -- instant, no node/cargo) ───────────
branch=$(fact_branch)
dirty=$(fact_dirty)
last=$(fact_last_commit)
((${#last} > 26)) && last="${last:0:25}…"
pkg_v=$(fact_pkg_version)
node_req=$(fact_node_req)
pnpm_v=$(fact_pnpm)
crates=$(fact_crates)
loc_ts=$(fact_loc ts src)
loc_rs=$(fact_loc rs crates)
built=$(fact_built)
deps=$(fact_deps)
toolbelt=$("$LIB_DIR/doctor.bash" --summary 2>/dev/null || true)

dirty_str="clean"
((dirty > 0)) && dirty_str="${dirty} dirty file(s)"

# ── banner ───────────────────────────────────────────────────────────────
banner() {
  if has figlet; then
    local art line i=0 n=${#BANNER_RAMP[@]}
    art=$(figlet -f smslant -w "$COLS" "$BIN" 2>/dev/null) ||
      art=$(figlet -f slant -w "$COLS" "$BIN" 2>/dev/null) ||
      art=$(figlet -w "$COLS" "$BIN")
    while IFS= read -r line; do
      local tint=''
      ((_ncolors >= 8)) && tint=$(tput setaf "${BANNER_RAMP[i % n]}" 2>/dev/null)
      printf '  %s%s%s\n' "$tint" "$line" "$C_RESET"
      ((i++)) || true
    done <<<"$art"
  else
    printf '\n  %s%s◢◤◢◤ %s ◥◣◥◣%s\n' "$C_BOLD" "$C_ACCENT" "${PKGNAME^^}" "$C_RESET"
  fi
  printf '  %s%s%s\n' "$C_BOLD" "$(fact_description)" "$C_RESET"
  printf '  %s%s node %s · pnpm %s · v%s · %s crate(s)%s\n' \
    "$C_MUTED" "$I_NODE" "$node_req" "$pnpm_v" "$pkg_v" "$crates" "$C_RESET"
}

# ── panel bodies (plain text; gum draws the boxes) ───────────────────────
panel_project() {
  printf '%s  PROJECT\n\n' "$I_GIT"
  printf 'branch    %s\n' "$branch"
  printf 'tree      %s\n' "$dirty_str"
  printf 'last      %s\n' "$last"
  printf 'package   v%s (node %s)\n' "$pkg_v" "$node_req"
  printf 'source    %s ts · %s rs\n' "$loc_ts" "$loc_rs"
}

panel_state() {
  printf '%s  STATE\n\n' "$I_BOX"
  if [[ -n "$deps" ]]; then
    printf 'deps      installed\n'
  else
    printf 'deps      none -> just setup\n'
  fi
  if [[ -n "$built" ]]; then
    printf 'build     %s present\n' "$ENTRY"
  else
    printf 'build     none -> just build\n'
  fi
  printf 'rust      %s workspace crate(s)\n' "$crates"
}

panel_quickstart() {
  printf '%s  QUICK START\n\n' "$I_ROCKET"
  printf 'just %-11s guided launcher\n' 'menu'
  printf 'just %-11s power launcher\n' 'fzf'
  printf 'just %-11s build (tsc)\n' 'build'
  printf 'just %-11s run omx CLI\n' 'run'
  printf 'just %-11s full test suite\n' 'test'
  printf 'just %-11s rg->fzf->editor\n' 'search-fzf'
  printf 'just %-11s dependency audit\n' 'doctor'
}

panel_gates() {
  printf '%s  GATES\n\n' "$I_WEB"
  printf 'just %-11s full pre-push gate\n' 'verify'
  printf 'just %-11s biome lint (TS)\n' 'lint'
  printf 'just %-11s tsc no-unused\n' 'check-unused'
  printf 'just %-11s markdown lint\n' 'md-lint'
  printf 'just %-11s spell check\n' 'typos'
}

panel_rust() {
  printf '%s  RUST\n\n' "$I_RUST"
  printf 'just %-11s cargo build\n' 'rust-build'
  printf 'just %-11s cargo test\n' 'rust-test'
  printf 'just %-11s clippy -D warn\n' 'rust-lint'
  printf 'just %-11s cargo fmt\n' 'rust-fmt'
}

panel_status() {
  printf '%s  TOOLBELT & DOCS\n\n' "$I_GEAR"
  printf '%s\n\n' "${toolbelt:-doctor unavailable}"
  printf '%-14s approach & usage\n' 'README.md'
  printf '%-14s agent contract\n' 'AGENTS.md'
  printf '%-14s release flow\n' 'RELEASE_PROTOCOL.md'
}

# ── the hi-viz KEYS box (vertical rail / horizontal bar) ─────────────────
panel_keys_vertical() {
  printf '%s  KEYS\n\n' "$I_BOLT"
  printf '⏎ m   menu\n'
  printf 'f     fzf\n'
  printf 'd     doctor\n'
  printf 't     test\n'
  printf 'q     shell\n'
}

keys_bar_text() {
  printf '%s  ⏎/m menu · f fzf · d doctor · t test · q shell' "$I_BOLT"
}

# ── compose with gum (boxes + horizontal join) ───────────────────────────
render_panels() {
  local style=(--border rounded --border-foreground "$G_ACCENT" --padding "0 2" --margin "0 1")
  local keystyle=(--border thick --border-foreground "$G_WARN" --padding "0 2" --margin "0 1" --bold)
  local p1 p2 p3 rail body
  if ((COLS >= 144)); then # very wide: hi-viz KEYS rail LEFT + 3 columns
    local railw=16
    local w=$(((COLS - railw - 16) / 3))
    rail=$(panel_keys_vertical | gum style "${keystyle[@]}" --width "$railw")
    p1=$({
      panel_project
      printf '\n'
      panel_state
    } | gum style "${style[@]}" --width "$w")
    p2=$({
      panel_quickstart
      printf '\n'
      panel_rust
    } | gum style "${style[@]}" --width "$w")
    p3=$({
      panel_gates
      printf '\n'
      panel_status
    } | gum style "${style[@]}" --width "$w")
    gum join --horizontal --align top "$rail" "$p1" "$p2" "$p3"
  elif ((COLS >= 130)); then # landscape: 3 columns + KEYS bar at the BOTTOM
    local w=$(((COLS - 12) / 3))
    p1=$({
      panel_project
      printf '\n'
      panel_state
    } | gum style "${style[@]}" --width "$w")
    p2=$({
      panel_quickstart
      printf '\n'
      panel_rust
    } | gum style "${style[@]}" --width "$w")
    p3=$({
      panel_gates
      printf '\n'
      panel_status
    } | gum style "${style[@]}" --width "$w")
    gum join --horizontal --align top "$p1" "$p2" "$p3"
    keys_bar_text | gum style "${keystyle[@]}" --width $((COLS - 6))
  elif ((COLS >= 96)); then # squarish: 2 columns + KEYS bar at the BOTTOM
    local w=$(((COLS - 10) / 2))
    p1=$({
      panel_project
      printf '\n'
      panel_state
      printf '\n'
      panel_rust
    } | gum style "${style[@]}" --width "$w")
    p2=$({
      panel_quickstart
      printf '\n'
      panel_gates
      printf '\n'
      panel_status
    } | gum style "${style[@]}" --width "$w")
    gum join --horizontal --align top "$p1" "$p2"
    keys_bar_text | gum style "${keystyle[@]}" --width $((COLS - 6))
  else # portrait: stacked + KEYS bar at the BOTTOM
    local w=$((COLS - 6))
    for body in panel_project panel_state panel_quickstart panel_gates panel_rust panel_status; do
      "$body" | gum style "${style[@]}" --width "$w"
    done
    keys_bar_text | gum style "${keystyle[@]}" --width "$w"
  fi
}

# ── countdown footer ─────────────────────────────────────────────────────
# 6.7 s default, 0.1 s resolution; JUST_SPLASH_SECS accepts "5" or "4.2".
splash_tenths() {
  local s="${JUST_SPLASH_SECS:-6.7}"
  if [[ "$s" == *.* ]]; then
    printf '%s' "$((${s%.*} * 10 + ${s#*.}))"
  else
    printf '%s' "$((s * 10))"
  fi
}

countdown() {
  local t key rc total barw
  total=$(splash_tenths)
  barw=10
  tput civis 2>/dev/null
  drain_tty_input # gum's terminal-query replies must not count as hotkeys
  for ((t = total; t > 0; t--)); do
    # shrinking time bar: ceil so it only empties exactly at t=0
    local filled=$(((t * barw + total - 1) / total)) empty bar='' gap=''
    ((filled > barw)) && filled=barw
    empty=$((barw - filled))
    ((filled > 0)) && {
      printf -v bar '%*s' "$filled" ''
      bar=${bar// /█}
    }
    ((empty > 0)) && {
      printf -v gap '%*s' "$empty" ''
      gap=${gap// /░}
    }
    # the hi-viz countdown chip: timer icon + padded seconds in reverse video
    local chip
    printf -v chip ' %s %ss ' "$I_TIMER" "$(fmt_tenths "$t")"
    printf '\r  %s▌%s %s%s%s %s%s%s%s  %s⏎/m%s menu · %sf%s fzf · %sd%s doctor · %st%s test · %sq%s shell ' \
      "$C_BOLD$C_CYAN" "$C_RESET" \
      "$C_BOLD$C_YELLOW$C_REV" "$chip" "$C_RESET" \
      "$C_DIM" "$bar" "$gap" "$C_RESET" \
      "$C_BOLD$C_GREEN" "$C_RESET" "$C_BOLD$C_GREEN" "$C_RESET" \
      "$C_BOLD$C_GREEN" "$C_RESET" "$C_BOLD$C_GREEN" "$C_RESET" \
      "$C_BOLD" "$C_RESET"
    rc=0
    read -rsn1 -t 0.1 key || rc=$?
    if ((rc == 0)); then
      printf '\r'
      is_tty && tput el 2>/dev/null
      restore
      case "$key" in
        '' | m | M) exec just menu ;;
        f | F) exec just fzf ;;
        d | D) exec just doctor ;;
        t | T) exec just test ;;
        *) return 0 ;; # q / esc / arrows / anything -> shell
      esac
    fi
    ((rc > 128)) || break # rc 1 = EOF
  done
  printf '\r'
  is_tty && tput el 2>/dev/null
  restore
  # timeout: ONE frugal factoid, then nothing
  local factoid
  factoid=$("$LIB_DIR/doctor.bash" --factoid 2>/dev/null || true)
  printf '  %s%s%s %s\n' "$C_BOLD$C_YELLOW" "$I_BOLT" "$C_RESET" "${factoid:-just menu anytime · just help for the plain list}"
}

# ── main (Iron Rule 5: print inline, never clear) ────────────────────────
banner
printf '\n'
if has gum; then
  render_panels
else
  panel_project
  printf '\n'
  panel_state
  printf '\n'
  panel_quickstart
  printf '\n'
  panel_gates
fi
printf '\n'
((STATIC)) || countdown
restore
exit 0
