#!/usr/bin/env bash
# Symlink (or copy, per .dotfiles-copy) tracked dotfiles from $DOTFILES into $HOME. Invoked by the nix-darwin
# activation script as the primary user (not root). Expects DOTFILES,
# DOTFILES_REPO and DOTFILES_PUSH_URL in the environment.
set -euo pipefail

# Bootstrap: clone over HTTPS (no ssh-agent under sudo), then point pushes at SSH.
# GIT_CONFIG_GLOBAL=/dev/null keeps the user's https->ssh URL rewrite out of the clone.
if [ ! -d "$DOTFILES/.git" ]; then
  mkdir -p "$(dirname "$DOTFILES")"
  GIT_CONFIG_GLOBAL=/dev/null git clone "$DOTFILES_REPO" "$DOTFILES" \
    || { echo "warning: could not clone dotfiles (offline?); skipping" >&2; exit 0; }
  git -C "$DOTFILES" remote set-url --push origin "$DOTFILES_PUSH_URL"
fi

# Mirror every tracked path starting with a dot to the same path under $HOME.
# Tracked-only, so ignored/untracked files never land. Files are handled one by one,
# never whole ~/.config/<tool> dirs, so caches stay out of git.
# Default is a symlink; paths matching a glob in .dotfiles-copy are copied instead
# (for tools like apm that refuse symlinks). Copies are overwritten: repo wins.
copy_globs=$(grep -v -e '^#' -e '^$' "$DOTFILES/.dotfiles-copy" 2>/dev/null || true)
is_copy() {
  local p
  while IFS= read -r p; do
    [ -n "$p" ] && [[ $1 == $p ]] && return 0  # unquoted $p = glob; * also matches /
  done <<< "$copy_globs"
  return 1
}

git -C "$DOTFILES" ls-files | grep '^\.' | grep -vxE '\.gitignore|\.dotfiles-copy' | while read -r f; do
  mkdir -p "$HOME/$(dirname "$f")"
  if is_copy "$f"; then
    rm -f "$HOME/$f"  # never cp through a leftover symlink into the repo
    cp "$DOTFILES/$f" "$HOME/$f"
  else
    ln -sfn "$DOTFILES/$f" "$HOME/$f"
  fi
done

# Prune: remove links into the repo whose target no longer exists (file was git rm'd).
find "$HOME" -maxdepth 1 -type l -lname "$DOTFILES/*" ! -exec test -e {} \; -print -delete
find "$HOME/.config" -maxdepth 3 -type l -lname "$DOTFILES/*" ! -exec test -e {} \; -print -delete

# .zshrc sources this plugin; it is not in nixpkgs (zsh-fzf-tab is a different project).
plugin="$HOME/.oh-my-zsh/custom/plugins/fzf-tab-completion"
[ -d "$plugin" ] || git clone --depth 1 https://github.com/lincheney/fzf-tab-completion.git "$plugin" \
  || echo "warning: could not clone fzf-tab-completion" >&2
