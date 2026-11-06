# nix-darwin-config

A [nix-darwin](https://github.com/nix-darwin/nix-darwin) flake for a whole Mac: CLI tools
from nixpkgs, apps from Homebrew and the App Store, dotfiles linked from a separate repo,
and a sandbox for coding agents.

## Layout

| Path | What it is |
|------|------------|
| `user.nix` | **Who and what machine.** User name, hostname, CPU, dotfiles repo. Edit this first when forking. |
| `flake.nix` | Inputs (nixpkgs, nix-darwin) and outputs: the system config, `nix fmt`, and a shellcheck `nix flake check`. |
| `configuration.nix` | The system: nix packages, Homebrew taps/brews/casks, App Store apps, zsh, direnv, Touch ID sudo. |
| `link-dotfiles.sh` | Run on every switch. Clones the dotfiles repo if missing, then links its dotfiles into `$HOME`. |
| `sandbox/` | `sandbox` command: run Claude/Gemini/OpenCode in a smolvm microVM. Optional, see [sandbox/README.md](sandbox/README.md). |
| `tools/` | Odds and ends not wired into the system (e.g. a Google Apps Script). |

## Dotfiles

Dotfiles live in their own repo (set in `user.nix`), not here. On every switch,
`link-dotfiles.sh`:

1. Clones the repo over HTTPS to `~/<dotfiles.dir>` if it isn't there, then sets the push URL to SSH.
2. Symlinks every **git-tracked** path starting with `.` to the same path under `$HOME`
   (e.g. `.config/nvim/init.vim` → `~/.config/nvim/init.vim`). Untracked files are never linked.
3. Copies instead of linking any path matching a glob in the repo's `.dotfiles-copy`
   (for tools that reject symlinks). The repo wins: copies are overwritten each switch.
4. Removes symlinks whose target was `git rm`'d.

The checkout path is exported as `$DOTFILES`. To start your own dotfiles repo, create one
with your dotfiles at the paths they'd have under `$HOME` (`.zshrc`, `.gitconfig`,
`.config/...`). Never commit credentials (`.npmrc`, `.aws/`, `.kube/`, gh tokens).
Don't want any of this? Set `dotfiles = null;` in `user.nix`.

## Fork it

1. **Install Nix.** [Determinate Nix](https://determinate.systems/nix-installer/) is assumed:
   `nix.enable = false` here because Determinate manages the Nix daemon. With upstream Nix,
   remove that line.
2. **Install [Homebrew](https://brew.sh).** nix-darwin drives it but doesn't install it.
3. **Fork and clone** to `/etc/nix-darwin` (the path `nh` is configured with):
   ```sh
   sudo git clone https://github.com/<you>/nix-darwin-config /etc/nix-darwin
   sudo chown -R "$(whoami)" /private/etc/nix-darwin
   ```
4. **Edit `user.nix`:** `username` (`whoami`), `hostname` (`scutil --get LocalHostName`),
   `system`, and your `dotfiles` repo (or `null`).
5. **Trim `configuration.nix`** to the packages, casks and `masApps` you want. Sign in to the
   App Store first or remove `masApps`. Note `cleanup = "uninstall"`: Homebrew packages *not*
   listed get removed on switch.
6. **Drop the sandbox** if you don't want it: remove `./sandbox` from `modules` in `flake.nix`.
7. **First switch** (nh isn't installed yet):
   ```sh
   cd /etc/nix-darwin
   sudo nix run nix-darwin -- switch --flake .
   ```

## Day to day

```sh
nh darwin switch            # apply changes (from any directory)
nh darwin switch --update   # also update flake.lock
nix flake check             # eval the config + shellcheck the scripts
nix fmt                     # format .nix files
nh clean all --keep-since 14d
```

Commits use [Conventional Commits](https://www.conventionalcommits.org).
