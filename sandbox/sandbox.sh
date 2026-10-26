# Run a coding agent in a smolvm microVM against the current git repo.
# The repo's git dir is mounted read-only and cloned inside the VM; when the session ends,
# the agent's commits are fetched into refs/remotes/sandbox-<name>/*. Nothing else comes back.
# Usage: cd <repo> && sandbox [claude|gemini|opencode|shell] [args...]
#        sandbox --update     rebuild the image with fresh agents
# Lifecycle: smolvm machine ls | stop --name <name> | delete --name <name>
# Expects SANDBOX_IMAGE_DIR, SANDBOX_SMOLFILE, SANDBOX_SECRETS and SANDBOX_OLLAMA_SOCK;
# set by the Nix wrapper.

declare -A AGENTS=(
  [claude]="claude --dangerously-skip-permissions"
  [gemini]="gemini --yolo"
  [opencode]="opencode"
  [shell]="bash"
)

# The image directory's store hash changes whenever its files do, so it doubles as the tag.
TAG=$(basename "$SANDBOX_IMAGE_DIR" | cut -c1-12)
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/sandbox"
IMAGE="$CACHE/sandbox-$TAG.tar"

build_image() {
  echo "==> Building sandbox image $TAG (needs Docker Desktop running)..."
  docker build "$@" -t "sandbox:$TAG" "$SANDBOX_IMAGE_DIR"
  mkdir -p "$CACHE"
  # Warn only: findings are mostly in upstream base-image binaries.
  if trivy image --quiet --severity HIGH,CRITICAL "sandbox:$TAG" >"$CACHE/trivy-$TAG.txt" 2>&1; then
    echo "==> Trivy report: $CACHE/trivy-$TAG.txt"
  else
    echo "sandbox: trivy scan failed (see $CACHE/trivy-$TAG.txt); continuing" >&2
  fi
  docker save "sandbox:$TAG" -o "$IMAGE.tmp"
  mv "$IMAGE.tmp" "$IMAGE"
  find "$CACHE" \( -name 'sandbox-*.tar' -o -name 'trivy-*.txt' \) ! -name "*-$TAG.*" -delete
}

if [ "${1:-}" = --update ]; then
  build_image --pull --no-cache
  echo "==> Existing machines keep their image; remove them to use the new one."
  exit
fi

agent=${1:-claude}
[ $# -gt 0 ] && shift
if [ -z "${AGENTS[$agent]:-}" ]; then
  echo "sandbox: unknown agent '$agent' (known: ${!AGENTS[*]})" >&2
  exit 1
fi
read -ra cmd <<<"${AGENTS[$agent]}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "sandbox: not inside a git repository; cd into one first" >&2
  exit 1
fi
repo=$(git rev-parse --show-toplevel)
branch=$(git branch --show-current)
if [ -z "$branch" ]; then
  echo "sandbox: HEAD is detached; check out a branch first" >&2
  exit 1
fi
# The common dir works for main checkouts and linked worktrees alike.
gitdir=$(git rev-parse --path-format=absolute --git-common-dir)
origin=$(git remote get-url origin 2>/dev/null || true)
name="$agent-$(basename "$repo" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' - | cut -c1-20)-$(printf %s "$repo" | shasum | cut -c1-8)"
work="/home/agent/$(basename "$repo")"

# 1. Create once per repo and agent.
if ! smolvm machine status --name "$name" >/dev/null 2>&1; then
  [ -f "$IMAGE" ] || build_image
  echo "==> Creating $name..."
  smolvm machine create --name "$name" -s "$SANDBOX_SMOLFILE" --image "$IMAGE" \
    -v "$gitdir:/src.git:ro" --mount-socket "$SANDBOX_OLLAMA_SOCK:/run/ollama.sock" >/dev/null
fi

# 2. Start if needed; credentials resolve from 1Password at launch and stay on the host.
if ! smolvm machine status --name "$name" 2>/dev/null | grep -q running; then
  op run --env-file "$SANDBOX_SECRETS" -- smolvm machine start --name "$name" >/dev/null
fi

# 3. Clone on first use, pointing origin at the host repo's remote.
# shellcheck disable=SC2016 # $1-$3 belong to the guest's sh, passed as arguments
smolvm machine exec --name "$name" -u agent -- sh -c '
  [ -d "$1/.git" ] && exit
  # The read-only mount keeps the host uid, so trust it for this clone only.
  git -c safe.directory=/src.git clone -q --branch "$2" /src.git "$1"
  if [ -n "$3" ]; then git -C "$1" remote set-url origin "$3"; fi' _ "$work" "$branch" "$origin"

# 4. Run the agent; whatever its exit status, bring back its commits.
status=0
smolvm machine exec -it --name "$name" -u agent -w "$work" -- "${cmd[@]}" "$@" || status=$?

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if smolvm machine exec --name "$name" -u agent -w "$work" -- git bundle create - --branches >"$tmp/work.bundle" 2>/dev/null &&
  git bundle list-heads "$tmp/work.bundle" >/dev/null 2>&1; then
  # fsck: the bundle was written by the agent, so verify every object it brings.
  git -c transfer.fsckObjects=true fetch -q "$tmp/work.bundle" "+refs/heads/*:refs/remotes/sandbox-$name/*"
  new=$(git log --oneline "$branch..sandbox-$name/$branch" 2>/dev/null || true)
  if [ -n "$new" ]; then
    echo "==> Agent commits on sandbox-$name/$branch (not yet on $branch):"
    echo "$new"
  fi
fi
exit "$status"
