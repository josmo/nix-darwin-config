# Per-directory Lima sandbox for coding agents: each directory gets its own VM,
# cloned from a provisioned base, with ONLY that directory mounted.
# Usage: cd <repo-or-worktree> && sandbox [claude|gemini|opencode|bash] [args...]
#        sandbox --list | --stop | --rm | --prune | --rebuild-base
# Expects LIMA_TEMPLATE (agent-base.yaml) in the environment; set by the Nix wrapper.

BASE="agent-base"
inst="agent-$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' - | cut -c1-20)-$(printf %s "$PWD" | shasum | cut -c1-8)"

exists() { limactl list -q | grep -qx "$1"; }

case "${1:-}" in
  # limactl list takes exact names, not globs, so filter by prefix here.
  --list) mapfile -t names < <(limactl list -q | grep '^agent-') && exec limactl list "${names[@]}" ;;
  --stop) exec limactl stop "$inst" ;;
  --rm) exec limactl delete -f "$inst" ;;
  # Delete clones whose project directory (first mount) no longer exists.
  --prune)
    # shellcheck disable=SC2016 # $i/$m are Go template vars, not shell
    limactl list --format '{{.Name}}{{"\t"}}{{range $i, $m := .Config.Mounts}}{{if eq $i 0}}{{$m.Location}}{{end}}{{end}}' |
      while IFS=$'\t' read -r name dir; do
        [[ "$name" == agent-* && "$name" != "$BASE" && -n "$dir" && ! -d "$dir" ]] || continue
        echo "==> Deleting $name ($dir is gone)"
        limactl delete -f "$name"
      done
    exit ;;
  --rebuild-base) exec limactl delete -f "$BASE" ;;
esac

if [ "$PWD" = / ] || [ "$PWD" = "$HOME" ]; then
  echo "sandbox: refusing to mount $PWD; cd into a project first" >&2
  exit 1
fi

# 1. One-time base: create, provision (probes wait for the agents), then stop so it can be cloned.
stamp="$HOME/.lima/$BASE/sandbox-template"
if ! exists "$BASE"; then
  echo "==> Provisioning $BASE (one-time)..."
  limactl create --name="$BASE" --tty=false "$LIMA_TEMPLATE"
  limactl start --tty=false "$BASE"
  limactl stop "$BASE"
  echo "$LIMA_TEMPLATE" >"$stamp"
elif [ "$(cat "$stamp" 2>/dev/null)" != "$LIMA_TEMPLATE" ]; then
  echo "sandbox: agent-base.yaml changed; run 'sandbox --rebuild-base' to apply it" >&2
fi

# 2. One-time clone for this directory. In a git worktree the shared git dir lives
#    outside $PWD, so mount it too or git breaks inside the VM.
if ! exists "$inst"; then
  mounts="{\"location\": \"$PWD\", \"writable\": true}"
  gitdir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [ -n "$gitdir" ] && [[ "$gitdir" != "$PWD"/* ]]; then
    mounts="$mounts, {\"location\": \"$gitdir\", \"writable\": true}"
  fi
  echo "==> Creating $inst for $PWD..."
  limactl clone --tty=false "$BASE" "$inst" --set ".mounts = [$mounts]"
fi

# 3. Start only if needed, so other sessions in this VM keep running.
if [ "$(limactl list --format '{{.Status}}' "$inst")" != Running ]; then
  limactl start --tty=false "$inst"
fi

# 4. Run the agent. Forward only the API keys, not the rest of the host environment.
agent="${1:-claude}"
shift || true
export LIMA_SHELLENV_BLOCK='*' LIMA_SHELLENV_ALLOW=ANTHROPIC_API_KEY,GEMINI_API_KEY
exec limactl shell --preserve-env --workdir "$PWD" "$inst" "$agent" "$@"
