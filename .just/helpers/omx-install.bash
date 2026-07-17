#!/usr/bin/env bash
# omx-install.bash -- install / uninstall the omx CLI globally from this checkout.
#
#   omx-install.bash install      pnpm add -g <this-repo>, then verify on PATH
#   omx-install.bash uninstall    pnpm remove -g oh-my-codex, then verify gone
#   omx-install.bash reinstall    uninstall then install (full cycle)
#
# node comes from fnm (operator rule -- never the Homebrew node); pnpm from
# corepack. Both are provisioned here so the recipe works from a bare shell.
#
# Pure GNU Bash 5.3+. Colors: terminal defaults via tput only.

# shellcheck source=lib.bash disable=SC2154,SC1091
source "$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)/lib.bash"
trap 'exit 130' INT TERM HUP

# fnm-provisioned node + corepack pnpm (mirrors the Justfile pnpm_cmd preamble)
# shellcheck disable=SC1090
source ~/.config/sh/fnm-init.sh >/dev/null 2>&1 || true
corepack enable >/dev/null 2>&1 || true

has pnpm || die "pnpm not found (run: just doctor-install)"

# on_path -- true when a callable `omx` resolves in the current PATH
on_path() { type -af "$BIN" >/dev/null 2>&1; }

do_uninstall() {
  printf '%s── omx-uninstall: removing global %s ──%s\n' "$C_HEAD" "$PKGNAME" "$C_RESET"
  if pnpm list -g --depth=0 2>/dev/null | rg -q "$PKGNAME"; then
    pnpm remove -g "$PKGNAME"
    printf '%somx-uninstall: removed %s%s\n' "$C_GREEN" "$I_OK" "$C_RESET"
  else
    printf 'omx-uninstall: nothing to remove (not installed globally)\n'
  fi
  if on_path; then
    printf '%sWARNING: %s still on PATH after uninstall:%s\n' "$C_YELLOW" "$BIN" "$C_RESET" >&2
    type -af "$BIN" >&2
  else
    printf '%somx-uninstall: verified not on PATH %s%s\n' "$C_GREEN" "$I_OK" "$C_RESET"
  fi
}

do_install() {
  printf '%s── omx-install: installing from %s ──%s\n' "$C_HEAD" "$REPO_ROOT" "$C_RESET"
  pnpm add -g "$REPO_ROOT"
  printf '%somx-install: installed %s%s\n' "$C_GREEN" "$I_OK" "$C_RESET"
  if on_path; then
    printf '  %s\n' "$(type -af "$BIN" 2>/dev/null | head -1)"
  else
    printf '%sWARNING: %s not on PATH after install%s\n' "$C_YELLOW" "$BIN" "$C_RESET" >&2
    printf 'hint : ensure ~/Library/pnpm/bin precedes system paths in PATH\n' >&2
  fi
}

case "${1:-}" in
  install) do_install ;;
  uninstall) do_uninstall ;;
  reinstall)
    do_uninstall
    do_install
    ;;
  '') die "usage: omx-install.bash {install|uninstall|reinstall}" ;;
  *) die "omx-install.bash: unknown action '$1' (want install|uninstall|reinstall)" ;;
esac
