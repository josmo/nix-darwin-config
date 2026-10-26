#!/usr/bin/env bash
# Checks a sandbox machine's security claims from inside it. Run with: sandbox --verify
set -u
fail=0

# check pass|fail <description> <command...>: "pass" means the command must succeed,
# "fail" means it must be blocked or fail.
check() {
  local want=$1 desc=$2 got
  shift 2
  if "$@" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$want" ]; then echo "ok   $desc"; else echo "FAIL $desc"; fail=1; fi
}

check pass "allowlisted host is reachable" curl -sf -m 10 https://registry.npmjs.org/
check fail "unlisted host is blocked" curl -sf -m 10 https://example.com
check fail "host loopback blocked (gateway, :11434)" curl -sf -m 4 http://100.96.0.1:11434/api/version
check fail "host loopback blocked (gateway, IDE :63342)" curl -s -m 4 -o /dev/null http://100.96.0.1:63342/
check pass "host Ollama reachable via relay" curl -sf -m 4 "$OLLAMA_HOST/api/version"
check fail "no real secrets in env" sh -c 'env | grep -qE "sk-ant-|AIza"'
check fail "host git dir is read-only" touch /src.git/sandbox-verify
check pass "nix flakes evaluate" nix eval --expr '1 + 1'
check pass "nix fetches from the binary cache" nix run nixpkgs#hello
check pass "docker runs containers" docker run --rm hello-world
exit $fail
