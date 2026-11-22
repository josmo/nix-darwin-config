#!/usr/bin/env bash
# Tests for ../sandbox, with a stub `bento` that records its arguments, and for the agent-config
# kit's startup step.
# Run: bash sandbox/tests/run.sh   (no VM, network or Nix needed)
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd -P)
root=$(dirname "$here")  # the sandbox/ folder, physical path (realpath gives the same)
script=$root/sandbox
# The env file and agent-config kit live in dotfiles; read before setup changes HOME.
dot=${DOTFILES:?set DOTFILES to your dotfiles checkout}
ORIG_PATH=$PATH

# A fresh HOME, XDG dirs, git config and git repo (the cwd), with the stub bento first on PATH.
setup() {
  t=$(cd "$(mktemp -d)" && pwd -P)
  export HOME=$t/home XDG_CONFIG_HOME=$t/config XDG_DATA_HOME=$t/data
  export GIT_CONFIG_GLOBAL=$t/gitconfig GIT_CONFIG_NOSYSTEM=1 STUB_LOG=$t/bento.log
  mkdir -p "$HOME" "$t/bin" "$t/repo"
  : > "$GIT_CONFIG_GLOBAL"
  cat > "$t/bin/bento" <<'EOF'
#!/usr/bin/env bash
# env: log one argument per line.
case $1 in
  env) printf '%s\n' "$@" > "$STUB_LOG" ;;
esac
EOF
  chmod +x "$t/bin/bento"
  export PATH=$t/bin:$ORIG_PATH
  touch "$HOME/.sbxenv.yaml"
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

# --- bento's default env files; runs without Nix ---

test_via_symlink() {
  ln -s "$script" "$t/bin/sandbox"
  SANDBOX_CMD=$t/bin/sandbox run_sandbox claude || fail "exit $?: $(cat "$t/err")"
  assert_contains "$stage/AGENTS.md" "$(head -1 "$root/sandbox.md")"
}

test_env_run_defaults() {
  run_sandbox claude || fail "exit $?: $(cat "$t/err")"
  assert_eq "$(head -2 "$STUB_LOG")" "$(printf 'env\nrun')"
  # No env file paths: the args start right after `env run`.
  assert_eq "$(sed -n 3p "$STUB_LOG")" --env-arg
  assert_line "$STUB_LOG" agent=claude
  assert_line "$STUB_LOG" "stage=$stage"
  assert_not_contains "$STUB_LOG" '^(workspace|signingKey|agentKit)=|^--$'
}

test_default_agent() {
  run_sandbox || fail "exit $?: $(cat "$t/err")"
  assert_line "$STUB_LOG" agent=claude
}

test_antigravity_agent_kit() {
  run_sandbox antigravity || fail "exit $?: $(cat "$t/err")"
  assert_line "$STUB_LOG" agent=antigravity
  assert_line "$STUB_LOG" agentKit=docker.io/sbx/antigravity:latest
}

test_missing_home_env() {
  rm "$HOME/.sbxenv.yaml"
  if run_sandbox claude; then fail "ran without ~/.sbxenv.yaml"; fi
  # shellcheck disable=SC2088 # the literal ~ the message shows
  assert_contains "$t/err" "~/.sbxenv.yaml"
  [ ! -e "$STUB_LOG" ] || fail "bento ran"
  # A project file alone isn't: it'd run without your kits, signing or staged config.
  touch "$t/repo/sbxenv.yaml"
  if run_sandbox claude; then fail "ran with only ./sbxenv.yaml"; fi
  [ ! -e "$STUB_LOG" ] || fail "bento ran"
}

test_agent_args() {
  run_sandbox claude -- -c --x || fail "exit $?: $(cat "$t/err")"
  assert_eq "$(tail -3 "$STUB_LOG")" "$(printf -- '--\n-c\n--x')"
}

test_agent_args_without_dashes() {
  run_sandbox claude -c || fail "exit $?: $(cat "$t/err")"
  assert_eq "$(tail -2 "$STUB_LOG")" "$(printf -- '--\n-c')"
}

test_dashes_without_agent() {
  run_sandbox -- -c || fail "exit $?: $(cat "$t/err")"
  assert_line "$STUB_LOG" agent=claude
  assert_eq "$(tail -2 "$STUB_LOG")" "$(printf -- '--\n-c')"
}

test_bad_agent_names() {
  for a in ../sbxenv docker.io/x .hidden 'a b'; do
    rm -f "$STUB_LOG"
    if run_sandbox "$a"; then fail "accepted agent '$a'"; fi
    assert_contains "$t/err" "isn't an agent name"
    [ ! -e "$STUB_LOG" ] || fail "bento ran for agent '$a'"
  done
}

test_extra_env_args() {
  run_sandbox --env-arg region=eu --env-arg 'x=a b' opencode -c || fail "exit $?: $(cat "$t/err")"
  assert_line "$STUB_LOG" agent=opencode
  assert_line "$STUB_LOG" region=eu
  assert_line "$STUB_LOG" 'x=a b'
  assert_eq "$(grep -c -x -- --env-arg "$STUB_LOG")" 4
  assert_eq "$(tail -2 "$STUB_LOG")" "$(printf -- '--\n-c')"
}

test_extra_env_args_default_agent() {
  run_sandbox --env-arg region=eu || fail "exit $?: $(cat "$t/err")"
  assert_line "$STUB_LOG" agent=claude
  assert_line "$STUB_LOG" region=eu
}

test_env_arg_needs_value() {
  if run_sandbox --env-arg; then fail "accepted --env-arg without a value"; fi
  assert_contains "$t/err" "--env-arg needs NAME=VALUE"
  [ ! -e "$STUB_LOG" ] || fail "bento ran"
}

test_paths_with_spaces() {
  export XDG_DATA_HOME="$t/my data"
  mkdir -p "$t/my repo"
  git -C "$t/my repo" init -q
  (cd "$t/my repo" && "$script" claude) > "$t/out" 2> "$t/err" || fail "exit $?: $(cat "$t/err")"
  assert_line "$STUB_LOG" "stage=$t/my data/sandbox/agent-config"
}

test_shared_file_declares_kits() {
  [ -f "$dot/.sbxenv.yaml" ] || fail "no $dot/.sbxenv.yaml"
  f=$t/sbxenv.yaml  # without comments
  grep -v '^[[:space:]]*#' "$dot/.sbxenv.yaml" > "$f"
  # shellcheck disable=SC2016 # a literal ${{ }} reference, as in the file
  for s in 'agent: ${{ env.args.agent }}' 'path: ${{ env.projectDir }}' 'clone: true' \
    'readOnly: true' 'agentKit:' '- ${{ env.args.agentKit }}' \
    'ghcr.io/pelotech/smolbento/kits/nix:0.2.0' 'source: git-signing' \
    'source: .config/sandbox/kits/agent-config' \
    'OLLAMA_HOST:' 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:'; do
    assert_contains "$f" "$s"
  done
  assert_not_contains "$f" 'lifecycle|command:|signingKey'
  # Kit builds can't follow symlinks, so link-dotfiles.sh copies the kit.
  assert_line "$dot/.dotfiles-copy" '.config/sandbox/kits/*'
  for p in sbxenv.yaml agent-config agents nix-tools; do
    [ ! -e "$root/$p" ] || fail "$root/$p still present (moved to dotfiles or retired)"
  done
  # git-signing is smolbento's built-in kit (0.29+); a local folder would shadow it.
  [ ! -e "$root/git-signing" ] || fail "local git-signing kit still present"
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

test_opencode_agents_and_commands() {
  o=$HOME/.config/opencode
  mkdir -p "$o/agents" "$o/commands" "$HOME/.claude/commands"
  printf -- '---\nname: x\ntools: Read, Write\nmodel: sonnet\ncolor: pink\n---\nmodel: stays in the body\n' > "$o/agents/x.md"
  echo c > "$o/commands/c.md"
  echo k > "$HOME/.claude/commands/k.md"
  run_sandbox claude || fail "exit $?: $(cat "$t/err")"
  assert_eq "$(cat "$stage/opencode/agents/x.md")" "$(printf -- '---\nname: x\n---\nmodel: stays in the body')"
  [ -e "$stage/opencode/commands/c.md" ] || fail "opencode command not staged"
  [ -e "$stage/claude/commands/k.md" ] || fail "claude command not staged"
}

test_shipped_notes_generic() {
  [ -s "$root/sandbox.md" ] || fail "no shipped sandbox.md"
  assert_not_contains "$root/sandbox.md" 'aws-sso|IntelliJ'
}

# --- The agent-config kit's startup step, run on the host with a fake HOME ---

# run_kit: run the kit's startup command with HOME=$t/home and AGENT_CONFIG=$stage.
run_kit() {
  awk '/- command: \|/ { on = 1; next } on && NF && !/^            / { exit } on { sub(/^ {12}/, ""); print }' \
    "$dot/.config/sandbox/kits/agent-config/agent-config.yaml" > "$t/kit.sh"
  [ -s "$t/kit.sh" ] || fail "no startup command in agent-config.yaml"
  AGENT_CONFIG=${1-$stage} sh "$t/kit.sh" || fail "kit step exit $?"
}
# kit_stage TEXT: a staging dir whose AGENTS.md holds TEXT.
kit_stage() { mkdir -p "$stage"; printf '%s\n' "$1" > "$stage/AGENTS.md"; }
B='<!-- sandbox:instructions start -->' E='<!-- sandbox:instructions end -->'

test_kit_keeps_agent_file() {
  kit_stage "# My rules"
  mkdir -p "$HOME/.claude"
  printf '## Claude Code\nguide\n\n## Kits\n- **nix** — See nix.md.\n' > "$HOME/.claude/CLAUDE.md"
  run_kit
  assert_eq "$(cat "$HOME/.claude/CLAUDE.md")" "$(printf '## Claude Code\nguide\n\n## Kits\n- **nix** — See nix.md.\n\n%s\n# My rules\n%s' "$B" "$E")"
}

test_kit_replaces_its_block() {
  kit_stage "old rules"
  mkdir -p "$HOME/.claude"; printf 'guide\n' > "$HOME/.claude/CLAUDE.md"
  run_kit; kit_stage "new rules"; run_kit; run_kit
  assert_eq "$(cat "$HOME/.claude/CLAUDE.md")" "$(printf 'guide\n\n%s\nnew rules\n%s' "$B" "$E")"
}

test_kit_replaces_old_link() {
  kit_stage "rules"
  mkdir -p "$HOME/.claude"; ln -s "$stage/AGENTS.md" "$HOME/.claude/CLAUDE.md"
  run_kit
  [ ! -L "$HOME/.claude/CLAUDE.md" ] || fail "still a link"
  assert_eq "$(cat "$HOME/.claude/CLAUDE.md")" "$(printf '%s\nrules\n%s' "$B" "$E")"
  assert_eq "$(cat "$stage/AGENTS.md")" "rules"
}

test_kit_every_agent_file() {
  kit_stage "rules"
  run_kit
  for f in .claude/CLAUDE.md .config/opencode/AGENTS.md .codex/AGENTS.md .gemini/GEMINI.md \
    .copilot/copilot-instructions.md; do
    assert_eq "$(cat "$HOME/$f")" "$(printf '%s\nrules\n%s' "$B" "$E")"
  done
}

test_kit_links_agents_and_commands() {
  kit_stage "rules"; mkdir -p "$stage/claude/agents" "$stage/opencode/commands"
  run_kit
  assert_eq "$(readlink "$HOME/.claude/agents")" "$stage/claude/agents"
  assert_eq "$(readlink "$HOME/.config/opencode/commands")" "$stage/opencode/commands"
  [ ! -e "$HOME/.claude/commands" ] || fail "linked a missing dir"
}

test_kit_links_home_agents_file_for_antigravity() {
  kit_stage "rules"; printf 'guide\n' > "$HOME/AGENTS.md"
  run_kit
  assert_eq "$(readlink "$HOME/.gemini/AGENTS.md")" "$HOME/AGENTS.md"
}

test_kit_no_home_agents_file() {
  kit_stage "rules"
  run_kit
  [ ! -e "$HOME/.gemini/AGENTS.md" ] && [ ! -L "$HOME/.gemini/AGENTS.md" ] || fail "linked a missing file"
}

test_kit_without_config() {
  run_kit ""
  [ -z "$(find "$HOME" -mindepth 1 ! -name .sbxenv.yaml)" ] || fail "wrote $(ls -A "$HOME")"
}

# --- runner ---
passed=0 failed=0
for name in $(declare -F | awk '$3 ~ /^test_/ { print $3 }'); do
  if (setup && "$name"); then echo "PASS $name"; passed=$((passed + 1))
  else echo "FAIL $name"; failed=$((failed + 1)); fi
done
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
