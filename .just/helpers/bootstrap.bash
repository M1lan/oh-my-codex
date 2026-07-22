#!/usr/bin/env bash
# bootstrap.bash -- `make` lands here: install everything, show it live.
#
#   bootstrap.bash             orchestrator: bg installer + live splash + welcome
#   bootstrap.bash --install   the installer itself (runs in the background)
#   bootstrap.bash --welcome   re-render the welcome from the last stats
#   bootstrap.bash --force     always run the full install splash
#
# Flow:
#   1. spawn `--install` in the background, logging to .just/state/bootstrap.log
#   2. foreground: a 2 Hz "loading" splash whose DOMINANT panel is the live
#      install log; side rail shows identity, a steps checklist, and hotkeys.
#      NO timeout -- the splash stays until the installer finishes.
#      hotkeys: q abort install · s shell now (installer keeps running) ·
#               l follow the full log in less
#   3. success -> one-time ASCII-art welcome screen (stats + what-next),
#      4.2 s countdown: m menu · f fzf · any other key shell.
#   4. failure -> red summary + log tail, exit 1.
#
# oh-my-codex install layers: brew (just/UI/GNU) -> pnpm install (node deps) ->
# pnpm build (tsc) -> cargo build (the Rust crates).
#
# Iron Rule 5: NEVER clear the scrollback. The ONLY in-place repaint (this
# live splash) uses the ALTERNATE SCREEN BUFFER (tput smcup/rmcup + cup 0 0),
# exactly like less/fzf/vim -- it fully restores the primary screen on exit.
# Pure GNU Bash 5.3+. Colors: terminal defaults via tput only; boxes via gum.

# shellcheck source=lib.bash disable=SC2154,SC1091
source "$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)/lib.bash"
cd "$REPO_ROOT" || exit 1

LOG="$STATE_DIR/bootstrap.log"
STEPS="$STATE_DIR/bootstrap.steps"   # one line per step: name|state|detail
STATS="$STATE_DIR/bootstrap.stats"   # key=value lines
STATUS="$STATE_DIR/bootstrap.status" # running | ok | fail

ALT_ON=0 # tracks whether the alternate screen buffer is active

# ── step bookkeeping (installer side) ────────────────────────────────────
step_set() { # <name> <state> <detail>
  local name="$1" state="$2" detail="${3:-}" line out=''
  while IFS= read -r line; do
    [[ "$line" == "$name|"* ]] || out+="$line"$'\n'
  done <"$STEPS" 2>/dev/null
  printf '%s%s|%s|%s\n' "$out" "$name" "$state" "$detail" >"$STEPS"
}

# ── the installer (background process) ───────────────────────────────────
now_stamp() {
  if has gdate; then gdate '+%Y-%m-%d %H:%M:%S'; else date '+%Y-%m-%d %H:%M:%S'; fi
}

cmd_install() {
  local t0=$EPOCHSECONDS installed=() failed=()
  # doctor.bash provides PKG/check_tool + the catalogue
  # shellcheck source=doctor.bash disable=SC1091
  source "$LIB_DIR/doctor.bash"

  # layer 1: brew base (the UI + GNU + just themselves). UI tools first so the
  # splash can upgrade itself mid-install.
  step_set brew-base running 'scanning'
  if ! has brew; then
    printf 'FATAL: homebrew not found -- install from https://brew.sh first\n'
    step_set brew-base fail 'homebrew missing'
    printf 'fail\n' >"$STATUS"
    return 1
  fi
  local -a base=(just gum jq fzf bat fd rg gawk gsed gdate figlet git curl)
  local t n=0 missing=()
  for t in "${base[@]}"; do
    check_tool "$t"
    [[ $CHECK_STATE == ok ]] || missing+=("$t")
  done
  local total=${#missing[@]}
  if ((total == 0)); then
    printf 'brew: all %d base tools already present\n' "${#base[@]}"
    step_set brew-base 'done' 'all present'
  else
    for t in "${missing[@]}"; do
      ((++n))
      step_set brew-base running "$t ($n/$total)"
      printf '>> brew install %s  [%d/%d]\n' "${PKG[$t]:-$t}" "$n" "$total"
      if brew install "${PKG[$t]:-$t}" 2>&1; then installed+=("$t"); else
        failed+=("$t")
        printf '!! %s failed\n' "$t"
      fi
    done
    step_set brew-base 'done' "${#installed[@]} installed, ${#failed[@]} failed"
  fi

  # layer 2: node deps via pnpm (corepack-activate pnpm if missing)
  step_set node-deps running 'pnpm install'
  if ! has pnpm && has corepack; then
    printf '>> corepack enable  (activating pnpm)\n'
    corepack enable 2>&1 || true
  fi
  if has pnpm; then
    printf '>> pnpm install  (downloads node deps)\n'
    if pnpm install 2>&1; then step_set node-deps 'done' 'deps installed'; else
      step_set node-deps fail 'pnpm install failed'
      failed+=(pnpm-install)
    fi
  else
    printf 'pnpm: not present -- install node via fnm, then corepack enable\n'
    step_set node-deps fail 'no pnpm'
    failed+=(pnpm)
  fi

  # layer 3: TypeScript build (tsc via pnpm)
  step_set ts-build running 'pnpm run build'
  if has pnpm && [[ -d "$REPO_ROOT/node_modules" ]]; then
    printf '>> pnpm run build  (tsc -> dist/)\n'
    if pnpm run build 2>&1; then step_set ts-build 'done' 'compiled'; else
      step_set ts-build fail 'build failed'
      failed+=(ts-build)
    fi
  else
    printf 'build: skipped -- node deps not installed\n'
    step_set ts-build fail 'skipped (no deps)'
  fi

  # layer 4: Rust workspace build (best-effort)
  step_set rust-build running 'cargo build'
  if has cargo; then
    printf '>> cargo build  (compiles the omx Rust crates)\n'
    if cargo build 2>&1; then step_set rust-build 'done' 'compiled'; else
      step_set rust-build fail 'cargo build failed'
      failed+=(rust-build)
    fi
  else
    printf 'rust: cargo not present -- skipped (install via rustup)\n'
    step_set rust-build 'done' 'skipped (no cargo)'
  fi

  {
    printf 'duration=%s\n' "$((EPOCHSECONDS - t0))"
    printf 'installed=%s\n' "${installed[*]:-}"
    printf 'failed=%s\n' "${failed[*]:-}"
    printf 'pkg=%s\n' "$(fact_pkg_version)"
    printf 'node=%s\n' "$(fact_node_req)"
    printf 'loc_ts=%s\n' "$(fact_loc ts src)"
    printf 'loc_rs=%s\n' "$(fact_loc rs crates)"
    printf 'crates=%s\n' "$(fact_crates)"
    printf 'toolbelt=%s\n' "$("$LIB_DIR/doctor.bash" --summary 2>/dev/null || true)"
    printf 'finished=%s\n' "$(now_stamp)"
  } >"$STATS"

  if ((${#failed[@]} > 0)); then
    printf 'fail\n' >"$STATUS"
    return 1
  fi
  printf 'ok\n' >"$STATUS"
}

# ── alternate-screen helpers (Iron Rule 5 compliant repaint) ─────────────
enter_alt() { is_tty && ((!ALT_ON)) && {
  tput smcup 2>/dev/null
  ALT_ON=1
}; }
leave_alt() {
  is_tty && {
    ((ALT_ON)) && tput rmcup 2>/dev/null
    tput cnorm 2>/dev/null
  }
  ALT_ON=0
}

# ── splash rendering (orchestrator side) ─────────────────────────────────
SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

panel_identity() {
  printf '%s  BOOTSTRAP\n\n' "$I_BOX"
  printf '%s\n' "$PKGNAME"
  printf 'v%s · node %s\n' "$(fact_pkg_version)" "$(fact_node_req)"
  printf 'one make -- zero to ready\n'
}

panel_steps() { # <tick>
  local tick="$1" name state detail mark
  printf '%s  STEPS\n\n' "$I_GEAR"
  while IFS='|' read -r name state detail; do
    case "$state" in
      done) mark="${C_GREEN}✓${C_RESET}" ;;
      fail) mark="${C_RED}✗${C_RESET}" ;;
      running) mark="${C_CYAN}${SPIN[tick % ${#SPIN[@]}]}${C_RESET}" ;;
      *) mark="${C_DIM}·${C_RESET}" ;;
    esac
    printf '%b %-11s %s\n' "$mark" "$name" "$detail"
  done <"$STEPS" 2>/dev/null
}

panel_hotkeys() {
  printf '%sq abort · s shell · l log%s\n' "$C_DIM" "$C_RESET"
}

# log_body <height> <width> -- label + separator + tinted tail of the log
log_body() {
  local h="$1" w="$2" line bar
  printf -v bar '%*s' $((w - 4)) ''
  bar=${bar// /─}
  printf '%s%s install log — live%s\n' "$C_BOLD" "$I_DOC" "$C_RESET"
  printf '%s%s%s\n' "$C_DIM" "$bar" "$C_RESET"
  while IFS= read -r line; do
    case "$line" in
      *ERROR* | *error* | *Error* | *FAILED* | *'!!'* | *FATAL*)
        printf '%s%s%s\n' "$C_RED" "$line" "$C_RESET"
        ;;
      *Compiling* | *Finished* | *installed* | *Pouring* | *'>>'* | *Downloaded* | *done*)
        printf '%s%s%s\n' "$C_GREEN" "$line" "$C_RESET"
        ;;
      *) printf '%s%s%s\n' "$C_DIM" "$line" "$C_RESET" ;;
    esac
  done < <(tail -n $((h - 3)) "$LOG" 2>/dev/null)
}

render_splash() { # <tick>
  local tick="$1" cols lines_ logh
  cols=$(term_cols)
  lines_=$(term_lines)
  # home the cursor on the alternate screen instead of clearing (Iron Rule 5)
  is_tty && tput cup 0 0 2>/dev/null
  if ((cols >= 130)); then # wide: rail left + DOMINANT log right
    local railw=32
    local logw=$((cols - railw - 8))
    logh=$((lines_ - 5))
    ((logh < 6)) && logh=6
    local rail log
    rail=$({
      panel_identity
      printf '\n'
      panel_steps "$tick"
      printf '\n'
      panel_hotkeys
    } | gum style --border rounded --border-foreground "$G_ACCENT" --padding "0 1" --width $((railw - 2)))
    log=$(log_body "$logh" "$logw" |
      gum style --border thick --border-foreground "$G_WARN" --padding "0 1" \
        --width "$logw" --height "$logh")
    gum join --horizontal --align top "$rail" "$log"
  else # medium/portrait: strip + DOMINANT log below
    logh=$((lines_ - 16))
    ((logh < 5)) && logh=5
    {
      panel_identity
      printf '\n'
      panel_steps "$tick"
      printf '\n'
      panel_hotkeys
    } | gum style --border rounded --border-foreground "$G_ACCENT" --padding "0 1" --width $((cols - 6))
    log_body "$logh" $((cols - 6)) |
      gum style --border thick --border-foreground "$G_WARN" --padding "0 1" \
        --width $((cols - 6)) --height "$logh"
  fi
  printf '  %s%s installing -- the screen stays until everything is ready%s' \
    "$C_DIM" "${SPIN[tick % ${#SPIN[@]}]}" "$C_RESET"
  is_tty && tput el 2>/dev/null # clear trailing chars on THIS line only
  printf '\n'
}

render_plain() { # minimal output until gum/just exist (or non-tty)
  local last
  last=$(tail -n 1 "$LOG" 2>/dev/null)
  printf '\r%-*s' "$(term_cols)" "bootstrap: ${last:0:100}"
}

# ── welcome screen (one-time, after a successful (re)install) ────────────
welcome_art() {
  if has figlet; then
    local art line i=0 n=${#BANNER_RAMP[@]}
    art=$(figlet -f smslant "$BIN" 2>/dev/null) || art=$(figlet "$BIN" 2>/dev/null)
    while IFS= read -r line; do
      local tint=''
      ((_ncolors >= 8)) && tint=$(tput setaf "${BANNER_RAMP[i % n]}" 2>/dev/null)
      printf '  %s%s%s\n' "$tint" "$line" "$C_RESET"
      ((i++)) || true
    done <<<"$art"
  else
    printf '\n  %s%s %s %s\n' "$C_BOLD" "$C_ACCENT" "${PKGNAME^^}" "$C_RESET"
  fi
  printf '  %ssetup  ·  build  ·  orchestrate%s\n' "$C_BOLD" "$C_RESET"
}

read_stats() { # populates ST[] from the stats file
  declare -gA ST=()
  local k v
  while IFS='=' read -r k v; do [[ -n "$k" ]] && ST[$k]=$v; done <"$STATS" 2>/dev/null
}

# welcome_screen -- prints INLINE (Iron Rule 5): the caller must already have
# left the alternate screen so this appends to the real scrollback.
welcome_screen() {
  read_stats
  local cols
  cols=$(term_cols)
  welcome_art
  printf '\n'
  local w=$(((cols - 12) / 2))
  ((w < 36)) && w=36
  local left right
  left=$({
    printf '%stools installed%s    %s\n' "$C_DIM" "$C_RESET" "${ST[installed]:-none (all present)}"
    printf '%sinstall time%s       %ss\n' "$C_DIM" "$C_RESET" "${ST[duration]:-?}"
    printf '%spackage%s            v%s (node %s)\n' "$C_DIM" "$C_RESET" "${ST[pkg]:-?}" "${ST[node]:-?}"
    printf '%srust crates%s        %s\n' "$C_DIM" "$C_RESET" "${ST[crates]:-?}"
  } | gum style --border rounded --border-foreground "$G_ACCENT" --padding "0 3" --width "$w")
  right=$({
    printf '%ssource files%s       %s ts · %s rs\n' "$C_DIM" "$C_RESET" "${ST[loc_ts]:-?}" "${ST[loc_rs]:-?}"
    printf '%stoolbelt%s           %s\n' "$C_DIM" "$C_RESET" "${ST[toolbelt]:-?}"
    printf '%sfinished%s           %s\n' "$C_DIM" "$C_RESET" "${ST[finished]:-?}"
  } | gum style --border rounded --border-foreground "$G_ACCENT" --padding "0 3" --width "$w")
  gum join --horizontal --align top "$left" "$right"
  printf '\n'
  {
    printf '%sWHAT NEXT%s\n\n' "$C_BOLD" "$C_RESET"
    printf '%sjust%s              smart entry (menu for humans, terse dump for agents)\n' "$C_BOLD$C_CYAN" "$C_RESET"
    printf '%sjust menu%s         the human menu (splash + guided builder)\n' "$C_BOLD$C_CYAN" "$C_RESET"
    printf '%sjust ci%s           the full pre-push gate\n' "$C_BOLD$C_CYAN" "$C_RESET"
  } | gum style --border thick --border-foreground "$G_WARN" --padding "0 3" --margin "0 2"
  printf '%s\n' "$EPOCHSECONDS" >"$STATE_DIR/welcome-shown"

  # 4.2 s tenths countdown: ⏎/m menu · any other key -> shell
  local t key rc
  is_tty && tput civis 2>/dev/null
  drain_tty_input # gum's terminal-query replies must not count as hotkeys
  local secs="${JUST_WELCOME_SECS:-4.2}" tenths
  if [[ "$secs" == *.* ]]; then tenths=$((${secs%.*} * 10 + ${secs#*.})); else tenths=$((secs * 10)); fi
  for ((t = tenths; t > 0; t--)); do
    printf '\r  %s▌%s  %s%s %s %s  %s⏎/m%s menu   %sany key%s shell ' \
      "$C_BOLD$C_CYAN" "$C_RESET" \
      "$C_BOLD$C_YELLOW" "$C_REV" "$(fmt_tenths "$t")" "$C_RESET" \
      "$C_BOLD$C_GREEN" "$C_RESET" "$C_BOLD" "$C_RESET"
    rc=0
    read -rsn1 -t 0.1 key || rc=$?
    if ((rc == 0)); then
      printf '\r'
      is_tty && tput el 2>/dev/null
      is_tty && tput cnorm 2>/dev/null
      case "$key" in
        '' | m | M) exec just menu ;;
        *) return 0 ;;
      esac
    fi
    ((rc > 128)) || break
  done
  printf '\r'
  is_tty && tput el 2>/dev/null
  is_tty && tput cnorm 2>/dev/null
  printf '  %s%s%s just menu anytime\n' "$C_BOLD$C_YELLOW" "$I_BOLT" "$C_RESET"
}

# needs_bootstrap -- 0 (true) when there is real work to do: any required or
# recommended tool missing, node deps not installed, or the TS build absent.
# Lets the bare `make` hand straight to `just` on consecutive, already-set-up
# runs (fast + silent) instead of replaying the whole install splash.
needs_bootstrap() {
  # shellcheck source=doctor.bash disable=SC1091
  source "$LIB_DIR/doctor.bash" # provides check_tool + the tier arrays
  local t
  for t in "${REQUIRED[@]}" "${RECOMMENDED[@]}"; do
    check_tool "$t"
    [[ $CHECK_STATE == ok ]] || return 0
  done
  [[ -n "$(fact_deps)" ]] || return 0
  [[ -n "$(fact_built)" ]] || return 0
  return 1 # fully provisioned -- nothing to do
}

# ── orchestrator ─────────────────────────────────────────────────────────
cmd_bootstrap() {
  # fast path: everything already in place -> just hand over to the splash.
  if [[ "${1:-}" != --force ]] && has just && ! needs_bootstrap; then
    exec just
  fi
  mkdir -p "$STATE_DIR"
  : >"$LOG"
  : >"$STEPS"
  printf 'running\n' >"$STATUS"
  step_set brew-base pending ''
  step_set node-deps pending ''
  step_set ts-build pending ''
  step_set rust-build pending ''

  "${BASH_SOURCE[0]}" --install >>"$LOG" 2>&1 &
  local pid=$!
  trap 'leave_alt; exit 130' INT TERM HUP

  local tick=0 key rc status fancy
  while :; do
    status=$(<"$STATUS")
    [[ "$status" != running ]] && break
    kill -0 "$pid" 2>/dev/null || {
      status=fail
      printf 'fail\n' >"$STATUS"
      break
    }
    fancy=0
    if is_tty && [[ -t 0 ]] && has gum && has just && (($(term_cols) >= 78)); then fancy=1; fi
    if ((fancy)); then
      enter_alt
      is_tty && tput civis 2>/dev/null
      render_splash "$tick"
    else render_plain; fi
    rc=0
    read -rsn1 -t 0.5 key || rc=$?
    # stdin at EOF (rc=1, non-tty) returns instantly -> pace the loop by hand
    ((rc == 1)) && sleep 0.5
    if ((rc == 0)); then
      case "$key" in
        q | Q)
          leave_alt
          printf '\n%saborting -- killing installer (pid %s)%s\n' "$C_RED" "$pid" "$C_RESET"
          kill "$pid" 2>/dev/null
          printf 'fail\n' >"$STATUS"
          exit 130
          ;;
        s | S)
          leave_alt
          printf '\n%sinstall continues in the background%s -- follow it: tail -f %s\n' \
            "$C_BOLD" "$C_RESET" "${LOG#"$REPO_ROOT"/}"
          exit 0
          ;;
        l | L)
          leave_alt
          "${PAGER:-less}" +F "$LOG" || true
          ;;
      esac
    fi
    ((tick++)) || true
  done
  wait "$pid" 2>/dev/null
  leave_alt # back to the primary screen + scrollback before printing results

  status=$(<"$STATUS")
  if [[ "$status" == ok ]]; then
    if is_tty && has gum && has figlet; then
      welcome_screen
    else
      printf 'bootstrap ok -- run: just\n'
    fi
  else
    printf '%s%s bootstrap FAILED%s -- last log lines:\n\n' "$C_BOLD$C_RED" "$I_MISS" "$C_RESET"
    tail -n 15 "$LOG" 2>/dev/null
    printf '\nfull log: %s\nretry: make\n' "${LOG#"$REPO_ROOT"/}"
    exit 1
  fi
}

# ── dispatch ─────────────────────────────────────────────────────────────
case "${1:-}" in
  --install) cmd_install ;;
  --welcome) welcome_screen ;;      # re-render from the last bootstrap stats
  --force) cmd_bootstrap --force ;; # always run the full install splash
  '') cmd_bootstrap ;;
  *) die "usage: bootstrap.bash [--install|--welcome|--force]" ;;
esac
