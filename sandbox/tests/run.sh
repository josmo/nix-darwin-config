#!/usr/bin/env bash
# Tests for ../sandbox, with a stub `sbt` that records its arguments.
# Run: bash sandbox/tests/run.sh   (no VM, network or Nix needed)
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd -P)
root=$(dirname "$here")  # the sandbox/ folder, physical path (realpath gives the same)
script=$root/sandbox
ORIG_PATH=$PATH

# A fresh HOME, XDG dirs, git config and git repo (the cwd), with the stub sbt first on PATH.
setup() {
  t=$(cd "$(mktemp -d)" && pwd -P)
  export HOME=$t/home XDG_CONFIG_HOME=$t/config XDG_DATA_HOME=$t/data
  export GIT_CONFIG_GLOBAL=$t/gitconfig GIT_CONFIG_NOSYSTEM=1 STUB_LOG=$t/sbt.log
  unset STUB_EXISTS SANDBOX_KITS
  mkdir -p "$HOME" "$t/bin" "$t/repo"
  : > "$GIT_CONFIG_GLOBAL"
  cat > "$t/bin/sbt" <<'EOF'
#!/usr/bin/env bash
# inspect: the sandbox exists only when STUB_EXISTS=1. run: log one argument per line.
case $1 in
  inspect) [ "${STUB_EXISTS:-}" = 1 ] ;;
  run) printf '%s\n' "$@" > "$STUB_LOG" ;;
esac
EOF
  chmod +x "$t/bin/sbt"
  export PATH=$t/bin:$ORIG_PATH
  git -C "$t/repo" init -q
  stage=$XDG_DATA_HOME/sandbox/agent-config
}

# run_sandbox ARGS…: run the script (or $SANDBOX_CMD) from the repo; output in $t/out, $t/err.
run_sandbox() { (cd "$t/repo" && "${SANDBOX_CMD:-$script}" "$@") > "$t/out" 2> "$t/err"; }

fail() { echo "    $*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected: $(printf %q "$2")" "got: $(printf %q "$1")"; }
assert_line() { grep -qxF -- "$2" "$1" || fail "no line '$2' in $1: $(cat "$1" 2>&1)"; }
assert_contains() { grep -qF -- "$2" "$1" || fail "no '$2' in $1: $(cat "$1" 2>&1)"; }
assert_not_contains() { ! grep -qE -- "$2" "$1" || fail "unexpected '$2' in $1"; }

# --- Task 1: runs without Nix, kits beside the script ---

test_kits_beside_script() {
  run_sandbox claude || fail "exit $?: $(cat "$t/err")"
  for k in nix-tools git-signing agent-config; do assert_line "$STUB_LOG" "$root/$k"; done
}

test_kits_from_env() {
  SANDBOX_KITS=/x run_sandbox claude || fail "exit $?: $(cat "$t/err")"
  assert_line "$STUB_LOG" /x/nix-tools
}

test_via_symlink() {
  ln -s "$script" "$t/bin/sandbox"
  SANDBOX_CMD=$t/bin/sandbox run_sandbox claude || fail "exit $?: $(cat "$t/err")"
  assert_line "$STUB_LOG" "$root/nix-tools"
}

test_existing_sandbox() {
  STUB_EXISTS=1 run_sandbox claude || fail "exit $?: $(cat "$t/err")"
  assert_eq "$(cat "$STUB_LOG")" "$(printf 'run\nclaude')"
  [ -e "$stage/AGENTS.md" ] || fail "staging not refreshed"
}

test_runs_without_nix() {
  assert_eq "$(head -1 "$script")" '#!/usr/bin/env bash'
  assert_eq "$(grep -v -e '^#' -e '^$' "$script" | head -1)" 'set -euo pipefail'
}

# --- Task 2: shipped sandbox.md and the instructions folder ---

instr() { mkdir -p "$XDG_CONFIG_HOME/sandbox/instructions"; echo "$XDG_CONFIG_HOME/sandbox/instructions"; }

test_no_instructions_folder() {
  run_sandbox claude || fail "exit $?: $(cat "$t/err")"
  assert_eq "$(cat "$stage/AGENTS.md"; echo .)" "$(cat "$root/sandbox.md"; echo; echo .)"
}

test_instructions_order_and_frontmatter() {
  d=$(instr)
  echo B > "$d/20-b.md"
  printf -- '---\ntrigger: always_on\n---\nA\n' > "$d/10-a.md"
  echo X > "$d/notes.txt"
  run_sandbox claude || fail "exit $?: $(cat "$t/err")"
  assert_eq "$(grep -v '^$' "$stage/AGENTS.md" | tail -2)" "$(printf 'A\nB')"
  assert_contains "$stage/AGENTS.md" "$(head -1 "$root/sandbox.md")"
  assert_eq "$(head -1 "$stage/AGENTS.md")" "$(head -1 "$root/sandbox.md")"
  assert_not_contains "$stage/AGENTS.md" 'trigger:|^X$'
}

test_instructions_symlink_and_spaces() {
  d=$(instr)
  echo C > "$t/c.md"
  ln -s "$t/c.md" "$d/30-my notes.md"
  run_sandbox claude || fail "exit $?: $(cat "$t/err")"
  assert_line "$stage/AGENTS.md" C
}

test_claude_only_agents() {
  mkdir -p "$HOME/.claude/agents"
  echo x > "$HOME/.claude/agents/x.md"
  run_sandbox claude || fail "exit $?: $(cat "$t/err")"
  [ -e "$stage/claude/agents/x.md" ] || fail "claude agent not staged"
  [ ! -e "$stage/opencode" ] || fail "opencode staged without a source"
}

test_shipped_notes_generic() {
  [ -s "$root/sandbox.md" ] || fail "no shipped sandbox.md"
  assert_not_contains "$root/sandbox.md" 'aws-sso|IntelliJ'
}

# --- Task 3: signing key only when it's an SSH key ---

# key_case FORMAT KEY: set gpg.format (empty: unset) and user.signingkey, run, leave the log.
key_case() {
  [ -z "$1" ] || git config --global gpg.format "$1"
  [ -z "$2" ] || git config --global user.signingkey "$2"
  run_sandbox claude || fail "exit $?: $(cat "$t/err")"
}

test_key_none() {
  key_case "" ""
  assert_line "$STUB_LOG" git-signing.signingKey=
  assert_eq "$(cat "$t/err")" ""
}

test_key_literal() {
  key_case ssh "ssh-ed25519 AAAAC3x me"
  assert_line "$STUB_LOG" "git-signing.signingKey=ssh-ed25519 AAAAC3x"
}

test_key_prefixed() {
  key_case ssh "key::ssh-rsa AAAAB3x"
  assert_line "$STUB_LOG" "git-signing.signingKey=ssh-rsa AAAAB3x"
}

test_key_file_tilde() {
  mkdir -p "$HOME/.ssh"
  echo "ssh-ed25519 AAAAF me" > "$HOME/.ssh/id.pub"
  # shellcheck disable=SC2088 # a literal ~, as git config stores it
  key_case ssh "~/.ssh/id.pub"
  assert_line "$STUB_LOG" "git-signing.signingKey=ssh-ed25519 AAAAF"
}

test_key_file_comment_underscore() {
  mkdir -p "$HOME/.ssh"
  echo "ssh-ed25519 AAAAF me_x@host" > "$HOME/.ssh/id.pub"
  key_case ssh "$HOME/.ssh/id.pub"
  assert_line "$STUB_LOG" "git-signing.signingKey=ssh-ed25519 AAAAF"
  assert_eq "$(cat "$t/err")" ""
}

test_key_gpg() {
  key_case "" ABCDEF1234
  assert_line "$STUB_LOG" git-signing.signingKey=
  assert_contains "$t/err" "won't be signed"
}

test_key_missing_file() {
  # shellcheck disable=SC2088 # a literal ~, as git config stores it
  key_case ssh "~/.ssh/nope.pub"
  assert_line "$STUB_LOG" git-signing.signingKey=
  assert_contains "$t/err" "won't be signed"
}

# --- runner ---
passed=0 failed=0
for name in $(declare -F | awk '$3 ~ /^test_/ { print $3 }'); do
  if (setup && "$name"); then echo "PASS $name"; passed=$((passed + 1))
  else echo "FAIL $name"; failed=$((failed + 1)); fi
done
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
