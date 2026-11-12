# sandbox

Run a coding agent (Claude, Gemini, OpenCode, …) in a microVM with
[smolbento](https://github.com/pelotech/smolbento) (`sbt`). The agent works on its own clone of
the repo, with filtered network access and no real credentials. Only its commits come back.

## Usage

```sh
cd <git repo>
sandbox                 # Claude (default)
sandbox gemini          # or: opencode, shell, … (sbt run --help lists agents)
sandbox claude -- -c    # arguments after -- go to the agent
```

`sandbox` is `sbt run --clone` with the two kits below. Everything else is plain `sbt`:

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

## Setup (once)

1. `nh darwin switch`: installs smolbento (with smolvm) and the `sandbox` command.
2. Network policy, and host access for Ollama (opens **every** port on the host's localhost
   to sandboxes created afterwards):
   ```sh
   sbt policy init balanced
   sbt policy allow network localhost
   ```
3. In 1Password: an item `claude-sandbox` in vault `Private` whose `credential` field holds
   `claude setup-token`'s output, and the SSH agent turned on with your signing key in it.
   Set `user.signingkey` in your git config to the public key (`ssh-rsa AAAA...`).

smolbento's settings (the 1Password SSH agent socket) and secret references
(`claude` → `op://Private/claude-sandbox/credential`) live in the dotfiles repo as
`.config/smolbento/config.toml` and `secrets.toml`, linked into `~/.config/smolbento/`.
`sbt settings set` and `sbt secret set` write through the links: commit the change in dotfiles.
`policy.toml` stays local (smolbento keeps per-sandbox rules there).

## The git-signing kit

`git-signing/git-signing.yaml` gives the sandbox your git identity (`user.name`/`user.email`
from the repo you run `sandbox` in) and, when `user.signingkey` is set, SSH-signed commits.
The private key stays in 1Password: smolbento forwards your SSH agent into the sandbox while
you're attached (listing keys and signing only), and 1Password asks you to approve. Commits
come back with their signatures.

## The nix-tools kit

`nix-tools/nix-tools.yaml` is a smolbento v3 mixin kit (needs smolbento 0.15.2+) that adds to
every sandbox `sandbox` creates:

- Nix (pinned, checksummed installer, single-user, flakes on) and direnv, installed on the
  sandbox's first start;
- `PATH` with the Nix profile first, `OLLAMA_HOST=http://host.docker.internal:11434`,
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`;
- network access to the Nix caches.

Docker inside the sandbox comes from smolbento's built-in `docker` kit.

Kit changes, policy host access and new secret services apply to **new** sandboxes:
`sbt rm <name>`, then `sandbox` again. Check a kit edit with `sbt kit validate ./nix-tools`.

## How it stays safe

| Risk | Protection |
|------|------------|
| Agent damages your files | The repo is mounted read-only; the agent works on a clone in the VM |
| Agent plants git hooks, config or `.envrc` | Only commits come back (`git fetch`, objects fsck'd) |
| Data exfiltration | Network is deny-by-default plus the `balanced` allow list |
| Credential theft | The VM sees a placeholder; the real token is swapped in on the host, only for Anthropic's hosts |
| Signing as you | While you're attached, the agent can ask your SSH agent to sign; 1Password asks you to approve. Every key in the agent is offered, not just the signing key |
| Reaching host services | **Open:** every host loopback port is reachable (for Ollama), until smolvm can open a single port |
