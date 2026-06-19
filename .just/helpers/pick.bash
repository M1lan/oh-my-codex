#!/usr/bin/env bash
# pick.bash -- fuzzy-pick a source file (bat preview) and open it in $EDITOR.
# Searches the TypeScript (src) and Rust (crates) trees.
# shellcheck source=lib.bash disable=SC1091
source "$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)/lib.bash"
cd "$REPO_ROOT" || exit 1
trap 'exit 130' INT TERM HUP

has fzf || die "fzf not installed (run: just doctor-install)"
has fd || die "fd not installed (run: just doctor-install)"
has bat || die "bat not installed (run: just doctor-install)"

file="$(fd -e ts -e rs --type f . src crates 2>/dev/null |
  fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}' || true)"
[[ -z "$file" ]] && exit 0
"${EDITOR:-vim}" "$file"
