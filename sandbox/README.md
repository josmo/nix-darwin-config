# sandbox

Run a coding agent (Claude, OpenCode, Codex, Antigravity, …) in a microVM with
[smolbento](https://github.com/pelotech/smolbento) (`bento`). The agent works on its own clone of
the repo, with filtered network access and no real credentials. Only its commits come back.

This folder stands alone: the `sandbox` script, its kits and its notes. Nix is optional.

## Usage

```sh
cd <git repo>
sandbox                 # Claude (default)
sandbox opencode        # or: codex, copilot, cursor, shell, … (smolbento's built-in agents)
sandbox antigravity     # an agent from a workload kit (agents/antigravity.yaml)
sandbox claude -- -c    # arguments after the agent go to it (the -- is optional)
sandbox --env-arg region=eu opencode   # args for the env files come first
```

`sandbox` stages [your instructions](#your-instructions), then runs `bento env run` with
[env files](#env-files). Everything else is plain `bento`:

```sh
bento ls                       # sandboxes
bento rm claude-<repo>         # remove one (also removes its git remote: merge first)
bento policy log               # what the network policy blocked
```

When the agent exits, its commits are fetched to the remote `sandbox-<agent>-<repo>`:

```sh
git log  main..sandbox-claude-<repo>/main
git merge sandbox-claude-<repo>/main
```

Each repo + agent gets one sandbox, created on first use and reused after. The clone starts
from your last commit; uncommitted changes aren't copied in.

The first run asks `Approve this plan?` (it needs a terminal), and so does a run after any env
file or its inputs change, such as a new signing key. Changes to kits, workspaces or ports only
reach new sandboxes: `bento rm <name>`, then `sandbox` again.

Sandboxes made by `sandbox` before it used env files aren't found by `bento env run` ("not found
for this environment"): merge their commits, `bento rm` them, and run `sandbox` again.

## Env files

`sandbox` passes these [sbxenv.yaml](https://github.com/pelotech/smolbento/blob/main/docs/usage.md#environments-sbxenvyaml)
files to `bento env run`, the ones that exist, in this order (later wins: maps merge, lists add up):

1. [`sbxenv.yaml`](sbxenv.yaml): the clone, your staged instructions (read-only), the kits and
   a few variables.
2. `agents/<agent>.yaml`: for agents that come from a kit, such as
   [Antigravity](agents/antigravity.yaml).
3. `~/.config/sandbox/agents/<agent>.yaml`: your own kit-based agents.
4. `~/.config/sandbox/sbxenv.yaml`: your own additions for every sandbox (kits, `env`, memory).
5. `./sbxenv.yaml`: the project's, from the directory you run `sandbox` in. Run it from the
   repo's root: from a subdirectory, that subdirectory is the workspace and the place it looks.

(`~/.config` is `$XDG_CONFIG_HOME` if set.) Preview what a run would do with `bento env plan`
and the same files.

`sandbox` passes the args `agent`, `workspace` (the current directory), `stage` and
`signingKey`; your files can use them as `${{ env.args.NAME }}`. Pass others, such as a project
file's required ones, with `--env-arg NAME=VALUE` before the agent. `${{ env.projectDir }}` and
`SBX_ENV_DIR` name the first file's directory, which here is this folder, not your repo: use
`${{ env.args.workspace }}` for the repo.

A project's `sbxenv.yaml` works on its own too: teammates without `sandbox` can use it with
plain `bento env run` (or Docker's `sbx env run`). Being last, its `agent:` and `name:` win over
the agent you ask `sandbox` for: in a file meant to work both ways, write
`agent: ${{ env.args.agent }}` with `args: {agent: {default: claude}}`, and leave `name:` out.

A project file can also run commands on your Mac, mount your directories, add kits, change the
agent, or turn off the clone (or point the workspace elsewhere) so the agent writes straight to
your checkout. All of it shows in the approval plan before anything runs, so read it before you
approve a file you didn't write.

## Install

Pick how much you take. Each option builds on the one before it:

| You take | You get | You need |
|----------|---------|----------|
| [1. Just the sandbox](#1-just-the-sandbox) | The `sandbox` command | Homebrew |
| [2. Plus nix-darwin-config](#2-plus-nix-darwin-config) | The above, installed with the rest of your Mac's setup | Nix and Homebrew; a fork of this repo |
| [3. Plus dotfiles](#3-plus-dotfiles) | The above, plus shared instructions and smolbento settings that follow you between Macs | A dotfiles repo (a fork of [mine](https://github.com/josmo/dotfiles) or your own) |

All three need smolbento 0.29 or newer (its command is `bento`). Then do the
[one-time setup](#once-whichever-you-pick).

### 1. Just the sandbox

No Nix and no fork: clone this repo anywhere and link the script onto your `PATH`.

```sh
brew install pelotech/tap/smolbento   # brings its own smolvm on first use
git clone https://github.com/josmo/nix-darwin-config.git
mkdir -p ~/.local/bin
ln -s "$PWD/nix-darwin-config/sandbox/sandbox" ~/.local/bin/sandbox   # or any dir on your PATH
```

If `~/.local/bin` isn't on your `PATH` yet, add `export PATH="$HOME/.local/bin:$PATH"` to
`~/.zshrc`. `sandbox` finds its kits next to itself (through the link), so `git pull` updates
everything. The rest of the repo is unused.

### 2. Plus nix-darwin-config

Fork the repo and follow [Fork it](../README.md#fork-it) in the main README. Keep `./sandbox`
in the flake's `modules`: it installs the `sandbox` command, Homebrew's smolbento and Docker's
`sbx`. Set `dotfiles = null;` in `user.nix` if you're not taking option 3.

The command runs from the Nix store copy of this folder, so edits here (to the script, kits or
env files) take effect after `nh darwin switch`, not on save. Your own files under
`~/.config/sandbox/` aren't affected: they're read on each run.

### 3. Plus dotfiles

Point `dotfiles` in `user.nix` at your dotfiles repo; on every switch, `link-dotfiles.sh` links
its files into your home (see [Dotfiles](../README.md#dotfiles)). For the sandbox, the files that
matter are:

| In the dotfiles repo | What it does | Instead of |
|----------------------|--------------|------------|
| `.config/sandbox/instructions/*.md` | [Your instructions](#your-instructions) for every agent. Mine: `10-core.md`, a link to the `core.md` my agents on the Mac read too, and `20-host.md`, the host tools that aren't in the VM | Making the folder by hand |
| `.config/smolbento/secrets.toml` | The Claude token as a 1Password reference (`op://Private/claude-sandbox/credential`), not the token. Put your own `claude setup-token` token in 1Password and point the reference at it | `bento secret set claude` (setup step 2) |
| `.config/smolbento/config.toml` | smolbento settings; mine points the SSH agent at 1Password's socket. Change the user name in the path, or drop the file if you use the default SSH agent | — |

The rest stays by hand, because it shouldn't be in git or isn't a file:

- A private instructions file: `ln -s <private file> ~/.config/sandbox/instructions/90-private.md`.
- The network policy (`bento policy init balanced`): smolbento keeps it in
  `~/.config/smolbento/policy.toml` and changes it as you allow things.
- Subagents and commands: mine come from APM (its manifest is in the dotfiles), which installs
  them for both Claude and OpenCode, where `sandbox` picks them up.
- Skills: `bento skills import` collects the host's skills into smolbento's shared store; re-run
  it after APM updates.

### Once, whichever you pick

1. `bento policy init balanced`: deny-by-default network with a common allow list.
2. `claude setup-token`, then `bento secret set claude` and paste the token (or use `--ref` for
   a 1Password reference). The VM only ever sees a placeholder. With option 3's
   `secrets.toml`, skip this.
3. To sign sandbox commits: `gpg.format ssh` and `user.signingkey` set to your SSH public key
   (the key itself, or a path to the `.pub` file), with that key in your SSH agent. smolbento
   forwards the agent while the sandbox runs. Without that setting, commits are signed with the
   agent's first key; with no agent at all, the agent can't commit (see
   [git-signing](#git-signing)).

## Your instructions

Every agent in a sandbox gets one instructions file, rebuilt on each `sandbox` launch:

1. [`sandbox.md`](sandbox.md), always: where it's running and the house rules (commit, never
   push).
2. Then each `*.md` in `~/.config/sandbox/instructions/` (`$XDG_CONFIG_HOME` if set), in name
   order, symlinks followed. Prefixes like `10-` and `90-` set the order. Leading frontmatter is
   removed. The folder is optional: without it, agents get only `sandbox.md`.

Subagents and commands come along too, from `~/.claude/{agents,commands}` and
`~/.config/opencode/{agents,commands}` when they exist.

Keep anything for the host only (MCP servers, host tools) out of the folder.

## Ollama on the host

```sh
bento policy allow network localhost
```

Lets sandboxes created afterwards reach `host.docker.internal`. It opens **every** port on
your Mac's localhost (smolvm can't open just one yet), and kits can't grant it.

## The kits

Kit changes apply to **new** sandboxes: `bento rm <name>`, then `sandbox` again. Check an edit
with `bento kit validate ./<kit>`.

### git-signing

smolbento's built-in [`git-signing` kit](https://github.com/pelotech/smolbento/tree/main/kits/git-signing)
(0.29+), listed in `sbxenv.yaml`. It gives the sandbox your git identity (`user.name` and
`user.email` from the repo you run `sandbox` in) and signs commits in repos with a remote, which
includes the agent's clone, with a key from your SSH agent. The private key never enters the
sandbox; commits come back with their signatures, and `git log --show-signature` verifies them
inside. Tags and scratch `git init` repos stay unsigned.

`sandbox` passes your `user.signingkey` as the kit's `signingKey`, so the kit signs with that key
even when the agent holds several, when `gpg.format` is `ssh` and `user.signingkey` is an SSH
public key or a file holding one. Otherwise it warns and passes nothing, and the kit signs with
the first key your agent lists. With no SSH agent at all, the agent's commits are refused, with a
`git-signing:` message saying what to fix.

The kit asks for your agent (`ssh-agent@1`) for git signatures only, since agents from workload
kits, such as Antigravity, get none otherwise. There the agent signs commits and refuses SSH
logins. Built-in agents (Claude, OpenCode, …) always get it with no limits, which a kit can't
narrow: they can also log in over SSH as you (`git push` to an SSH remote).

### Nix

smolbento's [`nix` kit](https://github.com/pelotech/smolbento/tree/main/kits/nix), pinned in
`sbxenv.yaml`: Nix with flakes, direnv with nix-direnv, and xz, in the kit's image layer, so
nothing is downloaded at create. It brings its own network rules for the Nix caches. Agents run
project commands with `direnv exec . <cmd>` or `nix develop -c <cmd>`, which the kit tells them.

`sbxenv.yaml` also sets `OLLAMA_HOST=http://host.docker.internal:11434` and
`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`. Docker inside the sandbox comes from smolbento's
built-in `docker` kit.

### agent-config

On each launch `sandbox` rebuilds `~/.local/share/sandbox/agent-config/`:

- `AGENTS.md`: [your instructions](#your-instructions), joined.
- `claude/` and `opencode/`: each agent's `agents` and `commands`. OpenCode's lose `tools:`,
  `model:` and `color:`, which the sandbox's older OpenCode rejects (they come in Claude's
  format from APM).

`sandbox` mounts that folder read-only, at the same path, as a second workspace
(`additionalWorkspaces` with `readOnly: true` in `sbxenv.yaml`). smolvm enforces it on the host
side, so not even root in the VM can write to it. `agent-config/agent-config.yaml` gets the path
as a kit argument and, on every start:

- Adds `AGENTS.md` to the end of each agent's instructions file, between
  `<!-- sandbox:instructions -->` markers, replacing the copy from the last start:
  `~/.claude/CLAUDE.md`, `~/.config/opencode/AGENTS.md`, `~/.codex/AGENTS.md`,
  `~/.gemini/GEMINI.md` (Antigravity) and `~/.copilot/copilot-instructions.md`. The rest of
  the file stays: the agent kit's own guide (for Claude: how logins, packages and the shell
  work here) and smolbento's `## Kits` list, which points to each kit's tip, such as Nix's.
- Links the Claude and OpenCode subagents and commands to the folder, so those update in
  running sandboxes too.
- Links `~/.gemini/AGENTS.md` to `~/AGENTS.md`, where Antigravity's kit writes its guide and the
  kit tips but where Antigravity doesn't look.

A sandbox picks up changed instructions when it next starts, which `sandbox` does when the
sandbox is stopped (it stops when the agent exits). Sandboxes made with agent-config 2.x had
their instructions file replaced by a link, which lost the agent's guide and the kit tips: the
next start puts your instructions back, but `bento rm` and a new sandbox bring back the rest.

It also allows `opencode.ai`, where OpenCode's default model is served.

Hooks and MCP servers aren't available in sandboxes.

## Tests

```sh
bash tests/run.sh   # the script against a stub bento: no VM, network or Nix
```

## How it stays safe

| Risk | Protection |
|------|------------|
| Agent damages your files | The repo is mounted read-only; the agent works on a clone in the VM |
| Agent plants git hooks, config or `.envrc` | Only commits come back (`git fetch`, objects fsck'd) |
| Data exfiltration | Network is deny-by-default plus the `balanced` allow list (and the kits' few additions) |
| Credential theft | The VM sees a placeholder; the real token is swapped in on the host, only for the service's hosts |
| Tampering with instructions | Your staged files are mounted read-only, enforced by smolvm on the host. The copy in each agent's instructions file is rewritten on every start |
| Signing or logging in as you | While the sandbox runs, attached or not, the agent can ask your SSH agent to sign: commits, and for built-in agents SSH logins too (such as `git push` over SSH). Every key in the agent is offered, not just the signing key. 1Password, for one, asks you to approve each use; `bento settings set ssh.agentForwardingEnabled false` turns it off for every sandbox |
| Reaching host services | **Open** if you allowed `localhost`: every host loopback port is reachable, until smolvm can open a single port |
