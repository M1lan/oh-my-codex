#!/usr/bin/env bash
# entry.bash -- the smart bare-`just` entry point.
#
# Humans get the menu; agents and headless callers get a terse, token-lean
# recipe dump. Detection (first match wins):
#
#   OMX_MENU=1                      -> human (force the menu)
#   OMX_AGENT=1 / AGENT=1           -> agent
#   CI / CLAUDECODE / CODEX_*       -> agent (harness env markers)
#   no tty on stdin or stdout       -> agent/headless
#   ancestor shell fish or zsh      -> human (operator shells; agents are
#   ancestor shell bash/sh          -> agent   forced onto bash)
#   nothing recognizable            -> agent (safe: terse text, no UI grab)
#
# The agent dump is generated from `just --dump --dump-format json` (modules
# recursed, one level) -- it can never go stale. Format, one recipe per line:
#   just <name> [<params>]  -- <doc>
# Pure GNU Bash 5.3+. No color, no boxes, bounded output.
# Debug the verdict: OMX_ENTRY_TRACE=1 just   (prints the ancestor walk).

# shellcheck source=lib.bash disable=SC2154,SC1091
source "$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)/lib.bash"
cd "$REPO_ROOT" || exit 1

# ── audience detection ───────────────────────────────────────────────────
# Walk the parent chain and print the shell that INVOKED just. Shells seen
# before the `just` process are just's own recipe wrappers (bash -c) -- they
# must not count, or every verdict would be "bash". First shell above `just`
# decides; when `just` never appears (helper run directly), the first shell
# seen anywhere decides.
_ancestor_shell() {
  local pid=$PPID comm hops=0 seen_just=0 fallback=''
  while ((pid > 1 && hops < 15)); do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null) || break
    comm=${comm##*/} comm=${comm#-} # basename, strip login-shell dash
    [[ -z "${OMX_ENTRY_TRACE:-}" ]] || printf 'trace: pid=%s comm=%s seen_just=%s\n' "$pid" "$comm" "$seen_just" >&2
    case "$comm" in
      just) seen_just=1 ;;
      make | gmake) ;; # make's transient recipe shell sits below it -- skip
      fish | zsh | bash | sh)
        if ((seen_just)); then
          # a shell directly under make/gmake is make's own recipe shell,
          # not the caller -- keep walking
          local ppid pcomm
          ppid=$(ps -o ppid= -p "$pid" 2>/dev/null) && ppid=${ppid//[[:space:]]/}
          pcomm=$(ps -o comm= -p "${ppid:-1}" 2>/dev/null) && pcomm=${pcomm##*/}
          if [[ "$pcomm" == make || "$pcomm" == gmake ]]; then
            pid=$ppid
            ((hops++)) || true
            continue
          fi
          printf '%s' "$comm"
          return 0
        fi
        [[ -n "$fallback" ]] || fallback=$comm
        ;;
    esac
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null) || break
    pid=${pid//[[:space:]]/}
    [[ -n "$pid" ]] || break
    ((hops++)) || true
  done
  [[ -n "$fallback" ]] || return 1
  printf '%s' "$fallback"
}

# truthy env marker: set AND not a common "false" spelling (CI=false must
# not count as CI)
_marker_on() {
  case "${1,,}" in
    '' | 0 | false | no | off) return 1 ;;
    *) return 0 ;;
  esac
}

audience() { # prints "human" or "agent"
  if _marker_on "${OMX_MENU:-}"; then
    printf 'human'
    return
  fi
  if _marker_on "${OMX_AGENT:-}" || _marker_on "${AGENT:-}" || _marker_on "${CI:-}" ||
    _marker_on "${CLAUDECODE:-}" || _marker_on "${CODEX_SANDBOX:-}" || _marker_on "${CODEX_THREAD_ID:-}"; then
    printf 'agent'
    return
  fi
  if [[ -n "${SSH_ORIGINAL_COMMAND:-}" ]]; then
    printf 'agent'
    return
  fi
  # human needs a keyboard (stdin tty) and a screen (stdout OR stderr tty --
  # some shell integrations wrap stdout, and gum draws its UI on stderr)
  if [[ ! -t 0 ]] || [[ ! -t 1 && ! -t 2 ]]; then
    printf 'agent'
    return
  fi
  case "$(_ancestor_shell || true)" in
    fish | zsh) printf 'human' ;;
    *) printf 'agent' ;;
  esac
}

# ── terse recipe dump for agents ─────────────────────────────────────────
dump_recipes() {
  local jq_recipe_lines='
    def lines($prefix):
        .recipes
        | to_entries[]
        | select(.key | startswith("_") | not)
        | select(.key != "default")
        | select([.value.attributes[]? | strings] | index("private") | not)
        | [ "just " + $prefix + .key
            + ([.value.parameters[]?
                | " <" + .name
                  + (if .kind == "star" or .kind == "plus" then "...>"
                     elif .default != null then "?>"
                     else ">" end)
               ] | join("")),
            (.value.doc // "") ]
        | "\(.[0])  -- \(.[1])";
    lines(""),
    (.modules | to_entries[]
     | (.key + " ") as $p
     | ("just " + .key + "  -- " + (.key) + " module default (see below)"),
       (.value | lines($p)))'
  just --dump --dump-format json | jq -r "$jq_recipe_lines"
}

case "$(audience)" in
  human) exec "$LIB_DIR/menu.bash" ;;
  agent)
    printf '# oh-my-codex recipes (just <name>; bare module name runs its default)\n'
    dump_recipes
    ;;
esac
