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
sandbox docker.io/sbx/antigravity:latest   # an agent from a workload kit
sandbox claude -- -c    # arguments after -- go to the agent
```

`sandbox` is `sbt run --clone` with the three kits below, after staging
[your instructions](#your-instructions). Everything else is plain `sbt`:

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

## Install

On a Mac with Homebrew:

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

### nix-tools

`nix-tools/nix-tools.yaml` adds to every sandbox:

- Nix (pinned, checksummed installer, single-user, flakes on), direnv and xz, installed on the
  sandbox's first start;
- `PATH` with the Nix profile in front of the agent image's own, `OLLAMA_HOST=http://host.docker.internal:11434`,
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`;
- network access to the Nix caches.

Docker inside the sandbox comes from smolbento's built-in `docker` kit.

### agent-config

On each launch `sandbox` rebuilds `~/.local/share/sandbox/agent-config/`:

- `AGENTS.md`: [your instructions](#your-instructions), joined.
- `claude/` and `opencode/`: each agent's `agents` and `commands`. OpenCode's lose `tools:`,
  `model:` and `color:`, which the sandbox's older OpenCode rejects (they come in Claude's
  format from APM).

`sandbox` mounts that folder read-only, at the same path, as a second workspace
(`sbt run … . <dir>:ro`). smolvm enforces it on the host side, so not even root in the VM can
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
