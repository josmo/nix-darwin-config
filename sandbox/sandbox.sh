# Run a coding agent in a smolvm microVM against the current git repo; see usage below.
# Expects SANDBOX_IMAGE_DIR, SANDBOX_SMOLFILE, SANDBOX_SECRETS, SANDBOX_VERIFY and
# SANDBOX_OLLAMA_SOCK; set by the Nix wrapper.

usage() {
  cat <<'EOF'
Usage: sandbox [claude|gemini|opencode|shell] [agent args...]   (default: claude)
       sandbox --update    rebuild the image with the latest agents
       sandbox --rm        remove this repo's sandboxes
       sandbox --verify    run the security checks in this repo's sandbox
       sandbox --help

The repo is mounted read-only and cloned inside the VM. When the agent exits, its
commits are fetched to sandbox/<agent>/<branch>; nothing else reaches the host:
  git log main..sandbox/claude/main
  git merge sandbox/claude/main
EOF
}

die() {
  echo "sandbox: $*" >&2
  exit 1
}

AGENTS=(claude gemini opencode shell)
# The image directory's store hash changes whenever its files do, so it doubles as the tag.
TAG=$(basename "$SANDBOX_IMAGE_DIR" | cut -c1-12)
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/sandbox"
IMAGE="$CACHE/sandbox-$TAG.tar"

build_image() {
  echo "==> Building the sandbox image (needs Docker Desktop running)..."
  docker build "$@" -t "sandbox:$TAG" "$SANDBOX_IMAGE_DIR"
  mkdir -p "$CACHE"
  # Warn only: findings are mostly in upstream base-image binaries.
  trivy image --quiet --severity HIGH,CRITICAL "sandbox:$TAG" >"$CACHE/trivy.txt" 2>&1 || true
  echo "==> Trivy report: $CACHE/trivy.txt"
  rm -f "$CACHE"/sandbox-*.tar*
  docker save "sandbox:$TAG" -o "$IMAGE.tmp"
  mv "$IMAGE.tmp" "$IMAGE"
}

mode=run
case "${1:-}" in
  -h | --help) usage; exit ;;
  --update)
    build_image --pull --no-cache
    echo "==> Run 'sandbox --rm' in a repo to move its sandboxes to the new image."
    exit ;;
  --rm | --verify) mode=${1#--}; shift ;;
esac

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository; cd into one first"
repo=$(git rev-parse --show-toplevel)
# One machine per repo and agent: <agent>-<repo name>-<hash of repo path>.
id="$(basename "$repo" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' - | cut -c1-20)-$(printf %s "$repo" | shasum | cut -c1-8)"

if [ "$mode" = rm ]; then
  for a in "${AGENTS[@]}"; do
    smolvm machine status --name "$a-$id" >/dev/null 2>&1 || continue
    smolvm machine stop --name "$a-$id" >/dev/null 2>&1 || true
    smolvm machine delete --name "$a-$id" -f >/dev/null
    echo "==> Removed the $a sandbox"
  done
  exit
fi

agent=${1:-claude}
[ $# -gt 0 ] && shift
case "$agent" in
  claude) cmd=(claude --dangerously-skip-permissions) ;;
  gemini) cmd=(gemini --yolo) ;;
  opencode) cmd=(opencode) ;;
  shell) cmd=(bash) ;;
  *) die "unknown agent '$agent' (try: ${AGENTS[*]})" ;;
esac
name="$agent-$id"
branch=$(git branch --show-current)
[ -n "$branch" ] || die "HEAD is detached; check out a branch first"

# Create once, start if stopped. Credentials resolve from 1Password at launch and stay on the host.
state=$(smolvm machine status --name "$name" 2>/dev/null || true)
if [ -z "$state" ]; then
  [ -f "$IMAGE" ] || build_image
  echo "==> Creating the $agent sandbox for $(basename "$repo")..."
  # The git common dir works for main checkouts and linked worktrees alike.
  smolvm machine create --name "$name" -s "$SANDBOX_SMOLFILE" --image "$IMAGE" \
    -v "$(git rev-parse --path-format=absolute --git-common-dir):/src.git:ro" \
    --mount-socket "$SANDBOX_OLLAMA_SOCK:/run/ollama.sock" >/dev/null
fi
case "$state" in
  *running*) ;;
  *) op run --env-file "$SANDBOX_SECRETS" -- smolvm machine start --name "$name" >/dev/null ;;
esac

if [ "$mode" = verify ]; then
  exec smolvm machine exec -i --name "$name" -u agent -- bash -s <"$SANDBOX_VERIFY"
fi

# Clone on first use, pointing origin at the host repo's remote.
work="/home/agent/$(basename "$repo")"
# shellcheck disable=SC2016 # $1-$3 belong to the guest's sh, passed as arguments
smolvm machine exec --name "$name" -u agent -- sh -c '
  [ -d "$1/.git" ] && exit
  # The read-only mount keeps the host uid, so trust it for this clone only.
  git -c safe.directory=/src.git clone -q --branch "$2" /src.git "$1"
  if [ -n "$3" ]; then git -C "$1" remote set-url origin "$3"; fi' \
  _ "$work" "$branch" "$(git remote get-url origin 2>/dev/null || true)"

# Run the agent; whatever its exit status, bring back its commits (and only those).
status=0
smolvm machine exec -it --name "$name" -u agent -w "$work" -- "${cmd[@]}" "$@" || status=$?

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if smolvm machine exec --name "$name" -u agent -w "$work" -- git bundle create - --branches >"$tmp/work.bundle" 2>/dev/null; then
  ref="sandbox/$agent/$branch"
  before=$(git rev-parse -q --verify "$ref" || echo "$branch")
  # fsck: the agent wrote this bundle, so verify every object it brings.
  git -c transfer.fsckObjects=true fetch -q "$tmp/work.bundle" "+refs/heads/*:refs/remotes/sandbox/$agent/*"
  new=$(git log --oneline "$before..$ref" 2>/dev/null || true)
  [ -z "$new" ] || printf '==> New agent commits on %s:\n%s\n' "$ref" "$new"
fi
exit "$status"
