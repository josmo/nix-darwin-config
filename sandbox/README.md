# sandbox

Run a coding agent (Claude, OpenCode, Codex, Antigravity, …) in a microVM with
[smolbento](https://github.com/pelotech/smolbento) (`sbt`). The agent works on its own clone of
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

`sandbox` stages [your instructions](#your-instructions), then runs `sbt env run` with
[env files](#env-files). Everything else is plain `sbt`:

```sh
sbt ls                         # sandboxes
sbt rm claude-<repo>           # remove one (also removes its git remote: merge first)
sbt policy log                 # what the network policy blocked
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
reach new sandboxes: `sbt rm <name>`, then `sandbox` again.

Sandboxes made by `sandbox` before it used env files aren't found by `sbt env run` ("not found
for this environment"): merge their commits, `sbt rm` them, and run `sandbox` again.

## Env files

`sandbox` passes these [sbxenv.yaml](https://github.com/pelotech/smolbento/blob/main/docs/usage.md#environments-sbxenvyaml)
files to `sbt env run`, the ones that exist, in this order (later wins: maps merge, lists add up):

1. [`sbxenv.yaml`](sbxenv.yaml): the clone, your staged instructions (read-only), the kits and
   a few variables.
2. `agents/<agent>.yaml`: for agents that come from a kit, such as
   [Antigravity](agents/antigravity.yaml).
3. `~/.config/sandbox/agents/<agent>.yaml`: your own kit-based agents.
4. `~/.config/sandbox/sbxenv.yaml`: your own additions for every sandbox (kits, `env`, memory).
5. `./sbxenv.yaml`: the project's, from the directory you run `sandbox` in. Run it from the
   repo's root: from a subdirectory, that subdirectory is the workspace and the place it looks.

(`~/.config` is `$XDG_CONFIG_HOME` if set.) Preview what a run would do with `sbt env plan`
and the same files.

`sandbox` passes the args `agent`, `workspace` (the current directory), `stage` and
`signingKey`; your files can use them as `${{ env.args.NAME }}`. Pass others, such as a project
file's required ones, with `--env-arg NAME=VALUE` before the agent. `${{ env.projectDir }}` and
`SBX_ENV_DIR` name the first file's directory, which here is this folder, not your repo: use
`${{ env.args.workspace }}` for the repo.

A project's `sbxenv.yaml` works on its own too: teammates without `sandbox` can use it with
plain `sbt env run` (or Docker's `sbx env run`). Being last, its `agent:` and `name:` win over
the agent you ask `sandbox` for: in a file meant to work both ways, write
`agent: ${{ env.args.agent }}` with `args: {agent: {default: claude}}`, and leave `name:` out.

A project file can also run commands on your Mac, mount your directories, add kits, change the
agent, or turn off the clone (or point the workspace elsewhere) so the agent writes straight to
your checkout. All of it shows in the approval plan before anything runs, so read it before you
approve a file you didn't write.

## Install

On a Mac with Homebrew (smolbento 0.26 or newer):

```sh
brew install smol-machines/tap/smolvm pelotech/tap/smolbento
git clone https://github.com/josmo/nix-darwin-config.git
mkdir -p ~/.local/bin
ln -s "$PWD/nix-darwin-config/sandbox/sandbox" ~/.local/bin/sandbox   # or any dir on your PATH
```

If `~/.local/bin` isn't on your `PATH` yet, add `export PATH="$HOME/.local/bin:$PATH"` to
`~/.zshrc`.

`sandbox` finds its kits next to itself (through the link), so `git pull` updates everything.
With nix-darwin, the `./sandbox` module installs it all instead.

Then, once:

1. `sbt policy init balanced`: deny-by-default network with a common allow list.
2. `claude setup-token`, then `sbt secret set claude` and paste the token (or use `--ref` for
   a 1Password reference). The VM only ever sees a placeholder.
3. To sign sandbox commits: `gpg.format ssh` and `user.signingkey` set to your SSH public key
   (the key itself, or a path to the `.pub` file), with that key in your SSH agent. smolbento
   forwards the agent while the sandbox runs. Without it, commits are made unsigned, with a note.

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
sbt policy allow network localhost
```

Lets sandboxes created afterwards reach `host.docker.internal`. It opens **every** port on
your Mac's localhost (smolvm can't open just one yet), and kits can't grant it.

## How I set mine up

As an example, not a requirement ([dotfiles](https://github.com/josmo/dotfiles)):

- Instructions: `10-core.md` (a symlink to my shared `core.md`), `20-host.md` (my host tools
  that aren't in the VM), and `90-private.md`, a hand-made link to a private file that never
  goes in git.
- The Claude token lives in 1Password (item `claude-sandbox`, vault `Private`), referenced as
  `op://Private/claude-sandbox/credential`. smolbento's `config.toml` (the 1Password SSH agent
  socket) and `secrets.toml` are in my dotfiles, linked into `~/.config/smolbento/`.
- Subagents and commands come from APM, which installs them for both Claude and OpenCode.
- Skills: `sbt skills import` collects the host's skills into smolbento's shared store; re-run
  it after APM updates.

## The kits

Kit changes apply to **new** sandboxes: `sbt rm <name>`, then `sandbox` again. Check an edit
with `sbt kit validate ./<kit>`.

### git-signing

`git-signing/git-signing.yaml` gives the sandbox your git identity (`user.name`/`user.email`
from the repo you run `sandbox` in) and, when `sandbox` passes it a key, SSH-signed commits.
`sandbox` passes one only when `gpg.format` is `ssh` and `user.signingkey` is an SSH public
key or a file holding one; anything else would make every commit fail. The private key stays
in your SSH agent: smolbento forwards it into the sandbox whenever the sandbox runs, attached
or not (listing keys and signing only). Commits come back with their signatures.

The kit also asks for the agent (`ssh-agent@1`) for git signing only, since agents from
workload kits, such as Antigravity, get none otherwise. There the agent signs commits and
refuses SSH logins. Built-in agents (Claude, OpenCode, …) always get it with no limits, which a
kit can't narrow: they can also log in over SSH as you (`git push` to an SSH remote).

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
(`additionalWorkspaces` with `readOnly: true` in `sbxenv.yaml`). smolvm enforces it on the host side, so not even root in the VM can
write to it. `agent-config/agent-config.yaml` gets the path as a kit argument and, on every
start, links each agent's files to it: `~/.claude/CLAUDE.md`, `~/.config/opencode/AGENTS.md`,
`~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md` (Antigravity) and
`~/.copilot/copilot-instructions.md`, plus the Claude and OpenCode subagents and commands.
Being a mount, it updates running sandboxes too, on the next `sandbox` run from anywhere.

It also allows `opencode.ai`, where OpenCode's default model is served.

Hooks and MCP servers aren't available in sandboxes.

## Tests

```sh
bash tests/run.sh   # the script against a stub sbt: no VM, network or Nix
```

## How it stays safe

| Risk | Protection |
|------|------------|
| Agent damages your files | The repo is mounted read-only; the agent works on a clone in the VM |
| Agent plants git hooks, config or `.envrc` | Only commits come back (`git fetch`, objects fsck'd) |
| Data exfiltration | Network is deny-by-default plus the `balanced` allow list (and the kits' few additions) |
| Credential theft | The VM sees a placeholder; the real token is swapped in on the host, only for the service's hosts |
| Tampering with instructions | They're mounted read-only, enforced by smolvm on the host |
| Signing or logging in as you | While the sandbox runs, attached or not, the agent can ask your SSH agent to sign: commits, and for built-in agents SSH logins too (such as `git push` over SSH). Every key in the agent is offered, not just the signing key. 1Password, for one, asks you to approve each use; `sbt settings set ssh.agentForwardingEnabled false` turns it off for every sandbox |
| Reaching host services | **Open** if you allowed `localhost`: every host loopback port is reachable, until smolvm can open a single port |
