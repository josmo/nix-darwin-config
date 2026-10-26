# sandbox

Run a coding agent (Claude, Gemini, OpenCode) in a [smolvm](https://github.com/smol-machines/smolvm)
microVM against the current git repo. The agent works on its own clone with locked-down
network access and no real credentials. Only its commits come back.

## Usage

```sh
cd <git repo>
sandbox                 # Claude (default)
sandbox gemini          # or: opencode, shell
sandbox claude -c       # anything after the agent name goes to the agent

sandbox --update        # rebuild the image with the latest agents
sandbox --rm            # remove this repo's sandboxes
sandbox --verify        # run the security checks inside this repo's sandbox
sandbox --help
```

When the agent exits, its new commits are fetched to `sandbox/<agent>/<branch>`:

```sh
git log  main..sandbox/claude/main
git diff main sandbox/claude/main
git merge sandbox/claude/main
```

Each repo + agent gets one machine, created on first use and reused after. The agent
starts from your last commit; uncommitted changes aren't copied in.

## Setup (once)

1. `nh darwin switch` — installs `sandbox`, smolvm and the Ollama relay.
2. In 1Password, vault `grannec`: create item `claude-sandbox` with a `credential` field
   containing the output of `claude setup-token`.
3. Have Docker Desktop running for the first run; it builds the image (a few minutes).

## How it stays safe

| Risk | Protection |
|------|------------|
| Agent damages your files | The repo's git dir is mounted read-only; the agent works on a clone in the VM |
| Agent plants git hooks, config or `.envrc` | Only commits come back (`git bundle`, fsck'd); nothing else reaches the host |
| Data exfiltration | Network is deny-by-default; only hosts in `Smolfile` are reachable |
| Credential theft | The VM sees a placeholder; smolvm swaps in the real token on the host, only for `api.anthropic.com` |
| Reaching host services | Host loopback and LAN are blocked; Ollama is exposed only through one socket |

## Configuration

| File | What it controls |
|------|------------------|
| `Smolfile` | Network allowlist, credential bindings |
| `secrets.env` | 1Password references (`op://grannec/<service>-sandbox/credential`); no values |
| `image/Dockerfile` | Tools in the VM: agents, Nix, Docker, direnv |
| `image/sandbox-init` | VM main process: starts dockerd and the Ollama relay |
| `sandbox.sh` | The `sandbox` command |
| `default.nix` | nix-darwin module: packages the command, smolvm, Ollama relay |
| `verify.sh` | Checks run by `sandbox --verify` |

Changes to `Smolfile` or the image apply to new machines: run `sandbox --rm`, then `sandbox`.

To add a secret (e.g. Gemini): add `GEMINI_API_KEY=op://grannec/gemini-sandbox/credential`
to `secrets.env`, and a matching `[secrets]` entry and `[[network.credentials]]` block
to `Smolfile`.

## Troubleshooting

- **A tool can't reach something** — see what was blocked, then add the host to `Smolfile`:
  `smolvm machine egress-events --name <machine>` (machine names: `smolvm machine ls`).
- **Something seems off** — `sandbox --verify` should print all `ok`.
- **Ollama returns 403** — clients must use `http://localhost:11434` (already set as
  `OLLAMA_HOST` in the VM); Ollama rejects other host names.
- **1Password prompts** — Touch ID is asked when a machine starts, not on every run.
- **Image scan** — each build writes a Trivy report to `~/.cache/sandbox/trivy.txt`.
