#!/usr/bin/env bash
# Symlink tracked dotfiles from $DOTFILES into $HOME. Invoked by the nix-darwin
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

# Link every tracked path starting with a dot (except .gitignore) to the same path
# under $HOME. Tracked-only, so ignored/untracked files are never linked. Files are
# linked individually, never whole ~/.config/<tool> dirs, so caches stay out of git.
git -C "$DOTFILES" ls-files | grep '^\.' | grep -vx '.gitignore' | while read -r f; do
  mkdir -p "$HOME/$(dirname "$f")"
  ln -sfn "$DOTFILES/$f" "$HOME/$f"
done
ln -sfn "$DOTFILES/apm" "$HOME/.apm"

# Prune: remove links into the repo whose target no longer exists (file was git rm'd).
find "$HOME" -maxdepth 1 -type l -lname "$DOTFILES/*" ! -exec test -e {} \; -print -delete
find "$HOME/.config" -maxdepth 3 -type l -lname "$DOTFILES/*" ! -exec test -e {} \; -print -delete

# .zshrc sources this plugin; it is not in nixpkgs (zsh-fzf-tab is a different project).
plugin="$HOME/.oh-my-zsh/custom/plugins/fzf-tab-completion"
[ -d "$plugin" ] || git clone --depth 1 https://github.com/lincheney/fzf-tab-completion.git "$plugin" \
  || echo "warning: could not clone fzf-tab-completion" >&2
