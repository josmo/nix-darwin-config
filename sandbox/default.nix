# Coding-agent sandboxes with smolbento (`bento`): one smolvm microVM per repo and agent.
# Usage: `sandbox [agent] [-- agent args]`; see README.md.
{ pkgs, ... }:
let
  # A link to the script in this directory's store copy, so it finds sandbox.md beside it, as it
  # does from a clone.
  sandbox = pkgs.runCommand "sandbox" { } ''
    mkdir -p $out/bin
    ln -s ${./.}/sandbox $out/bin/sandbox
  '';
in
{
  environment.systemPackages = [ sandbox ];

  # smolbento downloads the smolvm release it's tested with on first use (into ~/.smolbento).
  homebrew.taps = [ "pelotech/tap" "docker/tap" ];
  homebrew.brews = [ "pelotech/tap/smolbento" ];
  # Docker Sandboxes, alongside smolbento.
  homebrew.casks = [ "docker/tap/sbx" ];
}
