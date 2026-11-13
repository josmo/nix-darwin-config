# `sandbox [agent] [-- agent args]`: run a coding agent in a smolbento sandbox; see README.md.
# Wrapped by writeShellApplication in default.nix, which sets SANDBOX_KITS (this directory in
# the store). sbt and git come from PATH.
[ $# -gt 0 ] || set -- claude

# Stage personal agent config for the agent-config kit, fresh on every launch. Sandboxes see it
# live through a host mount and can write to it, so it's a copy, never the dotfiles themselves.
stage=${XDG_DATA_HOME:-$HOME/.local/share}/sandbox/agent-config
# Emptied, not recreated: running sandboxes have this directory mounted.
mkdir -p "$stage" && find "$stage" -mindepth 1 -delete
# One instructions file for every agent: shared, sandbox-specific, then private (if present),
# each without its leading frontmatter (Antigravity's `trigger:`) and followed by a blank line.
for f in ~/.config/agents/core.md ~/.config/agents/sandbox.md ~/.claude/CLAUDE.private.md; do
  [ -e "$f" ] || continue
  awk 'NR == 1 && /^---$/ { fm = 1; next } fm { if (/^---$/) fm = 0; next } 1; END { print "" }' "$f"
done > "$stage/AGENTS.md"
# Subagents and commands, in each agent's own format (APM writes both).
for src in ~/.claude ~/.config/opencode; do
  a=$(basename "$src"); a=${a#.}
  for d in agents commands; do
    if [ -d "$src/$d" ]; then mkdir -p "$stage/$a" && cp -RL "$src/$d" "$stage/$a/"; fi
  done
done
# APM gives OpenCode the Claude frontmatter. The sandbox's older OpenCode rejects its `tools:` (a
# list, not a map), `model:` (`sonnet`, not provider/model) and named `color:`s. Without them a
# subagent gets every tool and the session's model.
for f in "$stage"/opencode/agents/*.md; do
  [ -e "$f" ] || continue
  awk '/^---$/ { n++ } !(n == 1 && /^(tools|model|color):/)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done

# Kits, the clone and the mount only apply on create (sbt warns about them after), so an
# existing sandbox just runs. sbt's name: <agent, or a kit's last path part>-<workspace basename>.
name=$(basename "${1%%[:@]*}")-$(basename "$PWD")
if sbt inspect "$name" >/dev/null 2>&1; then exec sbt run "$@"; fi

# user.signingkey is the public key itself ("ssh-rsa AAAA..."); empty: no signing.
key=$(git config user.signingkey || true)
exec sbt run --clone \
  --kit "$SANDBOX_KITS/nix-tools" \
  --kit "$SANDBOX_KITS/git-signing" --kit-arg "git-signing.signingKey=${key#key::}" \
  --kit "$SANDBOX_KITS/agent-config" --mount "$stage:/opt/agent-config" \
  "$@"
