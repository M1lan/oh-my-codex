# lib.bash -- shared library for .just/helpers/*.bash
#
# GNU Bash >= 5.3 ONLY. This file is SOURCED, never executed.
# shellcheck shell=bash disable=SC2034  # variables are consumed by sourcing helpers
# Colors come exclusively from tput DEFAULT terminal colors (setaf 0-7).
# No themes, no hardcoded palettes -- the terminal's own scheme is the theme.

((BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 3))) || {
  printf 'error: GNU Bash >= 5.3 required, got %s\n' "$BASH_VERSION" >&2
  printf 'hint : brew install bash  (/opt/homebrew/bin must precede /bin in PATH)\n' >&2
  exit 1
}

# re-source guard (bootstrap sources lib.bash AND doctor.bash, which sources
# lib.bash again -- the readonly repo facts below would collide)
[[ -n "${_JUST_LIB_LOADED:-}" ]] && return 0
_JUST_LIB_LOADED=1

set -o pipefail

# ── repo facts ───────────────────────────────────────────────────────────
LIB_DIR=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)
REPO_ROOT=$(cd -- "$LIB_DIR/../.." && pwd)
readonly LIB_DIR REPO_ROOT
PKGNAME="oh-my-codex"
BIN="omx"                          # the published CLI bin name
ENTRY="dist/cli/omx.js"            # built entrypoint (run from source)
STATE_DIR="$REPO_ROOT/.just/state" # runtime state (gitignored): bootstrap log/stats

# ── tiny utils ───────────────────────────────────────────────────────────
has() { command -v -- "$1" >/dev/null 2>&1; }
die() {
  printf '%s\n' "$*" >&2
  exit 1
}
is_tty() { [[ -t 1 ]]; }

# Terminal size. GOTCHA: `tput cols` inside $() sees a pipe (not the tty)
# and silently reports 80 -- ask the controlling tty via stty instead.
# Precedence: COLUMNS/LINES env (test override) > stty on /dev/tty > tput > 80x24.
_term_size() { # sets _TERM_COLS _TERM_LINES
  local sz=''
  if [[ -z "${COLUMNS:-}" || -z "${LINES:-}" ]] && [[ -r /dev/tty ]]; then
    # 2>/dev/null BEFORE </dev/tty: redirections apply left-to-right, and on
    # macOS [[ -r /dev/tty ]] passes even without a controlling tty -- the
    # failing open must already have stderr silenced
    sz=$({ command -v gstty >/dev/null && gstty size || stty size; } 2>/dev/null </dev/tty) || sz=''
  fi
  # stty reports "0 0" on degenerate ptys (Emacs shell, fresh pty wrappers):
  # right SHAPE, useless VALUES -- treat non-positive as "no answer".
  if [[ $sz == +([0-9])\ +([0-9]) ]] && ((${sz% *} > 0 && ${sz#* } > 0)); then
    _TERM_COLS=${COLUMNS:-${sz#* }}
    _TERM_LINES=${LINES:-${sz% *}}
  else
    _TERM_COLS=${COLUMNS:-$(tput cols 2>/dev/null || printf 80)}
    _TERM_LINES=${LINES:-$(tput lines 2>/dev/null || printf 24)}
  fi
  # last-resort sanity (tput can also echo 0 on a 0x0 pty)
  ((_TERM_COLS > 0)) || _TERM_COLS=80
  ((_TERM_LINES > 0)) || _TERM_LINES=24
}
term_cols() {
  _term_size
  printf '%s' "$_TERM_COLS"
}
term_lines() {
  _term_size
  printf '%s' "$_TERM_LINES"
}

# fmt_tenths <tenths> -> "6.7" (fractional countdowns tick in 0.1s units)
fmt_tenths() { printf '%d.%d' "$(($1 / 10))" "$(($1 % 10))"; }

# drain_tty_input -- swallow pending stdin bytes before a hotkey read loop.
# gum/lipgloss QUERIES the terminal while styling (DSR ESC[6n, OSC 11 bg) when
# its stdout is the tty; the terminal's REPLIES land in our stdin, and the
# first `read -rsn1` would eat the reply's ESC -> "any key -> shell" -> the
# countdown exits instantly. Burst-drain until the line is quiet for 100ms.
drain_tty_input() {
  local _junk
  while read -rsn1 -t 0.1 _junk; do
    while read -rsn1 -t 0.02 _junk; do :; done
  done
}

# ── colors: terminal DEFAULT colors via tput only (themes are abolished) ─
_ncolors=0
if is_tty && [[ -z "${NO_COLOR:-}" ]]; then
  _ncolors=$(tput colors 2>/dev/null || printf 0)
fi

if ((_ncolors >= 8)); then
  C_RESET=$(tput sgr0) C_BOLD=$(tput bold) C_DIM=$(tput dim)
  C_RED=$(tput setaf 1) C_GREEN=$(tput setaf 2) C_YELLOW=$(tput setaf 3)
  C_BLUE=$(tput setaf 4) C_MAGENTA=$(tput setaf 5) C_CYAN=$(tput setaf 6)
  C_ACCENT=$C_CYAN C_HEAD=$C_BLUE C_MUTED=$C_DIM
  C_REV=$(tput rev 2>/dev/null) # reverse video -- tput is $TERM-only, so
  # it MUST live behind this tty/color gate
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW=''
  C_BLUE='' C_MAGENTA='' C_CYAN='' C_ACCENT='' C_HEAD='' C_MUTED='' C_REV=''
fi
# ANSI palette indexes for gum/fzf flags (resolved against the terminal's
# own scheme -- default colors, not hex)
G_ACCENT=6 # cyan
G_OK=2     # green
G_WARN=3   # yellow
# banner gradient cycles the default ANSI colors (cyan/blue/green)
BANNER_RAMP=(6 4 2 6 4 2)

# ── icons (nerdfont, with plain-ascii fallback via NO_NERDFONT=1) ────────
if [[ -n "${NO_NERDFONT:-}" ]]; then
  I_OK='[ok]' I_MISS='[--]' I_WARN='[!]' I_GEAR='*' I_ROCKET='>' I_TEST='#'
  I_NODE='N' I_GIT='Y' I_BOX='=' I_DOC='~' I_BOLT='!' I_SEARCH='?' I_WEB='@' I_RUST='R'
  I_TIMER='[t]'
else
  I_OK='' I_MISS='' I_WARN='' I_GEAR='' I_ROCKET='󱓞' I_TEST='󰙨'
  I_NODE='' I_GIT='' I_BOX='󰏗' I_DOC='󰈙' I_BOLT='󱐋' I_SEARCH='' I_WEB='󰖟' I_RUST=''
  I_TIMER=''
fi

# ── fast project facts (file parsing only -- never spawns node/cargo) ────
_pkg_json="$REPO_ROOT/package.json"

# _jq_pkg <filter> -- read a value from package.json (jq when present, else rg)
_jq_pkg() {
  [[ -f $_pkg_json ]] || {
    printf '?'
    return
  }
  if has jq; then
    jq -r "$1 // \"?\"" "$_pkg_json" 2>/dev/null || printf '?'
  else
    printf '?'
  fi
}

fact_pkg_version() {
  local v
  v=$(_jq_pkg '.version')
  [[ -n $v ]] || v='?'
  printf '%s' "$v"
}

fact_node_req() {
  local v
  v=$(_jq_pkg '.engines.node')
  printf '%s' "${v:-?}"
}

fact_pnpm() { # "11.5.3" from "pnpm@11.5.3"
  local v
  v=$(_jq_pkg '.packageManager')
  printf '%s' "${v#pnpm@}"
}

fact_description() {
  local v
  v=$(_jq_pkg '.description')
  printf '%s' "${v:-multi-agent orchestration for Codex}"
}

# fact_crates -- count of workspace members in Cargo.toml
fact_crates() {
  local f="$REPO_ROOT/Cargo.toml"
  [[ -f $f ]] || {
    printf '0'
    return
  }
  rg -c '^\s*"crates/' "$f" 2>/dev/null || printf '0'
}

fact_branch() {
  git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '(no git)'
}

fact_dirty() {
  git -C "$REPO_ROOT" status --porcelain 2>/dev/null | gawk 'END { print NR }'
}

fact_last_commit() {
  git -C "$REPO_ROOT" log -1 --format='%h %s' 2>/dev/null || printf '(none)'
}

# fact_loc <ext> <dir>  -- summed count of *.<ext> files under dir
fact_loc() {
  local ext="$1" dir="$REPO_ROOT/$2"
  [[ -d $dir ]] || {
    printf '0'
    return
  }
  fd -e "$ext" . "$dir" -X gawk 'END { print NR }' 2>/dev/null || printf '?'
}

# fact_mtime <file> -- "YYYY-mm-dd HH:MM" mtime, or empty when absent
fact_mtime() {
  local f="$REPO_ROOT/$1"
  [[ -f $f ]] || return 0
  if has gdate; then
    gdate -r "$f" '+%Y-%m-%d %H:%M'
  else
    date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null || true
  fi
}

# fact_built -- "built" when the compiled CLI entrypoint exists, else empty
fact_built() {
  [[ -f "$REPO_ROOT/$ENTRY" ]] && printf 'built'
}

# fact_deps -- "installed" when node_modules is present, else empty
fact_deps() {
  [[ -d "$REPO_ROOT/node_modules" ]] && printf 'installed'
}
